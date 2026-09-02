/**
 * normalize-postgrest-error.ts
 *
 * Low-level PostgREST/Supabase error normalization for the RLS diagnostics
 * system. This module is intentionally separate from the app-level
 * `src/lib/supabase/errors.ts` normalizer — it preserves raw diagnostic
 * fields needed for the test matrix (HTTP status, PostgREST code, PG code)
 * rather than translating everything to a user-friendly message.
 *
 * No PII is extracted from error payloads. Sensitive column values are never
 * surfaced here.
 */

import type { RlsErrorDetail, RlsProbeStatus } from './rls-test-types';

// ---------------------------------------------------------------------------
// PostgREST error shape
// See: https://postgrest.org/en/stable/references/errors.html
// ---------------------------------------------------------------------------

interface PostgrestErrorPayload {
  code?: string;       // PostgREST error code, e.g. "PGRST301"
  details?: string;
  hint?: string;
  message?: string;
}

// Supabase JS wraps PostgREST errors in this shape when calling .from()
interface SupabasePostgrestError {
  code?: string;          // pg error code, e.g. "42501"
  message?: string;
  details?: string;
  hint?: string;
  status?: number;        // HTTP status (present on some versions)
}

// ---------------------------------------------------------------------------
// Well-known PostgreSQL error codes
// ---------------------------------------------------------------------------

const PG_CODES: Record<string, string> = {
  '42501': 'insufficient_privilege',
  '42P01': 'undefined_table',
  '42703': 'undefined_column',
  '42883': 'undefined_function',
  '28000': 'invalid_authorization_specification',
  '28P01': 'invalid_password',
  'P0001': 'raise_exception',
  'P0002': 'no_data_found',
  '23505': 'unique_violation',
  '22004': 'null_value_not_allowed',
};

// PostgREST codes relevant to RLS diagnostics
const POSTGREST_CODES: Record<string, string> = {
  'PGRST100': 'parsing_error',
  'PGRST106': 'schema_not_exposed',      // Only the following schemas are exposed: public, ...
  'PGRST200': 'ambiguous_or_missing_relation',
  'PGRST204': 'could_not_find_column',
  'PGRST300': 'ambiguous_relationship',
  'PGRST301': 'rls_or_policy_denied',
  'PGRST302': 'invalid_filter',
  'PGRST116': 'too_many_rows',
};

// ---------------------------------------------------------------------------
// Status classification from HTTP status + codes
// ---------------------------------------------------------------------------

export function classifyStatus(
  httpStatus: number | undefined,
  pgCode: string | undefined,
  postgrestCode: string | undefined,
): RlsProbeStatus {
  // Auth-level failures before PostgREST
  if (httpStatus === 401) return 'NO_PERMISSION';

  // Schema intentionally not served through PostgREST API (PGRST106)
  // e.g. "Only the following schemas are exposed: public, graphql_public"
  if (postgrestCode === 'PGRST106') return 'NOT_EXPOSED';

  // Missing relation/function (PGRST200 or pg 42P01/42883)
  if (
    postgrestCode === 'PGRST200' ||
    pgCode === '42P01' ||
    pgCode === '42883'
  ) {
    return 'NOT_AVAILABLE';
  }

  // PostgreSQL role lacks SELECT privilege on the table.
  // 42501 on a SELECT always means "no table-level privilege" — NOT an RLS policy denial.
  // (RLS silently filters rows on SELECT when the role does have SELECT privilege.)
  if (pgCode === '42501' || pgCode === '28000') {
    return 'NO_PERMISSION';
  }

  // Intentional RLS denial via PGRST301 or HTTP 403 without a 42501 pg code
  // (e.g., PostgREST-level policy or SECURITY INVOKER RLS rejection)
  if (postgrestCode === 'PGRST301' || httpStatus === 403) {
    return 'DENIED_BY_RLS';
  }

  // Custom server-side exceptions from SECURITY DEFINER RPCs
  // (P0001 = RAISE EXCEPTION, used for intentional application-level denial)
  if (pgCode === 'P0001' || pgCode === 'P0002') return 'DENIED_BY_RLS';

  // Invalid input syntax errors (e.g. 22P02 for a malformed UUID) — not a policy decision
  if (pgCode === '22P02' || pgCode === '22003' || pgCode === '22007') return 'ERROR';

  // Generic HTTP failures
  if (httpStatus !== undefined && httpStatus >= 400) return 'ERROR';

  return 'ERROR';
}

// ---------------------------------------------------------------------------
// Human-readable message normalization (no PII, no raw secrets)
// ---------------------------------------------------------------------------

function humanMessage(
  pgCode: string | undefined,
  postgrestCode: string | undefined,
  rawMessage: string | undefined,
): string {
  if (pgCode === '42501') {
    return 'The authenticated PostgreSQL role does not have SELECT privilege on this table. ' +
      'Direct browser access is not granted; RPC-mediated access may still be available.';
  }
  if (pgCode === '28000') return 'Authentication/authorization specification rejected.';
  if (pgCode === 'P0001' || pgCode === 'P0002') {
    // Server-raised exception; include message but trim potential PII paths
    const safe = (rawMessage ?? '').replace(/\/[^\s]+/g, '[path]').substring(0, 200);
    return safe || 'Server raised an exception (no data found or custom error).';
  }
  if (pgCode === '42P01') return 'Relation does not exist or is not accessible.';
  if (pgCode === '42883') return 'Function does not exist or is not accessible.';
  if (pgCode === '22P02') return 'Invalid input syntax — the query contained a malformed value (e.g. bad UUID format).';
  if (postgrestCode === 'PGRST106') {
    return 'Schema is not exposed through the PostgREST API. ' +
      'This is the expected secure configuration — the audit schema is intentionally unavailable to browser clients.';
  }
  if (postgrestCode === 'PGRST200') return 'Relation or schema is not exposed through the API.';
  if (postgrestCode === 'PGRST301') return 'Access denied by row-level security or PostgREST API policy.';

  const pgDesc = pgCode ? (PG_CODES[pgCode] ?? pgCode) : '';
  const pgrDesc = postgrestCode ? (POSTGREST_CODES[postgrestCode] ?? postgrestCode) : '';
  const codeLabel = [pgDesc, pgrDesc].filter(Boolean).join(' / ');

  return codeLabel
    ? `Database error: ${codeLabel}.`
    : 'An unexpected error occurred accessing this resource.';
}

// ---------------------------------------------------------------------------
// Main normalizer
// ---------------------------------------------------------------------------

/**
 * Normalize any error thrown by `supabase.from().select()` or `supabase.rpc()`
 * into a structured `RlsErrorDetail` for the diagnostics matrix.
 *
 * This function is intentionally non-throwing; it always returns a valid object.
 */
export function normalizePostgrestError(
  error: unknown,
  httpStatusHint?: number,
): RlsErrorDetail {
  if (error === null || error === undefined) {
    return { normalizedMessage: 'No error object provided.' };
  }

  // Supabase JS PostgREST errors are plain objects with { code, message, details, hint }
  if (typeof error === 'object' && !Array.isArray(error)) {
    const e = error as SupabasePostgrestError & PostgrestErrorPayload;

    // Determine which code field is a PG code vs PostgREST code.
    // PostgREST codes start with "PGRST"; PG codes are typically 5-char alphanumeric.
    const codeStr: string | undefined = typeof e.code === 'string' ? e.code : undefined;
    const isPgrestCode = codeStr?.startsWith('PGRST') ?? false;

    const pgCode: string | undefined = !isPgrestCode ? codeStr : undefined;
    const postgrestCode: string | undefined = isPgrestCode ? codeStr : undefined;

    const httpStatus: number | undefined =
      typeof e.status === 'number' ? e.status : httpStatusHint;

    const rawMessage: string | undefined =
      typeof e.message === 'string' ? e.message : undefined;

    const hint: string | undefined =
      typeof e.hint === 'string' ? e.hint : undefined;

    return {
      httpStatus,
      postgrestCode,
      pgCode,
      normalizedMessage: humanMessage(pgCode, postgrestCode, rawMessage),
      rawMessage,
      hint,
    };
  }

  if (error instanceof Error) {
    return {
      httpStatus: httpStatusHint,
      normalizedMessage: `JavaScript error: ${error.name}.`,
      rawMessage: error.message.substring(0, 200),
    };
  }

  return {
    httpStatus: httpStatusHint,
    normalizedMessage: 'Unknown error type.',
    rawMessage: String(error).substring(0, 200),
  };
}

/**
 * Derive a `RlsProbeStatus` from the normalized error detail.
 */
export function statusFromErrorDetail(detail: RlsErrorDetail): RlsProbeStatus {
  return classifyStatus(detail.httpStatus, detail.pgCode, detail.postgrestCode);
}

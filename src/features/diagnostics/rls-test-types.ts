/**
 * rls-test-types.ts
 *
 * Type definitions for the Phase 3 RLS diagnostics system.
 * These types describe probe inputs, intermediate states, and final results
 * reported by the /dev/rls-tests diagnostics page.
 *
 * All probes are read-only. No mutations are performed.
 */

// ---------------------------------------------------------------------------
// Status codes
// ---------------------------------------------------------------------------

/**
 * The five canonical probe outcomes, plus an internal ALLOWED_EMPTY variant
 * that distinguishes a successful 0-row response from a true denial.
 *
 * Display rules:
 *  - ALLOWED and ALLOWED_EMPTY both render as "ALLOWED" in the summary matrix.
 *  - The row count distinguishes them in the detail view.
 */
export type RlsProbeStatus =
  | 'ALLOWED'           // SELECT succeeded, ≥1 rows returned
  | 'ALLOWED_EMPTY'     // SELECT succeeded, 0 rows returned (RLS may be filtering silently)
  | 'ACCESS_DENIED'     // RPC/application authorization boundary explicitly rejected the request
  | 'DENIED_BY_RLS'     // Intentional access denial by an RLS policy or server-side exception (P0001)
  | 'NO_PERMISSION'     // PostgreSQL role lacks SELECT privilege on the table (42501) or session not authenticated (401)
  | 'NOT_AVAILABLE'     // Relation/schema/function not found (PGRST200, 42P01, 42883)
  | 'NOT_EXPOSED'       // Schema intentionally not served through PostgREST API (PGRST106)
  | 'ERROR'             // Unexpected technical failure (22P02, network error, JS exception)
  | 'PENDING'           // Not yet run
  | 'RUNNING';          // Probe is in-flight

// ---------------------------------------------------------------------------
// Expectation annotation
// ---------------------------------------------------------------------------

/**
 * What we expect given the current permission model (7 effective permissions,
 * Org Admin role, single org).  The diagnostics page flags deviations.
 */
export type RlsExpectation =
  | 'ALLOWED'
  | 'ALLOWED_OR_EMPTY'    // RLS may filter silently; either is valid
  | 'DENIED'              // Should be denied regardless of role
  | 'UNKNOWN';            // Insufficient information to predict

// ---------------------------------------------------------------------------
// Normalized error detail
// ---------------------------------------------------------------------------

/**
 * Structured error metadata extracted from a PostgREST or Supabase JS error.
 * All fields are optional because some may not be present for every error type.
 */
export interface RlsErrorDetail {
  /** HTTP status code (e.g. 400, 401, 403). */
  httpStatus?: number;
  /** PostgREST error code (e.g. "PGRST301", "PGRST200"). */
  postgrestCode?: string;
  /** PostgreSQL error code (e.g. "42501", "P0002", "42P01"). */
  pgCode?: string;
  /** Normalized, human-readable message (no PII). */
  normalizedMessage: string;
  /** Raw technical message from the server (may contain schema details). */
  rawMessage?: string;
  /** Raw "hint" from PostgREST, if present. */
  hint?: string;
}

// ---------------------------------------------------------------------------
// Probe definition (input)
// ---------------------------------------------------------------------------

/** Probe groups matching the test matrix sections A–G. */
export type RlsProbeGroup =
  | 'A_IDENTITY'
  | 'B_AUTHORIZATION'
  | 'C_GOVERNANCE'
  | 'D_MEMBER_FAMILY'
  | 'E_SENSITIVE'
  | 'F_BOUNDARY'
  | 'G_CATALOG';

/** The underlying operation type. */
export type RlsProbeOperation =
  | 'SELECT'
  | 'SELECT_FILTERED'   // SELECT with a where clause (e.g. eq profile_id)
  | 'SELECT_LIMIT1'     // SELECT limited to 1 row
  | 'RPC'               // Function call via supabase.rpc()
  | 'RPC_INVALID';      // RPC call with deliberately invalid arguments (boundary test)

export interface RlsProbeDefinition {
  /** Unique probe identifier (e.g. "A1", "E2"). */
  id: string;
  /** Group this probe belongs to. */
  group: RlsProbeGroup;
  /** Human-readable name shown in the matrix. */
  label: string;
  /** Table, view, or RPC being probed. */
  target: string;
  /** Schema of the target ("public" | "audit"). */
  schema: 'public' | 'audit';
  /** Type of operation. */
  operation: RlsProbeOperation;
  /** Expected outcome given current role/permission context. */
  expected: RlsExpectation;
  /** Why we expect what we expect. */
  expectedRationale: string;
  /**
   * Whether a successful result for this probe would be a security concern.
   * Used to flag UNEXPECTED_ACCESS prominently.
   */
  sensitiveOnSuccess: boolean;
}

// ---------------------------------------------------------------------------
// Probe result (output)
// ---------------------------------------------------------------------------

export interface RlsProbeResult {
  /** Matches the probe definition id. */
  probeId: string;
  /** Final status after execution. */
  status: RlsProbeStatus;
  /**
   * Display status: collapses ALLOWED_EMPTY → ALLOWED for the matrix header,
   * but retains distinction in detail view.
   */
  displayStatus: 'ALLOWED' | 'ACCESS_DENIED' | 'DENIED_BY_RLS' | 'NO_PERMISSION' | 'NOT_AVAILABLE' | 'NOT_EXPOSED' | 'ERROR' | 'PENDING' | 'RUNNING';
  /** Number of rows returned (undefined if probe did not succeed). */
  rowCount?: number;
  /**
   * Whether the result is flagged as unexpected:
   * - "unexpected_access" when sensitiveOnSuccess=true and status is ALLOWED/ALLOWED_EMPTY
   * - "unexpected_denial" when expected is ALLOWED and probe was denied
   * - undefined otherwise
   */
  anomaly?: 'unexpected_access' | 'unexpected_denial';
  /**
   * For ALLOWED results: column names that were returned.
   * Used to verify whether sensitive columns (e.g. token_hash) were included.
   */
  returnedColumns?: string[];
  /**
   * For QR/notes probes: explicitly flag if a sensitive column was present
   * in the response even if we don't display its value.
   */
  sensitiveColumnPresent?: boolean;
  /** Error detail, populated when status is not ALLOWED/ALLOWED_EMPTY. */
  error?: RlsErrorDetail;
  /**
   * Free-form diagnostic note appended after probe execution.
   * e.g. "RLS filtering cannot be distinguished from 0 real rows."
   */
  diagnosticNote?: string;
  /** Wall-clock milliseconds the probe took. */
  durationMs?: number;
  /** ISO timestamp when this result was recorded. */
  recordedAt: string;
}

// ---------------------------------------------------------------------------
// Run state (aggregate)
// ---------------------------------------------------------------------------

export interface RlsRunState {
  /** Probe definitions, keyed by id. */
  definitions: Record<string, RlsProbeDefinition>;
  /** Ordered list of probe ids. */
  order: string[];
  /** Results, keyed by probe id. */
  results: Record<string, RlsProbeResult>;
  /** Whether all probes have completed. */
  isComplete: boolean;
  /** ISO timestamp of run start, if running. */
  startedAt?: string;
  /** ISO timestamp of run completion. */
  completedAt?: string;
}

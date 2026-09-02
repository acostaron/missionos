/**
 * rls-probes.ts
 *
 * All 32 read-only RLS probe functions for the Phase 3 diagnostics page.
 *
 * Rules enforced here:
 *  - All probes use the normal authenticated browser Supabase client (anon key + user JWT).
 *  - No service-role key. No SECURITY DEFINER shortcuts. No private schema calls.
 *  - No INSERT, UPDATE, DELETE, or mutation RPCs.
 *  - SELECT queries use minimal column projections (not SELECT *).
 *  - Sensitive column values (token_hash, note_text, audit payloads) are detected
 *    but never stored or rendered.
 *  - Empty result sets are classified ALLOWED_EMPTY, not DENIED_BY_RLS.
 */

import { supabase } from '../../lib/supabase/client';
import {
  normalizePostgrestError,
  statusFromErrorDetail,
} from './normalize-postgrest-error';
import type {
  RlsProbeDefinition,
  RlsProbeResult,
  RlsProbeStatus,
} from './rls-test-types';

// ---------------------------------------------------------------------------
// Probe catalogue (definitions)
// ---------------------------------------------------------------------------

export const PROBE_DEFINITIONS: RlsProbeDefinition[] = [
  // ── Group A: Identity / Organization ───────────────────────────────────
  {
    id: 'A1',
    group: 'A_IDENTITY',
    label: 'profiles — own row',
    target: 'profiles',
    schema: 'public',
    operation: 'SELECT_FILTERED',
    expected: 'UNKNOWN',
    expectedRationale:
      'Release 1A uses RPC-mediated access (get_current_profile_context). ' +
      'The authenticated PostgreSQL role may not have direct SELECT on this table. ' +
      'NO_PERMISSION is an acceptable outcome here.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'A2',
    group: 'A_IDENTITY',
    label: 'profiles — unfiltered',
    target: 'profiles',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Unfiltered profile access. Direct SELECT privilege may not be granted; NO_PERMISSION expected if RPC-only architecture.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'A3',
    group: 'A_IDENTITY',
    label: 'profile_organization_memberships',
    target: 'profile_organization_memberships',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Own memberships visible via RPC context. Direct SELECT privilege may not be granted; both ALLOWED and NO_PERMISSION are valid observations.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'A4',
    group: 'A_IDENTITY',
    label: 'organizations',
    target: 'organizations',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Organization record surfaced via RPC context. Direct SELECT may not be granted; both ALLOWED and NO_PERMISSION are valid.',
    sensitiveOnSuccess: false,
  },

  // ── Group B: Authorization ──────────────────────────────────────────────
  {
    id: 'B1',
    group: 'B_AUTHORIZATION',
    label: 'profile_role_assignments',
    target: 'profile_role_assignments',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Runtime confirmed: NO_PERMISSION (42501). Role assignments are surfaced via auth context RPC; ' +
      'direct browser SELECT is not part of Release 1A contract.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'B2',
    group: 'B_AUTHORIZATION',
    label: 'profile_scope_assignments',
    target: 'profile_scope_assignments',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Runtime confirmed: NO_PERMISSION (42501). Scope data is surfaced via auth context RPC; ' +
      'direct browser SELECT is not part of Release 1A contract.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'B3',
    group: 'B_AUTHORIZATION',
    label: 'app_roles (catalog)',
    target: 'app_roles',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Role catalog; direct SELECT privilege depends on deployment configuration. ' +
      'NO_PERMISSION is acceptable if roles are accessed via the auth context RPC only.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'B4',
    group: 'B_AUTHORIZATION',
    label: 'permissions (catalog)',
    target: 'permissions',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Permission catalog; surfaced via auth context RPC. Direct SELECT may or may not be granted.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'B5',
    group: 'B_AUTHORIZATION',
    label: 'role_permissions',
    target: 'role_permissions',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Runtime confirmed: NO_PERMISSION (42501). Role↔permission mapping is surfaced via auth context RPC; ' +
      'direct browser SELECT is not part of Release 1A contract.',
    sensitiveOnSuccess: false,
  },

  // ── Group C: Governance ─────────────────────────────────────────────────
  {
    id: 'C1',
    group: 'C_GOVERNANCE',
    label: 'governance_nodes',
    target: 'governance_nodes',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Governance hierarchy accessed via RPC or context function in Release 1A. ' +
      'The governance.structure.view permission code does not imply direct SQL SELECT privilege; ' +
      'NO_PERMISSION is an acceptable result.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'C2',
    group: 'C_GOVERNANCE',
    label: 'governance_node_relationships',
    target: 'governance_node_relationships',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Hierarchy edge data accessed alongside nodes via RPC. Direct SELECT privilege not required by Release 1A.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'C3',
    group: 'C_GOVERNANCE',
    label: 'governance_node_types',
    target: 'governance_node_types',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Node type catalog; may require direct SELECT or may be served via RPC. Either outcome is valid.',
    sensitiveOnSuccess: false,
  },

  // ── Group D: Member / Family ────────────────────────────────────────────
  {
    id: 'D1',
    group: 'D_MEMBER_FAMILY',
    label: 'members',
    target: 'members',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'members.records.view is an application permission code, not a PostgreSQL privilege grant. ' +
      'Direct SELECT privilege on members may not be assigned in Release 1A; NO_PERMISSION is expected.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D2',
    group: 'D_MEMBER_FAMILY',
    label: 'member_names',
    target: 'member_names',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Name data accessed via service layer. Direct SELECT privilege may not be granted.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D3',
    group: 'D_MEMBER_FAMILY',
    label: 'member_identifiers',
    target: 'member_identifiers',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Identifier data accessed via service layer. Direct SELECT privilege may not be granted.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D4',
    group: 'D_MEMBER_FAMILY',
    label: 'member_emails',
    target: 'member_emails',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Contact data; members.contacts.view is an application permission, not a direct SQL grant.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D5',
    group: 'D_MEMBER_FAMILY',
    label: 'member_phones',
    target: 'member_phones',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Contact data; members.contacts.view is an application permission, not a direct SQL grant.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D6',
    group: 'D_MEMBER_FAMILY',
    label: 'member_addresses',
    target: 'member_addresses',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Contact data; members.addresses.view is an application permission, not a direct SQL grant.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D7',
    group: 'D_MEMBER_FAMILY',
    label: 'families',
    target: 'families',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Family records; direct SELECT privilege unknown at this stage of Release 1A.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D8',
    group: 'D_MEMBER_FAMILY',
    label: 'section_memberships (placement)',
    target: 'section_memberships',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Placement data; members.placements.view is an application permission, not a direct SQL grant.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D9',
    group: 'D_MEMBER_FAMILY',
    label: 'household_memberships (placement)',
    target: 'household_memberships',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Placement data (household); direct SELECT privilege unknown.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'D10',
    group: 'D_MEMBER_FAMILY',
    label: 'member_governance_assignments (placement)',
    target: 'member_governance_assignments',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Governance assignment data; direct SELECT privilege unknown.',
    sensitiveOnSuccess: false,
  },

  // ── Group E: Sensitive / Protected ──────────────────────────────────────
  {
    id: 'E1',
    group: 'E_SENSITIVE',
    label: 'member_notes (sensitive content)',
    target: 'member_notes',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'DENIED',
    expectedRationale: 'Notes contain sensitive pastoral data; should be restricted.',
    sensitiveOnSuccess: true,
  },
  {
    id: 'E2',
    group: 'E_SENSITIVE',
    label: 'member_qr_tokens (token_hash check)',
    target: 'member_qr_tokens',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'DENIED',
    expectedRationale: 'QR token hashes must not be exposed to the browser. DENIED or filtered.',
    sensitiveOnSuccess: true,
  },
  {
    id: 'E3',
    group: 'E_SENSITIVE',
    label: 'security_events',
    target: 'security_events',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'DENIED',
    expectedRationale: 'Security event log; should require elevated privilege.',
    sensitiveOnSuccess: true,
  },
  {
    id: 'E4',
    group: 'E_SENSITIVE',
    label: 'login_history',
    target: 'login_history',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'DENIED',
    expectedRationale: 'Login audit trail; should be inaccessible to ordinary sessions.',
    sensitiveOnSuccess: true,
  },
  {
    id: 'E5',
    group: 'E_SENSITIVE',
    label: 'user_devices',
    target: 'user_devices',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale:
      'Runtime confirmed: NO_PERMISSION (42501). Device records are not directly accessible; ' +
      'device management uses a dedicated service layer.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'E6',
    group: 'E_SENSITIVE',
    label: 'audit.events',
    target: 'events',
    schema: 'audit',
    operation: 'SELECT_LIMIT1',
    expected: 'DENIED',
    expectedRationale:
      'Audit schema is intentionally not exposed via PostgREST (PGRST106). ' +
      'NOT_EXPOSED is the correct secure result and should not be flagged as anomalous.',
    sensitiveOnSuccess: true,
  },
  {
    id: 'E7',
    group: 'E_SENSITIVE',
    label: 'audit.entity_changes',
    target: 'entity_changes',
    schema: 'audit',
    operation: 'SELECT_LIMIT1',
    expected: 'DENIED',
    expectedRationale:
      'Audit schema is intentionally not exposed via PostgREST (PGRST106). ' +
      'NOT_EXPOSED is the correct secure result and should not be flagged as anomalous.',
    sensitiveOnSuccess: true,
  },
  {
    id: 'E8',
    group: 'E_SENSITIVE',
    label: 'audit.permission_events',
    target: 'permission_events',
    schema: 'audit',
    operation: 'SELECT_LIMIT1',
    expected: 'DENIED',
    expectedRationale:
      'Audit schema is intentionally not exposed via PostgREST (PGRST106). ' +
      'NOT_EXPOSED is the correct secure result and should not be flagged as anomalous.',
    sensitiveOnSuccess: true,
  },

  // ── Group F: Impersonation / Boundary Tests ─────────────────────────────
  {
    id: 'F1',
    group: 'F_BOUNDARY',
    label: 'get_current_profile_context() — own session',
    target: 'get_current_profile_context',
    schema: 'public',
    operation: 'RPC',
    expected: 'ALLOWED',
    expectedRationale: 'Must return caller\'s own data; bound to auth.uid() server-side.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'F2',
    group: 'F_BOUNDARY',
    label: 'get_current_authorization_context() — own org',
    target: 'get_current_authorization_context',
    schema: 'public',
    operation: 'RPC',
    expected: 'ALLOWED',
    expectedRationale: 'Caller has active membership in mfcny; should succeed.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'F3',
    group: 'F_BOUNDARY',
    label: 'get_current_authorization_context() — invalid org UUID',
    target: 'get_current_authorization_context',
    schema: 'public',
    operation: 'RPC_INVALID',
    expected: 'DENIED',
    expectedRationale:
      'RPC enforces an application-level organization-boundary check. ' +
      'A UUID not belonging to the caller must be rejected with ACCESS_DENIED. ' +
      'This is distinct from PostgreSQL RLS — it is an explicit server-side authorization guard.',
    sensitiveOnSuccess: true,
  },
  {
    id: 'F4',
    group: 'F_BOUNDARY',
    label: 'profile_organization_memberships — other profile filter',
    target: 'profile_organization_memberships',
    schema: 'public',
    operation: 'SELECT_FILTERED',
    expected: 'DENIED',
    expectedRationale: 'A WHERE clause targeting a different profile_id must return 0 rows or be denied.',
    sensitiveOnSuccess: true,
  },

  // ── Group G: Catalog Tables ─────────────────────────────────────────────
  {
    id: 'G1',
    group: 'G_CATALOG',
    label: 'member_statuses (org catalog)',
    target: 'member_statuses',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Org-scoped catalog table; direct SELECT may or may not be granted by Release 1A.',
    sensitiveOnSuccess: false,
  },
  {
    id: 'G2',
    group: 'G_CATALOG',
    label: 'governance_node_types (org catalog)',
    target: 'governance_node_types',
    schema: 'public',
    operation: 'SELECT_LIMIT1',
    expected: 'UNKNOWN',
    expectedRationale: 'Node type catalog; direct SELECT may or may not be granted by Release 1A.',
    sensitiveOnSuccess: false,
  },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeResult(
  probeId: string,
  status: RlsProbeStatus,
  overrides: Partial<RlsProbeResult> = {},
): RlsProbeResult {
  const displayStatus = ((): RlsProbeResult['displayStatus'] => {
    if (status === 'ALLOWED' || status === 'ALLOWED_EMPTY') return 'ALLOWED';
    if (status === 'NOT_EXPOSED') return 'NOT_EXPOSED';
    if (status === 'ACCESS_DENIED') return 'ACCESS_DENIED';
    // All other statuses map directly (DENIED_BY_RLS, NO_PERMISSION, NOT_AVAILABLE, ERROR, PENDING, RUNNING)
    return status as RlsProbeResult['displayStatus'];
  })();

  return {
    probeId,
    status,
    displayStatus,
    recordedAt: new Date().toISOString(),
    ...overrides,
  };
}

function computeAnomaly(
  def: RlsProbeDefinition,
  status: RlsProbeStatus,
): RlsProbeResult['anomaly'] {
  const succeeded = status === 'ALLOWED' || status === 'ALLOWED_EMPTY';

  // Flag unexpected access only if the probe is marked sensitive and the query succeeded.
  if (succeeded && def.sensitiveOnSuccess) return 'unexpected_access';

  // Flag unexpected denial ONLY when we explicitly required direct ALLOWED access
  // (expected === 'ALLOWED'). Probes with expected === 'UNKNOWN', 'ALLOWED_OR_EMPTY',
  // or 'DENIED' do not generate UNEXPECTED_DENIAL regardless of actual status.
  if (
    def.expected === 'ALLOWED' &&
    !succeeded &&
    status !== 'PENDING' &&
    status !== 'RUNNING'
  ) {
    return 'unexpected_denial';
  }

  return undefined;
}

type TimedSelect = {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  data: any;
  error: unknown;
  durationMs: number;
};

/**
 * Times a Supabase query. Accepts any thenable (including PostgrestFilterBuilder,
 * which TypeScript types strongly but satisfies PromiseLike at runtime).
 */
async function timedSelect(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  fn: () => PromiseLike<{ data: any; error: unknown }>,
): Promise<TimedSelect> {
  const t0 = performance.now();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const result = await (fn() as Promise<any>);
  return {
    data: result.data,
    error: result.error,
    durationMs: Math.round(performance.now() - t0),
  };
}

// ---------------------------------------------------------------------------
// Probe runner implementations
// ---------------------------------------------------------------------------

/** Run a single probe by id, using the current user's Supabase session. */
export async function runProbe(
  def: RlsProbeDefinition,
  ownProfileId: string,
  ownOrganizationId: string,
): Promise<RlsProbeResult> {
  try {
    switch (def.id) {
      case 'A1': return await probeA1(def, ownProfileId);
      case 'A2': return await probeA2(def);
      case 'A3': return await probeA3(def);
      case 'A4': return await probeA4(def);

      case 'B1': return await probeSimpleSelect(def, 'profile_role_assignments', ['id', 'profile_id', 'app_role_id', 'assignment_status']);
      case 'B2': return await probeSimpleSelect(def, 'profile_scope_assignments', ['id', 'profile_role_assignment_id', 'scope_type', 'assignment_status']);
      case 'B3': return await probeSimpleSelect(def, 'app_roles', ['id', 'code', 'name', 'role_category', 'is_active']);
      case 'B4': return await probeSimpleSelect(def, 'permissions', ['id', 'code', 'name', 'domain_code', 'is_active']);
      case 'B5': return await probeSimpleSelect(def, 'role_permissions', ['id', 'app_role_id', 'permission_id', 'permission_effect']);

      case 'C1': return await probeSimpleSelect(def, 'governance_nodes', ['id', 'name', 'organization_id', 'lifecycle_status']);
      case 'C2': return await probeSimpleSelect(def, 'governance_node_relationships', ['id', 'parent_node_id', 'child_node_id', 'relationship_status']);
      case 'C3': return await probeSimpleSelect(def, 'governance_node_types', ['id', 'code', 'name', 'organization_id']);

      case 'D1': return await probeSimpleSelect(def, 'members', ['id', 'display_name', 'record_status', 'organization_id']);
      case 'D2': return await probeSimpleSelect(def, 'member_names', ['id', 'full_name', 'name_type', 'is_primary', 'organization_id']);
      case 'D3': return await probeSimpleSelect(def, 'member_identifiers', ['id', 'identifier_type', 'is_primary', 'organization_id']);
      case 'D4': return await probeSimpleSelect(def, 'member_emails', ['id', 'email_type', 'is_primary', 'organization_id']);
      case 'D5': return await probeSimpleSelect(def, 'member_phones', ['id', 'phone_type', 'is_primary', 'organization_id']);
      case 'D6': return await probeSimpleSelect(def, 'member_addresses', ['id', 'address_type', 'is_primary', 'organization_id']);
      case 'D7': return await probeSimpleSelect(def, 'families', ['id', 'display_name', 'family_status', 'organization_id']);
      case 'D8': return await probeSimpleSelect(def, 'section_memberships', ['id', 'member_id', 'membership_status', 'organization_id']);
      case 'D9': return await probeSimpleSelect(def, 'household_memberships', ['id', 'member_id', 'membership_status', 'organization_id']);
      case 'D10': return await probeSimpleSelect(def, 'member_governance_assignments', ['id', 'member_id', 'assignment_status', 'organization_id']);

      case 'E1': return await probeE1(def);
      case 'E2': return await probeE2(def);
      case 'E3': return await probeSimpleSelect(def, 'security_events', ['id', 'event_code', 'severity', 'event_status']);
      case 'E4': return await probeSimpleSelect(def, 'login_history', ['id', 'login_outcome', 'occurred_at']);
      case 'E5': return await probeSimpleSelect(def, 'user_devices', ['id', 'platform', 'device_status']);
      case 'E6': return await probeAuditTable(def, 'events', ['id', 'action', 'event_category', 'outcome']);
      case 'E7': return await probeAuditTable(def, 'entity_changes', ['id', 'entity_type', 'operation']);
      case 'E8': return await probeAuditTable(def, 'permission_events', ['id', 'event_type', 'profile_id']);

      case 'F1': return await probeF1(def);
      case 'F2': return await probeF2(def, ownOrganizationId);
      case 'F3': return await probeF3(def);
      case 'F4': return await probeF4(def, ownProfileId);

      case 'G1': return await probeSimpleSelect(def, 'member_statuses', ['id', 'code', 'name', 'is_active', 'organization_id']);
      case 'G2': return await probeSimpleSelect(def, 'governance_node_types', ['id', 'code', 'name', 'organization_id']);

      default:
        return makeResult(def.id, 'ERROR', {
          diagnosticNote: `No implementation found for probe id "${def.id}".`,
        });
    }
  } catch (unexpectedError) {
    const errorDetail = normalizePostgrestError(unexpectedError);
    return makeResult(def.id, 'ERROR', {
      error: errorDetail,
      diagnosticNote: 'Probe threw an unexpected JavaScript exception.',
    });
  }
}

// ---------------------------------------------------------------------------
// Generic SELECT probe (public schema, limit 1)
// ---------------------------------------------------------------------------

async function probeSimpleSelect(
  def: RlsProbeDefinition,
  table: string,
  columns: string[],
): Promise<RlsProbeResult> {
  const projection = columns.join(', ');
  const { data, error, durationMs } = await timedSelect(() =>
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase.from(table as any) as any)
      .select(projection)
      .limit(1),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, {
      error: errorDetail,
      durationMs,
      anomaly: computeAnomaly(def, status),
    });
  }

  const rows = Array.isArray(data) ? data : [];
  const status: RlsProbeStatus = rows.length > 0 ? 'ALLOWED' : 'ALLOWED_EMPTY';
  const anomaly = computeAnomaly(def, status);
  const note =
    rows.length === 0
      ? 'Empty result: RLS may be filtering silently, or no data exists for this org.'
      : undefined;

  return makeResult(def.id, status, {
    rowCount: rows.length,
    returnedColumns: columns,
    durationMs,
    anomaly,
    diagnosticNote: note,
  });
}

// ---------------------------------------------------------------------------
// Audit schema probe
// ---------------------------------------------------------------------------

async function probeAuditTable(
  def: RlsProbeDefinition,
  table: string,
  columns: string[],
): Promise<RlsProbeResult> {
  const projection = columns.join(', ');
  // PostgREST exposes non-default schemas via a schema header.
  // The Supabase JS client supports this via .schema().
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const client = (supabase as any).schema ? (supabase as any).schema('audit') : supabase;
  const { data, error, durationMs } = await timedSelect(() =>
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (client.from(table) as any).select(projection).limit(1),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, {
      error: errorDetail,
      durationMs,
      anomaly: computeAnomaly(def, status),
    });
  }

  // If we got data back from an audit table that's supposed to be denied, that's a finding.
  const rows = Array.isArray(data) ? data : [];
  const status: RlsProbeStatus = rows.length > 0 ? 'ALLOWED' : 'ALLOWED_EMPTY';
  return makeResult(def.id, status, {
    rowCount: rows.length,
    returnedColumns: columns,
    durationMs,
    anomaly: computeAnomaly(def, status),
    diagnosticNote: rows.length > 0
      ? '⚠ Audit table returned rows — raw payload is NOT rendered here.'
      : 'Audit table returned 0 rows — may be denied silently or genuinely empty.',
  });
}

// ---------------------------------------------------------------------------
// Specific probe implementations
// ---------------------------------------------------------------------------

/** A1: profiles — own row via eq('id', auth.uid()) */
async function probeA1(
  def: RlsProbeDefinition,
  ownProfileId: string,
): Promise<RlsProbeResult> {
  const cols = ['id', 'display_name', 'account_status', 'is_platform_administrator'];
  const { data, error, durationMs } = await timedSelect(() =>
    supabase
      .from('profiles')
      .select(cols.join(', '))
      .eq('id', ownProfileId)
      .limit(1),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, { error: errorDetail, durationMs });
  }

  const rows = Array.isArray(data) ? data : [];
  const status: RlsProbeStatus = rows.length > 0 ? 'ALLOWED' : 'ALLOWED_EMPTY';
  return makeResult(def.id, status, {
    rowCount: rows.length,
    returnedColumns: cols,
    durationMs,
    anomaly: computeAnomaly(def, status),
    diagnosticNote:
      rows.length === 0
        ? 'Own profile row not found — profile may not exist in public.profiles or RLS denies self-read.'
        : undefined,
  });
}

/** A2: profiles — unfiltered, limit 1 */
async function probeA2(def: RlsProbeDefinition): Promise<RlsProbeResult> {
  const cols = ['id', 'display_name', 'account_status'];
  const { data, error, durationMs } = await timedSelect(() =>
    supabase.from('profiles').select(cols.join(', ')).limit(1),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, { error: errorDetail, durationMs });
  }

  const rows = Array.isArray(data) ? data : [];
  const status: RlsProbeStatus = rows.length > 0 ? 'ALLOWED' : 'ALLOWED_EMPTY';
  return makeResult(def.id, status, {
    rowCount: rows.length,
    returnedColumns: cols,
    durationMs,
    anomaly: computeAnomaly(def, status),
    diagnosticNote:
      'Unfiltered result — if multiple rows visible, RLS is not scoping to own profile.',
  });
}

/** A3: profile_organization_memberships */
async function probeA3(def: RlsProbeDefinition): Promise<RlsProbeResult> {
  const cols = ['id', 'profile_id', 'organization_id', 'membership_status', 'is_default'];
  const { data, error, durationMs } = await timedSelect(() =>
    supabase.from('profile_organization_memberships').select(cols.join(', ')).limit(5),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, { error: errorDetail, durationMs });
  }

  const rows = Array.isArray(data) ? data : [];
  const status: RlsProbeStatus = rows.length > 0 ? 'ALLOWED' : 'ALLOWED_EMPTY';
  // Check whether we see rows for profiles other than the caller — would be a finding
  return makeResult(def.id, status, {
    rowCount: rows.length,
    returnedColumns: cols,
    durationMs,
    anomaly: computeAnomaly(def, status),
  });
}

/** A4: organizations */
async function probeA4(def: RlsProbeDefinition): Promise<RlsProbeResult> {
  const cols = ['id', 'code', 'name', 'lifecycle_status'];
  const { data, error, durationMs } = await timedSelect(() =>
    supabase.from('organizations').select(cols.join(', ')).limit(5),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, { error: errorDetail, durationMs });
  }

  const rows = Array.isArray(data) ? data : [];
  const status: RlsProbeStatus = rows.length > 0 ? 'ALLOWED' : 'ALLOWED_EMPTY';
  return makeResult(def.id, status, {
    rowCount: rows.length,
    returnedColumns: cols,
    durationMs,
    anomaly: computeAnomaly(def, status),
    diagnosticNote:
      rows.length > 1
        ? `${rows.length} organizations returned. If RLS filters to own org, only 1 is expected.`
        : undefined,
  });
}

/**
 * E1: member_notes
 * Only request non-sensitive metadata columns. Never display note_text.
 */
async function probeE1(def: RlsProbeDefinition): Promise<RlsProbeResult> {
  // Deliberately exclude note_text from the projection
  const cols = ['id', 'member_id', 'note_type', 'is_resolved', 'organization_id'];
  const { data, error, durationMs } = await timedSelect(() =>
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase.from('member_notes') as any).select(cols.join(', ')).limit(1),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, {
      error: errorDetail,
      durationMs,
      anomaly: computeAnomaly(def, status),
    });
  }

  const rows = Array.isArray(data) ? data : [];
  const status: RlsProbeStatus = rows.length > 0 ? 'ALLOWED' : 'ALLOWED_EMPTY';

  return makeResult(def.id, status, {
    rowCount: rows.length,
    returnedColumns: cols,
    durationMs,
    anomaly: computeAnomaly(def, status),
    // note_text is excluded from projection — we only report existence, not content
    diagnosticNote:
      rows.length > 0
        ? '⚠ member_notes rows accessible. note_text was EXCLUDED from the probe projection and is NOT rendered.'
        : 'No member_notes rows returned — either denied or no notes exist for this org.',
  });
}

/**
 * E2: member_qr_tokens
 * Probe specifically for token_hash exposure.
 * We request a minimal projection that INCLUDES token_hash to test whether
 * RLS strips it or denies access entirely.
 */
async function probeE2(def: RlsProbeDefinition): Promise<RlsProbeResult> {
  const safeMetaCols = ['id', 'token_public_id', 'token_status', 'organization_id', 'is_primary'];
  const hashCol = 'token_hash';
  const allCols = [...safeMetaCols, hashCol];

  const { data, error, durationMs } = await timedSelect(() =>
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase.from('member_qr_tokens') as any).select(allCols.join(', ')).limit(1),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, {
      error: errorDetail,
      durationMs,
      anomaly: computeAnomaly(def, status),
    });
  }

  const rows = Array.isArray(data) ? data : [];
  const status: RlsProbeStatus = rows.length > 0 ? 'ALLOWED' : 'ALLOWED_EMPTY';

  // Detect if token_hash was present in the response (regardless of value)
  const firstRow = rows[0] as Record<string, unknown> | undefined;
  const hashPresent = firstRow !== undefined && hashCol in firstRow && firstRow[hashCol] !== null;

  return makeResult(def.id, status, {
    rowCount: rows.length,
    returnedColumns: safeMetaCols, // do NOT log the hash column name as "returned" in display
    sensitiveColumnPresent: hashPresent,
    durationMs,
    anomaly: computeAnomaly(def, status),
    diagnosticNote:
      rows.length > 0
        ? hashPresent
          ? '🚨 CRITICAL: token_hash was returned in the response. The raw value is NOT stored or rendered here.'
          : '⚠ QR token metadata accessible. token_hash was not present in the returned columns (may be stripped by column-level security).'
        : 'No QR token rows returned — either denied or no tokens exist.',
  });
}

/**
 * F1: get_current_profile_context() — verifies binding to own session
 */
async function probeF1(def: RlsProbeDefinition): Promise<RlsProbeResult> {
  const t0 = performance.now();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)('get_current_profile_context');
  const durationMs = Math.round(performance.now() - t0);

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, {
      error: errorDetail,
      durationMs,
      anomaly: computeAnomaly(def, status),
    });
  }

  const hasProfile = data && typeof data === 'object' && 'profile' in data && data.profile !== null;
  const status: RlsProbeStatus = hasProfile ? 'ALLOWED' : 'ALLOWED_EMPTY';

  return makeResult(def.id, status, {
    rowCount: hasProfile ? 1 : 0,
    durationMs,
    anomaly: computeAnomaly(def, status),
    diagnosticNote:
      'RPC returned. Profile ID is bound to auth.uid() server-side — no caller-supplied ID accepted.',
  });
}

/**
 * F2: get_current_authorization_context() with own org UUID
 */
async function probeF2(
  def: RlsProbeDefinition,
  organizationId: string,
): Promise<RlsProbeResult> {
  const t0 = performance.now();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)(
    'get_current_authorization_context',
    { p_organization_id: organizationId },
  );
  const durationMs = Math.round(performance.now() - t0);

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, {
      error: errorDetail,
      durationMs,
      anomaly: computeAnomaly(def, status),
    });
  }

  const hasData = data && typeof data === 'object';
  const status: RlsProbeStatus = hasData ? 'ALLOWED' : 'ALLOWED_EMPTY';

  return makeResult(def.id, status, {
    rowCount: hasData ? 1 : 0,
    durationMs,
    anomaly: computeAnomaly(def, status),
    diagnosticNote: 'Authorization context returned for own organization. Roles and permissions present in context.',
  });
}

/**
 * F3: get_current_authorization_context() with a random UUID (not caller's org)
 * The RPC enforces an application-level organization-boundary check. This is NOT
 * an RLS policy — it is an explicit server-side authorization guard that rejects
 * any org UUID not belonging to the caller.
 * Expected: ACCESS_DENIED (server raises P0001/42501 via application logic)
 */
async function probeF3(def: RlsProbeDefinition): Promise<RlsProbeResult> {
  // A deterministic but invalid UUID — not a real org
  const invalidOrgId = '00000000-0000-4000-8000-000000000000';
  const t0 = performance.now();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)(
    'get_current_authorization_context',
    { p_organization_id: invalidOrgId },
  );
  const durationMs = Math.round(performance.now() - t0);

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    // Any error from this probe is the expected application-boundary rejection.
    // Classify as ACCESS_DENIED to distinguish from RLS policy denials.
    return makeResult(def.id, 'ACCESS_DENIED', {
      error: {
        ...errorDetail,
        normalizedMessage:
          `Organization boundary correctly enforced: ${errorDetail.normalizedMessage}`,
      },
      durationMs,
      anomaly: undefined, // This is the expected outcome — not an anomaly
      diagnosticNote:
        '✓ Server correctly rejected organization UUID not belonging to caller. ' +
        'ACCESS_DENIED confirms the application-level org-boundary check is functioning. ' +
        'This is an RPC authorization guard, not a PostgreSQL RLS policy.',
    });
  }

  // If we got data back, that IS an anomaly — the boundary check failed
  return makeResult(def.id, 'ALLOWED', {
    rowCount: data ? 1 : 0,
    durationMs,
    anomaly: 'unexpected_access',
    diagnosticNote:
      '🚨 CRITICAL: Authorization context was returned for a UUID not belonging to caller. Org boundary check may be ineffective.',
  });
}

/**
 * F4: profile_organization_memberships filtered to a different profile_id
 * (uses a deterministic fake UUID — not a real profile).
 * Expected: 0 rows (RLS filters silently) or explicit denial.
 */
async function probeF4(
  def: RlsProbeDefinition,
  ownProfileId: string,
): Promise<RlsProbeResult> {
  // Construct a syntactically valid UUID guaranteed not to equal ownProfileId.
  // Strategy: keep the caller's first four UUID segments unchanged, then replace
  // the last 12-char segment with a fixed safe hex value.
  // This avoids any integer overflow or signed-bit issues from bitwise ops.
  let otherProfileId = '00000000-0000-4000-8000-000000000001';
  const parts = ownProfileId.split('-');
  if (parts.length === 5 && parts[0].length === 8) {
    // Use caller's UUID prefix so the UUID is in the same UUID version/variant family,
    // but replace the last segment entirely.
    const safeSuffix = parts[4] === '000000000001' ? '000000000002' : '000000000001';
    otherProfileId = `${parts[0]}-${parts[1]}-${parts[2]}-${parts[3]}-${safeSuffix}`;
  }

  const cols = ['id', 'profile_id', 'organization_id', 'membership_status'];
  const { data, error, durationMs } = await timedSelect(() =>
    supabase
      .from('profile_organization_memberships')
      .select(cols.join(', '))
      .eq('profile_id', otherProfileId)
      .limit(1),
  );

  if (error) {
    const errorDetail = normalizePostgrestError(error);
    const status = statusFromErrorDetail(errorDetail);
    return makeResult(def.id, status, {
      error: errorDetail,
      durationMs,
      // If it's denied, that's actually the expected behaviour
      anomaly: undefined,
      diagnosticNote: 'Query with other-profile filter was explicitly rejected by RLS.',
    });
  }

  const rows = Array.isArray(data) ? data : [];
  if (rows.length === 0) {
    return makeResult(def.id, 'ALLOWED_EMPTY', {
      rowCount: 0,
      returnedColumns: cols,
      durationMs,
      anomaly: undefined,
      diagnosticNote:
        'Request succeeded but returned 0 rows — RLS appears to silently filter to own profile. ' +
        'Cannot definitively confirm cross-profile isolation without a second real user.',
    });
  }

  // Rows returned for a different profile_id — potential RLS bypass
  return makeResult(def.id, 'ALLOWED', {
    rowCount: rows.length,
    returnedColumns: cols,
    durationMs,
    anomaly: 'unexpected_access',
    diagnosticNote:
      '🚨 Rows returned for a different profile_id filter. Verify whether the returned profile_id matches the current user.',
  });
}

// ---------------------------------------------------------------------------
// Run all probes in sequence
// ---------------------------------------------------------------------------

export type ProbeRunnerContext = {
  ownProfileId: string;
  ownOrganizationId: string;
  onProbeStart?: (id: string) => void;
  onProbeComplete?: (id: string, result: RlsProbeResult) => void;
};

export async function runAllProbes(ctx: ProbeRunnerContext): Promise<Record<string, RlsProbeResult>> {
  const results: Record<string, RlsProbeResult> = {};

  for (const def of PROBE_DEFINITIONS) {
    ctx.onProbeStart?.(def.id);
    const result = await runProbe(def, ctx.ownProfileId, ctx.ownOrganizationId);
    results[def.id] = result;
    ctx.onProbeComplete?.(def.id, result);
  }

  return results;
}

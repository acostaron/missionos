/**
 * RlsDiagnosticsPage.tsx
 *
 * Development-only RLS test matrix page at /dev/rls-tests.
 *
 * This page is only rendered in development builds (import.meta.env.DEV).
 * The router also gates it behind an authenticated session.
 *
 * What this page does:
 *  - Shows current auth/org/role/permission context
 *  - Runs 32 read-only RLS probes against the live Supabase database
 *  - Reports ALLOWED, ALLOWED_EMPTY, DENIED_BY_RLS, NO_PERMISSION, NOT_AVAILABLE, NOT_EXPOSED, ERROR
 *  - Flags UNEXPECTED_ACCESS and UNEXPECTED_DENIAL prominently
 *  - UNEXPECTED_DENIAL only fires when expected === ALLOWED; UNKNOWN-expected probes do not generate it
 *  - Expands per-probe error detail on click
 *  - Never renders sensitive values (note_text, token_hash, audit payloads)
 */

import { useState, useCallback } from 'react';
import { useAuth } from '../../hooks/use-auth';
import { useCurrentProfile } from '../../hooks/use-current-profile';
import { useCurrentOrganization } from '../../hooks/use-current-organization';
import { usePermissions } from '../../hooks/use-permissions';
import {
  PROBE_DEFINITIONS,
  runAllProbes,
} from './rls-probes';
import type {
  RlsProbeDefinition,
  RlsProbeResult,
  RlsProbeGroup,
} from './rls-test-types';

// ---------------------------------------------------------------------------
// Group metadata
// ---------------------------------------------------------------------------

const GROUP_LABELS: Record<RlsProbeGroup, string> = {
  A_IDENTITY: 'A — Identity & Organization',
  B_AUTHORIZATION: 'B — Authorization',
  C_GOVERNANCE: 'C — Governance',
  D_MEMBER_FAMILY: 'D — Member / Family',
  E_SENSITIVE: 'E — Sensitive & Protected',
  F_BOUNDARY: 'F — Impersonation & Boundary',
  G_CATALOG: 'G — Catalog Tables',
};

const GROUP_ORDER: RlsProbeGroup[] = [
  'A_IDENTITY',
  'B_AUTHORIZATION',
  'C_GOVERNANCE',
  'D_MEMBER_FAMILY',
  'E_SENSITIVE',
  'F_BOUNDARY',
  'G_CATALOG',
];

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

type DisplayStatus = RlsProbeResult['displayStatus'];

const STATUS_STYLES: Record<DisplayStatus, { bg: string; text: string; label: string }> = {
  ALLOWED: { bg: '#166534', text: '#dcfce7', label: 'ALLOWED' },
  ACCESS_DENIED: { bg: '#4c1d95', text: '#ede9fe', label: 'ACCESS DENIED' },
  DENIED_BY_RLS: { bg: '#9f1239', text: '#ffe4e6', label: 'DENIED (RLS)' },
  NO_PERMISSION: { bg: '#7c2d12', text: '#ffedd5', label: 'NO PERMISSION' },
  NOT_AVAILABLE: { bg: '#374151', text: '#e5e7eb', label: 'NOT AVAILABLE' },
  NOT_EXPOSED: { bg: '#134e4a', text: '#ccfbf1', label: 'NOT EXPOSED ✓' },
  ERROR: { bg: '#78350f', text: '#fef3c7', label: 'ERROR' },
  PENDING: { bg: '#1e3a5f', text: '#bfdbfe', label: 'PENDING' },
  RUNNING: { bg: '#1e40af', text: '#dbeafe', label: 'RUNNING…' },
};

function StatusBadge({
  status,
  anomaly,
}: {
  status: DisplayStatus;
  anomaly?: RlsProbeResult['anomaly'];
}) {
  const s = STATUS_STYLES[status];
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '2px 8px',
        borderRadius: 4,
        fontSize: 11,
        fontWeight: 700,
        letterSpacing: '0.05em',
        background: s.bg,
        color: s.text,
        fontFamily: 'monospace',
      }}
    >
      {s.label}
      {anomaly === 'unexpected_access' && ' 🚨'}
      {anomaly === 'unexpected_denial' && ' ⚠️'}
    </span>
  );
}

function ExpectationBadge({ expected }: { expected: RlsProbeDefinition['expected'] }) {
  const labelMap: Record<string, string> = {
    ALLOWED: 'ALLOWED',
    ALLOWED_OR_EMPTY: 'ALLOWED / EMPTY',
    DENIED: 'DENIED',
    UNKNOWN: '?',
  };
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '2px 6px',
        borderRadius: 4,
        fontSize: 10,
        fontWeight: 600,
        background: '#1e293b',
        color: '#94a3b8',
        fontFamily: 'monospace',
        border: '1px solid #334155',
      }}
    >
      {labelMap[expected] ?? expected}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Expandable detail row
// ---------------------------------------------------------------------------

function ProbeDetail({ result }: { result: RlsProbeResult }) {
  if (!result.error && !result.diagnosticNote && result.rowCount === undefined) return null;

  return (
    <div
      style={{
        background: '#0f172a',
        border: '1px solid #1e293b',
        borderRadius: 4,
        padding: '8px 12px',
        marginTop: 4,
        fontSize: 12,
        color: '#94a3b8',
        fontFamily: 'monospace',
      }}
    >
      {result.rowCount !== undefined && (
        <div>
          <span style={{ color: '#64748b' }}>rows returned: </span>
          <span style={{ color: '#e2e8f0' }}>{result.rowCount}</span>
          {result.status === 'ALLOWED_EMPTY' && (
            <span style={{ color: '#64748b' }}> (ALLOWED — empty)</span>
          )}
        </div>
      )}
      {result.returnedColumns && result.returnedColumns.length > 0 && (
        <div>
          <span style={{ color: '#64748b' }}>columns probed: </span>
          <span style={{ color: '#e2e8f0' }}>{result.returnedColumns.join(', ')}</span>
        </div>
      )}
      {result.sensitiveColumnPresent !== undefined && (
        <div style={{ color: result.sensitiveColumnPresent ? '#f87171' : '#4ade80' }}>
          token_hash present in response: {result.sensitiveColumnPresent ? '🚨 YES' : '✓ NO'}
        </div>
      )}
      {result.durationMs !== undefined && (
        <div>
          <span style={{ color: '#64748b' }}>duration: </span>
          <span style={{ color: '#e2e8f0' }}>{result.durationMs}ms</span>
        </div>
      )}
      {result.diagnosticNote && (
        <div style={{ marginTop: 4, color: '#cbd5e1', fontSize: 11 }}>
          {result.diagnosticNote}
        </div>
      )}
      {result.error && (
        <div style={{ marginTop: 4 }}>
          {result.error.httpStatus !== undefined && (
            <div>
              <span style={{ color: '#64748b' }}>http status: </span>
              <span style={{ color: '#fca5a5' }}>{result.error.httpStatus}</span>
            </div>
          )}
          {result.error.pgCode && (
            <div>
              <span style={{ color: '#64748b' }}>pg code: </span>
              <span style={{ color: '#fca5a5' }}>{result.error.pgCode}</span>
            </div>
          )}
          {result.error.postgrestCode && (
            <div>
              <span style={{ color: '#64748b' }}>postgrest code: </span>
              <span style={{ color: '#fca5a5' }}>{result.error.postgrestCode}</span>
            </div>
          )}
          <div>
            <span style={{ color: '#64748b' }}>message: </span>
            <span style={{ color: '#e2e8f0' }}>{result.error.normalizedMessage}</span>
          </div>
          {result.error.hint && (
            <div>
              <span style={{ color: '#64748b' }}>hint: </span>
              <span style={{ color: '#e2e8f0' }}>{result.error.hint}</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Probe row
// ---------------------------------------------------------------------------

function ProbeRow({
  def,
  result,
}: {
  def: RlsProbeDefinition;
  result: RlsProbeResult | undefined;
}) {
  const [expanded, setExpanded] = useState(false);
  const status = result?.displayStatus ?? 'PENDING';
  const anomaly = result?.anomaly;

  const hasDetail =
    result &&
    (result.error || result.diagnosticNote || result.rowCount !== undefined);

  const rowBg =
    anomaly === 'unexpected_access'
      ? '#2d0a0a'
      : anomaly === 'unexpected_denial'
      ? '#1c1a00'
      : 'transparent';

  return (
    <>
      <tr
        style={{
          background: rowBg,
          cursor: hasDetail ? 'pointer' : 'default',
          borderBottom: '1px solid #1e293b',
        }}
        onClick={() => hasDetail && setExpanded(e => !e)}
        title={hasDetail ? 'Click to expand' : undefined}
      >
        <td style={{ padding: '6px 8px', color: '#64748b', fontFamily: 'monospace', width: 40 }}>
          {def.id}
        </td>
        <td style={{ padding: '6px 8px', color: '#e2e8f0', fontSize: 13 }}>
          {def.label}
          {anomaly === 'unexpected_access' && (
            <span style={{ marginLeft: 6, color: '#f87171', fontSize: 11 }}>⚠ UNEXPECTED ACCESS</span>
          )}
          {anomaly === 'unexpected_denial' && (
            <span style={{ marginLeft: 6, color: '#fbbf24', fontSize: 11 }}>⚠ UNEXPECTED DENIAL</span>
          )}
        </td>
        <td style={{ padding: '6px 8px', color: '#94a3b8', fontSize: 11, fontFamily: 'monospace' }}>
          {def.schema}.{def.target}
        </td>
        <td style={{ padding: '6px 8px' }}>
          <ExpectationBadge expected={def.expected} />
        </td>
        <td style={{ padding: '6px 8px' }}>
          <StatusBadge status={status} anomaly={anomaly} />
        </td>
        <td style={{ padding: '6px 8px', color: '#475569', fontSize: 11 }}>
          {result?.durationMs !== undefined ? `${result.durationMs}ms` : '—'}
        </td>
        <td style={{ padding: '6px 8px', color: '#475569', fontSize: 10 }}>
          {hasDetail ? (expanded ? '▲' : '▼') : ''}
        </td>
      </tr>
      {expanded && hasDetail && (
        <tr style={{ background: rowBg }}>
          <td />
          <td colSpan={6} style={{ padding: '4px 8px 8px' }}>
            <ProbeDetail result={result!} />
          </td>
        </tr>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// Context panel
// ---------------------------------------------------------------------------

function ContextPanel({
  userId,
  profileName,
  orgName,
  orgId,
  orgCode,
  roles,
  permissions,
}: {
  userId: string | undefined;
  profileName: string | undefined;
  orgName: string | undefined;
  orgId: string | undefined;
  orgCode: string | undefined;
  roles: { role_code: string; assignment_status: string }[];
  permissions: { code: string; state: string }[];
}) {
  const activePermissions = permissions.filter(p => p.state === 'allow');

  return (
    <div
      style={{
        background: '#0f172a',
        border: '1px solid #1e3a5f',
        borderRadius: 8,
        padding: 16,
        marginBottom: 20,
        fontSize: 13,
      }}
    >
      <div style={{ color: '#60a5fa', fontWeight: 700, marginBottom: 10, fontSize: 14 }}>
        Current Session Context
      </div>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr 1fr',
          gap: 8,
          color: '#cbd5e1',
        }}
      >
        <div>
          <span style={{ color: '#64748b' }}>auth.uid(): </span>
          <code style={{ color: '#93c5fd', fontSize: 11 }}>{userId ?? '—'}</code>
        </div>
        <div>
          <span style={{ color: '#64748b' }}>display name: </span>
          <span>{profileName ?? '—'}</span>
        </div>
        <div>
          <span style={{ color: '#64748b' }}>organization: </span>
          <span>{orgName ?? '—'} {orgCode ? `(${orgCode})` : ''}</span>
        </div>
        <div>
          <span style={{ color: '#64748b' }}>org id: </span>
          <code style={{ fontSize: 11 }}>{orgId ?? '—'}</code>
        </div>
        <div>
          <span style={{ color: '#64748b' }}>roles: </span>
          <span>
            {roles.length > 0
              ? roles.map(r => `${r.role_code} (${r.assignment_status})`).join(', ')
              : '—'}
          </span>
        </div>
        <div>
          <span style={{ color: '#64748b' }}>effective permissions: </span>
          <span style={{ color: activePermissions.length > 0 ? '#4ade80' : '#f87171' }}>
            {activePermissions.length} allowed
          </span>
        </div>
      </div>
      {activePermissions.length > 0 && (
        <div style={{ marginTop: 10 }}>
          <span style={{ color: '#64748b', fontSize: 12 }}>allowed permission codes: </span>
          <div style={{ marginTop: 4, display: 'flex', flexWrap: 'wrap', gap: 4 }}>
            {activePermissions.map(p => (
              <code
                key={p.code}
                style={{
                  background: '#1e3a5f',
                  color: '#93c5fd',
                  padding: '2px 6px',
                  borderRadius: 3,
                  fontSize: 10,
                }}
              >
                {p.code}
              </code>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Summary row
// ---------------------------------------------------------------------------

function SummaryBar({ results }: { results: Record<string, RlsProbeResult> }) {
  const values = Object.values(results);
  const counts = {
    allowed: values.filter(r => r.displayStatus === 'ALLOWED').length,
    accessDenied: values.filter(r => r.displayStatus === 'ACCESS_DENIED').length,
    denied: values.filter(r => r.displayStatus === 'DENIED_BY_RLS').length,
    noPermission: values.filter(r => r.displayStatus === 'NO_PERMISSION').length,
    notExposed: values.filter(r => r.displayStatus === 'NOT_EXPOSED').length,
    notAvailable: values.filter(r => r.displayStatus === 'NOT_AVAILABLE').length,
    error: values.filter(r => r.displayStatus === 'ERROR').length,
    anomalyAccess: values.filter(r => r.anomaly === 'unexpected_access').length,
    anomalyDenial: values.filter(r => r.anomaly === 'unexpected_denial').length,
  };
  const total = PROBE_DEFINITIONS.length;
  const run = values.length;

  return (
    <div
      style={{
        background: '#0f172a',
        border: '1px solid #1e293b',
        borderRadius: 8,
        padding: 12,
        marginBottom: 20,
        display: 'flex',
        flexWrap: 'wrap',
        gap: 12,
        fontSize: 13,
        color: '#e2e8f0',
      }}
    >
      <span style={{ color: '#64748b' }}>Probes: {run}/{total}</span>
      <span style={{ color: '#4ade80' }}>✓ ALLOWED: {counts.allowed}</span>
      {counts.accessDenied > 0 && (
        <span style={{ color: '#a78bfa' }}>✓ ACCESS DENIED (boundary): {counts.accessDenied}</span>
      )}
      {counts.denied > 0 && (
        <span style={{ color: '#f87171' }}>✗ DENIED (RLS): {counts.denied}</span>
      )}
      <span style={{ color: '#fb923c' }}>⊘ NO PERMISSION: {counts.noPermission}</span>
      {counts.notExposed > 0 && (
        <span style={{ color: '#2dd4bf' }}>✓ NOT EXPOSED (secure): {counts.notExposed}</span>
      )}
      {counts.notAvailable > 0 && (
        <span style={{ color: '#94a3b8' }}>? NOT AVAILABLE: {counts.notAvailable}</span>
      )}
      {counts.error > 0 && (
        <span style={{ color: '#fbbf24' }}>⚠ ERROR: {counts.error}</span>
      )}

      {counts.anomalyAccess > 0 && (
        <span style={{ color: '#f87171', fontWeight: 700 }}>
          🚨 UNEXPECTED ACCESS: {counts.anomalyAccess}
        </span>
      )}
      {counts.anomalyDenial > 0 && (
        <span style={{ color: '#fbbf24', fontWeight: 700 }}>
          ⚠️ UNEXPECTED DENIAL: {counts.anomalyDenial}
        </span>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function RlsDiagnosticsPage() {
  const { user } = useAuth();
  const { profile } = useCurrentProfile();
  const { organization } = useCurrentOrganization();
  const { roles, permissions, isLoading: permLoading } = usePermissions();

  const [results, setResults] = useState<Record<string, RlsProbeResult>>({});
  const [runningId, setRunningId] = useState<string | null>(null);
  const [isRunning, setIsRunning] = useState(false);
  const [completedAt, setCompletedAt] = useState<string | null>(null);

  const profileId = user?.id ?? '';
  const orgId = organization?.id ?? '';

  const runAll = useCallback(async () => {
    if (!profileId || !orgId) return;
    setResults({});
    setIsRunning(true);
    setCompletedAt(null);

    await runAllProbes({
      ownProfileId: profileId,
      ownOrganizationId: orgId,
      onProbeStart: id => setRunningId(id),
      onProbeComplete: (id, result) => {
        setRunningId(null);
        setResults(prev => ({ ...prev, [id]: result }));
      },
    });

    setIsRunning(false);
    setCompletedAt(new Date().toISOString());
  }, [profileId, orgId]);

  const pendingResult = (id: string): RlsProbeResult | undefined => {
    if (runningId === id) {
      return {
        probeId: id,
        status: 'RUNNING',
        displayStatus: 'RUNNING',
        recordedAt: new Date().toISOString(),
      };
    }
    return results[id];
  };

  const canRun = !!profileId && !!orgId && !isRunning;

  return (
    <div
      style={{
        minHeight: '100vh',
        background: '#020617',
        color: '#e2e8f0',
        fontFamily: 'system-ui, -apple-system, sans-serif',
        padding: 24,
      }}
    >
      {/* Header */}
      <div style={{ marginBottom: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 8 }}>
          <span
            style={{
              background: '#b45309',
              color: '#fef3c7',
              padding: '2px 10px',
              borderRadius: 4,
              fontSize: 11,
              fontWeight: 700,
              letterSpacing: '0.1em',
            }}
          >
            DEV ONLY
          </span>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: '#f1f5f9' }}>
            RLS Diagnostics — Phase 3 Verification
          </h1>
        </div>
        <p style={{ margin: 0, color: '#64748b', fontSize: 13 }}>
          All probes execute read-only queries through the authenticated browser client (anon key + user JWT).
          No service-role key. No mutations. Sensitive column values are never rendered.
        </p>
      </div>

      {/* Context panel */}
      <ContextPanel
        userId={user?.id}
        profileName={profile?.display_name}
        orgName={organization?.name}
        orgId={organization?.id}
        orgCode={organization?.code}
        roles={roles}
        permissions={permissions}
      />

      {/* Run controls */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 20 }}>
        <button
          id="run-all-probes"
          onClick={runAll}
          disabled={!canRun || permLoading}
          style={{
            background: canRun ? '#2563eb' : '#1e293b',
            color: canRun ? '#fff' : '#475569',
            border: 'none',
            borderRadius: 6,
            padding: '8px 18px',
            fontSize: 14,
            fontWeight: 600,
            cursor: canRun ? 'pointer' : 'not-allowed',
            transition: 'background 0.15s',
          }}
        >
          {isRunning ? 'Running…' : completedAt ? 'Re-run All Probes' : 'Run All Probes'}
        </button>
        {!profileId && (
          <span style={{ color: '#f87171', fontSize: 12 }}>
            No authenticated session detected — login required.
          </span>
        )}
        {!orgId && profileId && (
          <span style={{ color: '#fbbf24', fontSize: 12 }}>
            No active organization — cannot run org-scoped probes.
          </span>
        )}
        {completedAt && (
          <span style={{ color: '#64748b', fontSize: 12 }}>
            Completed at {new Date(completedAt).toLocaleTimeString()}
          </span>
        )}
      </div>

      {/* Summary */}
      {Object.keys(results).length > 0 && <SummaryBar results={results} />}

      {/* Probe matrix grouped by section */}
      {GROUP_ORDER.map(group => {
        const defs = PROBE_DEFINITIONS.filter(d => d.group === group);
        return (
          <div key={group} style={{ marginBottom: 28 }}>
            <div
              style={{
                color: '#94a3b8',
                fontSize: 13,
                fontWeight: 700,
                letterSpacing: '0.05em',
                textTransform: 'uppercase',
                marginBottom: 8,
                paddingBottom: 4,
                borderBottom: '1px solid #1e293b',
              }}
            >
              {GROUP_LABELS[group]}
            </div>
            <table
              style={{
                width: '100%',
                borderCollapse: 'collapse',
                background: '#0a0f1e',
                borderRadius: 6,
                overflow: 'hidden',
                border: '1px solid #1e293b',
              }}
            >
              <thead>
                <tr style={{ background: '#0f172a', borderBottom: '1px solid #1e293b' }}>
                  <th style={{ ...thStyle, width: 40 }}>ID</th>
                  <th style={thStyle}>Probe</th>
                  <th style={thStyle}>Target</th>
                  <th style={thStyle}>Expected</th>
                  <th style={thStyle}>Actual</th>
                  <th style={{ ...thStyle, width: 70 }}>Time</th>
                  <th style={{ ...thStyle, width: 24 }} />
                </tr>
              </thead>
              <tbody>
                {defs.map(def => (
                  <ProbeRow
                    key={def.id}
                    def={def}
                    result={pendingResult(def.id)}
                  />
                ))}
              </tbody>
            </table>
          </div>
        );
      })}

      {/* Legend */}
      <div
        style={{
          marginTop: 32,
          borderTop: '1px solid #1e293b',
          paddingTop: 16,
          fontSize: 11,
          color: '#475569',
        }}
      >
        <div style={{ marginBottom: 8, fontWeight: 700, color: '#64748b' }}>Legend</div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>
          {Object.entries(STATUS_STYLES).map(([key, s]) => (
            <span key={key} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
              <span
                style={{
                  background: s.bg,
                  color: s.text,
                  padding: '1px 6px',
                  borderRadius: 3,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: 700,
                }}
              >
                {s.label}
              </span>
            </span>
          ))}
          <span>🚨 = UNEXPECTED ACCESS (security concern)</span>
          <span>⚠️ = UNEXPECTED DENIAL (only for expected=ALLOWED probes)</span>
        </div>
        <div style={{ marginTop: 8, lineHeight: 1.7 }}>
          <div>
            <strong>ALLOWED_EMPTY</strong> is displayed as ALLOWED — row count in detail distinguishes the two.
            An empty successful SELECT means the query was permitted; rows may be silently filtered by RLS.
          </div>
          <div>
            <strong>ACCESS DENIED</strong> = an RPC/application authorization boundary explicitly rejected the request.
            This is distinct from RLS: the server enforces an app-level check (e.g., org membership) before returning data.
            F3 returning ACCESS DENIED is the expected and correct result.
          </div>
          <div>
            <strong>NO PERMISSION</strong> (pg 42501) = the PostgreSQL role lacks direct SELECT privilege on the table.
            This is expected for most tables in Release 1A, which uses RPC-mediated access.
            It is NOT an RLS denial and does NOT indicate a security problem.
          </div>
          <div>
            <strong>NOT EXPOSED ✓</strong> (PGRST106) = the schema is intentionally unavailable through PostgREST.
            This is the correct secure state for the audit schema and should not be treated as an error.
          </div>
          <div>
            <strong>Expected=UNKNOWN</strong> probes never generate UNEXPECTED DENIAL.
            Only probes with Expected=ALLOWED will flag it.
          </div>
        </div>

      </div>
    </div>
  );
}

const thStyle: React.CSSProperties = {
  padding: '6px 8px',
  textAlign: 'left',
  fontSize: 11,
  fontWeight: 600,
  color: '#64748b',
  letterSpacing: '0.04em',
  textTransform: 'uppercase',
};

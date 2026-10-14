import { useState, useMemo } from 'react';
import {
  Check,
  Copy,
  Printer,
  RotateCcw,
  Search,
  ShieldAlert,
  Users,
  KeyRound,
  CheckCircle2,
  AlertTriangle,
  UserX,
} from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import {
  useMemberLoginStatus,
  useIssueMemberClaimCodes,
  useRevokeMemberClaimCode,
  type MemberLoginStatus,
  type IssueCodesResult,
} from '../features/members/login-queries';
import {
  Alert,
  Badge,
  Button,
  Card,
  EmptyState,
  Modal,
  PageHeader,
  Select,
  StatCard,
} from '../components/ui';

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  try {
    const d = new Date(dateStr);
    if (!Number.isNaN(d.getTime())) {
      return d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      });
    }
  } catch {
    // fallback
  }
  return dateStr.split('T')[0] || dateStr;
}

const REASON_LABELS: Record<string, string> = {
  already_has_login: 'already has a login',
  out_of_scope: 'outside your area',
  not_active: 'not an active member',
  not_found: 'not found',
};

export default function MemberLoginsPage() {
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const orgId = activeOrganization?.id ?? null;

  const canIssueCodes = !isPermLoading && hasPermission(Permissions.MembersAccountsIssueCodes);

  // Queries & mutations
  const { data: members = [], isLoading, error } = useMemberLoginStatus(orgId);
  const issueMutation = useIssueMemberClaimCodes();
  const revokeMutation = useRevokeMemberClaimCode();

  // Filters & selection
  const [search, setSearch] = useState('');
  const [chapterFilter, setChapterFilter] = useState('all');
  const [sectionFilter, setSectionFilter] = useState('all');
  const [stateFilter, setStateFilter] = useState<string>('all');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Confirmations & result modal
  const [confirmIssueOpen, setConfirmIssueOpen] = useState(false);
  const [memberToRevoke, setMemberToRevoke] = useState<MemberLoginStatus | null>(null);
  const [issuedResult, setIssuedResult] = useState<IssueCodesResult | null>(null);
  const [copiedAll, setCopiedAll] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  // Chapters & Sections for filter dropdowns
  const { chapters, sections } = useMemo(() => {
    const cSet = new Set<string>();
    const sSet = new Set<string>();
    members.forEach((m) => {
      if (m.chapter_name) cSet.add(m.chapter_name);
      if (m.section_name) sSet.add(m.section_name);
    });
    return {
      chapters: Array.from(cSet).sort(),
      sections: Array.from(sSet).sort(),
    };
  }, [members]);

  // Overall counts (unfiltered)
  const counts = useMemo(() => {
    let linked = 0;
    let code_active = 0;
    let code_expired = 0;
    let none = 0;
    members.forEach((m) => {
      if (m.login_state === 'linked') linked++;
      else if (m.login_state === 'code_active') code_active++;
      else if (m.login_state === 'code_expired') code_expired++;
      else none++;
    });
    return {
      total: members.length,
      linked,
      code_active,
      code_expired,
      none,
    };
  }, [members]);

  // Filtered members list
  const filteredMembers = useMemo(() => {
    const q = search.trim().toLowerCase();
    return members.filter((m) => {
      if (chapterFilter !== 'all' && m.chapter_name !== chapterFilter) return false;
      if (sectionFilter !== 'all' && m.section_name !== sectionFilter) return false;
      if (stateFilter !== 'all' && m.login_state !== stateFilter) return false;
      if (q) {
        const nameMatch = m.display_name.toLowerCase().includes(q);
        const numMatch = m.member_number ? m.member_number.toLowerCase().includes(q) : false;
        if (!nameMatch && !numMatch) return false;
      }
      return true;
    });
  }, [members, search, chapterFilter, sectionFilter, stateFilter]);

  // Selectable rows in current filtered list (rows with 'linked' cannot be selected)
  const selectableFilteredRows = useMemo(() => {
    return filteredMembers.filter((m) => m.login_state !== 'linked');
  }, [filteredMembers]);

  const allFilteredSelected =
    selectableFilteredRows.length > 0 &&
    selectableFilteredRows.every((m) => selectedIds.has(m.member_id));
  const someFilteredSelected =
    selectableFilteredRows.some((m) => selectedIds.has(m.member_id)) && !allFilteredSelected;

  const toggleSelectAllFiltered = () => {
    const next = new Set(selectedIds);
    if (allFilteredSelected) {
      selectableFilteredRows.forEach((m) => next.delete(m.member_id));
    } else {
      selectableFilteredRows.forEach((m) => next.add(m.member_id));
    }
    setSelectedIds(next);
  };

  const toggleRowSelect = (memberId: string) => {
    const next = new Set(selectedIds);
    if (next.has(memberId)) {
      next.delete(memberId);
    } else {
      next.add(memberId);
    }
    setSelectedIds(next);
  };

  // Check if any selected row has an active code
  const hasActiveCodeSelected = useMemo(() => {
    return members.some((m) => selectedIds.has(m.member_id) && m.login_state === 'code_active');
  }, [members, selectedIds]);

  // Handle clicking "Issue codes for selected"
  const handleIssueClick = () => {
    setActionError(null);
    if (selectedIds.size === 0) return;
    if (hasActiveCodeSelected) {
      setConfirmIssueOpen(true);
    } else {
      executeIssueCodes();
    }
  };

  const executeIssueCodes = async () => {
    if (!orgId || selectedIds.size === 0) return;
    setActionError(null);
    setConfirmIssueOpen(false);

    try {
      const result = await issueMutation.mutateAsync({
        organizationId: orgId,
        memberIds: Array.from(selectedIds),
      });
      setIssuedResult(result);
      setSelectedIds(new Set());
    } catch (err) {
      const msg = (err as Error).message || 'Failed to issue codes.';
      setActionError(msg);
    }
  };

  const handleRevokeConfirm = async () => {
    if (!orgId || !memberToRevoke) return;
    setActionError(null);

    try {
      await revokeMutation.mutateAsync({
        organizationId: orgId,
        memberId: memberToRevoke.member_id,
      });
      setMemberToRevoke(null);
    } catch (err) {
      const msg = (err as Error).message || 'Failed to revoke code.';
      setActionError(msg);
      setMemberToRevoke(null);
    }
  };

  const handleCopyAll = async () => {
    if (!issuedResult || issuedResult.issued.length === 0) return;
    const lines = issuedResult.issued.map((item) => {
      const formattedDate = formatDate(item.expires_at);
      return `${item.display_name} — your MissionOS code: ${item.code} — open app.mfcny.net/claim — expires ${formattedDate}`;
    });
    try {
      await navigator.clipboard.writeText(lines.join('\n'));
      setCopiedAll(true);
      setTimeout(() => setCopiedAll(false), 2500);
    } catch {
      // fallback
    }
  };

  const handlePrint = () => {
    if (!issuedResult || issuedResult.issued.length === 0) return;
    const printWindow = window.open('', '_blank');
    if (!printWindow) {
      window.print();
      return;
    }
    const rows = issuedResult.issued
      .map(
        (item) => `
      <tr>
        <td style="padding: 10px; border: 1px solid #e2e8f0;">${item.display_name}</td>
        <td style="padding: 10px; border: 1px solid #e2e8f0; font-family: monospace;">${item.member_number || '—'}</td>
        <td style="padding: 10px; border: 1px solid #e2e8f0; font-family: monospace; font-size: 1.15em; font-weight: bold; letter-spacing: 0.05em; color: #1e3a8a;">${item.code}</td>
        <td style="padding: 10px; border: 1px solid #e2e8f0;">${formatDate(item.expires_at)}</td>
      </tr>
    `
      )
      .join('');

    printWindow.document.write(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>MissionOS — Member Login Claim Codes</title>
          <style>
            body { font-family: system-ui, -apple-system, sans-serif; padding: 32px; color: #0f172a; }
            h1 { font-size: 22px; font-weight: 700; margin: 0 0 6px 0; }
            p { color: #475569; font-size: 14px; margin: 0 0 24px 0; line-height: 1.5; }
            table { width: 100%; border-collapse: collapse; text-align: left; font-size: 13px; }
            th { padding: 10px; background: #f8fafc; border: 1px solid #cbd5e1; font-weight: 600; color: #334155; }
            td { vertical-align: middle; }
            .footer { margin-top: 28px; font-size: 12px; color: #64748b; border-top: 1px solid #e2e8f0; pt: 16px; }
          </style>
        </head>
        <body>
          <h1>MissionOS — Member Login Claim Codes</h1>
          <p>Each member may redeem their one-time code by visiting <strong>app.mfcny.net/claim</strong>.</p>
          <table>
            <thead>
              <tr>
                <th>Member Name</th>
                <th>Member #</th>
                <th>One-Time Code</th>
                <th>Expires</th>
              </tr>
            </thead>
            <tbody>
              ${rows}
            </tbody>
          </table>
          <div class="footer">
            Generated on ${new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}. Shown only once upon issue. Codes expire in 30 days.
          </div>
        </body>
      </html>
    `);
    printWindow.document.close();
    printWindow.focus();
    setTimeout(() => {
      printWindow.print();
    }, 250);
  };

  // Permission / Loading states
  if (isOrgLoading || isPermLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center">
        <div className="text-sm text-ink-muted">Loading…</div>
      </div>
    );
  }

  if (!canIssueCodes) {
    return (
      <div className="mx-auto max-w-5xl space-y-8 px-4 py-8 sm:px-6 lg:px-8">
        <Card padding="comfortable">
          <EmptyState
            icon={<ShieldAlert />}
            title="Access Restricted"
            message="You do not have permission to issue or manage member login codes. Contact your organization administrator."
          />
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Member Logins"
        description="Issue one-time personal claim codes so members can create or link their MissionOS login."
      />

      {actionError && (
        <Alert variant="danger" className="mb-4">
          {actionError}
        </Alert>
      )}

      {/* Counts per state at the top */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-5">
        <div
          onClick={() => setStateFilter('all')}
          className={`cursor-pointer transition-opacity ${stateFilter === 'all' ? 'ring-2 ring-primary rounded-card' : 'opacity-85 hover:opacity-100'}`}
        >
          <StatCard
            label="Total Members"
            value={counts.total}
            icon={<Users />}
            tone="neutral"
          />
        </div>
        <div
          onClick={() => setStateFilter('linked')}
          className={`cursor-pointer transition-opacity ${stateFilter === 'linked' ? 'ring-2 ring-success-500 rounded-card' : 'opacity-85 hover:opacity-100'}`}
        >
          <StatCard
            label="Has Login"
            value={counts.linked}
            icon={<CheckCircle2 />}
            tone="success"
          />
        </div>
        <div
          onClick={() => setStateFilter('code_active')}
          className={`cursor-pointer transition-opacity ${stateFilter === 'code_active' ? 'ring-2 ring-primary rounded-card' : 'opacity-85 hover:opacity-100'}`}
        >
          <StatCard
            label="Code Active"
            value={counts.code_active}
            icon={<KeyRound />}
            tone="neutral"
          />
        </div>
        <div
          onClick={() => setStateFilter('code_expired')}
          className={`cursor-pointer transition-opacity ${stateFilter === 'code_expired' ? 'ring-2 ring-warning-500 rounded-card' : 'opacity-85 hover:opacity-100'}`}
        >
          <StatCard
            label="Code Expired"
            value={counts.code_expired}
            icon={<AlertTriangle />}
            tone="warning"
          />
        </div>
        <div
          onClick={() => setStateFilter('none')}
          className={`cursor-pointer transition-opacity ${stateFilter === 'none' ? 'ring-2 ring-primary rounded-card' : 'opacity-85 hover:opacity-100'}`}
        >
          <StatCard
            label="No Login"
            value={counts.none}
            icon={<UserX />}
            tone="neutral"
          />
        </div>
      </div>

      {/* Toolbar / Filters */}
      <Card padding="compact" className="space-y-4">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-1 flex-wrap items-center gap-3">
            {/* Search Box */}
            <div className="relative min-w-[220px] flex-1 sm:max-w-xs">
              <Search className="pointer-events-none absolute left-3 top-2.5 h-4 w-4 text-ink-muted" />
              <input
                type="search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search by name or number…"
                className="w-full rounded-control border border-line bg-surface py-2 pl-9 pr-3 text-small text-ink placeholder:text-ink-muted focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus"
              />
            </div>

            {/* Chapter Filter */}
            {chapters.length > 0 && (
              <div className="w-40">
                <Select
                  value={chapterFilter}
                  onChange={(e) => setChapterFilter(e.target.value)}
                  className="w-full"
                >
                  <option value="all">All Chapters</option>
                  {chapters.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </Select>
              </div>
            )}

            {/* Section Filter */}
            {sections.length > 0 && (
              <div className="w-40">
                <Select
                  value={sectionFilter}
                  onChange={(e) => setSectionFilter(e.target.value)}
                  className="w-full"
                >
                  <option value="all">All Sections</option>
                  {sections.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </Select>
              </div>
            )}

            {/* State Filter */}
            <div className="w-40">
              <Select
                value={stateFilter}
                onChange={(e) => setStateFilter(e.target.value)}
                className="w-full"
              >
                <option value="all">All States</option>
                <option value="linked">Has login</option>
                <option value="code_active">Code active</option>
                <option value="code_expired">Code expired</option>
                <option value="none">No login</option>
              </Select>
            </div>
          </div>

          {/* Action Button: Issue codes for selected */}
          <div className="flex items-center gap-3">
            <Button
              type="button"
              variant="primary"
              disabled={selectedIds.size === 0 || issueMutation.isPending}
              loading={issueMutation.isPending}
              onClick={handleIssueClick}
            >
              Issue codes for selected {selectedIds.size > 0 ? `(${selectedIds.size})` : ''}
            </Button>
          </div>
        </div>
      </Card>

      {/* Table */}
      <Card padding="none" className="overflow-hidden">
        {isLoading ? (
          <div className="p-8 text-center text-sm text-ink-muted">Loading member logins…</div>
        ) : error ? (
          <div className="p-8 text-center text-sm text-danger-700">
            Failed to load member login statuses.
          </div>
        ) : filteredMembers.length === 0 ? (
          <div className="p-8 text-center text-sm text-ink-muted">
            No members match the selected filters.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-small">
              <thead className="border-b border-line bg-surface-muted text-xs font-semibold uppercase tracking-wider text-ink-secondary">
                <tr>
                  <th className="w-10 px-4 py-3">
                    <input
                      type="checkbox"
                      checked={allFilteredSelected}
                      ref={(el) => {
                        if (el) el.indeterminate = someFilteredSelected;
                      }}
                      onChange={toggleSelectAllFiltered}
                      disabled={selectableFilteredRows.length === 0}
                      className="h-4 w-4 rounded border-line text-primary focus:ring-focus"
                      aria-label="Select all eligible members in view"
                    />
                  </th>
                  <th className="px-4 py-3">Name</th>
                  <th className="px-4 py-3">Member #</th>
                  <th className="px-4 py-3">Chapter</th>
                  <th className="px-4 py-3">Section</th>
                  <th className="px-4 py-3">Placement</th>
                  <th className="px-4 py-3 text-center">Email on file</th>
                  <th className="px-4 py-3">Login State</th>
                  <th className="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {filteredMembers.map((m) => {
                  const isLinked = m.login_state === 'linked';
                  const isSelected = selectedIds.has(m.member_id);

                  return (
                    <tr
                      key={m.member_id}
                      className={`hover:bg-surface-muted/60 transition-colors ${isSelected ? 'bg-surface-muted/40' : ''}`}
                    >
                      <td className="px-4 py-3">
                        <input
                          type="checkbox"
                          checked={isSelected}
                          disabled={isLinked}
                          onChange={() => toggleRowSelect(m.member_id)}
                          className="h-4 w-4 rounded border-line text-primary focus:ring-focus disabled:opacity-40"
                          aria-label={`Select ${m.display_name}`}
                        />
                      </td>
                      <td className="px-4 py-3 font-medium text-ink">
                        {m.display_name}
                      </td>
                      <td className="px-4 py-3 font-mono text-xs text-ink-secondary">
                        {m.member_number || '—'}
                      </td>
                      <td className="px-4 py-3 text-ink-secondary">
                        {m.chapter_name || '—'}
                      </td>
                      <td className="px-4 py-3 text-ink-secondary">
                        {m.section_name || '—'}
                      </td>
                      <td className="px-4 py-3 text-ink-secondary">
                        {m.placement_name || '—'}
                      </td>
                      <td className="px-4 py-3 text-center text-ink-secondary">
                        {m.has_email ? (
                          <span className="font-bold text-success-700" title="Email on file">
                            ✓
                          </span>
                        ) : (
                          <span className="text-ink-muted" title="No email on file">
                            –
                          </span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        {m.login_state === 'linked' && (
                          <Badge variant="success">Has login</Badge>
                        )}
                        {m.login_state === 'code_active' && (
                          <Badge variant="info">
                            Code active · expires {formatDate(m.code_expires_at)} · …{m.code_hint || ''}
                          </Badge>
                        )}
                        {m.login_state === 'code_expired' && (
                          <Badge variant="warning">Code expired</Badge>
                        )}
                        {m.login_state === 'none' && (
                          <Badge variant="neutral">No login</Badge>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        {m.login_state === 'code_active' && (
                          <button
                            type="button"
                            onClick={() => setMemberToRevoke(m)}
                            disabled={revokeMutation.isPending}
                            className="inline-flex items-center gap-1 rounded-control px-2 py-1 text-xs font-medium text-danger-700 hover:bg-danger-50 transition-colors"
                          >
                            <RotateCcw className="h-3 w-3" />
                            Revoke code
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {/* Confirmation Modal: Re-issue codes */}
      <Modal
        open={confirmIssueOpen}
        onClose={() => setConfirmIssueOpen(false)}
        title="Re-issue Claim Codes?"
        size="md"
        footer={
          <>
            <Button
              type="button"
              variant="outline"
              onClick={() => setConfirmIssueOpen(false)}
              disabled={issueMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="primary"
              onClick={executeIssueCodes}
              loading={issueMutation.isPending}
            >
              Yes, Issue Codes
            </Button>
          </>
        }
      >
        <p className="text-small text-ink-secondary">
          Issuing a new code cancels the old one. One or more selected members already have an active code.
          Are you sure you want to proceed?
        </p>
      </Modal>

      {/* Confirmation Modal: Revoke code */}
      <Modal
        open={!!memberToRevoke}
        onClose={() => setMemberToRevoke(null)}
        title="Revoke Claim Code"
        size="md"
        footer={
          <>
            <Button
              type="button"
              variant="outline"
              onClick={() => setMemberToRevoke(null)}
              disabled={revokeMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="danger"
              onClick={handleRevokeConfirm}
              loading={revokeMutation.isPending}
            >
              Revoke Code
            </Button>
          </>
        }
      >
        <p className="text-small text-ink-secondary">
          Are you sure you want to revoke the active claim code for{' '}
          <strong className="text-ink">{memberToRevoke?.display_name}</strong>? They will no longer be able to use it to create their login.
        </p>
      </Modal>

      {/* Result Modal: Codes issued — shown only once */}
      <Modal
        open={!!issuedResult}
        onClose={() => setIssuedResult(null)}
        title="Codes issued — shown only once"
        size="lg"
        closeOnBackdrop={false}
        footer={
          <div className="flex w-full items-center justify-between">
            <div className="flex items-center gap-2">
              <Button
                type="button"
                variant="outline"
                onClick={handleCopyAll}
                className="gap-1.5"
              >
                {copiedAll ? <Check className="h-4 w-4 text-success-700" /> : <Copy className="h-4 w-4" />}
                {copiedAll ? 'Copied!' : 'Copy all'}
              </Button>
              <Button
                type="button"
                variant="outline"
                onClick={handlePrint}
                className="gap-1.5"
              >
                <Printer className="h-4 w-4" />
                Print
              </Button>
            </div>
            <Button
              type="button"
              variant="primary"
              onClick={() => setIssuedResult(null)}
            >
              Done
            </Button>
          </div>
        }
      >
        <div className="space-y-4">
          <Alert variant="warning" title="Save these codes now">
            These one-time codes will not be displayed again in full. Copy or print them now before closing this window.
          </Alert>

          {issuedResult?.issued && issuedResult.issued.length > 0 && (
            <div className="max-h-80 overflow-y-auto rounded-card border border-line">
              <table className="w-full border-collapse text-left text-small">
                <thead className="sticky top-0 border-b border-line bg-surface-muted text-xs font-semibold text-ink-secondary">
                  <tr>
                    <th className="px-3 py-2">Name</th>
                    <th className="px-3 py-2">Member #</th>
                    <th className="px-3 py-2 font-mono">Code</th>
                    <th className="px-3 py-2">Expires</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-line">
                  {issuedResult.issued.map((item) => (
                    <tr key={item.member_id} className="hover:bg-surface-muted/40">
                      <td className="px-3 py-2 font-medium text-ink">{item.display_name}</td>
                      <td className="px-3 py-2 font-mono text-xs text-ink-secondary">
                        {item.member_number || '—'}
                      </td>
                      <td className="px-3 py-2">
                        <span className="font-mono text-base font-bold tracking-widest text-primary">
                          {item.code}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-ink-secondary">
                        {formatDate(item.expires_at)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {/* Skipped members list */}
          {issuedResult?.skipped && issuedResult.skipped.length > 0 && (
            <div className="rounded-card border border-line bg-surface-muted p-3">
              <p className="text-xs font-semibold text-ink-secondary mb-2">
                Skipped ({issuedResult.skipped.length} {issuedResult.skipped.length === 1 ? 'member' : 'members'}):
              </p>
              <ul className="space-y-1 text-xs text-ink-muted">
                {issuedResult.skipped.map((s, idx) => {
                  const m = members.find((x) => x.member_id === s.member_id);
                  const reasonLabel = REASON_LABELS[s.reason] || s.reason;
                  return (
                    <li key={idx} className="flex items-center gap-1.5">
                      <span className="text-ink font-medium">{m?.display_name || s.member_id}</span>
                      <span>— {reasonLabel}</span>
                    </li>
                  );
                })}
              </ul>
            </div>
          )}
        </div>
      </Modal>
    </div>
  );
}

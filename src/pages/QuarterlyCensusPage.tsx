import { useMemo, useState } from 'react';
import {
  Calendar,
  CheckCircle2,
  ChevronRight,
  Eye,
  FileCheck2,
  FileText,
  Lock,
  RefreshCw,
  RotateCcw,
  ShieldCheck,
  Users,
} from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import {
  useCensusPreview,
  useReportingPeriods,
  useReportingPeriod,
  useCreateDraftPeriod,
  useCaptureCensusSnapshot,
  useSetReportingPeriodStatus,
} from '../features/reports/queries';
import { ApproveCensusModal } from '../features/reports/components/ApproveCensusModal';
import {
  Alert,
  Badge,
  Button,
  Card,
  PageHeader,
  Select,
  Skeleton,
  StatCard,
} from '../components/ui';
import { formatNyDateShort, formatNyTime } from '../lib/ny-time';
import type { SectionCensusItem } from '../features/reports/types';

function formatTimestamp(iso: string | null | undefined): string {
  if (!iso) return '—';
  return `${formatNyDateShort(iso)} at ${formatNyTime(iso)}`;
}

function formatChange(change: number | null | undefined, percent: number | null | undefined): string {
  if (change === null || change === undefined) return '—';
  const sign = change > 0 ? '+' : '';
  const pctStr = percent !== null && percent !== undefined ? ` (${sign}${percent}%)` : '';
  return `${sign}${change}${pctStr}`;
}

const QUARTER_MONTHS: Record<number, string> = {
  1: 'Jan 1 – Mar 31',
  2: 'Apr 1 – Jun 30',
  3: 'Jul 1 – Sep 30',
  4: 'Oct 1 – Dec 31',
};

const YEAR_OPTIONS = [2025, 2026, 2027, 2028];
const QUARTER_OPTIONS = [
  { value: 1, label: 'Q1 (Jan 1 – Mar 31)' },
  { value: 2, label: 'Q2 (Apr 1 – Jun 30)' },
  { value: 3, label: 'Q3 (Jul 1 – Sep 30)' },
  { value: 4, label: 'Q4 (Oct 1 – Dec 31)' },
];

export default function QuarterlyCensusPage() {
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const orgId = activeOrganization?.id ?? null;

  const canViewReports = !isPermLoading && hasPermission(Permissions.ReportsCensusView);
  const canManageReports = !isPermLoading && hasPermission(Permissions.ReportsCensusManage);
  const canApproveReports = !isPermLoading && hasPermission(Permissions.ReportsCensusApprove);

  // Default to current year and quarter
  const now = new Date();
  const currentYear = now.getFullYear();
  const currentQuarter = Math.floor(now.getMonth() / 3) + 1;

  const [selectedYear, setSelectedYear] = useState<number>(currentYear);
  const [selectedQuarter, setSelectedQuarter] = useState<number>(currentQuarter);
  const [showLivePreview, setShowLivePreview] = useState<boolean>(false);
  const [isApproveModalOpen, setIsApproveModalOpen] = useState<boolean>(false);
  const [actionError, setActionError] = useState<string | null>(null);

  // Queries
  const { data: periodsList, isLoading: isPeriodsLoading } = useReportingPeriods(
    canViewReports ? orgId : null
  );

  // Check if a period already exists for selected year/quarter
  const matchingPeriodSummary = useMemo(() => {
    return periodsList?.find(
      (p) => p.period_year === selectedYear && p.period_quarter === selectedQuarter
    );
  }, [periodsList, selectedYear, selectedQuarter]);

  const activePeriodId = matchingPeriodSummary?.id ?? null;

  // Period detail (persisted snapshot) if period exists
  const {
    data: periodDetail,
    isLoading: isDetailLoading,
  } = useReportingPeriod(activePeriodId, canViewReports && !!activePeriodId);

  // Live preview query
  const {
    data: livePreview,
    isLoading: isPreviewLoading,
    refetch: refetchPreview,
  } = useCensusPreview(
    canViewReports ? orgId : null,
    selectedYear,
    selectedQuarter,
    canViewReports && (showLivePreview || !activePeriodId)
  );

  // Mutations
  const createDraftMutation = useCreateDraftPeriod();
  const captureSnapshotMutation = useCaptureCensusSnapshot();
  const setStatusMutation = useSetReportingPeriodStatus();

  const isMutating =
    createDraftMutation.isPending ||
    captureSnapshotMutation.isPending ||
    setStatusMutation.isPending;

  // Current display data: either snapshot from periodDetail or livePreview
  const isPeriodExisting = !!periodDetail?.period;
  const periodStatus = periodDetail?.period?.status ?? null;
  const isApproved = periodStatus === 'approved';
  const isReview = periodStatus === 'review';
  const isDraft = periodStatus === 'draft';

  // Use snapshot when existing and not explicitly toggled to preview
  const displaySource = isPeriodExisting && !showLivePreview ? 'snapshot' : 'preview';
  const totalActiveMembers =
    displaySource === 'snapshot'
      ? (periodDetail?.snapshot?.total_active_members ?? 0)
      : (livePreview?.total_active_members ?? 0);

  const uncategorizedMembers =
    displaySource === 'snapshot'
      ? (periodDetail?.snapshot?.uncategorized_active_members ?? 0)
      : (livePreview?.uncategorized_active_members ?? 0);

  const sectionsList: SectionCensusItem[] = useMemo(() => {
    if (displaySource === 'snapshot') {
      return periodDetail?.sections ?? [];
    }
    return livePreview?.sections ?? [];
  }, [displaySource, periodDetail, livePreview]);

  // Group sections by branch (MFC vs FMC)
  const branchGroups = useMemo(() => {
    const groups: Record<string, { branchName: string; items: SectionCensusItem[]; totalCount: number }> = {};

    sectionsList.forEach((sec) => {
      const branchKey = sec.branch_name || 'Other';
      if (!groups[branchKey]) {
        groups[branchKey] = {
          branchName: branchKey,
          items: [],
          totalCount: 0,
        };
      }
      groups[branchKey].items.push(sec);
      groups[branchKey].totalCount += sec.current_count;
    });

    // Sort: MFC New York first, FMC New York second, others after
    return Object.values(groups).sort((a, b) => {
      if (a.branchName.toLowerCase().includes('mfc')) return -1;
      if (b.branchName.toLowerCase().includes('mfc')) return 1;
      if (a.branchName.toLowerCase().includes('fmc')) return -1;
      if (b.branchName.toLowerCase().includes('fmc')) return 1;
      return a.branchName.localeCompare(b.branchName);
    });
  }, [sectionsList]);

  // Calculate sum of section counts to verify reconciliation
  const sumSectionCounts = useMemo(() => {
    return sectionsList.reduce((acc, s) => acc + s.current_count, 0);
  }, [sectionsList]);

  const isReconciled = sumSectionCounts + uncategorizedMembers === totalActiveMembers;

  const comparison =
    displaySource === 'snapshot' ? periodDetail?.comparison : livePreview?.comparison;
  const prevQuarter =
    displaySource === 'snapshot' ? periodDetail?.previous_quarter : livePreview?.previous_quarter;

  // Handlers
  const handleCreateDraft = async () => {
    if (!orgId) return;
    setActionError(null);
    try {
      await createDraftMutation.mutateAsync({
        orgId,
        year: selectedYear,
        quarter: selectedQuarter,
      });
      setShowLivePreview(false);
    } catch (err: unknown) {
      setActionError(err instanceof Error ? err.message : 'Failed to create draft period');
    }
  };

  const handleRefreshSnapshot = async () => {
    if (!activePeriodId) return;
    setActionError(null);
    try {
      await captureSnapshotMutation.mutateAsync(activePeriodId);
      setShowLivePreview(false);
    } catch (err: unknown) {
      setActionError(err instanceof Error ? err.message : 'Failed to refresh snapshot');
    }
  };

  const handleSetStatus = async (status: 'draft' | 'review' | 'approved') => {
    if (!activePeriodId) return;
    setActionError(null);
    try {
      await setStatusMutation.mutateAsync({ periodId: activePeriodId, status });
      if (status === 'approved') {
        setIsApproveModalOpen(false);
      }
    } catch (err: unknown) {
      setActionError(err instanceof Error ? err.message : `Failed to update status to ${status}`);
    }
  };

  if (isPermLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  if (!canViewReports) {
    return (
      <div className="space-y-4">
        <PageHeader title="Quarterly Census" />
        <Alert variant="danger">
          Access restricted: you do not have permission to view ministry reports.
        </Alert>
      </div>
    );
  }

  const isLoadingData = isPeriodsLoading || (activePeriodId ? isDetailLoading : isPreviewLoading);

  return (
    <div className="space-y-6">
      {/* Header */}
      <PageHeader
        title="Quarterly Census Report"
        description="National ministry membership census snapshots and quarter-over-quarter growth breakdown."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            {/* View live preview toggle when snapshot exists */}
            {isPeriodExisting && (
              <Button
                variant={showLivePreview ? 'secondary' : 'ghost'}
                size="sm"
                onClick={() => {
                  setShowLivePreview((v) => !v);
                  if (!showLivePreview) void refetchPreview();
                }}
                disabled={isMutating}
              >
                <Eye className="mr-1.5 h-4 w-4" />
                {showLivePreview ? 'Back to Saved Snapshot' : 'Preview Live Census'}
              </Button>
            )}

            {/* Actions for draft period */}
            {isDraft && canManageReports && (
              <>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={handleRefreshSnapshot}
                  loading={captureSnapshotMutation.isPending}
                  disabled={isMutating}
                >
                  <RefreshCw className="mr-1.5 h-4 w-4" />
                  Refresh Snapshot
                </Button>
                <Button
                  variant="primary"
                  size="sm"
                  onClick={() => handleSetStatus('review')}
                  loading={setStatusMutation.isPending}
                  disabled={isMutating}
                >
                  Move to Review
                  <ChevronRight className="ml-1.5 h-4 w-4" />
                </Button>
              </>
            )}

            {/* Actions for review period */}
            {isReview && (
              <>
                {canManageReports && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleSetStatus('draft')}
                    loading={setStatusMutation.isPending}
                    disabled={isMutating}
                  >
                    <RotateCcw className="mr-1.5 h-4 w-4" />
                    Return to Draft
                  </Button>
                )}
                {canApproveReports && (
                  <Button
                    variant="primary"
                    size="sm"
                    onClick={() => setIsApproveModalOpen(true)}
                    loading={setStatusMutation.isPending}
                    disabled={isMutating}
                  >
                    <ShieldCheck className="mr-1.5 h-4 w-4" />
                    Approve Census
                  </Button>
                )}
              </>
            )}

            {/* Create draft if period does not exist */}
            {!isPeriodExisting && canManageReports && (
              <Button
                variant="primary"
                size="sm"
                onClick={handleCreateDraft}
                loading={createDraftMutation.isPending}
                disabled={isMutating}
              >
                <FileCheck2 className="mr-1.5 h-4 w-4" />
                Create Draft & Capture Snapshot
              </Button>
            )}
          </div>
        }
      />

      {/* Error alert */}
      {actionError && (
        <Alert variant="danger">
          {actionError}
        </Alert>
      )}

      {/* Period Selection Bar */}
      <Card className="p-4 sm:p-5">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-wrap items-center gap-3">
            <div className="w-32">
              <label htmlFor="select-year" className="block text-caption font-medium text-ink-muted mb-1">
                Reporting Year
              </label>
              <Select
                id="select-year"
                value={selectedYear}
                onChange={(e) => setSelectedYear(Number(e.target.value))}
              >
                {YEAR_OPTIONS.map((y) => (
                  <option key={y} value={y}>
                    {y}
                  </option>
                ))}
              </Select>
            </div>

            <div className="w-56">
              <label htmlFor="select-quarter" className="block text-caption font-medium text-ink-muted mb-1">
                Quarter
              </label>
              <Select
                id="select-quarter"
                value={selectedQuarter}
                onChange={(e) => setSelectedQuarter(Number(e.target.value))}
              >
                {QUARTER_OPTIONS.map((q) => (
                  <option key={q.value} value={q.value}>
                    {q.label}
                  </option>
                ))}
              </Select>
            </div>
          </div>

          {/* Status & Period Info Badge */}
          <div className="flex flex-col items-start sm:items-end gap-1">
            <div className="flex items-center gap-2">
              <span className="text-caption text-ink-muted">Quarter Window:</span>
              <span className="text-caption font-semibold text-ink">
                {QUARTER_MONTHS[selectedQuarter]}, {selectedYear}
              </span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-caption text-ink-muted">Period Status:</span>
              {isApproved && <Badge variant="success">Approved (Frozen)</Badge>}
              {isReview && <Badge variant="info">In Review</Badge>}
              {isDraft && <Badge variant="warning">Draft Period</Badge>}
              {!isPeriodExisting && <Badge variant="neutral">Not Created (Live Preview)</Badge>}
            </div>
          </div>
        </div>
      </Card>

      {/* Status Notice Banners */}
      {showLivePreview && isPeriodExisting && (
        <div className="flex items-center justify-between rounded-lg border border-info-200 bg-info-50 p-3.5 text-sm text-info-900">
          <div className="flex items-center gap-2">
            <Eye className="h-4 w-4 text-info-700 shrink-0" />
            <span>
              <strong>Previewing Live Data:</strong> Currently showing real-time database numbers as of today.
            </span>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setShowLivePreview(false)}
            className="text-info-900 underline font-medium"
          >
            Show Saved Snapshot
          </Button>
        </div>
      )}

      {isApproved && (
        <div className="flex items-center gap-3 rounded-lg border border-success-200 bg-success-50 p-4 text-sm text-success-900">
          <Lock className="h-5 w-5 text-success-700 shrink-0" />
          <div className="space-y-0.5">
            <p className="font-semibold text-ink">
              Official Approved Census Snapshot (Frozen)
            </p>
            <p className="text-caption text-ink-muted">
              Approved on {formatTimestamp(periodDetail?.period?.approved_at)}
              {periodDetail?.period?.approved_by_name ? ` by ${periodDetail.period.approved_by_name}` : ''}.
              This census snapshot is permanently locked against automatic member record modifications.
            </p>
          </div>
        </div>
      )}

      {isReview && !showLivePreview && (
        <div className="flex items-center gap-3 rounded-lg border border-info-200 bg-info-50 p-4 text-sm text-info-900">
          <FileText className="h-5 w-5 text-info-700 shrink-0" />
          <div className="space-y-0.5">
            <p className="font-semibold text-ink">Quarterly Report In Review</p>
            <p className="text-caption text-ink-muted">
              Snapshot captured on {formatTimestamp(periodDetail?.snapshot?.captured_at)}.
              Live changes to member profiles will not alter these numbers while under review. Return to draft if a refresh is needed.
            </p>
          </div>
        </div>
      )}

      {isDraft && !showLivePreview && (
        <div className="flex items-center gap-3 rounded-lg border border-warning-200 bg-warning-50 p-4 text-sm text-warning-900">
          <RefreshCw className="h-5 w-5 text-warning-700 shrink-0" />
          <div className="space-y-0.5">
            <p className="font-semibold text-ink">Draft Snapshot Captured</p>
            <p className="text-caption text-ink-muted">
              Last captured on {formatTimestamp(periodDetail?.snapshot?.captured_at)}.
              Use <strong>Refresh Snapshot</strong> at any time to synchronize this draft with recent member additions or transfers before submitting for review.
            </p>
          </div>
        </div>
      )}

      {/* Summary KPI Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label="Total Active Members"
          value={isLoadingData ? '…' : totalActiveMembers.toLocaleString()}
          context={
            comparison && comparison.change_total !== null
              ? `${formatChange(comparison.change_total, comparison.change_percent_total)} vs ${prevQuarter?.period_year} Q${prevQuarter?.period_quarter}`
              : undefined
          }
          icon={<Users className="h-4 w-4" />}
        />

        <StatCard
          label="Active Sections"
          value={isLoadingData ? '…' : sectionsList.length}
          icon={<Calendar className="h-4 w-4" />}
        />

        <StatCard
          label="Uncategorized Active"
          value={isLoadingData ? '…' : uncategorizedMembers}
          icon={<Users className="h-4 w-4" />}
        />

        <Card className="flex flex-col justify-between p-4">
          <div className="text-caption font-medium text-ink-muted">Census Reconciliation</div>
          <div className="mt-2 flex items-center gap-2">
            {isReconciled ? (
              <>
                <CheckCircle2 className="h-5 w-5 text-success-600" />
                <span className="text-sm font-semibold text-success-700">100% Reconciled</span>
              </>
            ) : (
              <span className="text-sm font-semibold text-danger-700">Reconciliation Mismatch</span>
            )}
          </div>
          <div className="mt-1 text-xs text-ink-muted">
            Sections ({sumSectionCounts}) + Uncat ({uncategorizedMembers}) = {totalActiveMembers}
          </div>
        </Card>
      </div>

      {/* Section Breakdown Table */}
      <Card className="overflow-hidden">
        <div className="border-b border-line px-5 py-4">
          <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 className="text-section-title font-semibold text-ink">
                Section-Level Census Breakdown
              </h2>
              <p className="text-caption text-ink-muted">
                Active member count by canonical section, categorized under parallel governance branches (MFC vs FMC).
              </p>
            </div>
            {prevQuarter && (
              <div className="text-caption text-ink-muted">
                Comparison baseline: <strong className="text-ink">{prevQuarter.period_year} Q{prevQuarter.period_quarter} Approved</strong>
              </div>
            )}
          </div>
        </div>

        {isLoadingData ? (
          <div className="space-y-3 p-5">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="bg-surface-muted/60 text-xs font-semibold text-ink-muted uppercase tracking-wider border-b border-line">
                <tr>
                  <th scope="col" className="px-5 py-3">Section</th>
                  <th scope="col" className="px-5 py-3">Category</th>
                  <th scope="col" className="px-5 py-3 text-right">
                    {displaySource === 'snapshot' ? 'Snapshot Count' : 'Live Preview'}
                  </th>
                  <th scope="col" className="px-5 py-3 text-right">
                    {prevQuarter ? `${prevQuarter.period_year} Q${prevQuarter.period_quarter}` : 'Prev Quarter'}
                  </th>
                  <th scope="col" className="px-5 py-3 text-right">Quarter Change</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {branchGroups.map((group) => (
                  <div key={group.branchName} style={{ display: 'contents' }}>
                    {/* Branch Group Header */}
                    <tr className="bg-surface-muted/30">
                      <td colSpan={2} className="px-5 py-2.5 font-bold text-xs uppercase tracking-wide text-ink-secondary">
                        {group.branchName}
                      </td>
                      <td className="px-5 py-2.5 text-right font-bold text-xs text-ink-secondary">
                        {group.totalCount} members
                      </td>
                      <td colSpan={2} className="px-5 py-2.5"></td>
                    </tr>

                    {/* Section Rows */}
                    {group.items.map((sec) => (
                      <tr key={sec.section_node_id} className="hover:bg-surface-muted/20 transition-colors">
                        <td className="px-5 py-3 font-medium text-ink pl-8">
                          {sec.section_name}
                        </td>
                        <td className="px-5 py-3 capitalize text-ink-muted">
                          {sec.section_category ? (
                            <Badge variant="neutral">{sec.section_category}</Badge>
                          ) : (
                            '—'
                          )}
                        </td>
                        <td className="px-5 py-3 text-right font-semibold text-ink tabular-nums">
                          {sec.current_count}
                        </td>
                        <td className="px-5 py-3 text-right text-ink-muted tabular-nums">
                          {sec.previous_count !== null ? sec.previous_count : '—'}
                        </td>
                        <td className="px-5 py-3 text-right tabular-nums">
                          {sec.change_count !== null ? (
                            <span
                              className={
                                sec.change_count > 0
                                  ? 'font-medium text-success-700'
                                  : sec.change_count < 0
                                  ? 'font-medium text-danger-700'
                                  : 'text-ink-muted'
                              }
                            >
                              {formatChange(sec.change_count, sec.change_percent)}
                            </span>
                          ) : (
                            <span className="text-ink-muted">—</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </div>
                ))}

                {/* Uncategorized Row */}
                <tr className="bg-surface-muted/10 font-medium">
                  <td className="px-5 py-3 text-ink-muted italic pl-8">
                    Uncategorized Active Members
                  </td>
                  <td className="px-5 py-3 text-caption text-ink-muted">
                    {uncategorizedMembers > 0 ? (
                      <Badge variant="warning">Requires Placement</Badge>
                    ) : (
                      <span className="text-ink-muted">None</span>
                    )}
                  </td>
                  <td className="px-5 py-3 text-right font-semibold text-ink tabular-nums">
                    {uncategorizedMembers}
                  </td>
                  <td className="px-5 py-3 text-right text-ink-muted tabular-nums">—</td>
                  <td className="px-5 py-3 text-right text-ink-muted tabular-nums">—</td>
                </tr>
              </tbody>
              <tfoot className="border-t-2 border-line bg-surface-muted/40 font-bold text-sm">
                <tr>
                  <td colSpan={2} className="px-5 py-3.5 text-ink">
                    Total Active Membership Census
                  </td>
                  <td className="px-5 py-3.5 text-right text-ink tabular-nums font-extrabold text-base">
                    {totalActiveMembers}
                  </td>
                  <td className="px-5 py-3.5 text-right text-ink-muted tabular-nums">
                    {comparison?.previous_total ?? '—'}
                  </td>
                  <td className="px-5 py-3.5 text-right tabular-nums">
                    {comparison?.change_total !== null && comparison?.change_total !== undefined ? (
                      <span
                        className={
                          comparison.change_total > 0
                            ? 'text-success-700'
                            : comparison.change_total < 0
                            ? 'text-danger-700'
                            : 'text-ink-muted'
                        }
                      >
                        {formatChange(comparison.change_total, comparison.change_percent_total)}
                      </span>
                    ) : (
                      '—'
                    )}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </Card>

      {/* Historical Reporting Periods Table */}
      {periodsList && periodsList.length > 0 && (
        <Card className="overflow-hidden">
          <div className="border-b border-line px-5 py-4">
            <h3 className="text-section-title font-semibold text-ink">
              Recorded Quarterly Reporting Periods
            </h3>
            <p className="text-caption text-ink-muted">
              History of draft, review, and approved quarterly ministry reports in this organization.
            </p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="bg-surface-muted/60 text-xs font-semibold text-ink-muted uppercase tracking-wider border-b border-line">
                <tr>
                  <th scope="col" className="px-5 py-3">Period</th>
                  <th scope="col" className="px-5 py-3">Calendar Window</th>
                  <th scope="col" className="px-5 py-3">Status</th>
                  <th scope="col" className="px-5 py-3 text-right">Active Members</th>
                  <th scope="col" className="px-5 py-3">Snapshot Captured</th>
                  <th scope="col" className="px-5 py-3">Approval</th>
                  <th scope="col" className="px-5 py-3 text-right">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {periodsList.map((p) => {
                  const isSelected = p.period_year === selectedYear && p.period_quarter === selectedQuarter;
                  return (
                    <tr
                      key={p.id}
                      className={isSelected ? 'bg-surface-muted/40 font-medium' : 'hover:bg-surface-muted/10'}
                    >
                      <td className="px-5 py-3 font-semibold text-ink">
                        {p.period_year} Q{p.period_quarter}
                      </td>
                      <td className="px-5 py-3 text-ink-muted text-xs">
                        {p.period_start} to {p.period_end}
                      </td>
                      <td className="px-5 py-3">
                        {p.status === 'approved' && <Badge variant="success">Approved</Badge>}
                        {p.status === 'review' && <Badge variant="info">In Review</Badge>}
                        {p.status === 'draft' && <Badge variant="warning">Draft</Badge>}
                      </td>
                      <td className="px-5 py-3 text-right font-semibold text-ink tabular-nums">
                        {p.snapshot?.total_active_members ?? '—'}
                      </td>
                      <td className="px-5 py-3 text-xs text-ink-muted">
                        {formatTimestamp(p.snapshot?.captured_at)}
                      </td>
                      <td className="px-5 py-3 text-xs text-ink-muted">
                        {p.approved_at ? (
                          <span>
                            {formatTimestamp(p.approved_at)}
                            {p.approved_by_name ? ` (${p.approved_by_name})` : ''}
                          </span>
                        ) : (
                          '—'
                        )}
                      </td>
                      <td className="px-5 py-3 text-right">
                        {!isSelected ? (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => {
                              setSelectedYear(p.period_year);
                              setSelectedQuarter(p.period_quarter);
                              setShowLivePreview(false);
                            }}
                          >
                            View
                          </Button>
                        ) : (
                          <span className="text-xs font-semibold text-primary">Selected</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* Approval Warning Modal */}
      <ApproveCensusModal
        open={isApproveModalOpen}
        onClose={() => setIsApproveModalOpen(false)}
        onConfirm={() => handleSetStatus('approved')}
        isSubmitting={setStatusMutation.isPending}
        periodYear={selectedYear}
        periodQuarter={selectedQuarter}
        totalMembers={totalActiveMembers}
      />
    </div>
  );
}

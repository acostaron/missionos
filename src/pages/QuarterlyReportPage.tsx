import { useMemo, useState } from 'react';
import { CheckCircle2, Download, FileSpreadsheet, RefreshCw, RotateCcw, Send } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { Alert, Badge, Button, Card, EmptyState, PageHeader, Skeleton } from '../components/ui';
import {
  useApproveQuarterlyReport,
  useQuarterlyReportPreview,
  useQuarterlyReports,
  useRefreshQuarterlyDraft,
  useReturnQuarterlyReport,
  useSubmitQuarterlyReport,
} from '../features/quarterly-reports/queries';
import { QuarterSelector } from '../features/quarterly-reports/components/QuarterSelector';
import { ReportReadiness } from '../features/quarterly-reports/components/ReportReadiness';
import { QuarterlyReportPreview } from '../features/quarterly-reports/components/QuarterlyReportPreview';
import { ApproveQuarterlyReportModal } from '../features/quarterly-reports/components/ApproveQuarterlyReportModal';
import { exportQuarterlyReport } from '../features/quarterly-reports/exports/run-export';
import { STATUS_BADGE, formatTimestamp } from '../features/quarterly-reports/format';

const SOURCE_LABEL: Record<string, string> = {
  approved_snapshot: 'Approved snapshot (frozen)',
  review_draft: 'Draft frozen for review',
  stored_draft: 'Saved draft',
  live_preview: 'Live preview (not yet saved as a draft)',
};

function errorMessage(e: unknown): string {
  if (e && typeof e === 'object' && 'message' in e) return String((e as { message: unknown }).message);
  return 'Something went wrong.';
}

export default function QuarterlyReportPage() {
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const orgId = activeOrganization?.id ?? null;
  const canView = !isPermLoading && hasPermission(Permissions.ReportsQuarterlyView);

  const { data: list, isLoading: isListLoading, error: listError } = useQuarterlyReports(canView ? orgId : null);
  const periods = useMemo(
    () => [...(list?.periods ?? [])].sort((a, b) => b.period_year - a.period_year || b.period_quarter - a.period_quarter),
    [list]
  );
  const [chosenId, setChosenId] = useState<string | null>(null);
  const selectedId = chosenId ?? periods[0]?.reporting_period_id ?? null;

  const { data: preview, isLoading: isPreviewLoading, error: previewError } = useQuarterlyReportPreview(
    canView ? selectedId : null
  );

  const refresh = useRefreshQuarterlyDraft();
  const submit = useSubmitQuarterlyReport();
  const reopen = useReturnQuarterlyReport();
  const approve = useApproveQuarterlyReport();
  const [approveOpen, setApproveOpen] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [exportNote, setExportNote] = useState<{ variant: 'success' | 'warning'; text: string } | null>(null);
  const [exporting, setExporting] = useState<'pdf' | 'xlsx' | null>(null);

  if (isPermLoading) return <Skeleton className="h-40" />;
  if (!canView) {
    return (
      <Alert variant="warning" title="Access restricted">
        You do not have permission to view quarterly national reports.
      </Alert>
    );
  }

  const status = preview?.report.status ?? 'not_started';
  const doc = preview?.document;
  const canManage = !!preview?.can_manage;
  const canApprove = !!preview?.can_approve;
  const isApproved = status === 'approved';
  const stage = isApproved ? 'official' : status === 'review' ? 'review' : 'draft';
  const stageLabel = isApproved ? 'Official' : status === 'review' ? 'Review' : 'Draft';
  const blocked = !!doc && (!doc.readiness.blocking.census_snapshot_exists || !doc.readiness.blocking.census_approved);
  const busy = refresh.isPending || submit.isPending || reopen.isPending || approve.isPending;

  const run = async (fn: () => Promise<unknown>) => {
    setActionError(null);
    try {
      await fn();
    } catch (e) {
      setActionError(errorMessage(e));
    }
  };

  const doExport = async (format: 'pdf' | 'xlsx') => {
    if (!doc || !selectedId) return;
    setExporting(format);
    setExportNote(null);
    try {
      const out = await exportQuarterlyReport(selectedId, doc, format, stage);
      setExportNote(
        out.warnings.length
          ? { variant: 'warning', text: `${out.filename} downloaded with ${out.warnings.length} warning(s): ${out.warnings.join('; ')}` }
          : { variant: 'success', text: `${out.filename} downloaded.` }
      );
    } catch (e) {
      setExportNote({ variant: 'warning', text: `Export failed: ${errorMessage(e)}` });
    } finally {
      setExporting(null);
    }
  };

  return (
    <div className="space-y-4">
      <PageHeader
        title="Quarterly National Report"
        description="Review, approve, and export the quarterly report for national leadership."
      />

      {listError && <Alert variant="danger">{errorMessage(listError)}</Alert>}
      {isListLoading ? (
        <Skeleton className="h-16" />
      ) : periods.length === 0 ? (
        <EmptyState
          title="No reporting periods yet"
          message="Create the quarter's reporting period and census snapshot on the Quarterly Census page first."
        />
      ) : (
        <Card>
          <QuarterSelector periods={periods} selectedId={selectedId} onSelect={setChosenId} />
        </Card>
      )}

      {previewError && <Alert variant="danger">{errorMessage(previewError)}</Alert>}
      {selectedId && isPreviewLoading && <Skeleton className="h-64" />}

      {preview && doc && (
        <>
          <Card>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="text-xs uppercase tracking-wide text-slate-500">{doc.header.organization_name}</p>
                <h2 className="text-lg font-semibold text-slate-900">
                  {doc.header.area_name} · {doc.header.period_label}
                </h2>
                <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-slate-500">
                  <Badge variant={STATUS_BADGE[status].variant}>{STATUS_BADGE[status].label}</Badge>
                  <span>{SOURCE_LABEL[preview.document_source]}</span>
                  <span>· Generated {formatTimestamp(doc.header.generated_at)}</span>
                  {preview.report.approved_at && (
                    <span>
                      · Approved {formatTimestamp(preview.report.approved_at)} by {preview.report.approved_by_name ?? '—'}
                    </span>
                  )}
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                {canManage && (status === 'not_started' || status === 'draft') && (
                  <Button
                    id="refresh-quarterly-draft"
                    variant="outline"
                    icon={<RefreshCw className="h-4 w-4" />}
                    loading={refresh.isPending}
                    disabled={busy}
                    onClick={() => run(() => refresh.mutateAsync(selectedId!))}
                  >
                    {status === 'not_started' ? 'Create Draft' : 'Refresh Draft'}
                  </Button>
                )}
                {canManage && status === 'draft' && (
                  <Button
                    id="submit-quarterly-review"
                    variant="secondary"
                    icon={<Send className="h-4 w-4" />}
                    loading={submit.isPending}
                    disabled={busy}
                    onClick={() => run(() => submit.mutateAsync(selectedId!))}
                  >
                    Submit for Review
                  </Button>
                )}
                {canManage && status === 'review' && (
                  <Button
                    id="return-quarterly-draft"
                    variant="ghost"
                    icon={<RotateCcw className="h-4 w-4" />}
                    loading={reopen.isPending}
                    disabled={busy}
                    onClick={() => run(() => reopen.mutateAsync(selectedId!))}
                  >
                    Return to Draft
                  </Button>
                )}
                {canApprove && status === 'review' && (
                  <Button
                    id="approve-quarterly-report"
                    icon={<CheckCircle2 className="h-4 w-4" />}
                    disabled={busy || blocked}
                    onClick={() => setApproveOpen(true)}
                  >
                    Approve Quarterly Report
                  </Button>
                )}
              </div>
            </div>
            <div className="mt-4 flex flex-wrap gap-2 border-t border-slate-100 pt-4">
              <Button
                id="download-quarterly-pdf"
                variant={isApproved ? 'primary' : 'outline'}
                icon={<Download className="h-4 w-4" />}
                loading={exporting === 'pdf'}
                disabled={!!exporting}
                onClick={() => doExport('pdf')}
              >
                {stageLabel} PDF
              </Button>
              <Button
                id="download-quarterly-excel"
                variant={isApproved ? 'primary' : 'outline'}
                icon={<FileSpreadsheet className="h-4 w-4" />}
                loading={exporting === 'xlsx'}
                disabled={!!exporting}
                onClick={() => doExport('xlsx')}
              >
                {stageLabel} Excel
              </Button>
              {!isApproved && (
                <p className="self-center text-xs text-slate-500">
                  {status === 'review'
                    ? 'Review exports use the frozen review document and are marked REVIEW; approval will publish this exact content.'
                    : 'Draft exports are marked DRAFT and are not for national submission.'}
                </p>
              )}
            </div>
          </Card>

          {actionError && <Alert variant="danger">{actionError}</Alert>}
          {exportNote && <Alert variant={exportNote.variant}>{exportNote.text}</Alert>}
          {isApproved && (
            <Alert variant="success" title="Approved">
              This report is frozen as the historical record for {doc.header.period_label}. Exports use the approved snapshot.
            </Alert>
          )}

          {!isApproved && <ReportReadiness doc={doc} />}
          <QuarterlyReportPreview doc={doc} />

          <ApproveQuarterlyReportModal
            open={approveOpen}
            periodLabel={doc.header.period_label}
            loading={approve.isPending}
            onClose={() => setApproveOpen(false)}
            onConfirm={() =>
              run(async () => {
                await approve.mutateAsync(selectedId!);
                setApproveOpen(false);
              })
            }
          />
        </>
      )}
    </div>
  );
}

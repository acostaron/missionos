import type { AnyReportActivity, QuarterlyReportStatus, ReportFormationItem, ReportPhoto, ReportPriority } from './types';

export const STATUS_BADGE: Record<
  QuarterlyReportStatus,
  { label: string; variant: 'neutral' | 'info' | 'warning' | 'success' }
> = {
  not_started: { label: 'Not started', variant: 'neutral' },
  draft: { label: 'Draft', variant: 'info' },
  review: { label: 'Review', variant: 'warning' },
  approved: { label: 'Approved', variant: 'success' },
};

/** PDF shows at most this many selected photos per activity; all remain in snapshot/Excel. */
export const PDF_PHOTOS_PER_ACTIVITY = 3;

export const COMPLETION_NOT_RECORDED = 'Completion data not recorded';
export const NONE_REPORTED = 'None reported this quarter';

export const PRIORITY_LABEL: Record<ReportPriority, string> = {
  major_highlight: 'Major highlight',
  ministry_activity: 'Ministry activity',
  routine: 'Routine',
};

export const SOURCE_KIND_LABEL: Record<ReportFormationItem['source_kind'], string> = {
  cls: 'CLS',
  lcs: 'LCS',
  formation: 'Formal Formation',
};

export function priorityLabel(p: ReportPriority | null | undefined): string {
  return p ? PRIORITY_LABEL[p] ?? p : '—';
}

export function humanize(code: string | null | undefined): string {
  if (!code) return '—';
  return code.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

/** Formats a YYYY-MM-DD local date without timezone shifting. */
export function formatDate(d: string | null | undefined): string {
  if (!d) return '—';
  const [y, m, day] = d.slice(0, 10).split('-').map(Number);
  if (!y || !m || !day) return d;
  return new Date(Date.UTC(y, m - 1, day)).toLocaleDateString('en-US', {
    timeZone: 'UTC',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export function formatDateRange(a: string | null | undefined, b: string | null | undefined): string {
  if (!a) return '—';
  if (!b || b.slice(0, 10) === a.slice(0, 10)) return formatDate(a);
  return `${formatDate(a)} – ${formatDate(b)}`;
}

export function formatTimestamp(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('en-US', {
    timeZone: 'America/New_York',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export function hierarchyLabel(a: AnyReportActivity): string {
  const parts = [a.branch_name, a.section_names?.length ? a.section_names.join(', ') : null, a.chapter_name].filter(
    Boolean
  );
  return parts.length ? parts.join(' · ') : a.audience_name ?? '—';
}

export function completionLabel(f: ReportFormationItem): string {
  if (!f.completion_data_available || f.completion_count === null || f.completion_count === undefined) {
    return COMPLETION_NOT_RECORDED;
  }
  return String(f.completion_count);
}

export function participantsLabel(f: ReportFormationItem): string {
  if (!f.participant_count_is_authoritative || f.participant_count === null) return 'Not tracked';
  return String(f.participant_count);
}

export function sortedPhotos(photos: ReportPhoto[]): ReportPhoto[] {
  return [...photos].sort(
    (a, b) => (a.report_sort_order ?? Number.MAX_SAFE_INTEGER) - (b.report_sort_order ?? Number.MAX_SAFE_INTEGER)
  );
}

export type ExportStage = 'draft' | 'review' | 'official';

export const STAGE_STATUS_TEXT: Record<ExportStage, string> = {
  draft: 'DRAFT — not an approved submission',
  review: 'IN REVIEW — frozen for leader review, not yet approved',
  official: 'APPROVED — official record',
};

export const STAGE_WATERMARK: Record<ExportStage, string> = { draft: ' · DRAFT', review: ' · REVIEW', official: '' };

export const STAGE_SHEET_STATUS: Record<ExportStage, string> = { draft: 'Draft', review: 'Review (frozen)', official: 'Approved' };

/** Deterministic, sanitized export filename. */
export function reportFilename(year: number, quarter: number, ext: 'pdf' | 'xlsx', stage: ExportStage): string {
  const suffix = stage === 'draft' ? '_DRAFT' : stage === 'review' ? '_REVIEW' : '';
  const base = `MFCNY_Quarterly_Report_${year}_Q${quarter}${suffix}`;
  return `${base.replace(/[^A-Za-z0-9_-]/g, '_')}.${ext}`;
}

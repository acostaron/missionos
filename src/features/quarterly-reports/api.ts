import { supabase } from '../../lib/supabase/client';
import type { QuarterlyReportList, QuarterlyReportPreview, ReportState } from './types';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const rpc = (fn: string, args: Record<string, unknown>) => (supabase.rpc as any)(fn, args);

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await rpc(fn, args);
  if (error) throw error;
  return data as T;
}

export const fetchQuarterlyReports = (orgId: string) =>
  call<QuarterlyReportList>('list_quarterly_reports', { p_organization_id: orgId });

export const fetchQuarterlyReportPreview = (periodId: string) =>
  call<QuarterlyReportPreview>('get_quarterly_report_preview', { p_reporting_period_id: periodId });

export const refreshQuarterlyReportDraft = (periodId: string) =>
  call<unknown>('refresh_quarterly_report_draft', { p_reporting_period_id: periodId });

export const submitQuarterlyReportForReview = (periodId: string) =>
  call<unknown>('submit_quarterly_report_for_review', { p_reporting_period_id: periodId });

export const returnQuarterlyReportToDraft = (periodId: string) =>
  call<unknown>('return_quarterly_report_to_draft', { p_reporting_period_id: periodId });

export const approveQuarterlyReport = (periodId: string) =>
  call<unknown>('approve_quarterly_report', { p_reporting_period_id: periodId });

export const fetchQuarterlyReportSnapshot = (periodId: string) =>
  call<{ reporting_period_id: string; report: ReportState; document: QuarterlyReportPreview['document'] }>(
    'get_quarterly_report_snapshot',
    { p_reporting_period_id: periodId }
  );

export const recordQuarterlyReportExport = (periodId: string, format: 'pdf' | 'xlsx') =>
  call<unknown>('record_quarterly_report_export', { p_reporting_period_id: periodId, p_format: format });

/** Short-lived signed URL, used only in-memory during export/preview. Never persisted. */
export async function signPhotoUrl(bucket: string, path: string): Promise<string | null> {
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, 600);
  if (error || !data?.signedUrl) return null;
  return data.signedUrl;
}

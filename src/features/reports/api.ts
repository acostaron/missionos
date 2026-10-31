import { supabase } from '../../lib/supabase/client';
import type {
  CensusPreviewResult,
  ReportingPeriodDetail,
  ReportingPeriodStatus,
  ReportingPeriodSummary,
} from './types';

export async function fetchCensusPreview(
  orgId: string,
  year: number,
  quarter: number
): Promise<CensusPreviewResult> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)('get_quarterly_census_preview', {
    p_organization_id: orgId,
    p_year: year,
    p_quarter: quarter,
  });

  if (error) throw error;
  return data as CensusPreviewResult;
}

export async function fetchReportingPeriods(
  orgId: string
): Promise<ReportingPeriodSummary[]> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)('list_reporting_periods', {
    p_organization_id: orgId,
  });

  if (error) throw error;
  return (data ?? []) as ReportingPeriodSummary[];
}

export async function fetchReportingPeriod(
  periodId: string
): Promise<ReportingPeriodDetail> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)('get_reporting_period', {
    p_reporting_period_id: periodId,
  });

  if (error) throw error;
  return data as ReportingPeriodDetail;
}

export async function createDraftReportingPeriod(
  orgId: string,
  year: number,
  quarter: number,
  notes?: string
): Promise<ReportingPeriodDetail> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)('create_draft_reporting_period', {
    p_organization_id: orgId,
    p_year: year,
    p_quarter: quarter,
    p_notes: notes ?? null,
  });

  if (error) throw error;
  return data as ReportingPeriodDetail;
}

export async function captureCensusSnapshot(
  periodId: string
): Promise<ReportingPeriodDetail> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)('capture_quarterly_census_snapshot', {
    p_reporting_period_id: periodId,
  });

  if (error) throw error;
  return data as ReportingPeriodDetail;
}

export async function setReportingPeriodStatus(
  periodId: string,
  status: ReportingPeriodStatus
): Promise<ReportingPeriodDetail> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)('set_reporting_period_status', {
    p_reporting_period_id: periodId,
    p_status: status,
  });

  if (error) throw error;
  return data as ReportingPeriodDetail;
}

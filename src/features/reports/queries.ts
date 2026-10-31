import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  fetchCensusPreview,
  fetchReportingPeriods,
  fetchReportingPeriod,
  createDraftReportingPeriod,
  captureCensusSnapshot,
  setReportingPeriodStatus,
} from './api';
import type { ReportingPeriodStatus } from './types';

export const reportKeys = {
  all: ['reports'] as const,
  previews: () => [...reportKeys.all, 'preview'] as const,
  preview: (orgId: string | null, year: number, quarter: number) =>
    [...reportKeys.previews(), orgId, year, quarter] as const,
  periods: () => [...reportKeys.all, 'periods'] as const,
  periodsList: (orgId: string | null) => [...reportKeys.periods(), 'list', orgId] as const,
  periodDetail: (periodId: string | null) => [...reportKeys.periods(), 'detail', periodId] as const,
};

export function useCensusPreview(
  orgId: string | null,
  year: number,
  quarter: number,
  enabled = true
) {
  return useQuery({
    queryKey: reportKeys.preview(orgId, year, quarter),
    queryFn: () => {
      if (!orgId) throw new Error('Organization ID is required');
      return fetchCensusPreview(orgId, year, quarter);
    },
    enabled: Boolean(orgId) && enabled,
    staleTime: 30 * 1000,
  });
}

export function useReportingPeriods(orgId: string | null, enabled = true) {
  return useQuery({
    queryKey: reportKeys.periodsList(orgId),
    queryFn: () => {
      if (!orgId) throw new Error('Organization ID is required');
      return fetchReportingPeriods(orgId);
    },
    enabled: Boolean(orgId) && enabled,
    staleTime: 60 * 1000,
  });
}

export function useReportingPeriod(periodId: string | null, enabled = true) {
  return useQuery({
    queryKey: reportKeys.periodDetail(periodId),
    queryFn: () => {
      if (!periodId) throw new Error('Period ID is required');
      return fetchReportingPeriod(periodId);
    },
    enabled: Boolean(periodId) && enabled,
  });
}

export function useCreateDraftPeriod() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      orgId,
      year,
      quarter,
      notes,
    }: {
      orgId: string;
      year: number;
      quarter: number;
      notes?: string;
    }) => createDraftReportingPeriod(orgId, year, quarter, notes),
    onSuccess: (data, variables) => {
      queryClient.invalidateQueries({ queryKey: reportKeys.periodsList(variables.orgId) });
      queryClient.invalidateQueries({
        queryKey: reportKeys.preview(variables.orgId, variables.year, variables.quarter),
      });
      if (data?.period?.id) {
        queryClient.setQueryData(reportKeys.periodDetail(data.period.id), data);
      }
    },
  });
}

export function useCaptureCensusSnapshot() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (periodId: string) => captureCensusSnapshot(periodId),
    onSuccess: (data) => {
      if (data?.period?.id) {
        queryClient.setQueryData(reportKeys.periodDetail(data.period.id), data);
        queryClient.invalidateQueries({
          queryKey: reportKeys.periodsList(data.period.organization_id),
        });
        queryClient.invalidateQueries({
          queryKey: reportKeys.preview(
            data.period.organization_id,
            data.period.period_year,
            data.period.period_quarter
          ),
        });
      }
    },
  });
}

export function useSetReportingPeriodStatus() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      periodId,
      status,
    }: {
      periodId: string;
      status: ReportingPeriodStatus;
    }) => setReportingPeriodStatus(periodId, status),
    onSuccess: (data) => {
      if (data?.period?.id) {
        queryClient.setQueryData(reportKeys.periodDetail(data.period.id), data);
        queryClient.invalidateQueries({
          queryKey: reportKeys.periodsList(data.period.organization_id),
        });
        queryClient.invalidateQueries({
          queryKey: reportKeys.preview(
            data.period.organization_id,
            data.period.period_year,
            data.period.period_quarter
          ),
        });
      }
    },
  });
}

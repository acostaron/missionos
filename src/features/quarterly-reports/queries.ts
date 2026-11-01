import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  approveQuarterlyReport,
  fetchQuarterlyReportPreview,
  fetchQuarterlyReports,
  refreshQuarterlyReportDraft,
  returnQuarterlyReportToDraft,
  submitQuarterlyReportForReview,
} from './api';

export const quarterlyReportKeys = {
  all: ['quarterly-reports'] as const,
  list: (orgId: string | null) => [...quarterlyReportKeys.all, 'list', orgId] as const,
  preview: (periodId: string | null) => [...quarterlyReportKeys.all, 'preview', periodId] as const,
};

export function useQuarterlyReports(orgId: string | null) {
  return useQuery({
    queryKey: quarterlyReportKeys.list(orgId),
    queryFn: () => fetchQuarterlyReports(orgId as string),
    enabled: !!orgId,
  });
}

export function useQuarterlyReportPreview(periodId: string | null) {
  return useQuery({
    queryKey: quarterlyReportKeys.preview(periodId),
    queryFn: () => fetchQuarterlyReportPreview(periodId as string),
    enabled: !!periodId,
  });
}

function useWorkflowMutation(fn: (periodId: string) => Promise<unknown>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: quarterlyReportKeys.all }),
  });
}

export const useRefreshQuarterlyDraft = () => useWorkflowMutation(refreshQuarterlyReportDraft);
export const useSubmitQuarterlyReport = () => useWorkflowMutation(submitQuarterlyReportForReview);
export const useReturnQuarterlyReport = () => useWorkflowMutation(returnQuarterlyReportToDraft);
export const useApproveQuarterlyReport = () => useWorkflowMutation(approveQuarterlyReport);

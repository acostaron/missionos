import type {
  HouseholdFormationStatus,
  HouseholdTopicAssignmentStatus,
  HouseholdTopicReasonCode,
} from '../types';
import { formationKeys } from '../api/get-household-formation-plan';
import { householdKeys } from '../queries';
import { pastoralDashboardKeys } from '../api/get-pastoral-operations-dashboard';
import type { QueryClient } from '@tanstack/react-query';

export const FORMATION_STATUS_LABELS: Record<HouseholdFormationStatus, string> = {
  no_plan: 'No Plan',
  planned: 'Planned',
  topic_due: 'Topic Due',
  topic_overdue: 'Topic Overdue',
  up_to_date: 'Up To Date',
};

export const ASSIGNMENT_STATUS_LABELS: Record<HouseholdTopicAssignmentStatus, string> = {
  planned: 'Planned',
  completed: 'Completed',
  skipped: 'Skipped',
  cancelled: 'Cancelled',
};

export const REASON_CODE_LABELS: Record<HouseholdTopicReasonCode, string> = {
  schedule_change: 'Schedule change',
  topic_replaced: 'Topic replaced',
  not_applicable: 'Not applicable',
  other: 'Other',
};

export const REASON_CODE_OPTIONS = (
  Object.keys(REASON_CODE_LABELS) as HouseholdTopicReasonCode[]
).map((value) => ({ value, label: REASON_CODE_LABELS[value] }));

export function formatFormationLabel(map: Record<string, string>, value: string | null | undefined) {
  if (!value) return '—';
  return map[value] ?? value.replace(/_/g, ' ');
}

export async function invalidateFormationQueries(queryClient: QueryClient) {
  await Promise.all([
    queryClient.invalidateQueries({ queryKey: formationKeys.all }),
    queryClient.invalidateQueries({ queryKey: householdKeys.all }),
    queryClient.invalidateQueries({ queryKey: pastoralDashboardKeys.all }),
  ]);
}
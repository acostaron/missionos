import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import type { HouseholdMeetingHistory } from '../types';

export const meetingKeys = {
  all: ['household-meetings'] as const,
  history: (orgId: string, householdId: string, page?: number) =>
    [...meetingKeys.all, 'history', orgId, householdId, page ?? 0] as const,
  detail: (orgId: string, meetingId: string) =>
    [...meetingKeys.all, 'detail', orgId, meetingId] as const,
};

export async function getHouseholdMeetingHistory(
  organizationId: string,
  householdId: string,
  limit = 20,
  offset = 0
): Promise<HouseholdMeetingHistory> {
  const { data, error } = await supabase.rpc('get_household_meeting_history', {
    p_organization_id: organizationId,
    p_household_id: householdId,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) throw error;
  return data as unknown as HouseholdMeetingHistory;
}

export function useHouseholdMeetingHistory(
  organizationId: string | null,
  householdId: string | null,
  page = 0,
  pageSize = 20,
  enabled = true
) {
  return useQuery({
    queryKey:
      organizationId && householdId
        ? meetingKeys.history(organizationId, householdId, page)
        : ['household-meetings', 'disabled'],
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!householdId) throw new Error('householdId is required');
      return getHouseholdMeetingHistory(organizationId, householdId, pageSize, page * pageSize);
    },
    enabled: !!organizationId && !!householdId && enabled,
    staleTime: 30_000,
  });
}

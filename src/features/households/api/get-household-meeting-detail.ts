import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { meetingKeys } from './get-household-meeting-history';
import type { HouseholdMeetingDetail } from '../types';

export async function getHouseholdMeetingDetail(
  organizationId: string,
  meetingId: string
): Promise<HouseholdMeetingDetail> {
  const { data, error } = await supabase.rpc('get_household_meeting_detail', {
    p_organization_id: organizationId,
    p_meeting_id: meetingId,
  });

  if (error) throw error;
  return data as unknown as HouseholdMeetingDetail;
}

export function useHouseholdMeetingDetail(
  organizationId: string | null,
  meetingId: string | null,
  enabled = true
) {
  return useQuery({
    queryKey:
      organizationId && meetingId
        ? meetingKeys.detail(organizationId, meetingId)
        : ['household-meetings', 'detail', 'disabled'],
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!meetingId) throw new Error('meetingId is required');
      return getHouseholdMeetingDetail(organizationId, meetingId);
    },
    enabled: !!organizationId && !!meetingId && enabled,
    staleTime: 30_000,
  });
}

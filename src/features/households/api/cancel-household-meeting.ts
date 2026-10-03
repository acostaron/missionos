import { supabase } from '../../../lib/supabase/client';

export interface CancelHouseholdMeetingResult {
  household_meeting_id: string;
  meeting_status: 'cancelled';
}

export async function cancelHouseholdMeeting(
  organizationId: string,
  meetingId: string,
  reason?: string
): Promise<CancelHouseholdMeetingResult> {
  const { data, error } = await supabase.rpc('cancel_household_meeting', {
    p_organization_id: organizationId,
    p_meeting_id: meetingId,
    p_reason: reason ?? undefined,
  });

  if (error) throw error;
  return data as unknown as CancelHouseholdMeetingResult;
}

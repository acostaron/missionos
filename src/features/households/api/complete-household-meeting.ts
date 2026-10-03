import { supabase } from '../../../lib/supabase/client';
import type { AttendanceSummary } from '../types';

export interface CompleteHouseholdMeetingResult {
  household_meeting_id: string;
  meeting_status: 'completed';
  attendance_summary: AttendanceSummary;
}

export async function completeHouseholdMeeting(
  organizationId: string,
  meetingId: string
): Promise<CompleteHouseholdMeetingResult> {
  const { data, error } = await supabase.rpc('complete_household_meeting', {
    p_organization_id: organizationId,
    p_meeting_id: meetingId,
    // p_actual_start_at / p_actual_end_at / p_notes_summary deliberately omitted
    // notes_summary is reserved/unused in Phase 6B-8
  });

  if (error) throw error;
  return data as unknown as CompleteHouseholdMeetingResult;
}

import { supabase } from '../../../lib/supabase/client';

export interface CompleteHouseholdTopicResult {
  assignment_id: string;
  assignment_status: 'completed';
  completed_at: string;
  completed_household_meeting_id: string;
  meeting_date: string;
}

export async function completeHouseholdTopic(
  organizationId: string,
  assignmentId: string,
  meetingId: string
): Promise<CompleteHouseholdTopicResult> {
  const { data, error } = await supabase.rpc('complete_household_topic', {
    p_organization_id: organizationId,
    p_household_topic_assignment_id: assignmentId,
    p_household_meeting_id: meetingId,
  });

  if (error) throw error;
  return data as unknown as CompleteHouseholdTopicResult;
}
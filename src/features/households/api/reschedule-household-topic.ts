import { supabase } from '../../../lib/supabase/client';

export interface RescheduleHouseholdTopicResult {
  assignment_id: string;
  previous_planned_date: string | null;
  planned_for_date: string | null;
}

export async function rescheduleHouseholdTopic(
  organizationId: string,
  assignmentId: string,
  plannedForDate: string
): Promise<RescheduleHouseholdTopicResult> {
  const { data, error } = await supabase.rpc('reschedule_household_topic', {
    p_organization_id: organizationId,
    p_household_topic_assignment_id: assignmentId,
    p_planned_for_date: plannedForDate,
  });

  if (error) throw error;
  return data as unknown as RescheduleHouseholdTopicResult;
}
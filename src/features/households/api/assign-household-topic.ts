import { supabase } from '../../../lib/supabase/client';

export interface AssignHouseholdTopicResult {
  assignment_id: string;
  household_node_id: string;
  topic_id: string;
  topic_title: string;
  assignment_status: 'planned';
  planned_for_date: string | null;
  sequence_number: number | null;
}

export async function assignHouseholdTopic(
  organizationId: string,
  householdId: string,
  topicId: string,
  plannedForDate: string | null,
  sequenceNumber: number | null
): Promise<AssignHouseholdTopicResult> {
  const { data, error } = await supabase.rpc('assign_household_topic', {
    p_organization_id: organizationId,
    p_household_node_id: householdId,
    p_topic_id: topicId,
    p_planned_for_date: plannedForDate ?? undefined,
    p_sequence_number: sequenceNumber ?? undefined,
  });

  if (error) throw error;
  return data as unknown as AssignHouseholdTopicResult;
}
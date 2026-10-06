import { supabase } from '../../../lib/supabase/client';
import type { HouseholdTopicReasonCode } from '../types';

export async function skipHouseholdTopic(
  organizationId: string,
  assignmentId: string,
  reasonCode: HouseholdTopicReasonCode
): Promise<{ assignment_id: string; assignment_status: 'skipped' }> {
  const { data, error } = await supabase.rpc('skip_household_topic', {
    p_organization_id: organizationId,
    p_household_topic_assignment_id: assignmentId,
    p_reason_code: reasonCode,
  });

  if (error) throw error;
  return data as unknown as { assignment_id: string; assignment_status: 'skipped' };
}
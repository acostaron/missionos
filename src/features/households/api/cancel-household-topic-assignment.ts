import { supabase } from '../../../lib/supabase/client';
import type { HouseholdTopicReasonCode } from '../types';

export async function cancelHouseholdTopicAssignment(
  organizationId: string,
  assignmentId: string,
  reasonCode: HouseholdTopicReasonCode
): Promise<{ assignment_id: string; assignment_status: 'cancelled' }> {
  const { data, error } = await supabase.rpc('cancel_household_topic_assignment', {
    p_organization_id: organizationId,
    p_household_topic_assignment_id: assignmentId,
    p_reason_code: reasonCode,
  });

  if (error) throw error;
  return data as unknown as { assignment_id: string; assignment_status: 'cancelled' };
}
import { supabase } from '../../../lib/supabase/client';
import type {
  EndHouseholdMembershipInput,
  EndHouseholdMembershipResult,
} from '../types';

export async function endHouseholdMembership(
  organizationId: string,
  input: EndHouseholdMembershipInput
): Promise<EndHouseholdMembershipResult> {
  const { data, error } = await supabase.rpc('end_household_membership', {
    p_organization_id: organizationId,
    p_member_id: input.member_id,
    p_effective_to: input.effective_to ?? undefined,
    p_reason: input.reason,
  });

  if (error) {
    throw error;
  }

  return data as unknown as EndHouseholdMembershipResult;
}

import { supabase } from '../../../lib/supabase/client';
import type {
  AssignHouseholdMemberInput,
  AssignHouseholdMemberResult,
} from '../types';

export async function assignHouseholdMember(
  organizationId: string,
  input: AssignHouseholdMemberInput
): Promise<AssignHouseholdMemberResult> {
  const { data, error } = await supabase.rpc('assign_member_to_household', {
    p_organization_id: organizationId,
    p_member_id: input.member_id,
    p_household_id: input.household_id,
    p_effective_from: input.effective_from ?? undefined,
    p_confirm_governance_mismatch: input.confirm_governance_mismatch ?? false,
  });

  if (error) {
    throw error;
  }

  return data as unknown as AssignHouseholdMemberResult;
}

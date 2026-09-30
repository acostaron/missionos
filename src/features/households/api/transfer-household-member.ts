import { supabase } from '../../../lib/supabase/client';
import type {
  TransferHouseholdMemberInput,
  TransferHouseholdMemberResult,
} from '../types';

export async function transferHouseholdMember(
  organizationId: string,
  input: TransferHouseholdMemberInput
): Promise<TransferHouseholdMemberResult> {
  const { data, error } = await supabase.rpc('transfer_household_member', {
    p_organization_id: organizationId,
    p_member_id: input.member_id,
    p_destination_household_id: input.destination_household_id,
    p_effective_date: input.effective_date ?? undefined,
    p_reason: input.reason,
    p_confirm_governance_mismatch: input.confirm_governance_mismatch ?? false,
  });

  if (error) {
    throw error;
  }

  return data as unknown as TransferHouseholdMemberResult;
}

import { supabase } from '../../../lib/supabase/client';
import type { EndFamilyMembershipInput, EndFamilyMembershipResponse } from '../types';

export async function endFamilyMembership(input: EndFamilyMembershipInput): Promise<EndFamilyMembershipResponse> {
  const { data, error } = await supabase.rpc('end_family_membership', {
    p_organization_id: input.organizationId,
    p_family_member_id: input.familyMemberId,
    p_effective_to: input.effectiveTo?.trim() || undefined,
    p_reason: input.reason.trim(),
  });

  if (error) throw error;
  return data as unknown as EndFamilyMembershipResponse;
}

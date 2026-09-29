import { supabase } from '../../../lib/supabase/client';
import type { UpdateFamilyMemberInput, UpdateFamilyMemberResponse } from '../types';

export async function updateFamilyMember(input: UpdateFamilyMemberInput): Promise<UpdateFamilyMemberResponse> {
  const { data, error } = await supabase.rpc('update_family_member', {
    p_organization_id: input.organizationId,
    p_family_member_id: input.familyMemberId,
    p_family_role: input.familyRole?.trim() || '',
    p_is_primary_contact: !!input.isPrimaryContact,
    p_is_dependent: !!input.isDependent,
  });

  if (error) throw error;
  return data as unknown as UpdateFamilyMemberResponse;
}

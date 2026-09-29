import { supabase } from '../../../lib/supabase/client';
import type { AddFamilyMemberInput, AddFamilyMemberResult } from '../types';

export async function addFamilyMember(input: AddFamilyMemberInput): Promise<AddFamilyMemberResult> {
  const { data, error } = await supabase.rpc('add_family_member', {
    p_organization_id: input.organizationId,
    p_family_id: input.familyId,
    p_member_id: input.memberId,
    p_family_role: input.familyRole?.trim() || undefined,
    p_is_primary_contact: !!input.isPrimaryContact,
    p_is_dependent: !!input.isDependent,
    p_effective_from: input.effectiveFrom?.trim() || undefined,
    p_confirm_multiple_active_family: !!input.confirmMultipleActiveFamily,
  });

  if (error) throw error;
  return data as unknown as AddFamilyMemberResult;
}

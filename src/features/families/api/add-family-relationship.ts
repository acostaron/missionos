import { supabase } from '../../../lib/supabase/client';
import type { AddFamilyRelationshipInput, AddFamilyRelationshipResponse } from '../types';

export async function addFamilyRelationship(
  input: AddFamilyRelationshipInput
): Promise<AddFamilyRelationshipResponse> {
  const { data, error } = await supabase.rpc('add_family_relationship', {
    p_organization_id: input.organizationId,
    p_family_id: input.familyId,
    p_from_member_id: input.fromMemberId,
    p_to_member_id: input.toMemberId,
    p_relationship_type_code: input.relationshipTypeCode,
    p_effective_from: input.effectiveFrom?.trim() || undefined,
  });

  if (error) throw error;
  return data as unknown as AddFamilyRelationshipResponse;
}

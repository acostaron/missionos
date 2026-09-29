import { supabase } from '../../../lib/supabase/client';
import type { EndFamilyRelationshipInput, EndFamilyRelationshipResponse } from '../types';

export async function endFamilyRelationship(
  input: EndFamilyRelationshipInput
): Promise<EndFamilyRelationshipResponse> {
  const { data, error } = await supabase.rpc('end_family_relationship', {
    p_organization_id: input.organizationId,
    p_relationship_id: input.relationshipId,
    p_effective_to: input.effectiveTo?.trim() || undefined,
    p_reason: input.reason.trim(),
  });

  if (error) throw error;
  return data as unknown as EndFamilyRelationshipResponse;
}

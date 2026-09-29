import { supabase } from '../../../lib/supabase/client';
import type {
  RepairFamilyRelationshipReciprocalInput,
  RepairFamilyRelationshipReciprocalResponse,
} from '../types';

export async function repairFamilyRelationshipReciprocal(
  input: RepairFamilyRelationshipReciprocalInput
): Promise<RepairFamilyRelationshipReciprocalResponse> {
  const { data, error } = await supabase.rpc('repair_family_relationship_reciprocal', {
    p_organization_id: input.organizationId,
    p_relationship_id: input.relationshipId,
    p_reason: input.reason.trim(),
  });

  if (error) throw error;
  return data as unknown as RepairFamilyRelationshipReciprocalResponse;
}

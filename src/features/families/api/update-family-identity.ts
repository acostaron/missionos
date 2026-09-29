import { supabase } from '../../../lib/supabase/client';
import type { UpdateFamilyIdentityInput, UpdateFamilyIdentityResponse } from '../types';

export async function updateFamilyIdentity(
  input: UpdateFamilyIdentityInput
): Promise<UpdateFamilyIdentityResponse> {
  const { data, error } = await supabase.rpc('update_family_identity', {
    p_organization_id: input.organizationId,
    p_family_id: input.familyId,
    p_display_name: input.displayName.trim(),
    p_family_name: input.familyName.trim(),
    p_family_type: input.familyType?.trim() || undefined,
    p_formed_on: input.formedOn?.trim() ? input.formedOn.trim() : undefined,
  });

  if (error) throw error;
  return data as unknown as UpdateFamilyIdentityResponse;
}

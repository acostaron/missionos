import { supabase } from '../../../lib/supabase/client';
import type { CreateFamilyInput, CreateFamilyResult } from '../types';

export async function createFamily(input: CreateFamilyInput): Promise<CreateFamilyResult> {
  const { data, error } = await supabase.rpc('create_family', {
    p_organization_id: input.organizationId,
    p_display_name: input.displayName.trim(),
    p_family_name: input.familyName.trim(),
    p_family_type: input.familyType || 'household_family',
    p_formed_on: input.formedOn?.trim() ? input.formedOn.trim() : undefined,
    p_confirm_duplicate: !!input.confirmDuplicate,
  });

  if (error) throw error;
  return data as unknown as CreateFamilyResult;
}

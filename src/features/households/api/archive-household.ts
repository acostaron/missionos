import { supabase } from '../../../lib/supabase/client';
import type { ArchiveHouseholdResult } from '../types';

export async function archiveHousehold(
  organizationId: string,
  householdId: string,
  reason: string
): Promise<ArchiveHouseholdResult> {
  const { data, error } = await supabase.rpc('archive_household', {
    p_organization_id: organizationId,
    p_household_id: householdId,
    p_reason: reason,
  });

  if (error) {
    throw error;
  }

  return data as unknown as ArchiveHouseholdResult;
}

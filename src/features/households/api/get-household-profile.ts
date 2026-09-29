import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { householdKeys } from '../queries';
import type { HouseholdProfileData } from '../types';

export async function fetchHouseholdProfile(
  organizationId: string,
  householdId: string
): Promise<HouseholdProfileData> {
  const { data, error } = await supabase.rpc('get_household_profile', {
    p_organization_id: organizationId,
    p_household_id: householdId,
  });

  if (error) throw error;
  return data as unknown as HouseholdProfileData;
}

export function useHouseholdProfile(
  organizationId: string | null,
  householdId: string | null,
  enabled: boolean = true
) {
  return useQuery({
    queryKey:
      organizationId && householdId
        ? householdKeys.profile(organizationId, householdId)
        : householdKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!householdId) throw new Error('householdId is required');
      return fetchHouseholdProfile(organizationId, householdId);
    },
    enabled: !!organizationId && !!householdId && enabled,
    staleTime: 60 * 1000,
  });
}

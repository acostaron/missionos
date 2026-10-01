import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { pastoralDashboardKeys } from './get-pastoral-operations-dashboard';

import type { PastoralHouseholdRoster } from '../types';

export async function getPastoralHouseholdRoster(
  organizationId: string,
  householdId: string
): Promise<PastoralHouseholdRoster> {
  const { data, error } = await supabase.rpc('get_pastoral_household_roster', {
    p_organization_id: organizationId,
    p_household_id: householdId,
  });

  if (error) {
    throw error;
  }

  return data as unknown as PastoralHouseholdRoster;
}

export function usePastoralHouseholdRoster(
  organizationId: string | null,
  householdId: string | null,
  enabled: boolean = true
) {
  return useQuery({
    queryKey: organizationId && householdId
      ? pastoralDashboardKeys.roster(organizationId, householdId)
      : ['pastoral-roster', 'disabled'],
    queryFn: () => {
      if (!organizationId || !householdId) {
        throw new Error('Organization ID and Household ID are required');
      }
      return getPastoralHouseholdRoster(organizationId, householdId);
    },
    enabled: !!organizationId && !!householdId && enabled,
    staleTime: 30000,
  });
}

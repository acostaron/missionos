import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import type { HouseholdFormationPlan } from '../types';

export const formationKeys = {
  all: ['household-formation'] as const,
  plan: (orgId: string, householdId: string) =>
    [...formationKeys.all, 'plan', orgId, householdId] as const,
  history: (orgId: string, householdId: string, page?: number) =>
    [...formationKeys.all, 'history', orgId, householdId, page ?? 0] as const,
  topics: (orgId: string, search: string) =>
    [...formationKeys.all, 'topics', orgId, search] as const,
};

export async function getHouseholdFormationPlan(
  organizationId: string,
  householdId: string
): Promise<HouseholdFormationPlan> {
  const { data, error } = await supabase.rpc('get_household_formation_plan', {
    p_organization_id: organizationId,
    p_household_node_id: householdId,
  });

  if (error) throw error;
  return data as unknown as HouseholdFormationPlan;
}

export function useHouseholdFormationPlan(
  organizationId: string | null,
  householdId: string | null,
  enabled = true
) {
  return useQuery({
    queryKey:
      organizationId && householdId
        ? formationKeys.plan(organizationId, householdId)
        : ['household-formation', 'disabled'],
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!householdId) throw new Error('householdId is required');
      return getHouseholdFormationPlan(organizationId, householdId);
    },
    enabled: !!organizationId && !!householdId && enabled,
    staleTime: 30_000,
  });
}
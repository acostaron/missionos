import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import type { HouseholdTopicHistory } from '../types';
import { formationKeys } from './get-household-formation-plan';

export async function getHouseholdTopicHistory(
  organizationId: string,
  householdId: string,
  limit = 10,
  offset = 0
): Promise<HouseholdTopicHistory> {
  const { data, error } = await supabase.rpc('get_household_topic_history', {
    p_organization_id: organizationId,
    p_household_node_id: householdId,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) throw error;
  return data as unknown as HouseholdTopicHistory;
}

export function useHouseholdTopicHistory(
  organizationId: string | null,
  householdId: string | null,
  page = 0,
  pageSize = 10,
  enabled = true
) {
  return useQuery({
    queryKey:
      organizationId && householdId
        ? formationKeys.history(organizationId, householdId, page)
        : ['household-formation', 'history-disabled'],
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!householdId) throw new Error('householdId is required');
      return getHouseholdTopicHistory(organizationId, householdId, pageSize, page * pageSize);
    },
    enabled: !!organizationId && !!householdId && enabled,
    staleTime: 30_000,
  });
}
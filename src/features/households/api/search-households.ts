import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { householdKeys } from '../queries';
import type { HouseholdSearchResult } from '../types';

export interface SearchHouseholdsParams {
  search?: string;
  parentGovernanceNodeId?: string;
  lifecycleStatus?: string;
  limit?: number;
  offset?: number;
}

export async function searchHouseholds(
  organizationId: string,
  params: SearchHouseholdsParams = {}
): Promise<HouseholdSearchResult> {
  const { data, error } = await supabase.rpc('search_households', {
    p_organization_id: organizationId,
    p_search: params.search ?? undefined,
    p_parent_governance_node_id: params.parentGovernanceNodeId ?? undefined,
    p_lifecycle_status: params.lifecycleStatus ?? 'active',
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });

  if (error) throw error;
  return data as unknown as HouseholdSearchResult;
}

export function useSearchHouseholds(
  organizationId: string | null,
  params: SearchHouseholdsParams = {},
  enabled: boolean = true
) {
  return useQuery({
    queryKey: organizationId
      ? householdKeys.list(organizationId, params as Record<string, unknown>)
      : householdKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      return searchHouseholds(organizationId, params);
    },
    enabled: !!organizationId && enabled,
    staleTime: 30 * 1000,
  });
}

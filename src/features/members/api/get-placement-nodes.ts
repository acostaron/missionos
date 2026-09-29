import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import type { PlacementNodeItem } from '../types';

export const placementNodeKeys = {
  all: ['placement-nodes'] as const,
  byOrg: (orgId: string) => [...placementNodeKeys.all, orgId] as const,
};

export async function fetchPlacementNodes(organizationId: string): Promise<PlacementNodeItem[]> {
  const { data, error } = await supabase.rpc('get_placement_nodes', {
    p_organization_id: organizationId,
  });

  if (error) throw error;
  return (data as PlacementNodeItem[]) || [];
}

export function usePlacementNodes(organizationId: string | null, enabled: boolean = true) {
  return useQuery({
    queryKey: organizationId ? placementNodeKeys.byOrg(organizationId) : placementNodeKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      return fetchPlacementNodes(organizationId);
    },
    enabled: !!organizationId && enabled,
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
}

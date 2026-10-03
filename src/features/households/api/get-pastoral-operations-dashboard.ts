import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import type { PastoralOperationsDashboardV2 } from '../types';


export const pastoralDashboardKeys = {
  all: ['pastoral-dashboard'] as const,
  dashboard: (orgId: string, nodeId?: string | null) =>
    [...pastoralDashboardKeys.all, orgId, nodeId ?? 'all'] as const,
  roster: (orgId: string, householdId: string) =>
    [...pastoralDashboardKeys.all, 'roster', orgId, householdId] as const,
};

export async function getPastoralOperationsDashboard(
  organizationId: string,
  governanceNodeId?: string | null
): Promise<PastoralOperationsDashboardV2> {
  const { data, error } = await supabase.rpc('get_pastoral_operations_dashboard', {
    p_organization_id: organizationId,
    p_governance_node_id: governanceNodeId ?? undefined,
  });

  if (error) {
    throw error;
  }

  return data as unknown as PastoralOperationsDashboardV2;
}

export function usePastoralOperationsDashboard(
  organizationId: string | null,
  governanceNodeId?: string | null,
  enabled: boolean = true
) {
  return useQuery({
    queryKey: organizationId
      ? pastoralDashboardKeys.dashboard(organizationId, governanceNodeId)
      : ['pastoral-dashboard', 'disabled'],
    queryFn: () => {
      if (!organizationId) {
        throw new Error('Organization ID is required');
      }
      return getPastoralOperationsDashboard(organizationId, governanceNodeId);
    },
    enabled: !!organizationId && enabled,
    staleTime: 30000,
  });
}

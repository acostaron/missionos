import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import type { ServantLeaderAccessStatus } from '../types';

export async function getServantLeaderAccessStatus(
  organizationId: string,
  leadershipAssignmentId: string
): Promise<ServantLeaderAccessStatus> {
  const { data, error } = await supabase.rpc('get_servant_leader_access_status', {
    p_organization_id: organizationId,
    p_leadership_assignment_id: leadershipAssignmentId,
  });

  if (error) throw error;
  return data as unknown as ServantLeaderAccessStatus;
}

export function useServantLeaderAccessStatus(
  organizationId: string | null,
  leadershipAssignmentId: string | null,
  enabled = true
) {
  return useQuery({
    queryKey: ['servant-leader-access-status', organizationId, leadershipAssignmentId],
    queryFn: () => getServantLeaderAccessStatus(organizationId!, leadershipAssignmentId!),
    enabled: enabled && !!organizationId && !!leadershipAssignmentId,
    staleTime: 30_000,
  });
}

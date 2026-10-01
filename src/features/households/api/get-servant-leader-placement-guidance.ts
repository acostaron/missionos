import { supabase } from '../../../lib/supabase/client';
import type { ServantLeaderPlacementGuidanceResult } from '../types';

export async function getServantLeaderPastoralPlacementGuidance(
  organizationId: string,
  memberId: string,
  leadershipAssignmentId?: string
): Promise<ServantLeaderPlacementGuidanceResult> {
  const { data, error } = await supabase.rpc(
    'get_servant_leader_pastoral_placement_guidance',
    {
      p_organization_id: organizationId,
      p_member_id: memberId,
      p_leadership_assignment_id: leadershipAssignmentId ?? undefined,
    }
  );

  if (error) {
    throw error;
  }

  return data as unknown as ServantLeaderPlacementGuidanceResult;
}

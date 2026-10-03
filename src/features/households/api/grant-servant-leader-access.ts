import { supabase } from '../../../lib/supabase/client';
import type { GrantServantLeaderAccessResult } from '../types';

export async function grantServantLeaderAccess(
  organizationId: string,
  leadershipAssignmentId: string,
  profileId?: string | null
): Promise<GrantServantLeaderAccessResult> {
  const { data, error } = await supabase.rpc('grant_servant_leader_access', {
    p_organization_id: organizationId,
    p_leadership_assignment_id: leadershipAssignmentId,
    p_profile_id: profileId ?? undefined,
  });

  if (error) throw error;
  return data as unknown as GrantServantLeaderAccessResult;
}

import { supabase } from '../../../lib/supabase/client';
import type { RevokeServantLeaderAccessResult } from '../types';

export async function revokeServantLeaderAccess(
  organizationId: string,
  options: {
    leadershipAssignmentId?: string | null;
    grantId?: string | null;
    reason?: string | null;
  }
): Promise<RevokeServantLeaderAccessResult> {
  const { data, error } = await supabase.rpc('revoke_servant_leader_access', {
    p_organization_id: organizationId,
    p_leadership_assignment_id: options.leadershipAssignmentId ?? undefined,
    p_grant_id: options.grantId ?? undefined,
    p_reason: options.reason ?? undefined,
  });

  if (error) throw error;
  return data as unknown as RevokeServantLeaderAccessResult;
}

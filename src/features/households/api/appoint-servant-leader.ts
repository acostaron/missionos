import { supabase } from '../../../lib/supabase/client';
import type {
  AppointServantLeaderInput,
  AppointServantLeaderResult,
} from '../types';

export async function appointServantLeader(
  organizationId: string,
  input: AppointServantLeaderInput
): Promise<AppointServantLeaderResult> {
  const { data, error } = await supabase.rpc('appoint_servant_leader', {
    p_organization_id: organizationId,
    p_role_code: input.role_code,
    p_governance_node_id: input.governance_node_id,
    p_member_id: input.member_id,
    p_effective_from: input.effective_from ?? undefined,
    p_reason: input.reason ?? undefined,
  });

  if (error) {
    throw error;
  }

  return data as unknown as AppointServantLeaderResult;
}

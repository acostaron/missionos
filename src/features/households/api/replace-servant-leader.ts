import { supabase } from '../../../lib/supabase/client';
import type {
  ReplaceServantLeaderInput,
  ReplaceServantLeaderResult,
} from '../types';

export async function replaceServantLeader(
  organizationId: string,
  input: ReplaceServantLeaderInput
): Promise<ReplaceServantLeaderResult> {
  const { data, error } = await supabase.rpc('replace_servant_leader', {
    p_organization_id: organizationId,
    p_role_code: input.role_code,
    p_governance_node_id: input.governance_node_id,
    p_new_member_id: input.new_member_id,
    p_effective_date: input.effective_date ?? undefined,
    p_reason: input.reason,
  });

  if (error) {
    throw error;
  }

  return data as unknown as ReplaceServantLeaderResult;
}

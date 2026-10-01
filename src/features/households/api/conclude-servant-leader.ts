import { supabase } from '../../../lib/supabase/client';
import type {
  ConcludeServantLeaderInput,
  ConcludeServantLeaderResult,
} from '../types';

export async function concludeServantLeader(
  organizationId: string,
  input: ConcludeServantLeaderInput
): Promise<ConcludeServantLeaderResult> {
  const { data, error } = await supabase.rpc('conclude_servant_leader', {
    p_organization_id: organizationId,
    p_leadership_assignment_id: input.leadership_assignment_id,
    p_effective_to: input.effective_to ?? undefined,
    p_reason: input.reason,
  });

  if (error) {
    throw error;
  }

  return data as unknown as ConcludeServantLeaderResult;
}

import { supabase } from '../../../lib/supabase/client';
import type {
  ChangeMemberGovernanceAssignmentInput,
  ChangeMemberGovernanceAssignmentResponse,
} from '../types';

/**
 * Frontend API wrapper for public.change_member_governance_assignment RPC.
 *
 * This function handles initial placement, transfer to Chapter/Unit,
 * or unplacement (targetGovernanceNodeId: null).
 *
 * It enforces:
 * - Explicit nulls for absent target nodes (Unplaced).
 * - Explicit required YYYY-MM-DD string for p_effective_from (no undefined).
 * - Explicit null for empty/whitespace reasons.
 *
 * Zero direct table access.
 */
export async function changeMemberGovernanceAssignment(
  input: ChangeMemberGovernanceAssignmentInput
): Promise<ChangeMemberGovernanceAssignmentResponse> {
  const cleanOrNull = (val?: string | null): string | null => {
    if (!val) return null;
    const t = val.trim();
    return t.length > 0 ? t : null;
  };

  const payload = {
    p_organization_id: input.organizationId,
    p_member_id: input.memberId,
    p_target_governance_node_id: input.targetGovernanceNodeId ? input.targetGovernanceNodeId : null,
    p_effective_from: input.effectiveFrom,
    p_reason: cleanOrNull(input.reason),
  };

  const { data, error } = await supabase.rpc(
    'change_member_governance_assignment',
    payload as any
  );


  if (error) {
    throw error;
  }

  return data as unknown as ChangeMemberGovernanceAssignmentResponse;
}

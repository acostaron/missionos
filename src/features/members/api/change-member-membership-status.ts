import { supabase } from '../../../lib/supabase/client';
import type {
  ChangeMemberMembershipStatusInput,
  ChangeMemberMembershipStatusResponse,
} from '../types';

/**
 * Frontend API wrapper for public.change_member_membership_status RPC.
 *
 * Enforces:
 * - organization UUID and member UUID
 * - selected targetStatusId UUID
 * - explicit required YYYY-MM-DD string for p_effective_from (never undefined)
 * - trimmed string or null for reason (never blank string)
 *
 * Zero direct table access.
 */
export async function changeMemberMembershipStatus(
  input: ChangeMemberMembershipStatusInput
): Promise<ChangeMemberMembershipStatusResponse> {
  const cleanOrNull = (val?: string | null): string | null => {
    if (!val) return null;
    const t = val.trim();
    return t.length > 0 ? t : null;
  };

  const payload = {
    p_organization_id: input.organizationId,
    p_member_id: input.memberId,
    p_target_status_id: input.targetStatusId,
    p_effective_from: input.effectiveFrom,
    p_reason: cleanOrNull(input.reason) ?? undefined,
  };

  const { data, error } = await supabase.rpc(
    'change_member_membership_status',
    payload
  );

  if (error) {
    throw error;
  }

  return data as unknown as ChangeMemberMembershipStatusResponse;
}

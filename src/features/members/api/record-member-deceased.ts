import { supabase } from '../../../lib/supabase/client';
import type {
  RecordMemberDeceasedInput,
  RecordMemberDeceasedResponse,
} from '../types';

/**
 * Specialized write API to record a member as deceased.
 *
 * Calls public.record_member_deceased write RPC.
 * Enforces:
 *   - members.deceased.manage permission
 *   - Organization access
 *   - Member governance scope
 *   - Atomically synchronizes is_deceased, deceased_on, deceased_on_precision,
 *     membership_status_id, and member_status_history.
 */
export async function recordMemberDeceased(
  input: RecordMemberDeceasedInput
): Promise<RecordMemberDeceasedResponse> {
  const { data, error } = await supabase.rpc('record_member_deceased', {
    p_organization_id: input.organizationId,
    p_member_id: input.memberId,
    p_deceased_on: input.deceasedOn ? input.deceasedOn : null,
    p_deceased_on_precision: input.deceasedOnPrecision ?? 'unknown',
    p_effective_from: input.effectiveFrom,
    p_reason: input.reason?.trim() ? input.reason.trim() : null,
  });

  if (error) {
    throw error;
  }

  return data as unknown as RecordMemberDeceasedResponse;
}

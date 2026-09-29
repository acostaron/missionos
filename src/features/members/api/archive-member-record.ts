import { supabase } from '../../../lib/supabase/client';
import type {
  ArchiveMemberRecordInput,
  ArchiveMemberRecordResponse,
} from '../types';

/**
 * Frontend API wrapper for public.archive_member_record RPC.
 *
 * Enforces:
 * - organization UUID and member UUID
 * - non-empty reason string
 * - callers holding members.records.archive permission
 * - canonical profile resolution and audit logging
 *
 * Zero direct table access.
 */
export async function archiveMemberRecord(
  input: ArchiveMemberRecordInput
): Promise<ArchiveMemberRecordResponse> {
  const { data, error } = await supabase.rpc('archive_member_record', {
    p_organization_id: input.organizationId,
    p_member_id: input.memberId,
    p_reason: input.reason.trim(),
  });

  if (error) {
    throw error;
  }

  return data as unknown as ArchiveMemberRecordResponse;
}

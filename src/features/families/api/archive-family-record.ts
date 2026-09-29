import { supabase } from '../../../lib/supabase/client';
import type { ArchiveFamilyRecordInput, ArchiveFamilyResult } from '../types';

export async function archiveFamilyRecord(
  input: ArchiveFamilyRecordInput
): Promise<ArchiveFamilyResult> {
  const { data, error } = await supabase.rpc('archive_family_record', {
    p_organization_id: input.organizationId,
    p_family_id: input.familyId,
    p_reason: input.reason.trim(),
    p_confirm_with_active_members: !!input.confirmWithActiveMembers,
  });

  if (error) throw error;
  return data as unknown as ArchiveFamilyResult;
}

import { supabase } from '../../lib/supabase/client';
import {
  formationCatalogResponseSchema,
  formationProgramDetailSchema,
  formationProgramRecordResultSchema,
  formationTalkRecordResultSchema,
  formationTranscriptSchema,
  voidFormationRecordResultSchema,
} from './schemas';
import type {
  FormationCatalogFilters,
  FormationProgramDetail,
  FormationProgramRecordResult,
  FormationProgramSummary,
  FormationTalkRecordResult,
  FormationTranscript,
  RecordFormationProgramInput,
  RecordFormationTalkInput,
  VoidFormationRecordResult,
} from './types';

/**
 * Retrieves the formation curriculum catalog accessible in the requested organization context.
 * Returns global programs (organization_id IS NULL) plus any local programs for the organization.
 * Inactive programs are omitted unless includeInactive is explicitly true (requires formation.catalog.manage).
 */
export async function getFormationCatalog(
  organizationId: string,
  filters?: FormationCatalogFilters
): Promise<FormationProgramSummary[]> {
  const { data, error } = await supabase.rpc('get_formation_catalog', {
    p_organization_id: organizationId,
    p_program_category: filters?.programCategory ?? undefined,
    p_include_inactive: filters?.includeInactive ?? false,
  });

  if (error) {
    throw error;
  }

  return formationCatalogResponseSchema.parse(data);
}

/**
 * Retrieves the complete detail of a specific formation program by ID,
 * including structured talk sessions and canonical requirements.
 */
export async function getFormationProgram(
  organizationId: string,
  programId: string
): Promise<FormationProgramDetail> {
  const { data, error } = await supabase.rpc('get_formation_program', {
    p_organization_id: organizationId,
    p_program_id: programId,
  });

  if (error) {
    throw error;
  }

  return formationProgramDetailSchema.parse(data);
}

/**
 * Records a formation program participation or completion for a member.
 */
export async function recordFormationProgram(
  input: RecordFormationProgramInput
): Promise<FormationProgramRecordResult> {
  const { data, error } = await supabase.rpc('record_member_formation_program', {
    p_organization_id: input.organizationId,
    p_member_id: input.memberId,
    p_program_id: input.programId,
    p_status: input.status,
    p_completed_date: input.completedDate ?? undefined,
    p_completed_year: input.completedYear ?? undefined,
    p_completed_month: input.completedMonth ?? undefined,
    p_date_precision: input.datePrecision ?? 'unknown',
    p_verification_method: input.verificationMethod ?? 'leader_attestation',
    p_source_reference: input.sourceReference ?? undefined,
    p_verification_notes: input.verificationNotes ?? undefined,
  });

  if (error) {
    throw error;
  }

  return formationProgramRecordResultSchema.parse(data);
}

/**
 * Records a talk participation for a specific program attempt.
 */
export async function recordFormationTalk(
  input: RecordFormationTalkInput
): Promise<FormationTalkRecordResult> {
  const { data, error } = await supabase.rpc('record_member_formation_talk', {
    p_organization_id: input.organizationId,
    p_program_record_id: input.programRecordId,
    p_talk_id: input.talkId,
    p_session_status: input.sessionStatus,
    p_attended_date: input.attendedDate ?? undefined,
    p_notes: input.notes ?? undefined,
  });

  if (error) {
    throw error;
  }

  return formationTalkRecordResultSchema.parse(data);
}

/**
 * Voids an erroneous program record and atomically cascades to active child talks.
 */
export async function voidFormationProgramRecord(
  organizationId: string,
  recordId: string,
  voidReason: string
): Promise<VoidFormationRecordResult> {
  const { data, error } = await supabase.rpc('void_member_formation_program_record', {
    p_organization_id: organizationId,
    p_record_id: recordId,
    p_void_reason: voidReason,
  });

  if (error) {
    throw error;
  }

  return voidFormationRecordResultSchema.parse(data);
}

/**
 * Voids an erroneous talk participation record.
 */
export async function voidFormationTalkRecord(
  organizationId: string,
  talkRecordId: string,
  voidReason: string
): Promise<VoidFormationRecordResult> {
  const { data, error } = await supabase.rpc('void_member_formation_talk_record', {
    p_organization_id: organizationId,
    p_talk_record_id: talkRecordId,
    p_void_reason: voidReason,
  });

  if (error) {
    throw error;
  }

  return voidFormationRecordResultSchema.parse(data);
}

/**
 * Retrieves the complete pastoral formation transcript for a member within pastoral scope.
 */
export async function getMemberFormationTranscript(
  organizationId: string,
  memberId: string
): Promise<FormationTranscript> {
  const { data, error } = await supabase.rpc('get_member_formation_transcript', {
    p_organization_id: organizationId,
    p_member_id: memberId,
  });

  if (error) {
    throw error;
  }

  return formationTranscriptSchema.parse(data);
}

/**
 * Retrieves the authenticated caller's own formation transcript.
 */
export async function getMyFormationTranscript(
  organizationId?: string
): Promise<FormationTranscript> {
  const { data, error } = await supabase.rpc('get_my_formation_transcript', {
    p_organization_id: organizationId ?? undefined,
  });

  if (error) {
    throw error;
  }

  return formationTranscriptSchema.parse(data);
}

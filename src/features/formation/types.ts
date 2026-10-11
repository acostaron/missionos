export type FormationProgramCategory =
  | 'pastoral_formation'
  | 'leadership_training'
  | 'ministry_skills';

export type FormationProgramType =
  | 'course'
  | 'retreat'
  | 'recollection'
  | 'entry_seminar'
  | 'training_workshop';

export type FormationTargetAudience =
  | 'all_members'
  | 'couples'
  | 'household_servants'
  | 'unit_servants_above'
  | 'chapter_servants'
  | 'service_team';

export interface FormationProgramSummary {
  id: string;
  organization_id: string | null;
  code: string;
  title: string;
  edition: string;
  program_category: FormationProgramCategory;
  program_type: FormationProgramType;
  description: string | null;
  sequence_order: number | null;
  is_active: boolean;
  effective_from: string | null;
  effective_to: string | null;
  source_document: string | null;
  source_url: string | null;
  source_verified_at: string | null;
  talk_count: number;
  requirement_count: number;
}

export interface FormationTalk {
  id: string;
  talk_code: string;
  title: string;
  session_label: string | null;
  sequence_order: number;
  description: string | null;
  is_required: boolean;
  is_active: boolean;
}

export interface FormationRequirement {
  id: string;
  target_audience: FormationTargetAudience;
  is_mandatory: boolean;
  timing_norm: string | null;
  notes: string | null;
  valid_from: string | null;
  valid_to: string | null;
  is_active: boolean;
}

export interface FormationProgramDetail extends FormationProgramSummary {
  talks: FormationTalk[];
  requirements: FormationRequirement[];
}

export interface FormationCatalogFilters {
  programCategory?: FormationProgramCategory;
  includeInactive?: boolean;
}

export type FormationProgramRecordStatus =
  | 'in_progress'
  | 'completed'
  | 'waived';

export type FormationRecordLifecycleStatus =
  | 'active'
  | 'superseded'
  | 'voided';

export type FormationDatePrecision =
  | 'exact_date'
  | 'month_year'
  | 'year_only'
  | 'approximate'
  | 'unknown';

export type FormationVerificationMethod =
  | 'leader_attestation'
  | 'attendance_roll'
  | 'historical_backfill'
  | 'pastoral_waiver';

export type FormationSessionStatus =
  | 'attended'
  | 'absent_excused'
  | 'makeup_attended'
  | 'waived';

export type FormationProgressStatus =
  | 'not_applicable'
  | 'not_started'
  | 'in_progress'
  | 'completed'
  | 'waived';

export interface FormationProgress {
  total_talks: number;
  required_talks: number;
  attended_talks: number;
  progress_percent: number | null;
  progress_status: FormationProgressStatus;
}

export interface FormationTranscriptTalk {
  talk_record_id: string;
  talk_id: string;
  talk_code: string;
  title: string;
  sequence_order: number;
  session_status: FormationSessionStatus;
  attended_date: string | null;
  notes?: string | null;
}

export interface FormationTranscriptProgram {
  record_id: string;
  program_id: string;
  code: string;
  title: string;
  edition: string;
  program_category: FormationProgramCategory;
  program_type: FormationProgramType;
  attempt_number: number;
  status: FormationProgramRecordStatus;
  record_status: FormationRecordLifecycleStatus;
  completed_date: string | null;
  completed_year: number | null;
  completed_month: number | null;
  date_precision: FormationDatePrecision;
  verification_method?: FormationVerificationMethod;
  source_reference: string | null;
  verified_at?: string | null;
  verifier_display_name?: string | null;
  verification_notes?: string | null;
  recorded_at?: string;
  talks: FormationTranscriptTalk[];
  progress: FormationProgress;
}

export interface FormationTranscriptMemberSummary {
  id: string;
  member_number: string | null;
  display_name: string;
}

export interface FormationTranscript {
  organization_id?: string;
  member: FormationTranscriptMemberSummary;
  programs: FormationTranscriptProgram[];
}

export interface RecordFormationProgramInput {
  organizationId: string;
  memberId: string;
  programId: string;
  status: FormationProgramRecordStatus;
  completedDate?: string | null;
  completedYear?: number | null;
  completedMonth?: number | null;
  datePrecision?: FormationDatePrecision;
  verificationMethod?: FormationVerificationMethod;
  sourceReference?: string | null;
  verificationNotes?: string | null;
}

export interface FormationProgramRecord {
  id: string;
  organization_id: string;
  member_id: string;
  program_id: string;
  attempt_number: number;
  status: FormationProgramRecordStatus;
  record_status: FormationRecordLifecycleStatus;
  completed_date: string | null;
  completed_year: number | null;
  completed_month: number | null;
  date_precision: FormationDatePrecision;
  verification_method: FormationVerificationMethod;
  source_reference: string | null;
  recorded_at: string;
  verified_at: string | null;
}

export type FormationProgramRecordResult = FormationProgramRecord;

export interface RecordFormationTalkInput {
  organizationId: string;
  programRecordId: string;
  talkId: string;
  sessionStatus: FormationSessionStatus;
  attendedDate?: string | null;
  notes?: string | null;
}

export interface FormationTalkRecord {
  id: string;
  organization_id: string;
  member_id: string;
  program_id: string;
  program_record_id: string;
  talk_id: string;
  session_status: FormationSessionStatus;
  attended_date: string | null;
  record_status: FormationRecordLifecycleStatus;
  recorded_at: string;
}

export type FormationTalkRecordResult = FormationTalkRecord;

export interface VoidFormationRecordResult {
  id: string;
  record_status: 'voided';
  voided_at: string;
  void_reason: string;
  cascade_voided_talk_count?: number;
}

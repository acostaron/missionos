import { z } from 'zod';

export const formationProgramCategorySchema = z.enum([
  'pastoral_formation',
  'leadership_training',
  'ministry_skills',
]);

export const formationProgramTypeSchema = z.enum([
  'course',
  'retreat',
  'recollection',
  'entry_seminar',
  'training_workshop',
]);

export const formationTargetAudienceSchema = z.enum([
  'all_members',
  'couples',
  'household_servants',
  'unit_servants_above',
  'chapter_servants',
  'service_team',
]);

export const formationProgramSummarySchema = z.object({
  id: z.string().uuid(),
  organization_id: z.string().uuid().nullable(),
  code: z.string().min(1),
  title: z.string().min(1),
  edition: z.string().min(1),
  program_category: formationProgramCategorySchema,
  program_type: formationProgramTypeSchema,
  description: z.string().nullable(),
  sequence_order: z.number().int().nullable(),
  is_active: z.boolean(),
  effective_from: z.string().nullable(),
  effective_to: z.string().nullable(),
  source_document: z.string().nullable(),
  source_url: z.string().nullable(),
  source_verified_at: z.string().nullable(),
  talk_count: z.number().int().nonnegative(),
  requirement_count: z.number().int().nonnegative(),
});

export const formationTalkSchema = z.object({
  id: z.string().uuid(),
  talk_code: z.string().min(1),
  title: z.string().min(1),
  session_label: z.string().nullable(),
  sequence_order: z.number().int(),
  description: z.string().nullable(),
  is_required: z.boolean(),
  is_active: z.boolean(),
});

export const formationRequirementSchema = z.object({
  id: z.string().uuid(),
  target_audience: formationTargetAudienceSchema,
  is_mandatory: z.boolean(),
  timing_norm: z.string().nullable(),
  notes: z.string().nullable(),
  valid_from: z.string().nullable(),
  valid_to: z.string().nullable(),
  is_active: z.boolean(),
});

export const formationProgramDetailSchema = formationProgramSummarySchema.extend({
  talks: z.array(formationTalkSchema),
  requirements: z.array(formationRequirementSchema),
});

export const formationCatalogResponseSchema = z.array(formationProgramSummarySchema);

export const formationProgramRecordStatusSchema = z.enum([
  'in_progress',
  'completed',
  'waived',
]);

export const formationRecordLifecycleStatusSchema = z.enum([
  'active',
  'superseded',
  'voided',
]);

export const formationDatePrecisionSchema = z.enum([
  'exact_date',
  'month_year',
  'year_only',
  'approximate',
  'unknown',
]);

export const formationVerificationMethodSchema = z.enum([
  'leader_attestation',
  'attendance_roll',
  'historical_backfill',
  'pastoral_waiver',
]);

export const formationSessionStatusSchema = z.enum([
  'attended',
  'absent_excused',
  'makeup_attended',
  'waived',
]);

export const formationProgressStatusSchema = z.enum([
  'not_applicable',
  'not_started',
  'in_progress',
  'completed',
  'waived',
]);

export const formationProgressSchema = z.object({
  total_talks: z.number().int().nonnegative(),
  required_talks: z.number().int().nonnegative(),
  attended_talks: z.number().int().nonnegative(),
  progress_percent: z.number().nullable(),
  progress_status: formationProgressStatusSchema,
});

export const formationTranscriptTalkSchema = z.object({
  talk_record_id: z.string().uuid(),
  talk_id: z.string().uuid(),
  talk_code: z.string().min(1),
  title: z.string().min(1),
  sequence_order: z.number().int(),
  session_status: formationSessionStatusSchema,
  attended_date: z.string().nullable(),
  notes: z.string().nullable().optional(),
});

export const formationTranscriptProgramSchema = z.object({
  record_id: z.string().uuid(),
  program_id: z.string().uuid(),
  code: z.string().min(1),
  title: z.string().min(1),
  edition: z.string().min(1),
  program_category: formationProgramCategorySchema,
  program_type: formationProgramTypeSchema,
  attempt_number: z.number().int().positive(),
  status: formationProgramRecordStatusSchema,
  record_status: formationRecordLifecycleStatusSchema,
  completed_date: z.string().nullable(),
  completed_year: z.number().int().nullable(),
  completed_month: z.number().int().nullable(),
  date_precision: formationDatePrecisionSchema,
  verification_method: formationVerificationMethodSchema.optional(),
  source_reference: z.string().nullable(),
  verified_at: z.string().nullable().optional(),
  verifier_display_name: z.string().nullable().optional(),
  verification_notes: z.string().nullable().optional(),
  recorded_at: z.string().optional(),
  talks: z.array(formationTranscriptTalkSchema),
  progress: formationProgressSchema,
});

export const formationTranscriptMemberSummarySchema = z.object({
  id: z.string().uuid(),
  member_number: z.string().nullable(),
  display_name: z.string().min(1),
});

export const formationTranscriptSchema = z.object({
  organization_id: z.string().uuid().optional(),
  member: formationTranscriptMemberSummarySchema,
  programs: z.array(formationTranscriptProgramSchema),
});

export const formationProgramRecordResultSchema = z.object({
  id: z.string().uuid(),
  organization_id: z.string().uuid(),
  member_id: z.string().uuid(),
  program_id: z.string().uuid(),
  attempt_number: z.number().int().positive(),
  status: formationProgramRecordStatusSchema,
  record_status: formationRecordLifecycleStatusSchema,
  completed_date: z.string().nullable(),
  completed_year: z.number().int().nullable(),
  completed_month: z.number().int().nullable(),
  date_precision: formationDatePrecisionSchema,
  verification_method: formationVerificationMethodSchema,
  source_reference: z.string().nullable(),
  recorded_at: z.string(),
  verified_at: z.string().nullable(),
});

export const formationTalkRecordResultSchema = z.object({
  id: z.string().uuid(),
  organization_id: z.string().uuid(),
  member_id: z.string().uuid(),
  program_id: z.string().uuid(),
  program_record_id: z.string().uuid(),
  talk_id: z.string().uuid(),
  session_status: formationSessionStatusSchema,
  attended_date: z.string().nullable(),
  record_status: formationRecordLifecycleStatusSchema,
  recorded_at: z.string(),
});

export const voidFormationRecordResultSchema = z.object({
  id: z.string().uuid(),
  record_status: z.literal('voided'),
  voided_at: z.string(),
  void_reason: z.string(),
  cascade_voided_talk_count: z.number().int().nonnegative().optional(),
});

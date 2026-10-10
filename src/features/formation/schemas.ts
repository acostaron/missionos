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

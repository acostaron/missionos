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

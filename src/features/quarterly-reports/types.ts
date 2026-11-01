// Quarterly National Report (Pass 9.52). Shapes mirror
// private.build_quarterly_report_document (schema_version 1).

export type QuarterlyReportStatus = 'not_started' | 'draft' | 'review' | 'approved';
export type ReportPriority = 'routine' | 'ministry_activity' | 'major_highlight';
export type DocumentSource = 'approved_snapshot' | 'review_draft' | 'stored_draft' | 'live_preview';

export interface ReportState {
  id?: string;
  status: QuarterlyReportStatus;
  schema_version?: number;
  draft_built_at?: string | null;
  draft_built_by_name?: string | null;
  submitted_at?: string | null;
  approved_at?: string | null;
  approved_by_name?: string | null;
}

export interface QuarterlyPeriodSummary {
  reporting_period_id: string;
  period_year: number;
  period_quarter: number;
  period_label: string;
  period_start: string;
  period_end: string;
  census_status: 'draft' | 'review' | 'approved';
  census_snapshot_exists: boolean;
  report: ReportState;
}

export interface QuarterlyReportList {
  can_manage: boolean;
  can_approve: boolean;
  periods: QuarterlyPeriodSummary[];
}

export interface ReportSpeaker {
  speaker_id: string;
  name: string | null;
  is_member: boolean;
  external_title: string | null;
  external_organization: string | null;
  speaker_role: string | null;
  topic_title: string | null;
  session_label: string | null;
  session_number: number | null;
}

export interface ReportServiceMember {
  assignment_id: string;
  name: string | null;
  is_member: boolean;
  role_code: string | null;
  role_label: string | null;
  team_group: string | null;
  session_number: number | null;
}

export interface ReportPhoto {
  photo_id: string;
  storage_bucket: string;
  storage_path: string;
  caption: string | null;
  alt_text: string | null;
  report_sort_order: number | null;
  session_number: number | null;
}

interface ActivityCommon {
  source_id: string;
  activity_start_date: string | null;
  activity_end_date: string | null;
  meeting_type: string | null;
  location: string | null;
  audience_name: string | null;
  branch_name: string | null;
  section_names: string[];
  chapter_name: string | null;
  participant_count: number | null;
  report_priority: ReportPriority | null;
  report_highlight: string | null;
  speakers: ReportSpeaker[];
  service_team: ReportServiceMember[];
  selected_photos: ReportPhoto[];
}

export interface ReportActivity extends ActivityCommon {
  activity_kind: 'event' | 'program';
  activity_type: string | null;
  title: string;
  sessions_scheduled: number | null;
}

export interface ReportFormationItem extends ActivityCommon {
  source_kind: 'cls' | 'lcs' | 'formation';
  source_title: string;
  program_code: string | null;
  formation_program_title: string | null;
  formation_talk_title: string | null;
  participant_count_is_authoritative: boolean;
  attendance_count: number | null;
  attendance_count_definition: string | null;
  completion_count: number | null;
  completion_data_available: boolean;
}

export interface CensusSectionRow {
  section_code: string;
  section_name: string;
  section_category: string | null;
  branch_name: string | null;
  active_member_count: number;
}

export interface ReportCensus {
  available: boolean;
  census_period_status: string;
  census_approved?: boolean;
  snapshot_date?: string;
  captured_at?: string;
  total_active_members?: number;
  uncategorized_active_members?: number;
  branches?: { branch_name: string; active_member_count: number }[];
  sections?: CensusSectionRow[];
}

export interface ReportSummary {
  total_active_members: number | null;
  branch_totals: { branch_name: string; active_member_count: number }[];
  reportable_events: number;
  reportable_programs: number;
  cls_count: number;
  lcs_count: number;
  formation_count: number;
  cls_registered_participants: number;
  lcs_registered_participants: number;
  known_completions: number | null;
  completion_known_activities: number;
  completion_unavailable_activities: number;
  selected_photos: number;
  speaker_assignments: number;
  service_team_assignments: number;
}

export interface QuarterlyReportDocument {
  schema_version: number;
  header: {
    organization_name: string;
    organization_record_name: string | null;
    area_name: string;
    report_title: string;
    period_year: number;
    period_quarter: number;
    period_label: string;
    period_start: string;
    period_end: string;
    generated_at: string;
  };
  census: ReportCensus;
  major_highlights: ReportActivity[];
  other_activities: ReportActivity[];
  formation_items: ReportFormationItem[];
  summary: ReportSummary;
  readiness: {
    blocking: { census_snapshot_exists: boolean; census_approved: boolean };
    warnings: {
      missing_highlight: number;
      missing_photos: number;
      missing_speakers: number;
      missing_service_team: number;
      completion_unavailable: number;
    };
  };
  approval?: { approved_at: string; approved_by_profile_id: string; approved_by_name: string | null };
}

export interface QuarterlyReportPreview {
  reporting_period_id: string;
  document_source: DocumentSource;
  report: ReportState;
  census_status: string;
  can_manage: boolean;
  can_approve: boolean;
  document: QuarterlyReportDocument;
}

/** Any activity shown in the report (generic or formation). */
export type AnyReportActivity = ReportActivity | ReportFormationItem;

export function activityTitle(a: AnyReportActivity): string {
  return 'title' in a ? a.title : a.source_title;
}

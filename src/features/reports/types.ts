export type ReportingPeriodStatus = 'draft' | 'review' | 'approved';

export interface SectionCensusItem {
  section_node_id: string;
  section_code: string;
  section_name: string;
  section_category: string | null;
  branch_name: string | null;
  branch_code?: string | null;
  display_order?: number;
  current_count: number;
  previous_count: number | null;
  change_count: number | null;
  change_percent: number | null;
}

export interface PreviousQuarterSummary {
  period_year: number;
  period_quarter: number;
  status: string;
  total_active_members: number;
  captured_at: string | null;
}

export interface CensusComparison {
  current_total: number;
  previous_total: number;
  change_total: number;
  change_percent_total: number | null;
}

export interface ExistingPeriodSummary {
  id: string;
  status: ReportingPeriodStatus;
  snapshot_id: string | null;
  captured_at: string | null;
}

export interface CensusPreviewResult {
  organization_id: string;
  period_year: number;
  period_quarter: number;
  period_start: string;
  period_end: string;
  as_of_date: string;
  total_active_members: number;
  uncategorized_active_members: number;
  reconciled: boolean;
  sections: SectionCensusItem[];
  previous_quarter: PreviousQuarterSummary | null;
  comparison: CensusComparison | null;
  existing_period: ExistingPeriodSummary | null;
}

export interface SnapshotHeader {
  id: string;
  snapshot_date: string;
  captured_at: string;
  captured_by_profile_id?: string | null;
  total_active_members: number;
  uncategorized_active_members: number;
  notes?: string | null;
}

export interface ReportingPeriodSummary {
  id: string;
  organization_id: string;
  report_type: string;
  period_year: number;
  period_quarter: number;
  period_start: string;
  period_end: string;
  status: ReportingPeriodStatus;
  notes: string | null;
  created_at: string;
  created_by_profile_id: string | null;
  created_by_name: string | null;
  updated_at: string;
  updated_by_profile_id: string | null;
  approved_at: string | null;
  approved_by_profile_id: string | null;
  approved_by_name: string | null;
  snapshot: SnapshotHeader | null;
}

export interface ReportingPeriodDetail {
  period: ReportingPeriodSummary;
  snapshot: SnapshotHeader | null;
  sections: SectionCensusItem[];
  previous_quarter: PreviousQuarterSummary | null;
  comparison: CensusComparison | null;
  reconciled: boolean;
}

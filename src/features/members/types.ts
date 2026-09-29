export interface DuplicateCandidateMatch {
  member_id: string;
  member_number: string | null;
  display_name: string;
  match_score: number;
  match_reasons: string[];
}

export interface DuplicateWarningResponse {
  status: 'duplicate_warning';
  warning_count: number;
  candidate_matches: DuplicateCandidateMatch[];
}

export interface CreateMemberSuccessResponse {
  status: 'success';
  member_id: string;
  member_number: string | null;
  display_name: string;
  governance_node_id: string | null;
  duplicate_override_applied: boolean;
}

export type CreateMemberRpcResponse = CreateMemberSuccessResponse | DuplicateWarningResponse;

export interface PlacementNodeItem {
  governance_node_id: string;
  node_code: string;
  node_name: string;
  node_type_code: string;
  parent_governance_node_id: string | null;
  parent_node_name: string | null;
  hierarchy_rank: number;
}

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

export interface UpdateMemberBasicProfileInput {
  organizationId: string;
  memberId: string;
  givenNames: string;
  familyName: string;
  middleNames?: string | null;
  preferredName?: string | null;
  birthDate?: string | null;
  sex?: string | null;
  civilStatus?: string | null;
  homeCountryCode?: string | null;
  preferredLanguageCode?: string | null;
  isNameChange: boolean;
  effectiveFrom?: string | null;
  changeReason?: string | null;
}

export interface UpdateMemberBasicProfileResponse {
  status: 'success';
  member_id: string;
  display_name: string;
  is_name_change: boolean;
}

export interface SetMemberAddressData {
  line1: string;
  line2?: string | null;
  city: string;
  state?: string | null;
  postal?: string | null;
  country?: string | null;
}

export interface SetMemberContactPointInput {
  organizationId: string;
  memberId: string;
  contactType: 'email' | 'phone' | 'address';
  operation: 'add' | 'replace_primary' | 'remove';
  targetId?: string | null;
  value?: string | null;
  phoneCountryCode?: string | null;
  addressData?: SetMemberAddressData | null;
  effectiveFrom?: string | null;
  reason?: string | null;
}

export interface SetMemberContactPointResponse {
  status: 'success';
  member_id: string;
  contact_type: 'email' | 'phone' | 'address';
  operation: 'add' | 'replace_primary' | 'remove';
  record_id: string;
}

export interface ChangeMemberGovernanceAssignmentInput {
  organizationId: string;
  memberId: string;
  targetGovernanceNodeId?: string | null;
  effectiveFrom: string; // YYYY-MM-DD
  reason?: string | null;
}

export interface ChangeMemberGovernanceAssignmentResponse {
  status: 'success';
  member_id: string;
  previous_node_id: string | null;
  new_node_id: string | null;
  assignment_id: string | null;
}

export interface MemberStatusOption {
  status_id: string;
  code: string;
  name: string;
  description: string | null;
  status_category: string;
  is_active_membership: boolean;
  display_order: number;
}

export interface ChangeMemberMembershipStatusInput {
  organizationId: string;
  memberId: string;
  targetStatusId: string;
  effectiveFrom: string; // YYYY-MM-DD
  reason?: string | null;
}

export interface ChangeMemberMembershipStatusResponse {
  status: 'success';
  member_id: string;
  previous_status_id: string;
  previous_status_code: string;
  new_status_id: string;
  new_status_code: string;
  effective_from: string;
}

export interface MemberStatusHistoryItem {
  history_id: string;
  status_id: string;
  status_code: string;
  status_name: string;
  status_category: string;
  is_active_membership: boolean;
  effective_from_at: string;
  effective_to_at: string | null;
  change_reason_code: string | null;
  change_summary: string | null;
  source: string;
  recorded_at: string;
  recorded_by_profile_id: string | null;
  recorded_by_name: string | null;
  is_current: boolean;
}

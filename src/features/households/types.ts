export type HouseholdLifecycleStatus =
  | 'planned'
  | 'active'
  | 'temporarily_inactive'
  | 'closed'
  | 'merged'
  | 'archived';

export interface HouseholdSummary {
  household_id: string;
  name: string;
  code: string;
  lifecycle_status: HouseholdLifecycleStatus | string;
  household_category: string;
  parent_node_id: string | null;
  parent_node_name: string | null;
  parent_node_code: string | null;
  parent_node_type: string | null;
  active_member_count: number;
  target_member_count: number | null;
  maximum_member_count: number | null;
  accepts_new_members: boolean;
  meeting_frequency: string | null;
  meeting_day_of_week: number | null;
  meeting_start_time: string | null;
  meeting_timezone_name: string | null;
  meeting_location_type: string | null;
}

export interface HouseholdSearchResult {
  households: HouseholdSummary[];
  total_count: number;
  limit: number;
  offset: number;
}

export interface HouseholdParentGovernance {
  parent_node_id: string;
  parent_node_name: string;
  parent_node_code: string;
  parent_node_type: string;
}

export interface HouseholdLeader {
  leadership_assignment_id: string;
  member_id: string;
  display_name: string;
  leadership_role_code: string;
  leadership_role_name: string;
  effective_from: string;
  effective_to: string | null;
  assignment_status: string;
}

export interface HouseholdMember {
  household_membership_id: string;
  member_id: string;
  member_number: string | null;
  display_name: string;
  membership_status: string;
  membership_role: string;
  is_primary: boolean;
  effective_from: string;
  effective_to: string | null;
}

export interface HouseholdProfileIdentity {
  id: string;
  name: string;
  code: string;
  lifecycle_status: HouseholdLifecycleStatus | string;
  household_category: string;
  effective_from: string;
  effective_to: string | null;
  meeting_frequency: string;
  meeting_day_of_week: number | null;
  meeting_start_time: string | null;
  meeting_timezone_name: string;
  meeting_location_type: string;
  meeting_location_text: string | null;
  target_member_count: number | null;
  maximum_member_count: number | null;
  accepts_new_members: boolean;
  language_code: string;
  is_couple_household: boolean;
  created_at: string;
  updated_at: string;
}

export interface HouseholdLeadersCouple {
  husband: {
    member_id: string;
    display_name: string;
  };
  wife: {
    member_id: string;
    display_name: string;
  };
  pastoral_label: string;
  formatted_names: string;
  effective_from: string;
}

export interface HouseholdProfileData {
  household: HouseholdProfileIdentity;
  parent_governance: HouseholdParentGovernance | null;
  leaders: HouseholdLeader[];
  household_leaders?: HouseholdLeadersCouple | null;
  members: HouseholdMember[];
  counts: {
    active_member_count: number;
    target_member_count: number | null;
    maximum_member_count: number | null;
    accepts_new_members: boolean;
  };
}

export interface MemberHouseholdAssignment {
  household_membership_id: string;
  household_id: string;
  household_name: string;
  household_code: string;
  household_status: string;
  membership_status: string;
  membership_role: string;
  is_primary: boolean;
  effective_from: string;
  effective_to: string | null;
  parent_node_id: string | null;
  parent_node_name: string | null;
  parent_node_type: string | null;
  household_servant_name: string | null;
}

export interface CreateHouseholdInput {
  name: string;
  code: string;
  parent_governance_node_id: string;
  household_category?: string;
  meeting_frequency?: string;
  meeting_day_of_week?: number | null;
  meeting_start_time?: string | null;
  meeting_timezone_name?: string;
  meeting_location_type?: string;
  meeting_location_text?: string | null;
  target_member_count?: number | null;
  maximum_member_count?: number | null;
  accepts_new_members?: boolean;
  language_code?: string;
  is_couple_household?: boolean;
}

export interface CreateHouseholdResult {
  status: 'created';
  household_id: string;
  name: string;
  code: string;
  lifecycle_status: HouseholdLifecycleStatus | string;
  parent_governance_node_id: string;
}

export interface UpdateHouseholdInput {
  household_id: string;
  name: string;
  code: string;
  household_category?: string;
  meeting_frequency?: string;
  meeting_day_of_week?: number | null;
  meeting_start_time?: string | null;
  meeting_timezone_name?: string;
  meeting_location_type?: string;
  meeting_location_text?: string | null;
  target_member_count?: number | null;
  maximum_member_count?: number | null;
  accepts_new_members?: boolean;
  language_code?: string;
  is_couple_household?: boolean;
}

export interface UpdateHouseholdResult {
  status: 'updated' | 'success';
  household_id: string;
  name: string;
  code: string;
  lifecycle_status: HouseholdLifecycleStatus | string;
}

export interface ArchiveHouseholdSuccessResult {
  status: 'success';
  household_id: string;
  lifecycle_status: 'archived';
  archive_reason: string;
}

export interface ArchiveHouseholdBlockedResult {
  status: 'blocked';
  blocker_type: 'active_household_memberships' | 'active_leadership_assignments';
  active_member_count?: number;
  active_leadership_count?: number;
  message: string;
}

export type ArchiveHouseholdResult =
  | ArchiveHouseholdSuccessResult
  | ArchiveHouseholdBlockedResult;

export interface AssignHouseholdMemberInput {
  member_id: string;
  household_id: string;
  effective_from?: string;
  confirm_governance_mismatch?: boolean;
}

export interface AssignHouseholdMemberSuccessResult {
  status: 'assigned';
  household_membership_id: string;
  organization_id: string;
  member_id: string;
  household_id: string;
  household_name: string;
  membership_status: string;
  membership_role: string;
  is_primary: boolean;
  effective_from: string;
}

export interface AssignHouseholdMemberBlockedResult {
  status: 'blocked';
  blocker_type: 'existing_primary_household' | 'already_member_of_destination';
  existing_household_id?: string;
  existing_household_name?: string;
  destination_household_id?: string;
  message: string;
}

export interface AssignHouseholdMemberWarningResult {
  status: 'warning';
  warning_type: 'governance_mismatch' | 'governance_unplaced';
  member_id: string;
  member_governance_node_id: string | null;
  member_governance_name: string | null;
  household_parent_node_id: string;
  household_parent_name: string;
  message: string;
  requires_confirmation: true;
}

export type AssignHouseholdMemberResult =
  | AssignHouseholdMemberSuccessResult
  | AssignHouseholdMemberBlockedResult
  | AssignHouseholdMemberWarningResult;

export interface TransferHouseholdMemberInput {
  member_id: string;
  destination_household_id: string;
  effective_date?: string;
  reason: string;
  confirm_governance_mismatch?: boolean;
}

export interface TransferHouseholdMemberSuccessResult {
  status: 'transferred';
  member_id: string;
  source_household_id: string;
  source_household_name: string;
  destination_household_id: string;
  destination_household_name: string;
  ended_household_membership_id: string;
  new_household_membership_id: string;
  effective_date: string;
}

export interface TransferHouseholdMemberBlockedResult {
  status: 'blocked';
  blocker_type:
    | 'no_current_household'
    | 'multiple_current_households'
    | 'destination_same_as_source'
    | 'active_household_leadership'
    | 'leadership_role_inconsistency';
  message: string;
  active_leadership_count?: number;
  membership_role?: string;
}

export interface TransferHouseholdMemberWarningResult {
  status: 'warning';
  warning_type: 'governance_mismatch' | 'governance_unplaced';
  member_id: string;
  member_governance_node_id: string | null;
  member_governance_name: string | null;
  household_parent_node_id: string;
  household_parent_name: string;
  message: string;
  requires_confirmation: true;
}

export type TransferHouseholdMemberResult =
  | TransferHouseholdMemberSuccessResult
  | TransferHouseholdMemberBlockedResult
  | TransferHouseholdMemberWarningResult;

export interface EndHouseholdMembershipInput {
  member_id: string;
  effective_to?: string;
  reason: string;
}

export interface EndHouseholdMembershipSuccessResult {
  status: 'ended';
  member_id: string;
  household_id: string;
  household_name: string;
  household_membership_id: string;
  effective_to: string;
}

export interface EndHouseholdMembershipBlockedResult {
  status: 'blocked';
  blocker_type: 'active_household_leadership' | 'leadership_role_inconsistency';
  message: string;
  active_leadership_count?: number;
  membership_role?: string;
}

export type EndHouseholdMembershipResult =
  | EndHouseholdMembershipSuccessResult
  | EndHouseholdMembershipBlockedResult;

export interface MemberWithoutHousehold {
  member_id: string;
  member_number: string | null;
  display_name: string;
  primary_governance_node_id: string | null;
  primary_governance_name: string | null;
  primary_governance_type: string | null;
  joined_on: string | null;
}

export interface SearchMembersWithoutHouseholdResult {
  members: MemberWithoutHousehold[];
  total_count: number;
  limit: number;
  offset: number;
}

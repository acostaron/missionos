export type HouseholdLifecycleStatus =
  | 'planned'
  | 'active'
  | 'temporarily_inactive'
  | 'closed'
  | 'merged'
  | 'archived';

export type PastoralLevel =
  | 'member'
  | 'unit'
  | 'chapter'
  | 'area'
  | 'fraternal';

export interface HouseholdSummary {
  household_id: string;
  name: string;
  code: string;
  lifecycle_status: HouseholdLifecycleStatus | string;
  household_category: string;
  pastoral_level: PastoralLevel | string;
  pastoral_level_label?: string;
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
  pastoral_level: PastoralLevel | string;
  pastoral_level_label?: string;
  leadership_source?: string;
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
  formation_summary?: HouseholdFormationSummary;
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
  pastoral_level?: PastoralLevel;
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
  pastoral_level?: PastoralLevel | string;
  parent_governance_node_id: string;
}

export interface UpdateHouseholdInput {
  household_id: string;
  name: string;
  code: string;
  household_category?: string;
  pastoral_level?: PastoralLevel;
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

// =============================================================================
// Phase 6B-5: Servant Leader Appointment Lifecycle & Placement Guidance Types
// =============================================================================

export type ServantLeaderRoleCode =
  | 'household_servant_leader'
  | 'unit_servant_leader'
  | 'chapter_servant_leader'
  | 'area_servant_leader';

export interface AppointServantLeaderInput {
  role_code: ServantLeaderRoleCode;
  governance_node_id: string;
  member_id: string;
  effective_from?: string;
  reason?: string;
}

export interface AppointServantLeaderResult {
  status: 'appointed';
  organization_id: string;
  leadership_assignment_id: string;
  governance_node_id: string;
  member_id: string;
  role_code: ServantLeaderRoleCode;
  role_name: string;
  effective_from: string;
}

export interface ConcludeServantLeaderInput {
  leadership_assignment_id: string;
  effective_to?: string;
  reason: string;
}

export interface ConcludeServantLeaderResult {
  status: 'concluded';
  organization_id: string;
  leadership_assignment_id: string;
  governance_node_id: string;
  member_id: string;
  role_code: ServantLeaderRoleCode;
  role_name: string;
  effective_to: string;
  reason: string;
}

export interface ReplaceServantLeaderInput {
  role_code: ServantLeaderRoleCode;
  governance_node_id: string;
  new_member_id: string;
  effective_date?: string;
  reason: string;
}

export interface ReplaceServantLeaderSuccessResult {
  status: 'replaced';
  organization_id: string;
  governance_node_id: string;
  role_code: ServantLeaderRoleCode;
  role_name: string;
  outgoing_assignment_id: string;
  outgoing_member_id: string;
  incoming_assignment_id: string;
  incoming_member_id: string;
  effective_date: string;
  reason: string;
}

export interface ReplaceServantLeaderBlockedResult {
  status: 'blocked';
  blocker_type: 'no_current_role_holder' | string;
  governance_node_id: string;
  role_code: ServantLeaderRoleCode;
  message: string;
}

export type ReplaceServantLeaderResult =
  | ReplaceServantLeaderSuccessResult
  | ReplaceServantLeaderBlockedResult;

export type PlacementStatus =
  | 'correct'
  | 'missing_household'
  | 'different_level'
  | 'no_matching_household_available'
  | 'manual_review_required';

export interface ServantLeaderPlacementGuidanceResult {
  has_formal_role: boolean;
  formal_role_code?: ServantLeaderRoleCode;
  formal_role_name?: string;
  formal_governance_node_id?: string;
  formal_governance_node_name?: string;
  leadership_assignment_id?: string;
  member_id: string;
  member_name?: string;
  recommended_pastoral_level?: PastoralLevel;
  recommended_scope_node_id?: string | null;
  recommended_scope_node_name?: string | null;
  current_primary_household_id?: string | null;
  current_primary_household_name?: string | null;
  current_primary_pastoral_level?: PastoralLevel | null;
  matching_echelon_households_count?: number;
  placement_status?: PlacementStatus;
  spouse_context?: {
    has_spouse: boolean;
    has_verified_spouse: boolean;
    spouse_member_id: string | null;
    spouse_name: string | null;
    evaluation_rule: string;
  };
  message?: string;
}

export type PastoralPlacementWorkflowStatus =
  | 'already_correct'
  | 'ready_to_assign'
  | 'ready_to_transfer'
  | 'blocked_no_destination'
  | 'blocked_spouse_review'
  | 'blocked_invalid_context'
  | 'manual_review_required';

export type PastoralPlacementRecommendedAction =
  | 'none'
  | 'assign'
  | 'transfer'
  | 'review_spouse'
  | 'create_destination_household';

export type CouplesContextStatus = 'couples' | 'non_couples' | 'ambiguous';

export type CouplesContextSource =
  | 'originating_household'
  | 'primary_section'
  | 'member_governance_assignment'
  | 'pastoral_lineage'
  | 'governance_node_metadata'
  | 'unmarried_individual'
  | 'unresolved';

export type DestinationCapacityStatus =
  | 'available'
  | 'at_target'
  | 'full'
  | 'not_accepting';

export interface PastoralPlacementDestination {
  household_id: string;
  household_name: string;
  pastoral_level: PastoralLevel;
  scope_node_id: string;
  scope_node_name: string;
  is_couple_household: boolean;
  current_member_count: number;
  target_member_count: number | null;
  maximum_member_count: number | null;
  accepts_new_members: boolean;
  capacity_status: DestinationCapacityStatus;
  is_eligible: boolean;
}

export interface PastoralPlacementReview {
  leadership_assignment_id: string;
  formal_role_code: ServantLeaderRoleCode;
  formal_role_name: string;
  leader_member_id: string;
  leader_member_name: string;
  formal_governance_node_id: string;
  formal_governance_node_name: string;
  recommended_pastoral_level: PastoralLevel;
  recommended_scope_node_id: string;
  recommended_scope_node_name: string;
  current_primary_household_id: string | null;
  current_primary_household_name: string | null;
  current_primary_pastoral_level: PastoralLevel | null;
  current_primary_scope_node_id: string | null;
  placement_status: PlacementStatus;
  workflow_status: PastoralPlacementWorkflowStatus;
  recommended_action: PastoralPlacementRecommendedAction;
  required_seats: number;
  couples_context: boolean | null;
  couples_context_status: CouplesContextStatus;
  couples_context_source: CouplesContextSource;
  spouse_context: {
    has_spouse: boolean;
    has_verified_spouse: boolean;
    spouse_member_id: string | null;
    spouse_name: string | null;
  };
  spouse_current_primary_household: {
    household_id: string | null;
    household_name: string | null;
    pastoral_level: PastoralLevel | null;
    scope_node_id: string | null;
  };
  spouse_placement_status: PlacementStatus | null;
  available_destination_households: PastoralPlacementDestination[];
}

export interface PastoralPlacementExecutionInput {
  organizationId: string;
  leadershipAssignmentId: string;
  destinationHouseholdId: string;
  effectiveDate?: string;
  reason: string;
  includeVerifiedSpouse?: boolean;
}

export interface PastoralPlacementMemberPlanResult {
  action: 'assign' | 'transfer' | 'none';
  household_membership_id: string;
  source_household_id: string | null;
  destination_household_id: string;
}

export interface PastoralPlacementExecutionResult {
  status: 'completed';
  leadership_assignment_id: string;
  formal_role_code: ServantLeaderRoleCode;
  destination_household_id: string;
  destination_household_name: string;
  effective_date: string;
  couples_placement: boolean;
  leader_result: PastoralPlacementMemberPlanResult;
  spouse_result: PastoralPlacementMemberPlanResult | null;
  message: string;
}

export interface PastoralPlacementQueueItem {
  leadership_assignment_id: string;
  role_code: ServantLeaderRoleCode;
  role_name: string;
  leader_member_id: string;
  leader_name: string;
  governance_node_id: string;
  governance_node_name: string;
  recommended_pastoral_level: PastoralLevel;
  recommended_scope_node_id: string;
  recommended_scope_name: string;
  current_household_id: string | null;
  current_household_name: string | null;
  placement_status: PlacementStatus;
  couples_context: boolean | null;
  couples_context_status?: CouplesContextStatus;
  spouse_name: string | null;
  spouse_current_household_name: string | null;
}

// =============================================================================
// Phase 6B-7: Pastoral Household Operations & Leader Care Dashboard
// =============================================================================

export type PastoralCapacityStatus = 'available' | 'at_target' | 'full' | 'not_accepting';

export type PastoralLeadershipStatus = 'assigned' | 'vacant' | 'not_applicable' | 'review_required';

export type PastoralOperationalStatus =
  | 'ready'
  | 'needs_leader'
  | 'needs_members'
  | 'at_capacity'
  | 'not_accepting'
  | 'placement_review_required'
  | 'inactive';

export interface PastoralServingAssignment {
  leadership_assignment_id: string;
  role_code: ServantLeaderRoleCode;
  role_name: string;
  governance_node_id: string;
  governance_node_name: string;
  pastoral_level: PastoralLevel | null;
  effective_from: string;
  effective_to: string | null;
}

export interface PastoralCareMembership {
  household_id: string;
  household_name: string;
  pastoral_level: PastoralLevel;
  scope_node_id: string | null;
  scope_node_name: string | null;
  membership_role: string;
  effective_from: string;
  meeting_frequency: string;
  meeting_day_of_week: number | null;
  meeting_start_time: string | null;
  meeting_timezone_name: string | null;
  is_fraternal: boolean;
}

export interface PastoralDashboardIdentity {
  profile_id: string;
  member_id: string | null;
  display_name: string;
  has_linked_member: boolean;
  serving_assignments: PastoralServingAssignment[];
  pastoral_membership: PastoralCareMembership | null;
  pastoral_household_placement_needed: boolean;
}

export interface PastoralCareResponsibility {
  leadership_assignment_id: string;
  responsibility_level: 'household' | 'unit' | 'chapter' | 'area';
  scope_id: string;
  scope_name: string;
  details: {
    type: 'household_members' | 'household_leaders' | 'unit_leaders' | 'chapter_leaders';
    household_id?: string;
    household_name?: string;
    unit_id?: string;
    unit_name?: string;
    chapter_id?: string;
    chapter_name?: string;
    area_id?: string;
    area_name?: string;
    member_count?: number;
    members?: Array<{
      member_id: string;
      display_name: string;
      member_number: string | null;
      membership_role: string;
      effective_from: string;
    }>;
    leaders?: Array<{
      household_id?: string;
      household_name?: string;
      unit_id?: string;
      unit_name?: string;
      chapter_id?: string;
      chapter_name?: string;
      is_couple_household?: boolean;
      leader_member_id: string;
      leader_name: string;
      role_code: ServantLeaderRoleCode;
      effective_from: string;
      couples_context_status?: CouplesContextStatus;
      has_derived_spouse: boolean;
      derived_spouse_name: string | null;
      derived_pastoral_title: string;
    }>;
  };
}

export interface PastoralHouseholdSummary {
  household_id: string;
  household_name: string;
  pastoral_level: PastoralLevel;
  household_category: string;
  lifecycle_status: string;
  is_couple_household: boolean;
  scope_node_id: string | null;
  scope_node_name: string | null;
  formal_leader: {
    leadership_assignment_id: string;
    member_id: string;
    display_name: string;
    role_code: ServantLeaderRoleCode;
    role_name: string;
  } | null;
  derived_leader_spouse: string | null;
  leader_display_label: string;
  member_count: number;
  target_member_count: number | null;
  maximum_member_count: number | null;
  accepts_new_members: boolean;
  capacity_status: PastoralCapacityStatus;
  leadership_status: PastoralLeadershipStatus;
  operational_status: PastoralOperationalStatus;
  meeting_frequency: string;
  meeting_day_of_week: number | null;
  meeting_start_time: string | null;
  meeting_operational_status?: MeetingOperationalStatus;
  last_completed_meeting_date?: string | null;
  next_scheduled_meeting_date?: string | null;
  expected_next_meeting_date?: string | null;
  days_since_last_completed_meeting?: number | null;
}

export interface PastoralLeadershipVacancy {
  governance_node_id: string;
  governance_node_name: string;
  role_code: ServantLeaderRoleCode;
  role_name: string;
  pastoral_level: PastoralLevel | null;
  vacancy_status: 'vacant';
}

export interface PastoralOperationsDashboard {
  organization_id: string;
  identity: PastoralDashboardIdentity;
  care_responsibilities: PastoralCareResponsibility[];
  household_summary: PastoralHouseholdSummary[];
  leadership_vacancies: PastoralLeadershipVacancy[];
  capacity_summary: {
    available: number;
    at_target: number;
    full: number;
    not_accepting: number;
    total: number;
  };
  operational_summary: {
    ready: number;
    needs_leader: number;
    needs_members: number;
    at_capacity: number;
    not_accepting: number;
    placement_review_required: number;
    inactive: number;
    total: number;
  };
  placement_review_summary: {
    missing_household: number;
    different_level: number;
    no_matching_household_available: number;
    manual_review_required: number;
    total: number;
    actionable_items: PastoralPlacementQueueItem[];
  };
  unassigned_members_count: number;
}

export interface PastoralHouseholdRosterMember {
  member_id: string;
  member_number: string | null;
  display_name: string;
  membership_id: string;
  membership_role: string;
  membership_status: string;
  effective_from: string;
  is_primary: boolean;
}

export interface PastoralHouseholdRoster {
  household_id: string;
  household_name: string;
  household_category: string;
  pastoral_level: PastoralLevel;
  lifecycle_status: string;
  is_couple_household: boolean;
  scope_node_id: string | null;
  scope_node_name: string | null;
  target_member_count: number | null;
  maximum_member_count: number | null;
  accepts_new_members: boolean;
  meeting_frequency: string;
  meeting_day_of_week: number | null;
  meeting_start_time: string | null;
  meeting_timezone_name: string | null;
  formal_leader: {
    leadership_assignment_id: string;
    member_id: string;
    display_name: string;
    role_code: ServantLeaderRoleCode;
    role_name: string;
    effective_from: string;
  } | null;
  derived_leader_spouse: string | null;
  is_fraternal: boolean;
  members_count: number;
  members: PastoralHouseholdRosterMember[];
}

// =============================================================================
// Phase 6B-8: Household Meetings, Attendance & Pastoral Follow-up
// =============================================================================

export type HouseholdMeetingStatus = 'scheduled' | 'completed' | 'cancelled';

export type HouseholdMeetingType =
  | 'regular_household'
  | 'special_household'
  | 'fellowship'
  | 'formation'
  | 'prayer'
  | 'other';

export type HouseholdLocationTypeMeeting = 'in_person' | 'virtual' | 'hybrid';

export type AttendanceStatusValue = 'present' | 'absent' | 'excused';

export interface AttendanceSummary {
  expected_member_count: number;
  recorded_attendance_count: number;
  present_count: number;
  absent_count: number;
  excused_count: number;
  attendance_complete: boolean;
}

/** A single meeting row in get_household_meeting_history */
export interface HouseholdMeetingRow {
  household_meeting_id: string;
  meeting_date: string;
  meeting_status: HouseholdMeetingStatus;
  meeting_type: HouseholdMeetingType;
  location_type: HouseholdLocationTypeMeeting | null;
  location_text: string | null;
  facilitator_member_id: string | null;
  facilitator_display_name: string | null;
  host_member_id: string | null;
  host_display_name: string | null;
  attendance_recorded_at: string | null;
  attendance_summary: AttendanceSummary;
  scheduled_start_at: string | null;
  scheduled_end_at: string | null;
  created_at: string;
}

export type MeetingOperationalStatus =
  | 'attendance_pending'
  | 'scheduled'
  | 'no_meeting_history'
  | 'overdue'
  | 'current'
  | 'not_configured';

export interface HouseholdMeetingCadence {
  last_completed_meeting_date: string | null;
  next_scheduled_meeting_date: string | null;
  expected_next_meeting_date: string | null;
  days_since_last_completed_meeting: number | null;
  meeting_frequency: string | null;
  meeting_operational_status: MeetingOperationalStatus;
}

/** Return shape of get_household_meeting_history */
export interface HouseholdMeetingHistory {
  household_id: string;
  household_name: string;
  total_count: number;
  limit: number;
  offset: number;
  meetings: HouseholdMeetingRow[];
  cadence?: HouseholdMeetingCadence;
  last_completed_meeting_date?: string | null;
  next_scheduled_meeting_date?: string | null;
  expected_next_meeting_date?: string | null;
  days_since_last_completed_meeting?: number | null;
  meeting_frequency?: string | null;
  meeting_operational_status?: MeetingOperationalStatus;
}

/** An attendance record within a meeting detail */
export interface HouseholdMeetingAttendanceRecord {
  member_id: string;
  display_name: string | null;
  attendance_status: AttendanceStatusValue;
  arrival_time: string | null;
  recorded_at: string;
}

/** An expected roster member */
export interface HouseholdMeetingRosterMember {
  member_id: string;
  display_name: string;
  membership_role: string;
}

/** Return shape of get_household_meeting_detail (Phase 6B-8: notes_summary absent) */
export interface HouseholdMeetingDetail {
  household_meeting_id: string;
  household_node_id: string;
  household_name: string;
  meeting_date: string;
  meeting_status: HouseholdMeetingStatus;
  meeting_type: HouseholdMeetingType;
  location_type: HouseholdLocationTypeMeeting | null;
  location_text: string | null;
  scheduled_start_at: string | null;
  scheduled_end_at: string | null;
  actual_start_at: string | null;
  actual_end_at: string | null;
  facilitator_member_id: string | null;
  facilitator_display_name: string | null;
  host_member_id: string | null;
  host_display_name: string | null;
  attendance_recorded_at: string | null;
  attendance_summary: AttendanceSummary;
  expected_roster: HouseholdMeetingRosterMember[];
  recorded_attendance: HouseholdMeetingAttendanceRecord[];
  created_at: string;
}

/** Dashboard meeting_operations_summary block (Phase 6B-8) */
export interface MeetingOperationsSummary {
  upcoming_meetings: number;
  meetings_this_month: number;
  attendance_pending: number;
  households_without_meeting_history: number;
  households_overdue: number;
  member_follow_up_signals: number;
}

/** Extended PastoralOperationsDashboard (Phase 6B-8 addition) */
export interface PastoralOperationsDashboardV2 extends PastoralOperationsDashboard {
  meeting_operations_summary: MeetingOperationsSummary;
  formation_operations_summary?: FormationOperationsSummary;
}

// =============================================================================
// Phase 6B-9: Delegated Servant Leader Access
// =============================================================================

export type ServantLeaderAccessStatusType = 'none' | 'active' | 'revoked' | 'expired';

export type ServantLeaderEligibilityStatus =
  | 'eligible'
  | 'no_linked_profile'
  | 'leadership_not_current'
  | 'unsupported_role'
  | 'already_active'
  | 'future_effective';

export interface ServantLeaderAccessStatus {
  leadership_assignment_id: string;
  leader_member_id: string;
  leader_member_name: string;
  role_code: string;
  role_name: string;
  governance_node_id: string;
  governance_node_name: string;
  linked_profile_id: string | null;
  has_linked_profile: boolean;
  access_grant_id: string | null;
  access_status: ServantLeaderAccessStatusType;
  eligibility_status: ServantLeaderEligibilityStatus;
  app_role_code: string | null;
  app_role_name: string | null;
  granted_at: string | null;
  granted_by_profile_id: string | null;
  revoked_at: string | null;
  revoked_by_profile_id: string | null;
  revocation_reason: string | null;
  effective_from: string | null;
  effective_to: string | null;
}

export interface GrantServantLeaderAccessResult {
  grant_id: string;
  leadership_assignment_id: string;
  profile_id: string;
  member_id: string;
  member_name: string;
  role_code: string;
  app_role_code: string;
  governance_node_id: string;
  governance_node_name: string;
  access_status: string;
  granted_at: string;
}

export interface RevokeServantLeaderAccessResult {
  grant_id: string;
  leadership_assignment_id: string;
  profile_id: string;
  member_id: string;
  access_status: string;
  revoked_at: string;
  reason: string;
}

// =============================================================================
// Phase 6B-10: Household Formation
// =============================================================================

export type HouseholdFormationStatus =
  | 'no_plan'
  | 'planned'
  | 'topic_due'
  | 'topic_overdue'
  | 'up_to_date';

export type HouseholdTopicAssignmentStatus = 'planned' | 'completed' | 'skipped' | 'cancelled';

export type HouseholdTopicReasonCode =
  | 'schedule_change'
  | 'topic_replaced'
  | 'not_applicable'
  | 'other';

export interface FormationTopic {
  id: string;
  organization_id: string | null;
  title: string;
  short_title: string | null;
  topic_code: string | null;
  description: string | null;
  objectives: string | null;
  source_type: string;
  scripture_reference: string | null;
  recommended_duration_minutes: number | null;
  recommended_pastoral_level: string | null;
  sort_order: number | null;
  is_active: boolean;
}

export interface FormationTopicSearchResult {
  total_count: number;
  limit: number;
  offset: number;
  topics: FormationTopic[];
}

/** Compact topic reference embedded in the profile formation_summary. */
export interface HouseholdFormationTopicRef {
  assignment_id: string;
  topic_id: string;
  title: string;
  planned_for_date?: string | null;
  sequence_number?: number | null;
  completed_at?: string | null;
  meeting_date?: string | null;
}

/** Topic reference returned by get_household_formation_plan. */
export interface HouseholdFormationPlanTopic extends HouseholdFormationTopicRef {
  short_title?: string | null;
  topic_code?: string | null;
  source_type?: string | null;
  scripture_reference?: string | null;
  recommended_duration_minutes?: number | null;
  completed_household_meeting_id?: string | null;
}

export interface HouseholdFormationSummary {
  formation_status: HouseholdFormationStatus;
  next_topic: HouseholdFormationTopicRef | null;
  last_completed_topic: HouseholdFormationTopicRef | null;
  planned_topics_count: number;
  completed_topics_count: number;
}

export interface HouseholdFormationPlan {
  household_id: string;
  formation_status: HouseholdFormationStatus;
  next_topic: HouseholdFormationPlanTopic | null;
  upcoming_topics: HouseholdFormationPlanTopic[];
  last_completed_topic: HouseholdFormationPlanTopic | null;
  last_completed_date: string | null;
  planned_count: number;
  completed_count: number;
}

export interface HouseholdTopicHistoryRow {
  assignment_id: string;
  topic_id: string;
  topic_title: string;
  topic_code: string | null;
  source_type: string;
  scripture_reference: string | null;
  sequence_number: number | null;
  planned_for_date: string | null;
  assignment_status: HouseholdTopicAssignmentStatus;
  assigned_at: string;
  completed_at: string | null;
  completed_household_meeting_id: string | null;
  meeting_date: string | null;
  meeting_type: string | null;
  resolution_reason_code: HouseholdTopicReasonCode | null;
}

export interface HouseholdTopicHistory {
  total_count: number;
  limit: number;
  offset: number;
  history: HouseholdTopicHistoryRow[];
}

/** Dashboard formation_operations_summary block (Phase 6B-10) */
export interface FormationOperationsSummary {
  households_with_no_plan: number;
  topics_planned: number;
  topics_completed_this_month: number;
  topics_due: number;
  topics_overdue: number;
}

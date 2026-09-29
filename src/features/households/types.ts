export interface HouseholdSummary {
  household_id: string;
  name: string;
  code: string;
  lifecycle_status: string;
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
  lifecycle_status: string;
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

export interface HouseholdProfileData {
  household: HouseholdProfileIdentity;
  parent_governance: HouseholdParentGovernance | null;
  leaders: HouseholdLeader[];
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

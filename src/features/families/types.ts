export interface FamilyMembershipStatus {
  code: string;
  name: string;
  status_category: string;
  is_active_membership: boolean;
}

export interface FamilyProfileMember {
  family_member_id: string;
  member_id: string;
  member_number: string | null;
  display_name: string;
  preferred_name: string | null;
  family_role: string | null;
  is_primary_contact: boolean;
  is_dependent: boolean;
  membership_status: FamilyMembershipStatus | null;
  record_status: string;
  is_deceased: boolean;
  effective_from: string | null;
  effective_to: string | null;
}

export interface FamilyRelationshipTypeSummary {
  code: string;
  name: string;
  inverse_code: string;
  is_symmetric: boolean;
  category: string;
}

export interface FamilyProfileRelationship {
  relationship_id: string;
  from_member_id: string;
  to_member_id: string;
  relationship_type: FamilyRelationshipTypeSummary;
  effective_from: string | null;
  effective_to: string | null;
  relationship_status: string;
  verification_status: string;
  source: string | null;
}

export interface FamilyIdentity {
  id: string;
  family_name: string;
  display_name: string;
  family_type: string;
  family_status: string;
  formed_on: string | null;
  ended_on: string | null;
  directory_visibility: string;
  created_at: string;
  updated_at: string;
}

export interface FamilyProfile {
  family: FamilyIdentity;
  members: FamilyProfileMember[];
  relationships: FamilyProfileRelationship[] | null;
}

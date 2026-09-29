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

export const FAMILY_TYPES = [
  { value: 'household_family', label: 'Household family' },
  { value: 'married_couple', label: 'Married couple' },
  { value: 'single_parent_family', label: 'Single-parent family' },
  { value: 'guardian_family', label: 'Guardian family' },
  { value: 'extended_family', label: 'Extended family' },
  { value: 'other', label: 'Other' },
] as const;

export type FamilyTypeCode = (typeof FAMILY_TYPES)[number]['value'];

export interface CreateFamilyInput {
  organizationId: string;
  displayName: string;
  familyName: string;
  familyType?: string;
  formedOn?: string | null;
  confirmDuplicate?: boolean;
}

export interface DuplicateFamilyMatch {
  family_id: string;
  family_name: string;
  display_name: string;
  family_status: string;
  formed_on: string | null;
}

export interface CreateFamilySuccessResponse {
  status: 'created';
  family_id: string;
  display_name: string;
  family_name: string;
  family_status: string;
  warning_count: number;
}

export interface CreateFamilyWarningResponse {
  status: 'warning';
  warning_type: 'duplicate_family_detected';
  warning_count: number;
  warnings: DuplicateFamilyMatch[];
}

export type CreateFamilyResult = CreateFamilySuccessResponse | CreateFamilyWarningResponse;

export interface UpdateFamilyIdentityInput {
  organizationId: string;
  familyId: string;
  displayName: string;
  familyName: string;
  familyType?: string;
  formedOn?: string | null;
}

export interface UpdateFamilyIdentityResponse {
  status: 'success';
  family_id: string;
  display_name: string;
  family_name: string;
  family_type: string;
  formed_on: string | null;
}

export interface ArchiveFamilyRecordInput {
  organizationId: string;
  familyId: string;
  reason: string;
  confirmWithActiveMembers?: boolean;
}

export interface ArchiveFamilySuccessResponse {
  status: 'success';
  family_id: string;
  family_status: 'archived';
  ended_on: string;
  active_member_count: number;
  active_relationship_count: number;
}

export interface ArchiveFamilyWarningResponse {
  status: 'warning';
  warning_type: 'active_members_present';
  active_member_count: number;
  active_relationship_count: number;
  message: string;
}

export type ArchiveFamilyResult = ArchiveFamilySuccessResponse | ArchiveFamilyWarningResponse;

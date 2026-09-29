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

export const FAMILY_ROLES = [
  { value: 'parent', label: 'Parent' },
  { value: 'spouse', label: 'Spouse' },
  { value: 'child', label: 'Child' },
  { value: 'guardian', label: 'Guardian' },
  { value: 'dependent', label: 'Dependent' },
  { value: 'relative', label: 'Relative' },
  { value: 'family_contact', label: 'Family contact' },
  { value: 'other', label: 'Other' },
] as const;

export type FamilyRoleCode = (typeof FAMILY_ROLES)[number]['value'];

export interface ExistingFamilyMembership {
  family_id: string;
  family_name: string;
  display_name: string;
  family_status: string;
  family_role: string | null;
}

export interface AddFamilyMemberInput {
  organizationId: string;
  familyId: string;
  memberId: string;
  familyRole?: string | null;
  isPrimaryContact?: boolean;
  isDependent?: boolean;
  effectiveFrom?: string | null;
  confirmMultipleActiveFamily?: boolean;
}

export interface AddFamilyMemberSuccessResponse {
  status: 'created';
  family_member_id: string;
  family_id: string;
  member_id: string;
  family_role: string | null;
  effective_from: string;
  warning_count: number;
}

export interface AddFamilyMemberWarningResponse {
  status: 'warning';
  warning_type: 'multiple_active_family_memberships';
  warning_count: number;
  existing_families: ExistingFamilyMembership[];
}

export type AddFamilyMemberResult = AddFamilyMemberSuccessResponse | AddFamilyMemberWarningResponse;

export interface UpdateFamilyMemberInput {
  organizationId: string;
  familyMemberId: string;
  familyRole?: string | null;
  isPrimaryContact?: boolean;
  isDependent?: boolean;
}

export interface UpdateFamilyMemberResponse {
  status: 'success';
  family_member_id: string;
  family_id: string;
  member_id: string;
  family_role: string | null;
  is_primary_contact: boolean;
  is_dependent: boolean;
}

export interface EndFamilyMembershipInput {
  organizationId: string;
  familyMemberId: string;
  effectiveTo?: string | null;
  reason: string;
}

export interface EndFamilyMembershipResponse {
  status: 'success';
  family_member_id: string;
  family_id: string;
  member_id: string;
  membership_status: 'ended';
  effective_to: string;
}

export interface FamilyRelationshipType {
  type_id: string;
  code: string;
  name: string;
  inverse_code: string | null;
  relationship_category: string;
  is_symmetric: boolean;
  requires_same_family: boolean;
  allows_multiple_current: boolean;
  display_order: number;
  is_active: boolean;
}

export interface AddFamilyRelationshipInput {
  organizationId: string;
  familyId: string;
  fromMemberId: string;
  toMemberId: string;
  relationshipTypeCode: string;
  effectiveFrom?: string | null;
}

export interface AddFamilyRelationshipResponse {
  status: 'created';
  relationship_id: string;
  reciprocal_relationship_id?: string;
  family_id: string;
  from_member_id: string;
  to_member_id: string;
  relationship_code: string;
  effective_from: string;
}

export interface EndFamilyRelationshipInput {
  organizationId: string;
  relationshipId: string;
  effectiveTo?: string | null;
  reason: string;
}

export interface EndFamilyRelationshipResponse {
  status: 'success';
  relationship_id: string;
  family_id: string;
  relationship_status: 'ended';
  effective_to: string;
}

export interface RepairFamilyRelationshipReciprocalInput {
  organizationId: string;
  relationshipId: string;
  reason: string;
}

export interface RepairFamilyRelationshipReciprocalResponse {
  status: 'repaired';
  existing_relationship_id: string;
  reciprocal_relationship_id: string;
  existing_relationship_code: string;
  reciprocal_relationship_code: string;
}

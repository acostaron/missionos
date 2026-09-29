import { supabase } from '../../../lib/supabase/client';
import type { CreateMemberRpcResponse } from '../types';

export interface CreateMemberInput {
  organizationId: string;
  givenNames: string;
  familyName: string;
  middleNames?: string | null;
  preferredName?: string | null;
  birthDate?: string | null;
  sex?: string | null;
  civilStatus?: string | null;
  joinedOn?: string | null;
  homeCountryCode?: string | null;
  governanceNodeId?: string | null;
  allocateMemberNumber?: boolean;
  email?: string | null;
  phone?: string | null;
  phoneCountryCode?: string | null;
  addressLine1?: string | null;
  addressLine2?: string | null;
  cityName?: string | null;
  stateProvinceName?: string | null;
  postalCode?: string | null;
  addressCountryCode?: string | null;
  allowPotentialDuplicate?: boolean;
}

export interface CallerPermissions {
  canManageIdentifiers: boolean;
  canManagePlacements: boolean;
  canManageContacts: boolean;
  canManageAddresses: boolean;
}

export async function createMember(
  input: CreateMemberInput,
  permissions: CallerPermissions
): Promise<CreateMemberRpcResponse> {
  // Normalize empty strings to explicit null for nullable RPC arguments
  const cleanOrNull = (val?: string | null): string | null => {
    if (!val) return null;
    const t = val.trim();
    return t.length > 0 ? t : null;
  };

  const payload = {
    p_organization_id: input.organizationId,
    p_given_names: input.givenNames.trim(),
    p_family_name: input.familyName.trim(),
    p_middle_names: cleanOrNull(input.middleNames) ?? undefined,
    p_preferred_name: cleanOrNull(input.preferredName) ?? undefined,
    p_birth_date: cleanOrNull(input.birthDate) ?? undefined,
    p_sex: cleanOrNull(input.sex) ?? undefined,
    p_civil_status: cleanOrNull(input.civilStatus) ?? undefined,
    p_joined_on: cleanOrNull(input.joinedOn) || new Date().toISOString().split('T')[0],
    p_home_country_code: cleanOrNull(input.homeCountryCode) || 'US',
    // Only pass governance_node_id if authorized, otherwise undefined
    p_governance_node_id: permissions.canManagePlacements ? (cleanOrNull(input.governanceNodeId) ?? undefined) : undefined,
    // Explicit booleans
    p_allocate_member_number: permissions.canManageIdentifiers ? (input.allocateMemberNumber ?? true) : false,
    p_allow_potential_duplicate: input.allowPotentialDuplicate ?? false,
    // Only pass email/phone if authorized, otherwise undefined
    p_email: permissions.canManageContacts ? (cleanOrNull(input.email) ?? undefined) : undefined,
    p_phone: permissions.canManageContacts ? (cleanOrNull(input.phone) ?? undefined) : undefined,
    p_phone_country_code: permissions.canManageContacts ? (cleanOrNull(input.phoneCountryCode) || 'US') : 'US',
    // Only pass address if authorized, otherwise undefined
    p_address_line_1: permissions.canManageAddresses ? (cleanOrNull(input.addressLine1) ?? undefined) : undefined,
    p_address_line_2: permissions.canManageAddresses ? (cleanOrNull(input.addressLine2) ?? undefined) : undefined,
    p_city_name: permissions.canManageAddresses ? (cleanOrNull(input.cityName) ?? undefined) : undefined,
    p_state_province_name: permissions.canManageAddresses ? (cleanOrNull(input.stateProvinceName) ?? undefined) : undefined,
    p_postal_code: permissions.canManageAddresses ? (cleanOrNull(input.postalCode) ?? undefined) : undefined,
    p_address_country_code: permissions.canManageAddresses ? (cleanOrNull(input.addressCountryCode) || 'US') : 'US',
  };

  const { data, error } = await supabase.rpc('create_member', payload);

  if (error) {
    throw error;
  }

  return data as unknown as CreateMemberRpcResponse;
}

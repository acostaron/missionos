/**
 * Member directory and profile TanStack Query hooks.
 *
 * Both RPCs are SECURITY DEFINER and enforce:
 *   - Organization access
 *   - members.records.view permission
 *   - Per-member scope via private.can_access_member()
 *   - Field-level scope per permission section
 *
 * The frontend never calls these with service_role or elevated credentials.
 * The authenticated browser session JWT is used automatically by the Supabase client.
 */

import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface MemberStatus {
  id: string;
  code: string;
  name: string;
  status_category: string;
  is_active_membership: boolean;
}

/** A single row from search_members.members[] */
export interface MemberListItem {
  id: string;
  display_name: string;
  preferred_name: string | null;
  record_status: string;
  /** null when caller lacks members.identifiers.view for this member */
  member_number: string | null;
  membership_status: MemberStatus | null;
}

export interface SearchMembersResult {
  total_count: number;
  page: number;
  page_size: number;
  members: MemberListItem[];
}

export interface MemberIdentifier {
  id: string;
  identifier_type: string;
  identifier_value: string;
  is_primary: boolean;
  verification_status: string | null;
}

export interface MemberEmail {
  id: string;
  email_address: string;
  email_type: string | null;
  is_primary: boolean;
  verification_status: string | null;
}

export interface MemberPhone {
  id: string;
  phone_number: string;
  phone_type: string | null;
  is_primary: boolean;
  normalized_e164: string | null;
}

export interface MemberContacts {
  emails: MemberEmail[];
  phones: MemberPhone[];
}

export interface AddressDetail {
  address_line_1: string | null;
  address_line_2: string | null;
  address_line_3: string | null;
  city_name: string | null;
  state_province_name: string | null;
  postal_code: string | null;
  country_code: string | null;
  formatted_address: string | null;
}

export interface MemberAddress {
  id: string;
  address_type: string | null;
  is_primary: boolean;
  is_mailing_address: boolean;
  address: AddressDetail;
}

export interface SectionPlacement {
  section_membership_id: string;
  section_node_id: string;
  section_name: string;
  section_code: string;
  membership_status: string;
  effective_from: string;
}

export interface HouseholdPlacement {
  household_membership_id: string;
  household_node_id: string;
  household_name: string;
  household_code: string;
  membership_status: string;
  membership_role: string | null;
  effective_from: string;
}

export interface GovernancePlacement {
  assignment_id: string;
  governance_node_id: string;
  node_name: string;
  node_code: string;
  assignment_type: string | null;
  assignment_basis: string | null;
  assignment_status: string;
  effective_from: string;
}

/**
 * Full member profile returned by get_member_profile.
 *
 * Permission-gated sections are typed as `null | T`:
 *   - null  = caller lacks the required permission for this member's scope
 *             OR the member has no data for this section
 *   - T     = data is present and caller is authorized
 *
 * The key is always present in the JSON response (never absent),
 * so the frontend can safely use `profile.contacts === null` to decide
 * whether to show an "access restricted" indicator vs. an empty list.
 */
export interface MemberProfile {
  id: string;
  display_name: string;
  preferred_name: string | null;
  sort_name: string;
  record_status: string;
  /** null when caller lacks members.identifiers.view for this member */
  member_number: string | null;
  membership_status: MemberStatus | null;

  /** null = no members.identifiers.view for this member */
  identifiers: MemberIdentifier[] | null;

  /** null = no members.contacts.view for this member */
  contacts: MemberContacts | null;

  /** null = no members.addresses.view for this member */
  addresses: MemberAddress[] | null;

  /** null = no members.sections.view OR no active primary section */
  section_placement: SectionPlacement | null;

  /** null = no members.households.view OR no active primary household */
  household_placement: HouseholdPlacement | null;

  /** null = no members.placements.view OR no active primary assignment */
  governance_placement: GovernancePlacement | null;
}

// ---------------------------------------------------------------------------
// Query keys
// ---------------------------------------------------------------------------

export const memberKeys = {
  all: ['members'] as const,
  lists: () => [...memberKeys.all, 'list'] as const,
  list: (orgId: string, params: SearchMembersParams) =>
    [...memberKeys.lists(), orgId, params] as const,
  profiles: () => [...memberKeys.all, 'profile'] as const,
  profile: (orgId: string, memberId: string) =>
    [...memberKeys.profiles(), orgId, memberId] as const,
};

// ---------------------------------------------------------------------------
// search_members hook
// ---------------------------------------------------------------------------

export interface SearchMembersParams {
  search?: string;
  recordStatus?: string;
  statusIds?: string[];
  page?: number;
  pageSize?: number;
}

export function useSearchMembers(
  organizationId: string | null,
  params: SearchMembersParams = {},
) {
  const {
    search,
    recordStatus = 'active',
    statusIds,
    page = 1,
    pageSize = 50,
  } = params;

  return useQuery({
    queryKey: organizationId
      ? memberKeys.list(organizationId, params)
      : ([] as unknown as ReturnType<typeof memberKeys.list>),
    queryFn: async (): Promise<SearchMembersResult> => {
      if (!organizationId) throw new Error('organizationId is required');

      const { data, error } = await supabase.rpc('search_members', {
        p_organization_id: organizationId,
        p_search: search || undefined,
        p_record_status: recordStatus,
        p_status_ids: statusIds && statusIds.length > 0 ? statusIds : undefined,
        p_page: page,
        p_page_size: pageSize,
      });

      if (error) throw error;
      return data as unknown as SearchMembersResult;
    },
    enabled: !!organizationId,
    // Keep previous page data visible while fetching new page (no flash)
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
}

// ---------------------------------------------------------------------------
// get_member_profile hook
// ---------------------------------------------------------------------------

export function useMemberProfile(
  organizationId: string | null,
  memberId: string | null,
) {
  return useQuery({
    queryKey:
      organizationId && memberId
        ? memberKeys.profile(organizationId, memberId)
        : ([] as unknown as ReturnType<typeof memberKeys.profile>),
    queryFn: async (): Promise<MemberProfile> => {
      if (!organizationId || !memberId) throw new Error('organizationId and memberId are required');

      const { data, error } = await supabase.rpc('get_member_profile', {
        p_organization_id: organizationId,
        p_member_id: memberId,
      });

      if (error) throw error;
      return data as unknown as MemberProfile;
    },
    enabled: !!organizationId && !!memberId,
    staleTime: 60_000,
    retry: (failureCount, error) => {
      // Do not retry P0002 (member not found / not accessible) — it won't change
      const supabaseError = error as { code?: string };
      if (supabaseError?.code === 'P0002') return false;
      return failureCount < 2;
    },
  });
}

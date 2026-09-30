import { supabase } from '../../../lib/supabase/client';
import type { SearchMembersWithoutHouseholdResult } from '../types';

export interface SearchMembersWithoutHouseholdParams {
  search?: string;
  limit?: number;
  offset?: number;
}

export async function searchMembersWithoutHousehold(
  organizationId: string,
  params?: SearchMembersWithoutHouseholdParams
): Promise<SearchMembersWithoutHouseholdResult> {
  const { data, error } = await supabase.rpc('search_members_without_household', {
    p_organization_id: organizationId,
    p_search: params?.search ? params.search.trim() : undefined,
    p_limit: params?.limit ?? 50,
    p_offset: params?.offset ?? 0,
  });

  if (error) {
    throw error;
  }

  return data as unknown as SearchMembersWithoutHouseholdResult;
}

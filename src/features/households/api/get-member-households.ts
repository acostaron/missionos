import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { householdKeys } from '../queries';
import type { MemberHouseholdAssignment } from '../types';

export async function fetchMemberHouseholds(
  organizationId: string,
  memberId: string
): Promise<MemberHouseholdAssignment[]> {
  const { data, error } = await supabase.rpc('get_member_households', {
    p_organization_id: organizationId,
    p_member_id: memberId,
  });

  if (error) throw error;
  return (data as unknown as MemberHouseholdAssignment[]) || [];
}

export function useMemberHouseholds(
  organizationId: string | null,
  memberId: string | null,
  enabled: boolean = true
) {
  return useQuery({
    queryKey:
      organizationId && memberId
        ? householdKeys.member(organizationId, memberId)
        : householdKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!memberId) throw new Error('memberId is required');
      return fetchMemberHouseholds(organizationId, memberId);
    },
    enabled: !!organizationId && !!memberId && enabled,
    staleTime: 60 * 1000,
  });
}

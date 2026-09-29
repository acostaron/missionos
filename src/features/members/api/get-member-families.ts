import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { memberKeys } from '../queries';
import type { MemberFamilySummary } from '../types';

export async function fetchMemberFamilies(
  organizationId: string,
  memberId: string
): Promise<MemberFamilySummary[]> {
  const { data, error } = await supabase.rpc('get_member_families', {
    p_organization_id: organizationId,
    p_member_id: memberId,
  });

  if (error) throw error;
  return (data as MemberFamilySummary[]) || [];
}

export function useMemberFamilies(
  organizationId: string | null,
  memberId: string | null,
  enabled: boolean = true
) {
  return useQuery({
    queryKey:
      organizationId && memberId
        ? memberKeys.families(organizationId, memberId)
        : memberKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!memberId) throw new Error('memberId is required');
      return fetchMemberFamilies(organizationId, memberId);
    },
    enabled: !!organizationId && !!memberId && enabled,
    staleTime: 60 * 1000,
  });
}

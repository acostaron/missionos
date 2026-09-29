import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { memberKeys } from '../queries';
import type { MemberStatusHistoryItem } from '../types';

export async function fetchMemberStatusHistory(
  organizationId: string,
  memberId: string
): Promise<MemberStatusHistoryItem[]> {
  const { data, error } = await supabase.rpc('get_member_status_history', {
    p_organization_id: organizationId,
    p_member_id: memberId,
  });

  if (error) throw error;
  return (data as MemberStatusHistoryItem[]) || [];
}

export function useMemberStatusHistory(
  organizationId: string | null,
  memberId: string | null,
  enabled: boolean = true
) {
  return useQuery({
    queryKey:
      organizationId && memberId
        ? memberKeys.statusHistory(organizationId, memberId)
        : memberKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!memberId) throw new Error('memberId is required');
      return fetchMemberStatusHistory(organizationId, memberId);
    },
    enabled: !!organizationId && !!memberId && enabled,
    staleTime: 60 * 1000, // 1 minute
  });
}

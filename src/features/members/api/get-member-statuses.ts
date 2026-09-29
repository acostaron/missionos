import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { memberKeys } from '../queries';
import type { MemberStatusOption } from '../types';

export async function fetchMemberStatuses(organizationId: string): Promise<MemberStatusOption[]> {
  const { data, error } = await supabase.rpc('get_member_statuses', {
    p_organization_id: organizationId,
  });

  if (error) throw error;
  return (data as MemberStatusOption[]) || [];
}

export function useMemberStatuses(organizationId: string | null, enabled: boolean = true) {
  return useQuery({
    queryKey: organizationId ? memberKeys.statuses(organizationId) : memberKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      return fetchMemberStatuses(organizationId);
    },
    enabled: !!organizationId && enabled,
    staleTime: 10 * 60 * 1000, // 10 minutes cache as status reference rarely changes
  });
}

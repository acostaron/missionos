import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { fetchMemberAccountStatus, provisionMemberAccount } from './api';
import type { ProvisionMemberAccountParams, MemberAccountStatus } from './types';

export function useMemberAccountStatus(
  organizationId: string | null | undefined,
  memberId: string | null | undefined,
  options?: { enabled?: boolean }
) {
  return useQuery<MemberAccountStatus>({
    queryKey: ['member-account-status', organizationId, memberId],
    queryFn: () => {
      if (!organizationId || !memberId) {
        throw new Error('Organization ID and Member ID are required');
      }
      return fetchMemberAccountStatus(organizationId, memberId);
    },
    enabled: !!organizationId && !!memberId && (options?.enabled ?? true),
  });
}

export function useProvisionMemberAccount() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ProvisionMemberAccountParams) => provisionMemberAccount(params),
    onSuccess: (result, variables) => {
      if (result.success) {
        queryClient.invalidateQueries({
          queryKey: ['member-account-status', variables.organization_id, variables.member_id],
        });
        queryClient.invalidateQueries({
          queryKey: ['member-profile', variables.organization_id, variables.member_id],
        });
      }
    },
  });
}

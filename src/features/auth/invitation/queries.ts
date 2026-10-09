import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  fetchMemberAccountStatus,
  provisionMemberAccount,
  fetchMyPendingAccountInvitations,
} from './api';
import type {
  ProvisionMemberAccountParams,
  MemberAccountStatus,
  PendingAccountInvitation,
} from './types';

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

export function useMyPendingAccountInvitations(options?: { enabled?: boolean }) {
  return useQuery<PendingAccountInvitation[]>({
    queryKey: ['my-pending-account-invitations'],
    queryFn: () => fetchMyPendingAccountInvitations(),
    enabled: options?.enabled ?? true,
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

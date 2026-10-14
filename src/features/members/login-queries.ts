import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export interface MemberLoginStatus {
  member_id: string;
  display_name: string;
  member_number: string | null;
  section_name: string | null;
  placement_name: string | null;
  chapter_name: string | null;
  has_email: boolean;
  login_state: 'linked' | 'code_active' | 'code_expired' | 'none';
  code_expires_at: string | null;
  code_hint: string | null;
}

export interface IssuedCodeItem {
  member_id: string;
  display_name: string;
  member_number: string | null;
  code: string;
  expires_at: string;
}

export interface SkippedMemberItem {
  member_id: string;
  reason: 'already_has_login' | 'out_of_scope' | 'not_active' | 'not_found' | string;
}

export interface IssueCodesResult {
  status: string;
  issued: IssuedCodeItem[];
  skipped: SkippedMemberItem[];
}

export const memberLoginKeys = {
  all: ['member-logins'] as const,
  list: (orgId: string | null) => [...memberLoginKeys.all, 'list', orgId] as const,
};

export function useMemberLoginStatus(organizationId: string | null) {
  return useQuery({
    queryKey: memberLoginKeys.list(organizationId),
    queryFn: async (): Promise<MemberLoginStatus[]> => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('list_member_login_status', {
        p_organization_id: organizationId,
      });
      if (error) throw error;
      return (data as unknown as MemberLoginStatus[]) || [];
    },
    enabled: !!organizationId,
    staleTime: 30_000,
  });
}

export function useIssueMemberClaimCodes() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      organizationId,
      memberIds,
    }: {
      organizationId: string;
      memberIds: string[];
    }): Promise<IssueCodesResult> => {
      const { data, error } = await supabase.rpc('issue_member_claim_codes', {
        p_organization_id: organizationId,
        p_member_ids: memberIds,
      });
      if (error) throw error;
      return data as unknown as IssueCodesResult;
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({
        queryKey: memberLoginKeys.list(variables.organizationId),
      });
    },
  });
}

export function useRevokeMemberClaimCode() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      organizationId,
      memberId,
    }: {
      organizationId: string;
      memberId: string;
    }) => {
      const { data, error } = await supabase.rpc('revoke_member_claim_code', {
        p_organization_id: organizationId,
        p_member_id: memberId,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({
        queryKey: memberLoginKeys.list(variables.organizationId),
      });
    },
  });
}

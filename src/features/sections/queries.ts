import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getSectionsOverview, getMemberSection, changeMemberSection } from './api';
import type { ChangeMemberSectionParams, SectionsOverviewResponse, MemberSection } from './types';
import { memberKeys } from '../members/queries';

export const sectionKeys = {
  all: ['sections'] as const,
  overview: (orgId: string | null) => [...sectionKeys.all, 'overview', orgId] as const,
  memberSection: (orgId: string | null, memberId: string | null) =>
    [...sectionKeys.all, 'member', orgId, memberId] as const,
};

export function useSectionsOverview(orgId: string | null) {
  return useQuery({
    queryKey: sectionKeys.overview(orgId),
    queryFn: async (): Promise<SectionsOverviewResponse> => {
      if (!orgId) throw new Error('Organization ID is required');
      return getSectionsOverview(orgId);
    },
    enabled: !!orgId,
  });
}

export function useMemberSection(orgId: string | null, memberId: string | null) {
  return useQuery({
    queryKey: sectionKeys.memberSection(orgId, memberId),
    queryFn: async (): Promise<MemberSection | null> => {
      if (!orgId || !memberId) throw new Error('Org and Member ID are required');
      return getMemberSection(orgId, memberId);
    },
    enabled: !!orgId && !!memberId,
  });
}

export function useChangeMemberSection() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ChangeMemberSectionParams) => changeMemberSection(params),
    onSuccess: (_, variables) => {
      // Invalidate member section query for this member
      queryClient.invalidateQueries({
        queryKey: sectionKeys.memberSection(variables.organizationId, variables.memberId),
      });
      // Invalidate member profiles so both member and possible partner get fresh data
      queryClient.invalidateQueries({
        queryKey: memberKeys.profiles(),
      });
      // Invalidate all member section queries to refresh any partner's section info
      queryClient.invalidateQueries({
        queryKey: sectionKeys.all,
      });
    },
  });
}

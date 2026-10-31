import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  getActivityTeam,
  listActivityServiceRoles,
  removeActivityServiceAssignment,
  removeActivitySpeaker,
  saveActivityServiceAssignment,
  saveActivitySpeaker,
  searchMembersForActivityTeam,
} from './api';
import type { ActivityTarget, SaveServiceParams, SaveSpeakerParams } from './types';

export const activityTeamKeys = {
  all: ['activity-team'] as const,
  team: (orgId: string, target: ActivityTarget) =>
    [...activityTeamKeys.all, 'team', orgId, target.eventId ?? null, target.programRunId ?? null] as const,
  roles: (orgId: string) => [...activityTeamKeys.all, 'roles', orgId] as const,
  search: (orgId: string, target: ActivityTarget, q: string) =>
    [...activityTeamKeys.all, 'search', orgId, target.eventId ?? null, target.programRunId ?? null, q] as const,
};

export function useActivityTeam(organizationId: string | null, target: ActivityTarget) {
  const hasTarget = !!(target.eventId || target.programRunId);
  return useQuery({
    queryKey: organizationId && hasTarget ? activityTeamKeys.team(organizationId, target) : ['activity-team', 'empty'],
    queryFn: () => getActivityTeam(organizationId!, target),
    enabled: !!organizationId && hasTarget,
  });
}

export function useActivityServiceRoles(organizationId: string | null, enabled = true) {
  return useQuery({
    queryKey: organizationId ? activityTeamKeys.roles(organizationId) : ['activity-team', 'roles', 'empty'],
    queryFn: () => listActivityServiceRoles(organizationId!),
    enabled: !!organizationId && enabled,
    staleTime: 10 * 60 * 1000,
  });
}

export function useActivityMemberSearch(organizationId: string | null, target: ActivityTarget, query: string) {
  const q = query.trim();
  return useQuery({
    queryKey: organizationId ? activityTeamKeys.search(organizationId, target, q) : ['activity-team', 'search', 'empty'],
    queryFn: () => searchMembersForActivityTeam(organizationId!, target, q),
    enabled: !!organizationId && q.length >= 2 && !!(target.eventId || target.programRunId),
  });
}

function useInvalidateTeam() {
  const queryClient = useQueryClient();
  return () => queryClient.invalidateQueries({ queryKey: [...activityTeamKeys.all, 'team'] });
}

export function useSaveActivitySpeaker() {
  const invalidate = useInvalidateTeam();
  return useMutation({
    mutationFn: (params: SaveSpeakerParams) => saveActivitySpeaker(params),
    onSuccess: invalidate,
  });
}

export function useRemoveActivitySpeaker() {
  const invalidate = useInvalidateTeam();
  return useMutation({
    mutationFn: (p: { organizationId: string; speakerId: string }) => removeActivitySpeaker(p.organizationId, p.speakerId),
    onSuccess: invalidate,
  });
}

export function useSaveActivityServiceAssignment() {
  const invalidate = useInvalidateTeam();
  return useMutation({
    mutationFn: (params: SaveServiceParams) => saveActivityServiceAssignment(params),
    onSuccess: invalidate,
  });
}

export function useRemoveActivityServiceAssignment() {
  const invalidate = useInvalidateTeam();
  return useMutation({
    mutationFn: (p: { organizationId: string; assignmentId: string }) =>
      removeActivityServiceAssignment(p.organizationId, p.assignmentId),
    onSuccess: invalidate,
  });
}

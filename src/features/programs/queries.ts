import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  listProgramRuns,
  getProgramRun,
  createProgramRun,
  updateProgramRun,
  setProgramRunStatus,
  addProgramSession,
  updateProgramSession,
  addProgramParticipant,
  updateProgramParticipant,
  setProgramParticipantStatus,
  getProgramSessionRoster,
  setProgramParticipantAttendance,
  type CreateProgramRunParams,
  type UpdateProgramRunParams,
  type SetProgramRunStatusParams,
  type AddProgramSessionParams,
  type UpdateProgramSessionParams,
  type AddProgramParticipantParams,
  type UpdateProgramParticipantParams,
  type SetProgramParticipantStatusParams,
  type SetProgramParticipantAttendanceParams,
} from './api';
import { eventKeys } from '../events/queries';

export const programKeys = {
  all: ['programs'] as const,
  lists: () => [...programKeys.all, 'list'] as const,
  list: (orgId: string, includeClosed: boolean) =>
    [...programKeys.lists(), orgId, { includeClosed }] as const,
  details: () => [...programKeys.all, 'detail'] as const,
  detail: (orgId: string, runId: string) =>
    [...programKeys.details(), orgId, runId] as const,
  rosters: () => [...programKeys.all, 'session-roster'] as const,
  roster: (orgId: string, eventId: string) =>
    [...programKeys.rosters(), orgId, eventId] as const,
};

export function useProgramRunsList(organizationId: string | null, includeClosed = false) {
  return useQuery({
    queryKey: organizationId ? programKeys.list(organizationId, includeClosed) : ['programs', 'empty'],
    queryFn: () => listProgramRuns(organizationId!, includeClosed),
    enabled: !!organizationId,
  });
}

export function useProgramRun(organizationId: string | null, runId: string | null) {
  return useQuery({
    queryKey: organizationId && runId ? programKeys.detail(organizationId, runId) : ['program', 'empty'],
    queryFn: () => getProgramRun(organizationId!, runId!),
    enabled: !!organizationId && !!runId,
  });
}

export function useCreateProgramRun() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: CreateProgramRunParams) => createProgramRun(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: programKeys.lists() });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useUpdateProgramRun() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: UpdateProgramRunParams) => updateProgramRun(params),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: programKeys.detail(vars.organizationId, vars.runId) });
      queryClient.invalidateQueries({ queryKey: programKeys.lists() });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useSetProgramRunStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: SetProgramRunStatusParams) => setProgramRunStatus(params),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: programKeys.detail(vars.organizationId, vars.runId) });
      queryClient.invalidateQueries({ queryKey: programKeys.lists() });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useAddProgramSession() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: AddProgramSessionParams) => addProgramSession(params),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: programKeys.detail(vars.organizationId, vars.runId) });
      queryClient.invalidateQueries({ queryKey: programKeys.lists() });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useUpdateProgramSession() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: UpdateProgramSessionParams) => updateProgramSession(params),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: programKeys.details() });
      queryClient.invalidateQueries({ queryKey: eventKeys.detail(vars.organizationId, vars.eventId) });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useAddProgramParticipant() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: AddProgramParticipantParams) => addProgramParticipant(params),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: programKeys.detail(vars.organizationId, vars.runId) });
      queryClient.invalidateQueries({ queryKey: programKeys.rosters() });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useUpdateProgramParticipant() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: UpdateProgramParticipantParams) => updateProgramParticipant(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: programKeys.details() });
      queryClient.invalidateQueries({ queryKey: programKeys.rosters() });
    },
  });
}

export function useSetProgramParticipantStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: SetProgramParticipantStatusParams) => setProgramParticipantStatus(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: programKeys.details() });
      queryClient.invalidateQueries({ queryKey: programKeys.rosters() });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useProgramSessionRoster(
  organizationId: string | null,
  eventId: string | null,
  enabled = true
) {
  return useQuery({
    queryKey:
      organizationId && eventId
        ? programKeys.roster(organizationId, eventId)
        : ['programSessionRoster', 'empty'],
    queryFn: () => getProgramSessionRoster(organizationId!, eventId!),
    enabled: !!organizationId && !!eventId && enabled,
  });
}

export function useSetProgramParticipantAttendance() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: SetProgramParticipantAttendanceParams) =>
      setProgramParticipantAttendance(params),
    onMutate: async (vars) => {
      await queryClient.cancelQueries({
        queryKey: programKeys.roster(vars.organizationId, vars.eventId),
      });

      const prevRoster = queryClient.getQueryData(
        programKeys.roster(vars.organizationId, vars.eventId)
      );

      // Optimistic update
      queryClient.setQueryData(
        programKeys.roster(vars.organizationId, vars.eventId),
        (old: any) => {
          if (!old) return old;
          const targetIds = new Set(vars.participantIds);
          const nextParticipants = old.participants.map((p: any) => {
            if (targetIds.has(p.participant_id)) {
              return { ...p, is_present: vars.present };
            }
            return p;
          });

          const currentPresentCount = nextParticipants.filter((p: any) => p.is_present).length;

          return {
            ...old,
            participants: nextParticipants,
            event: old.event
              ? {
                  ...old.event,
                  present_count: currentPresentCount,
                  present_expected_count: currentPresentCount,
                }
              : old.event,
          };
        }
      );

      return { prevRoster };
    },
    onError: (_err, vars, context) => {
      if (context?.prevRoster) {
        queryClient.setQueryData(
          programKeys.roster(vars.organizationId, vars.eventId),
          context.prevRoster
        );
      }
    },
    onSettled: (_, __, vars) => {
      queryClient.invalidateQueries({
        queryKey: programKeys.roster(vars.organizationId, vars.eventId),
      });
      queryClient.invalidateQueries({
        queryKey: eventKeys.detail(vars.organizationId, vars.eventId),
      });
      queryClient.invalidateQueries({ queryKey: programKeys.details() });
    },
  });
}

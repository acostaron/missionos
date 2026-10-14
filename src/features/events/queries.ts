import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  createEvent,
  getEvent,
  getEventAttendanceRoster,
  getMyEventAccess,
  listEventAudienceOptions,
  listEventFormationTalks,
  listEvents,
  postEventAttendanceToFormation,
  setEventAttendance,
  setEventGreeter,
  setEventStatus,
  updateEvent,
} from './api';
import type {
  CreateEventParams,
  EventDetail,
  EventRosterResponse,
  FormationTalkOption,
  ListEventAudienceOptionsResponse,
  ListEventsResponse,
  MyEventAccessResponse,
  PostAttendanceToFormationParams,
  PostAttendanceToFormationResult,
  SetEventAttendanceParams,
  SetEventAttendanceResult,
  SetEventGreeterParams,
  SetEventStatusParams,
  UpdateEventParams,
} from './types';

export const eventKeys = {
  all: ['events'] as const,
  list: (orgId: string | null, from?: string, to?: string) =>
    [...eventKeys.all, 'list', orgId, from, to] as const,
  detail: (orgId: string | null, eventId: string | null) =>
    [...eventKeys.all, 'detail', orgId, eventId] as const,
  roster: (orgId: string | null, eventId: string | null) =>
    [...eventKeys.all, 'roster', orgId, eventId] as const,
  formationTalks: (orgId: string | null) =>
    [...eventKeys.all, 'formationTalks', orgId] as const,
  audienceOptions: (orgId: string | null) =>
    [...eventKeys.all, 'audienceOptions', orgId] as const,
  myAccess: (orgId: string | null) =>
    [...eventKeys.all, 'myAccess', orgId] as const,
};

export function useEventsList(
  organizationId: string | null,
  from: string,
  to: string,
  enabled: boolean = true
) {
  return useQuery({
    queryKey: eventKeys.list(organizationId, from, to),
    queryFn: async (): Promise<ListEventsResponse> => {
      if (!organizationId) throw new Error('Organization ID is required');
      return listEvents(organizationId, from, to);
    },
    enabled: enabled && !!organizationId && !!from && !!to,
  });
}

export function useEvent(organizationId: string | null, eventId: string | null) {
  return useQuery({
    queryKey: eventKeys.detail(organizationId, eventId),
    queryFn: async (): Promise<EventDetail> => {
      if (!organizationId || !eventId) throw new Error('Organization ID and Event ID are required');
      return getEvent(organizationId, eventId);
    },
    enabled: !!organizationId && !!eventId,
  });
}

export function useEventRoster(organizationId: string | null, eventId: string | null) {
  return useQuery({
    queryKey: eventKeys.roster(organizationId, eventId),
    queryFn: async (): Promise<EventRosterResponse> => {
      if (!organizationId || !eventId) throw new Error('Organization ID and Event ID are required');
      return getEventAttendanceRoster(organizationId, eventId);
    },
    enabled: !!organizationId && !!eventId,
  });
}

export function useEventFormationTalks(organizationId: string | null, enabled: boolean = true) {
  return useQuery({
    queryKey: eventKeys.formationTalks(organizationId),
    queryFn: async (): Promise<FormationTalkOption[]> => {
      if (!organizationId) throw new Error('Organization ID is required');
      return listEventFormationTalks(organizationId);
    },
    enabled: enabled && !!organizationId,
  });
}

export function useEventAudienceOptions(organizationId: string | null, enabled: boolean = true) {
  return useQuery({
    queryKey: eventKeys.audienceOptions(organizationId),
    queryFn: async (): Promise<ListEventAudienceOptionsResponse> => {
      if (!organizationId) throw new Error('Organization ID is required');
      return listEventAudienceOptions(organizationId);
    },
    enabled: enabled && !!organizationId,
  });
}

export function useMyEventAccess(organizationId: string | null, enabled: boolean = true) {
  return useQuery({
    queryKey: eventKeys.myAccess(organizationId),
    queryFn: async (): Promise<MyEventAccessResponse> => {
      if (!organizationId) throw new Error('Organization ID is required');
      return getMyEventAccess(organizationId);
    },
    enabled: enabled && !!organizationId,
  });
}

export function useCreateEvent() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: CreateEventParams) => createEvent(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useUpdateEvent() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateEventParams) => updateEvent(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useSetEventStatus() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: SetEventStatusParams) => setEventStatus(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useSetEventGreeter() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: SetEventGreeterParams) => setEventGreeter(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function useSetEventAttendance() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: SetEventAttendanceParams): Promise<SetEventAttendanceResult> =>
      setEventAttendance(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

export function usePostEventAttendanceToFormation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: PostAttendanceToFormationParams): Promise<PostAttendanceToFormationResult> =>
      postEventAttendanceToFormation(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
    },
  });
}

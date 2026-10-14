import { supabase } from '../../lib/supabase/client';
import type {
  CreateEventParams,
  EventDetail,
  EventRosterResponse,
  EventSummary,
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

export async function listEvents(
  organizationId: string,
  from: string,
  to: string
): Promise<ListEventsResponse> {
  const { data, error } = await supabase.rpc('list_events', {
    p_organization_id: organizationId,
    p_from: from,
    p_to: to,
  });

  if (error) throw error;
  return data as unknown as ListEventsResponse;
}

export async function getEvent(
  organizationId: string,
  eventId: string
): Promise<EventDetail> {
  const { data, error } = await supabase.rpc('get_event', {
    p_organization_id: organizationId,
    p_event_id: eventId,
  });

  if (error) throw error;
  return data as unknown as EventDetail;
}

export async function createEvent(params: CreateEventParams): Promise<{ status: string; event: EventSummary }> {
  const { data, error } = await supabase.rpc('create_event', {
    p_organization_id: params.organizationId,
    p_event_type: params.eventType,
    p_title: params.title,
    p_starts_at: params.startsAt,
    p_ends_at: params.endsAt ?? undefined,
    p_location_text: params.locationText ?? undefined,
    p_description: params.description ?? undefined,
    p_audience_code: params.audienceCode ?? 'mfc_ny',
    p_formation_talk_id: params.formationTalkId ?? undefined,
  });

  if (error) throw error;
  return data as unknown as { status: string; event: EventSummary };
}

export async function updateEvent(params: UpdateEventParams): Promise<{ status: string; event: EventSummary }> {
  const { data, error } = await supabase.rpc('update_event', {
    p_organization_id: params.organizationId,
    p_event_id: params.eventId,
    p_event_type: params.eventType,
    p_title: params.title,
    p_starts_at: params.startsAt,
    p_ends_at: params.endsAt ?? undefined,
    p_location_text: params.locationText ?? undefined,
    p_description: params.description ?? undefined,
    p_audience_code: params.audienceCode ?? 'mfc_ny',
    p_formation_talk_id: params.formationTalkId ?? undefined,
  });

  if (error) throw error;
  return data as unknown as { status: string; event: EventSummary };
}

export async function setEventStatus(params: SetEventStatusParams): Promise<{ status: string; event: EventSummary }> {
  const { data, error } = await supabase.rpc('set_event_status', {
    p_organization_id: params.organizationId,
    p_event_id: params.eventId,
    p_status: params.status,
    p_reason: params.reason ?? undefined,
  });

  if (error) throw error;
  return data as unknown as { status: string; event: EventSummary };
}

export async function setEventGreeter(
  params: SetEventGreeterParams
): Promise<{ status: string; event_id: string; member_id: string; assigned: boolean }> {
  const { data, error } = await supabase.rpc('set_event_greeter', {
    p_organization_id: params.organizationId,
    p_event_id: params.eventId,
    p_member_id: params.memberId,
    p_assign: params.assign ?? true,
  });

  if (error) throw error;
  return data as unknown as { status: string; event_id: string; member_id: string; assigned: boolean };
}

export async function getEventAttendanceRoster(
  organizationId: string,
  eventId: string
): Promise<EventRosterResponse> {
  const { data, error } = await supabase.rpc('get_event_attendance_roster', {
    p_organization_id: organizationId,
    p_event_id: eventId,
  });

  if (error) throw error;
  return data as unknown as EventRosterResponse;
}

export async function setEventAttendance(
  params: SetEventAttendanceParams
): Promise<SetEventAttendanceResult> {
  const { data, error } = await supabase.rpc('set_event_attendance', {
    p_organization_id: params.organizationId,
    p_event_id: params.eventId,
    p_member_ids: params.memberIds,
    p_present: params.present ?? true,
    p_check_in_method: params.checkInMethod ?? 'tick',
  });

  if (error) throw error;
  return data as unknown as SetEventAttendanceResult;
}

export async function postEventAttendanceToFormation(
  params: PostAttendanceToFormationParams
): Promise<PostAttendanceToFormationResult> {
  const { data, error } = await supabase.rpc('post_event_attendance_to_formation', {
    p_organization_id: params.organizationId,
    p_event_id: params.eventId,
  });

  if (error) throw error;
  return data as unknown as PostAttendanceToFormationResult;
}

export async function listEventFormationTalks(
  organizationId: string
): Promise<FormationTalkOption[]> {
  const { data, error } = await supabase.rpc('list_event_formation_talks', {
    p_organization_id: organizationId,
  });

  if (error) throw error;
  return data as unknown as FormationTalkOption[];
}

export async function listEventAudienceOptions(
  organizationId: string
): Promise<ListEventAudienceOptionsResponse> {
  const { data, error } = await supabase.rpc('list_event_audience_options', {
    p_organization_id: organizationId,
  });

  if (error) throw error;
  return data as unknown as ListEventAudienceOptionsResponse;
}

export async function getMyEventAccess(
  organizationId: string
): Promise<MyEventAccessResponse> {
  const { data, error } = await supabase.rpc('get_my_event_access', {
    p_organization_id: organizationId,
  });

  if (error) throw error;
  return data as unknown as MyEventAccessResponse;
}


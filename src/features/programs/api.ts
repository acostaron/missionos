import { supabase } from '../../lib/supabase/client';
import type {
  ListProgramRunsResponse,
  ProgramCode,
  ProgramRunDetail,
  ProgramRunStatus,
  ProgramSessionRosterResponse,
} from './types';
import type { EventSummary } from '../events/types';

export async function listProgramRuns(
  organizationId: string,
  includeClosed = false
): Promise<ListProgramRunsResponse> {
  const { data, error } = await supabase.rpc('list_program_runs', {
    p_organization_id: organizationId,
    p_include_closed: includeClosed,
  });
  if (error) throw error;
  return data as unknown as ListProgramRunsResponse;
}

export async function getProgramRun(
  organizationId: string,
  runId: string
): Promise<ProgramRunDetail> {
  const { data, error } = await supabase.rpc('get_program_run', {
    p_organization_id: organizationId,
    p_run_id: runId,
  });
  if (error) throw error;
  return data as unknown as ProgramRunDetail;
}

export interface CreateProgramRunParams {
  organizationId: string;
  programCode: ProgramCode;
  title: string;
  sessionCount?: number;
  chapterCode?: string;
  sectionCodes?: string[];
  description?: string;
}

export async function createProgramRun(params: CreateProgramRunParams) {
  const { data, error } = await supabase.rpc('create_program_run', {
    p_organization_id: params.organizationId,
    p_program_code: params.programCode,
    p_title: params.title,
    p_session_count: params.sessionCount ?? undefined,
    p_chapter_code: params.chapterCode ?? undefined,
    p_section_codes: params.sectionCodes ?? [],
    p_description: params.description ?? undefined,
  });
  if (error) throw error;
  return data as unknown as { status: string; run: ProgramRunDetail['run'] };
}

export interface UpdateProgramRunParams {
  organizationId: string;
  runId: string;
  title: string;
  description?: string;
}

export async function updateProgramRun(params: UpdateProgramRunParams) {
  const { data, error } = await supabase.rpc('update_program_run', {
    p_organization_id: params.organizationId,
    p_run_id: params.runId,
    p_title: params.title,
    p_description: params.description ?? undefined,
  });
  if (error) throw error;
  return data as unknown as { status: string; run: ProgramRunDetail['run'] };
}

export interface SetProgramRunStatusParams {
  organizationId: string;
  runId: string;
  status: ProgramRunStatus;
  reason?: string;
}

export async function setProgramRunStatus(params: SetProgramRunStatusParams) {
  const { data, error } = await supabase.rpc('set_program_run_status', {
    p_organization_id: params.organizationId,
    p_run_id: params.runId,
    p_status: params.status,
    p_reason: params.reason ?? undefined,
  });
  if (error) throw error;
  return data as unknown as { status: string; run: ProgramRunDetail['run'] };
}

export interface AddProgramSessionParams {
  organizationId: string;
  runId: string;
  sessionNumber: number;
  startsAt: string;
  endsAt?: string | null;
  locationText?: string | null;
}

export async function addProgramSession(params: AddProgramSessionParams) {
  const { data, error } = await supabase.rpc('add_program_session', {
    p_organization_id: params.organizationId,
    p_run_id: params.runId,
    p_session_number: params.sessionNumber,
    p_starts_at: params.startsAt,
    p_ends_at: params.endsAt ?? undefined,
    p_location_text: params.locationText ?? undefined,
  });
  if (error) throw error;
  return data as unknown as { status: string; event: EventSummary };
}

export interface UpdateProgramSessionParams {
  organizationId: string;
  eventId: string;
  startsAt: string;
  endsAt?: string | null;
  locationText?: string | null;
}

export async function updateProgramSession(params: UpdateProgramSessionParams) {
  const { data, error } = await supabase.rpc('update_program_session', {
    p_organization_id: params.organizationId,
    p_event_id: params.eventId,
    p_starts_at: params.startsAt,
    p_ends_at: params.endsAt ?? undefined,
    p_location_text: params.locationText ?? undefined,
  });
  if (error) throw error;
  return data as unknown as { status: string; event: EventSummary };
}

export interface AddProgramParticipantParams {
  organizationId: string;
  runId: string;
  memberId?: string | null;
  firstName?: string | null;
  lastName?: string | null;
  phone?: string | null;
  email?: string | null;
  invitedByMemberId?: string | null;
  notes?: string | null;
}

export async function addProgramParticipant(params: AddProgramParticipantParams) {
  const { data, error } = await supabase.rpc('add_program_participant', {
    p_organization_id: params.organizationId,
    p_run_id: params.runId,
    p_member_id: params.memberId ?? undefined,
    p_first_name: params.firstName ?? undefined,
    p_last_name: params.lastName ?? undefined,
    p_phone: params.phone ?? undefined,
    p_email: params.email ?? undefined,
    p_invited_by_member_id: params.invitedByMemberId ?? undefined,
    p_notes: params.notes ?? undefined,
  });
  if (error) throw error;
  return data as unknown as { status: string; participant_id: string; name: string };
}

export interface UpdateProgramParticipantParams {
  organizationId: string;
  participantId: string;
  firstName?: string | null;
  lastName?: string | null;
  phone?: string | null;
  email?: string | null;
  invitedByMemberId?: string | null;
  notes?: string | null;
}

export async function updateProgramParticipant(params: UpdateProgramParticipantParams) {
  const { data, error } = await supabase.rpc('update_program_participant', {
    p_organization_id: params.organizationId,
    p_participant_id: params.participantId,
    p_first_name: params.firstName ?? undefined,
    p_last_name: params.lastName ?? undefined,
    p_phone: params.phone ?? undefined,
    p_email: params.email ?? undefined,
    p_invited_by_member_id: params.invitedByMemberId ?? undefined,
    p_notes: params.notes ?? undefined,
  });
  if (error) throw error;
  return data as unknown as { status: string; participant_id: string; name: string };
}

export interface SetProgramParticipantStatusParams {
  organizationId: string;
  participantId: string;
  status: 'registered' | 'withdrawn';
}

export async function setProgramParticipantStatus(params: SetProgramParticipantStatusParams) {
  const { data, error } = await supabase.rpc('set_program_participant_status', {
    p_organization_id: params.organizationId,
    p_participant_id: params.participantId,
    p_status: params.status,
  });
  if (error) throw error;
  return data as unknown as { status: string; participant_id: string; participant_status: string };
}

export async function getProgramSessionRoster(
  organizationId: string,
  eventId: string
): Promise<ProgramSessionRosterResponse> {
  const { data, error } = await supabase.rpc('get_program_session_roster', {
    p_organization_id: organizationId,
    p_event_id: eventId,
  });
  if (error) throw error;
  return data as unknown as ProgramSessionRosterResponse;
}

export interface SetProgramParticipantAttendanceParams {
  organizationId: string;
  eventId: string;
  participantIds: string[];
  present: boolean;
}

export async function setProgramParticipantAttendance(params: SetProgramParticipantAttendanceParams) {
  const { data, error } = await supabase.rpc('set_program_participant_attendance', {
    p_organization_id: params.organizationId,
    p_event_id: params.eventId,
    p_participant_ids: params.participantIds,
    p_present: params.present,
  });
  if (error) throw error;
  return data as unknown as {
    status: string;
    changed_count: number;
    unchanged_count: number;
    event: EventSummary;
  };
}

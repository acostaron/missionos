import { supabase } from '../../lib/supabase/client';
import type {
  ActivityMemberOption,
  ActivityTarget,
  ActivityTeam,
  SaveServiceParams,
  SaveSpeakerParams,
  ServiceRoleOption,
} from './types';

export async function getActivityTeam(
  organizationId: string,
  target: ActivityTarget
): Promise<ActivityTeam> {
  const { data, error } = await supabase.rpc('get_activity_team', {
    p_organization_id: organizationId,
    p_event_id: target.eventId ?? undefined,
    p_program_run_id: target.programRunId ?? undefined,
  });
  if (error) throw error;
  return data as unknown as ActivityTeam;
}

export async function listActivityServiceRoles(organizationId: string): Promise<ServiceRoleOption[]> {
  const { data, error } = await supabase.rpc('list_activity_service_roles', {
    p_organization_id: organizationId,
  });
  if (error) throw error;
  return data as unknown as ServiceRoleOption[];
}

export async function searchMembersForActivityTeam(
  organizationId: string,
  target: ActivityTarget,
  query: string
): Promise<ActivityMemberOption[]> {
  const { data, error } = await supabase.rpc('search_members_for_activity_team', {
    p_organization_id: organizationId,
    p_event_id: target.eventId ?? undefined,
    p_program_run_id: target.programRunId ?? undefined,
    p_query: query,
  });
  if (error) throw error;
  return data as unknown as ActivityMemberOption[];
}

export async function saveActivitySpeaker(params: SaveSpeakerParams) {
  const { data, error } = await supabase.rpc('save_activity_speaker', {
    p_organization_id: params.organizationId,
    p_speaker_id: params.speakerId ?? undefined,
    p_event_id: params.eventId ?? undefined,
    p_program_run_id: params.programRunId ?? undefined,
    p_member_id: params.memberId ?? undefined,
    p_external_name: params.externalName ?? undefined,
    p_external_title: params.externalTitle ?? undefined,
    p_external_organization: params.externalOrganization ?? undefined,
    p_speaker_role: params.speakerRole,
    p_topic_title: params.topicTitle ?? undefined,
    p_session_label: params.sessionLabel ?? undefined,
    p_notes: params.notes ?? undefined,
  });
  if (error) throw error;
  return data;
}

export async function removeActivitySpeaker(organizationId: string, speakerId: string) {
  const { data, error } = await supabase.rpc('remove_activity_speaker', {
    p_organization_id: organizationId,
    p_speaker_id: speakerId,
  });
  if (error) throw error;
  return data;
}

export async function saveActivityServiceAssignment(params: SaveServiceParams) {
  const { data, error } = await supabase.rpc('save_activity_service_assignment', {
    p_organization_id: params.organizationId,
    p_assignment_id: params.assignmentId ?? undefined,
    p_event_id: params.eventId ?? undefined,
    p_program_run_id: params.programRunId ?? undefined,
    p_member_id: params.memberId ?? undefined,
    p_external_name: params.externalName ?? undefined,
    p_role_code: params.roleCode,
    p_role_label: params.roleLabel ?? undefined,
    p_team_group: params.teamGroup ?? undefined,
    p_notes: params.notes ?? undefined,
  });
  if (error) throw error;
  return data;
}

export async function removeActivityServiceAssignment(organizationId: string, assignmentId: string) {
  const { data, error } = await supabase.rpc('remove_activity_service_assignment', {
    p_organization_id: organizationId,
    p_assignment_id: assignmentId,
  });
  if (error) throw error;
  return data;
}

// Household card in My Events: data and actions (Pass 9.9, written by Claude 2026-10-16).
// Everyone sees their household's meetings, topics and their OWN attendance. Those who can manage the household
// (can_edit: servant leaders, spouse in couple leadership, administrators, any member of a Fraternal household)
// also schedule / edit / cancel / complete meetings and record attendance. The server checks every action again.
import { useQuery, type QueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';
import type { Json } from '../../types/database';

export type AttendanceStatus = 'present' | 'absent' | 'excused';

export interface CardTopic {
  assignment_id: string;
  topic_id: string;
  title: string;
  is_library_topic: boolean;
  assignment_status: 'planned' | 'completed' | 'skipped';
  change_reason_code: string | null;
  replaced_by_title: string | null;
  replaces_title: string | null;
}

export interface AttendanceSummary {
  expected_member_count: number;
  recorded_attendance_count: number;
  present_count: number;
  absent_count: number;
  excused_count: number;
  attendance_complete: boolean;
}

export interface CardMeeting {
  household_meeting_id: string;
  meeting_date: string;
  scheduled_start_at: string | null;
  meeting_status: 'scheduled' | 'completed' | 'cancelled';
  location_type: string | null;
  location_text: string | null;
  host_member_id: string | null;
  host_name: string | null;
  my_attendance: AttendanceStatus | null;
  attendance_summary: AttendanceSummary | null;
  topics: CardTopic[];
}

export interface CardHousehold {
  household_id: string;
  household_name: string;
  pastoral_level: string;
  can_edit: boolean;
  meetings: CardMeeting[];
}

export interface RosterMember {
  member_id: string;
  display_name: string;
}

export interface AttendanceRosterMember extends RosterMember {
  attendance_status: AttendanceStatus | null;
}

export interface MeetingAttendance {
  household_meeting_id: string;
  meeting_date: string;
  meeting_status: CardMeeting['meeting_status'];
  summary: AttendanceSummary | null;
  roster: AttendanceRosterMember[];
}

export interface MeetingFields {
  meetingDate: string;
  scheduledStartAt: string | null;
  locationType: string | null;
  locationText: string | null;
  hostMemberId: string | null;
}

export const LOCATION_TYPES: Record<string, string> = { in_person: 'In person', virtual: 'Virtual', hybrid: 'Hybrid' };
export const ATTENDANCE_LABELS: Record<AttendanceStatus, string> = {
  present: 'Present',
  absent: 'Absent',
  excused: 'Excused',
};

export const householdCardKeys = {
  all: ['self-service', 'household-topics'] as const,
  list: (orgId: string | null) => [...householdCardKeys.all, orgId] as const,
  roster: (orgId: string, householdId: string) => [...householdCardKeys.all, 'roster', orgId, householdId] as const,
  attendance: (orgId: string, meetingId: string) =>
    [...householdCardKeys.all, 'attendance', orgId, meetingId] as const,
};

export function useMyHouseholdCards(orgId: string | null) {
  return useQuery<CardHousehold[]>({
    queryKey: householdCardKeys.list(orgId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_my_household_topics', { p_organization_id: orgId! });
      if (error) throw error;
      return (data ?? []) as unknown as CardHousehold[];
    },
    enabled: !!orgId,
    staleTime: 30_000,
  });
}

export function useHouseholdRoster(orgId: string, householdId: string, enabled: boolean) {
  return useQuery<RosterMember[]>({
    queryKey: householdCardKeys.roster(orgId, householdId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('member_household_roster', {
        p_organization_id: orgId,
        p_household_id: householdId,
      });
      if (error) throw error;
      return (data ?? []) as unknown as RosterMember[];
    },
    enabled,
    staleTime: 60_000,
  });
}

export function useMeetingAttendance(orgId: string, meetingId: string, enabled: boolean) {
  return useQuery<MeetingAttendance>({
    queryKey: householdCardKeys.attendance(orgId, meetingId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('member_get_household_attendance', {
        p_organization_id: orgId,
        p_meeting_id: meetingId,
      });
      if (error) throw error;
      return data as unknown as MeetingAttendance;
    },
    enabled,
    staleTime: 0,
  });
}

export async function scheduleMeeting(orgId: string, householdId: string, f: MeetingFields) {
  const { error } = await supabase.rpc('member_schedule_household_meeting', {
    p_organization_id: orgId,
    p_household_id: householdId,
    p_meeting_date: f.meetingDate,
    p_scheduled_start_at: f.scheduledStartAt ?? undefined,
    p_location_type: f.locationType ?? undefined,
    p_location_text: f.locationText ?? undefined,
    p_host_member_id: f.hostMemberId ?? undefined,
  });
  if (error) throw error;
}

export async function updateMeeting(orgId: string, meetingId: string, f: MeetingFields) {
  const { error } = await supabase.rpc('member_update_household_meeting', {
    p_organization_id: orgId,
    p_meeting_id: meetingId,
    p_meeting_date: f.meetingDate,
    p_scheduled_start_at: f.scheduledStartAt ?? undefined,
    p_location_type: f.locationType ?? undefined,
    p_location_text: f.locationText ?? undefined,
    p_host_member_id: f.hostMemberId ?? undefined,
  });
  if (error) throw error;
}

export async function setMeetingStatus(orgId: string, meetingId: string, status: 'completed' | 'cancelled') {
  const { error } = await supabase.rpc('member_set_household_meeting_status', {
    p_organization_id: orgId,
    p_meeting_id: meetingId,
    p_new_status: status,
  });
  if (error) throw error;
}

export async function recordAttendance(
  orgId: string,
  meetingId: string,
  attendance: { member_id: string; attendance_status: AttendanceStatus }[],
) {
  const { error } = await supabase.rpc('member_record_household_attendance', {
    p_organization_id: orgId,
    p_meeting_id: meetingId,
    p_attendance: attendance as unknown as Json,
    p_complete_meeting: true,
  });
  if (error) throw error;
}

export async function invalidateHouseholdCards(qc: QueryClient) {
  await qc.invalidateQueries({ queryKey: householdCardKeys.all });
}

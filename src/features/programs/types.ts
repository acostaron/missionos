import type { EventSummary } from '../events/types';

export type ProgramCode = 'youth_camp' | 'discovery_camp' | 'cls' | 'other_program';
export type ProgramRunStatus = 'planned' | 'running' | 'completed' | 'cancelled';
export type ParticipantStatus = 'registered' | 'withdrawn';

export interface ProgramSectionRef {
  code: string;
  name: string;
  sub_area_name?: string | null;
}

export interface ProgramRunSummary {
  id: string;
  program_code: ProgramCode;
  title: string;
  description: string | null;
  chapter_code: string | null;
  chapter_name: string | null;
  sections: ProgramSectionRef[];
  audience_name: string;
  session_count: number;
  sessions_scheduled: number;
  run_status: ProgramRunStatus;
  cancel_reason: string | null;
  participant_count: number;
  graduate_count: number;
  first_session_at: string | null;
  last_session_at: string | null;
  can_manage: boolean;
}

export interface ProgramParticipant {
  participant_id: string;
  name: string;
  is_member: boolean;
  member_id: string | null;
  member_number: string | null;
  participant_status: ParticipantStatus;
  invited_by_name: string | null;
  invited_by_member_id: string | null;
  phone: string | null;
  email: string | null;
  notes: string | null;
  first_name: string | null;
  last_name: string | null;
  attended_sessions: number[];
  attended_count: number;
  graduated: boolean;
}

export interface ProgramRunDetail {
  run: ProgramRunSummary;
  sessions: EventSummary[];
  participants: ProgramParticipant[];
}

export interface ProgramSessionParticipantRosterItem {
  participant_id: string;
  name: string;
  is_member: boolean;
  member_number: string | null;
  is_present: boolean;
}

export interface ProgramSessionRosterResponse {
  event: EventSummary;
  participants: ProgramSessionParticipantRosterItem[];
}

export interface ListProgramRunsResponse {
  can_create: boolean;
  runs: ProgramRunSummary[];
}

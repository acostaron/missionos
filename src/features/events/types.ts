export type EventType = 'assembly' | 'teaching' | 'formation_talk' | 'other';
export type EventStatus = 'scheduled' | 'held' | 'cancelled';

export interface EventSummary {
  id: string;
  event_type: EventType;
  title: string;
  description: string | null;
  starts_at: string;
  ends_at: string | null;
  location_text: string | null;
  event_status: EventStatus;
  cancel_reason: string | null;
  audience_node_id: string | null;
  audience_code: string | null;
  audience_name: string;
  formation_program_id: string | null;
  formation_program_name: string | null;
  formation_talk_id: string | null;
  formation_talk_title: string | null;
  formation_posted_at: string | null;
  expected_count: number;
  present_count: number;
  present_expected_count: number;
  guest_count: number;
  is_greeter: boolean;
  can_record: boolean;
  can_manage: boolean;
}

export interface EventGreeter {
  member_id: string;
  display_name: string;
  member_number: string | null;
}

export interface EventDetail extends EventSummary {
  greeters: EventGreeter[];
}

export interface ListEventsResponse {
  can_view_all: boolean;
  can_manage: boolean;
  events: EventSummary[];
}

export interface EventRosterMember {
  member_id: string;
  member_number: string | null;
  display_name: string;
  sort_name: string;
  section_name: string | null;
  sub_area_code: string | null;
  sub_area_name: string | null;
  placement_name: string | null;
  in_audience: boolean;
  is_present: boolean;
  check_in_method: string | null;
  recorded_at: string | null;
}

export interface EventRosterResponse {
  event: EventSummary;
  members: EventRosterMember[];
}

export interface FormationTalkOption {
  talk_id: string;
  talk_title: string;
  talk_code: string;
  sequence_order: number;
  program_id: string;
  program_name: string;
}

export interface CreateEventParams {
  organizationId: string;
  eventType: EventType;
  title: string;
  startsAt: string;
  endsAt?: string | null;
  locationText?: string | null;
  description?: string | null;
  audienceCode?: string;
  formationTalkId?: string | null;
}

export interface UpdateEventParams {
  organizationId: string;
  eventId: string;
  eventType: EventType;
  title: string;
  startsAt: string;
  endsAt?: string | null;
  locationText?: string | null;
  description?: string | null;
  audienceCode?: string;
  formationTalkId?: string | null;
}

export interface SetEventStatusParams {
  organizationId: string;
  eventId: string;
  status: EventStatus;
  reason?: string | null;
}

export interface SetEventGreeterParams {
  organizationId: string;
  eventId: string;
  memberId: string;
  assign?: boolean;
}

export interface SetEventAttendanceParams {
  organizationId: string;
  eventId: string;
  memberIds: string[];
  present?: boolean;
  checkInMethod?: 'tick' | 'qr';
}

export interface SetEventAttendanceResult {
  status: string;
  changed_count: number;
  unchanged_count: number;
  event: EventSummary;
}

export interface PostAttendanceToFormationParams {
  organizationId: string;
  eventId: string;
}

export interface PostAttendanceToFormationResult {
  status: string;
  posted_count: number;
  already_recorded_count: number;
  program_already_completed_count: number;
  attempts_opened_count: number;
  event: EventSummary;
}

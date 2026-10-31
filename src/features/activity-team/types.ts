// Pass 9.49: structured Speakers + Service Team for Events and Programs.

export type ActivityPersonType = 'member' | 'external';

export type SpeakerRole =
  | 'speaker'
  | 'facilitator'
  | 'testimony'
  | 'exhortation'
  | 'trainer'
  | 'panelist'
  | 'moderator'
  | 'other';

export const SPEAKER_ROLE_LABELS: Record<SpeakerRole, string> = {
  speaker: 'Speaker',
  facilitator: 'Facilitator',
  testimony: 'Testimony',
  exhortation: 'Exhortation',
  trainer: 'Trainer',
  panelist: 'Panelist',
  moderator: 'Moderator',
  other: 'Other',
};

export const SPEAKER_ROLES = Object.keys(SPEAKER_ROLE_LABELS) as SpeakerRole[];

export interface ActivitySpeaker {
  id: string;
  event_id: string | null;
  program_run_id: string | null;
  session_number: number | null;
  event_title: string | null;
  event_starts_at: string | null;
  person_type: ActivityPersonType;
  member_id: string | null;
  member_number: string | null;
  display_name: string;
  external_name: string | null;
  external_title: string | null;
  external_organization: string | null;
  speaker_role: SpeakerRole;
  topic_title: string | null;
  session_label: string | null;
  sort_order: number;
  notes: string | null;
}

export interface ActivityServiceAssignment {
  id: string;
  event_id: string | null;
  program_run_id: string | null;
  session_number: number | null;
  event_title: string | null;
  person_type: ActivityPersonType;
  member_id: string | null;
  member_number: string | null;
  display_name: string;
  external_name: string | null;
  role_code: string;
  role_label: string;
  custom_role_label: string | null;
  team_group: string | null;
  sort_order: number;
  notes: string | null;
}

export interface ActivityTeam {
  can_manage: boolean;
  speakers: ActivitySpeaker[];
  service_team: ActivityServiceAssignment[];
}

export interface ServiceRoleOption {
  code: string;
  label: string;
}

export interface ActivityMemberOption {
  member_id: string;
  display_name: string;
  member_number: string | null;
}

/** Exactly one of eventId / programRunId. */
export interface ActivityTarget {
  eventId?: string | null;
  programRunId?: string | null;
}

export interface SaveSpeakerParams extends ActivityTarget {
  organizationId: string;
  speakerId?: string | null;
  memberId?: string | null;
  externalName?: string | null;
  externalTitle?: string | null;
  externalOrganization?: string | null;
  speakerRole: SpeakerRole;
  topicTitle?: string | null;
  sessionLabel?: string | null;
  notes?: string | null;
}

export interface SaveServiceParams extends ActivityTarget {
  organizationId: string;
  assignmentId?: string | null;
  memberId?: string | null;
  externalName?: string | null;
  roleCode: string;
  roleLabel?: string | null;
  teamGroup?: string | null;
  notes?: string | null;
}

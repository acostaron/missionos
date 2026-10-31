import type { EventType, EventStatus, EventMeetingType, EventReportPriority } from './types';
import type { BadgeVariant } from '../../components/ui';

export const EVENT_TYPE_LABELS: Record<EventType, string> = {
  assembly: 'Assembly',
  chapter_assembly: 'Chapter Assembly',
  section_assembly: 'Section Assembly',
  formation_talk: 'Pastoral Formation Talk',
  teaching: 'Programs & Retreat',
  other: 'Other',
};

export const EVENT_STATUS_LABELS: Record<EventStatus, string> = {
  scheduled: 'Scheduled',
  held: 'Held',
  cancelled: 'Cancelled',
};

export const EVENT_MEETING_TYPE_LABELS: Record<EventMeetingType, string> = {
  in_person: 'In-Person',
  virtual: 'Virtual',
};

export const REPORT_PRIORITY_LABELS: Record<EventReportPriority, string> = {
  routine: 'Routine',
  ministry_activity: 'Ministry Activity',
  major_highlight: 'Major Highlight',
};

export function getEventTypeBadgeVariant(type: EventType): BadgeVariant {
  switch (type) {
    case 'assembly':
      return 'info';
    case 'chapter_assembly':
      return 'warning';
    case 'section_assembly':
      return 'neutral';
    case 'formation_talk':
      return 'success';
    case 'teaching':
      return 'info';
    case 'other':
      return 'neutral';
  }
}

export function getEventStatusBadgeVariant(status: EventStatus): BadgeVariant {
  switch (status) {
    case 'scheduled':
      return 'info';
    case 'held':
      return 'success';
    case 'cancelled':
      return 'danger';
  }
}

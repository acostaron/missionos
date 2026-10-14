import type { EventType, EventStatus } from './types';
import type { BadgeVariant } from '../../components/ui';

export const EVENT_TYPE_LABELS: Record<EventType, string> = {
  assembly: 'Assembly',
  teaching: 'Teaching',
  formation_talk: 'Course talk',
  other: 'Other',
};

export const EVENT_STATUS_LABELS: Record<EventStatus, string> = {
  scheduled: 'Scheduled',
  held: 'Held',
  cancelled: 'Cancelled',
};

export const AUDIENCE_OPTIONS: Array<{ code: string; label: string }> = [
  { code: 'mfc_ny', label: 'MFC New York (FMC welcome as guests)' },
  { code: 'fmc_ny', label: 'FMC New York' },
  { code: '', label: 'All members' },
];

export function getEventTypeBadgeVariant(type: EventType): BadgeVariant {
  switch (type) {
    case 'assembly':
      return 'info';
    case 'formation_talk':
      return 'success';
    case 'teaching':
      return 'neutral';
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

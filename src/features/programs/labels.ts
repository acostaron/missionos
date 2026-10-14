import type { BadgeVariant } from '../../components/ui';
import type { ProgramCode, ProgramRunStatus } from './types';

export const PROGRAM_CODE_LABELS: Record<ProgramCode, string> = {
  youth_camp: 'Youth Camp',
  discovery_camp: 'Discovery Camp',
  cls: 'Christian Life Seminar',
  other_program: 'Other program / retreat',
};

export const PROGRAM_STATUS_LABELS: Record<ProgramRunStatus, string> = {
  planned: 'Planned',
  running: 'Running',
  completed: 'Completed',
  cancelled: 'Cancelled',
};

export function getProgramCodeBadgeVariant(code: ProgramCode): BadgeVariant {
  switch (code) {
    case 'youth_camp':
      return 'info';
    case 'discovery_camp':
      return 'success';
    case 'cls':
      return 'warning';
    case 'other_program':
      return 'neutral';
  }
}

export function getProgramStatusBadgeVariant(status: ProgramRunStatus): BadgeVariant {
  switch (status) {
    case 'planned':
      return 'neutral';
    case 'running':
      return 'info';
    case 'completed':
      return 'success';
    case 'cancelled':
      return 'danger';
  }
}

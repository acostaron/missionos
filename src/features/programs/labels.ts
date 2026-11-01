import type { BadgeVariant } from '../../components/ui';
import type { ProgramCode, ProgramReportPriority, ProgramRunStatus } from './types';

export const PROGRAM_CODE_LABELS: Record<ProgramCode, string> = {
  youth_camp: 'Youth Camp',
  discovery_camp: 'Discovery Camp',
  cls: 'Christian Life Seminar',
  lcs: 'Life in Christ Seminar (LCS)',
  other_program: 'Other program / retreat',
};

export const PROGRAM_STATUS_LABELS: Record<ProgramRunStatus, string> = {
  planned: 'Planned',
  running: 'Running',
  completed: 'Completed',
  cancelled: 'Cancelled',
};

export const PROGRAM_REPORT_PRIORITY_LABELS: Record<ProgramReportPriority, string> = {
  routine: 'Routine',
  ministry_activity: 'Ministry Activity',
  major_highlight: 'Major Highlight',
};

export function getProgramReportPriorityBadgeVariant(
  priority: ProgramReportPriority | string | null | undefined
): BadgeVariant {
  switch (priority) {
    case 'major_highlight':
      return 'warning';
    case 'ministry_activity':
      return 'info';
    case 'routine':
    default:
      return 'neutral';
  }
}

export function getProgramCodeBadgeVariant(code: ProgramCode): BadgeVariant {
  switch (code) {
    case 'youth_camp':
      return 'info';
    case 'discovery_camp':
      return 'success';
    case 'cls':
      return 'warning';
    case 'lcs':
      return 'success';
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

export function getProgramSessionBadgeLabel(evt: {
  program_code?: string | null;
  session_number?: number | null;
  session_count?: number | null;
}): string {
  let base = 'Program';
  if (evt.program_code === 'cls') {
    base = 'CLS';
  } else if (evt.program_code === 'lcs') {
    base = 'LCS';
  } else if (evt.program_code === 'youth_camp') {
    base = 'Youth Camp';
  } else if (evt.program_code === 'discovery_camp') {
    base = 'Discovery Camp';
  }

  if (evt.session_count === 1 || !evt.session_number) {
    return base;
  }
  return `${base} · S${evt.session_number}`;
}

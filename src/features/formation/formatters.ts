import type {
  FormationDatePrecision,
  FormationProgramCategory,
  FormationProgramType,
  FormationTargetAudience,
} from './types';

const MONTH_NAMES = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
] as const;

/**
 * Formats a formation completion date strictly by its precision contract:
 * - exact_date  → "June 14, 2015"
 * - month_year  → "June 2015"
 * - year_only   → "2015"
 * - approximate → "c. 2015"
 * - unknown     → "Date unknown"
 *
 * Never invents a day or a month.
 */
export function formatFormationCompletionDate(
  precision: FormationDatePrecision,
  completedDate: string | null,
  completedYear: number | null,
  completedMonth: number | null
): string {
  switch (precision) {
    case 'exact_date': {
      if (completedDate) {
        const parts = completedDate.split('-');
        if (parts.length === 3) {
          const y = parseInt(parts[0], 10);
          const m = parseInt(parts[1], 10);
          const d = parseInt(parts[2], 10);
          if (!Number.isNaN(y) && !Number.isNaN(m) && !Number.isNaN(d) && m >= 1 && m <= 12) {
            return `${MONTH_NAMES[m - 1]} ${d}, ${y}`;
          }
        }
      }
      if (completedYear && completedMonth && completedMonth >= 1 && completedMonth <= 12) {
        return `${MONTH_NAMES[completedMonth - 1]} ${completedYear}`;
      }
      if (completedYear) {
        return `${completedYear}`;
      }
      return 'Date unknown';
    }

    case 'month_year': {
      let year = completedYear;
      let month = completedMonth;

      if ((!year || !month) && completedDate) {
        const parts = completedDate.split('-');
        if (parts.length >= 2) {
          year = parseInt(parts[0], 10);
          month = parseInt(parts[1], 10);
        }
      }

      if (year && month && month >= 1 && month <= 12) {
        return `${MONTH_NAMES[month - 1]} ${year}`;
      }
      if (year) {
        return `${year}`;
      }
      return 'Date unknown';
    }

    case 'year_only': {
      let year = completedYear;
      if (!year && completedDate) {
        const parsed = parseInt(completedDate.split('-')[0], 10);
        if (!Number.isNaN(parsed)) {
          year = parsed;
        }
      }
      if (year) {
        return `${year}`;
      }
      return 'Date unknown';
    }

    case 'approximate': {
      let year = completedYear;
      if (!year && completedDate) {
        const parsed = parseInt(completedDate.split('-')[0], 10);
        if (!Number.isNaN(parsed)) {
          year = parsed;
        }
      }
      if (year) {
        return `c. ${year}`;
      }
      return 'Date unknown';
    }

    case 'unknown':
    default:
      return 'Date unknown';
  }
}

export function formatProgramCategory(category: FormationProgramCategory): string {
  switch (category) {
    case 'pastoral_formation':
      return 'Pastoral Formation';
    case 'leadership_training':
      return 'Leadership Training';
    case 'ministry_skills':
      return 'Ministry Skills';
    default: {
      const exhaustiveCheck: string = category;
      return exhaustiveCheck.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
    }
  }
}

export function formatProgramType(type: FormationProgramType): string {
  switch (type) {
    case 'course':
      return 'Course';
    case 'retreat':
      return 'Retreat';
    case 'recollection':
      return 'Recollection';
    case 'entry_seminar':
      return 'Entry Seminar';
    case 'training_workshop':
      return 'Training Workshop';
    default: {
      const exhaustiveCheck: string = type;
      return exhaustiveCheck.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
    }
  }
}

export function formatTargetAudience(audience: FormationTargetAudience): string {
  switch (audience) {
    case 'all_members':
      return 'All Members';
    case 'couples':
      return 'Couples';
    case 'household_servants':
      return 'Household Servants';
    case 'unit_servants_above':
      return 'Unit Servants and Above';
    case 'chapter_servants':
      return 'Chapter Servants';
    case 'service_team':
      return 'Service Team';
    default: {
      const exhaustiveCheck: string = audience;
      return exhaustiveCheck.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
    }
  }
}

export function formatTimingNorm(timingNorm: string | null | undefined): string | null {
  if (!timingNorm) return null;
  switch (timingNorm.toLowerCase().trim()) {
    case 'entry':
      return 'Entry phase';
    case 'month_3':
      return 'Approximately Month 3';
    case 'month_6':
      return 'Approximately Month 6';
    case 'month_12':
      return 'Approximately Month 12';
    case 'year_2_onward':
      return 'Year 2 onward';
    case 'upon_appointment':
      return 'Upon appointment';
    case 'prior_to_service':
      return 'Prior to service';
    default:
      return timingNorm.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

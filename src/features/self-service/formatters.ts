/**
 * Formatting utilities for member self-service and household meeting schedules.
 */

const DAYS_OF_WEEK = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
] as const;

export function formatDayOfWeek(day: number | null | undefined): string | null {
  if (day === null || day === undefined) return null;
  return DAYS_OF_WEEK[day] ?? null;
}

export function formatFrequency(freq: string | null | undefined): string | null {
  if (!freq) return null;
  const normalized = freq.toLowerCase().trim();
  switch (normalized) {
    case 'weekly':
      return 'Weekly';
    case 'biweekly':
      return 'Biweekly';
    case 'monthly':
      return 'Monthly';
    case 'quarterly':
      return 'Quarterly';
    case 'seasonal':
      return 'Seasonal';
    case 'variable':
      return 'Variable';
    default:
      return normalized.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

export function formatMeetingTime(
  timeStr: string | null | undefined,
  timeZone?: string | null
): string | null {
  if (!timeStr) return null;
  const parts = timeStr.split(':');
  if (parts.length < 2) return null;
  const hour = parseInt(parts[0], 10);
  const minute = parseInt(parts[1], 10);
  if (Number.isNaN(hour) || Number.isNaN(minute)) return null;

  const period = hour >= 12 ? 'PM' : 'AM';
  const hour12 = hour % 12 || 12;
  const minuteStr = minute.toString().padStart(2, '0');
  const baseTime = `${hour12}:${minuteStr} ${period}`;

  if (timeZone) {
    try {
      const formatter = new Intl.DateTimeFormat('en-US', {
        timeZone,
        timeZoneName: 'short',
      });
      const tzPart = formatter
        .formatToParts(new Date())
        .find((p) => p.type === 'timeZoneName')?.value;
      if (tzPart) {
        return `${baseTime} ${tzPart}`;
      }
      return `${baseTime} (${timeZone})`;
    } catch {
      return baseTime;
    }
  }

  return baseTime;
}

export interface ScheduleInput {
  frequency?: string | null;
  dayOfWeek?: number | null;
  startTime?: string | null;
  timezoneName?: string | null;
}

export function formatMeetingSchedule({
  frequency,
  dayOfWeek,
  startTime,
  timezoneName,
}: ScheduleInput): string {
  const dayText = formatDayOfWeek(dayOfWeek);
  const timeText = formatMeetingTime(startTime, timezoneName);
  const freq = frequency?.toLowerCase().trim() || null;

  if (!freq && !dayText && !timeText) {
    return 'Meeting schedule not yet set.';
  }

  if (freq === 'weekly') {
    if (dayText && timeText) return `Every ${dayText} at ${timeText}`;
    if (dayText && !timeText) return `Every ${dayText}`;
    if (!dayText && timeText) return `Weekly at ${timeText}`;
    return 'Weekly';
  }

  if (freq === 'biweekly') {
    if (dayText && timeText) return `Biweekly on ${dayText} at ${timeText}`;
    if (dayText && !timeText) return `Biweekly on ${dayText}`;
    if (!dayText && timeText) return `Biweekly at ${timeText}`;
    return 'Biweekly';
  }

  if (freq === 'monthly') {
    if (dayText && timeText) return `Monthly on ${dayText} at ${timeText}`;
    if (dayText && !timeText) return `Monthly on ${dayText}`;
    if (!dayText && timeText) return `Monthly at ${timeText}`;
    return 'Monthly';
  }

  if (freq) {
    const freqLabel = formatFrequency(freq) || freq;
    if (dayText && timeText) return `${freqLabel} on ${dayText} at ${timeText}`;
    if (dayText && !timeText) return `${freqLabel} on ${dayText}`;
    if (!dayText && timeText) return `${freqLabel} at ${timeText}`;
    return freqLabel;
  }

  // No explicit frequency provided, but day or time exists
  if (dayText && timeText) return `${dayText}s at ${timeText}`;
  if (dayText) return `${dayText}s`;
  if (timeText) return `At ${timeText}`;

  return 'Meeting schedule not yet set.';
}

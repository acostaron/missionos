export const NY_TZ = 'America/New_York';

function nyOffsetMinutes(utcMs: number): number {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: NY_TZ,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const p = Object.fromEntries(dtf.formatToParts(new Date(utcMs)).map((x) => [x.type, x.value]));
  const asUtc = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  return (asUtc - utcMs) / 60000;
}

/** date 'YYYY-MM-DD' + time 'HH:mm' entered as New York wall-clock time → ISO UTC string */
export function nyLocalToIso(date: string, time: string): string {
  const [y, m, d] = date.split('-').map(Number);
  const [hh, mm] = time.split(':').map(Number);
  const guess = Date.UTC(y, m - 1, d, hh, mm);
  let utc = guess - nyOffsetMinutes(guess) * 60000;
  utc = guess - nyOffsetMinutes(utc) * 60000;
  return new Date(utc).toISOString();
}

/** ISO timestamp → { date: 'YYYY-MM-DD', time: 'HH:mm' } in New York */
export function isoToNyLocal(iso: string): { date: string; time: string } {
  const dtf = new Intl.DateTimeFormat('en-CA', {
    timeZone: NY_TZ,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
  const p = Object.fromEntries(dtf.formatToParts(new Date(iso)).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}` };
}

/** Today's calendar date 'YYYY-MM-DD' in New York */
export function getTodayNyDate(): string {
  const now = new Date();
  const dtf = new Intl.DateTimeFormat('en-CA', {
    timeZone: NY_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return dtf.format(now);
}

/** Formats an ISO string to 12-hour time in NY (e.g. "7:00 PM") */
export function formatNyTime(iso: string): string {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: NY_TZ,
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(new Date(iso));
}

/** Formats start and optional end time in NY (e.g. "7:00 PM – 9:00 PM" or "7:00 PM") */
export function formatNyTimeRange(startsAt: string, endsAt?: string | null): string {
  const startStr = formatNyTime(startsAt);
  if (!endsAt) return startStr;
  const endStr = formatNyTime(endsAt);
  return `${startStr} – ${endStr}`;
}

/** Formats date to long format (e.g. "Saturday, October 11, 2026") */
export function formatNyDateLong(isoOrDate: string): string {
  const d = isoOrDate.includes('T') ? new Date(isoOrDate) : new Date(`${isoOrDate}T12:00:00Z`);
  return new Intl.DateTimeFormat('en-US', {
    timeZone: NY_TZ,
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(d);
}

/** Formats date to short format (e.g. "Sat, Oct 11, 2026") */
export function formatNyDateShort(isoOrDate: string): string {
  const d = isoOrDate.includes('T') ? new Date(isoOrDate) : new Date(`${isoOrDate}T12:00:00Z`);
  return new Intl.DateTimeFormat('en-US', {
    timeZone: NY_TZ,
    weekday: 'short',
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(d);
}

/** Formats month and year header (e.g. "October 2026") */
export function formatNyMonthYear(year: number, monthIndex: number): string {
  // monthIndex: 0 = January, 11 = December
  const d = new Date(Date.UTC(year, monthIndex, 15, 12, 0, 0));
  return new Intl.DateTimeFormat('en-US', {
    timeZone: NY_TZ,
    year: 'numeric',
    month: 'long',
  }).format(d);
}

/** Returns first and last calendar dates 'YYYY-MM-DD' for a given month in New York */
export function getNyMonthRange(year: number, monthIndex: number): { from: string; to: string } {
  const y = String(year);
  const m = String(monthIndex + 1).padStart(2, '0');
  const from = `${y}-${m}-01`;
  const lastDay = new Date(year, monthIndex + 1, 0).getDate();
  const to = `${y}-${m}-${String(lastDay).padStart(2, '0')}`;
  return { from, to };
}

/** Adds given days to a 'YYYY-MM-DD' date string and returns 'YYYY-MM-DD' */
export function addDaysToDateStr(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d + days, 12, 0, 0));
  const ny = new Intl.DateTimeFormat('en-CA', {
    timeZone: NY_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
  return ny;
}

import { useState, useMemo } from 'react';
import { Calendar, CalendarCheck2, Clock, MapPin, QrCode } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import {
  useListMyEvents,
  useListMyHouseholdMeetings,
  useListMyAttendance,
  type MyEvent,
  type MyHouseholdMeeting,
} from '../features/self-service/portal-api';
import {
  getTodayNyDate,
  addDaysToDateStr,
  formatNyDateShort,
  formatNyTime,
  isoToNyLocal,
  formatNyMonthYear,
} from '../lib/ny-time';
import { EVENT_TYPE_LABELS, getEventTypeBadgeVariant } from '../features/events/labels';
import type { EventType } from '../features/events/types';
import { Badge, Card, EmptyState, PageHeader } from '../components/ui';
import { HouseholdTopicsCard } from '../features/self-service/HouseholdTopicsCard';

type UpcomingItem =
  | { kind: 'event'; sortKey: string; event: MyEvent }
  | { kind: 'meeting'; sortKey: string; meeting: MyHouseholdMeeting };

export default function MyEventsPage() {
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;

  const [activeTab, setActiveTab] = useState<'upcoming' | 'attendance'>('upcoming');

  const today = getTodayNyDate();
  const upcomingTo = useMemo(() => addDaysToDateStr(today, 120), [today]);
  const pastFrom = useMemo(() => addDaysToDateStr(today, -365), [today]);

  const { data: upcomingEvents = [], isLoading: isEventsLoading } = useListMyEvents(
    orgId,
    today,
    upcomingTo
  );

  const { data: householdMeetings = [], isLoading: isMeetingsLoading } = useListMyHouseholdMeetings(
    orgId,
    today,
    upcomingTo
  );

  const { data: attendanceList = [], isLoading: isAttendanceLoading } = useListMyAttendance(
    orgId,
    pastFrom,
    today
  );

  // Group upcoming events and meetings by month ('YYYY-MM')
  const groupedUpcoming = useMemo(() => {
    const groups: { monthKey: string; monthLabel: string; items: UpcomingItem[] }[] = [];
    const map = new Map<string, UpcomingItem[]>();

    upcomingEvents.forEach((e) => {
      const local = isoToNyLocal(e.starts_at);
      const key = local.date.slice(0, 7); // 'YYYY-MM'
      if (!map.has(key)) {
        map.set(key, []);
      }
      map.get(key)!.push({
        kind: 'event',
        sortKey: `${local.date}T${local.time}`,
        event: e,
      });
    });

    householdMeetings
      .filter((m) => m.meeting_date >= today)
      .forEach((m) => {
        const key = m.meeting_date.slice(0, 7); // 'YYYY-MM'
        if (!map.has(key)) {
          map.set(key, []);
        }
        const timePart = m.scheduled_start_at
          ? isoToNyLocal(m.scheduled_start_at).time
          : '99:99';
        map.get(key)!.push({
          kind: 'meeting',
          sortKey: `${m.meeting_date}T${timePart}`,
          meeting: m,
        });
      });

    Array.from(map.keys()).sort().forEach((key) => {
      const [y, m] = key.split('-').map(Number);
      const items = map.get(key)!;
      items.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
      groups.push({
        monthKey: key,
        monthLabel: formatNyMonthYear(y, m - 1),
        items,
      });
    });

    return groups;
  }, [upcomingEvents, householdMeetings, today]);

  if (isOrgLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center">
        <div className="text-sm text-ink-muted">Loading events…</div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6 px-4 py-8 sm:px-6">
      <PageHeader
        title="My Events"
        description="View your upcoming community assemblies and personal attendance record."
      />

      <HouseholdTopicsCard organizationId={orgId} />

      {/* Tabs */}
      <div className="flex border-b border-line gap-4">
        <button
          type="button"
          onClick={() => setActiveTab('upcoming')}
          className={`flex items-center gap-2 pb-3 text-small font-medium border-b-2 transition-colors ${
            activeTab === 'upcoming'
              ? 'border-primary text-primary'
              : 'border-transparent text-ink-secondary hover:text-ink'
          }`}
        >
          <Calendar className="h-4 w-4" />
          Upcoming
        </button>
        <button
          type="button"
          onClick={() => setActiveTab('attendance')}
          className={`flex items-center gap-2 pb-3 text-small font-medium border-b-2 transition-colors ${
            activeTab === 'attendance'
              ? 'border-primary text-primary'
              : 'border-transparent text-ink-secondary hover:text-ink'
          }`}
        >
          <CalendarCheck2 className="h-4 w-4" />
          My attendance
        </button>
      </div>

      {/* Tab 1: Upcoming Events */}
      {activeTab === 'upcoming' && (
        <div className="space-y-6">
          {isEventsLoading || isMeetingsLoading ? (
            <div className="p-8 text-center text-sm text-ink-muted">Loading upcoming events…</div>
          ) : groupedUpcoming.length === 0 ? (
            <Card padding="comfortable">
              <EmptyState
                icon={<Calendar />}
                title="No upcoming events for you yet."
                message="Check back later for assemblies, teachings, and formation gatherings."
              />
            </Card>
          ) : (
            groupedUpcoming.map((group) => (
              <div key={group.monthKey} className="space-y-3">
                <h3 className="text-xs font-bold uppercase tracking-wider text-ink-secondary">
                  {group.monthLabel}
                </h3>
                <div className="space-y-2">
                  {group.items.map((item) => {
                    if (item.kind === 'event') {
                      const e = item.event;
                      const isCancelled = e.event_status === 'cancelled';
                      const typeLabel = EVENT_TYPE_LABELS[e.event_type as EventType] || e.event_type;
                      const typeBadgeVariant = getEventTypeBadgeVariant(e.event_type as EventType);

                      return (
                        <div
                          key={`event-${e.event_id}`}
                          className={`rounded-card border border-line bg-surface p-4 transition-colors ${
                            isCancelled ? 'opacity-70' : ''
                          }`}
                        >
                          <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-2">
                            <div className="space-y-1">
                              <div className="flex flex-wrap items-center gap-2">
                                <Badge variant={typeBadgeVariant}>{typeLabel}</Badge>
                                {isCancelled && <Badge variant="danger">Cancelled</Badge>}
                                {e.attended && <Badge variant="success">Attended</Badge>}
                              </div>

                              <h4
                                className={`text-base font-semibold text-ink pt-1 ${
                                  isCancelled ? 'line-through text-ink-muted' : ''
                                }`}
                              >
                                {e.title}
                              </h4>

                              <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-ink-secondary pt-1">
                                <span className="flex items-center gap-1 font-medium">
                                  <Clock className="h-3.5 w-3.5 text-ink-muted" />
                                  {formatNyDateShort(e.starts_at)} · {formatNyTime(e.starts_at)}
                                </span>

                                {e.location_text && (
                                  <span className="flex items-center gap-1">
                                    <MapPin className="h-3.5 w-3.5 text-ink-muted" />
                                    {e.location_text}
                                  </span>
                                )}

                                {e.audience_name && (
                                  <span className="rounded bg-surface-muted px-1.5 py-0.5 text-[11px] text-ink-muted">
                                    {e.audience_name}
                                  </span>
                                )}
                              </div>

                              {e.program_title && (
                                <p className="text-xs font-medium text-primary pt-1">
                                  Session {e.session_number || 1}
                                  {e.session_count ? ` of ${e.session_count}` : ''} · {e.program_title}
                                </p>
                              )}
                            </div>
                          </div>
                        </div>
                      );
                    }

                    const m = item.meeting;
                    const isCancelled = m.meeting_status === 'cancelled';

                    return (
                      <div
                        key={`meeting-${m.household_meeting_id}`}
                        className={`rounded-card border border-line bg-surface p-4 transition-colors ${
                          isCancelled ? 'opacity-70' : ''
                        }`}
                      >
                        <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-2">
                          <div className="space-y-1">
                            <div className="flex flex-wrap items-center gap-2">
                              <Badge variant="neutral">Household</Badge>
                              {isCancelled && <Badge variant="danger">Cancelled</Badge>}
                            </div>

                            <h4
                              className={`text-base font-semibold text-ink pt-1 ${
                                isCancelled ? 'line-through text-ink-muted' : ''
                              }`}
                            >
                              {m.household_name} — Household Meeting
                            </h4>

                            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-ink-secondary pt-1">
                              <span className="flex items-center gap-1 font-medium">
                                <Clock className="h-3.5 w-3.5 text-ink-muted" />
                                {formatNyDateShort(m.meeting_date)} ·{' '}
                                {m.scheduled_start_at
                                  ? formatNyTime(m.scheduled_start_at)
                                  : 'Time to be confirmed'}
                              </span>

                              {m.location_text && (
                                <span className="flex items-center gap-1">
                                  <MapPin className="h-3.5 w-3.5 text-ink-muted" />
                                  {m.location_text}
                                </span>
                              )}

                              {m.host_name && (
                                <span className="text-ink-muted">
                                  Host: {m.host_name}
                                </span>
                              )}
                            </div>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Tab 2: My Attendance */}
      {activeTab === 'attendance' && (
        <div className="space-y-4">
          {isAttendanceLoading ? (
            <div className="p-8 text-center text-sm text-ink-muted">Loading attendance history…</div>
          ) : attendanceList.length === 0 ? (
            <Card padding="comfortable">
              <EmptyState
                icon={<CalendarCheck2 />}
                title="No attendance recorded yet."
                message="When you attend an event or check in with your QR code, your record will appear here."
              />
            </Card>
          ) : (
            <div className="divide-y divide-line rounded-card border border-line bg-surface overflow-hidden">
              {attendanceList.map((a) => {
                const typeLabel = EVENT_TYPE_LABELS[a.event_type as EventType] || a.event_type;
                const typeBadgeVariant = getEventTypeBadgeVariant(a.event_type as EventType);

                return (
                  <div key={a.event_id} className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-surface-muted/40 transition-colors">
                    <div className="space-y-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <Badge variant={typeBadgeVariant}>{typeLabel}</Badge>
                        {a.check_in_method === 'qr' && (
                          <span className="inline-flex items-center gap-1 rounded bg-navy-50 px-2 py-0.5 text-caption font-medium text-primary">
                            <QrCode className="h-3 w-3" />
                            Checked in by QR
                          </span>
                        )}
                      </div>

                      <p className="text-small font-semibold text-ink pt-0.5">{a.title}</p>

                      {a.program_title && (
                        <p className="text-xs text-primary font-medium">
                          Session {a.session_number || 1} · {a.program_title}
                        </p>
                      )}
                    </div>

                    <div className="text-xs text-ink-muted sm:text-right shrink-0">
                      <p className="font-medium text-ink-secondary">{formatNyDateShort(a.starts_at)}</p>
                      <p className="text-[11px]">Recorded {formatNyDateShort(a.recorded_at)}</p>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

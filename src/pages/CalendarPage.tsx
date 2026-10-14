import { useState, useMemo } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  GraduationCap,
  List as ListIcon,
  Plus,
} from 'lucide-react';
import {
  Badge,
  Button,
  Card,
  EmptyState,
  Modal,
  PageHeader,
  Skeleton,
} from '../components/ui';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { useEventsList } from '../features/events/queries';
import { useProgramRunsList } from '../features/programs/queries';
import {
  EVENT_STATUS_LABELS,
  EVENT_TYPE_LABELS,
  getEventStatusBadgeVariant,
  getEventTypeBadgeVariant,
} from '../features/events/labels';
import { getProgramSessionBadgeLabel } from '../features/programs/labels';
import { EventFormModal } from '../features/events/components/EventFormModal';
import { NewProgramModal } from '../features/programs/components/NewProgramModal';
import { ProgramsList } from '../features/programs/components/ProgramsList';
import {
  formatNyDateLong,
  formatNyMonthYear,
  formatNyTime,
  formatNyTimeRange,
  getNyMonthRange,
  getTodayNyDate,
  isoToNyLocal,
} from '../lib/ny-time';
import type { EventSummary } from '../features/events/types';

export type CalendarTab = 'month' | 'list' | 'programs';

interface MonthGridItem {
  event: EventSummary;
  isFirstDay: boolean;
  dateStr: string;
}

export default function CalendarPage() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { organization, isLoading: isOrgLoading } = useCurrentOrganization();
  const orgId = organization?.id ?? null;

  // Active tab management with URL synchronization (?tab=month|list|programs)
  const tabParam = searchParams.get('tab');
  const currentTab: CalendarTab =
    tabParam === 'month' || tabParam === 'list' || tabParam === 'programs'
      ? tabParam
      : typeof window !== 'undefined' && window.innerWidth < 768
        ? 'list'
        : 'month';

  const setTab = (newTab: CalendarTab) => {
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev);
        next.set('tab', newTab);
        return next;
      },
      { replace: true }
    );
  };

  // Track selected year & monthIndex (0-indexed)
  const todayNy = getTodayNyDate();
  const [todayY, todayM] = todayNy.split('-').map(Number);

  const [currentYear, setCurrentYear] = useState(todayY);
  const [currentMonthIndex, setCurrentMonthIndex] = useState(todayM - 1);

  // Filters
  const [showCancelled, setShowCancelled] = useState(false);
  const [includeClosedPrograms, setIncludeClosedPrograms] = useState(false);

  // Modals state
  const [isChooserOpen, setIsChooserOpen] = useState(false);
  const [isCreateEventOpen, setIsCreateEventOpen] = useState(false);
  const [isNewProgramOpen, setIsNewProgramOpen] = useState(false);

  const { from, to } = useMemo(
    () => getNyMonthRange(currentYear, currentMonthIndex),
    [currentYear, currentMonthIndex]
  );

  const { data: eventsData, isLoading: isEventsLoading } = useEventsList(orgId, from, to);
  const { data: programsData } = useProgramRunsList(orgId, includeClosedPrograms);

  const canManageEvents = eventsData?.can_manage ?? false;
  const canCreatePrograms = programsData?.can_create ?? false;
  const canCreate = canManageEvents || canCreatePrograms;

  const handlePrevMonth = () => {
    if (currentMonthIndex === 0) {
      setCurrentYear((y) => y - 1);
      setCurrentMonthIndex(11);
    } else {
      setCurrentMonthIndex((m) => m - 1);
    }
  };

  const handleNextMonth = () => {
    if (currentMonthIndex === 11) {
      setCurrentYear((y) => y + 1);
      setCurrentMonthIndex(0);
    } else {
      setCurrentMonthIndex((m) => m + 1);
    }
  };

  const handleToday = () => {
    setCurrentYear(todayY);
    setCurrentMonthIndex(todayM - 1);
  };

  // Filter events based on showCancelled
  const filteredEvents = useMemo(() => {
    if (!eventsData?.events) return [];
    if (showCancelled) return eventsData.events;
    return eventsData.events.filter((e) => e.event_status !== 'cancelled');
  }, [eventsData?.events, showCancelled]);

  // Group events by New York date string for Month view (with multi-day spanning)
  const monthEventsByDate = useMemo(() => {
    const map = new Map<string, MonthGridItem[]>();
    for (const e of filteredEvents) {
      const startLocal = isoToNyLocal(e.starts_at);
      const startDateStr = startLocal.date;
      const endDateStr = e.ends_at ? isoToNyLocal(e.ends_at).date : startDateStr;

      if (e.ends_at && endDateStr > startDateStr) {
        // Multi-day session: spans every day from startDateStr to endDateStr
        const current = new Date(`${startDateStr}T12:00:00Z`);
        const end = new Date(`${endDateStr}T12:00:00Z`);
        let isFirst = true;

        while (current <= end) {
          const y = current.getUTCFullYear();
          const m = String(current.getUTCMonth() + 1).padStart(2, '0');
          const d = String(current.getUTCDate()).padStart(2, '0');
          const dateStr = `${y}-${m}-${d}`;

          const list = map.get(dateStr) ?? [];
          list.push({ event: e, isFirstDay: isFirst, dateStr });
          map.set(dateStr, list);

          isFirst = false;
          current.setUTCDate(current.getUTCDate() + 1);
        }
      } else {
        // Single day session
        const list = map.get(startDateStr) ?? [];
        list.push({ event: e, isFirstDay: true, dateStr: startDateStr });
        map.set(startDateStr, list);
      }
    }
    return map;
  }, [filteredEvents]);

  // Group events by New York date string for List view (by start date)
  const eventsByDate = useMemo(() => {
    const map = new Map<string, EventSummary[]>();
    for (const e of filteredEvents) {
      const local = isoToNyLocal(e.starts_at);
      const list = map.get(local.date) ?? [];
      list.push(e);
      map.set(local.date, list);
    }
    return map;
  }, [filteredEvents]);

  // Generate calendar grid days for Month view
  const monthGridDays = useMemo(() => {
    const firstDayDate = new Date(Date.UTC(currentYear, currentMonthIndex, 1));
    const firstDayOfWeek = firstDayDate.getUTCDay(); // 0 = Sunday, 6 = Saturday
    const daysInMonth = new Date(currentYear, currentMonthIndex + 1, 0).getDate();

    const days: Array<{
      dateStr: string;
      dayNumber: number;
      isCurrentMonth: boolean;
      isToday: boolean;
    }> = [];

    // Previous month padding
    const prevMonthDaysCount = new Date(currentYear, currentMonthIndex, 0).getDate();
    for (let i = firstDayOfWeek - 1; i >= 0; i--) {
      const dayNum = prevMonthDaysCount - i;
      const prevM = currentMonthIndex === 0 ? 12 : currentMonthIndex;
      const prevY = currentMonthIndex === 0 ? currentYear - 1 : currentYear;
      const dStr = `${prevY}-${String(prevM).padStart(2, '0')}-${String(dayNum).padStart(2, '0')}`;
      days.push({
        dateStr: dStr,
        dayNumber: dayNum,
        isCurrentMonth: false,
        isToday: dStr === todayNy,
      });
    }

    // Current month days
    for (let dayNum = 1; dayNum <= daysInMonth; dayNum++) {
      const dStr = `${currentYear}-${String(currentMonthIndex + 1).padStart(2, '0')}-${String(dayNum).padStart(2, '0')}`;
      days.push({
        dateStr: dStr,
        dayNumber: dayNum,
        isCurrentMonth: true,
        isToday: dStr === todayNy,
      });
    }

    // Next month padding to fill out complete 7-day rows (up to 35 or 42)
    const remaining = 7 - (days.length % 7);
    if (remaining < 7) {
      for (let dayNum = 1; dayNum <= remaining; dayNum++) {
        const nextM = currentMonthIndex === 11 ? 1 : currentMonthIndex + 2;
        const nextY = currentMonthIndex === 11 ? currentYear + 1 : currentYear;
        const dStr = `${nextY}-${String(nextM).padStart(2, '0')}-${String(dayNum).padStart(2, '0')}`;
        days.push({
          dateStr: dStr,
          dayNumber: dayNum,
          isCurrentMonth: false,
          isToday: dStr === todayNy,
        });
      }
    }

    return days;
  }, [currentYear, currentMonthIndex, todayNy]);

  // List view grouping: unique dates that have events, sorted ascending
  const listDates = useMemo(() => {
    return Array.from(eventsByDate.keys()).sort();
  }, [eventsByDate]);

  if (isOrgLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-10 w-48" />
        <Skeleton className="h-96" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Calendar"
        description="Community assemblies, teachings, course talks, and events."
        actions={
          canCreate ? (
            <Button
              variant="primary"
              icon={<Plus className="h-4 w-4" />}
              onClick={() => setIsChooserOpen(true)}
            >
              New
            </Button>
          ) : undefined
        }
      />

      {/* Controls Bar */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        {/* Left Side: Month/List Navigation Controls (Hidden on Programs tab) */}
        {currentTab !== 'programs' ? (
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={handlePrevMonth}
              aria-label="Previous month"
            >
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <Button variant="outline" size="sm" onClick={handleToday}>
              Today
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={handleNextMonth}
              aria-label="Next month"
            >
              <ChevronRight className="h-4 w-4" />
            </Button>
            <span className="ml-2 text-h3 font-semibold text-ink">
              {formatNyMonthYear(currentYear, currentMonthIndex)}
            </span>
          </div>
        ) : (
          <div />
        )}

        {/* Right Side: Filters and View Mode Tabs */}
        <div className="flex flex-wrap items-center gap-4">
          {currentTab !== 'programs' ? (
            <label className="flex cursor-pointer items-center gap-2 text-small text-ink-secondary">
              <input
                type="checkbox"
                checked={showCancelled}
                onChange={(e) => setShowCancelled(e.target.checked)}
                className="h-4 w-4 rounded border-line text-primary focus:ring-focus"
              />
              Show cancelled
            </label>
          ) : (
            <label className="flex cursor-pointer items-center gap-2 text-small text-ink-secondary">
              <input
                type="checkbox"
                checked={includeClosedPrograms}
                onChange={(e) => setIncludeClosedPrograms(e.target.checked)}
                className="h-4 w-4 rounded border-line text-primary focus:ring-focus"
              />
              Show completed & cancelled
            </label>
          )}

          {/* Three tabs: Month | List | Programs */}
          <div className="inline-flex rounded-control border border-line bg-surface p-0.5">
            <button
              type="button"
              onClick={() => setTab('month')}
              className={`flex items-center gap-1.5 rounded-[calc(var(--radius-control)-2px)] px-3 py-1 text-small font-medium transition-colors ${
                currentTab === 'month'
                  ? 'bg-primary text-white shadow-xs'
                  : 'text-ink-secondary hover:text-ink'
              }`}
            >
              <CalendarDays className="h-3.5 w-3.5" />
              Month
            </button>
            <button
              type="button"
              onClick={() => setTab('list')}
              className={`flex items-center gap-1.5 rounded-[calc(var(--radius-control)-2px)] px-3 py-1 text-small font-medium transition-colors ${
                currentTab === 'list'
                  ? 'bg-primary text-white shadow-xs'
                  : 'text-ink-secondary hover:text-ink'
              }`}
            >
              <ListIcon className="h-3.5 w-3.5" />
              List
            </button>
            <button
              type="button"
              onClick={() => setTab('programs')}
              className={`flex items-center gap-1.5 rounded-[calc(var(--radius-control)-2px)] px-3 py-1 text-small font-medium transition-colors ${
                currentTab === 'programs'
                  ? 'bg-primary text-white shadow-xs'
                  : 'text-ink-secondary hover:text-ink'
              }`}
            >
              <GraduationCap className="h-3.5 w-3.5" />
              Programs
            </button>
          </div>
        </div>
      </div>

      {/* Main Content Area */}
      {currentTab === 'programs' ? (
        <ProgramsList
          organizationId={orgId}
          includeClosed={includeClosedPrograms}
        />
      ) : isEventsLoading ? (
        <Skeleton className="h-96" />
      ) : filteredEvents.length === 0 && currentTab === 'list' ? (
        <Card padding="comfortable">
          <EmptyState
            title="No events this month"
            message={
              canManageEvents
                ? 'There are no events scheduled for this month yet. Click "New" to schedule one.'
                : 'There are no events scheduled for this month.'
            }
          />
        </Card>
      ) : currentTab === 'month' ? (
        /* Month Grid View */
        <div className="overflow-hidden rounded-card border border-line bg-surface shadow-xs">
          {/* Day Headers (Sun - Sat) */}
          <div className="grid grid-cols-7 border-b border-line bg-surface-muted text-center text-caption font-semibold text-ink-secondary">
            {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((day) => (
              <div key={day} className="py-2">
                {day}
              </div>
            ))}
          </div>

          {/* Grid Cells */}
          <div className="grid grid-cols-7 divide-x divide-y divide-line">
            {monthGridDays.map((cell) => {
              const dayItems = monthEventsByDate.get(cell.dateStr) ?? [];

              return (
                <div
                  key={cell.dateStr}
                  className={`min-h-[100px] p-1.5 transition-colors sm:min-h-[120px] ${
                    cell.isCurrentMonth ? 'bg-surface' : 'bg-surface-muted/40 opacity-60'
                  } ${cell.isToday ? 'ring-2 ring-inset ring-primary' : ''}`}
                >
                  <div className="mb-1 flex items-center justify-between">
                    <span
                      className={`inline-flex h-6 w-6 items-center justify-center rounded-full text-caption font-semibold ${
                        cell.isToday
                          ? 'bg-primary text-white'
                          : cell.isCurrentMonth
                            ? 'text-ink'
                            : 'text-ink-muted'
                      }`}
                    >
                      {cell.dayNumber}
                    </span>
                  </div>

                  {/* Event Chips */}
                  <div className="space-y-1">
                    {dayItems.map((item) => (
                      <button
                        key={`${item.event.id}-${item.dateStr}`}
                        type="button"
                        onClick={() => navigate(`/app/calendar/${item.event.id}`)}
                        className={`group w-full truncate rounded px-1.5 py-1 text-left text-[11px] leading-tight font-medium transition-colors hover:brightness-95 ${
                          item.event.event_status === 'cancelled'
                            ? 'bg-danger-50 text-danger-700 line-through'
                            : item.event.event_type === 'assembly'
                              ? 'bg-navy-50 text-navy-800'
                              : item.event.event_type === 'chapter_assembly'
                                ? 'bg-warning-50 text-warning-800'
                                : item.event.event_type === 'section_assembly'
                                  ? 'bg-surface-muted text-ink'
                                  : item.event.event_type === 'formation_talk'
                                    ? 'bg-success-50 text-success-800'
                                    : 'bg-surface-muted text-ink'
                        }`}
                        title={
                          item.isFirstDay
                            ? `${formatNyTime(item.event.starts_at)} - ${item.event.title}`
                            : `${item.event.title} (cont.)`
                        }
                      >
                        {item.isFirstDay ? (
                          <>
                            <span className="font-semibold">{formatNyTime(item.event.starts_at)}</span>{' '}
                            {item.event.is_program_session && (
                              <span className="inline-flex items-center rounded bg-primary/10 px-1 py-0.2 text-[9px] font-bold text-primary mr-1">
                                {getProgramSessionBadgeLabel(item.event)}
                              </span>
                            )}
                            <span className="truncate">{item.event.title}</span>
                          </>
                        ) : (
                          <>
                            {item.event.is_program_session && (
                              <span className="inline-flex items-center rounded bg-primary/10 px-1 py-0.2 text-[9px] font-bold text-primary mr-1">
                                {getProgramSessionBadgeLabel(item.event)}
                              </span>
                            )}
                            <span className="italic text-ink-muted">(cont.)</span>
                          </>
                        )}
                      </button>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ) : (
        /* List View */
        <div className="space-y-6">
          {listDates.map((dateStr) => {
            const dayEvents = eventsByDate.get(dateStr) ?? [];

            return (
              <div key={dateStr} className="space-y-3">
                <div className="border-b border-line pb-1">
                  <h3 className="text-body font-semibold text-ink">
                    {formatNyDateLong(dateStr)}
                    {dateStr === todayNy && (
                      <span className="ml-2 inline-flex items-center rounded-full bg-primary/10 px-2 py-0.5 text-caption font-semibold text-primary">
                        Today
                      </span>
                    )}
                  </h3>
                </div>

                <div className="divide-y divide-line rounded-card border border-line bg-surface shadow-xs">
                  {dayEvents.map((evt) => {
                    const isPast = dateStr < todayNy || evt.event_status === 'held';

                    return (
                      <div
                        key={evt.id}
                        onClick={() => navigate(`/app/calendar/${evt.id}`)}
                        className="flex cursor-pointer flex-col justify-between gap-3 p-4 transition-colors hover:bg-surface-muted sm:flex-row sm:items-center"
                      >
                        <div className="min-w-0 space-y-1">
                          <div className="flex flex-wrap items-center gap-2">
                            {evt.is_program_session && (
                              <span className="inline-flex items-center rounded bg-primary/10 px-2 py-0.5 text-caption font-semibold text-primary">
                                {getProgramSessionBadgeLabel(evt)}
                              </span>
                            )}
                            <span className="text-body font-semibold text-ink">
                              {evt.title}
                            </span>
                            <Badge variant={getEventTypeBadgeVariant(evt.event_type)}>
                              {EVENT_TYPE_LABELS[evt.event_type]}
                            </Badge>
                            <Badge variant={getEventStatusBadgeVariant(evt.event_status)}>
                              {EVENT_STATUS_LABELS[evt.event_status]}
                            </Badge>
                          </div>

                          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-small text-ink-muted">
                            <span>{formatNyTimeRange(evt.starts_at, evt.ends_at)}</span>
                            {evt.location_text && <span>· {evt.location_text}</span>}
                            {evt.audience_name && (
                              <span>
                                ·{' '}
                                {evt.audience_type === 'chapter'
                                  ? evt.audience_name.toLowerCase().startsWith('chapter ')
                                    ? evt.audience_name
                                    : `Chapter ${evt.audience_name}`
                                  : evt.audience_type === 'section'
                                    ? evt.audience_name.toLowerCase().startsWith('section ')
                                      ? evt.audience_name
                                      : `Section ${evt.audience_name}`
                                    : evt.audience_name}
                              </span>
                            )}
                          </div>
                        </div>

                        {/* Past events attendance snippet */}
                        {isPast && evt.event_status !== 'cancelled' && (
                          <div className="shrink-0 text-right sm:text-right">
                            <p className="text-small font-medium text-ink">
                              Present {evt.present_expected_count} / expected {evt.expected_count}
                            </p>
                            {evt.guest_count > 0 && (
                              <p className="text-caption text-ink-muted">
                                +{evt.guest_count} guest{evt.guest_count === 1 ? '' : 's'}
                              </p>
                            )}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Creation Chooser Modal */}
      <Modal
        open={isChooserOpen}
        onClose={() => setIsChooserOpen(false)}
        title="Create new"
        size="sm"
      >
        <div className="space-y-3 py-2">
          <button
            type="button"
            onClick={() => {
              setIsChooserOpen(false);
              setIsCreateEventOpen(true);
            }}
            className="w-full text-left p-4 rounded-card border border-line bg-surface hover:border-primary hover:bg-surface-muted transition-all flex items-start gap-3.5 group cursor-pointer"
          >
            <div className="p-2.5 rounded-control bg-primary/10 text-primary group-hover:bg-primary group-hover:text-white transition-colors shrink-0">
              <CalendarDays className="h-5 w-5" />
            </div>
            <div>
              <div className="font-semibold text-body text-ink group-hover:text-primary transition-colors">
                Event
              </div>
              <div className="text-small text-ink-muted mt-0.5">
                Assemblies, formation talks, retreats and other one-time events
              </div>
            </div>
          </button>

          <button
            type="button"
            onClick={() => {
              setIsChooserOpen(false);
              setIsNewProgramOpen(true);
            }}
            className="w-full text-left p-4 rounded-card border border-line bg-surface hover:border-primary hover:bg-surface-muted transition-all flex items-start gap-3.5 group cursor-pointer"
          >
            <div className="p-2.5 rounded-control bg-primary/10 text-primary group-hover:bg-primary group-hover:text-white transition-colors shrink-0">
              <GraduationCap className="h-5 w-5" />
            </div>
            <div>
              <div className="font-semibold text-body text-ink group-hover:text-primary transition-colors">
                Program
              </div>
              <div className="text-small text-ink-muted mt-0.5">
                Youth Camp, Discovery Camp, Christian Life Seminar (with participants and sessions)
              </div>
            </div>
          </button>
        </div>
      </Modal>

      {/* New Event Modal */}
      {canManageEvents && orgId && (
        <EventFormModal
          open={isCreateEventOpen}
          onClose={() => setIsCreateEventOpen(false)}
          organizationId={orgId}
          onSuccess={(newEvent) => {
            navigate(`/app/calendar/${newEvent.id}`);
          }}
        />
      )}

      {/* New Program Modal */}
      {canCreatePrograms && orgId && (
        <NewProgramModal
          open={isNewProgramOpen}
          onClose={() => setIsNewProgramOpen(false)}
          organizationId={orgId}
          onSuccess={(newRun) => {
            navigate(`/app/programs/${newRun.id}`);
          }}
        />
      )}
    </div>
  );
}

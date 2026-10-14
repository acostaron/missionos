import { useState, useMemo, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  List as ListIcon,
  Plus,
} from 'lucide-react';
import {
  Badge,
  Button,
  Card,
  EmptyState,
  PageHeader,
  Skeleton,
} from '../components/ui';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { useEventsList } from '../features/events/queries';
import {
  EVENT_STATUS_LABELS,
  EVENT_TYPE_LABELS,
  getEventStatusBadgeVariant,
  getEventTypeBadgeVariant,
} from '../features/events/labels';
import { EventFormModal } from '../features/events/components/EventFormModal';
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

export default function CalendarPage() {
  const navigate = useNavigate();
  const { organization, isLoading: isOrgLoading } = useCurrentOrganization();
  const orgId = organization?.id ?? null;

  // Track selected year & monthIndex (0-indexed)
  const todayNy = getTodayNyDate();
  const [todayY, todayM] = todayNy.split('-').map(Number);

  const [currentYear, setCurrentYear] = useState(todayY);
  const [currentMonthIndex, setCurrentMonthIndex] = useState(todayM - 1);

  // Responsive view mode: default to List on mobile (< 768px), Month on desktop
  const [viewMode, setViewMode] = useState<'month' | 'list'>(() => {
    if (typeof window !== 'undefined' && window.innerWidth < 768) {
      return 'list';
    }
    return 'month';
  });

  const [showCancelled, setShowCancelled] = useState(false);
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);

  // Sync initial viewMode if window is resized before interaction
  useEffect(() => {
    const handleResize = () => {
      if (window.innerWidth < 768 && viewMode === 'month') {
        // Leave user choice if already touched, or default
      }
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [viewMode]);

  const { from, to } = useMemo(
    () => getNyMonthRange(currentYear, currentMonthIndex),
    [currentYear, currentMonthIndex]
  );

  const { data: eventsData, isLoading: isEventsLoading } = useEventsList(orgId, from, to);

  const canManage = eventsData?.can_manage ?? false;

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

  // Group events by New York date string 'YYYY-MM-DD'
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
          canManage ? (
            <Button
              variant="primary"
              icon={<Plus className="h-4 w-4" />}
              onClick={() => setIsCreateModalOpen(true)}
            >
              New event
            </Button>
          ) : undefined
        }
      />

      {/* Controls Bar */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        {/* Navigation: Prev / Today / Next / Month Name */}
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

        {/* View Toggle & Show Cancelled Filter */}
        <div className="flex flex-wrap items-center gap-4">
          <label className="flex cursor-pointer items-center gap-2 text-small text-ink-secondary">
            <input
              type="checkbox"
              checked={showCancelled}
              onChange={(e) => setShowCancelled(e.target.checked)}
              className="h-4 w-4 rounded border-line text-primary focus:ring-focus"
            />
            Show cancelled
          </label>

          <div className="inline-flex rounded-control border border-line bg-surface p-0.5">
            <button
              type="button"
              onClick={() => setViewMode('month')}
              className={`flex items-center gap-1.5 rounded-[calc(var(--radius-control)-2px)] px-3 py-1 text-small font-medium transition-colors ${
                viewMode === 'month'
                  ? 'bg-primary text-white shadow-xs'
                  : 'text-ink-secondary hover:text-ink'
              }`}
            >
              <CalendarDays className="h-3.5 w-3.5" />
              Month
            </button>
            <button
              type="button"
              onClick={() => setViewMode('list')}
              className={`flex items-center gap-1.5 rounded-[calc(var(--radius-control)-2px)] px-3 py-1 text-small font-medium transition-colors ${
                viewMode === 'list'
                  ? 'bg-primary text-white shadow-xs'
                  : 'text-ink-secondary hover:text-ink'
              }`}
            >
              <ListIcon className="h-3.5 w-3.5" />
              List
            </button>
          </div>
        </div>
      </div>

      {/* Main Content Area */}
      {isEventsLoading ? (
        <Skeleton className="h-96" />
      ) : filteredEvents.length === 0 && viewMode === 'list' ? (
        <Card padding="comfortable">
          <EmptyState
            title="No events this month"
            message={
              canManage
                ? 'There are no events scheduled for this month yet. Click "New event" to schedule one.'
                : 'There are no events scheduled for this month.'
            }
          />
        </Card>
      ) : viewMode === 'month' ? (
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
              const dayEvents = eventsByDate.get(cell.dateStr) ?? [];

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
                    {dayEvents.map((evt) => (
                      <button
                        key={evt.id}
                        type="button"
                        onClick={() => navigate(`/app/calendar/${evt.id}`)}
                        className={`group w-full truncate rounded px-1.5 py-1 text-left text-[11px] leading-tight font-medium transition-colors hover:brightness-95 ${
                          evt.event_status === 'cancelled'
                            ? 'bg-danger-50 text-danger-700 line-through'
                            : evt.event_type === 'assembly'
                              ? 'bg-navy-50 text-navy-800'
                              : evt.event_type === 'formation_talk'
                                ? 'bg-success-50 text-success-800'
                                : 'bg-surface-muted text-ink'
                        }`}
                        title={`${formatNyTime(evt.starts_at)} - ${evt.title}`}
                      >
                        <span className="font-semibold">{formatNyTime(evt.starts_at)}</span>{' '}
                        <span className="truncate">{evt.title}</span>
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
                            {evt.location_text && (
                              <span>· {evt.location_text}</span>
                            )}
                            {evt.audience_name && (
                              <span>· {evt.audience_name}</span>
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

      {/* New Event Modal */}
      {canManage && orgId && (
        <EventFormModal
          open={isCreateModalOpen}
          onClose={() => setIsCreateModalOpen(false)}
          organizationId={orgId}
          onSuccess={(newEvent) => {
            navigate(`/app/calendar/${newEvent.id}`);
          }}
        />
      )}
    </div>
  );
}

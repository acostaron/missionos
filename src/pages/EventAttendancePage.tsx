import { useState, useMemo } from 'react';
import { useParams, Link } from 'react-router-dom';
import {
  ArrowLeft,
  CheckCircle2,
  Circle,
  Loader2,
  Search,
} from 'lucide-react';
import {
  Alert,
  Badge,
  Skeleton,
} from '../components/ui';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { useEventRoster, useSetEventAttendance, eventKeys } from '../features/events/queries';
import { getEventErrorMessage } from '../features/events/error-message';
import { getTodayNyDate, isoToNyLocal } from '../lib/ny-time';
import { useQueryClient } from '@tanstack/react-query';
import type { EventRosterMember, EventRosterResponse } from '../features/events/types';

export default function EventAttendancePage() {
  const { eventId } = useParams<{ eventId: string }>();
  const queryClient = useQueryClient();
  const { organization, isLoading: isOrgLoading } = useCurrentOrganization();
  const orgId = organization?.id ?? null;

  const { data: rosterData, isLoading: isRosterLoading, error } = useEventRoster(
    orgId,
    eventId ?? null
  );

  const attendanceMutation = useSetEventAttendance();

  // Search & filter state
  const [search, setSearch] = useState('');
  const [filterMode, setFilterMode] = useState<'not_yet' | 'present' | 'all'>('not_yet');
  const [selectedSection, setSelectedSection] = useState<string>('all');
  const [inFlightIds, setInFlightIds] = useState<Set<string>>(new Set());
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const event = rosterData?.event;
  const members = useMemo(() => rosterData?.members ?? [], [rosterData?.members]);

  // Check if read-only
  const todayNy = getTodayNyDate();
  const eventDateNy = event ? isoToNyLocal(event.starts_at).date : todayNy;
  const isFuture = eventDateNy > todayNy;
  const isCancelled = event?.event_status === 'cancelled';
  const isReadOnly = isFuture || isCancelled || !event?.can_record;

  // Extract unique section names for the section filter
  const sectionOptions = useMemo(() => {
    const set = new Set<string>();
    let hasNoSection = false;
    for (const m of members) {
      if (m.section_name) {
        set.add(m.section_name);
      } else {
        hasNoSection = true;
      }
    }
    const list = Array.from(set).sort();
    return { sections: list, hasNoSection };
  }, [members]);

  // Filtered members list
  const filteredMembers = useMemo(() => {
    const q = search.trim().toLowerCase();

    return members
      .filter((m) => {
        // Attendance status filter
        if (filterMode === 'not_yet' && m.is_present) return false;
        if (filterMode === 'present' && !m.is_present) return false;

        // Section filter
        if (selectedSection !== 'all') {
          if (selectedSection === 'none') {
            if (m.section_name) return false;
          } else {
            if (m.section_name !== selectedSection) return false;
          }
        }

        // Search filter (display_name or member_number)
        if (q) {
          const nameMatch = m.display_name.toLowerCase().includes(q);
          const numMatch = m.member_number ? m.member_number.toLowerCase().includes(q) : false;
          if (!nameMatch && !numMatch) return false;
        }

        return true;
      })
      .sort((a, b) => a.sort_name.localeCompare(b.sort_name));
  }, [members, filterMode, selectedSection, search]);

  const handleToggleAttendance = async (member: EventRosterMember) => {
    if (isReadOnly || inFlightIds.has(member.member_id) || !orgId || !eventId) return;

    setErrorMessage(null);
    const targetMemberId = member.member_id;
    const nextPresent = !member.is_present;

    // Snapshot previous cache for rollback
    const prevData = queryClient.getQueryData<EventRosterResponse>(
      eventKeys.roster(orgId, eventId)
    );

    // Optimistic update
    setInFlightIds((prev) => new Set(prev).add(targetMemberId));
    queryClient.setQueryData<EventRosterResponse>(
      eventKeys.roster(orgId, eventId),
      (old) => {
        if (!old) return old;
        const updatedMembers = old.members.map((m) =>
          m.member_id === targetMemberId ? { ...m, is_present: nextPresent } : m
        );

        const delta = nextPresent ? 1 : -1;
        const inAudience = member.in_audience;

        return {
          ...old,
          event: {
            ...old.event,
            present_count: Math.max(0, old.event.present_count + delta),
            present_expected_count: inAudience
              ? Math.max(0, old.event.present_expected_count + delta)
              : old.event.present_expected_count,
            guest_count: !inAudience
              ? Math.max(0, old.event.guest_count + delta)
              : old.event.guest_count,
          },
          members: updatedMembers,
        };
      }
    );

    try {
      await attendanceMutation.mutateAsync({
        organizationId: orgId,
        eventId,
        memberIds: [targetMemberId],
        present: nextPresent,
        checkInMethod: 'tick',
      });
    } catch (err) {
      // Revert on error
      if (prevData) {
        queryClient.setQueryData(eventKeys.roster(orgId, eventId), prevData);
      }
      setErrorMessage(getEventErrorMessage(err));
    } finally {
      setInFlightIds((prev) => {
        const next = new Set(prev);
        next.delete(targetMemberId);
        return next;
      });
    }
  };

  if (isOrgLoading || isRosterLoading) {
    return (
      <div className="space-y-4 p-4">
        <Skeleton className="h-12 w-full" />
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (error || !event || !eventId) {
    return (
      <div className="p-4 space-y-4">
        <Link
          to={`/app/calendar/${eventId || ''}`}
          className="inline-flex items-center gap-1.5 text-small font-medium text-ink-secondary hover:text-ink"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Event
        </Link>
        <Alert variant="danger" title="Unable to load attendance roster">
          {error ? getEventErrorMessage(error) : 'Event not found.'}
        </Alert>
      </div>
    );
  }

  return (
    <div className="-mx-4 -my-6 min-h-[calc(100dvh-4rem)] bg-surface-muted sm:-mx-6 sm:-my-8">
      {/* Sticky Top Bar (Phone-Optimized) */}
      <div className="sticky top-0 z-20 border-b border-line bg-surface/95 backdrop-blur-sm px-4 py-3 shadow-xs">
        <div className="mx-auto max-w-2xl space-y-2">
          {/* Top row: Back link + Title */}
          <div className="flex items-center justify-between gap-2">
            <Link
              to={`/app/calendar/${eventId}`}
              className="inline-flex items-center gap-1 text-small font-medium text-ink-secondary hover:text-ink transition-colors"
            >
              <ArrowLeft className="h-4 w-4" />
              <span>Back</span>
            </Link>
            <span className="truncate text-small font-semibold text-ink">
              {event.title}
            </span>
          </div>

          {/* Counter: Present X of Y · Guests Z */}
          <div className="flex items-baseline justify-between border-t border-line/60 pt-2">
            <span className="text-h2 font-black tracking-tight text-ink">
              Present {event.present_count} of {event.expected_count} · Guests {event.guest_count}
            </span>
          </div>
        </div>
      </div>

      {/* Main Content Area */}
      <div className="mx-auto max-w-2xl p-4 space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        {isReadOnly && (
          <Alert variant="warning" title="Read-only mode">
            {isCancelled
              ? 'This event is cancelled. Attendance cannot be modified.'
              : isFuture
                ? 'Attendance can only be recorded on or after the day of the event.'
                : 'You do not have permission to record attendance for this event.'}
          </Alert>
        )}

        {/* Search Box */}
        <div className="relative">
          <Search className="absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search name or member number..."
            className="w-full rounded-control border border-line bg-surface py-2.5 pl-10 pr-4 text-body text-ink placeholder:text-ink-muted focus:border-primary focus:outline-hidden focus:ring-2 focus:ring-focus"
          />
        </div>

        {/* Filter Controls Row */}
        <div className="flex flex-wrap items-center justify-between gap-2">
          {/* Status Filter Chips: Not yet | Present | All */}
          <div className="inline-flex rounded-control border border-line bg-surface p-0.5">
            <button
              type="button"
              onClick={() => setFilterMode('not_yet')}
              className={`rounded-[calc(var(--radius-control)-2px)] px-3 py-1 text-small font-medium transition-colors ${
                filterMode === 'not_yet'
                  ? 'bg-primary text-white shadow-xs'
                  : 'text-ink-secondary hover:text-ink'
              }`}
            >
              Not yet
            </button>
            <button
              type="button"
              onClick={() => setFilterMode('present')}
              className={`rounded-[calc(var(--radius-control)-2px)] px-3 py-1 text-small font-medium transition-colors ${
                filterMode === 'present'
                  ? 'bg-primary text-white shadow-xs'
                  : 'text-ink-secondary hover:text-ink'
              }`}
            >
              Present
            </button>
            <button
              type="button"
              onClick={() => setFilterMode('all')}
              className={`rounded-[calc(var(--radius-control)-2px)] px-3 py-1 text-small font-medium transition-colors ${
                filterMode === 'all'
                  ? 'bg-primary text-white shadow-xs'
                  : 'text-ink-secondary hover:text-ink'
              }`}
            >
              All
            </button>
          </div>

          {/* Section Filter Dropdown */}
          <select
            value={selectedSection}
            onChange={(e) => setSelectedSection(e.target.value)}
            className="rounded-control border border-line bg-surface px-3 py-1.5 text-small text-ink focus:border-primary focus:outline-hidden focus:ring-2 focus:ring-focus"
          >
            <option value="all">All sections</option>
            {sectionOptions.sections.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
            {sectionOptions.hasNoSection && (
              <option value="none">No section</option>
            )}
          </select>
        </div>

        {/* Member Rows */}
        <div className="divide-y divide-line rounded-card border border-line bg-surface shadow-xs">
          {filteredMembers.length === 0 ? (
            <div className="p-8 text-center text-small text-ink-muted">
              No members match the current search and filter.
            </div>
          ) : (
            filteredMembers.map((member) => {
              const inFlight = inFlightIds.has(member.member_id);
              const placementText = [member.section_name, member.placement_name]
                .filter(Boolean)
                .join(' · ');

              return (
                <div
                  key={member.member_id}
                  onClick={() => !isReadOnly && handleToggleAttendance(member)}
                  className={`flex min-h-[56px] items-center justify-between gap-3 px-4 py-3 transition-colors select-none ${
                    isReadOnly
                      ? 'cursor-default'
                      : inFlight
                        ? 'cursor-wait opacity-60'
                        : 'cursor-pointer hover:bg-surface-muted active:bg-surface-muted/80'
                  } ${member.is_present ? 'bg-success-50/20' : ''}`}
                >
                  {/* Left: Name, Member Number, Section/Placement, Guest Badge */}
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="text-body font-semibold text-ink">
                        {member.display_name}
                      </span>
                      {!member.in_audience && (
                        <Badge variant="neutral" className="text-[11px] px-1.5 py-0">
                          Guest
                        </Badge>
                      )}
                    </div>

                    <p className="mt-0.5 text-small text-ink-muted truncate">
                      {member.member_number ? (
                        <span className="font-mono font-medium text-ink-secondary">
                          {member.member_number}
                        </span>
                      ) : (
                        <span>No number</span>
                      )}
                      {placementText && <span> · {placementText}</span>}
                    </p>
                  </div>

                  {/* Right: Large Checkbox Icon (min 44px tap target) */}
                  <div className="flex h-11 w-11 shrink-0 items-center justify-center">
                    {inFlight ? (
                      <Loader2 className="h-6 w-6 animate-spin text-primary" />
                    ) : member.is_present ? (
                      <CheckCircle2 className="h-7 w-7 text-success-600 fill-success-100" />
                    ) : (
                      <Circle className="h-7 w-7 text-ink-muted/50 hover:text-ink-muted" />
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}

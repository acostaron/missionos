import { Link } from 'react-router-dom';
import { CalendarCheck, ChevronRight } from 'lucide-react';
import { Badge, Card } from '../../../components/ui';
import { useEventsList } from '../queries';
import {
  EVENT_STATUS_LABELS,
  EVENT_TYPE_LABELS,
  getEventStatusBadgeVariant,
  getEventTypeBadgeVariant,
} from '../labels';
import {
  addDaysToDateStr,
  formatNyDateShort,
  formatNyTimeRange,
  getTodayNyDate,
} from '../../../lib/ny-time';

interface EventsGreetingCardProps {
  organizationId: string;
}

export function EventsGreetingCard({ organizationId }: EventsGreetingCardProps) {
  const today = getTodayNyDate();
  const to = addDaysToDateStr(today, 30);

  const { data } = useEventsList(organizationId, today, to);
  const greeterEvents = data?.events.filter((e) => e.is_greeter && e.event_status !== 'cancelled') ?? [];

  if (greeterEvents.length === 0) {
    return null;
  }

  return (
    <Card padding="comfortable" className="border-primary/20 bg-primary/5">
      <div className="flex items-center gap-2">
        <CalendarCheck className="h-5 w-5 text-primary" />
        <h2 className="text-h3 font-semibold text-ink">Events you're greeting</h2>
      </div>
      <p className="mt-1 text-small text-ink-muted">
        You are assigned to greet attendees and take attendance for these upcoming events.
      </p>

      <div className="mt-4 divide-y divide-line rounded-control border border-line bg-surface shadow-xs">
        {greeterEvents.map((evt) => (
          <Link
            key={evt.id}
            to={`/app/calendar/${evt.id}/attendance`}
            className="flex items-center justify-between p-3.5 transition-colors hover:bg-surface-muted"
          >
            <div className="min-w-0 pr-3 space-y-1">
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-body font-semibold text-ink truncate">
                  {evt.title}
                </span>
                <Badge variant={getEventTypeBadgeVariant(evt.event_type)}>
                  {EVENT_TYPE_LABELS[evt.event_type]}
                </Badge>
                <Badge variant={getEventStatusBadgeVariant(evt.event_status)}>
                  {EVENT_STATUS_LABELS[evt.event_status]}
                </Badge>
              </div>

              <div className="flex flex-wrap items-center gap-x-3 text-caption text-ink-muted">
                <span>{formatNyDateShort(evt.starts_at)}</span>
                <span>·</span>
                <span>{formatNyTimeRange(evt.starts_at, evt.ends_at)}</span>
                {evt.location_text && (
                  <>
                    <span>·</span>
                    <span className="truncate">{evt.location_text}</span>
                  </>
                )}
              </div>
            </div>

            <div className="flex items-center gap-1 text-small font-medium text-primary shrink-0">
              <span className="hidden sm:inline">Take attendance</span>
              <ChevronRight className="h-4 w-4" />
            </div>
          </Link>
        ))}
      </div>
    </Card>
  );
}

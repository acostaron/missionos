import { useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import {
  Calendar,
  Clock,
  MapPin,
  Users,
  CheckCircle2,
  UserCheck,
  QrCode,
  Edit,
  Trash2,
  RotateCcw,
  BookOpen,
  GraduationCap,
} from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  Card,
  Skeleton,
} from '../components/ui';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import {
  useEvent,
  usePostEventAttendanceToFormation,
  useSetEventGreeter,
  useSetEventStatus,
} from '../features/events/queries';
import {
  EVENT_STATUS_LABELS,
  EVENT_TYPE_LABELS,
  getEventStatusBadgeVariant,
  getEventTypeBadgeVariant,
} from '../features/events/labels';
import { EventFormModal } from '../features/events/components/EventFormModal';
import { CancelEventModal } from '../features/events/components/CancelEventModal';
import { AddGreeterModal } from '../features/events/components/AddGreeterModal';
import { getEventErrorMessage } from '../features/events/error-message';
import {
  formatNyDateLong,
  formatNyDateShort,
  formatNyTimeRange,
  getTodayNyDate,
  isoToNyLocal,
} from '../lib/ny-time';

export default function EventPage() {
  const { eventId } = useParams<{ eventId: string }>();
  const navigate = useNavigate();
  const { organization, isLoading: isOrgLoading } = useCurrentOrganization();
  const { hasPermission } = usePermissions();
  const orgId = organization?.id ?? null;

  const { data: event, isLoading: isEventLoading, error } = useEvent(orgId, eventId ?? null);

  const statusMutation = useSetEventStatus();
  const greeterMutation = useSetEventGreeter();
  const postFormationMutation = usePostEventAttendanceToFormation();

  const [isEditModalOpen, setIsEditModalOpen] = useState(false);
  const [isCancelModalOpen, setIsCancelModalOpen] = useState(false);
  const [isAddGreeterOpen, setIsAddGreeterOpen] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [formationPostResult, setFormationPostResult] = useState<{
    posted_count: number;
    already_recorded_count: number;
    program_already_completed_count: number;
    attempts_opened_count: number;
  } | null>(null);

  const [isConfirmingFormationPost, setIsConfirmingFormationPost] = useState(false);

  if (isOrgLoading || isEventLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-10 w-48" />
        <Skeleton className="h-64" />
        <Skeleton className="h-48" />
      </div>
    );
  }

  if (error || !event || !orgId || !eventId) {
    return (
      <div className="space-y-6">
        <Alert variant="danger" title="Event not found">
          {error ? getEventErrorMessage(error) : 'The requested event could not be found.'}
        </Alert>
      </div>
    );
  }

  const todayNy = getTodayNyDate();
  const eventDateNy = isoToNyLocal(event.starts_at).date;
  const isFuture = eventDateNy > todayNy;
  const isCancelled = event.event_status === 'cancelled';
  const canRecordAttendance = event.can_record && !isCancelled && !isFuture;

  // Attendance rate
  const pct =
    event.expected_count > 0
      ? Math.round((event.present_expected_count / event.expected_count) * 100)
      : 0;

  const handleStatusChange = async (status: 'scheduled' | 'held', reason?: string) => {
    setActionError(null);
    try {
      await statusMutation.mutateAsync({
        organizationId: orgId,
        eventId,
        status,
        reason,
      });
    } catch (err) {
      setActionError(getEventErrorMessage(err));
    }
  };

  const handleRemoveGreeter = async (memberId: string) => {
    setActionError(null);
    try {
      await greeterMutation.mutateAsync({
        organizationId: orgId,
        eventId,
        memberId,
        assign: false,
      });
    } catch (err) {
      setActionError(getEventErrorMessage(err));
    }
  };

  const handlePostToFormation = async () => {
    setActionError(null);
    try {
      const result = await postFormationMutation.mutateAsync({
        organizationId: orgId,
        eventId,
      });
      setFormationPostResult({
        posted_count: result.posted_count,
        already_recorded_count: result.already_recorded_count,
        program_already_completed_count: result.program_already_completed_count,
        attempts_opened_count: result.attempts_opened_count,
      });
      setIsConfirmingFormationPost(false);
    } catch (err) {
      setActionError(getEventErrorMessage(err));
      setIsConfirmingFormationPost(false);
    }
  };

  const canPostFormation =
    event.event_type === 'formation_talk' &&
    event.event_status === 'held' &&
    event.can_manage &&
    hasPermission(Permissions.FormationRecordsRecord);

  return (
    <div className="space-y-6">
      {actionError && (
        <Alert variant="danger">
          {actionError}
        </Alert>
      )}

      {/* Main Event Header Card */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="space-y-2">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant={getEventTypeBadgeVariant(event.event_type)}>
                {EVENT_TYPE_LABELS[event.event_type]}
              </Badge>
              <Badge variant={getEventStatusBadgeVariant(event.event_status)}>
                {EVENT_STATUS_LABELS[event.event_status]}
              </Badge>
              {event.is_greeter && (
                <Badge variant="info">
                  You are a greeter
                </Badge>
              )}
            </div>

            <h1 className="text-h1 font-bold text-ink">{event.title}</h1>

            {event.is_program_session && event.program_run_id && (
              <div className="flex items-center gap-2 text-small font-medium text-primary">
                <GraduationCap className="h-4 w-4" />
                <Link to={`/app/programs/${event.program_run_id}`} className="hover:underline">
                  Program: {event.program_title} · Session {event.session_number} of {event.session_count}
                </Link>
              </div>
            )}

            {event.event_type === 'formation_talk' && event.formation_program_name && (
              <div className="flex items-center gap-2 text-small font-medium text-success-700">
                <BookOpen className="h-4 w-4" />
                <span>
                  {event.formation_program_name} · {event.formation_talk_title}
                </span>
              </div>
            )}
          </div>

          {/* Manage Actions */}
          {event.can_manage && (
            <div className="flex flex-wrap items-center gap-2">
              {event.event_status !== 'cancelled' && (
                event.is_program_session && event.program_run_id ? (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => navigate(`/app/programs/${event.program_run_id}`)}
                  >
                    Change on program page
                  </Button>
                ) : (
                  <Button
                    variant="outline"
                    size="sm"
                    icon={<Edit className="h-3.5 w-3.5" />}
                    onClick={() => setIsEditModalOpen(true)}
                  >
                    Edit
                  </Button>
                )
              )}

              {event.event_status === 'scheduled' && (
                <Button
                  variant="outline"
                  size="sm"
                  icon={<CheckCircle2 className="h-3.5 w-3.5 text-success-600" />}
                  loading={statusMutation.isPending}
                  onClick={() => handleStatusChange('held')}
                >
                  Mark as held
                </Button>
              )}

              {event.event_status === 'held' && (
                <Button
                  variant="outline"
                  size="sm"
                  icon={<RotateCcw className="h-3.5 w-3.5 text-ink-muted" />}
                  loading={statusMutation.isPending}
                  onClick={() => handleStatusChange('scheduled')}
                >
                  Back to scheduled
                </Button>
              )}

              {event.event_status !== 'cancelled' && (
                <Button
                  variant="outline"
                  size="sm"
                  className="text-danger-600 hover:text-danger-700"
                  icon={<Trash2 className="h-3.5 w-3.5" />}
                  onClick={() => setIsCancelModalOpen(true)}
                >
                  Cancel event
                </Button>
              )}

              {event.event_status === 'cancelled' && (
                <Button
                  variant="outline"
                  size="sm"
                  icon={<RotateCcw className="h-3.5 w-3.5" />}
                  loading={statusMutation.isPending}
                  onClick={() => handleStatusChange('scheduled')}
                >
                  Restore event
                </Button>
              )}
            </div>
          )}
        </div>

        {/* Cancellation Notice Banner */}
        {event.event_status === 'cancelled' && (
          <Alert variant="danger" title="This event is cancelled">
            {event.cancel_reason
              ? `Reason: ${event.cancel_reason}`
              : 'This event was cancelled.'}
          </Alert>
        )}

        {/* Date, Time, Location, Audience */}
        <div className="grid grid-cols-1 gap-4 border-t border-line pt-4 sm:grid-cols-2 lg:grid-cols-4">
          <div className="flex items-start gap-2.5">
            <Calendar className="mt-0.5 h-4 w-4 text-ink-muted" />
            <div>
              <p className="text-caption font-medium text-ink-muted">Date</p>
              <p className="text-body font-medium text-ink">
                {formatNyDateLong(event.starts_at)}
              </p>
            </div>
          </div>

          <div className="flex items-start gap-2.5">
            <Clock className="mt-0.5 h-4 w-4 text-ink-muted" />
            <div>
              <p className="text-caption font-medium text-ink-muted">Time</p>
              <p className="text-body font-medium text-ink">
                {formatNyTimeRange(event.starts_at, event.ends_at)}
              </p>
            </div>
          </div>

          <div className="flex items-start gap-2.5">
            <MapPin className="mt-0.5 h-4 w-4 text-ink-muted" />
            <div>
              <p className="text-caption font-medium text-ink-muted">Location</p>
              <p className="text-body font-medium text-ink">
                {event.location_text || 'None specified'}
              </p>
            </div>
          </div>

          <div className="flex items-start gap-2.5">
            <Users className="mt-0.5 h-4 w-4 text-ink-muted" />
            <div>
              <p className="text-caption font-medium text-ink-muted">Audience</p>
              <p className="text-body font-medium text-ink">
                {event.audience_type === 'chapter'
                  ? (event.audience_name.toLowerCase().startsWith('chapter ')
                      ? event.audience_name
                      : `Chapter ${event.audience_name}`)
                  : event.audience_type === 'section'
                    ? (event.audience_name.toLowerCase().startsWith('section ')
                        ? event.audience_name
                        : `Section ${event.audience_name}`)
                    : event.audience_name}
              </p>
            </div>
          </div>
        </div>

        {/* Description */}
        {event.description && (
          <div className="border-t border-line pt-4">
            <p className="text-caption font-medium text-ink-muted">Description</p>
            <p className="mt-1 whitespace-pre-line text-body text-ink">
              {event.description}
            </p>
          </div>
        )}
      </Card>

      {/* Grid: Attendance & Greeters */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Attendance Card */}
        <Card padding="comfortable" className="space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-h3 font-semibold text-ink">Attendance</h2>
            {canRecordAttendance && (
              <div className="flex flex-wrap justify-end gap-2">
                {!event.is_program_session && (
                  <Button
                    variant="outline"
                    size="sm"
                    icon={<QrCode className="h-4 w-4" />}
                    onClick={() => navigate(`/app/calendar/${event.id}/scan`)}
                  >
                    Scan QR
                  </Button>
                )}
                <Button
                  variant="primary"
                  size="sm"
                  icon={<UserCheck className="h-4 w-4" />}
                  onClick={() => navigate(`/app/calendar/${event.id}/attendance`)}
                >
                  Take attendance
                </Button>
              </div>
            )}
          </div>

          {event.is_program_session ? (
            <div className="rounded-control bg-surface-muted p-4">
              <p className="text-caption font-medium text-ink-muted">Session Attendance</p>
              <p className="mt-1 text-h2 font-bold text-ink">
                Participants present {event.present_count} of {event.expected_count} · Team {event.team_count}
              </p>
            </div>
          ) : (
            <div className="rounded-control bg-surface-muted p-4">
              <p className="text-caption font-medium text-ink-muted">Present Attendees</p>
              <p className="mt-1 text-h2 font-bold text-ink">
                Present {event.present_expected_count} of {event.expected_count} expected{' '}
                <span className="text-h3 font-medium text-ink-muted">({pct}%)</span>
              </p>
              {event.guest_count > 0 && (
                <p className="mt-1 text-small font-medium text-ink-secondary">
                  +{event.guest_count} guest{event.guest_count === 1 ? '' : 's'} checked in
                </p>
              )}
            </div>
          )}

          {!canRecordAttendance && (
            <p className="text-small text-ink-muted">
              {isCancelled
                ? 'Attendance cannot be recorded for a cancelled event.'
                : isFuture
                  ? 'Attendance can be recorded on or after the day of the event.'
                  : !event.can_record
                    ? 'You do not have permission to record attendance for this event.'
                    : ''}
            </p>
          )}
        </Card>

        {/* Greeters Card (Only for users with can_manage) */}
        {event.can_manage && (
          <Card padding="comfortable" className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-h3 font-semibold text-ink">Greeters</h2>
                <p className="text-caption text-ink-muted">
                  Leaders assigned to greet attendees and record attendance.
                </p>
              </div>
              {event.event_status !== 'cancelled' && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setIsAddGreeterOpen(true)}
                >
                  Add greeter
                </Button>
              )}
            </div>

            {event.greeters.length === 0 ? (
              <p className="py-4 text-center text-small text-ink-muted">
                No greeters assigned yet.
              </p>
            ) : (
              <div className="divide-y divide-line rounded-control border border-line bg-surface">
                {event.greeters.map((g) => (
                  <div
                    key={g.member_id}
                    className="flex items-center justify-between p-3"
                  >
                    <div>
                      <p className="text-body font-medium text-ink">
                        {g.display_name}
                      </p>
                      <p className="text-caption text-ink-muted">
                        {g.member_number || 'No member number'}
                      </p>
                    </div>
                    {event.event_status !== 'cancelled' && (
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-danger-600 hover:text-danger-700"
                        loading={greeterMutation.isPending}
                        onClick={() => handleRemoveGreeter(g.member_id)}
                      >
                        Remove
                      </Button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>
        )}
      </div>

      {/* Formation Posting Section for Course Talk */}
      {canPostFormation && (
        <Card padding="comfortable" className="space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 className="text-h3 font-semibold text-ink">Formation Records</h2>
              <p className="text-small text-ink-muted">
                Post attendance records for this talk to each attendee's active formation track.
              </p>
              {event.formation_posted_at && (
                <p className="mt-1 text-caption text-success-700 font-medium">
                  Posted on {formatNyDateShort(event.formation_posted_at)}
                </p>
              )}
            </div>

            <Button
              variant="secondary"
              loading={postFormationMutation.isPending}
              onClick={() => setIsConfirmingFormationPost(true)}
            >
              Post attendance to formation records
            </Button>
          </div>

          {/* Posting Confirmation Dialog / Box */}
          {isConfirmingFormationPost && (
            <div className="rounded-card border border-warning-200 bg-warning-50 p-4 space-y-3">
              <p className="text-small font-medium text-warning-900">
                Are you sure you want to post attendance to formation records for all attendees?
              </p>
              <p className="text-caption text-warning-800">
                This will record talk completion for active attendees who do not already have it.
              </p>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="primary"
                  loading={postFormationMutation.isPending}
                  onClick={handlePostToFormation}
                >
                  Yes, post attendance
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => setIsConfirmingFormationPost(false)}
                >
                  Cancel
                </Button>
              </div>
            </div>
          )}

          {/* Results Summary if just posted */}
          {formationPostResult && (
            <div className="rounded-control bg-surface-muted p-4 space-y-1 text-small">
              <p className="font-semibold text-ink">Formation posting completed:</p>
              <p className="text-ink-secondary">
                • {formationPostResult.posted_count} record(s) posted
              </p>
              <p className="text-ink-secondary">
                • {formationPostResult.already_recorded_count} already had records for this talk
              </p>
              <p className="text-ink-secondary">
                • {formationPostResult.program_already_completed_count} already completed this program
              </p>
              <p className="text-ink-secondary">
                • {formationPostResult.attempts_opened_count} new program attempts opened
              </p>
            </div>
          )}
        </Card>
      )}

      {/* Modals */}
      {event.can_manage && (
        <>
          <EventFormModal
            open={isEditModalOpen}
            onClose={() => setIsEditModalOpen(false)}
            organizationId={orgId}
            event={event}
          />

          <CancelEventModal
            open={isCancelModalOpen}
            onClose={() => setIsCancelModalOpen(false)}
            organizationId={orgId}
            eventId={event.id}
            eventTitle={event.title}
          />

          <AddGreeterModal
            open={isAddGreeterOpen}
            onClose={() => setIsAddGreeterOpen(false)}
            organizationId={orgId}
            eventId={event.id}
            currentGreeters={event.greeters}
          />
        </>
      )}
    </div>
  );
}

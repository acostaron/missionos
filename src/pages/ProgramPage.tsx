import { useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import {
  ArrowLeft,
  Calendar,
  Check,
  Edit,
  Plus,
  Trash2,
  UserCheck,
  CheckCircle2,
  Play,
  RotateCcw,
} from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  Card,
  Skeleton,
} from '../components/ui';
import { useOrganizationContext } from '../hooks/use-organization-context';
import {
  useProgramRun,
  useSetProgramParticipantStatus,
  useSetProgramRunStatus,
} from '../features/programs/queries';
import {
  PROGRAM_CODE_LABELS,
  PROGRAM_STATUS_LABELS,
  getProgramCodeBadgeVariant,
  getProgramStatusBadgeVariant,
} from '../features/programs/labels';
import { EditProgramModal } from '../features/programs/components/EditProgramModal';
import { CancelProgramModal } from '../features/programs/components/CancelProgramModal';
import { ScheduleSessionModal } from '../features/programs/components/ScheduleSessionModal';
import { AddParticipantModal } from '../features/programs/components/AddParticipantModal';
import { EditParticipantModal } from '../features/programs/components/EditParticipantModal';
import { formatNyDateLong, formatNyTimeRange } from '../lib/ny-time';
import { getEventErrorMessage } from '../features/events/error-message';
import type { EventSummary } from '../features/events/types';
import type { ProgramParticipant } from '../features/programs/types';

export default function ProgramPage() {
  const { runId } = useParams<{ runId: string }>();
  const navigate = useNavigate();
  const { activeOrganization } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;

  const { data: detail, isLoading, error } = useProgramRun(orgId, runId ?? null);
  const setRunStatusMutation = useSetProgramRunStatus();
  const setParticipantStatusMutation = useSetProgramParticipantStatus();

  // Modals state
  const [isEditModalOpen, setIsEditModalOpen] = useState(false);
  const [isCancelModalOpen, setIsCancelModalOpen] = useState(false);
  const [sessionModalState, setSessionModalState] = useState<{
    open: boolean;
    sessionNumber: number;
    session: EventSummary | null;
  }>({
    open: false,
    sessionNumber: 1,
    session: null,
  });
  const [isAddParticipantOpen, setIsAddParticipantOpen] = useState(false);
  const [editingParticipant, setEditingParticipant] = useState<ProgramParticipant | null>(null);

  const [actionError, setActionError] = useState<string | null>(null);

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="h-8 w-40">
          <Skeleton className="h-full w-full" />
        </div>
        <Skeleton className="h-44" />
        <Skeleton className="h-72" />
      </div>
    );
  }

  if (error || !detail) {
    return (
      <div className="space-y-4">
        <Button
          variant="outline"
          size="sm"
          icon={<ArrowLeft className="h-4 w-4" />}
          onClick={() => navigate('/app/programs')}
        >
          Back to programs
        </Button>
        <Alert variant="danger">
          {error ? getEventErrorMessage(error) : 'Program not found.'}
        </Alert>
      </div>
    );
  }

  const { run, sessions, participants } = detail;
  const canManage = run.can_manage;
  const allSessionsScheduled = run.sessions_scheduled === run.session_count;

  const handleStatusChange = async (newStatus: 'running' | 'completed' | 'planned') => {
    setActionError(null);
    try {
      await setRunStatusMutation.mutateAsync({
        organizationId: orgId!,
        runId: run.id,
        status: newStatus,
      });
    } catch (err) {
      setActionError(getEventErrorMessage(err));
    }
  };

  const handleParticipantStatusToggle = async (
    participantId: string,
    newStatus: 'registered' | 'withdrawn'
  ) => {
    setActionError(null);
    try {
      await setParticipantStatusMutation.mutateAsync({
        organizationId: orgId!,
        participantId,
        status: newStatus,
      });
    } catch (err) {
      setActionError(getEventErrorMessage(err));
    }
  };

  // Build rows for 1..session_count
  const sessionRows: Array<{
    number: number;
    session: EventSummary | null;
  }> = [];

  for (let i = 1; i <= run.session_count; i++) {
    const s = sessions.find((item) => item.session_number === i) || null;
    sessionRows.push({ number: i, session: s });
  }

  return (
    <div className="space-y-6">
      {/* Top back navigation */}
      <div className="flex items-center gap-2">
        <Link
          to="/app/programs"
          className="inline-flex items-center gap-1.5 text-small font-medium text-ink-muted hover:text-ink transition-colors"
        >
          <ArrowLeft className="h-4 w-4" />
          <span>Programs</span>
        </Link>
      </div>

      {actionError && (
        <Alert variant="danger">
          {actionError}
        </Alert>
      )}

      {/* Program Header Card */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="space-y-2">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant={getProgramCodeBadgeVariant(run.program_code)}>
                {PROGRAM_CODE_LABELS[run.program_code]}
              </Badge>
              <Badge variant={getProgramStatusBadgeVariant(run.run_status)}>
                {PROGRAM_STATUS_LABELS[run.run_status]}
              </Badge>
            </div>

            <h1 className="text-h1 font-bold text-ink">{run.title}</h1>

            <div className="text-small text-ink-secondary space-y-1">
              {run.chapter_name && (
                <p>
                  <span className="font-semibold text-ink">Chapter:</span> {run.chapter_name}
                </p>
              )}
              {run.sections.length > 0 && (
                <p>
                  <span className="font-semibold text-ink">
                    {run.sections.length > 1 ? 'Sections:' : 'Section:'}
                  </span>{' '}
                  {run.sections.map((s) => s.name).join(', ')}
                </p>
              )}
              {!run.chapter_name && run.sections.length === 0 && run.audience_name && (
                <p>
                  <span className="font-semibold text-ink">Audience:</span> {run.audience_name}
                </p>
              )}
            </div>

            {run.description && (
              <p className="mt-2 whitespace-pre-line text-small text-ink">
                {run.description}
              </p>
            )}
          </div>

          {/* Manage Actions */}
          {canManage && (
            <div className="flex flex-wrap items-center gap-2">
              {run.run_status !== 'cancelled' && (
                <Button
                  variant="outline"
                  size="sm"
                  icon={<Edit className="h-3.5 w-3.5" />}
                  onClick={() => setIsEditModalOpen(true)}
                >
                  Edit
                </Button>
              )}

              {run.run_status === 'planned' && (
                <Button
                  variant="outline"
                  size="sm"
                  icon={<Play className="h-3.5 w-3.5 text-info-600" />}
                  loading={setRunStatusMutation.isPending}
                  onClick={() => handleStatusChange('running')}
                >
                  Mark running
                </Button>
              )}

              {run.run_status === 'running' && (
                <Button
                  variant="outline"
                  size="sm"
                  icon={<CheckCircle2 className="h-3.5 w-3.5 text-success-600" />}
                  loading={setRunStatusMutation.isPending}
                  onClick={() => handleStatusChange('completed')}
                >
                  Mark completed
                </Button>
              )}

              {run.run_status === 'completed' && (
                <Button
                  variant="outline"
                  size="sm"
                  icon={<RotateCcw className="h-3.5 w-3.5 text-ink-muted" />}
                  loading={setRunStatusMutation.isPending}
                  onClick={() => handleStatusChange('running')}
                >
                  Reopen
                </Button>
              )}

              {run.run_status !== 'cancelled' && (
                <Button
                  variant="outline"
                  size="sm"
                  className="text-danger-600 hover:text-danger-700"
                  icon={<Trash2 className="h-3.5 w-3.5" />}
                  onClick={() => setIsCancelModalOpen(true)}
                >
                  Cancel program
                </Button>
              )}
            </div>
          )}
        </div>

        {/* Cancellation Notice Banner */}
        {run.run_status === 'cancelled' && (
          <Alert variant="danger" title="This program is cancelled">
            {run.cancel_reason
              ? `Reason: ${run.cancel_reason}`
              : 'This program was cancelled.'}
          </Alert>
        )}

        {/* Graduation Summary Line */}
        <div className="border-t border-line/60 pt-3">
          {allSessionsScheduled ? (
            <p className="text-small font-semibold text-ink">
              🎓 {run.graduate_count} graduate{run.graduate_count === 1 ? '' : 's'} (attended all {run.session_count} sessions)
            </p>
          ) : (
            <p className="text-small text-ink-muted">
              Graduation is counted once all {run.session_count} sessions are scheduled.
            </p>
          )}
        </div>
      </Card>

      {/* SESSIONS CARD */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-h3 font-semibold text-ink">Sessions</h2>
            <p className="text-caption text-ink-muted">
              {run.sessions_scheduled} of {run.session_count} scheduled
            </p>
          </div>
        </div>

        <div className="divide-y divide-line rounded-control border border-line bg-surface">
          {sessionRows.map(({ number, session }) => {
            if (session) {
              return (
                <div
                  key={session.id}
                  className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between transition-colors hover:bg-surface-muted/40"
                >
                  <div className="space-y-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-body font-semibold text-ink">
                        Session {number}: {session.title}
                      </span>
                    </div>

                    <p className="text-small text-ink-secondary">
                      {formatNyDateLong(session.starts_at)} · {formatNyTimeRange(session.starts_at, session.ends_at)}
                      {session.location_text && <span> · {session.location_text}</span>}
                    </p>

                    <p className="text-caption font-medium text-ink-muted">
                      Present {session.present_count} of {session.expected_count} · Team {session.team_count}
                    </p>
                  </div>

                  <div className="flex flex-wrap items-center gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => navigate(`/app/calendar/${session.id}`)}
                    >
                      View event
                    </Button>

                    <Button
                      variant="primary"
                      size="sm"
                      icon={<UserCheck className="h-3.5 w-3.5" />}
                      onClick={() => navigate(`/app/calendar/${session.id}/attendance`)}
                    >
                      Take attendance
                    </Button>

                    {canManage && session.event_status !== 'cancelled' && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() =>
                          setSessionModalState({
                            open: true,
                            sessionNumber: number,
                            session,
                          })
                        }
                      >
                        Change
                      </Button>
                    )}
                  </div>
                </div>
              );
            }

            // Unscheduled Session Row
            return (
              <div
                key={number}
                className="flex items-center justify-between p-4 bg-surface-muted/20"
              >
                <div>
                  <p className="text-body font-medium text-ink-muted">
                    Session {number} <span className="text-caption">(Unscheduled)</span>
                  </p>
                </div>

                {canManage && run.run_status !== 'cancelled' && (
                  <Button
                    variant="outline"
                    size="sm"
                    icon={<Calendar className="h-3.5 w-3.5" />}
                    onClick={() =>
                      setSessionModalState({
                        open: true,
                        sessionNumber: number,
                        session: null,
                      })
                    }
                  >
                    Schedule
                  </Button>
                )}
              </div>
            );
          })}
        </div>
      </Card>

      {/* PARTICIPANTS CARD */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="text-h3 font-semibold text-ink">Participants</h2>
            <p className="text-caption text-ink-muted">
              {participants.length} registered participant{participants.length === 1 ? '' : 's'}
            </p>
          </div>

          {canManage && run.run_status !== 'cancelled' && (
            <Button
              variant="primary"
              size="sm"
              icon={<Plus className="h-4 w-4" />}
              onClick={() => setIsAddParticipantOpen(true)}
            >
              Add participant
            </Button>
          )}
        </div>

        {participants.length === 0 ? (
          <p className="py-8 text-center text-small text-ink-muted">
            No participants registered yet. Click "Add participant" to register members or new people.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-control border border-line bg-surface">
            <table className="w-full text-left text-small">
              <thead className="border-b border-line bg-surface-muted text-caption font-semibold text-ink-secondary">
                <tr>
                  <th className="p-3">Participant</th>
                  {canManage && <th className="p-3">Contact</th>}
                  <th className="p-3">Invited by</th>
                  {/* Session tick columns */}
                  {Array.from({ length: run.session_count }, (_, idx) => idx + 1).map((num) => (
                    <th key={num} className="p-3 text-center">
                      S{num}
                    </th>
                  ))}
                  <th className="p-3 text-center">Attended</th>
                  <th className="p-3">Status</th>
                  {canManage && <th className="p-3 text-right">Actions</th>}
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {participants.map((p) => {
                  const isWithdrawn = p.participant_status === 'withdrawn';

                  return (
                    <tr
                      key={p.participant_id}
                      className={`transition-colors ${
                        isWithdrawn ? 'bg-surface-muted/60 opacity-60' : 'hover:bg-surface-muted/30'
                      }`}
                    >
                      <td className="p-3 font-medium text-ink">
                        <div className="flex items-center gap-2">
                          <span>{p.name}</span>
                          {p.is_member ? (
                            <Badge variant="info">
                              Member {p.member_number ? `· ${p.member_number}` : ''}
                            </Badge>
                          ) : (
                            <Badge variant="neutral">New</Badge>
                          )}
                        </div>
                      </td>

                      {canManage && (
                        <td className="p-3 text-caption text-ink-secondary">
                          {p.phone && <div>{p.phone}</div>}
                          {p.email && <div>{p.email}</div>}
                          {!p.phone && !p.email && <span className="text-ink-muted">—</span>}
                        </td>
                      )}

                      <td className="p-3 text-ink-secondary">
                        {p.invited_by_name || '—'}
                      </td>

                      {/* Per-session attendance columns */}
                      {Array.from({ length: run.session_count }, (_, idx) => idx + 1).map((sNum) => {
                        const attended = p.attended_sessions.includes(sNum);
                        return (
                          <td key={sNum} className="p-3 text-center font-bold">
                            {attended ? (
                              <Check className="mx-auto h-4 w-4 text-success-600 stroke-[3]" />
                            ) : (
                              <span className="text-ink-muted/40">·</span>
                            )}
                          </td>
                        );
                      })}

                      <td className="p-3 text-center font-medium text-ink">
                        {p.attended_count} of {run.session_count}
                      </td>

                      <td className="p-3">
                        {isWithdrawn ? (
                          <Badge variant="neutral">Withdrawn</Badge>
                        ) : p.graduated ? (
                          <Badge variant="success">Graduate 🎓</Badge>
                        ) : (
                          <span className="text-caption text-ink-muted">Registered</span>
                        )}
                      </td>

                      {canManage && (
                        <td className="p-3 text-right">
                          <div className="inline-flex items-center gap-1.5 justify-end">
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={() => setEditingParticipant(p)}
                            >
                              Edit
                            </Button>

                            {isWithdrawn ? (
                              <Button
                                size="sm"
                                variant="ghost"
                                className="text-primary"
                                loading={setParticipantStatusMutation.isPending}
                                onClick={() =>
                                  handleParticipantStatusToggle(p.participant_id, 'registered')
                                }
                              >
                                Restore
                              </Button>
                            ) : (
                              <Button
                                size="sm"
                                variant="ghost"
                                className="text-danger-600 hover:text-danger-700"
                                loading={setParticipantStatusMutation.isPending}
                                onClick={() =>
                                  handleParticipantStatusToggle(p.participant_id, 'withdrawn')
                                }
                              >
                                Withdraw
                              </Button>
                            )}
                          </div>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {/* Modals */}
      {canManage && orgId && (
        <>
          <EditProgramModal
            open={isEditModalOpen}
            onClose={() => setIsEditModalOpen(false)}
            organizationId={orgId}
            run={run}
          />

          <CancelProgramModal
            open={isCancelModalOpen}
            onClose={() => setIsCancelModalOpen(false)}
            organizationId={orgId}
            runId={run.id}
            programTitle={run.title}
          />

          <ScheduleSessionModal
            open={sessionModalState.open}
            onClose={() =>
              setSessionModalState((prev) => ({ ...prev, open: false, session: null }))
            }
            organizationId={orgId}
            runId={run.id}
            sessionNumber={sessionModalState.sessionNumber}
            session={sessionModalState.session}
          />

          <AddParticipantModal
            open={isAddParticipantOpen}
            onClose={() => setIsAddParticipantOpen(false)}
            organizationId={orgId}
            runId={run.id}
          />

          <EditParticipantModal
            open={!!editingParticipant}
            onClose={() => setEditingParticipant(null)}
            organizationId={orgId}
            participant={editingParticipant}
          />
        </>
      )}
    </div>
  );
}

import { useState } from 'react';
import { Mic, Plus, Users } from 'lucide-react';
import { Alert, Badge, Button, Card, Skeleton } from '../../../components/ui';
import { getEventErrorMessage } from '../../events/error-message';
import { useActivityTeam, useRemoveActivityServiceAssignment, useRemoveActivitySpeaker } from '../queries';
import { AssignmentModal, type SessionOption } from './AssignmentModal';
import {
  SPEAKER_ROLE_LABELS,
  type ActivityServiceAssignment,
  type ActivitySpeaker,
  type ActivityTarget,
} from '../types';

interface ActivityTeamCardsProps {
  organizationId: string;
  target: ActivityTarget;
  /** Program mode: sessions so entries can be attached to a specific session. */
  sessionOptions?: SessionOption[];
  /** Disable editing (e.g. cancelled). */
  locked?: boolean;
}

type ModalState =
  | { kind: 'speaker'; editing: ActivitySpeaker | null }
  | { kind: 'service'; editing: ActivityServiceAssignment | null }
  | null;

function sessionTag(sessionNumber: number | null, isProgram: boolean) {
  if (!isProgram || sessionNumber == null) return null;
  return <Badge variant="neutral">Session {sessionNumber}</Badge>;
}

export function ActivityTeamCards({ organizationId, target, sessionOptions, locked }: ActivityTeamCardsProps) {
  const { data, isLoading, error } = useActivityTeam(organizationId, target);
  const removeSpeaker = useRemoveActivitySpeaker();
  const removeService = useRemoveActivityServiceAssignment();
  const [modal, setModal] = useState<ModalState>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const isProgram = !!target.programRunId;

  if (isLoading) {
    return <Skeleton className="h-40" />;
  }
  if (error || !data) {
    return null; // viewer may not have access; never block the page
  }

  const canEdit = data.can_manage && !locked;

  const handleRemove = async (fn: () => Promise<unknown>) => {
    setActionError(null);
    try {
      await fn();
    } catch (err) {
      setActionError(getEventErrorMessage(err));
    }
  };

  return (
    <>
      {actionError && <Alert variant="danger">{actionError}</Alert>}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Speakers */}
        <Card padding="comfortable" className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Mic className="h-4 w-4 text-ink-muted" />
              <h2 className="text-h3 font-semibold text-ink">Speakers</h2>
            </div>
            {canEdit && (
              <Button
                id="add-activity-speaker"
                variant="outline"
                size="sm"
                icon={<Plus className="h-3.5 w-3.5" />}
                onClick={() => setModal({ kind: 'speaker', editing: null })}
              >
                Add speaker
              </Button>
            )}
          </div>
          {data.speakers.length === 0 ? (
            <p className="py-4 text-center text-small text-ink-muted">No speakers recorded yet.</p>
          ) : (
            <div className="divide-y divide-line rounded-control border border-line bg-surface">
              {data.speakers.map((s) => (
                <div key={s.id} className="flex items-start justify-between gap-3 p-3">
                  <div className="min-w-0 space-y-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-body font-medium text-ink">{s.display_name}</span>
                      <Badge variant={s.person_type === 'member' ? 'info' : 'neutral'}>
                        {s.person_type === 'member' ? 'Member' : 'Guest'}
                      </Badge>
                      <Badge variant="neutral">{SPEAKER_ROLE_LABELS[s.speaker_role] ?? s.speaker_role}</Badge>
                      {sessionTag(s.session_number, isProgram)}
                    </div>
                    {s.external_organization && (
                      <p className="text-caption text-ink-muted">{s.external_organization}</p>
                    )}
                    {(s.topic_title || s.session_label) && (
                      <p className="text-small text-ink-secondary">
                        {[s.session_label, s.topic_title].filter(Boolean).join(' · ')}
                      </p>
                    )}
                    {s.notes && <p className="text-caption italic text-ink-muted">Note: {s.notes}</p>}
                  </div>
                  {canEdit && (
                    <div className="flex shrink-0 gap-1">
                      <Button size="sm" variant="ghost" onClick={() => setModal({ kind: 'speaker', editing: s })}>
                        Edit
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-danger-600 hover:text-danger-700"
                        loading={removeSpeaker.isPending && removeSpeaker.variables?.speakerId === s.id}
                        onClick={() =>
                          handleRemove(() => removeSpeaker.mutateAsync({ organizationId, speakerId: s.id }))
                        }
                      >
                        Remove
                      </Button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </Card>

        {/* Service team */}
        <Card padding="comfortable" className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Users className="h-4 w-4 text-ink-muted" />
              <h2 className="text-h3 font-semibold text-ink">Service Team</h2>
            </div>
            {canEdit && (
              <Button
                id="add-activity-service-member"
                variant="outline"
                size="sm"
                icon={<Plus className="h-3.5 w-3.5" />}
                onClick={() => setModal({ kind: 'service', editing: null })}
              >
                Add member
              </Button>
            )}
          </div>
          {data.service_team.length === 0 ? (
            <p className="py-4 text-center text-small text-ink-muted">No service team recorded yet.</p>
          ) : (
            <div className="divide-y divide-line rounded-control border border-line bg-surface">
              {data.service_team.map((a) => (
                <div key={a.id} className="flex items-start justify-between gap-3 p-3">
                  <div className="min-w-0 space-y-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-body font-medium text-ink">{a.display_name}</span>
                      {a.person_type === 'external' && <Badge variant="neutral">Volunteer</Badge>}
                      {sessionTag(a.session_number, isProgram)}
                    </div>
                    <p className="text-small text-ink-secondary">
                      {a.role_label}
                      {a.team_group ? ` · ${a.team_group}` : ''}
                    </p>
                    {a.notes && <p className="text-caption italic text-ink-muted">Note: {a.notes}</p>}
                  </div>
                  {canEdit && (
                    <div className="flex shrink-0 gap-1">
                      <Button size="sm" variant="ghost" onClick={() => setModal({ kind: 'service', editing: a })}>
                        Edit
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-danger-600 hover:text-danger-700"
                        loading={removeService.isPending && removeService.variables?.assignmentId === a.id}
                        onClick={() =>
                          handleRemove(() => removeService.mutateAsync({ organizationId, assignmentId: a.id }))
                        }
                      >
                        Remove
                      </Button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {canEdit && (
        <AssignmentModal
          open={!!modal}
          onClose={() => setModal(null)}
          organizationId={organizationId}
          kind={modal?.kind ?? 'speaker'}
          target={target}
          sessionOptions={sessionOptions}
          editingSpeaker={modal?.kind === 'speaker' ? modal.editing : null}
          editingService={modal?.kind === 'service' ? modal.editing : null}
        />
      )}
    </>
  );
}

import { useState } from 'react';
import { ChevronDown, Plus, Trash2 } from 'lucide-react';
import { useFormationProgram } from '../queries';
import { formatFormationCompletionDate } from '../formatters';
import type {
  FormationSessionStatus,
  FormationTranscriptProgram,
  FormationTranscriptTalk,
} from '../types';
import { Badge, Button } from '../../../components/ui';

interface FormationProgramRowProps {
  program: FormationTranscriptProgram;
  organizationId?: string | null;
  showAdminDetails?: boolean;
  canRecord?: boolean;
  canCorrect?: boolean;
  onOpenRecordTalk?: (program: FormationTranscriptProgram) => void;
  onOpenVoidProgram?: (program: FormationTranscriptProgram) => void;
  onOpenVoidTalk?: (talk: FormationTranscriptTalk, programTitle: string) => void;
}

function ProgramStatusBadge({ status }: { status: FormationTranscriptProgram['status'] }) {
  switch (status) {
    case 'completed':
      return <Badge variant="success">Completed</Badge>;
    case 'in_progress':
      return <Badge variant="info">In progress</Badge>;
    case 'waived':
      return <Badge variant="neutral">Waived</Badge>;
    default:
      return <Badge variant="neutral">{status}</Badge>;
  }
}

function TalkSessionStatusBadge({ status }: { status: FormationSessionStatus }) {
  switch (status) {
    case 'attended':
      return <Badge variant="success">Attended</Badge>;
    case 'makeup_attended':
      return <Badge variant="info">Make-up attended</Badge>;
    case 'absent_excused':
      return <Badge variant="neutral">Excused absence</Badge>;
    case 'waived':
      return <Badge variant="neutral">Waived</Badge>;
    default:
      return <Badge variant="neutral">{status}</Badge>;
  }
}

export function FormationProgramRow({
  program,
  organizationId,
  showAdminDetails = false,
  canRecord = false,
  canCorrect = false,
  onOpenRecordTalk,
  onOpenVoidProgram,
  onOpenVoidTalk,
}: FormationProgramRowProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  // Fetch canonical program talks when expanded in admin view
  const { data: programDetail, isLoading: isTalksLoading } = useFormationProgram(
    organizationId ?? null,
    program.program_id,
    showAdminDetails && isExpanded && !!organizationId
  );

  const isCompletedOrWaived = program.status === 'completed' || program.status === 'waived';
  const completionDateFormatted = formatFormationCompletionDate(
    program.date_precision,
    program.completed_date,
    program.completed_year,
    program.completed_month
  );

  const isProgramLevel =
    program.progress.progress_status === 'not_applicable' ||
    program.progress.total_talks === 0;

  const targetRequiredTalks =
    program.progress.required_talks > 0
      ? program.progress.required_talks
      : program.progress.total_talks;

  const progressPercent = program.progress.progress_percent ?? 0;

  // Map recorded talks by talk_id for fast lookup
  const recordedTalksMap = new Map<string, FormationTranscriptTalk>(
    program.talks.map((t) => [t.talk_id, t])
  );

  return (
    <div className="rounded-lg border border-line bg-surface p-3.5 space-y-2.5">
      {/* Title, Attempt & Status Badge */}
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-2 flex-wrap">
            <h3 className="text-sm font-semibold text-ink">{program.title}</h3>
            <span className="font-mono text-xs text-ink-muted">({program.code})</span>
            {program.attempt_number > 1 && (
              <span className="rounded border border-line bg-surface-muted px-1.5 py-0.5 text-[10px] font-semibold text-ink-secondary">
                Attempt {program.attempt_number}
              </span>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2">
          <ProgramStatusBadge status={program.status} />

          {/* Admin program-level actions */}
          {showAdminDetails && (
            <div className="flex items-center gap-1.5">
              {canRecord && !isProgramLevel && program.record_status === 'active' && (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => onOpenRecordTalk?.(program)}
                  className="h-7 text-xs px-2 py-0 gap-1"
                >
                  <Plus className="h-3 w-3" />
                  <span>Record talk</span>
                </Button>
              )}

              {canCorrect && program.record_status === 'active' && (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => onOpenVoidProgram?.(program)}
                  className="h-7 text-xs px-2 py-0 text-danger-700 hover:border-danger-600 hover:bg-danger-50"
                  title="Remove record"
                >
                  <Trash2 className="h-3 w-3" />
                  <span className="hidden sm:inline">Remove record</span>
                </Button>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Completion Date (shown only for completed or waived records) */}
      {isCompletedOrWaived && (
        <div className="flex items-center justify-between text-xs text-ink-muted">
          <span>Completion date</span>
          <span className="font-medium text-ink">{completionDateFormatted}</span>
        </div>
      )}

      {/* Talk Progress or Program-Level Course */}
      {isProgramLevel ? (
        <div className="pt-1 border-t border-line text-xs italic text-ink-muted">
          Program-level course — no individual talks tracked
        </div>
      ) : (
        <div className="space-y-1.5 pt-1 border-t border-line">
          <div className="flex items-center justify-between text-xs text-ink-muted">
            <span>Talk progress</span>
            <span className="font-medium text-ink">
              {program.progress.attended_talks} of {targetRequiredTalks} required talks
            </span>
          </div>
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface-muted border border-line">
            <div
              className="h-full rounded-full bg-primary-blue transition-all"
              style={{ width: `${progressPercent}%` }}
            />
          </div>

          {/* Admin: Expandable talk list toggle */}
          {showAdminDetails && (
            <div className="pt-1">
              <button
                type="button"
                onClick={() => setIsExpanded((prev) => !prev)}
                className="inline-flex items-center gap-1 text-[11px] font-medium text-primary-blue hover:underline focus:outline-none"
              >
                <span>
                  {isExpanded
                    ? 'Hide session details'
                    : `Show session details (${program.talks.length} recorded)`}
                </span>
                <ChevronDown
                  className={`h-3 w-3 transition-transform ${isExpanded ? 'rotate-180' : ''}`}
                  aria-hidden="true"
                />
              </button>

              {/* Collapsible talk breakdown */}
              {isExpanded && (
                <div className="mt-2.5 space-y-2 rounded-lg border border-line bg-surface-muted p-3">
                  {isTalksLoading ? (
                    <div className="space-y-1 py-1">
                      <div className="h-4 w-3/4 animate-pulse rounded bg-surface" />
                      <div className="h-4 w-1/2 animate-pulse rounded bg-surface" />
                    </div>
                  ) : !programDetail || programDetail.talks.length === 0 ? (
                    <p className="text-xs text-ink-muted italic">
                      No session details available for this course.
                    </p>
                  ) : (
                    <div className="divide-y divide-line">
                      {programDetail.talks.map((talk) => {
                        const recordedTalk = recordedTalksMap.get(talk.id);

                        return (
                          <div
                            key={talk.id}
                            className="flex flex-wrap items-center justify-between gap-2 py-2 first:pt-0 last:pb-0 text-xs"
                          >
                            <div className="min-w-0 flex-1">
                              <div className="flex items-center gap-1.5 flex-wrap">
                                <span className="font-semibold text-ink">
                                  {talk.sequence_order}. {talk.talk_code}
                                </span>
                                <span className="text-ink-secondary truncate">
                                  — {talk.title}
                                </span>
                              </div>
                              {recordedTalk?.attended_date && (
                                <p className="text-[11px] text-ink-muted mt-0.5">
                                  Attended: {recordedTalk.attended_date}
                                </p>
                              )}
                              {recordedTalk?.notes && (
                                <p className="text-[11px] text-ink-muted italic mt-0.5">
                                  Note: {recordedTalk.notes}
                                </p>
                              )}
                            </div>

                            <div className="flex items-center gap-2 shrink-0">
                              {recordedTalk ? (
                                <>
                                  <TalkSessionStatusBadge status={recordedTalk.session_status} />
                                  {canCorrect && (
                                    <button
                                      type="button"
                                      onClick={() => onOpenVoidTalk?.(recordedTalk, `${program.code}: ${talk.title}`)}
                                      className="text-[11px] text-danger-700 hover:text-danger-900 hover:underline font-medium"
                                    >
                                      Remove record
                                    </button>
                                  )}
                                </>
                              ) : (
                                <span className="rounded border border-line bg-surface px-1.5 py-0.5 text-[10px] text-ink-muted">
                                  Not recorded
                                </span>
                              )}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* Admin: Internal leader notes */}
      {showAdminDetails && program.verification_notes && (
        <div className="pt-2 border-t border-line text-xs text-ink-muted">
          <span className="font-medium text-ink-secondary">Leader note:</span>{' '}
          <span>{program.verification_notes}</span>
        </div>
      )}
    </div>
  );
}

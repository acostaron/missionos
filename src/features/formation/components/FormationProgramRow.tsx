import type { FormationTranscriptProgram } from '../types';
import { formatFormationCompletionDate } from '../formatters';
import { Badge } from '../../../components/ui';

interface FormationProgramRowProps {
  program: FormationTranscriptProgram;
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

export function FormationProgramRow({ program }: FormationProgramRowProps) {
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
        <div className="shrink-0">
          <ProgramStatusBadge status={program.status} />
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
        </div>
      )}
    </div>
  );
}

import { BookOpen } from 'lucide-react';
import { useMemberFormationTranscript } from '../queries';
import { FormationProgramRow } from './FormationProgramRow';

interface MemberFormationCardProps {
  organizationId: string | null;
  memberId: string;
  canViewFormation: boolean;
}

export function MemberFormationCard({
  organizationId,
  memberId,
  canViewFormation,
}: MemberFormationCardProps) {
  const {
    data: transcript,
    isLoading,
    error,
  } = useMemberFormationTranscript(organizationId, memberId, canViewFormation);

  // Only rendered if caller has FormationRecordsView
  if (!canViewFormation) {
    return null;
  }

  // Show only records with record_status === 'active' (excludes voided AND superseded)
  const activePrograms = (transcript?.programs ?? []).filter(
    (p) => p.record_status === 'active'
  );

  return (
    <div className="rounded-xl border border-line bg-surface-muted overflow-hidden">
      <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-ink-muted">
            <BookOpen className="h-4 w-4" />
          </span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
            Formation
          </h2>
        </div>
      </div>

      <div className="px-5 py-4">
        {isLoading ? (
          <div className="space-y-3 py-1">
            <div className="h-16 animate-pulse rounded-lg bg-surface border border-line" />
          </div>
        ) : error ? (
          <div className="rounded-lg border border-danger-600/30 bg-danger-50 p-3 text-xs text-danger-700">
            Failed to load formation records.
          </div>
        ) : activePrograms.length === 0 ? (
          <p className="text-xs text-ink-muted italic py-1">
            No Formation records yet.
          </p>
        ) : (
          <div className="space-y-3">
            {activePrograms.map((prog) => (
              <FormationProgramRow key={prog.record_id} program={prog} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

import { BookOpen } from 'lucide-react';
import { useMyFormationTranscript } from '../queries';
import { FormationProgramRow } from './FormationProgramRow';
import { Card } from '../../../components/ui';

interface MyFormationCardProps {
  organizationId?: string | null;
  enabled?: boolean;
}

export function MyFormationCard({
  organizationId,
  enabled = true,
}: MyFormationCardProps) {
  const { data: transcript, isLoading, error } = useMyFormationTranscript(
    organizationId,
    enabled
  );

  // If the RPC returns no linked member (e.g. error code P0002) or permission error,
  // hide the card gracefully (no red error box).
  if (error || (!isLoading && !transcript)) {
    return null;
  }

  // Show only records with record_status === 'active' (excludes voided AND superseded)
  const activePrograms = (transcript?.programs ?? []).filter(
    (p) => p.record_status === 'active'
  );

  return (
    <Card padding="comfortable">
      <div className="flex items-center gap-2.5 border-b border-line pb-4">
        <div
          className="flex h-9 w-9 items-center justify-center rounded-full bg-navy-50 text-primary-blue"
          aria-hidden="true"
        >
          <BookOpen className="h-5 w-5" />
        </div>
        <div>
          <h2 className="text-card-title font-semibold text-ink">My Formation</h2>
          <p className="text-caption text-ink-muted">
            Your pastoral courses, retreats, and curriculum progress
          </p>
        </div>
      </div>

      <div className="mt-4">
        {isLoading ? (
          <div className="space-y-3 py-1">
            <div className="h-16 animate-pulse rounded-lg bg-surface border border-line" />
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
    </Card>
  );
}

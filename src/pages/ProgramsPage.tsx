import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, GraduationCap, Calendar, Users, Award } from 'lucide-react';
import {
  Badge,
  Button,
  Card,
  PageHeader,
  Skeleton,
} from '../components/ui';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { useProgramRunsList } from '../features/programs/queries';
import {
  PROGRAM_CODE_LABELS,
  PROGRAM_STATUS_LABELS,
  getProgramCodeBadgeVariant,
  getProgramStatusBadgeVariant,
} from '../features/programs/labels';
import { NewProgramModal } from '../features/programs/components/NewProgramModal';

export default function ProgramsPage() {
  const navigate = useNavigate();
  const { activeOrganization } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;

  const [includeClosed, setIncludeClosed] = useState(false);
  const [isNewProgramOpen, setIsNewProgramOpen] = useState(false);

  const { data, isLoading } = useProgramRunsList(orgId, includeClosed);

  const canCreate = data?.can_create ?? false;
  const runs = data?.runs ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Programs"
        description="Youth Camp, Discovery Camp, Christian Life Seminar and community programs."
        actions={
          canCreate ? (
            <Button
              variant="primary"
              icon={<Plus className="h-4 w-4" />}
              onClick={() => setIsNewProgramOpen(true)}
            >
              New program
            </Button>
          ) : undefined
        }
      />

      {/* Filter Row: Switch "Show completed & cancelled" */}
      <div className="flex items-center justify-between border-b border-line pb-4">
        <label className="flex cursor-pointer items-center gap-2 text-small text-ink-secondary">
          <input
            type="checkbox"
            checked={includeClosed}
            onChange={(e) => setIncludeClosed(e.target.checked)}
            className="h-4 w-4 rounded border-line text-primary focus:ring-focus"
          />
          Show completed & cancelled
        </label>
        <span className="text-caption text-ink-muted">
          {runs.length} program{runs.length === 1 ? '' : 's'}
        </span>
      </div>

      {/* Loading state */}
      {isLoading && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Skeleton className="h-48" />
          <Skeleton className="h-48" />
          <Skeleton className="h-48" />
        </div>
      )}

      {/* Empty State */}
      {!isLoading && runs.length === 0 && (
        <Card padding="comfortable" className="text-center py-12 space-y-3">
          <GraduationCap className="mx-auto h-10 w-10 text-ink-muted" />
          <h3 className="text-h3 font-semibold text-ink">No programs found</h3>
          <p className="text-small text-ink-muted max-w-md mx-auto">
            {includeClosed
              ? 'No active, completed or cancelled programs found for this organization.'
              : 'There are currently no active programs. Check "Show completed & cancelled" or create a new program.'}
          </p>
          {canCreate && (
            <Button
              variant="primary"
              size="sm"
              icon={<Plus className="h-4 w-4" />}
              onClick={() => setIsNewProgramOpen(true)}
              className="mt-2"
            >
              New program
            </Button>
          )}
        </Card>
      )}

      {/* Program Cards Grid */}
      {!isLoading && runs.length > 0 && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {runs.map((run) => (
            <div
              key={run.id}
              onClick={() => navigate(`/app/programs/${run.id}`)}
              className="group flex flex-col justify-between rounded-card border border-line bg-surface p-5 shadow-xs transition-all hover:border-primary/40 hover:shadow-sm cursor-pointer"
            >
              <div className="space-y-3">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant={getProgramCodeBadgeVariant(run.program_code)}>
                    {PROGRAM_CODE_LABELS[run.program_code]}
                  </Badge>
                  <Badge variant={getProgramStatusBadgeVariant(run.run_status)}>
                    {PROGRAM_STATUS_LABELS[run.run_status]}
                  </Badge>
                </div>

                <h3 className="text-h3 font-bold text-ink group-hover:text-primary transition-colors">
                  {run.title}
                </h3>

                {/* Chapter / Section info */}
                <div className="text-small text-ink-secondary space-y-0.5">
                  {run.chapter_name && (
                    <p className="truncate">
                      <span className="font-medium text-ink">Chapter:</span> {run.chapter_name}
                    </p>
                  )}
                  {run.sections.length > 0 && (
                    <p className="truncate">
                      <span className="font-medium text-ink">
                        {run.sections.length > 1 ? 'Sections:' : 'Section:'}
                      </span>{' '}
                      {run.sections.map((s) => s.name).join(', ')}
                    </p>
                  )}
                  {!run.chapter_name && run.sections.length === 0 && run.audience_name && (
                    <p className="truncate">
                      <span className="font-medium text-ink">Audience:</span> {run.audience_name}
                    </p>
                  )}
                </div>
              </div>

              {/* Stats Footer */}
              <div className="mt-5 border-t border-line/60 pt-3 space-y-1.5 text-caption text-ink-muted">
                <div className="flex items-center gap-1.5">
                  <Calendar className="h-3.5 w-3.5" />
                  <span>
                    Sessions {run.sessions_scheduled} of {run.session_count} scheduled
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="flex items-center gap-1.5">
                    <Users className="h-3.5 w-3.5" />
                    <span>
                      {run.participant_count} participant{run.participant_count === 1 ? '' : 's'}
                    </span>
                  </span>
                  <span className="flex items-center gap-1.5 font-semibold text-ink">
                    <Award className="h-3.5 w-3.5 text-warning-600" />
                    <span>
                      {run.graduate_count} graduate{run.graduate_count === 1 ? '' : 's'}
                    </span>
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* New Program Modal */}
      {orgId && (
        <NewProgramModal
          open={isNewProgramOpen}
          onClose={() => setIsNewProgramOpen(false)}
          organizationId={orgId}
          onSuccess={(newRun) => {
            navigate(`/app/programs/${newRun.id}`);
          }}
        />
      )}
    </div>
  );
}

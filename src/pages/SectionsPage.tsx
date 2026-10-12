import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useSectionsOverview } from '../features/sections/queries';
import { PageHeader } from '../components/ui/PageHeader';
import { Card } from '../components/ui/Card';
import { Badge } from '../components/ui/Badge';
import { Skeleton } from '../components/ui/Skeleton';
import { Alert } from '../components/ui/Alert';
import type { SectionCoordinator } from '../features/sections/types';

function CoordinatorDisplay({
  coordinator,
  isException,
  exceptionReason,
}: {
  coordinator: SectionCoordinator | null;
  isException?: boolean;
  exceptionReason?: string | null;
}) {
  if (!coordinator) {
    return (
      <div className="mt-2">
        <Badge variant="neutral">Vacant</Badge>
      </div>
    );
  }

  const partnerText = coordinator.partner ? ` & ${coordinator.partner.display_name}` : '';
  const hasException = isException || coordinator.is_exception;
  const reason = exceptionReason ?? coordinator.exception_reason;

  return (
    <div className="mt-2 space-y-1">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium text-ink">
          {coordinator.display_name}
          {partnerText}
        </span>
        {coordinator.member_number && (
          <span className="text-caption text-ink-muted">
            ({coordinator.member_number})
          </span>
        )}
      </div>
      {hasException && (
        <div className="pt-1">
          <Badge variant="warning">Approved exception</Badge>
          {reason && (
            <p className="mt-1 text-caption text-ink-muted">{reason}</p>
          )}
        </div>
      )}
    </div>
  );
}

export default function SectionsPage() {
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const orgId = activeOrganization?.id ?? null;

  const canViewSections = !isPermLoading && hasPermission(Permissions.MembersRecordsView);
  const { data, isLoading, error } = useSectionsOverview(canViewSections ? orgId : null);

  if (!canViewSections && !isPermLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="rounded-card border border-line bg-surface p-6 text-center">
          <p className="text-small text-ink-muted">
            You do not have permission to view pastoral sections.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8 space-y-8">
      <PageHeader
        title="Sections"
        description="Pastoral sections, active member counts, and appointed coordinators."
      />

      {error && (
        <Alert variant="danger" title="Unable to load sections">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </Alert>
      )}

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {Array.from({ length: 7 }).map((_, i) => (
            <Card key={i} className="p-6 space-y-4">
              <Skeleton className="h-6 w-3/4" />
              <Skeleton className="h-4 w-1/3" />
              <div className="pt-4 border-t border-line space-y-2">
                <Skeleton className="h-4 w-1/4" />
                <Skeleton className="h-5 w-1/2" />
              </div>
            </Card>
          ))}
        </div>
      ) : data ? (
        <div className="space-y-8">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {data.sections.map((section) => (
              <Card key={section.code} className="flex flex-col justify-between p-6">
                <div>
                  <div className="flex items-start justify-between gap-2">
                    <h2 className="text-base font-semibold text-ink">{section.name}</h2>
                    <span className="inline-flex items-center rounded-full bg-navy-50 px-2.5 py-0.5 text-xs font-semibold text-navy-800">
                      {section.active_member_count}{' '}
                      {section.active_member_count === 1 ? 'member' : 'members'}
                    </span>
                  </div>

                  <div className="mt-5 pt-4 border-t border-line">
                    <span className="text-caption font-medium uppercase tracking-wider text-ink-muted">
                      Coordinator
                    </span>
                    <CoordinatorDisplay
                      coordinator={section.coordinator}
                      isException={section.is_exception}
                      exceptionReason={section.exception_reason}
                    />
                  </div>
                </div>
              </Card>
            ))}
          </div>

          {/* FMC Card at the bottom */}
          <div>
            <h3 className="text-small font-semibold uppercase tracking-wider text-ink-muted mb-3">
              Special Ministry Group
            </h3>
            <Card className="p-6">
              <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
                <div>
                  <div className="flex items-center gap-3">
                    <h2 className="text-base font-semibold text-ink">
                      FMC — Familias Misioneras de Cristo
                    </h2>
                    <span className="inline-flex items-center rounded-full bg-navy-50 px-2.5 py-0.5 text-xs font-semibold text-navy-800">
                      {data.fmc.tagged_member_count} tagged{' '}
                      {data.fmc.tagged_member_count === 1 ? 'member' : 'members'}
                    </span>
                  </div>
                  <p className="mt-1 text-caption text-ink-secondary">
                    Spanish-speaking community. FMC is a label on top of a member's section, not a section of its own.
                  </p>
                </div>

                <div className="sm:text-right min-w-[200px] border-t sm:border-t-0 pt-3 sm:pt-0 border-line">
                  <span className="text-caption font-medium uppercase tracking-wider text-ink-muted">
                    FMC Coordinator
                  </span>
                  <CoordinatorDisplay
                    coordinator={data.fmc.coordinator}
                    isException={data.fmc.is_exception}
                    exceptionReason={data.fmc.exception_reason}
                  />
                </div>
              </div>
            </Card>
          </div>
        </div>
      ) : null}
    </div>
  );
}

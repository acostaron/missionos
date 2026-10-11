import { useParams, Link } from 'react-router-dom';
import {
  ArrowLeft,
  BookOpen,
  Calendar,
  ExternalLink,
  FileText,
  Info,
  ListOrdered,
  ShieldAlert,
  Sparkles,
  Users,
} from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useFormationProgram } from '../features/formation/queries';
import {
  formatProgramCategory,
  formatProgramType,
  formatTargetAudience,
  formatTimingNorm,
} from '../features/formation/formatters';
import { Alert, Badge, Card, EmptyState, PageHeader, Skeleton } from '../components/ui';

export default function FormationProgramDetailPage() {
  const { programId } = useParams<{ programId: string }>();
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const orgId = activeOrganization?.id ?? null;
  const canViewCatalog = !isPermLoading && hasPermission(Permissions.FormationCatalogView);

  const {
    data: program,
    isLoading,
    error,
  } = useFormationProgram(orgId, programId ?? null, canViewCatalog);

  if (!canViewCatalog && !isPermLoading) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
        <Card padding="comfortable">
          <EmptyState
            icon={<ShieldAlert className="h-8 w-8 text-warning-600" />}
            title="Access Restricted"
            message="You do not have permission to view curriculum program details."
            action={
              <Link
                to="/app/formation"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Back to Formation Catalog
              </Link>
            }
          />
        </Card>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-5xl space-y-8 px-4 py-8 sm:px-6 lg:px-8">
      <PageHeader
        title={program ? program.title : 'Program Details'}
        description={
          program
            ? `${program.code} • ${formatProgramCategory(program.program_category)} • Edition: ${program.edition}`
            : 'Formation curriculum course detail'
        }
        breadcrumb={
          <nav aria-label="Breadcrumb" className="flex items-center gap-2 text-xs text-ink-muted">
            <Link
              to="/app/dashboard"
              className="inline-flex items-center gap-1 hover:text-ink transition-colors"
            >
              <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
              Home
            </Link>
            <span aria-hidden="true">/</span>
            <Link
              to="/app/formation"
              className="hover:text-ink transition-colors"
            >
              Formation
            </Link>
            <span aria-hidden="true">/</span>
            <span className="font-medium text-ink">
              {program ? program.code : 'Details'}
            </span>
          </nav>
        }
        actions={
          <Link
            to="/app/formation"
            className="inline-flex h-9 items-center gap-1.5 rounded-control border border-line-strong bg-surface px-3.5 text-xs font-medium text-ink hover:bg-surface-muted transition-colors"
          >
            <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
            Back to Catalog
          </Link>
        }
      />

      {error ? (
        <Alert variant="danger">
          Failed to load program details: {error instanceof Error ? error.message : 'Unknown error'}
        </Alert>
      ) : isLoading ? (
        <div className="space-y-6">
          <Card padding="comfortable" className="space-y-4">
            <Skeleton className="h-7 w-1/3" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-2/3" />
          </Card>
          <Card padding="comfortable" className="space-y-4">
            <Skeleton className="h-6 w-1/4" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </Card>
        </div>
      ) : !program ? (
        <Card padding="comfortable">
          <EmptyState
            icon={<BookOpen className="h-8 w-8 text-ink-muted" />}
            title="Program Not Found"
            message="The requested formation program could not be found or is not accessible."
            action={
              <Link
                to="/app/formation"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Back to Formation Catalog
              </Link>
            }
          />
        </Card>
      ) : (
        <div className="space-y-8">
          {/* Metadata Banner Card */}
          <Card padding="comfortable" className="space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line pb-4">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-mono text-sm font-bold text-primary-blue bg-navy-50 px-2.5 py-1 rounded border border-navy-100">
                  {program.code}
                </span>
                <span className="rounded bg-surface-muted px-2.5 py-1 text-xs font-medium text-ink-secondary border border-line">
                  {formatProgramCategory(program.program_category)}
                </span>
                <span className="inline-flex items-center gap-1 rounded bg-surface-muted px-2.5 py-1 text-xs font-medium text-ink-secondary border border-line">
                  <Sparkles className="h-3 w-3 text-secondary" aria-hidden="true" />
                  {formatProgramType(program.program_type)}
                </span>
              </div>
              <div>
                <Badge variant={program.is_active ? 'success' : 'neutral'}>
                  {program.is_active ? 'Active Program' : 'Retired Program'}
                </Badge>
              </div>
            </div>

            {/* Description */}
            <div className="space-y-2">
              <h2 className="text-xs font-semibold uppercase tracking-wider text-ink-muted">
                Description
              </h2>
              <p className="text-sm text-ink leading-relaxed">
                {program.description || 'No description provided for this program.'}
              </p>
            </div>

            {/* Source Reference if available */}
            {(program.source_document || program.source_url) && (
              <div className="pt-3 border-t border-line flex flex-wrap items-center justify-between gap-3 text-xs text-ink-muted">
                <div className="flex items-center gap-1.5">
                  <FileText className="h-3.5 w-3.5 text-ink-muted" aria-hidden="true" />
                  <span>Source: {program.source_document || 'Official Manual'}</span>
                  {program.source_verified_at && (
                    <span className="text-[11px] text-ink-muted">
                      (Verified {program.source_verified_at})
                    </span>
                  )}
                </div>
                {program.source_url && (
                  <a
                    href={program.source_url}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1 text-primary-blue hover:underline"
                  >
                    <span>View Curriculum Source</span>
                    <ExternalLink className="h-3 w-3" aria-hidden="true" />
                  </a>
                )}
              </div>
            )}
          </Card>

          {/* Section: Ordered Talk List */}
          <Card padding="comfortable" className="space-y-4">
            <div className="flex items-center justify-between border-b border-line pb-3">
              <div className="flex items-center gap-2">
                <div
                  className="flex h-7 w-7 items-center justify-center rounded-lg bg-navy-50 text-primary-blue"
                  aria-hidden="true"
                >
                  <ListOrdered className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="text-sm font-semibold text-ink">
                    Course Sessions & Talks
                  </h2>
                  <p className="text-xs text-ink-muted">
                    {program.talks.length === 0
                      ? 'Program-level course'
                      : `${program.talks.length} ${program.talks.length === 1 ? 'talk session' : 'talk sessions'} in canonical sequence`}
                  </p>
                </div>
              </div>
            </div>

            {program.talks.length === 0 ? (
              <div className="rounded-xl border border-line bg-surface-muted p-5 text-center sm:text-left">
                <div className="flex items-start gap-3">
                  <Info className="h-5 w-5 text-ink-muted shrink-0 mt-0.5" aria-hidden="true" />
                  <div>
                    <h3 className="text-sm font-semibold text-ink">
                      Program-level course — no individual talks tracked
                    </h3>
                    <p className="mt-1 text-xs text-ink-muted leading-relaxed">
                      This course is tracked at the program level upon completion of the entire retreat, seminar, or training program rather than individual talk modules.
                    </p>
                  </div>
                </div>
              </div>
            ) : (
              <div className="divide-y divide-line">
                {program.talks.map((talk) => (
                  <div
                    key={talk.id}
                    className="py-3.5 first:pt-1 last:pb-1 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between"
                  >
                    <div className="space-y-1">
                      <div className="flex items-center gap-2">
                        <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-surface-muted text-[11px] font-semibold text-ink-muted border border-line">
                          {talk.sequence_order}
                        </span>
                        <span className="font-mono text-xs font-semibold text-ink-secondary">
                          {talk.talk_code}
                        </span>
                        {talk.session_label && (
                          <span className="text-[11px] text-ink-muted">
                            ({talk.session_label})
                          </span>
                        )}
                      </div>
                      <h3 className="text-sm font-medium text-ink pl-7">
                        {talk.title}
                      </h3>
                      {talk.description && (
                        <p className="text-xs text-ink-muted pl-7 leading-relaxed">
                          {talk.description}
                        </p>
                      )}
                    </div>
                    <div className="pl-7 sm:pl-0 shrink-0">
                      <span
                        className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
                          talk.is_required
                            ? 'border-line-strong bg-surface-muted text-ink'
                            : 'border-line bg-surface text-ink-muted'
                        }`}
                      >
                        {talk.is_required ? 'Required Talk' : 'Elective Session'}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>

          {/* Section: Requirements & Prerequisites */}
          <Card padding="comfortable" className="space-y-4">
            <div className="flex items-center justify-between border-b border-line pb-3">
              <div className="flex items-center gap-2">
                <div
                  className="flex h-7 w-7 items-center justify-center rounded-lg bg-navy-50 text-primary-blue"
                  aria-hidden="true"
                >
                  <Users className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="text-sm font-semibold text-ink">
                    Requirements & Target Audience
                  </h2>
                  <p className="text-xs text-ink-muted">
                    Pastoral applicability norms and prerequisites
                  </p>
                </div>
              </div>
            </div>

            {program.requirements.length === 0 ? (
              <p className="text-xs text-ink-muted italic py-2">
                No specific prerequisites or audience requirements recorded.
              </p>
            ) : (
              <div className="space-y-3">
                {program.requirements.map((req) => (
                  <div
                    key={req.id}
                    className="rounded-lg border border-line bg-surface p-4 space-y-2"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-semibold text-ink">
                          {formatTargetAudience(req.target_audience)}
                        </span>
                        <Badge variant={req.is_mandatory ? 'info' : 'neutral'}>
                          {req.is_mandatory ? 'Mandatory' : 'Elective / Recommended'}
                        </Badge>
                      </div>
                      {req.timing_norm && (
                        <span className="inline-flex items-center gap-1 text-xs text-ink-muted">
                          <Calendar className="h-3.5 w-3.5" aria-hidden="true" />
                          <span>{formatTimingNorm(req.timing_norm)}</span>
                        </span>
                      )}
                    </div>

                    {req.notes && (
                      <p className="text-xs text-ink-muted leading-relaxed">
                        {req.notes}
                      </p>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      )}
    </div>
  );
}

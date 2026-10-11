import { Link } from 'react-router-dom';
import { ArrowLeft, BookOpen, Layers, ShieldAlert, Sparkles } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useFormationCatalog } from '../features/formation/queries';
import {
  formatProgramCategory,
  formatProgramType,
} from '../features/formation/formatters';
import type { FormationProgramCategory, FormationProgramSummary } from '../features/formation/types';
import { Alert, Badge, Card, EmptyState, PageHeader, Skeleton } from '../components/ui';

const CATEGORY_ORDER: FormationProgramCategory[] = [
  'pastoral_formation',
  'leadership_training',
  'ministry_skills',
];

export default function FormationCatalogPage() {
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const orgId = activeOrganization?.id ?? null;
  const canViewCatalog = !isPermLoading && hasPermission(Permissions.FormationCatalogView);

  const {
    data: programs,
    isLoading,
    error,
  } = useFormationCatalog(orgId, undefined, canViewCatalog);

  if (!canViewCatalog && !isPermLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <Card padding="comfortable">
          <EmptyState
            icon={<ShieldAlert className="h-8 w-8 text-warning-600" />}
            title="Access Restricted"
            message="You do not have permission to view the formation curriculum catalog. Please contact your servant leader or administrator."
            action={
              <Link
                to="/app/dashboard"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Return to Home
              </Link>
            }
          />
        </Card>
      </div>
    );
  }

  // Group programs by category according to canonical order
  const groupedPrograms = (programs ?? []).reduce<
    Record<string, FormationProgramSummary[]>
  >((acc, prog) => {
    const cat = prog.program_category;
    if (!acc[cat]) {
      acc[cat] = [];
    }
    acc[cat].push(prog);
    return acc;
  }, {});

  // Determine categories to display: defined order first, then any extra
  const categoriesPresent = Object.keys(groupedPrograms) as FormationProgramCategory[];
  const sortedCategories = [
    ...CATEGORY_ORDER.filter((c) => categoriesPresent.includes(c)),
    ...categoriesPresent.filter((c) => !CATEGORY_ORDER.includes(c)),
  ];

  return (
    <div className="mx-auto max-w-7xl space-y-8 px-4 py-8 sm:px-6 lg:px-8">
      <PageHeader
        title="Formation Curriculum"
        description="Canonical pastoral formation courses, retreats, and leadership training."
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
            <span className="font-medium text-ink">Formation</span>
          </nav>
        }
      />

      {error ? (
        <Alert variant="danger">
          Failed to load formation catalog: {error instanceof Error ? error.message : 'Unknown error'}
        </Alert>
      ) : isLoading ? (
        <div className="space-y-6">
          <div className="space-y-2">
            <Skeleton className="h-6 w-48" />
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {[1, 2, 3, 4, 5, 6].map((i) => (
                <div
                  key={i}
                  className="rounded-xl border border-line bg-surface p-5 space-y-3"
                >
                  <div className="flex justify-between">
                    <Skeleton className="h-5 w-16" />
                    <Skeleton className="h-5 w-16" />
                  </div>
                  <Skeleton className="h-5 w-3/4" />
                  <Skeleton className="h-4 w-full" />
                  <Skeleton className="h-4 w-1/2" />
                </div>
              ))}
            </div>
          </div>
        </div>
      ) : !programs || programs.length === 0 ? (
        <Card padding="comfortable">
          <EmptyState
            icon={<BookOpen className="h-8 w-8 text-ink-muted" />}
            title="No Programs Available"
            message="No formation programs are currently listed in the curriculum catalog."
          />
        </Card>
      ) : (
        <div className="space-y-10">
          {sortedCategories.map((cat) => {
            const catPrograms = groupedPrograms[cat] ?? [];
            if (catPrograms.length === 0) return null;

            return (
              <section key={cat} aria-labelledby={`category-heading-${cat}`} className="space-y-4">
                <div className="flex items-center gap-2.5 border-b border-line pb-3">
                  <div
                    className="flex h-7 w-7 items-center justify-center rounded-lg bg-navy-50 text-primary-blue"
                    aria-hidden="true"
                  >
                    <Layers className="h-4 w-4" />
                  </div>
                  <div>
                    <h2
                      id={`category-heading-${cat}`}
                      className="text-base font-semibold text-ink"
                    >
                      {formatProgramCategory(cat)}
                    </h2>
                    <p className="text-xs text-ink-muted">
                      {catPrograms.length} {catPrograms.length === 1 ? 'program' : 'programs'}
                    </p>
                  </div>
                </div>

                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  {catPrograms.map((program) => {
                    const isProgramOnly = program.talk_count === 0;

                    return (
                      <Link
                        key={program.id}
                        to={`/app/formation/${program.id}`}
                        className="group flex flex-col justify-between rounded-xl border border-line bg-surface p-5 transition-all hover:border-primary-blue hover:shadow-sm focus:outline-none focus:ring-2 focus:ring-primary-blue"
                      >
                        <div className="space-y-3">
                          {/* Top Row: Code & Active/Retired Badge */}
                          <div className="flex items-center justify-between gap-2">
                            <span className="font-mono text-xs font-bold text-primary-blue bg-navy-50 px-2 py-0.5 rounded border border-navy-100">
                              {program.code}
                            </span>
                            <div className="flex items-center gap-1.5 flex-wrap justify-end">
                              <Badge variant={program.is_active ? 'success' : 'neutral'}>
                                {program.is_active ? 'Active' : 'Retired'}
                              </Badge>
                            </div>
                          </div>

                          {/* Title */}
                          <h3 className="text-sm font-semibold text-ink group-hover:text-primary-blue transition-colors leading-snug">
                            {program.title}
                          </h3>

                          {/* Description snippet if available */}
                          {program.description && (
                            <p className="line-clamp-2 text-xs text-ink-muted leading-relaxed">
                              {program.description}
                            </p>
                          )}
                        </div>

                        {/* Bottom Metadata */}
                        <div className="mt-4 pt-3 border-t border-line space-y-2 text-xs">
                          {/* Program Type */}
                          <div className="flex items-center justify-between gap-2 text-ink-muted">
                            <span className="inline-flex items-center gap-1">
                              <Sparkles className="h-3 w-3 text-secondary" aria-hidden="true" />
                              <span className="font-medium text-ink-secondary">
                                {formatProgramType(program.program_type)}
                              </span>
                            </span>
                          </div>

                          {/* Talk count or Program-level course wording */}
                          <div className="text-[11px]">
                            {isProgramOnly ? (
                              <span className="italic text-ink-muted">
                                Program-level course — no individual talks tracked
                              </span>
                            ) : (
                              <span className="font-medium text-ink-secondary">
                                {program.talk_count}{' '}
                                {program.talk_count === 1 ? 'talk' : 'talks'}
                              </span>
                            )}
                          </div>
                        </div>
                      </Link>
                    );
                  })}
                </div>
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}

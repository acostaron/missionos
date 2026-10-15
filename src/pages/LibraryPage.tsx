// Household Library — month-by-month list of MFC topics (Pass 9.2, written by Claude 2026-10-15)
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { BookOpenText, ChevronRight, RefreshCw } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { getTodayNyDate } from '../lib/ny-time';
import {
  MATERIAL_KINDS,
  formatCopiedAt,
  formatTopicMonth,
  materialKindLabel,
  useTopicLibrary,
  type LibraryItem,
} from '../features/library/api';
import { SyncTopicLibraryModal } from '../features/library/SyncTopicLibraryModal';
import { Alert, Badge, Button, Card, EmptyState, PageHeader, Select, Skeleton } from '../components/ui';

export default function LibraryPage() {
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;
  const { data, isLoading, error } = useTopicLibrary(orgId);

  const [month, setMonth] = useState<string | null>(null); // 'YYYY-MM-01' | 'all' | null (default)
  const [kind, setKind] = useState<string>('all');
  const [syncOpen, setSyncOpen] = useState(false);

  const items = useMemo(() => data?.items ?? [], [data]);
  const months = useMemo(
    () => Array.from(new Set(items.map((i) => i.topic_month.slice(0, 10)))).sort().reverse(),
    [items],
  );

  // Default: this month if it has topics, otherwise the newest month.
  const thisMonth = `${getTodayNyDate().slice(0, 7)}-01`;
  const selectedMonth = month ?? (months.includes(thisMonth) ? thisMonth : (months[0] ?? 'all'));

  const groups = useMemo(() => {
    const filtered = items.filter(
      (i) =>
        (selectedMonth === 'all' || i.topic_month.slice(0, 10) === selectedMonth) &&
        (kind === 'all' || i.material_kind === kind),
    );
    const map = new Map<string, LibraryItem[]>();
    for (const i of filtered) {
      const key = i.topic_month.slice(0, 10);
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(i);
    }
    return Array.from(map.entries()).sort((a, b) => b[0].localeCompare(a[0]));
  }, [items, selectedMonth, kind]);

  if (isOrgLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center">
        <div className="text-sm text-ink-muted">Loading…</div>
      </div>
    );
  }

  const canManage = data?.can_manage === true;

  return (
    <div className="mx-auto max-w-3xl space-y-6 px-4 py-8 sm:px-6">
      <PageHeader
        title="Household Library"
        description="MFC monthly topics for household meetings and chapter assemblies."
        actions={
          canManage ? (
            <Button variant="outline" size="sm" icon={<RefreshCw size={16} />} onClick={() => setSyncOpen(true)}>
              Check MFC site
            </Button>
          ) : undefined
        }
      />

      {canManage && (data?.pending_review_count ?? 0) > 0 && (
        <Alert variant="warning" title="Copies waiting for your approval">
          {data!.pending_review_count} topic {data!.pending_review_count === 1 ? 'copy is' : 'copies are'} waiting.
          Open a topic marked “Awaiting approval” to review it. Members see a topic only after you approve it.
        </Alert>
      )}

      {error && <Alert variant="danger" title="Could not load the Household Library">{(error as Error).message}</Alert>}

      {isLoading ? (
        <div className="space-y-3">
          <Skeleton className="h-16 w-full" />
          <Skeleton className="h-16 w-full" />
          <Skeleton className="h-16 w-full" />
        </div>
      ) : items.length === 0 ? (
        <EmptyState
          icon={<BookOpenText />}
          title="No topics yet"
          message={
            canManage
              ? 'Use “Check MFC site” to copy the monthly topics into the library.'
              : 'Your leaders have not added this month’s topics yet.'
          }
        />
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">Month</span>
              <Select value={selectedMonth} onChange={(e) => setMonth(e.target.value)}>
                {months.map((m) => (
                  <option key={m} value={m}>
                    {formatTopicMonth(m)}
                  </option>
                ))}
                <option value="all">All months</option>
              </Select>
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">Type</span>
              <Select value={kind} onChange={(e) => setKind(e.target.value)}>
                <option value="all">All types</option>
                {MATERIAL_KINDS.map((k) => (
                  <option key={k} value={k}>
                    {materialKindLabel(k)}
                  </option>
                ))}
              </Select>
            </label>
          </div>

          {groups.length === 0 ? (
            <EmptyState title="Nothing here" message="No topics match this month and type." />
          ) : (
            groups.map(([m, list]) => (
              <section key={m} className="space-y-3">
                <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">{formatTopicMonth(m)}</h2>
                <ul className="space-y-3">
                  {list.map((i) => (
                    <li key={i.topic_id}>
                      <Link
                        to={`/app/library/${i.topic_id}`}
                        className="block rounded-card focus-visible:outline-2 focus-visible:outline-focus"
                      >
                        <Card variant="interactive" padding="compact" className="flex items-center gap-3">
                          <div className="min-w-0 flex-1 space-y-1">
                            <div className="flex flex-wrap items-center gap-2">
                              <Badge variant="info">{materialKindLabel(i.material_kind)}</Badge>
                              {canManage && i.has_pending && <Badge variant="warning">Awaiting approval</Badge>}
                            </div>
                            <p className="text-base font-medium text-ink">{i.title}</p>
                            <p className="text-xs text-ink-muted">
                              {i.has_content ? `Copied ${formatCopiedAt(i.copied_at)}` : 'Not yet approved'}
                            </p>
                          </div>
                          <ChevronRight className="h-5 w-5 shrink-0 text-ink-muted" aria-hidden="true" />
                        </Card>
                      </Link>
                    </li>
                  ))}
                </ul>
              </section>
            ))
          )}
        </>
      )}

      {canManage && <SyncTopicLibraryModal open={syncOpen} onClose={() => setSyncOpen(false)} organizationId={orgId} />}
    </div>
  );
}

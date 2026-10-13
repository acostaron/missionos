import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { usePlacementWorklist } from '../features/placement/queries';
import { useSectionsOverview } from '../features/sections/queries';
import { PlaceMembersModal } from '../features/placement/components/PlaceMembersModal';
import { PageHeader } from '../components/ui/PageHeader';
import { Button } from '../components/ui/Button';
import { Badge } from '../components/ui/Badge';
import { Alert } from '../components/ui/Alert';
import type {
  PlacementView,
  PlacementWorklistMember,
  SelectedMemberInfo,
} from '../features/placement/types';

function formatPlacementDisplay(placement: PlacementWorklistMember['placement']) {
  if (!placement) {
    return <span className="text-ink-muted">Not placed</span>;
  }
  if (placement.node_type_code === 'unit' && placement.parent_name) {
    return (
      <span className="text-ink">
        {placement.name} <span className="text-ink-muted">·</span> {placement.parent_name}
      </span>
    );
  }
  return <span className="text-ink">{placement.name}</span>;
}

export default function PlaceMembersPage() {
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const orgId = activeOrganization?.id ?? null;

  const canManagePlacements =
    !isPermLoading && hasPermission(Permissions.MembersPlacementsManage);

  // Filter state
  const [view, setView] = useState<PlacementView>('unplaced');
  const [sectionNodeId, setSectionNodeId] = useState<string | null>(null);
  const [searchInput, setSearchInput] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [page, setPage] = useState(1);

  // Selection state
  const [selectedMembers, setSelectedMembers] = useState<Map<string, SelectedMemberInfo>>(
    new Map()
  );

  // Modal state
  const [isModalOpen, setIsModalOpen] = useState(false);

  // Debounce search input (300ms)
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(searchInput);
    }, 300);
    return () => clearTimeout(timer);
  }, [searchInput]);

  // Load sections overview for section filter dropdown
  const { data: sectionsData } = useSectionsOverview(canManagePlacements ? orgId : null);

  // Load placement worklist
  const {
    data: worklistData,
    isLoading: isWorklistLoading,
    isFetching: isWorklistFetching,
    error: worklistError,
  } = usePlacementWorklist(
    canManagePlacements ? orgId : null,
    {
      view,
      sectionNodeId,
      search: debouncedSearch || null,
      page,
    },
    canManagePlacements
  );

  const summary = worklistData?.summary;
  const members = worklistData?.members ?? [];
  const totalCount = worklistData?.total_count ?? 0;
  const pageSize = worklistData?.page_size ?? 100;
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));

  // Filter handlers
  const handleViewChange = (newView: PlacementView) => {
    setView(newView);
    setPage(1);
  };

  const handleSectionChange = (val: string) => {
    setSectionNodeId(val || null);
    setPage(1);
  };

  const handleSearchChange = (val: string) => {
    setSearchInput(val);
    setPage(1);
  };

  // Selection handlers
  const isMaxSelected = selectedMembers.size >= 100;

  const allPageSelected =
    members.length > 0 && members.every((m) => selectedMembers.has(m.id));
  const somePageSelected =
    members.length > 0 && members.some((m) => selectedMembers.has(m.id));

  const handleToggleSelectAllPage = () => {
    const next = new Map(selectedMembers);
    if (allPageSelected) {
      for (const m of members) {
        next.delete(m.id);
      }
    } else {
      for (const m of members) {
        if (next.size >= 100) break;
        next.set(m.id, {
          display_name: m.display_name,
          member_number: m.member_number,
          has_placement: !!m.placement,
        });
      }
    }
    setSelectedMembers(next);
  };

  const handleToggleMember = (m: PlacementWorklistMember) => {
    const next = new Map(selectedMembers);
    if (next.has(m.id)) {
      next.delete(m.id);
    } else {
      if (next.size < 100) {
        next.set(m.id, {
          display_name: m.display_name,
          member_number: m.member_number,
          has_placement: !!m.placement,
        });
      }
    }
    setSelectedMembers(next);
  };

  const handleClearSelection = () => {
    setSelectedMembers(new Map());
  };

  const handlePlacementComplete = (placedMemberIds: string[]) => {
    const next = new Map(selectedMembers);
    for (const id of placedMemberIds) {
      next.delete(id);
    }
    setSelectedMembers(next);
  };

  // Permission check
  if (!canManagePlacements && !isPermLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="rounded-card border border-line bg-surface p-6 text-center">
          <p className="text-small text-ink-muted">
            You do not have permission to place members.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8 space-y-6 pb-24">
      {/* Page Header */}
      <PageHeader
        title="Place Members"
        description="Assign members to a chapter or unit. Each change is kept in the member's placement history."
      />

      {/* Summary Counts */}
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-2 rounded-lg border border-border bg-surface px-3 py-2 shadow-xs">
          <span className="text-xs font-medium text-ink-muted">Not placed:</span>
          <span className="text-sm font-semibold text-ink" id="not-placed-count">
            {summary ? summary.unplaced_count.toLocaleString() : '…'}
          </span>
        </div>
        <div className="flex items-center gap-2 rounded-lg border border-border bg-surface px-3 py-2 shadow-xs">
          <span className="text-xs font-medium text-ink-muted">Placed:</span>
          <span className="text-sm font-semibold text-ink" id="placed-count">
            {summary ? summary.placed_count.toLocaleString() : '…'}
          </span>
        </div>
        {isWorklistFetching && !isWorklistLoading && (
          <span className="text-xs text-primary-blue animate-pulse">updating…</span>
        )}
      </div>

      {/* Filter Controls */}
      <div className="flex flex-col gap-3 rounded-lg border border-border bg-surface p-4 shadow-xs sm:flex-row sm:items-center sm:justify-between">
        {/* View Segmented Control */}
        <div className="inline-flex rounded-lg border border-border bg-surface-subtle p-0.5">
          <button
            type="button"
            onClick={() => handleViewChange('unplaced')}
            className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
              view === 'unplaced'
                ? 'bg-surface text-ink shadow-xs'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            Not placed
          </button>
          <button
            type="button"
            onClick={() => handleViewChange('placed')}
            className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
              view === 'placed'
                ? 'bg-surface text-ink shadow-xs'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            Placed
          </button>
          <button
            type="button"
            onClick={() => handleViewChange('all')}
            className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
              view === 'all'
                ? 'bg-surface text-ink shadow-xs'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            All
          </button>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          {/* Section Select */}
          <select
            value={sectionNodeId ?? ''}
            onChange={(e) => handleSectionChange(e.target.value)}
            className="rounded-lg border border-border bg-surface px-3 py-1.5 text-xs text-ink focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent"
          >
            <option value="">All sections</option>
            {sectionsData?.sections.map((sec) => (
              <option key={sec.node_id} value={sec.node_id}>
                {sec.name}
              </option>
            ))}
          </select>

          {/* Search Input */}
          <div className="relative">
            <input
              type="text"
              placeholder="Search members…"
              value={searchInput}
              onChange={(e) => handleSearchChange(e.target.value)}
              className="w-full sm:w-56 rounded-lg border border-border bg-surface px-3 py-1.5 text-xs text-ink placeholder:text-ink-muted focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent"
            />
            {searchInput && (
              <button
                type="button"
                onClick={() => handleSearchChange('')}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-ink-muted hover:text-ink"
              >
                ×
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Max Selection Notice */}
      {isMaxSelected && (
        <Alert variant="info">
          You can place up to 100 members at a time.
        </Alert>
      )}

      {/* Error State */}
      {worklistError && (
        <Alert variant="danger" title="Unable to load worklist">
          {worklistError instanceof Error
            ? worklistError.message
            : 'An unexpected error occurred.'}
        </Alert>
      )}

      {/* Loading Skeleton */}
      {isWorklistLoading && (
        <div className="rounded-lg border border-border bg-surface p-6 text-center text-sm text-ink-muted">
          Loading members…
        </div>
      )}

      {/* Empty State */}
      {!isWorklistLoading && !worklistError && members.length === 0 && (
        <div className="rounded-lg border border-border bg-surface p-8 text-center text-sm text-ink-muted">
          No members found matching the current filters.
        </div>
      )}

      {/* Member List */}
      {!isWorklistLoading && !worklistError && members.length > 0 && (
        <div className="space-y-4">
          {/* Desktop Table View */}
          <div className="hidden sm:block overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
            <table className="min-w-full divide-y divide-border text-left text-xs">
              <thead className="bg-surface-subtle font-medium text-ink-muted">
                <tr>
                  <th scope="col" className="w-12 px-4 py-3">
                    <input
                      type="checkbox"
                      checked={allPageSelected}
                      ref={(el) => {
                        if (el) el.indeterminate = somePageSelected && !allPageSelected;
                      }}
                      onChange={handleToggleSelectAllPage}
                      className="h-4 w-4 rounded border-border bg-surface text-primary focus:ring-accent"
                      title="Select all on this page"
                    />
                  </th>
                  <th scope="col" className="px-4 py-3">Name</th>
                  <th scope="col" className="px-4 py-3">Member #</th>
                  <th scope="col" className="px-4 py-3">Section</th>
                  <th scope="col" className="px-4 py-3">Current placement</th>
                  <th scope="col" className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border/60">
                {members.map((m) => {
                  const isSelected = selectedMembers.has(m.id);
                  const isDisabled = !isSelected && isMaxSelected;
                  return (
                    <tr
                      key={m.id}
                      className={`transition-colors ${
                        isSelected ? 'bg-primary/5' : 'hover:bg-surface-subtle/50'
                      }`}
                    >
                      <td className="px-4 py-3">
                        <input
                          type="checkbox"
                          checked={isSelected}
                          disabled={isDisabled}
                          onChange={() => handleToggleMember(m)}
                          className="h-4 w-4 rounded border-border bg-surface text-primary focus:ring-accent disabled:opacity-40"
                        />
                      </td>
                      <td className="px-4 py-3 font-medium">
                        <Link
                          to={`/app/members/${m.id}`}
                          className="text-primary hover:underline"
                        >
                          {m.display_name}
                        </Link>
                      </td>
                      <td className="px-4 py-3 font-mono text-ink-muted">
                        {m.member_number ?? '—'}
                      </td>
                      <td className="px-4 py-3 text-ink">
                        {m.section?.name ?? '—'}
                      </td>
                      <td className="px-4 py-3">
                        {formatPlacementDisplay(m.placement)}
                      </td>
                      <td className="px-4 py-3">
                        {m.membership_status ? (
                          <Badge variant="neutral">{m.membership_status.name}</Badge>
                        ) : (
                          '—'
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {/* Mobile Stacked Cards (< sm breakpoint) */}
          <div className="block sm:hidden space-y-3">
            <div className="flex items-center justify-between px-1">
              <label className="flex items-center gap-2 text-xs text-ink-muted">
                <input
                  type="checkbox"
                  checked={allPageSelected}
                  ref={(el) => {
                    if (el) el.indeterminate = somePageSelected && !allPageSelected;
                  }}
                  onChange={handleToggleSelectAllPage}
                  className="h-4 w-4 rounded border-border bg-surface text-primary focus:ring-accent"
                />
                <span>Select all on page</span>
              </label>
            </div>

            {members.map((m) => {
              const isSelected = selectedMembers.has(m.id);
              const isDisabled = !isSelected && isMaxSelected;
              return (
                <div
                  key={m.id}
                  className={`rounded-lg border p-3 transition-colors ${
                    isSelected
                      ? 'border-primary/40 bg-primary/5'
                      : 'border-border bg-surface'
                  }`}
                >
                  <div className="flex items-start gap-3">
                    <input
                      type="checkbox"
                      checked={isSelected}
                      disabled={isDisabled}
                      onChange={() => handleToggleMember(m)}
                      className="mt-0.5 h-4 w-4 rounded border-border bg-surface text-primary focus:ring-accent disabled:opacity-40"
                    />
                    <div className="min-w-0 flex-1 space-y-1">
                      <div className="flex items-center justify-between gap-2">
                        <Link
                          to={`/app/members/${m.id}`}
                          className="text-sm font-semibold text-primary hover:underline truncate"
                        >
                          {m.display_name}
                        </Link>
                        {m.membership_status && (
                          <Badge variant="neutral">{m.membership_status.name}</Badge>
                        )}
                      </div>
                      <div className="flex flex-wrap items-center gap-2 text-xs text-ink-muted">
                        {m.member_number && (
                          <span className="font-mono">{m.member_number}</span>
                        )}
                        {m.section?.name && (
                          <>
                            <span>·</span>
                            <span>{m.section.name}</span>
                          </>
                        )}
                      </div>
                      <div className="text-xs pt-1">
                        <span className="text-ink-muted">Placement: </span>
                        {formatPlacementDisplay(m.placement)}
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>

          {/* Pagination Controls */}
          <div className="flex items-center justify-between border-t border-border pt-4 text-xs text-ink-muted">
            <span>
              Page {page} of {totalPages} ({totalCount.toLocaleString()}{' '}
              {totalCount === 1 ? 'member' : 'members'})
            </span>
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={page <= 1}
              >
                Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={page >= totalPages}
              >
                Next
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Sticky Bottom Bar when at least 1 member is selected */}
      {selectedMembers.size > 0 && (
        <div className="fixed bottom-0 left-0 right-0 z-40 border-t border-border bg-surface/95 backdrop-blur-md shadow-lg">
          <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
            <div className="flex items-center gap-3">
              <span className="text-sm font-semibold text-ink">
                {selectedMembers.size}{' '}
                {selectedMembers.size === 1 ? 'member' : 'members'} selected
              </span>
              <button
                type="button"
                onClick={handleClearSelection}
                className="text-xs text-ink-muted underline hover:text-ink"
              >
                Clear
              </button>
            </div>
            <Button
              variant="primary"
              onClick={() => setIsModalOpen(true)}
            >
              Place selected…
            </Button>
          </div>
        </div>
      )}

      {/* Bulk Placement Modal */}
      {orgId && (
        <PlaceMembersModal
          isOpen={isModalOpen}
          onClose={() => setIsModalOpen(false)}
          organizationId={orgId}
          selectedMembers={selectedMembers}
          onPlacementComplete={handlePlacementComplete}
        />
      )}
    </div>
  );
}

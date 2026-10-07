import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useSearchHouseholds } from '../features/households/api/search-households';
import { CreateHouseholdModal } from '../features/households/components/CreateHouseholdModal';

function formatFrequency(freq: string | null): string {
  if (!freq) return 'Weekly';
  return freq.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatDayOfWeek(day: number | null): string | null {
  if (day === null || day === undefined) return null;
  const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  return days[day] ?? null;
}

export default function HouseholdsPage() {
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('active');
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const orgId = activeOrganization?.id ?? null;
  const canViewHouseholds = !isPermLoading && hasPermission(Permissions.HouseholdsRecordsView);
  const canCreateHouseholds = !isPermLoading && hasPermission(Permissions.HouseholdsRecordsCreate);

  const {
    data,
    isLoading,
    error,
  } = useSearchHouseholds(
    orgId,
    {
      search: searchTerm,
      lifecycleStatus: statusFilter === 'all' ? undefined : statusFilter,
    },
    canViewHouseholds
  );

  const triggerToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 5000);
  };

  if (!canViewHouseholds && !isPermLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="rounded-xl border border-line bg-surface p-6 text-center">
          <p className="text-sm text-ink-muted">
            You do not have permission to view household records.
          </p>
        </div>
      </div>
    );
  }

  const households = data?.households ?? [];
  const totalCount = data?.total_count ?? 0;

  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8 space-y-6">
      {/* Toast Notification */}
      {toastMessage && (
        <div className="flex items-center justify-between rounded-xl border border-success-600/30 bg-success-50 px-4 py-3 text-sm text-success-700 shadow-lg">
          <div className="flex items-center gap-2">
            <svg className="h-5 w-5 text-success-700" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
            </svg>
            <span>{toastMessage}</span>
          </div>
          <button
            onClick={() => setToastMessage(null)}
            className="text-xs text-success-700 hover:text-success-700"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* Header */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-ink">
            Pastoral Households
          </h1>
          <p className="text-sm text-ink-muted mt-1">
            Browse pastoral household groupings and placements across units and chapters.
          </p>
        </div>

        <div className="flex items-center gap-2 self-start sm:self-auto flex-wrap">
          <Link
            to="/app/households/unassigned"
            id="btn-unassigned-household-members"
            className="inline-flex items-center gap-2 rounded-lg border border-line bg-surface-muted px-3.5 py-2 text-xs font-semibold text-ink hover:bg-line hover:text-white transition-colors"
          >
            <svg className="h-4 w-4 text-primary-blue" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
            </svg>
            Unassigned Members
          </Link>

          {canCreateHouseholds && (
            <button
              type="button"
              id="btn-create-household"
              onClick={() => setIsCreateModalOpen(true)}
              className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-xs font-semibold text-white shadow-sm hover:bg-primary-hover transition-colors"
            >
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
              </svg>
              Create Household
            </button>
          )}
        </div>
      </div>

      {/* Filter bar */}
      <div className="flex flex-col sm:flex-row gap-3 items-stretch sm:items-center justify-between">
        <div className="relative flex-1 max-w-md">
          <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <svg className="h-4 w-4 text-ink-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
          <input
            type="text"
            id="household-search-input"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder="Search by household name or code…"
            className="w-full rounded-lg border border-line bg-surface py-2 pl-9 pr-4 text-sm text-ink placeholder-slate-500 focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus"
          />
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="status-filter" className="text-xs text-ink-muted">
            Status:
          </label>
          <select
            id="status-filter"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="rounded-lg border border-line bg-surface px-3 py-2 text-xs text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus"
          >
            <option value="active">Active</option>
            <option value="planned">Planned</option>
            <option value="temporarily_inactive">Temporarily Inactive</option>
            <option value="closed">Closed</option>
            <option value="merged">Merged</option>
            <option value="archived">Archived</option>
            <option value="all">All Statuses</option>
          </select>
        </div>
      </div>

      {/* Main Content */}
      {isLoading ? (
        <div className="space-y-3">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="h-20 animate-pulse rounded-xl bg-surface-muted border border-line" />
          ))}
        </div>
      ) : error ? (
        <div className="rounded-xl border border-danger-600/30 bg-danger-50 p-6 text-center text-sm text-danger-700">
          Failed to load households. Please try again.
        </div>
      ) : households.length === 0 ? (
        <div className="rounded-xl border border-line bg-surface p-12 text-center">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-surface-muted text-ink-muted">
            <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
            </svg>
          </div>
          <h2 className="mt-4 text-base font-semibold text-ink">
            No households have been created yet
          </h2>
          <p className="mt-1.5 text-xs text-ink-muted max-w-sm mx-auto">
            {searchTerm
              ? 'No households matched your search query. Try clearing filters.'
              : 'Pastoral households are formed under Chapters and Units to shepherd and group members into prayer and pastoral communities.'}
          </p>
          {!searchTerm && canCreateHouseholds && (
            <div className="mt-5">
              <button
                type="button"
                id="btn-create-first-household"
                onClick={() => setIsCreateModalOpen(true)}
                className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-xs font-semibold text-white shadow-sm hover:bg-primary-hover transition-colors"
              >
                <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
                </svg>
                Create the first household
              </button>
            </div>
          )}
        </div>
      ) : (
        <div className="rounded-xl border border-line bg-surface-muted overflow-hidden">
          <div className="border-b border-line px-5 py-3 text-xs text-ink-muted">
            Showing {households.length} of {totalCount} {totalCount === 1 ? 'household' : 'households'}
          </div>
          <div className="divide-y divide-line">
            {households.map((hh) => {
              const day = formatDayOfWeek(hh.meeting_day_of_week);
              const freq = formatFrequency(hh.meeting_frequency);
              const schedule = [freq, day, hh.meeting_start_time ? hh.meeting_start_time.slice(0, 5) : null]
                .filter(Boolean)
                .join(' • ');

              return (
                <div key={hh.household_id} className="p-4 sm:px-6 hover:bg-surface-muted transition-colors flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <Link
                        to={`/app/households/${hh.household_id}`}
                        className="text-base font-semibold text-ink hover:text-primary-blue transition-colors"
                      >
                        {hh.name}
                      </Link>
                      <span className="font-mono text-xs text-ink-muted">
                        {hh.code}
                      </span>
                      <span className="inline-flex items-center rounded-full border border-navy-100 bg-navy-50 px-2 py-0.5 text-[10px] font-medium text-primary-blue">
                        {hh.pastoral_level_label ?? (hh.pastoral_level ? `${hh.pastoral_level.toUpperCase()} HOUSEHOLD` : 'MEMBER HOUSEHOLD')}
                      </span>
                      <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
                        hh.lifecycle_status === 'active'
                          ? 'border-success-600/30 bg-success-50 text-success-700'
                          : 'border-line-strong bg-surface-muted text-ink-muted'
                      }`}>
                        {hh.lifecycle_status}
                      </span>
                    </div>

                    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-ink-muted">
                      {hh.parent_node_name && (
                        <span>
                          Parent: <span className="text-ink">{hh.parent_node_name}</span>
                          {hh.parent_node_type && (
                            <span className="ml-1 text-[10px] uppercase text-ink-muted">
                              ({hh.parent_node_type})
                            </span>
                          )}
                        </span>
                      )}
                      {schedule && (
                        <>
                          <span className="text-ink-muted">•</span>
                          <span>{schedule}</span>
                        </>
                      )}
                      {hh.meeting_location_type && (
                        <>
                          <span className="text-ink-muted">•</span>
                          <span className="capitalize">{hh.meeting_location_type}</span>
                        </>
                      )}
                    </div>
                  </div>

                  <div className="flex items-center gap-4 text-xs sm:text-right text-ink-muted">
                    <div>
                      <p className="text-ink font-medium">
                        {hh.active_member_count}{' '}
                        <span className="text-ink-muted font-normal">
                          {hh.target_member_count ? `/ ${hh.target_member_count}` : ''} members
                        </span>
                      </p>
                      <p className="text-[10px] text-ink-muted">
                        {hh.accepts_new_members ? 'Accepting members' : 'Capacity full'}
                      </p>
                    </div>
                    <Link
                      to={`/app/households/${hh.household_id}`}
                      className="rounded-lg border border-line bg-surface px-3 py-1.5 text-xs font-medium text-ink-secondary hover:bg-surface-muted hover:text-white transition-colors"
                    >
                      View
                    </Link>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Create Household Modal */}
      {canCreateHouseholds && orgId && isCreateModalOpen && (
        <CreateHouseholdModal
          isOpen={isCreateModalOpen}
          onClose={() => setIsCreateModalOpen(false)}
          organizationId={orgId}
          onSuccessToast={triggerToast}
        />
      )}
    </div>
  );
}

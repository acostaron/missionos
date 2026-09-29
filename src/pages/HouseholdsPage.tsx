import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useSearchHouseholds } from '../features/households/api/search-households';

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

  const orgId = activeOrganization?.id ?? null;
  const canViewHouseholds = !isPermLoading && hasPermission(Permissions.HouseholdsRecordsView);

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

  if (!canViewHouseholds && !isPermLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-6 text-center">
          <p className="text-sm text-slate-400">
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
      {/* Header */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-100">
            Pastoral Households
          </h1>
          <p className="text-sm text-slate-400 mt-1">
            Browse pastoral household groupings and placements across units and chapters.
          </p>
        </div>
      </div>

      {/* Filter bar */}
      <div className="flex flex-col sm:flex-row gap-3 items-stretch sm:items-center justify-between">
        <div className="relative flex-1 max-w-md">
          <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <svg className="h-4 w-4 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
          <input
            type="text"
            id="household-search-input"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder="Search by household name or code…"
            className="w-full rounded-lg border border-slate-700 bg-slate-900/60 py-2 pl-9 pr-4 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="status-filter" className="text-xs text-slate-400">
            Status:
          </label>
          <select
            id="status-filter"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-2 text-xs text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="active">Active</option>
            <option value="temporarily_inactive">Temporarily Inactive</option>
            <option value="archived">Archived</option>
            <option value="all">All Statuses</option>
          </select>
        </div>
      </div>

      {/* Main Content */}
      {isLoading ? (
        <div className="space-y-3">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="h-20 animate-pulse rounded-xl bg-slate-800/40 border border-slate-700/60" />
          ))}
        </div>
      ) : error ? (
        <div className="rounded-xl border border-red-900/40 bg-red-950/20 p-6 text-center text-sm text-red-300">
          Failed to load households. Please try again.
        </div>
      ) : households.length === 0 ? (
        <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-12 text-center">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-slate-800 text-slate-400">
            <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
            </svg>
          </div>
          <h2 className="mt-4 text-base font-semibold text-slate-200">
            No households have been created yet
          </h2>
          <p className="mt-1.5 text-xs text-slate-400 max-w-sm mx-auto">
            {searchTerm
              ? 'No households matched your search query. Try clearing filters.'
              : 'Pastoral households are formed under Chapters and Units to shepherd and group members into prayer and pastoral communities.'}
          </p>
        </div>
      ) : (
        <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
          <div className="border-b border-slate-700 px-5 py-3 text-xs text-slate-400">
            Showing {households.length} of {totalCount} {totalCount === 1 ? 'household' : 'households'}
          </div>
          <div className="divide-y divide-slate-700/60">
            {households.map((hh) => {
              const day = formatDayOfWeek(hh.meeting_day_of_week);
              const freq = formatFrequency(hh.meeting_frequency);
              const schedule = [freq, day, hh.meeting_start_time ? hh.meeting_start_time.slice(0, 5) : null]
                .filter(Boolean)
                .join(' • ');

              return (
                <div key={hh.household_id} className="p-4 sm:px-6 hover:bg-slate-800/40 transition-colors flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <Link
                        to={`/app/households/${hh.household_id}`}
                        className="text-base font-semibold text-slate-100 hover:text-indigo-400 transition-colors"
                      >
                        {hh.name}
                      </Link>
                      <span className="font-mono text-xs text-slate-400">
                        {hh.code}
                      </span>
                      <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
                        hh.lifecycle_status === 'active'
                          ? 'border-emerald-700/60 bg-emerald-950/40 text-emerald-300'
                          : 'border-slate-600 bg-slate-800 text-slate-400'
                      }`}>
                        {hh.lifecycle_status}
                      </span>
                    </div>

                    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-400">
                      {hh.parent_node_name && (
                        <span>
                          Parent: <span className="text-slate-200">{hh.parent_node_name}</span>
                          {hh.parent_node_type && (
                            <span className="ml-1 text-[10px] uppercase text-slate-500">
                              ({hh.parent_node_type})
                            </span>
                          )}
                        </span>
                      )}
                      {schedule && (
                        <>
                          <span className="text-slate-600">•</span>
                          <span>{schedule}</span>
                        </>
                      )}
                      {hh.meeting_location_type && (
                        <>
                          <span className="text-slate-600">•</span>
                          <span className="capitalize">{hh.meeting_location_type}</span>
                        </>
                      )}
                    </div>
                  </div>

                  <div className="flex items-center gap-4 text-xs sm:text-right text-slate-400">
                    <div>
                      <p className="text-slate-200 font-medium">
                        {hh.active_member_count}{' '}
                        <span className="text-slate-500 font-normal">
                          {hh.target_member_count ? `/ ${hh.target_member_count}` : ''} members
                        </span>
                      </p>
                      <p className="text-[10px] text-slate-500">
                        {hh.accepts_new_members ? 'Accepting members' : 'Capacity full'}
                      </p>
                    </div>
                    <Link
                      to={`/app/households/${hh.household_id}`}
                      className="rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-1.5 text-xs font-medium text-slate-300 hover:bg-slate-800 hover:text-white transition-colors"
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
    </div>
  );
}

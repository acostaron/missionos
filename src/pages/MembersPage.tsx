import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { useSearchMembers } from '../features/members/queries';
import type { MemberListItem } from '../features/members/queries';

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function SearchBar({
  value,
  onChange,
  isLoading,
}: {
  value: string;
  onChange: (v: string) => void;
  isLoading: boolean;
}) {
  return (
    <div className="relative">
      <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
        {isLoading ? (
          <svg
            className="h-4 w-4 animate-spin text-indigo-400"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8v8z"
            />
          </svg>
        ) : (
          <svg
            className="h-4 w-4 text-slate-400"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M21 21l-4.35-4.35M17 11A6 6 0 111 11a6 6 0 0116 0z"
            />
          </svg>
        )}
      </div>
      <input
        id="member-search"
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="Search by name…"
        maxLength={200}
        className="block w-full rounded-lg border border-slate-700 bg-slate-800 py-2 pl-9 pr-4 text-sm text-slate-100 placeholder-slate-400 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
      />
    </div>
  );
}

function StatusBadge({ status }: { status: MemberListItem['membership_status'] }) {
  if (!status) return null;

  const isActive = status.is_active_membership;
  const bg = isActive
    ? 'bg-emerald-900/50 text-emerald-300 border-emerald-700'
    : 'bg-slate-800 text-slate-400 border-slate-600';

  return (
    <span
      className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium ${bg}`}
    >
      {status.name}
    </span>
  );
}

function MemberRow({ member }: { member: MemberListItem }) {
  const initials = member.display_name
    .split(' ')
    .map((w: string) => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();

  return (
    <Link
      to={`/app/members/${member.id}`}
      id={`member-row-${member.id}`}
      className="group flex items-center gap-4 rounded-lg border border-slate-700 bg-slate-800/60 px-4 py-3 transition-all hover:border-indigo-600 hover:bg-slate-800"
    >
      {/* Avatar */}
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-indigo-900 text-sm font-semibold text-indigo-200">
        {initials}
      </div>

      {/* Name + status */}
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-slate-100 group-hover:text-white">
          {member.display_name}
        </p>
        {member.preferred_name && member.preferred_name !== member.display_name && (
          <p className="truncate text-xs text-slate-400">
            Preferred: {member.preferred_name}
          </p>
        )}
      </div>

      {/* Member number — only when permission allows */}
      <div className="w-28 shrink-0 text-right">
        {member.member_number !== null ? (
          <span className="font-mono text-xs text-slate-300">{member.member_number}</span>
        ) : null}
      </div>

      {/* Membership status */}
      <div className="w-28 shrink-0 text-right">
        <StatusBadge status={member.membership_status} />
      </div>

      {/* Chevron */}
      <svg
        className="h-4 w-4 shrink-0 text-slate-500 transition-colors group-hover:text-indigo-400"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
        strokeWidth={2}
      >
        <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
      </svg>
    </Link>
  );
}

function Pagination({
  page,
  pageSize,
  totalCount,
  onPage,
  isFetching,
}: {
  page: number;
  pageSize: number;
  totalCount: number;
  onPage: (p: number) => void;
  isFetching: boolean;
}) {
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));
  const start = totalCount === 0 ? 0 : (page - 1) * pageSize + 1;
  const end = Math.min(page * pageSize, totalCount);

  return (
    <div className="flex items-center justify-between text-sm text-slate-400">
      <span>
        {totalCount === 0
          ? 'No members'
          : `${start}–${end} of ${totalCount.toLocaleString()} member${totalCount !== 1 ? 's' : ''}`}
        {isFetching && (
          <span className="ml-2 inline-block animate-pulse text-indigo-400">
            updating…
          </span>
        )}
      </span>

      <div className="flex items-center gap-2">
        <button
          id="members-prev-page"
          onClick={() => onPage(page - 1)}
          disabled={page <= 1}
          className="rounded border border-slate-700 px-3 py-1 text-xs font-medium text-slate-300 transition-colors hover:border-indigo-500 hover:text-indigo-300 disabled:cursor-not-allowed disabled:opacity-40"
        >
          ← Prev
        </button>
        <span className="text-xs">
          Page {page} / {totalPages}
        </span>
        <button
          id="members-next-page"
          onClick={() => onPage(page + 1)}
          disabled={page >= totalPages}
          className="rounded border border-slate-700 px-3 py-1 text-xs font-medium text-slate-300 transition-colors hover:border-indigo-500 hover:text-indigo-300 disabled:cursor-not-allowed disabled:opacity-40"
        >
          Next →
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

const PAGE_SIZE = 50;

export default function MembersPage() {
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;

  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [page, setPage] = useState(1);

  // Debounce search: wait 300ms after user stops typing, reset to page 1
  const handleSearchChange = useCallback((value: string) => {
    setSearch(value);
    setPage(1);

    // Simple manual debounce via a closure timeout
    const timer = setTimeout(() => {
      setDebouncedSearch(value);
    }, 300);

    return () => clearTimeout(timer);
  }, []);

  const { data, isLoading, isFetching, error } = useSearchMembers(orgId, {
    search: debouncedSearch || undefined,
    page,
    pageSize: PAGE_SIZE,
  });

  // -------------------------------------------------------------------------
  // Loading state
  // -------------------------------------------------------------------------
  if (isOrgLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center">
        <div className="text-sm text-slate-400">Loading organization…</div>
      </div>
    );
  }

  if (!orgId) {
    return (
      <div className="rounded-lg border border-red-700 bg-red-900/20 p-6 text-red-300">
        No active organization. Cannot load member directory.
      </div>
    );
  }

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------
  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-slate-100">
          Member Directory
        </h1>
        <p className="mt-1 text-sm text-slate-400">
          {activeOrganization?.name ?? 'Your organization'} ·{' '}
          {data ? `${data.total_count.toLocaleString()} active member${data.total_count !== 1 ? 's' : ''}` : '…'}
        </p>
      </div>

      {/* Search */}
      <SearchBar
        value={search}
        onChange={handleSearchChange}
        isLoading={isFetching && !!debouncedSearch}
      />

      {/* Error */}
      {error && (
        <div className="rounded-lg border border-red-700 bg-red-900/20 p-4">
          <p className="text-sm font-medium text-red-300">
            Failed to load members:{' '}
            {(error as { message?: string }).message ?? 'Unknown error'}
          </p>
        </div>
      )}

      {/* Skeleton */}
      {isLoading && !data && (
        <div className="space-y-2">
          {Array.from({ length: 8 }).map((_, i) => (
            <div
              key={i}
              className="h-14 animate-pulse rounded-lg bg-slate-800"
            />
          ))}
        </div>
      )}

      {/* Empty state */}
      {!isLoading && !error && data && data.members.length === 0 && (
        <div className="flex min-h-[20vh] flex-col items-center justify-center gap-3 text-center">
          <svg
            className="h-12 w-12 text-slate-600"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={1.5}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M17 20h5v-1a7 7 0 00-10.29-6.18M9 11a4 4 0 100-8 4 4 0 000 8zm-7 9v-1a7 7 0 0110.29-6.18"
            />
          </svg>
          <p className="text-sm text-slate-400">
            {debouncedSearch
              ? `No members matching "${debouncedSearch}"`
              : 'No active members in this organization.'}
          </p>
          {debouncedSearch && (
            <button
              onClick={() => {
                setSearch('');
                setDebouncedSearch('');
              }}
              className="text-xs text-indigo-400 underline hover:text-indigo-300"
            >
              Clear search
            </button>
          )}
        </div>
      )}

      {/* Member list */}
      {data && data.members.length > 0 && (
        <>
          {/* Column headers */}
          <div className="flex items-center gap-4 px-4 text-xs font-medium uppercase tracking-wider text-slate-500">
            <div className="w-10 shrink-0" aria-hidden />
            <div className="flex-1">Name</div>
            <div className="w-28 shrink-0 text-right">Member #</div>
            <div className="w-28 shrink-0 text-right">Status</div>
            <div className="w-4 shrink-0" aria-hidden />
          </div>

          <div className="space-y-1.5">
            {data.members.map((m: MemberListItem) => (
            <MemberRow key={m.id} member={m} />
            ))}
          </div>

          <Pagination
            page={page}
            pageSize={PAGE_SIZE}
            totalCount={data.total_count}
            onPage={setPage}
            isFetching={isFetching}
          />
        </>
      )}
    </div>
  );
}

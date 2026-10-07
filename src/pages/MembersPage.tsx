import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useSearchMembers } from '../features/members/queries';
import type { MemberListItem } from '../features/members/queries';
import { CreateFamilyModal } from '../features/families/components/CreateFamilyModal';

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
            className="h-4 w-4 animate-spin text-primary-blue"
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
            className="h-4 w-4 text-ink-muted"
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
        className="block w-full rounded-lg border border-line bg-surface-muted py-2 pl-9 pr-4 text-sm text-ink placeholder-slate-400 focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus"
      />
    </div>
  );
}

function StatusBadge({ status }: { status: MemberListItem['membership_status'] }) {
  if (!status) return null;

  const isActive = status.is_active_membership;
  const bg = isActive
    ? 'bg-success-50 text-success-700 border-success-600'
    : 'bg-surface-muted text-ink-muted border-line-strong';

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
      className="group flex items-center gap-4 rounded-lg border border-line bg-surface-muted px-4 py-3 transition-all hover:border-primary-blue hover:bg-surface-muted"
    >
      {/* Avatar */}
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-navy-50 text-sm font-semibold text-primary-blue">
        {initials}
      </div>

      {/* Name + status */}
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-ink group-hover:text-white">
          {member.display_name}
        </p>
        {member.preferred_name && member.preferred_name !== member.display_name && (
          <p className="truncate text-xs text-ink-muted">
            Preferred: {member.preferred_name}
          </p>
        )}
      </div>

      {/* Member number — only when permission allows */}
      <div className="w-28 shrink-0 text-right">
        {member.member_number !== null ? (
          <span className="font-mono text-xs text-ink-secondary">{member.member_number}</span>
        ) : null}
      </div>

      {/* Membership status */}
      <div className="w-28 shrink-0 text-right">
        <StatusBadge status={member.membership_status} />
      </div>

      {/* Chevron */}
      <svg
        className="h-4 w-4 shrink-0 text-ink-muted transition-colors group-hover:text-primary-blue"
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
    <div className="flex items-center justify-between text-sm text-ink-muted">
      <span>
        {totalCount === 0
          ? 'No members'
          : `${start}–${end} of ${totalCount.toLocaleString()} member${totalCount !== 1 ? 's' : ''}`}
        {isFetching && (
          <span className="ml-2 inline-block animate-pulse text-primary-blue">
            updating…
          </span>
        )}
      </span>

      <div className="flex items-center gap-2">
        <button
          id="members-prev-page"
          onClick={() => onPage(page - 1)}
          disabled={page <= 1}
          className="rounded border border-line px-3 py-1 text-xs font-medium text-ink-secondary transition-colors hover:border-primary-blue hover:text-primary-blue disabled:cursor-not-allowed disabled:opacity-40"
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
          className="rounded border border-line px-3 py-1 text-xs font-medium text-ink-secondary transition-colors hover:border-primary-blue hover:text-primary-blue disabled:cursor-not-allowed disabled:opacity-40"
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
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const orgId = activeOrganization?.id ?? null;

  const canCreateMember = !isPermLoading && hasPermission(Permissions.MembersRecordsCreate);
  const canCreateFamily = !isPermLoading && hasPermission(Permissions.FamiliesRecordsCreate);

  const [isCreateFamilyOpen, setIsCreateFamilyOpen] = useState(false);
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
        <div className="text-sm text-ink-muted">Loading organization…</div>
      </div>
    );
  }

  if (!orgId) {
    return (
      <div className="rounded-lg border border-danger-600 bg-danger-50 p-6 text-danger-700">
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
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-ink">
            Member Directory
          </h1>
          <p className="mt-1 text-sm text-ink-muted">
            {activeOrganization?.name ?? 'Your organization'} ·{' '}
            {data ? `${data.total_count.toLocaleString()} active member${data.total_count !== 1 ? 's' : ''}` : '…'}
          </p>
        </div>

        <div className="flex items-center gap-3">
          {canCreateFamily && (
            <button
              type="button"
              onClick={() => setIsCreateFamilyOpen(true)}
              id="create-family-button"
              className="inline-flex items-center justify-center gap-2 rounded-lg border border-line bg-surface-muted px-4 py-2 text-sm font-medium text-ink shadow-sm hover:bg-line hover:text-white focus:outline-none focus:ring-2 focus:ring-focus focus:ring-offset-2 focus:ring-offset-slate-900 transition-colors"
            >
              <svg
                className="h-4 w-4 text-ink-muted"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                strokeWidth={2}
              >
                <path strokeLinecap="round" strokeLinejoin="round" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
              </svg>
              Create Family
            </button>
          )}

          {canCreateMember && (
            <Link
              to="/app/members/new"
              id="add-member-button"
              className="inline-flex items-center justify-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary-hover focus:outline-none focus:ring-2 focus:ring-focus focus:ring-offset-2 focus:ring-offset-slate-900 transition-colors"
            >
              <svg
                className="h-4 w-4"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                strokeWidth={2}
              >
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
              </svg>
              Add Member
            </Link>
          )}
        </div>
      </div>

      {/* Search */}
      <SearchBar
        value={search}
        onChange={handleSearchChange}
        isLoading={isFetching && !!debouncedSearch}
      />

      {/* Error */}
      {error && (
        <div className="rounded-lg border border-danger-600 bg-danger-50 p-4">
          <p className="text-sm font-medium text-danger-700">
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
              className="h-14 animate-pulse rounded-lg bg-surface-muted"
            />
          ))}
        </div>
      )}

      {/* Empty state */}
      {!isLoading && !error && data && data.members.length === 0 && (
        <div className="flex min-h-[20vh] flex-col items-center justify-center gap-3 text-center">
          <svg
            className="h-12 w-12 text-ink-muted"
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
          <p className="text-sm text-ink-muted">
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
              className="text-xs text-primary-blue underline hover:text-primary-blue"
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
          <div className="flex items-center gap-4 px-4 text-xs font-medium uppercase tracking-wider text-ink-muted">
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

      {/* Create Family Modal */}
      {canCreateFamily && orgId && (
        <CreateFamilyModal
          isOpen={isCreateFamilyOpen}
          onClose={() => setIsCreateFamilyOpen(false)}
          organizationId={orgId}
        />
      )}
    </div>
  );
}

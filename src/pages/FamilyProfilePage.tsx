import { useParams, Link, Navigate } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useFamilyProfile } from '../features/families/api/get-family-profile';
import { FamilyMemberRoster } from '../features/families/components/FamilyMemberRoster';
import { FamilyRelationshipList } from '../features/families/components/FamilyRelationshipList';

function formatFamilyType(type: string | null): string {
  if (!type) return 'Family';
  return type
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export default function FamilyProfilePage() {
  const { familyId } = useParams<{ familyId: string }>();
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const orgId = activeOrganization?.id ?? null;

  const canViewFamilies = !isPermLoading && hasPermission(Permissions.FamiliesRecordsView);
  const canViewRelationships = !isPermLoading && hasPermission(Permissions.FamiliesRelationshipsView);

  const {
    data: profile,
    isLoading,
    error,
  } = useFamilyProfile(orgId, familyId ?? null, canViewFamilies);

  if (!familyId) {
    return <Navigate to="/app/members" replace />;
  }

  // Loading skeleton
  if (isOrgLoading || isLoading || isPermLoading) {
    return (
      <div className="space-y-6">
        <div className="h-4 w-32 animate-pulse rounded bg-slate-800" />
        <div className="h-20 w-80 animate-pulse rounded-xl bg-slate-800" />
        <div className="h-48 animate-pulse rounded-xl bg-slate-800" />
        <div className="h-48 animate-pulse rounded-xl bg-slate-800" />
      </div>
    );
  }

  // Access denied on page level
  if (!canViewFamilies) {
    return (
      <div className="space-y-6">
        <Link
          to="/app/members"
          id="family-profile-back"
          className="inline-flex items-center gap-1.5 text-sm text-slate-400 hover:text-slate-200"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Member Directory
        </Link>

        <div className="rounded-xl border border-red-700 bg-red-900/20 p-6">
          <h2 className="mb-2 text-base font-semibold text-red-300">
            Access Denied
          </h2>
          <p className="text-sm text-red-400">
            You do not have permission to view family records.
          </p>
        </div>
      </div>
    );
  }

  // Not found or error loading profile
  if (error || !profile) {
    return (
      <div className="space-y-6">
        <Link
          to="/app/members"
          id="family-profile-back"
          className="inline-flex items-center gap-1.5 text-sm text-slate-400 hover:text-slate-200"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Member Directory
        </Link>

        <div className="rounded-xl border border-red-700 bg-red-900/20 p-6">
          <h2 className="mb-2 text-base font-semibold text-red-300">
            Family Record Unavailable
          </h2>
          <p className="text-sm text-red-400">
            Family record not found or unavailable.
          </p>
        </div>
      </div>
    );
  }

  const { family, members, relationships } = profile;

  const familyName =
    family.display_name?.trim() ||
    family.family_name?.trim() ||
    'Family record';

  const familyTypeLabel = formatFamilyType(family.family_type);
  const isStatusActive = family.family_status === 'active';
  const statusLabel = family.family_status
    ? family.family_status.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
    : 'Active';

  const initials = familyName
    .split(' ')
    .map((w: string) => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase() || 'FA';

  return (
    <div className="space-y-6">
      {/* Navigation / Breadcrumb */}
      <nav className="flex items-center gap-2 text-sm text-slate-400">
        <Link
          to="/app/members"
          id="family-profile-back"
          className="hover:text-slate-200 transition-colors"
        >
          Members
        </Link>
        <span className="text-slate-600">/</span>
        <span className="text-slate-200 font-medium">{familyName}</span>
      </nav>

      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 rounded-xl border border-slate-700 bg-slate-800/80 p-5 shadow-sm">
        <div className="flex items-center gap-5">
          <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-indigo-900 text-xl font-bold text-indigo-200">
            {initials}
          </div>
          <div>
            <h1 className="text-2xl font-bold tracking-tight text-slate-100">
              {familyName}
            </h1>
            <div className="mt-1.5 flex items-center gap-2.5 flex-wrap">
              <span
                className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${
                  isStatusActive
                    ? 'border-emerald-700/60 bg-emerald-950/40 text-emerald-300'
                    : 'border-slate-600 bg-slate-800 text-slate-400'
                }`}
              >
                {statusLabel}
              </span>
              <span className="inline-flex items-center rounded-full border border-slate-600 bg-slate-800/80 px-2.5 py-0.5 text-xs font-medium text-slate-300">
                {familyTypeLabel}
              </span>
              <span className="text-xs text-slate-400">
                {members.length} {members.length === 1 ? 'member' : 'members'}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Family Member Roster */}
      <FamilyMemberRoster members={members} />

      {/* Family Relationships */}
      <FamilyRelationshipList
        relationships={relationships}
        members={members}
        canViewRelationships={canViewRelationships}
      />
    </div>
  );
}

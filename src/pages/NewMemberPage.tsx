import { Link } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { MemberOnboardingWizard } from '../features/members/components/MemberOnboardingWizard';
import PageLoadingFallback from '../components/ui/PageLoadingFallback';

export default function NewMemberPage() {
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const isLoading = isOrgLoading || isPermLoading;

  if (isLoading) {
    return <PageLoadingFallback />;
  }

  const canCreateRecord = hasPermission(Permissions.MembersRecordsCreate);

  // If not authorized to create records, render standard access-denied state
  if (!canCreateRecord) {
    return (
      <div className="space-y-6">
        <Link
          to="/app/members"
          className="inline-flex items-center gap-1.5 text-sm text-ink-muted hover:text-ink"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Member Directory
        </Link>

        <div className="rounded-xl border border-danger-600 bg-danger-50 p-6">
          <h2 className="mb-2 text-base font-semibold text-danger-700">Access Denied</h2>
          <p className="text-sm text-danger-700">
            You do not have permission to create member records in this organization.
          </p>
        </div>
      </div>
    );
  }

  if (!activeOrganization) {
    return (
      <div className="rounded-xl border border-danger-600 bg-danger-50 p-6 text-danger-700">
        No active organization selected.
      </div>
    );
  }

  // Permission flags for optional onboarding modules
  const canManageIdentifiers = hasPermission(Permissions.MembersIdentifiersManage);
  const canManagePlacements = hasPermission(Permissions.MembersPlacementsManage);
  const canManageContacts = hasPermission(Permissions.MembersContactsManage);
  const canManageAddresses = hasPermission(Permissions.MembersAddressesManage);
  const canViewStructure = hasPermission(Permissions.GovernanceStructureView);

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      {/* Header & Back Link */}
      <div>
        <Link
          to="/app/members"
          id="back-to-directory"
          className="inline-flex items-center gap-1.5 text-sm text-ink-muted hover:text-ink transition-colors mb-3"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Member Directory
        </Link>

        <h1 className="text-2xl font-bold tracking-tight text-ink">
          Onboard New Member
        </h1>
        <p className="mt-1 text-sm text-ink-muted">
          {activeOrganization.name} · Fill in member information below to create a canonical profile.
        </p>
      </div>

      {/* Main Form Wizard Container */}
      <div className="rounded-2xl border border-line bg-surface p-6 sm:p-8">
        <MemberOnboardingWizard
          organizationId={activeOrganization.id}
          canManageIdentifiers={canManageIdentifiers}
          canManagePlacements={canManagePlacements}
          canManageContacts={canManageContacts}
          canManageAddresses={canManageAddresses}
          canViewStructure={canViewStructure}
        />
      </div>
    </div>
  );
}

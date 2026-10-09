import { useCurrentProfile } from '../hooks/use-current-profile';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { usePermissions } from '../hooks/use-permissions';
import { useAuth } from '../hooks/use-auth';
import { Permissions } from '../types/permissions';
import { Alert, Skeleton } from '../components/ui';
import LeaderHome from '../features/home/components/LeaderHome';
import MemberHome from '../features/home/components/MemberHome';
import PendingInvitationNotice from '../features/home/components/PendingInvitationNotice';
import { ORGANIZATION_ADMINISTRATOR_ROLE_CODE } from '../features/home/role-labels';

/**
 * Home. Capability-driven: users with the existing
 * leadership.pastoral_dashboard.view permission get the operational Home;
 * everyone else gets the Member Home. No role hierarchy is derived.
 */
export default function DashboardPage() {
  const { user } = useAuth();
  const { profile, isLoading: isProfileLoading } = useCurrentProfile();
  const { organization, membership, isLoading: isOrgLoading } = useCurrentOrganization();
  const { roles, hasPermission, isLoading: isAuthLoading } = usePermissions();

  if (isProfileLoading || isOrgLoading || isAuthLoading) {
    return (
      <div className="space-y-6" aria-busy="true">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-24" />
        <Skeleton className="h-40" />
      </div>
    );
  }

  if (!membership || !organization) {
    return (
      <div className="space-y-6">
        <PendingInvitationNotice />
        <Alert variant="warning" title="No active organization membership">
          You do not have an active membership in any organization. Please contact your administrator.
        </Alert>
      </div>
    );
  }

  const fullName = profile?.display_name || user?.email || 'friend';
  const firstName = profile?.display_name ? profile.display_name.split(' ')[0] : fullName;
  const isOrgAdmin = roles.some(
    (r) => r.role_code === ORGANIZATION_ADMINISTRATOR_ROLE_CODE && r.assignment_status === 'active',
  );

  return (
    <div className="space-y-6">
      <PendingInvitationNotice />
      {hasPermission(Permissions.LeadershipPastoralDashboardView) ? (
        <LeaderHome
          organizationId={organization.id}
          organizationName={organization.name}
          firstName={firstName}
          isOrgAdmin={isOrgAdmin}
        />
      ) : (
        <MemberHome
          organizationId={organization.id}
          organizationName={organization.name}
          firstName={firstName}
        />
      )}
    </div>
  );
}

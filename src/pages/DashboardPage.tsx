import { useAuth } from '../hooks/use-auth';
import { useCurrentProfile } from '../hooks/use-current-profile';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { usePermissions } from '../hooks/use-permissions';
import { useCurrentMember } from '../hooks/use-current-member';

export default function DashboardPage() {
  const { user } = useAuth();
  const { profile, isLoading: isProfileLoading } = useCurrentProfile();
  const { organization, membership, isLoading: isOrgLoading } = useCurrentOrganization();
  const { roles, scopes, permissions, isLoading: isAuthLoading } = usePermissions();
  const { memberLink, isLoading: isMemberLoading } = useCurrentMember();

  const isLoading = isProfileLoading || isOrgLoading || isAuthLoading || isMemberLoading;

  if (isLoading) {
    return <div>Loading dashboard context...</div>;
  }

  if (!membership) {
    return (
      <div className="bg-red-50 text-red-800 p-6 rounded-lg border border-red-200">
        <h2 className="text-xl font-bold mb-2">Access Denied</h2>
        <p>You do not have an active membership in any organization. Please contact your administrator.</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="bg-white shadow rounded-lg p-6">
        <h2 className="text-xl font-bold mb-4">Dashboard</h2>
        <p className="text-gray-600 mb-6">
          Welcome, {profile?.display_name || user?.email}.
        </p>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="border rounded p-4">
            <h3 className="font-semibold mb-2 text-gray-700">Identity Status</h3>
            <ul className="text-sm space-y-1">
              <li><span className="font-medium">Connection:</span> Connected</li>
              <li><span className="font-medium">Auth UUID:</span> {user?.id}</li>
              <li><span className="font-medium">Profile UUID:</span> {profile?.id}</li>
              <li><span className="font-medium">Member ID:</span> {memberLink ? memberLink.member_id : 'Not Linked'}</li>
            </ul>
          </div>
          
          <div className="border rounded p-4">
            <h3 className="font-semibold mb-2 text-gray-700">Organization Context</h3>
            <ul className="text-sm space-y-1">
              <li><span className="font-medium">Active Org:</span> {organization?.name} ({organization?.code})</li>
              <li><span className="font-medium">Status:</span> {membership?.membership_status}</li>
              <li><span className="font-medium">Roles:</span> {roles.length > 0 ? roles.map(r => r.role_name).join(', ') : 'None'}</li>
              <li><span className="font-medium">Effective Permissions:</span> {permissions.length}</li>
            </ul>
          </div>
        </div>
      </div>
      
      {/* Dev Diagnostic Panel */}
      {import.meta.env.DEV && (
        <div className="bg-gray-800 text-gray-300 shadow rounded-lg p-6 font-mono text-xs">
          <h2 className="text-lg font-bold text-white mb-4">Diagnostics (DEV ONLY)</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <h3 className="font-bold text-gray-400 mb-1">Roles</h3>
              <pre>{JSON.stringify(roles, null, 2)}</pre>
            </div>
            <div>
              <h3 className="font-bold text-gray-400 mb-1">Scopes</h3>
              <pre>{JSON.stringify(scopes, null, 2)}</pre>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

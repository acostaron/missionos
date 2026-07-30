import { useOrganizationContext } from './use-organization-context';
import { useAuthorizationContextQuery } from '../features/authorization/queries';
import type { PermissionCode } from '../types/permissions';

export function usePermissions() {
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const { data: authContext, isLoading: isAuthLoading } = useAuthorizationContextQuery(activeOrganization?.id ?? null);

  const permissions = authContext?.permissions ?? [];
  const roles = authContext?.roles ?? [];
  const scopes = authContext?.scopes ?? [];

  const hasPermission = (code: PermissionCode): boolean => {
    const perm = permissions.find(p => p.code === code);
    return perm?.state === 'allow';
  };

  const hasAnyPermission = (codes: PermissionCode[]): boolean => {
    return codes.some(code => {
      const perm = permissions.find(p => p.code === code);
      return perm?.state === 'allow';
    });
  };

  const hasAllPermissions = (codes: PermissionCode[]): boolean => {
    return codes.length > 0 && codes.every(code => {
      const perm = permissions.find(p => p.code === code);
      return perm?.state === 'allow';
    });
  };

  return {
    permissions,
    roles,
    scopes,
    hasPermission,
    hasAnyPermission,
    hasAllPermissions,
    isLoading: isOrgLoading || isAuthLoading,
  };
}

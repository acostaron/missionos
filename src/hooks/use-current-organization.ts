import { useOrganizationContext } from './use-organization-context';

export function useCurrentOrganization() {
  const { activeOrganization, activeMembership, isLoading } = useOrganizationContext();
  return { organization: activeOrganization, membership: activeMembership, isLoading };
}

import { useProfileContextQuery } from '../features/identity/queries';
import { useOrganizationContext } from './use-organization-context';

export function useCurrentMember() {
  const { data: profileContext, isLoading: profileLoading } = useProfileContextQuery();
  const { activeOrganization, isLoading: orgLoading } = useOrganizationContext();

  const currentOrgId = activeOrganization?.id;
  const memberLink = profileContext?.member_links?.find(link => link.organization_id === currentOrgId) || null;

  return {
    memberLink,
    isLoading: profileLoading || orgLoading,
  };
}

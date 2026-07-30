import { useState, useEffect, useMemo } from 'react';
import type { ReactNode } from 'react';
import { useProfileContextQuery } from '../features/identity/queries';
import { OrganizationContext } from '../hooks/use-organization-context';

export function OrganizationProvider({ children }: { children: ReactNode }) {
  const { data, isLoading } = useProfileContextQuery();
  const [selectedOrgId, setSelectedOrgId] = useState<string | null>(null);

  const availableMemberships = useMemo(() => data?.memberships ?? [], [data?.memberships]);
  
  useEffect(() => {
    // If we have memberships but no selection, auto-select
    if (availableMemberships.length > 0 && !selectedOrgId) {
      const defaultOrg = availableMemberships.find(m => m.is_default);
      if (defaultOrg) {
        setSelectedOrgId(defaultOrg.organization_id);
      } else if (availableMemberships.length === 1) {
        setSelectedOrgId(availableMemberships[0].organization_id);
      }
    }
  }, [availableMemberships, selectedOrgId]);

  // Validate the selected org against active memberships
  const activeMembership = availableMemberships.find(m => m.organization_id === selectedOrgId) || null;
  const activeOrganization = activeMembership?.organization || null;

  return (
    <OrganizationContext.Provider value={{
      activeOrganization,
      activeMembership,
      availableMemberships,
      setActiveOrganizationId: setSelectedOrgId,
      isLoading
    }}>
      {children}
    </OrganizationContext.Provider>
  );
}

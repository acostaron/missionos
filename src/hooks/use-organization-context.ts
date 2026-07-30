import { createContext, useContext } from 'react';
import type { CurrentOrganization, OrganizationMembership } from '../types/auth';

export type OrganizationContextValue = {
  activeOrganization: CurrentOrganization | null;
  activeMembership: OrganizationMembership | null;
  availableMemberships: OrganizationMembership[];
  setActiveOrganizationId: (id: string) => void;
  isLoading: boolean;
};

export const OrganizationContext = createContext<OrganizationContextValue | undefined>(undefined);

export function useOrganizationContext() {
  const context = useContext(OrganizationContext);
  if (context === undefined) {
    throw new Error('useOrganizationContext must be used within OrganizationProvider');
  }
  return context;
}

import { Home, Users, Layers, House, HeartHandshake, BookOpen } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { Permissions } from '../../types/permissions';
import type { PermissionCode } from '../../types/permissions';

export type NavItem = {
  /** Stable element id (preserved for test compatibility). */
  id: string;
  label: string;
  /** Short label for the mobile bottom bar. */
  shortLabel: string;
  to: string;
  icon: LucideIcon;
  /** Existing permission gate; undefined = any authenticated user. */
  permission?: PermissionCode;
};

/**
 * Primary navigation. Only domains with real routes are listed.
 * Reserved (not yet implemented): Events & Mission,
 * Finance, Administration.
 */
export const NAV_ITEMS: NavItem[] = [
  { id: 'nav-dashboard', label: 'Home', shortLabel: 'Home', to: '/app/dashboard', icon: Home },
  {
    id: 'nav-members',
    label: 'People',
    shortLabel: 'People',
    to: '/app/members',
    icon: Users,
    permission: Permissions.MembersRecordsView,
  },
  {
    id: 'nav-sections',
    label: 'Sections',
    shortLabel: 'Sections',
    to: '/app/sections',
    icon: Layers,
    permission: Permissions.MembersRecordsView,
  },
  {
    id: 'nav-households',
    label: 'Households',
    shortLabel: 'Households',
    to: '/app/households',
    icon: House,
    permission: Permissions.HouseholdsRecordsView,
  },
  {
    id: 'nav-formation',
    label: 'Formation',
    shortLabel: 'Formation',
    to: '/app/formation',
    icon: BookOpen,
    permission: Permissions.FormationCatalogView,
  },
  {
    id: 'nav-pastoral-operations',
    label: 'Pastoral Care',
    shortLabel: 'Pastoral',
    to: '/app/pastoral-operations',
    icon: HeartHandshake,
    permission: Permissions.LeadershipPastoralDashboardView,
  },
];

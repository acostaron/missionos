import { Home, Users, House, HeartHandshake } from 'lucide-react';
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
 * Reserved (not yet implemented): Formation, Events & Mission, Groups,
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
    id: 'nav-households',
    label: 'Households',
    shortLabel: 'Households',
    to: '/app/households',
    icon: House,
    permission: Permissions.HouseholdsRecordsView,
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

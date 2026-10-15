import { Home, Users, CalendarDays, HeartHandshake, Library } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { Permissions } from '../../types/permissions';
import type { PermissionCode } from '../../types/permissions';

/** A sub-tab inside a combined navigation item (Pass 9.11, Claude 2026-10-16). */
export type NavTab = {
  label: string;
  to: string;
  permission?: PermissionCode;
};

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
  /**
   * Combined item: sub-tabs shown at the top of each tab's page. The item is shown when at least one
   * tab is allowed, links to the first allowed tab, and is highlighted on any of the tabs' paths.
   */
  tabs?: NavTab[];
  /** Extra path prefixes that highlight this item (e.g. detail pages). */
  matchPaths?: string[];
};

/**
 * Primary navigation. Only domains with real routes are listed.
 * Reserved (not yet implemented): Finance, Administration.
 * Pass 9.11 (Ron): People = Directory + Sections; Pastoral Operations = Households + Dashboard;
 * Library = Household Topics + Formation Curriculum. Old URLs are unchanged.
 */
export const NAV_ITEMS: NavItem[] = [
  { id: 'nav-dashboard', label: 'Home', shortLabel: 'Home', to: '/app/dashboard', icon: Home },
  {
    id: 'nav-members',
    label: 'People',
    shortLabel: 'People',
    to: '/app/members',
    icon: Users,
    tabs: [
      { label: 'Directory', to: '/app/members', permission: Permissions.MembersRecordsView },
      { label: 'Sections', to: '/app/sections', permission: Permissions.MembersRecordsView },
    ],
    matchPaths: ['/app/members', '/app/sections', '/app/families'],
  },
  {
    id: 'nav-calendar',
    label: 'Calendar',
    shortLabel: 'Calendar',
    to: '/app/calendar',
    icon: CalendarDays,
    permission: Permissions.EventsView,
    matchPaths: ['/app/calendar', '/app/programs'],
  },
  {
    id: 'nav-pastoral-operations',
    label: 'Pastoral Operations',
    shortLabel: 'Pastoral',
    to: '/app/households',
    icon: HeartHandshake,
    tabs: [
      { label: 'Households', to: '/app/households', permission: Permissions.HouseholdsRecordsView },
      { label: 'Dashboard', to: '/app/pastoral-operations', permission: Permissions.LeadershipPastoralDashboardView },
    ],
    matchPaths: ['/app/households', '/app/pastoral-operations'],
  },
  {
    id: 'nav-library',
    label: 'Library',
    shortLabel: 'Library',
    to: '/app/library',
    icon: Library,
    tabs: [
      { label: 'Household Topics', to: '/app/library' },
      { label: 'Formation Curriculum', to: '/app/formation', permission: Permissions.FormationCatalogView },
    ],
    matchPaths: ['/app/library', '/app/formation'],
  },
];

/** Is this nav item the current one? */
export function isNavItemActive(item: NavItem, pathname: string): boolean {
  const prefixes = item.matchPaths ?? [item.to];
  return prefixes.some((p) => pathname === p || pathname.startsWith(p + '/'));
}

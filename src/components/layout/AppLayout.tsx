import { useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../../hooks/use-auth';
import { usePermissions } from '../../hooks/use-permissions';
import { useOrganizationContext } from '../../hooks/use-organization-context';
import { Permissions } from '../../types/permissions';
import { useMyEventAccess } from '../../features/events/queries';
import { NAV_ITEMS, type NavItem } from './navigation';
import AppSidebar from './AppSidebar';
import AppHeader from './AppHeader';
import MobileNavigation from './MobileNavigation';

const COLLAPSE_KEY = 'missionos.sidebar.collapsed';

function readCollapsed(): boolean {
  try {
    return localStorage.getItem(COLLAPSE_KEY) === '1';
  } catch {
    return false;
  }
}

/**
 * Main application shell: sidebar (desktop), header, workspace and
 * bottom navigation (mobile).
 *
 * Navigation items are gated by the same permissions as before; the
 * server remains authoritative.
 */
export default function AppLayout() {
  const { user, signOut } = useAuth();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const { activeOrganization } = useOrganizationContext();
  const { data: eventAccess } = useMyEventAccess(
    activeOrganization?.id ?? null,
    !!activeOrganization?.id
  );
  const [collapsed, setCollapsed] = useState<boolean>(readCollapsed);

  const { pathname } = useLocation();
  const allowed = (permission?: Parameters<typeof hasPermission>[0]) =>
    !permission || (!isPermLoading && hasPermission(permission));

  // Combined items keep only the tabs this person may open; the item links to the first one.
  const items: NavItem[] = NAV_ITEMS.flatMap((item): NavItem[] => {
    if (item.id === 'nav-calendar') {
      const ok =
        (!isPermLoading && hasPermission(Permissions.EventsView)) ||
        eventAccess?.can_view_calendar === true;
      return ok ? [item] : [];
    }
    if (item.tabs) {
      const tabs = item.tabs.filter((t) => allowed(t.permission));
      return tabs.length > 0 ? [{ ...item, tabs, to: tabs[0].to }] : [];
    }
    return allowed(item.permission) ? [item] : [];
  });

  // Sub-tabs appear on the tab pages themselves (not on detail pages), only when there is a choice.
  const tabGroup = items.find((i) => i.tabs?.some((t) => t.to === pathname));

  const toggle = () => {
    setCollapsed((c) => {
      try {
        localStorage.setItem(COLLAPSE_KEY, c ? '0' : '1');
      } catch {
        /* ignore */
      }
      return !c;
    });
  };

  const orgName = activeOrganization?.name ?? null;

  return (
    <div className="flex min-h-screen bg-canvas text-ink">
      <AppSidebar
        items={items}
        collapsed={collapsed}
        onToggle={toggle}
        email={user?.email}
        organizationName={orgName}
        onSignOut={signOut}
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <AppHeader email={user?.email} organizationName={orgName} onSignOut={signOut} />
        <main className="min-w-0 w-full flex-1 overflow-x-clip px-4 py-6 pb-24 sm:px-6 sm:py-8 md:pb-8 lg:px-8">
          <div className="mx-auto w-full max-w-7xl">
            {tabGroup?.tabs && tabGroup.tabs.length > 1 && (
              <div className="mb-6">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-ink-muted">{tabGroup.label}</p>
              <nav aria-label={tabGroup.label} className="flex gap-1 overflow-x-auto border-b border-line">
                {tabGroup.tabs.map((t) => (
                  <NavLink
                    key={t.to}
                    to={t.to}
                    end
                    className={({ isActive }) =>
                      `whitespace-nowrap border-b-2 px-3 pb-2.5 pt-1 text-sm font-medium transition-colors ${
                        isActive
                          ? 'border-primary text-primary'
                          : 'border-transparent text-ink-secondary hover:text-ink'
                      }`
                    }
                  >
                    {t.label}
                  </NavLink>
                ))}
              </nav>
              </div>
            )}
            <Outlet />
          </div>
        </main>
      </div>
      <MobileNavigation items={items} />
    </div>
  );
}

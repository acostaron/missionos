import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import { useAuth } from '../../hooks/use-auth';
import { usePermissions } from '../../hooks/use-permissions';
import { useOrganizationContext } from '../../hooks/use-organization-context';
import { NAV_ITEMS } from './navigation';
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
  const [collapsed, setCollapsed] = useState<boolean>(readCollapsed);

  const items = NAV_ITEMS.filter(
    (item) => !item.permission || (!isPermLoading && hasPermission(item.permission)),
  );

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
        <main className="w-full flex-1 px-4 py-6 pb-24 sm:px-6 sm:py-8 md:pb-8 lg:px-8">
          <div className="mx-auto w-full max-w-7xl">
            <Outlet />
          </div>
        </main>
      </div>
      <MobileNavigation items={items} />
    </div>
  );
}

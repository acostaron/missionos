import { Outlet, NavLink } from 'react-router-dom';
import { useAuth } from '../../hooks/use-auth';
import { usePermissions } from '../../hooks/use-permissions';
import { Permissions } from '../../types/permissions';

/**
 * Main application shell.
 *
 * Navigation links are permission-gated:
 *   - "Members" is only shown when the authenticated user holds
 *     members.records.view for the active organization.
 *   - Additional nav items should follow the same pattern.
 */
export default function AppLayout() {
  const { user, signOut } = useAuth();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const canViewMembers = !isPermLoading && hasPermission(Permissions.MembersRecordsView);

  return (
    <div className="flex min-h-screen flex-col bg-slate-950 text-slate-100">
      {/* Top navigation bar */}
      <header className="sticky top-0 z-30 border-b border-slate-800 bg-slate-900/80 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
          {/* Brand */}
          <div className="flex items-center gap-6">
            <span className="text-base font-bold tracking-tight text-slate-100">
              Mission<span className="text-indigo-400">OS</span>
            </span>

            {/* Primary navigation */}
            <nav className="flex items-center gap-1" aria-label="Primary navigation">
              <NavLink
                to="/app/dashboard"
                id="nav-dashboard"
                className={({ isActive }) =>
                  `rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                    isActive
                      ? 'bg-slate-800 text-slate-100'
                      : 'text-slate-400 hover:bg-slate-800/60 hover:text-slate-200'
                  }`
                }
              >
                Dashboard
              </NavLink>

              {/* Members — only rendered when members.records.view is held */}
              {canViewMembers && (
                <NavLink
                  to="/app/members"
                  id="nav-members"
                  className={({ isActive }) =>
                    `rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                      isActive
                        ? 'bg-slate-800 text-slate-100'
                        : 'text-slate-400 hover:bg-slate-800/60 hover:text-slate-200'
                    }`
                  }
                >
                  Members
                </NavLink>
              )}
            </nav>
          </div>

          {/* User controls */}
          <div className="flex items-center gap-4">
            <span className="hidden text-xs text-slate-500 sm:block">{user?.email}</span>
            <button
              id="nav-sign-out"
              onClick={signOut}
              className="rounded-md px-3 py-1.5 text-sm font-medium text-slate-400 transition-colors hover:bg-red-900/30 hover:text-red-300"
            >
              Sign out
            </button>
          </div>
        </div>
      </header>

      {/* Page content */}
      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-8 sm:px-6 lg:px-8">
        <Outlet />
      </main>
    </div>
  );
}

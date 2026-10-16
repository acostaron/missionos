import { NavLink, useLocation } from 'react-router-dom';
import { LogOut, PanelLeftClose } from 'lucide-react';
import { isNavItemActive, type NavItem } from './navigation';
import { MissionOSLogo } from '../brand/MissionOSLogo';

type Props = {
  items: NavItem[];
  collapsed: boolean;
  onToggle: () => void;
  email?: string | null;
  organizationName?: string | null;
  onSignOut: () => void;
};

export default function AppSidebar({
  items,
  collapsed,
  onToggle,
  email,
  organizationName,
  onSignOut,
}: Props) {
  const { pathname } = useLocation();
  const focus =
    'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus';
  return (
    <aside
      className={`sticky top-0 hidden h-screen shrink-0 flex-col border-r border-line bg-surface transition-[width] duration-200 md:flex ${
        collapsed ? 'w-[76px]' : 'w-64'
      }`}
    >
      <div
        className={`flex h-16 items-center justify-between gap-2 border-b border-line ${collapsed ? 'px-2' : 'px-4'}`}
      >
        {collapsed ? (
          <button
            type="button"
            id="nav-collapse-toggle"
            onClick={onToggle}
            aria-label="Expand sidebar"
            title="Expand sidebar"
            className={`mx-auto rounded-full p-0.5 hover:bg-canvas ${focus}`}
          >
            <MissionOSLogo size={36} />
          </button>
        ) : (
          <>
            <div className="flex min-w-0 items-center gap-2.5">
              <MissionOSLogo size={36} />
              <div className="min-w-0">
                <div className="truncate text-base font-bold leading-tight text-primary">MissionOS</div>
                <div className="truncate text-xs text-ink-muted">Missionary Families of Christ</div>
              </div>
            </div>
            <button
              type="button"
              id="nav-collapse-toggle"
              onClick={onToggle}
              aria-label="Collapse sidebar"
              title="Collapse sidebar"
              className={`rounded-md p-2 text-ink-muted hover:bg-canvas ${focus}`}
            >
              <PanelLeftClose size={18} />
            </button>
          </>
        )}
      </div>

      <nav aria-label="Primary navigation" className="flex-1 space-y-1 overflow-y-auto p-3">
        {items.map((item) => {
          const { id, label, to, icon: Icon } = item;
          const active = isNavItemActive(item, pathname);
          return (
          <NavLink
            key={id}
            to={to}
            id={id}
            title={label}
            aria-label={label}
            className={() =>
              `flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${focus} ${
                collapsed ? 'justify-center' : ''
              } ${
                active
                  ? 'bg-primary/10 text-primary shadow-[inset_3px_0_0_var(--color-primary)]'
                  : 'text-ink-muted hover:bg-canvas hover:text-ink'
              }`
            }
          >
            <Icon size={20} aria-hidden="true" className="shrink-0" />
            {!collapsed && <span className="truncate">{label}</span>}
          </NavLink>
          );
        })}
      </nav>

      <div className="border-t border-line p-3">
        {!collapsed && (
          <div className="mb-2 min-w-0 px-2">
            <div className="truncate text-sm font-medium text-ink">{email}</div>
            {organizationName && (
              <div className="truncate text-xs text-ink-muted">{organizationName}</div>
            )}
          </div>
        )}
        <button
          type="button"
          id="nav-sign-out"
          onClick={onSignOut}
          title="Sign out"
          aria-label="Sign out"
          className={`flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium text-ink-muted hover:bg-canvas hover:text-ink ${focus} ${
            collapsed ? 'justify-center' : ''
          }`}
        >
          <LogOut size={18} aria-hidden="true" className="shrink-0" />
          {!collapsed && <span>Sign out</span>}
        </button>
      </div>
    </aside>
  );
}

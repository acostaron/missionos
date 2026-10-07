import { NavLink } from 'react-router-dom';
import { LogOut, PanelLeftClose, PanelLeftOpen } from 'lucide-react';
import type { NavItem } from './navigation';

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
  const focus =
    'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus';
  return (
    <aside
      className={`sticky top-0 hidden h-screen shrink-0 flex-col border-r border-line bg-surface transition-[width] duration-200 md:flex ${
        collapsed ? 'w-[76px]' : 'w-64'
      }`}
    >
      <div className="flex h-16 items-center justify-between gap-2 border-b border-line px-4">
        {!collapsed && (
          <div className="min-w-0">
            <div className="truncate text-base font-bold leading-tight text-primary">MissionOS</div>
            <div className="truncate text-xs text-ink-muted">Missionary Families of Christ</div>
          </div>
        )}
        <button
          type="button"
          id="nav-collapse-toggle"
          onClick={onToggle}
          aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          className={`rounded-md p-2 text-ink-muted hover:bg-canvas ${focus} ${collapsed ? 'mx-auto' : ''}`}
        >
          {collapsed ? <PanelLeftOpen size={18} /> : <PanelLeftClose size={18} />}
        </button>
      </div>

      <nav aria-label="Primary navigation" className="flex-1 space-y-1 overflow-y-auto p-3">
        {items.map(({ id, label, to, icon: Icon }) => (
          <NavLink
            key={id}
            to={to}
            id={id}
            title={label}
            aria-label={label}
            className={({ isActive }) =>
              `flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${focus} ${
                collapsed ? 'justify-center' : ''
              } ${
                isActive
                  ? 'bg-primary/10 text-primary shadow-[inset_3px_0_0_var(--color-primary)]'
                  : 'text-ink-muted hover:bg-canvas hover:text-ink'
              }`
            }
          >
            <Icon size={20} aria-hidden="true" className="shrink-0" />
            {!collapsed && <span className="truncate">{label}</span>}
          </NavLink>
        ))}
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

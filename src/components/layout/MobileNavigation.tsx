import { NavLink } from 'react-router-dom';
import type { NavItem } from './navigation';

export default function MobileNavigation({ items }: { items: NavItem[] }) {
  return (
    <nav
      aria-label="Primary navigation (mobile)"
      className="fixed inset-x-0 bottom-0 z-30 border-t border-line bg-surface pb-[env(safe-area-inset-bottom)] md:hidden"
    >
      <ul className="flex">
        {items.map(({ id, shortLabel, label, to, icon: Icon }) => (
          <li key={id} className="min-w-0 flex-1">
            <NavLink
              to={to}
              id={`m-${id}`}
              aria-label={label}
              className={({ isActive }) =>
                `flex flex-col items-center gap-0.5 px-1 py-2 text-[11px] font-medium focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-focus ${
                  isActive ? 'text-primary' : 'text-ink-muted'
                }`
              }
            >
              <Icon size={22} aria-hidden="true" />
              <span className="max-w-full truncate">{shortLabel}</span>
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}

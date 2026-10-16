import { Link } from 'react-router-dom';
import type { ReactNode } from 'react';

export type QuickAction = { key: string; label: string; to: string; icon: ReactNode };

export default function QuickActions({ actions }: { actions: QuickAction[] }) {
  if (actions.length === 0) return null;
  return (
    <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap sm:gap-3">
      {actions.map((a) => (
        <Link
          key={a.key}
          to={a.to}
          className="inline-flex h-9 min-w-0 items-center gap-2 rounded-control border border-line-strong bg-surface px-3 text-small font-medium sm:h-10 sm:px-4 sm:text-body text-ink transition-colors hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
        >
          <span aria-hidden="true" className="text-primary-blue [&>svg]:h-4 [&>svg]:w-4">
            {a.icon}
          </span>
          <span className="truncate">{a.label}</span>
        </Link>
      ))}
    </div>
  );
}

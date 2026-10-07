import { Link } from 'react-router-dom';
import type { ReactNode } from 'react';

export type QuickAction = { key: string; label: string; to: string; icon: ReactNode };

export default function QuickActions({ actions }: { actions: QuickAction[] }) {
  if (actions.length === 0) return null;
  return (
    <div className="flex flex-wrap gap-3">
      {actions.map((a) => (
        <Link
          key={a.key}
          to={a.to}
          className="inline-flex h-10 items-center gap-2 rounded-control border border-line-strong bg-surface px-4 text-body font-medium text-ink transition-colors hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
        >
          <span aria-hidden="true" className="text-primary-blue [&>svg]:h-4 [&>svg]:w-4">
            {a.icon}
          </span>
          {a.label}
        </Link>
      ))}
    </div>
  );
}

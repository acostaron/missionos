import type { ReactNode } from 'react';
import { cx } from './cx';

export interface EmptyStateProps {
  title: ReactNode;
  message?: ReactNode;
  /** Optional icon element, e.g. <Users /> from lucide-react. */
  icon?: ReactNode;
  /** Optional call-to-action (usually a Button). */
  action?: ReactNode;
  className?: string;
}

/** Calm placeholder for lists and sections that have nothing to show yet. */
export function EmptyState({ title, message, icon, action, className }: EmptyStateProps) {
  return (
    <div className={cx('flex flex-col items-center px-4 py-10 text-center', className)}>
      {icon && (
        <div
          className="mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-navy-50 text-navy-700 [&>svg]:h-6 [&>svg]:w-6"
          aria-hidden="true"
        >
          {icon}
        </div>
      )}
      <h3 className="text-card-title font-semibold text-ink">{title}</h3>
      {message && <p className="mt-1 max-w-md text-small text-ink-secondary">{message}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}
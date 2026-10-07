import type { ReactNode } from 'react';
import { cx } from './cx';

export interface PageHeaderProps {
  title: ReactNode;
  description?: ReactNode;
  /** Primary and secondary page actions, aligned to the right on wide screens. */
  actions?: ReactNode;
  /** Reserved for future breadcrumbs (rendered above the title). */
  breadcrumb?: ReactNode;
  className?: string;
}

/** Page title block. Render exactly one per page (it owns the <h1>). */
export function PageHeader({ title, description, actions, breadcrumb, className }: PageHeaderProps) {
  return (
    <header className={cx('space-y-2', className)}>
      {breadcrumb && <div className="text-small text-ink-muted">{breadcrumb}</div>}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="text-page-title font-semibold tracking-tight text-ink">{title}</h1>
          {description && <p className="mt-1 max-w-2xl text-body text-ink-secondary">{description}</p>}
        </div>
        {actions && <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>}
      </div>
    </header>
  );
}
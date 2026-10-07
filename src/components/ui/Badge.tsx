import type { HTMLAttributes } from 'react';
import { cx } from './cx';

export type BadgeVariant = 'neutral' | 'info' | 'success' | 'warning' | 'danger';

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant?: BadgeVariant;
}

const VARIANTS: Record<BadgeVariant, string> = {
  neutral: 'bg-surface-muted text-ink-secondary',
  info: 'bg-navy-50 text-navy-800',
  success: 'bg-success-50 text-success-700',
  warning: 'bg-warning-50 text-warning-700',
  danger: 'bg-danger-50 text-danger-700',
};

/** Status label. Always render meaningful text; never rely on color alone. */
export function Badge({ variant = 'neutral', className, ...rest }: BadgeProps) {
  return (
    <span
      className={cx(
        'inline-flex items-center rounded-full px-2.5 py-0.5 text-caption font-medium whitespace-nowrap',
        VARIANTS[variant],
        className
      )}
      {...rest}
    />
  );
}
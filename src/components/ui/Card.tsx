import type { HTMLAttributes } from 'react';
import { cx } from './cx';

export type CardVariant = 'standard' | 'subtle' | 'interactive';

export interface CardProps extends HTMLAttributes<HTMLDivElement> {
  variant?: CardVariant;
  /** Inner padding. Defaults to comfortable. */
  padding?: 'none' | 'compact' | 'comfortable';
}

const VARIANTS: Record<CardVariant, string> = {
  standard: 'border border-line bg-surface shadow-card',
  subtle: 'bg-surface-muted',
  interactive:
    'border border-line bg-surface shadow-card transition-shadow hover:shadow-raised focus-within:shadow-raised',
};

const PADDING = {
  none: '',
  compact: 'p-4',
  comfortable: 'p-4 sm:p-6',
} as const;

/** Surface container. Keep borders light; prefer whitespace over nesting cards. */
export function Card({ variant = 'standard', padding = 'comfortable', className, ...rest }: CardProps) {
  return <div className={cx('rounded-card', VARIANTS[variant], PADDING[padding], className)} {...rest} />;
}
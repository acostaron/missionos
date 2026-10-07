import type { HTMLAttributes } from 'react';
import { cx } from './cx';

/** Loading placeholder block. Size it with utility classes (h-*, w-*). */
export function Skeleton({ className, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return <div aria-hidden="true" className={cx('animate-pulse rounded-control bg-surface-muted', className)} {...rest} />;
}
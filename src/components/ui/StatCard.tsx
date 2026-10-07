import type { ReactNode } from 'react';
import { cx } from './cx';

export type StatTone = 'neutral' | 'success' | 'warning' | 'danger';

export interface StatCardProps {
  label: ReactNode;
  value: ReactNode;
  /** Short context line, e.g. "Past scheduled frequency". Pair tone with text, not color alone. */
  context?: ReactNode;
  icon?: ReactNode;
  tone?: StatTone;
  className?: string;
}

const VALUE_TONE: Record<StatTone, string> = {
  neutral: 'text-ink',
  success: 'text-success-700',
  warning: 'text-warning-700',
  danger: 'text-danger-700',
};

/** Compact ministry metric. Intentionally light: no heavy borders or shadows. */
export function StatCard({ label, value, context, icon, tone = 'neutral', className }: StatCardProps) {
  return (
    <div className={cx('rounded-card border border-line bg-surface p-4', className)}>
      <div className="flex items-start justify-between gap-2">
        <p className="text-small text-ink-secondary">{label}</p>
        {icon && (
          <span className="text-ink-muted [&>svg]:h-4 [&>svg]:w-4" aria-hidden="true">
            {icon}
          </span>
        )}
      </div>
      <p className={cx('mt-1 text-2xl font-semibold tabular-nums', VALUE_TONE[tone])}>{value}</p>
      {context && <p className="mt-0.5 text-caption text-ink-muted">{context}</p>}
    </div>
  );
}
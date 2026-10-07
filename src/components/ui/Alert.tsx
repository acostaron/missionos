import type { HTMLAttributes, ReactNode } from 'react';
import { AlertTriangle, CheckCircle2, Info, XCircle } from 'lucide-react';
import { cx } from './cx';

export type AlertVariant = 'info' | 'success' | 'warning' | 'danger';

export interface AlertProps extends Omit<HTMLAttributes<HTMLDivElement>, 'title'> {
  variant?: AlertVariant;
  title?: ReactNode;
}

const VARIANTS: Record<AlertVariant, { box: string; icon: typeof Info }> = {
  info: { box: 'border-navy-100 bg-navy-50 text-navy-900', icon: Info },
  success: { box: 'border-success-100 bg-success-50 text-success-700', icon: CheckCircle2 },
  warning: { box: 'border-warning-100 bg-warning-50 text-warning-700', icon: AlertTriangle },
  danger: { box: 'border-danger-100 bg-danger-50 text-danger-700', icon: XCircle },
};

/** Inline message. Danger/warning use role="alert"; others use role="status". */
export function Alert({ variant = 'info', title, className, children, ...rest }: AlertProps) {
  const { box, icon: Icon } = VARIANTS[variant];
  const role = variant === 'danger' || variant === 'warning' ? 'alert' : 'status';
  return (
    <div role={role} className={cx('flex gap-3 rounded-card border p-4 text-small', box, className)} {...rest}>
      <Icon className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
      <div className="min-w-0 space-y-1">
        {title && <p className="font-semibold">{title}</p>}
        {children && <div>{children}</div>}
      </div>
    </div>
  );
}
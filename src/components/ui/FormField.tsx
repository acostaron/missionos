import { cloneElement, isValidElement, useId } from 'react';
import type { ReactElement, ReactNode } from 'react';
import { cx } from './cx';

export interface FormFieldProps {
  label: ReactNode;
  /** A single form control (Input, Select, Textarea or a native control). */
  children: ReactElement<Record<string, unknown>>;
  hint?: ReactNode;
  error?: ReactNode;
  required?: boolean;
  className?: string;
}

/**
 * Connects a visible label, optional hint and error message to one control
 * via htmlFor / aria-describedby / aria-invalid.
 */
export function FormField({ label, children, hint, error, required, className }: FormFieldProps) {
  const baseId = useId();
  const controlId = (isValidElement(children) && (children.props.id as string | undefined)) || `${baseId}-control`;
  const hintId = hint ? `${baseId}-hint` : undefined;
  const errorId = error ? `${baseId}-error` : undefined;
  const describedBy = [hintId, errorId].filter(Boolean).join(' ') || undefined;

  const control = isValidElement(children)
    ? cloneElement(children, {
        id: controlId,
        'aria-describedby': describedBy,
        'aria-invalid': error ? true : undefined,
        required: required || undefined,
      })
    : children;

  return (
    <div className={cx('space-y-1.5', className)}>
      <label htmlFor={controlId} className="block text-label font-medium text-ink">
        {label}
        {required && (
          <span className="ml-0.5 text-danger-600" aria-hidden="true">
            *
          </span>
        )}
      </label>
      {control}
      {hint && (
        <p id={hintId} className="text-caption text-ink-muted">
          {hint}
        </p>
      )}
      {error && (
        <p id={errorId} className="text-caption font-medium text-danger-700">
          {error}
        </p>
      )}
    </div>
  );
}
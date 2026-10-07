import { forwardRef } from 'react';
import type { SelectHTMLAttributes } from 'react';
import { cx } from './cx';
import { CONTROL_CLASSES } from './form-control';

export type SelectProps = SelectHTMLAttributes<HTMLSelectElement>;

/** Native select (best mobile behavior). Pass <option> children. */
export const Select = forwardRef<HTMLSelectElement, SelectProps>(function Select({ className, ...rest }, ref) {
  return <select ref={ref} className={cx(CONTROL_CLASSES, 'h-10', className)} {...rest} />;
});
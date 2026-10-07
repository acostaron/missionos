import { forwardRef } from 'react';
import type { InputHTMLAttributes } from 'react';
import { cx } from './cx';
import { CONTROL_CLASSES } from './form-control';

export type InputProps = InputHTMLAttributes<HTMLInputElement>;

/** Text-like input. Pair with FormField for label, hint and error wiring. */
export const Input = forwardRef<HTMLInputElement, InputProps>(function Input({ className, ...rest }, ref) {
  return <input ref={ref} className={cx(CONTROL_CLASSES, 'h-10', className)} {...rest} />;
});
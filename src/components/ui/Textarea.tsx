import { forwardRef } from 'react';
import type { TextareaHTMLAttributes } from 'react';
import { cx } from './cx';
import { CONTROL_CLASSES } from './form-control';

export type TextareaProps = TextareaHTMLAttributes<HTMLTextAreaElement>;

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(function Textarea(
  { className, rows = 4, ...rest },
  ref
) {
  return <textarea ref={ref} rows={rows} className={cx(CONTROL_CLASSES, 'py-2', className)} {...rest} />;
});
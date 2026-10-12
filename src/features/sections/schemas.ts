import { z } from 'zod';

/**
 * Returns today's date formatted as YYYY-MM-DD in the user's local timezone.
 */
export function localToday(): string {
  const d = new Date();
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export const changeSectionSchema = z.object({
  sectionCode: z.string().min(1, 'Please select a section'),
  effectiveFrom: z
    .string()
    .min(1, 'Effective date is required')
    .refine((val) => {
      const today = localToday();
      return val <= today;
    }, 'Effective date cannot be in the future'),
  reason: z
    .string()
    .trim()
    .min(5, 'Reason must be at least 5 characters'),
});

export type ChangeSectionFormValues = z.infer<typeof changeSectionSchema>;

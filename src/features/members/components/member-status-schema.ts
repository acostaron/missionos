import { z } from 'zod';

export const changeMemberStatusSchema = z.object({
  targetStatusId: z
    .string()
    .trim()
    .min(1, 'Please select a membership status.'),
  effectiveFrom: z
    .string()
    .trim()
    .min(1, 'Effective date is required.')
    .refine((val) => !isNaN(new Date(val).getTime()), 'Invalid date format.')
    .refine((val) => {
      const today = new Date().toISOString().split('T')[0];
      return val <= today;
    }, 'Effective date cannot be in the future.'),
  reason: z
    .string()
    .max(500, 'Reason cannot exceed 500 characters.')
    .optional(),
});

export type ChangeMemberStatusFormValues = z.infer<typeof changeMemberStatusSchema>;

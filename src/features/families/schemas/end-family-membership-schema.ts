import { z } from 'zod';

export const endFamilyMembershipSchema = z.object({
  effective_to: z
    .string()
    .min(1, 'Effective end date is required')
    .refine(
      (val) => {
        const d = new Date(val);
        const today = new Date();
        today.setHours(23, 59, 59, 999);
        return d <= today;
      },
      { message: 'Effective end date cannot be in the future' }
    ),
  reason: z
    .string()
    .min(1, 'An end membership reason is required')
    .max(500, 'Reason must not exceed 500 characters')
    .refine((val) => val.trim().length > 0, {
      message: 'Reason cannot be blank',
    }),
});

export type EndFamilyMembershipFormValues = z.infer<typeof endFamilyMembershipSchema>;

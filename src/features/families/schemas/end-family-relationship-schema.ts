import { z } from 'zod';

export const endFamilyRelationshipSchema = z.object({
  reason: z
    .string()
    .min(3, 'Reason must be at least 3 characters')
    .max(500, 'Reason cannot exceed 500 characters'),
  effective_to: z
    .string()
    .optional()
    .refine(
      (val) => {
        if (!val) return true;
        const d = new Date(val);
        const today = new Date();
        today.setHours(23, 59, 59, 999);
        return d <= today;
      },
      { message: 'Effective to date cannot be in the future' }
    ),
});

export type EndFamilyRelationshipFormValues = z.infer<typeof endFamilyRelationshipSchema>;

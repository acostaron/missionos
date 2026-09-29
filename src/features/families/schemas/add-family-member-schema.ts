import { z } from 'zod';

export const addFamilyMemberSchema = z.object({
  member_id: z.string().min(1, 'Please select a member to add'),
  family_role: z.string().optional(),
  is_primary_contact: z.boolean(),
  is_dependent: z.boolean(),
  effective_from: z
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
      { message: 'Effective from date cannot be in the future' }
    ),
});

export type AddFamilyMemberFormValues = z.infer<typeof addFamilyMemberSchema>;

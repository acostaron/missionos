import { z } from 'zod';

const todayDateString = () => new Date().toISOString().split('T')[0];

export const editFamilySchema = z.object({
  display_name: z
    .string()
    .min(1, 'Display name is required')
    .max(200, 'Display name must not exceed 200 characters')
    .refine((val) => val.trim().length > 0, {
      message: 'Display name cannot be blank',
    }),
  family_name: z
    .string()
    .min(1, 'Family name is required')
    .max(100, 'Family name must not exceed 100 characters')
    .refine((val) => val.trim().length > 0, {
      message: 'Family name cannot be blank',
    }),
  family_type: z.enum([
    'household_family',
    'married_couple',
    'single_parent_family',
    'guardian_family',
    'extended_family',
    'other',
  ]),
  formed_on: z
    .string()
    .optional()
    .refine(
      (val) => {
        if (!val || val.trim() === '') return true;
        return val <= todayDateString();
      },
      { message: 'Formed on date cannot be in the future' }
    ),
});

export type EditFamilyFormValues = z.infer<typeof editFamilySchema>;

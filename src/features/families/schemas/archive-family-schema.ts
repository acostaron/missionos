import { z } from 'zod';

export const archiveFamilySchema = z.object({
  reason: z
    .string()
    .min(1, 'An archive reason is required')
    .max(500, 'Reason must not exceed 500 characters')
    .refine((val) => val.trim().length > 0, {
      message: 'Reason cannot be blank',
    }),
});

export type ArchiveFamilyFormValues = z.infer<typeof archiveFamilySchema>;

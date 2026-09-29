import { z } from 'zod';

export const repairFamilyRelationshipSchema = z.object({
  reason: z
    .string()
    .min(3, 'Reason must be at least 3 characters')
    .max(500, 'Reason cannot exceed 500 characters'),
});

export type RepairFamilyRelationshipFormValues = z.infer<typeof repairFamilyRelationshipSchema>;

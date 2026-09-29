import { z } from 'zod';

export const editFamilyMemberSchema = z.object({
  family_role: z.string().optional(),
  is_primary_contact: z.boolean(),
  is_dependent: z.boolean(),
});

export type EditFamilyMemberFormValues = z.infer<typeof editFamilyMemberSchema>;

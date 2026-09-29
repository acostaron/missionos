import { z } from 'zod';

export const addFamilyRelationshipSchema = z
  .object({
    from_member_id: z.string().min(1, 'Please select the from member'),
    to_member_id: z.string().min(1, 'Please select the to member'),
    relationship_type_code: z.string().min(1, 'Please select a relationship type'),
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
  })
  .refine((data) => data.from_member_id !== data.to_member_id, {
    message: 'A member cannot have a relationship with themselves',
    path: ['to_member_id'],
  });

export type AddFamilyRelationshipFormValues = z.infer<typeof addFamilyRelationshipSchema>;

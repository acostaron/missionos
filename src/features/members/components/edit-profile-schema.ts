import { z } from 'zod';

export const createEditProfileSchema = (currentNameEffectiveFrom?: string | null) =>
  z
    .object({
      // Identity
      givenNames: z.string().trim().min(1, 'Given name is required'),
      middleNames: z.string().optional(),
      familyName: z.string().trim().min(1, 'Family name is required'),
      preferredName: z.string().optional(),

      // Demographics
      birthDate: z
        .string()
        .optional()
        .refine((date) => {
          if (!date || date.trim() === '') return true;
          const parsed = new Date(date);
          return !isNaN(parsed.getTime()) && parsed <= new Date();
        }, 'Birth date cannot be in the future'),
      sex: z.enum(['', 'male', 'female', 'other']).optional(),
      civilStatus: z
        .enum(['', 'single', 'married', 'widowed', 'separated', 'divorced'])
        .optional(),
      homeCountryCode: z.string().optional(),
      preferredLanguageCode: z.string().optional(),

      // Name Update Type & Historical Semantics
      isNameChange: z.boolean(),
      effectiveFrom: z.string().optional(),
      changeReason: z.string().optional(),
    })
    .superRefine((data, ctx) => {
      // If official name change is selected
      if (data.isNameChange) {
        if (!data.effectiveFrom || data.effectiveFrom.trim() === '') {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['effectiveFrom'],
            message: 'Effective date is required for an official name change',
          });
        } else if (currentNameEffectiveFrom) {
          if (data.effectiveFrom < currentNameEffectiveFrom) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              path: ['effectiveFrom'],
              message: `Effective date cannot precede current name start date (${currentNameEffectiveFrom})`,
            });
          }
        }
      }
    });

export type EditProfileFormData = z.infer<ReturnType<typeof createEditProfileSchema>>;

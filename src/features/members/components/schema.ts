import { z } from 'zod';

export const createMemberSchema = z.object({
  // Step 1: Identity
  givenNames: z.string().trim().min(1, 'Given name is required'),
  familyName: z.string().trim().min(1, 'Family name is required'),
  middleNames: z.string().optional(),
  preferredName: z.string().optional(),
  birthDate: z
    .string()
    .optional()
    .refine((date) => {
      if (!date) return true;
      const parsed = new Date(date);
      return !isNaN(parsed.getTime()) && parsed <= new Date();
    }, 'Birth date cannot be in the future'),
  sex: z.enum(['', 'male', 'female', 'other']).optional(),
  civilStatus: z.enum(['', 'single', 'married', 'widowed', 'separated', 'divorced']).optional(),

  // Step 2: Membership
  joinedOn: z
    .string()
    .min(1, 'Joined date is required')
    .refine((date) => !isNaN(new Date(date).getTime()), 'Valid joined date is required'),
  homeCountryCode: z.string().length(2, 'Country code must be 2 letters'),
  allocateMemberNumber: z.boolean(),

  // Step 3: Placement
  governanceNodeId: z.string().optional(),

  // Step 4: Contact & Residential Address
  email: z
    .string()
    .optional()
    .refine((val) => {
      if (!val || val.trim() === '') return true;
      return z.string().email().safeParse(val.trim()).success;
    }, 'Invalid email address format'),
  phone: z.string().optional(),
  phoneCountryCode: z.string().length(2),

  addressLine1: z.string().optional(),
  addressLine2: z.string().optional(),
  cityName: z.string().optional(),
  stateProvinceName: z.string().optional(),
  postalCode: z.string().optional(),
  addressCountryCode: z.string().length(2),
}).superRefine((data, ctx) => {
  // If addressLine1 is supplied, cityName and addressCountryCode are required
  const hasAddr = !!data.addressLine1 && data.addressLine1.trim().length > 0;
  if (hasAddr) {
    if (!data.cityName || data.cityName.trim().length === 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['cityName'],
        message: 'City is required when street address is entered',
      });
    }
    if (!data.addressCountryCode || data.addressCountryCode.trim().length === 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['addressCountryCode'],
        message: 'Country is required when street address is entered',
      });
    }
  }
});

export type CreateMemberFormData = z.infer<typeof createMemberSchema>;

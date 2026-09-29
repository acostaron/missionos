import { z } from 'zod';

/**
 * Validation schemas for Phase 5D Member Contact & Address management.
 */

// ---------------------------------------------------------------------------
// Email Schema
// ---------------------------------------------------------------------------
export const emailSchema = z.object({
  email: z
    .string()
    .trim()
    .min(1, 'Email address is required')
    .email('Please enter a valid email address'),
  setAsPrimary: z.boolean(),
});

export type EmailFormData = z.infer<typeof emailSchema>;

// ---------------------------------------------------------------------------
// Phone Schema
// ---------------------------------------------------------------------------
export const phoneSchema = z.object({
  countryCode: z
    .string()
    .trim()
    .min(1, 'Country is required')
    .min(2, 'Country code must be a 2-letter ISO code')
    .max(2, 'Country code must be a 2-letter ISO code'),
  phoneNumber: z
    .string()
    .trim()
    .min(1, 'Phone number is required'),
  setAsPrimary: z.boolean(),
});


export type PhoneFormData = z.infer<typeof phoneSchema>;

// ---------------------------------------------------------------------------
// Address Schema
// ---------------------------------------------------------------------------
export const addressSchema = z.object({
  line1: z
    .string()
    .trim()
    .min(1, 'Street address (Line 1) is required'),
  line2: z.string().optional(),
  city: z
    .string()
    .trim()
    .min(1, 'City is required'),
  state: z.string().optional(),
  postal: z.string().optional(),
  country: z.string().optional(),
  effectiveDate: z
    .string()
    .trim()
    .min(1, 'Effective date is required')
    .refine((val) => {
      const d = new Date(val);
      return !isNaN(d.getTime());
    }, 'Invalid date format'),
});

export type AddressFormData = z.infer<typeof addressSchema>;

// ---------------------------------------------------------------------------
// Standard ISO Country Options
// ---------------------------------------------------------------------------
export const COUNTRY_OPTIONS = [
  { code: 'US', name: 'United States (+1)' },
  { code: 'PH', name: 'Philippines (+63)' },
  { code: 'CA', name: 'Canada (+1)' },
  { code: 'GB', name: 'United Kingdom (+44)' },
  { code: 'AU', name: 'Australia (+61)' },
] as const;

export const ADDRESS_COUNTRY_OPTIONS = [
  { code: 'US', name: 'United States (US)' },
  { code: 'PH', name: 'Philippines (PH)' },
  { code: 'CA', name: 'Canada (CA)' },
  { code: 'GB', name: 'United Kingdom (GB)' },
  { code: 'AU', name: 'Australia (AU)' },
] as const;

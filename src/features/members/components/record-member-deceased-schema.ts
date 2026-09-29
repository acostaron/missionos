import { z } from 'zod';

const today = new Date().toISOString().split('T')[0];

export const recordMemberDeceasedSchema = z
  .object({
    deceasedOnPrecision: z.enum(['exact', 'month_and_year', 'year_only', 'unknown']),
    exactDate: z.string().optional(),
    monthAndYear: z.string().optional(), // YYYY-MM
    yearOnly: z.string().optional(), // YYYY
    effectiveFrom: z
      .string()
      .min(1, 'Effective date is required')
      .refine((val) => val <= today, {
        message: 'Effective date cannot be in the future',
      }),
    reason: z
      .string()
      .max(500, 'Note must not exceed 500 characters')
      .optional(),
  })
  .superRefine((data, ctx) => {
    if (data.deceasedOnPrecision === 'exact') {
      if (!data.exactDate || !data.exactDate.trim()) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['exactDate'],
          message: 'Date of death is required for exact precision',
        });
      } else if (data.exactDate > today) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['exactDate'],
          message: 'Date of death cannot be in the future',
        });
      }
    } else if (data.deceasedOnPrecision === 'month_and_year') {
      if (!data.monthAndYear || !data.monthAndYear.trim()) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['monthAndYear'],
          message: 'Month and year are required',
        });
      } else {
        // e.g. YYYY-MM
        const currentMonth = today.slice(0, 7);
        if (data.monthAndYear > currentMonth) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['monthAndYear'],
            message: 'Month and year cannot be in the future',
          });
        }
      }
    } else if (data.deceasedOnPrecision === 'year_only') {
      if (!data.yearOnly || !data.yearOnly.trim()) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['yearOnly'],
          message: 'Year is required',
        });
      } else {
        const currentYear = today.slice(0, 4);
        if (data.yearOnly > currentYear) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['yearOnly'],
            message: 'Year cannot be in the future',
          });
        }
      }
    }
  });

export type RecordMemberDeceasedFormValues = z.infer<typeof recordMemberDeceasedSchema>;

import { z } from 'zod';

const currentYear = new Date().getFullYear();
const today = new Date().toISOString().split('T')[0];

export const recordFormationProgramSchema = z
  .object({
    programId: z.string().min(1, 'Please select a course'),
    status: z.enum(['in_progress', 'completed', 'waived']),
    datePrecision: z.enum(['exact_date', 'month_year', 'year_only', 'approximate', 'unknown']),
    completedDate: z.string().optional(),
    completedYear: z
      .union([z.number(), z.string()])
      .optional()
      .transform((val) => {
        if (val === '' || val === undefined || val === null) return undefined;
        const n = typeof val === 'number' ? val : parseInt(val, 10);
        return Number.isNaN(n) ? undefined : n;
      }),
    completedMonth: z
      .union([z.number(), z.string()])
      .optional()
      .transform((val) => {
        if (val === '' || val === undefined || val === null) return undefined;
        const n = typeof val === 'number' ? val : parseInt(val, 10);
        return Number.isNaN(n) ? undefined : n;
      }),
    verificationMethod: z.enum([
      'leader_attestation',
      'attendance_roll',
      'historical_backfill',
      'pastoral_waiver',
    ]),
    sourceReference: z.string().max(200, 'Source reference cannot exceed 200 characters').optional(),
    verificationNotes: z.string().max(1000, 'Internal notes cannot exceed 1000 characters').optional(),
  })
  .superRefine((data, ctx) => {
    if (data.status === 'completed' || data.status === 'waived') {
      if (data.datePrecision === 'exact_date') {
        if (!data.completedDate) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['completedDate'],
            message: 'Completion date is required for exact date precision',
          });
        } else if (data.completedDate > today) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['completedDate'],
            message: 'Completion date cannot be in the future',
          });
        }
      } else if (data.datePrecision === 'month_year') {
        if (!data.completedYear || data.completedYear < 1980 || data.completedYear > currentYear) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['completedYear'],
            message: `Year must be between 1980 and ${currentYear}`,
          });
        }
        if (!data.completedMonth || data.completedMonth < 1 || data.completedMonth > 12) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['completedMonth'],
            message: 'Month must be between 1 and 12',
          });
        }
      } else if (data.datePrecision === 'year_only' || data.datePrecision === 'approximate') {
        if (!data.completedYear || data.completedYear < 1980 || data.completedYear > currentYear) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['completedYear'],
            message: `Year must be between 1980 and ${currentYear}`,
          });
        }
      }
    }
  });

export type RecordFormationProgramFormValues = z.input<typeof recordFormationProgramSchema>;

export const recordFormationTalkSchema = z
  .object({
    talkId: z.string().min(1, 'Please select a talk'),
    sessionStatus: z.enum(['attended', 'absent_excused', 'makeup_attended', 'waived']),
    attendedDate: z.string().optional(),
    notes: z.string().max(500, 'Notes cannot exceed 500 characters').optional(),
  })
  .superRefine((data, ctx) => {
    if (data.attendedDate && data.attendedDate > today) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['attendedDate'],
        message: 'Attended date cannot be in the future',
      });
    }
  });

export type RecordFormationTalkFormValues = z.input<typeof recordFormationTalkSchema>;

export const voidFormationRecordSchema = z.object({
  voidReason: z
    .string()
    .trim()
    .min(5, 'Reason must be at least 5 characters'),
});

export type VoidFormationRecordFormValues = z.infer<typeof voidFormationRecordSchema>;

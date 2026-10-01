import { z } from 'zod';

export const createHouseholdSchema = z
  .object({
    name: z
      .string()
      .min(1, 'Household name is required')
      .max(200, 'Household name cannot exceed 200 characters')
      .refine((v) => v.trim().length > 0, { message: 'Household name cannot be empty' }),
    code: z
      .string()
      .min(1, 'Household code is required')
      .max(50, 'Household code cannot exceed 50 characters')
      .regex(
        /^[a-z][a-z0-9_]*$/,
        'Code must start with a lowercase letter and contain only lowercase letters, digits, and underscores'
      ),
    parent_governance_node_id: z
      .string()
      .min(1, 'Parent Unit or Chapter placement is required'),
    pastoral_level: z
      .enum(['member', 'unit', 'chapter', 'area', 'fraternal']),
    household_category: z
      .enum(['pastoral', 'formation', 'mission', 'temporary', 'welcoming', 'other']),
    meeting_frequency: z
      .enum(['weekly', 'biweekly', 'monthly', 'quarterly', 'seasonal', 'variable']),
    meeting_day_of_week: z
      .number()
      .int()
      .min(0)
      .max(6)
      .nullable()
      .optional(),
    meeting_start_time: z
      .string()
      .nullable()
      .optional(),
    meeting_timezone_name: z
      .string()
      .min(1, 'Timezone is required'),
    meeting_location_type: z
      .enum(['residence', 'church', 'parish_hall', 'online', 'hybrid', 'variable', 'other']),
    meeting_location_text: z
      .string()
      .max(500, 'Location description cannot exceed 500 characters')
      .nullable()
      .optional(),
    target_member_count: z
      .number()
      .int()
      .positive('Target members must be greater than zero')
      .nullable()
      .optional(),
    maximum_member_count: z
      .number()
      .int()
      .positive('Maximum members must be greater than zero')
      .nullable()
      .optional(),
    accepts_new_members: z
      .boolean(),
    language_code: z
      .string()
      .min(2, 'Language code is required'),
    is_couple_household: z
      .boolean(),
  })
  .refine(
    (data) => {
      if (
        data.target_member_count != null &&
        data.maximum_member_count != null &&
        data.maximum_member_count < data.target_member_count
      ) {
        return false;
      }
      return true;
    },
    {
      message: 'Maximum members cannot be less than target members',
      path: ['maximum_member_count'],
    }
  );

export type CreateHouseholdFormValues = z.infer<typeof createHouseholdSchema>;

export const editHouseholdSchema = z
  .object({
    name: z
      .string()
      .min(1, 'Household name is required')
      .max(200, 'Household name cannot exceed 200 characters')
      .refine((v) => v.trim().length > 0, { message: 'Household name cannot be empty' }),
    code: z
      .string()
      .min(1, 'Household code is required')
      .max(50, 'Household code cannot exceed 50 characters')
      .regex(
        /^[a-z][a-z0-9_]*$/,
        'Code must start with a lowercase letter and contain only lowercase letters, digits, and underscores'
      ),
    pastoral_level: z
      .enum(['member', 'unit', 'chapter', 'area', 'fraternal'])
      .optional(),
    household_category: z
      .enum(['pastoral', 'formation', 'mission', 'temporary', 'welcoming', 'other']),
    meeting_frequency: z
      .enum(['weekly', 'biweekly', 'monthly', 'quarterly', 'seasonal', 'variable']),
    meeting_day_of_week: z
      .number()
      .int()
      .min(0)
      .max(6)
      .nullable()
      .optional(),
    meeting_start_time: z
      .string()
      .nullable()
      .optional(),
    meeting_timezone_name: z
      .string()
      .min(1, 'Timezone is required'),
    meeting_location_type: z
      .enum(['residence', 'church', 'parish_hall', 'online', 'hybrid', 'variable', 'other']),
    meeting_location_text: z
      .string()
      .max(500, 'Location description cannot exceed 500 characters')
      .nullable()
      .optional(),
    target_member_count: z
      .number()
      .int()
      .positive('Target members must be greater than zero')
      .nullable()
      .optional(),
    maximum_member_count: z
      .number()
      .int()
      .positive('Maximum members must be greater than zero')
      .nullable()
      .optional(),
    accepts_new_members: z
      .boolean(),
    language_code: z
      .string()
      .min(2, 'Language code is required'),
    is_couple_household: z
      .boolean(),
  })
  .refine(
    (data) => {
      if (
        data.target_member_count != null &&
        data.maximum_member_count != null &&
        data.maximum_member_count < data.target_member_count
      ) {
        return false;
      }
      return true;
    },
    {
      message: 'Maximum members cannot be less than target members',
      path: ['maximum_member_count'],
    }
  );

export type EditHouseholdFormValues = z.infer<typeof editHouseholdSchema>;

export const archiveHouseholdSchema = z.object({
  reason: z
    .string()
    .min(1, 'An archive reason is required')
    .max(500, 'Reason must not exceed 500 characters')
    .refine((v) => v.trim().length > 0, { message: 'Reason cannot be empty' }),
});

export type ArchiveHouseholdFormValues = z.infer<typeof archiveHouseholdSchema>;

export const assignHouseholdMemberSchema = z.object({
  member_id: z.string().uuid('Please select a valid member'),
  household_id: z.string().uuid('Please select a valid household'),
  effective_from: z
    .string()
    .min(1, 'Effective date is required')
    .refine((val) => {
      const today = new Date().toISOString().split('T')[0];
      return val <= today;
    }, {
      message: 'Future household assignment changes are not supported yet',
    }),
  confirm_governance_mismatch: z.boolean(),
});

export type AssignHouseholdMemberFormValues = z.infer<typeof assignHouseholdMemberSchema>;

export const transferHouseholdMemberSchema = z.object({
  member_id: z.string().uuid('Invalid member'),
  destination_household_id: z.string().uuid('Please select a destination household'),
  effective_date: z
    .string()
    .min(1, 'Effective date is required')
    .refine((val) => {
      const today = new Date().toISOString().split('T')[0];
      return val <= today;
    }, {
      message: 'Future household assignment changes are not supported yet',
    }),
  reason: z
    .string()
    .min(1, 'A transfer reason is required')
    .max(500, 'Reason must not exceed 500 characters')
    .refine((v) => v.trim().length > 0, { message: 'Reason cannot be empty' }),
  confirm_governance_mismatch: z.boolean(),
});

export type TransferHouseholdMemberFormValues = z.infer<typeof transferHouseholdMemberSchema>;

export const endHouseholdMembershipSchema = z.object({
  member_id: z.string().uuid('Invalid member'),
  effective_to: z
    .string()
    .min(1, 'Effective end date is required')
    .refine((val) => {
      const today = new Date().toISOString().split('T')[0];
      return val <= today;
    }, {
      message: 'Future household assignment changes are not supported yet',
    }),
  reason: z
    .string()
    .min(1, 'A reason is required')
    .max(500, 'Reason must not exceed 500 characters')
    .refine((v) => v.trim().length > 0, { message: 'Reason cannot be empty' }),
});

export type EndHouseholdMembershipFormValues = z.infer<typeof endHouseholdMembershipSchema>;

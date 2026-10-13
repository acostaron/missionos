import { z } from 'zod';
import { localToday } from '../formation/form-schemas';

export const placementWorklistMemberSchema = z.object({
  id: z.string().uuid(),
  display_name: z.string(),
  preferred_name: z.string().nullable(),
  member_number: z.string().nullable(),
  membership_status: z
    .object({
      code: z.string(),
      name: z.string(),
    })
    .nullable(),
  section: z
    .object({
      node_id: z.string().uuid(),
      code: z.string(),
      name: z.string(),
    })
    .nullable(),
  placement: z
    .object({
      node_id: z.string().uuid(),
      code: z.string(),
      name: z.string(),
      node_type_code: z.string(),
      parent_name: z.string().nullable(),
      effective_from: z.string(),
    })
    .nullable(),
});

export const placementWorklistResponseSchema = z.object({
  total_count: z.number(),
  page: z.number(),
  page_size: z.number(),
  summary: z.object({
    unplaced_count: z.number(),
    placed_count: z.number(),
  }),
  members: z.array(placementWorklistMemberSchema),
});

export const placeMembersBulkPlacedItemSchema = z.object({
  member_id: z.string().uuid(),
  previous_node_id: z.string().uuid().nullable(),
});

export const placeMembersBulkSkippedItemSchema = z.object({
  member_id: z.string().uuid(),
  reason: z.string(),
  message: z.string().optional(),
});

export const placeMembersBulkResponseSchema = z.object({
  status: z.string(),
  target_governance_node_id: z.string().uuid(),
  effective_from: z.string(),
  placed_count: z.number(),
  skipped_count: z.number(),
  placed: z.array(placeMembersBulkPlacedItemSchema),
  skipped: z.array(placeMembersBulkSkippedItemSchema),
  correlation_id: z.string().uuid(),
});

export const placeMembersSchema = z.object({
  targetNodeId: z.string().uuid('Please select a chapter or unit'),
  effectiveFrom: z
    .string()
    .min(1, 'Effective date is required')
    .refine((val) => {
      const today = localToday();
      return val <= today;
    }, 'Effective date cannot be in the future'),
  reason: z
    .string()
    .trim()
    .min(5, 'Reason must be at least 5 characters'),
});

export type PlaceMembersFormValues = z.infer<typeof placeMembersSchema>;

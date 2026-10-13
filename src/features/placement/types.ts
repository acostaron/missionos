import { z } from 'zod';
import {
  placementWorklistMemberSchema,
  placementWorklistResponseSchema,
  placeMembersBulkPlacedItemSchema,
  placeMembersBulkSkippedItemSchema,
  placeMembersBulkResponseSchema,
  changeMembersSectionBulkChangedItemSchema,
  changeMembersSectionBulkSkippedItemSchema,
  changeMembersSectionBulkResponseSchema,
} from './schemas';

export type PlacementWorklistMember = z.infer<typeof placementWorklistMemberSchema>;
export type PlacementWorklistResponse = z.infer<typeof placementWorklistResponseSchema>;
export type PlaceMembersBulkPlacedItem = z.infer<typeof placeMembersBulkPlacedItemSchema>;
export type PlaceMembersBulkSkippedItem = z.infer<typeof placeMembersBulkSkippedItemSchema>;
export type PlaceMembersBulkResponse = z.infer<typeof placeMembersBulkResponseSchema>;

export type ChangeMembersSectionBulkChangedItem = z.infer<
  typeof changeMembersSectionBulkChangedItemSchema
>;
export type ChangeMembersSectionBulkSkippedItem = z.infer<
  typeof changeMembersSectionBulkSkippedItemSchema
>;
export type ChangeMembersSectionBulkResponse = z.infer<
  typeof changeMembersSectionBulkResponseSchema
>;

export type PlacementView = 'unplaced' | 'placed' | 'all';

export interface FetchPlacementWorklistParams {
  view?: PlacementView;
  sectionNodeId?: string | null;
  search?: string | null;
  page?: number;
}

export interface PlaceMembersBulkParams {
  memberIds: string[];
  targetNodeId: string;
  effectiveFrom: string;
  reason: string;
}

export interface ChangeMembersSectionBulkParams {
  memberIds: string[];
  sectionCode: string;
  effectiveFrom: string;
  reason: string;
}

export interface SelectedMemberInfo {
  display_name: string;
  member_number: string | null;
  has_placement: boolean;
  section_code?: string | null;
}

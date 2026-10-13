import { supabase } from '../../lib/supabase/client';
import {
  placementWorklistResponseSchema,
  placeMembersBulkResponseSchema,
} from './schemas';
import type {
  FetchPlacementWorklistParams,
  PlacementWorklistResponse,
  PlaceMembersBulkParams,
  PlaceMembersBulkResponse,
} from './types';

export async function fetchPlacementWorklist(
  orgId: string,
  params: FetchPlacementWorklistParams
): Promise<PlacementWorklistResponse> {
  const { data, error } = await supabase.rpc('get_placement_worklist', {
    p_organization_id: orgId,
    p_view: params.view ?? 'unplaced',
    p_section_node_id: params.sectionNodeId || undefined,
    p_search: params.search?.trim() || undefined,
    p_page: params.page ?? 1,
    p_page_size: 100,
  });

  if (error) throw error;
  return placementWorklistResponseSchema.parse(data);
}

export async function placeMembersBulk(
  orgId: string,
  params: PlaceMembersBulkParams
): Promise<PlaceMembersBulkResponse> {
  const { data, error } = await supabase.rpc('place_members_bulk', {
    p_organization_id: orgId,
    p_member_ids: params.memberIds,
    p_target_governance_node_id: params.targetNodeId,
    p_effective_from: params.effectiveFrom,
    p_reason: params.reason,
  });

  if (error) throw error;
  return placeMembersBulkResponseSchema.parse(data);
}

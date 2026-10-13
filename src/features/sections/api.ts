import { supabase } from '../../lib/supabase/client';
import type {
  SectionsOverviewResponse,
  MemberSection,
  ChangeMemberSectionParams,
  SubAreaPlacementTarget,
  MoveMemberToSubAreaParams,
  MoveMemberToSubAreaResult,
} from './types';

export async function getSectionsOverview(organizationId: string): Promise<SectionsOverviewResponse> {
  const { data, error } = await supabase.rpc('get_sections_overview', {
    p_organization_id: organizationId,
  });

  if (error) throw error;
  return data as unknown as SectionsOverviewResponse;
}

export async function getMemberSection(
  organizationId: string,
  memberId: string
): Promise<MemberSection | null> {
  const { data, error } = await supabase.rpc('get_member_section', {
    p_organization_id: organizationId,
    p_member_id: memberId,
  });

  if (error) throw error;
  return data as unknown as MemberSection | null;
}

export async function changeMemberSection(params: ChangeMemberSectionParams): Promise<unknown> {
  const { data, error } = await supabase.rpc('change_member_section', {
    p_organization_id: params.organizationId,
    p_member_id: params.memberId,
    p_section_code: params.sectionCode,
    p_effective_from: params.effectiveFrom,
    p_reason: params.reason,
  });

  if (error) throw error;
  return data;
}

export async function getSubAreaPlacementTargets(
  organizationId: string,
  subAreaNodeId: string
): Promise<SubAreaPlacementTarget[]> {
  const { data, error } = await (supabase.rpc as any)('get_sub_area_placement_targets', {
    p_organization_id: organizationId,
    p_sub_area_node_id: subAreaNodeId,
  });

  if (error) throw error;
  return (data ?? []) as unknown as SubAreaPlacementTarget[];
}

export async function moveMemberToSubArea(
  params: MoveMemberToSubAreaParams
): Promise<MoveMemberToSubAreaResult> {
  const { data, error } = await (supabase.rpc as any)('move_member_to_sub_area', {
    p_organization_id: params.organizationId,
    p_member_id: params.memberId,
    p_section_code: params.sectionCode,
    p_target_governance_node_id: params.targetGovernanceNodeId,
    p_effective_from: params.effectiveFrom,
    p_reason: params.reason,
  });

  if (error) throw error;
  return data as unknown as MoveMemberToSubAreaResult;
}

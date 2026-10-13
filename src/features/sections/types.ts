export interface SectionCoordinatorPartner {
  member_id: string;
  display_name: string;
}

export interface SectionCoordinator {
  member_id: string;
  display_name: string;
  member_number: string;
  partner: SectionCoordinatorPartner | null;
  is_exception?: boolean;
  exception_reason?: string | null;
}

export interface SectionOverviewItem {
  node_id: string;
  code: string;
  name: string;
  kind?: string;
  active_member_count: number;
  coordinator: SectionCoordinator | null;
  is_exception?: boolean;
  exception_reason?: string | null;
}

export interface SubAreaOverview {
  node_id: string;
  code: string;
  name: string;
  sections: SectionOverviewItem[];
}

export interface FmcOverview {
  coordinator: SectionCoordinator | null;
  tagged_member_count: number;
  is_exception?: boolean;
  exception_reason?: string | null;
}

export interface SectionsOverviewResponse {
  sections: SectionOverviewItem[];
  fmc: FmcOverview;
  sub_areas?: SubAreaOverview[];
}

export interface MemberSectionPairedMember {
  id: string;
  display_name: string;
}

export interface MemberSection {
  section_code: string;
  section_name: string;
  section_node_id?: string;
  section_kind?: string;
  sub_area_node_id?: string;
  sub_area_code?: string;
  sub_area_name?: string;
  effective_from: string;
  paired_member: MemberSectionPairedMember | null;
}

export interface ChangeMemberSectionParams {
  organizationId: string;
  memberId: string;
  sectionCode: string;
  effectiveFrom?: string;
  reason: string;
}

export interface SubAreaPlacementTarget {
  node_id: string;
  code: string;
  name: string;
  node_type: string;
  parent_name: string | null;
}

export interface MoveMemberToSubAreaParams {
  organizationId: string;
  memberId: string;
  sectionCode: string;
  targetGovernanceNodeId: string;
  effectiveFrom?: string;
  reason: string;
}

export interface MoveMemberToSubAreaResult {
  status: string;
  member_id: string;
  sub_area_code: string;
  previous_section_code: string | null;
  section_code: string;
  previous_node_id: string | null;
  new_node_id: string;
  paired_member_id: string | null;
}

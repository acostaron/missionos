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
  active_member_count: number;
  coordinator: SectionCoordinator | null;
  is_exception?: boolean;
  exception_reason?: string | null;
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
}

export interface MemberSectionPairedMember {
  id: string;
  display_name: string;
}

export interface MemberSection {
  section_code: string;
  section_name: string;
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

export const SECTION_OPTIONS = [
  { code: 'sec_couples', name: 'Couples' },
  { code: 'sec_handmaids', name: 'Handmaids of the Lord' },
  { code: 'sec_servants', name: 'Servants of the Lord' },
  { code: 'sec_singles', name: 'Singles' },
  { code: 'sec_campus', name: 'Campus' },
  { code: 'sec_youth', name: 'Youth' },
  { code: 'sec_kids', name: 'Kids' },
] as const;

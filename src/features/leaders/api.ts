// Servant leader offices (Area / Chapter / Unit): list, appoint with spouse (Pass 9.20, Claude 2026-10-19).
import { useQuery, type QueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';
import type { ServantLeaderRoleCode } from '../households/types';

export type OfficeNodeType = 'area_state' | 'chapter' | 'unit';

export interface OfficeLeader {
  assignment_id: string;
  member_id: string;
  member_number: string | null;
  display_name: string;
  role_name: string;
  effective_from: string;
  has_login: boolean;
  access_status: 'active' | null;
  /** Pass 9.27: interim (temporary) appointment */
  is_interim?: boolean;
  spouse: { member_id: string; member_number: string | null; display_name: string } | null;
}

export interface LeaderOffice {
  node_id: string;
  node_name: string;
  node_type: OfficeNodeType;
  role_code: ServantLeaderRoleCode;
  parent_name: string | null;
  leader: OfficeLeader | null;
  /** Pass 9.20A: an Area placed under another Area (MFC New York, FMC New York) */
  is_sub_area?: boolean;
  /** Pass 9.20A: a coordinator appointed on this node (e.g. FMC Coordinator) */
  coordinator?: {
    role_name: string;
    member_number: string | null;
    display_name: string;
    partner: { member_number: string | null; display_name: string } | null;
  } | null;
}

export interface LeaderOfficesResponse {
  can_appoint: boolean;
  can_conclude: boolean;
  can_manage_access: boolean;
  offices: LeaderOffice[];
}

export const leaderOfficeKeys = {
  all: ['leaders', 'offices'] as const,
  list: (orgId: string | null) => [...leaderOfficeKeys.all, orgId] as const,
};

export function useLeaderOffices(orgId: string | null) {
  return useQuery<LeaderOfficesResponse>({
    queryKey: leaderOfficeKeys.list(orgId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_servant_leader_offices', { p_organization_id: orgId! });
      if (error) throw error;
      return data as unknown as LeaderOfficesResponse;
    },
    enabled: !!orgId,
  });
}

export async function appointLeaderWithSpouse(
  orgId: string,
  input: { roleCode: ServantLeaderRoleCode; nodeId: string; memberId: string; spouseMemberId: string | null; reason: string },
) {
  const { data, error } = await supabase.rpc('appoint_servant_leader_with_spouse', {
    p_organization_id: orgId,
    p_role_code: input.roleCode,
    p_governance_node_id: input.nodeId,
    p_member_id: input.memberId,
    p_spouse_member_id: input.spouseMemberId ?? undefined,
    p_reason: input.reason.trim() || undefined,
  });
  if (error) throw error;
  return data as unknown as { role_name: string; spouse_link: string; leadership_assignment_id?: string };
}

/** Pass 9.27 (Ron, 2026-10-21): mark or unmark an appointment as Interim. */
export async function setLeaderInterim(orgId: string, assignmentId: string, isInterim: boolean) {
  const { error } = await supabase.rpc('set_servant_leader_interim', {
    p_organization_id: orgId,
    p_leadership_assignment_id: assignmentId,
    p_is_interim: isInterim,
  });
  if (error) throw error;
}

export async function invalidateLeaderOffices(qc: QueryClient) {
  await qc.invalidateQueries({ queryKey: leaderOfficeKeys.all });
}

export const LEVEL_LABELS: Record<OfficeNodeType, string> = {
  area_state: 'Area',
  chapter: 'Chapter',
  unit: 'Unit',
};

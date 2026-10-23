// Structure (Pass 9.38C, Ron 2026-10-22): administrators add chapters and units, rename and retire them, and the
// Section each household belongs to.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export type StructureNodeType = 'area_state' | 'section' | 'chapter' | 'unit';

export interface StructureNode {
  id: string;
  code: string | null;
  name: string;
  type: StructureNodeType;
  parent_id: string | null;
  section_category: string | null;
  child_nodes: number;
  households: number;
  leaders: number;
}

export interface StructureTree {
  nodes: StructureNode[];
  /** sub-area id -> standard section kinds it does not have yet */
  missing_sections: Record<string, string[] | null>;
}

export interface SectionInfo {
  section_id: string;
  name: string;
  category: string | null;
  sub_area_id: string | null;
  sub_area_name: string | null;
}

export interface HouseholdSectionInfo extends Partial<SectionInfo> {
  from_tree: boolean;
  needs_section: boolean;
}

export const structureKeys = {
  tree: (orgId: string | null) => ['structure', 'tree', orgId] as const,
  householdSections: (orgId: string | null) => ['structure', 'household-sections', orgId] as const,
  sectionOptions: (orgId: string | null) => ['structure', 'section-options', orgId] as const,
  nodeSection: (orgId: string | null, nodeId: string | null) => ['structure', 'node-section', orgId, nodeId] as const,
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (supabase.rpc as any)(fn, args);
  if (error) throw error;
  return data as T;
}

export function useStructureTree(orgId: string | null) {
  return useQuery<StructureTree>({
    queryKey: structureKeys.tree(orgId),
    queryFn: () => rpc<StructureTree>('get_structure_tree', { p_organization_id: orgId }),
    enabled: !!orgId,
  });
}

function useStructureMutation<A>(orgId: string | null, fn: (a: A) => Promise<unknown>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['structure'] });
      qc.invalidateQueries({ queryKey: ['placement-nodes'] });
    },
    meta: { orgId },
  });
}

export function useCreateStructureNode(orgId: string | null) {
  return useStructureMutation(orgId, (a: { parentId: string; type: 'chapter' | 'unit'; name: string }) =>
    rpc('create_structure_node', {
      p_organization_id: orgId,
      p_parent_node_id: a.parentId,
      p_node_type: a.type,
      p_name: a.name,
    }),
  );
}

export function useRenameStructureNode(orgId: string | null) {
  return useStructureMutation(orgId, (a: { nodeId: string; name: string }) =>
    rpc('rename_structure_node', { p_organization_id: orgId, p_node_id: a.nodeId, p_name: a.name }),
  );
}

export function useRetireStructureNode(orgId: string | null) {
  return useStructureMutation(orgId, (a: { nodeId: string; reason?: string }) =>
    rpc('retire_structure_node', { p_organization_id: orgId, p_node_id: a.nodeId, p_reason: a.reason ?? null }),
  );
}

export function useAddStandardSections(orgId: string | null) {
  return useStructureMutation(orgId, (subAreaId: string) =>
    rpc('add_standard_sections', { p_organization_id: orgId, p_sub_area_node_id: subAreaId }),
  );
}

export function useHouseholdSections(orgId: string | null) {
  return useQuery<Record<string, HouseholdSectionInfo>>({
    queryKey: structureKeys.householdSections(orgId),
    queryFn: () => rpc<Record<string, HouseholdSectionInfo>>('get_household_sections', { p_organization_id: orgId }),
    enabled: !!orgId,
  });
}

export function useSectionOptions(orgId: string | null, enabled = true) {
  return useQuery<SectionInfo[]>({
    queryKey: structureKeys.sectionOptions(orgId),
    queryFn: async () => (await rpc<SectionInfo[] | null>('get_section_options', { p_organization_id: orgId })) ?? [],
    enabled: !!orgId && enabled,
    staleTime: 5 * 60 * 1000,
  });
}

export function useNodeSection(orgId: string | null, nodeId: string | null) {
  return useQuery<SectionInfo | null>({
    queryKey: structureKeys.nodeSection(orgId, nodeId),
    queryFn: () => rpc<SectionInfo | null>('get_node_section', { p_organization_id: orgId, p_node_id: nodeId }),
    enabled: !!orgId && !!nodeId,
  });
}

export async function setHouseholdSection(orgId: string, householdId: string, sectionId: string | null) {
  return rpc('set_household_section', {
    p_organization_id: orgId,
    p_household_id: householdId,
    p_section_node_id: sectionId,
  });
}

export function useSetHouseholdSection(orgId: string | null) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (a: { householdId: string; sectionId: string | null }) =>
      setHouseholdSection(orgId!, a.householdId, a.sectionId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['structure'] }),
  });
}

export function sectionLabel(s: Partial<SectionInfo> | null | undefined): string {
  if (!s?.name) return '';
  return s.sub_area_name ? `${s.name} · ${s.sub_area_name}` : s.name;
}

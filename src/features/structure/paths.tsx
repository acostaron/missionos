// Pass 9.40 (Ron, 2026-10-22): where each area, section, chapter, unit and household sits — MFC New York or FMC New
// York, then Section, Chapter and Unit — so Pastoral Operations (Households, Dashboard, Leaders) can group by it.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export interface NodePath {
  type: 'area_state' | 'section' | 'chapter' | 'unit' | 'household';
  area_name: string | null;
  sub_area_id: string | null;
  sub_area_name: string | null;
  sub_area_code: string | null;
  section_id: string | null;
  section_name: string | null;
  section_category: string | null;
  chapter_id: string | null;
  chapter_name: string | null;
  unit_id: string | null;
  unit_name: string | null;
}

export type NodePaths = Record<string, NodePath>;

export function useNodePaths(orgId: string | null, enabled = true) {
  return useQuery<NodePaths>({
    queryKey: ['structure', 'node-paths', orgId],
    queryFn: async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase.rpc as any)('get_node_paths', { p_organization_id: orgId });
      if (error) throw error;
      return (data ?? {}) as NodePaths;
    },
    enabled: !!orgId && enabled,
    staleTime: 60 * 1000,
  });
}

const SECTION_ORDER = ['couples', 'handmaids', 'servants', 'singles', 'campus', 'youth', 'kids'];
const SUB_AREA_ORDER = ['mfc_ny', 'fmc_ny'];
const NOT_PLACED = '__none__';
const AREA_LEVEL = '__area__';

function subAreaRank(p: NodePath | undefined): number {
  if (!p) return 900;
  if (!p.sub_area_id) return 0;
  const i = SUB_AREA_ORDER.indexOf(p.sub_area_code ?? '');
  return i >= 0 ? i + 1 : 50;
}

function sectionRank(p: NodePath | undefined): number {
  if (!p?.section_id) return 0; // sub-area-wide items come first
  const i = SECTION_ORDER.indexOf(p.section_category ?? '');
  return i >= 0 ? i + 1 : 50;
}

export function subAreaKey(p: NodePath | undefined): string {
  if (!p) return NOT_PLACED;
  return p.sub_area_id ?? AREA_LEVEL;
}

export function subAreaTitle(p: NodePath | undefined): string {
  if (!p) return 'Not placed';
  return p.sub_area_name ?? p.area_name ?? 'Area';
}

export interface PathGroup<T> {
  key: string;
  subAreaKey: string;
  subAreaTitle: string;
  /** "Couples Section · Arch New York Chapter"; empty for items directly under the sub-area. */
  title: string;
  sectionName: string | null;
  chapterName: string | null;
  items: T[];
}

/** Groups items by sub-area, then section, then chapter, in ministry order. Unit stays on each item (see unitOf). */
export function groupByPath<T>(items: T[], nodeIdOf: (t: T) => string | null | undefined, paths: NodePaths | undefined): PathGroup<T>[] {
  const groups = new Map<string, PathGroup<T> & { rank: [number, number, number, string, string] }>();
  for (const it of items) {
    const id = nodeIdOf(it);
    const p = id ? paths?.[id] : undefined;
    const sa = subAreaKey(p);
    const key = `${sa}|${p?.section_id ?? ''}|${p?.chapter_id ?? ''}`;
    let g = groups.get(key);
    if (!g) {
      const title = [p?.section_name, p?.chapter_name].filter(Boolean).join(' · ');
      g = {
        key,
        subAreaKey: sa,
        subAreaTitle: subAreaTitle(p),
        title,
        sectionName: p?.section_name ?? null,
        chapterName: p?.chapter_name ?? null,
        items: [],
        rank: [subAreaRank(p), sectionRank(p), p?.chapter_id ? 1 : 0, p?.sub_area_name ?? '', `${p?.section_name ?? ''}|${p?.chapter_name ?? ''}`],
      };
      groups.set(key, g);
    }
    g.items.push(it);
  }
  return [...groups.values()]
    .sort((a, b) => {
      for (let i = 0; i < 3; i++) if (a.rank[i] !== b.rank[i]) return (a.rank[i] as number) - (b.rank[i] as number);
      return a.rank[3].localeCompare(b.rank[3]) || a.rank[4].localeCompare(b.rank[4]);
    })
    .map(({ rank: _rank, ...g }) => g);
}

/** The label for a group: "Couples Section · Arch New York Chapter", or where it sits when it has no section. */
export function groupLabel(g: Pick<PathGroup<unknown>, 'title' | 'subAreaKey' | 'subAreaTitle'>): string {
  if (g.title) return g.title;
  return g.subAreaKey === NOT_PLACED ? 'Not placed' : `Directly under ${g.subAreaTitle}`;
}

export function unitOf(paths: NodePaths | undefined, nodeId: string | null | undefined): string | null {
  if (!nodeId) return null;
  return paths?.[nodeId]?.unit_name ?? null;
}

export interface PathFilterValue {
  subArea: string; // 'all' | sub-area key
  section: string; // 'all' | section category
}

export const ALL_PATHS: PathFilterValue = { subArea: 'all', section: 'all' };

export function matchesPathFilter(p: NodePath | undefined, f: PathFilterValue): boolean {
  if (f.subArea !== 'all' && subAreaKey(p) !== f.subArea) return false;
  if (f.section !== 'all' && (p?.section_category ?? '') !== f.section) return false;
  return true;
}

const SECTION_LABEL: Record<string, string> = {
  couples: 'Couples', handmaids: 'Handmaids', servants: 'Servants', singles: 'Singles', campus: 'Campus', youth: 'Youth',
  kids: 'Kids',
};

/** Sub-area and Section selects, built from the items on the page. */
export function PathFilter({
  paths,
  nodeIds,
  value,
  onChange,
  className = '',
}: {
  paths: NodePaths | undefined;
  nodeIds: (string | null | undefined)[];
  value: PathFilterValue;
  onChange: (v: PathFilterValue) => void;
  className?: string;
}) {
  const subAreas = new Map<string, { title: string; rank: number }>();
  const sections = new Set<string>();
  for (const id of nodeIds) {
    const p = id ? paths?.[id] : undefined;
    subAreas.set(subAreaKey(p), { title: subAreaTitle(p), rank: subAreaRank(p) });
    if (p?.section_category && (value.subArea === 'all' || subAreaKey(p) === value.subArea)) sections.add(p.section_category);
  }
  if (subAreas.size <= 1 && sections.size <= 1) return null;
  const sel =
    'rounded-lg border border-line bg-surface px-2.5 py-1.5 text-xs text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus';
  return (
    <div className={`flex flex-wrap items-center gap-2 ${className}`}>
      <select
        aria-label="MFC or FMC"
        className={sel}
        value={value.subArea}
        onChange={(e) => onChange({ subArea: e.target.value, section: 'all' })}
      >
        <option value="all">MFC and FMC</option>
        {[...subAreas.entries()]
          .sort((a, b) => a[1].rank - b[1].rank || a[1].title.localeCompare(b[1].title))
          .map(([k, v]) => (
            <option key={k} value={k}>
              {v.title}
            </option>
          ))}
      </select>
      <select
        aria-label="Section"
        className={sel}
        value={value.section}
        onChange={(e) => onChange({ ...value, section: e.target.value })}
      >
        <option value="all">All sections</option>
        {SECTION_ORDER.filter((c) => sections.has(c)).map((c) => (
          <option key={c} value={c}>
            {SECTION_LABEL[c]}
          </option>
        ))}
      </select>
    </div>
  );
}

/** Heading shown when the sub-area changes from one group to the next. */
export function SubAreaHeading({ title }: { title: string }) {
  return <h2 className="pt-2 text-sm font-bold uppercase tracking-wide text-ink">{title}</h2>;
}

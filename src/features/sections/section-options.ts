import type { SectionsOverviewResponse } from './types';

export interface SectionMeta {
  nodeId: string;
  code: string;
  name: string;
  kind?: string;
  subAreaCode?: string;
  subAreaName?: string;
  displayLabel: string;
}

export interface SubAreaGroup {
  subAreaNodeId?: string;
  subAreaCode: string;
  subAreaName: string;
  sections: SectionMeta[];
}

export interface ParsedSectionOptions {
  groups: SubAreaGroup[];
  byCode: Map<string, SectionMeta>;
  getDisplayLabel: (code?: string | null) => string;
}

export function parseSectionOptions(overview?: SectionsOverviewResponse | null): ParsedSectionOptions {
  const byCode = new Map<string, SectionMeta>();
  const groups: SubAreaGroup[] = [];

  if (!overview) {
    return {
      groups,
      byCode,
      getDisplayLabel: (code) => code || '',
    };
  }

  if (overview.sub_areas && overview.sub_areas.length > 0) {
    for (const sa of overview.sub_areas) {
      const sectionMetas: SectionMeta[] = [];
      for (const s of sa.sections) {
        const displayLabel = `${sa.name} · ${s.name}`;
        const meta: SectionMeta = {
          nodeId: s.node_id,
          code: s.code,
          name: s.name,
          kind: s.kind,
          subAreaCode: sa.code,
          subAreaName: sa.name,
          displayLabel,
        };
        sectionMetas.push(meta);
        byCode.set(s.code, meta);
      }
      groups.push({
        subAreaNodeId: sa.node_id,
        subAreaCode: sa.code,
        subAreaName: sa.name,
        sections: sectionMetas,
      });
    }
  } else if (overview.sections && overview.sections.length > 0) {
    const sectionMetas: SectionMeta[] = [];
    for (const s of overview.sections) {
      const displayLabel = s.name;
      const meta: SectionMeta = {
        nodeId: s.node_id,
        code: s.code,
        name: s.name,
        kind: s.kind,
        displayLabel,
      };
      sectionMetas.push(meta);
      byCode.set(s.code, meta);
    }
    groups.push({
      subAreaCode: '',
      subAreaName: '',
      sections: sectionMetas,
    });
  }

  const getDisplayLabel = (code?: string | null): string => {
    if (!code) return '';
    return byCode.get(code)?.displayLabel || code;
  };

  return {
    groups,
    byCode,
    getDisplayLabel,
  };
}

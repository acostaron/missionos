import type { PastoralLevel } from '../households/types';

/**
 * Presentation-layer labels for formal pastoral offices and software roles.
 * Backend codes are never rendered directly.
 */
const SERVANT_ROLE_LABELS: Record<string, string> = {
  household_servant_leader: 'Household Servant Leader',
  unit_servant_leader: 'Unit Servant Leader',
  chapter_servant_leader: 'Chapter Servant Leader',
  area_servant_leader: 'Area Servant Leader',
};

const APP_ROLE_LABELS: Record<string, string> = {
  organization_administrator: 'Organization Administrator',
};

export const ORGANIZATION_ADMINISTRATOR_ROLE_CODE = 'organization_administrator';

/** Servant-leader office label; falls back to a generic label, never the raw code. */
export function servantRoleLabel(code: string | null | undefined): string {
  return (code && SERVANT_ROLE_LABELS[code]) || 'Servant Leader';
}

export function appRoleLabel(code: string | null | undefined): string | null {
  return (code && APP_ROLE_LABELS[code]) || null;
}

const LEVEL_TO_OFFICE: Record<string, string> = {
  household: 'Household Servant Leader',
  unit: 'Unit Servant Leader',
  chapter: 'Chapter Servant Leader',
  area: 'Area Servant Leader',
};

/** Office label for a care-responsibility level. */
export function officeForLevel(level: string | PastoralLevel | null | undefined): string {
  return (level && LEVEL_TO_OFFICE[level]) || 'Servant Leader';
}

export function pluralize(count: number, singular: string, plural?: string): string {
  return `${count} ${count === 1 ? singular : (plural ?? `${singular}s`)}`;
}

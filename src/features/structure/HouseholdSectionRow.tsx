// Section row on the household profile (Pass 9.38C, Ron 2026-10-22). A household under a chapter / unit takes the
// chapter's section; one placed directly under an Area has a chosen section that can be changed here.
import { useState } from 'react';
import { normalizeError } from '../../lib/supabase/errors';
import { sectionLabel, useHouseholdSections, useSectionOptions, useSetHouseholdSection } from './api';

export function HouseholdSectionRow({
  orgId,
  householdId,
  canEdit,
}: {
  orgId: string;
  householdId: string;
  canEdit: boolean;
}) {
  const { data: sections } = useHouseholdSections(orgId);
  const info = sections?.[householdId];
  const [editing, setEditing] = useState(false);
  const { data: options } = useSectionOptions(orgId, editing);
  const save = useSetHouseholdSection(orgId);
  const [error, setError] = useState<string | null>(null);

  if (!info) return null;
  const changeable = canEdit && !info.from_tree;

  return (
    <div className="space-y-1">
      <div className="flex justify-between items-center gap-3">
        <span className="text-ink-muted shrink-0">Section</span>
        <span className="font-medium text-ink text-right">
          {info.name ? (
            sectionLabel(info)
          ) : info.needs_section ? (
            <span className="text-warning-700">Not set</span>
          ) : (
            <span className="text-ink-muted italic">Several sections</span>
          )}
          {changeable && !editing && (
            <button type="button" className="ml-2 text-[11px] text-primary hover:underline" onClick={() => setEditing(true)}>
              Change
            </button>
          )}
        </span>
      </div>
      {editing && (
        <div className="flex items-center gap-2">
          <select
            className="min-w-0 flex-1 rounded-md border border-line bg-surface px-2 py-1 text-xs text-ink"
            defaultValue={info.section_id ?? ''}
            aria-label="Section"
            disabled={save.isPending}
            onChange={async (e) => {
              setError(null);
              try {
                await save.mutateAsync({ householdId, sectionId: e.target.value || null });
                setEditing(false);
              } catch (err) {
                setError(normalizeError(err).message);
              }
            }}
          >
            <option value="">No section (serves several sections)</option>
            {(options ?? []).map((s) => (
              <option key={s.section_id} value={s.section_id}>
                {sectionLabel(s)}
              </option>
            ))}
          </select>
          <button type="button" className="text-[11px] text-ink-muted hover:underline" onClick={() => setEditing(false)}>
            Cancel
          </button>
        </div>
      )}
      {error && <p className="text-[11px] text-danger-700">{error}</p>}
    </div>
  );
}

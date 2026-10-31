import { useState } from 'react';
import { Search, X } from 'lucide-react';
import { Button, FormField, Input } from '../../../components/ui';
import { useActivityMemberSearch } from '../queries';
import type { ActivityMemberOption, ActivityTarget } from '../types';

interface MemberPickerProps {
  organizationId: string;
  target: ActivityTarget;
  selected: ActivityMemberOption | null;
  onSelect: (m: ActivityMemberOption | null) => void;
}

/** Scoped member search (server returns only id, name, member number). */
export function MemberPicker({ organizationId, target, selected, onSelect }: MemberPickerProps) {
  const [query, setQuery] = useState('');
  const { data, isFetching } = useActivityMemberSearch(organizationId, target, query);

  if (selected) {
    return (
      <div className="flex items-center justify-between rounded-control border border-line bg-surface-muted/50 p-3">
        <div>
          <p className="text-body font-medium text-ink">{selected.display_name}</p>
          <p className="text-caption text-ink-muted">{selected.member_number || 'No member number'}</p>
        </div>
        <Button size="sm" variant="ghost" icon={<X className="h-3.5 w-3.5" />} onClick={() => onSelect(null)}>
          Change
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <FormField label="Search members">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
          <Input
            id="activity-team-member-search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Type at least 2 letters of a name or member number"
            className="pl-9"
            autoFocus
          />
        </div>
      </FormField>
      {query.trim().length >= 2 && (
        <div className="max-h-56 divide-y divide-line overflow-y-auto rounded-card border border-line bg-surface">
          {isFetching && !data ? (
            <p className="p-4 text-center text-small text-ink-muted">Searching…</p>
          ) : !data || data.length === 0 ? (
            <p className="p-4 text-center text-small text-ink-muted">No matching active members.</p>
          ) : (
            data.map((m) => (
              <button
                type="button"
                key={m.member_id}
                className="flex w-full items-center justify-between p-3 text-left transition-colors hover:bg-surface-muted"
                onClick={() => onSelect(m)}
              >
                <span className="text-body font-medium text-ink">{m.display_name}</span>
                <span className="text-caption text-ink-muted">{m.member_number || ''}</span>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}

// Appoint an Area / Chapter / Unit Servant Leader, linking husband and wife in the same step (Pass 9.20, Claude 2026-10-19).
// The server creates the family record and spouse link only if they are missing, then appoints — all or nothing.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Search, X } from 'lucide-react';
import { useSearchMembers, type MemberListItem } from '../members/queries';
import { normalizeError } from '../../lib/supabase/errors';
import { Alert, Button, Input, Modal } from '../../components/ui';
import { LEVEL_LABELS, appointLeaderWithSpouse, invalidateLeaderOffices, setLeaderInterim, type LeaderOffice } from './api';

function MemberPicker({
  orgId,
  label,
  value,
  onChange,
  excludeId,
}: {
  orgId: string;
  label: string;
  value: MemberListItem | null;
  onChange: (m: MemberListItem | null) => void;
  excludeId?: string;
}) {
  const [q, setQ] = useState('');
  const query = q.trim();
  const { data, isLoading } = useSearchMembers(query.length >= 2 ? orgId : null, {
    search: query || undefined,
    recordStatus: 'active',
    page: 1,
    pageSize: 8,
  });
  const found = (data?.members ?? []).filter((m) => m.id !== excludeId);

  return (
    <div className="space-y-1">
      <span className="block text-xs font-medium text-ink-secondary">{label}</span>
      {value ? (
        <div className="flex items-center justify-between rounded-control border border-line bg-surface-muted px-3 py-2 text-sm">
          <span className="text-ink">
            {value.display_name}
            {value.member_number && <span className="ml-2 text-xs text-ink-muted">{value.member_number}</span>}
          </span>
          <button type="button" aria-label={`Clear ${label}`} onClick={() => onChange(null)} className="text-ink-muted hover:text-ink">
            <X className="h-4 w-4" />
          </button>
        </div>
      ) : (
        <>
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
            <Input className="pl-9" placeholder="Search name or member number" value={q} onChange={(e) => setQ(e.target.value)} />
          </div>
          {query.length >= 2 && (
            <ul className="max-h-40 divide-y divide-line overflow-y-auto rounded-control border border-line">
              {isLoading ? (
                <li className="px-3 py-2 text-xs text-ink-muted">Searching…</li>
              ) : found.length === 0 ? (
                <li className="px-3 py-2 text-xs text-ink-muted">No active member found.</li>
              ) : (
                found.map((m) => (
                  <li key={m.id}>
                    <button
                      type="button"
                      className="w-full px-3 py-2 text-left text-sm hover:bg-surface-muted"
                      onClick={() => {
                        onChange(m);
                        setQ('');
                      }}
                    >
                      {m.display_name}
                      {m.member_number && <span className="ml-2 text-xs text-ink-muted">{m.member_number}</span>}
                    </button>
                  </li>
                ))
              )}
            </ul>
          )}
        </>
      )}
    </div>
  );
}

export function AppointLeaderModal({
  orgId,
  office,
  onClose,
  onDone,
}: {
  orgId: string;
  office: LeaderOffice;
  onClose: () => void;
  onDone: (msg: string) => void;
}) {
  const qc = useQueryClient();
  const [leader, setLeader] = useState<MemberListItem | null>(null);
  const [spouse, setSpouse] = useState<MemberListItem | null>(null);
  const [reason, setReason] = useState('');
  const [interim, setInterim] = useState(false);
  const [busy, setBusy] = useState(false);
  const [errorText, setErrorText] = useState<string | null>(null);
  const level = LEVEL_LABELS[office.node_type];

  const save = async () => {
    if (!leader) return;
    try {
      setBusy(true);
      setErrorText(null);
      const res = await appointLeaderWithSpouse(orgId, {
        roleCode: office.role_code,
        nodeId: office.node_id,
        memberId: leader.id,
        spouseMemberId: spouse?.id ?? null,
        reason,
      });
      // Pass 9.27: mark the new appointment as Interim when ticked.
      if (interim && res.leadership_assignment_id) {
        await setLeaderInterim(orgId, res.leadership_assignment_id, true);
      }
      await invalidateLeaderOffices(qc);
      onDone(
        `${spouse ? `${leader.display_name} & ${spouse.display_name}` : leader.display_name} appointed for ${office.node_name}.`,
      );
      onClose();
    } catch (e) {
      setErrorText(normalizeError(e).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      closeOnBackdrop={false}
      title={`Appoint ${level} Servant Leader`}
      description={office.node_name}
      footer={
        <div className="flex w-full justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={save} disabled={!leader || busy} loading={busy}>
            Appoint
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        {errorText && (
          <Alert variant="danger" title="Could not appoint">
            {errorText}
          </Alert>
        )}
        <MemberPicker orgId={orgId} label="Servant leader (the husband, for a couple)" value={leader} onChange={setLeader} excludeId={spouse?.id} />
        <MemberPicker orgId={orgId} label="Wife (optional — couples serve together)" value={spouse} onChange={setSpouse} excludeId={leader?.id} />
        <label className="flex items-center gap-2 text-sm text-ink">
          <input type="checkbox" checked={interim} onChange={(e) => setInterim(e.target.checked)} />
          Interim appointment (temporary, while leadership is being discerned)
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">Note (optional)</span>
          <Input value={reason} maxLength={200} placeholder="e.g. Appointed by the Area Council" onChange={(e) => setReason(e.target.value)} />
        </label>
        <p className="text-xs text-ink-muted">
          When a wife is chosen, the app links them as husband and wife (it creates their family record if they have none)
          and she appears with him as {level} Servant Leaders. App access is granted separately, once each has a login.
        </p>
      </div>
    </Modal>
  );
}

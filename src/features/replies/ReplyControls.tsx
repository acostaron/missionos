// Reply buttons for members and a replies summary for leaders (Pass 9.28, Ron 2026-10-21).
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Check, X } from 'lucide-react';
import { normalizeError } from '../../lib/supabase/errors';
import { invalidateReplies, setMyReply, type RepliesSummary, type ReplyResponse } from './api';
import { invalidatePayments } from '../events/payments';

/** "Will you attend?" — Attending / Not attending. Tapping the chosen answer again clears it. */
export function ReplyButtons({
  orgId,
  target,
  current,
}: {
  orgId: string;
  target: { eventId?: string; householdMeetingId?: string };
  current: ReplyResponse | null;
}) {
  const qc = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const choose = async (r: ReplyResponse) => {
    try {
      setBusy(true);
      setError(null);
      await setMyReply(orgId, target, current === r ? null : r);
      await invalidateReplies(qc);
      await invalidatePayments(qc); // Pass 9.29: a reply may register / cancel the registration
    } catch (e) {
      setError(normalizeError(e).message);
    } finally {
      setBusy(false);
    }
  };

  const base = 'inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs font-medium transition-colors disabled:opacity-60';
  return (
    <div className="space-y-1 pt-1">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-ink-secondary">Will you attend?</span>
        <button
          type="button"
          disabled={busy}
          aria-pressed={current === 'attending'}
          onClick={() => void choose('attending')}
          className={`${base} ${current === 'attending' ? 'border-success-600 bg-success-50 text-success-700' : 'border-line text-ink-secondary hover:bg-surface-muted'}`}
        >
          <Check className="h-3.5 w-3.5" /> Attending
        </button>
        <button
          type="button"
          disabled={busy}
          aria-pressed={current === 'not_attending'}
          onClick={() => void choose('not_attending')}
          className={`${base} ${current === 'not_attending' ? 'border-danger-600 bg-danger-50 text-danger-700' : 'border-line text-ink-secondary hover:bg-surface-muted'}`}
        >
          <X className="h-3.5 w-3.5" /> Not attending
        </button>
      </div>
      {error && <p className="text-xs text-danger-700">{error}</p>}
    </div>
  );
}

/** Counts, with a tap to see who replied. */
export function RepliesSummaryView({ data, dark = false }: { data: RepliesSummary | undefined; dark?: boolean }) {
  const [open, setOpen] = useState(false);
  if (!data) return null;
  const { attending, not_attending, counts } = data;
  const muted = dark ? 'text-slate-400' : 'text-ink-muted';
  const text = dark ? 'text-slate-200' : 'text-ink-secondary';
  const total = counts.attending + counts.not_attending;
  return (
    <div className={`text-xs ${text}`}>
      <button type="button" onClick={() => setOpen((v) => !v)} disabled={total === 0} className="hover:underline disabled:no-underline">
        Replies: {counts.attending} attending · {counts.not_attending} not attending
        {total > 0 && <span className={`ml-1 ${muted}`}>({open ? 'hide' : 'show'} names)</span>}
      </button>
      {open && total > 0 && (
        <div className="mt-1 grid gap-2 sm:grid-cols-2">
          <div>
            <p className="font-semibold">Attending</p>
            {attending.length === 0 ? <p className={muted}>None yet</p> : attending.map((p) => <p key={p.member_id}>{p.display_name}</p>)}
          </div>
          <div>
            <p className="font-semibold">Not attending</p>
            {not_attending.length === 0 ? <p className={muted}>None</p> : not_attending.map((p) => <p key={p.member_id}>{p.display_name}</p>)}
          </div>
        </div>
      )}
    </div>
  );
}

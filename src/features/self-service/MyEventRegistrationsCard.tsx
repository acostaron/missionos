// My Events: registration for one event — price, my registration and balance, advance payment, guests
// (Pass 9.14 / 9.15, Claude 2026-10-16). Pass 9.31 (Ron 2026-10-21): shown inside the event's item in Upcoming
// instead of a separate "Event registration" card, so each event appears once. Attending registers and
// Not attending cancels an unpaid registration (Pass 9.29), so there is no separate Cancel button.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { QrCode, UserPlus } from 'lucide-react';
import { formatNyDateShort } from '../../lib/ny-time';
import { getEventErrorMessage } from '../events/error-message';
import {
  PRICE_TIER_LABELS,
  addEventGuest,
  cancelEventGuest,
  invalidatePayments,
  money,
  type EventGuest,
  type MyEventRegistration,
} from '../events/payments';
import { GuestForm } from '../events/components/GuestForm';
import { GuestPassModal } from '../events/components/GuestPassModal';
import { AdvancePaymentBlock } from '../events/components/AdvancePaymentBlock';
import type { MyPaymentReport } from '../events/advance-payments';
import { invalidateReplies, setMyReply } from '../replies/api';
import { Badge, Button } from '../../components/ui';

function priceText(e: MyEventRegistration) {
  if (!e.fee_amount) return 'Free';
  const parts = [];
  if (e.early_bird_fee != null && e.early_bird_until) {
    parts.push(`Early-bird ${money(e.early_bird_fee)} until ${formatNyDateShort(e.early_bird_until)}`);
  }
  parts.push(`Regular ${money(e.fee_amount)}`);
  if (e.walk_in_fee != null) parts.push(`Walk-in ${money(e.walk_in_fee)}`);
  return parts.join(' · ');
}

export function EventRegistrationPanel({
  orgId,
  reg,
  guests,
  reports,
}: {
  orgId: string;
  reg: MyEventRegistration;
  guests: EventGuest[];
  reports: MyPaymentReport[];
}) {
  const qc = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [adding, setAdding] = useState(false);
  const [pass, setPass] = useState<EventGuest | null>(null);
  const [errorText, setErrorText] = useState<string | null>(null);
  const my = reg.my;

  const run = async (fn: () => Promise<unknown>) => {
    try {
      setBusy(true);
      setErrorText(null);
      await fn();
      await invalidatePayments(qc);
      await invalidateReplies(qc);
      return true;
    } catch (e) {
      setErrorText(getEventErrorMessage(e));
      return false;
    } finally {
      setBusy(false);
    }
  };

  const guestsBlock = (
    <div className="space-y-1.5 pt-1">
      {guests.length > 0 && (
        <ul className="space-y-1">
          {guests.map((g) => {
            const p = g.payment;
            const due = p.status === 'unpaid' || p.status === 'partial';
            return (
              <li key={g.guest_id} className="flex flex-wrap items-center gap-2 text-sm">
                <span className="text-ink">Guest: {g.display_name}</span>
                {p.status === 'paid' && <Badge variant="success">Paid</Badge>}
                {p.status === 'waived' && <Badge variant="info">Fee waived</Badge>}
                {due && <Badge variant="warning">{money(p.balance)} due</Badge>}
                {g.checked_in_today && <Badge variant="success">Checked in</Badge>}
                <Button size="sm" variant="ghost" icon={<QrCode className="h-4 w-4" />} onClick={() => setPass(g)}>
                  Guest pass
                </Button>
                {p.paid === 0 && !g.checked_in_ever && (
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={busy}
                    onClick={() => {
                      if (window.confirm(`Remove ${g.display_name} from your guests?`)) {
                        void run(() => cancelEventGuest(orgId, g.guest_id));
                      }
                    }}
                  >
                    Remove
                  </Button>
                )}
              </li>
            );
          })}
        </ul>
      )}
      {guests.some((g) => g.payment.status === 'unpaid' || g.payment.status === 'partial') && (
        <p className="text-xs text-ink-secondary">Pay for your guests with the registration team or the treasurer.</p>
      )}
      {reg.registration_open &&
        (adding ? (
          <div className="rounded-card border border-line p-3">
            <p className="mb-2 text-xs font-semibold text-ink-secondary">Add a guest (non-member)</p>
            <GuestForm
              submitLabel="Add guest"
              busy={busy}
              onSubmit={async (f) => {
                const ok = await run(() => addEventGuest(orgId, reg.event_id, f, { asStaff: false }));
                if (ok) setAdding(false);
                return ok;
              }}
              extra={
                <Button type="button" size="sm" variant="ghost" onClick={() => setAdding(false)}>
                  Cancel
                </Button>
              }
            />
          </div>
        ) : (
          <Button size="sm" variant="outline" icon={<UserPlus className="h-4 w-4" />} onClick={() => setAdding(true)}>
            Add a guest
          </Button>
        ))}
    </div>
  );

  return (
    <div className="space-y-1.5 border-t border-line pt-2">
      <p className="text-xs text-ink-muted">
        Registration · {priceText(reg)}
      </p>
      {my.registered ? (
        <div className="space-y-1">
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <Badge variant="success">Registered</Badge>
            {my.status === 'paid' && <Badge variant="success">Paid</Badge>}
            {my.status === 'waived' && <Badge variant="info">Fee waived</Badge>}
            {(my.status === 'unpaid' || my.status === 'partial') && <Badge variant="warning">{money(my.balance)} due</Badge>}
            {my.price_tier && my.price_tier !== 'free' && (
              <span className="text-xs text-ink-muted">
                {PRICE_TIER_LABELS[my.price_tier]} price {money(my.fee)}
              </span>
            )}
          </div>
          {(my.status === 'unpaid' || my.status === 'partial') && (
            <AdvancePaymentBlock orgId={orgId} eventId={reg.event_id} balance={Number(my.balance)} reports={reports} />
          )}
          {guestsBlock}
        </div>
      ) : (
        reg.registration_open && (
          <Button
            size="sm"
            loading={busy}
            // Pass 9.29: registering = replying Attending (registers while registration is open)
            onClick={() => void run(() => setMyReply(orgId, { eventId: reg.event_id }, 'attending'))}
          >
            Register{reg.fee_amount ? ` · ${money(reg.price_now.amount)}` : ''}
          </Button>
        )
      )}
      {errorText && <p className="text-xs text-danger-700">{errorText}</p>}
      {pass && <GuestPassModal guest={pass} eventTitle={reg.title} onClose={() => setPass(null)} />}
    </div>
  );
}

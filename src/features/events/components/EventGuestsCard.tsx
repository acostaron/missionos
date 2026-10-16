// Guests (non-members) on the Registrations & payments page (Pass 9.15, Claude 2026-10-16).
// Organizers and the Treasurer / Finance Coordinator: guest price, add guests (with or without a host member,
// reserved or walk-in), record payments, waive, void, cancel, check in from the list, show the guest pass.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { getEventErrorMessage } from '../error-message';
import {
  PAYMENT_METHODS,
  PAYMENT_STATUS_LABELS,
  PRICE_TIER_LABELS,
  addEventGuest,
  cancelEventGuest,
  checkInEventGuest,
  invalidatePayments,
  money,
  recordEventGuestPayment,
  setEventGuestFee,
  setEventGuestWaiver,
  useEventGuests,
  voidEventGuestPayment,
  type EventGuest,
  type GuestPriceTier,
} from '../payments';
import { GuestForm } from './GuestForm';
import { GuestPassModal } from './GuestPassModal';
import { RecordPaymentForm } from './RecordPaymentForm';
import { formatNyDateShort } from '../../../lib/ny-time';
import { Alert, Badge, Button, Card, Input, Select } from '../../../components/ui';
import type { BadgeVariant } from '../../../components/ui';

const VARIANT: Record<EventGuest['payment']['status'], BadgeVariant> = {
  free: 'neutral',
  waived: 'info',
  paid: 'success',
  partial: 'warning',
  unpaid: 'danger',
};

const tierLabel = (t: GuestPriceTier) => (t === 'guest' ? 'Guest' : PRICE_TIER_LABELS[t]);

export function EventGuestsCard({
  orgId,
  eventId,
  eventTitle,
  hosts,
}: {
  orgId: string;
  eventId: string;
  eventTitle: string;
  /** registered members, for choosing the host */
  hosts: { member_id: string; display_name: string }[];
}) {
  const qc = useQueryClient();
  const { data } = useEventGuests(orgId, eventId, true);
  const [fee, setFee] = useState<string | null>(null);
  const [hostId, setHostId] = useState('');
  const [walkIn, setWalkIn] = useState(false);
  const [open, setOpen] = useState<string | null>(null);
  const [pass, setPass] = useState<EventGuest | null>(null);
  const [busy, setBusy] = useState(false);
  const [errorText, setErrorText] = useState<string | null>(null);

  const run = async (fn: () => Promise<unknown>) => {
    try {
      setBusy(true);
      setErrorText(null);
      await fn();
      await invalidatePayments(qc);
      return true;
    } catch (e) {
      setErrorText(getEventErrorMessage(e));
      return false;
    } finally {
      setBusy(false);
    }
  };

  const guests = data?.guests ?? [];
  const feeValue = fee ?? (data?.guest_fee != null ? String(data.guest_fee) : '');
  const price = walkIn ? data?.guest_walk_in_price : data?.guest_price_now;

  return (
    <Card padding="compact" className="space-y-3">
      <h2 className="text-sm font-semibold text-ink">Guests (non-members) ({guests.length})</h2>
      {errorText && (
        <Alert variant="danger" title="Could not save">
          {errorText}
        </Alert>
      )}

      <form
        className="flex flex-wrap items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          run(async () => {
            await setEventGuestFee(orgId, eventId, feeValue.trim() === '' ? null : Number(feeValue));
            setFee(null);
          });
        }}
      >
        <label className="block w-36">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">Guest price ($)</span>
          <Input
            type="number"
            inputMode="decimal"
            min="0"
            step="0.01"
            placeholder="= Member price"
            value={feeValue}
            onChange={(e) => setFee(e.target.value)}
          />
        </label>
        <Button type="submit" size="sm" variant="outline" disabled={busy || fee === null}>
          Save guest price
        </Button>
      </form>
      <p className="text-xs text-ink-muted">
        Leave empty to charge guests the member price (early-bird / regular, walk-in at the door). Enter 0 for free.
      </p>

      <div className="rounded-card border border-line p-3">
        <p className="mb-2 text-xs font-semibold text-ink-secondary">
          Add a guest{price ? ` · ${tierLabel(price.tier)} ${money(price.amount)}` : ''}
        </p>
        <GuestForm
          submitLabel="Add guest"
          busy={busy}
          onSubmit={(f) => run(() => addEventGuest(orgId, eventId, f, { asStaff: true, hostMemberId: hostId || null, walkIn }))}
          extra={
            <div className="flex flex-wrap items-end gap-3">
              <label className="block min-w-[12rem] flex-1">
                <span className="mb-1 block text-xs font-medium text-ink-secondary">Guest of (optional)</span>
                <Select value={hostId} onChange={(e) => setHostId(e.target.value)}>
                  <option value="">— No host member —</option>
                  {hosts.map((h) => (
                    <option key={h.member_id} value={h.member_id}>
                      {h.display_name}
                    </option>
                  ))}
                </Select>
              </label>
              <label className="flex items-center gap-2 pb-2 text-sm text-ink">
                <input type="checkbox" checked={walkIn} onChange={(e) => setWalkIn(e.target.checked)} />
                Walk-in (at the door)
              </label>
            </div>
          }
        />
      </div>

      {guests.length === 0 ? (
        <p className="text-sm text-ink-muted">No guests yet.</p>
      ) : (
        <ul className="divide-y divide-line">
          {guests.map((g) => {
            const p = g.payment;
            const due = p.status === 'unpaid' || p.status === 'partial';
            return (
              <li key={g.guest_id} className="py-2">
                <button
                  type="button"
                  className="flex w-full items-center justify-between gap-2 text-left"
                  onClick={() => setOpen(open === g.guest_id ? null : g.guest_id)}
                >
                  <span className="min-w-0 text-sm text-ink">
                    {g.display_name}
                    <span className="block text-xs text-ink-secondary">
                      {g.host_name ? `Guest of ${g.host_name}` : 'No host member'} ·{' '}
                      {p.registration_type === 'walk_in' ? 'Walk-in' : 'Reserved'} · {tierLabel(p.price_tier)} {money(p.fee)}
                    </span>
                    {(g.phone || g.email) && (
                      <span className="block text-xs text-ink-muted">{[g.phone, g.email].filter(Boolean).join(' · ')}</span>
                    )}
                  </span>
                  <Badge variant={VARIANT[p.status]}>
                    {PAYMENT_STATUS_LABELS[p.status]}
                    {due ? ` · ${money(p.balance)} due` : ''}
                  </Badge>
                </button>
                {g.checked_in_today && <p className="text-xs font-medium text-success-700">Checked in today</p>}
                {(g.payments?.length ?? 0) > 0 && (
                  <ul className="mt-1 space-y-0.5">
                    {g.payments!.map((pay) => (
                      <li key={pay.payment_id} className="flex items-center justify-between gap-2 text-xs text-ink-secondary">
                        <span>
                          {money(pay.amount)} · {PAYMENT_METHODS.find((x) => x.value === pay.payment_method)?.label} ·{' '}
                          {formatNyDateShort(pay.recorded_at)}
                        </span>
                        {open === g.guest_id && (
                          <button
                            type="button"
                            className="text-danger-700 hover:underline disabled:opacity-50"
                            disabled={busy}
                            onClick={() => {
                              if (window.confirm(`Void the ${money(pay.amount)} payment? Use this only for a payment entered by mistake.`)) {
                                run(() => voidEventGuestPayment(orgId, pay.payment_id));
                              }
                            }}
                          >
                            Void
                          </button>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
                {open === g.guest_id && (
                  <div className="mt-2 space-y-2 rounded-card border border-line bg-surface-muted p-3">
                    {due && (
                      <RecordPaymentForm
                        defaultAmount={p.balance}
                        submitLabel="Record payment"
                        busy={busy}
                        onSubmit={(amount, method) => run(() => recordEventGuestPayment(orgId, g.guest_id, amount, method))}
                      />
                    )}
                    <div className="flex flex-wrap gap-2">
                      <Button size="sm" variant="outline" onClick={() => setPass(g)}>
                        Guest pass
                      </Button>
                      {!g.checked_in_today && !due && (
                        <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => checkInEventGuest(orgId, g.guest_id))}>
                          Check in
                        </Button>
                      )}
                      {p.fee > 0 && (
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={busy}
                          onClick={() => run(() => setEventGuestWaiver(orgId, g.guest_id, p.status !== 'waived'))}
                        >
                          {p.status === 'waived' ? 'Remove waiver' : 'Waive fee'}
                        </Button>
                      )}
                      {p.paid === 0 && !g.checked_in_ever && (
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={busy}
                          onClick={() => {
                            if (window.confirm(`Remove ${g.display_name} from the guest list?`)) {
                              run(async () => {
                                await cancelEventGuest(orgId, g.guest_id);
                                setOpen(null);
                              });
                            }
                          }}
                        >
                          Remove guest
                        </Button>
                      )}
                    </div>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}
      {pass && <GuestPassModal guest={pass} eventTitle={eventTitle} onClose={() => setPass(null)} />}
    </Card>
  );
}

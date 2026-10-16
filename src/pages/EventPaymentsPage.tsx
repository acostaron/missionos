// Registrations & payments for an event (Pass 9.13 / 9.14 / 9.15, written by Claude 2026-10-16).
// For the event organizers and the Treasurer / Finance Coordinator: prices (early-bird, regular, walk-in),
// open registration to members, register members, record payments, waive, cancel, void a mistaken payment.
import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, Search } from 'lucide-react';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { useEvent } from '../features/events/queries';
import { getEventErrorMessage } from '../features/events/error-message';
import {
  PAYMENT_METHODS,
  PAYMENT_STATUS_LABELS,
  PRICE_TIER_LABELS,
  cancelEventRegistration,
  invalidatePayments,
  money,
  recordEventPayment,
  registerForEvent,
  setEventPricing,
  setFeeWaiver,
  useEventPaymentAccess,
  useEventPayments,
  usePaymentMemberSearch,
  voidEventPayment,
  type PaymentState,
  type PaymentStatus,
} from '../features/events/payments';
import { RecordPaymentForm } from '../features/events/components/RecordPaymentForm';
import { EventGuestsCard } from '../features/events/components/EventGuestsCard';
import { formatNyDateShort } from '../lib/ny-time';
import { Alert, Badge, Button, Card, Input } from '../components/ui';
import type { BadgeVariant } from '../components/ui';

const STATUS_VARIANT: Record<PaymentStatus, BadgeVariant> = {
  free: 'neutral',
  waived: 'info',
  paid: 'success',
  partial: 'warning',
  unpaid: 'danger',
  not_registered: 'neutral',
};

function StatusBadge({ p }: { p: PaymentState }) {
  return (
    <Badge variant={STATUS_VARIANT[p.status]}>
      {PAYMENT_STATUS_LABELS[p.status]}
      {p.status === 'partial' || p.status === 'unpaid' ? ` · ${money(p.balance)} due` : ''}
    </Badge>
  );
}

function regLine(p: PaymentState) {
  if (!p.registered) return null;
  const type = p.registration_type === 'walk_in' ? 'Walk-in' : 'Reserved';
  const tier = p.price_tier ? PRICE_TIER_LABELS[p.price_tier] : '';
  return `${type} · ${tier} ${money(p.fee)}`;
}

type PriceForm = { fee: string; early: string; earlyUntil: string; walkIn: string; open: boolean };

export default function EventPaymentsPage() {
  const { eventId } = useParams<{ eventId: string }>();
  const qc = useQueryClient();
  const { organization } = useCurrentOrganization();
  const orgId = organization?.id ?? null;
  const { data: event } = useEvent(orgId, eventId ?? null);
  const { data: access, isLoading: accessLoading } = useEventPaymentAccess(orgId, eventId ?? null);
  const canManage = !!access?.can_manage_payments;
  const { data } = useEventPayments(orgId, eventId ?? null, canManage);

  const [form, setForm] = useState<PriceForm | null>(null);
  const [query, setQuery] = useState('');
  const [openMember, setOpenMember] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [errorText, setErrorText] = useState<string | null>(null);
  const { data: found = [] } = usePaymentMemberSearch(canManage ? orgId : null, eventId ?? null, query);

  const run = async (fn: () => Promise<unknown>) => {
    try {
      setBusy(true);
      setErrorText(null);
      await fn();
      await invalidatePayments(qc);
    } catch (e) {
      setErrorText(getEventErrorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  if (accessLoading || !event) return <div className="p-8 text-center text-sm text-ink-muted">Loading…</div>;
  if (!canManage) {
    return (
      <Alert variant="warning" title="Registrations & payments">
        Only the event organizers and the Treasurer / Finance Coordinator can manage registrations and payments.
      </Alert>
    );
  }

  const src = data ?? access;
  const current: PriceForm = form ?? {
    fee: src?.fee_amount ? String(src.fee_amount) : '',
    early: src?.early_bird_fee ? String(src.early_bird_fee) : '',
    earlyUntil: src?.early_bird_until ?? '',
    walkIn: src?.walk_in_fee ? String(src.walk_in_fee) : '',
    open: !!src?.registration_open,
  };
  const set = (patch: Partial<PriceForm>) => setForm({ ...current, ...patch });
  const num = (v: string) => (v.trim() === '' ? null : Number(v));
  const paid = !!src?.fee_amount;

  const memberActions = (memberId: string, p: PaymentState) =>
    openMember === memberId && (
      <div className="mt-2 space-y-2 rounded-card border border-line bg-surface-muted p-3">
        {!p.registered ? (
          <div className="flex flex-wrap gap-2">
            <Button size="sm" disabled={busy} onClick={() => run(() => registerForEvent(orgId!, eventId!, memberId, false))}>
              Register (reserved · {money(p.fee)})
            </Button>
            {paid && (
              <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => registerForEvent(orgId!, eventId!, memberId, true))}>
                Register as walk-in · {money(p.walk_in_fee ?? p.fee)}
              </Button>
            )}
          </div>
        ) : (
          <>
            {paid && p.status !== 'waived' && p.status !== 'paid' && (
              <RecordPaymentForm
                defaultAmount={p.balance}
                submitLabel="Record payment"
                busy={busy}
                onSubmit={(amount, method) =>
                  run(async () => {
                    await recordEventPayment(orgId!, eventId!, memberId, amount, method);
                    setOpenMember(null);
                  })
                }
              />
            )}
            <div className="flex flex-wrap gap-2">
              {paid && (
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() => run(() => setFeeWaiver(orgId!, eventId!, memberId, p.status !== 'waived'))}
                >
                  {p.status === 'waived' ? 'Remove waiver' : 'Waive fee'}
                </Button>
              )}
              {p.paid === 0 && (
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() => {
                    if (window.confirm('Cancel this registration?')) {
                      run(async () => {
                        await cancelEventRegistration(orgId!, eventId!, memberId);
                        setOpenMember(null);
                      });
                    }
                  }}
                >
                  Cancel registration
                </Button>
              )}
            </div>
          </>
        )}
      </div>
    );

  const row = (m: { member_id: string; display_name: string; member_number: string | null; payment: PaymentState }) => (
    <button
      type="button"
      className="flex w-full items-center justify-between gap-2 text-left"
      onClick={() => setOpenMember(openMember === m.member_id ? null : m.member_id)}
    >
      <span className="min-w-0 text-sm text-ink">
        {m.display_name}
        {m.member_number && <span className="ml-2 text-xs text-ink-muted">{m.member_number}</span>}
        {regLine(m.payment) && <span className="block text-xs text-ink-secondary">{regLine(m.payment)}</span>}
      </span>
      <StatusBadge p={m.payment} />
    </button>
  );

  const t = data?.totals;

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <Link to={`/app/calendar/${event.id}`} className="inline-flex items-center gap-1 text-sm text-ink-secondary hover:text-ink">
        <ArrowLeft className="h-4 w-4" /> Back to event
      </Link>
      <div>
        <h1 className="text-xl font-bold text-ink">Registrations & payments</h1>
        <p className="text-sm text-ink-secondary">
          {event.title} · {formatNyDateShort(event.starts_at)}
        </p>
      </div>

      {errorText && (
        <Alert variant="danger" title="Could not save">
          {errorText}
        </Alert>
      )}

      <Card padding="compact" className="space-y-3">
        <h2 className="text-sm font-semibold text-ink">Prices (per member) and registration</h2>
        <form
          className="space-y-3"
          onSubmit={(e) => {
            e.preventDefault();
            run(async () => {
              await setEventPricing(orgId!, eventId!, {
                fee_amount: num(current.fee),
                early_bird_fee: num(current.early),
                early_bird_until: current.earlyUntil || null,
                walk_in_fee: num(current.walkIn),
                registration_open: current.open,
              });
              setForm(null);
            });
          }}
        >
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">Regular ($)</span>
              <Input type="number" inputMode="decimal" min="0" step="0.01" placeholder="Free" value={current.fee} onChange={(e) => set({ fee: e.target.value })} />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">Early-bird ($)</span>
              <Input type="number" inputMode="decimal" min="0" step="0.01" placeholder="None" value={current.early} onChange={(e) => set({ early: e.target.value })} />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">Early-bird last day</span>
              <Input type="date" value={current.earlyUntil} onChange={(e) => set({ earlyUntil: e.target.value })} />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">Walk-in ($)</span>
              <Input type="number" inputMode="decimal" min="0" step="0.01" placeholder="= Regular" value={current.walkIn} onChange={(e) => set({ walkIn: e.target.value })} />
            </label>
          </div>
          <label className="flex items-center gap-2 text-sm text-ink">
            <input type="checkbox" checked={current.open} onChange={(e) => set({ open: e.target.checked })} />
            Members can register themselves in My Events
          </label>
          <div className="flex justify-end">
            <Button type="submit" variant="outline" disabled={busy || form === null}>
              Save prices
            </Button>
          </div>
        </form>
        <p className="text-xs text-ink-muted">
          Each member pays the price of the day they registered (early-bird until its last day, then regular).
          Walk-ins registered at the door pay the walk-in price. At the QR desk, members who are not registered or
          not paid in full are not checked in until they register and pay, or the fee is waived.
        </p>
      </Card>

      {t && (
        <div className="grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
          {[
            ['Registered', `${t.registered}`],
            ['Reserved / walk-in', `${t.reserved} / ${t.walk_in}`],
            ['Checked in', `${t.checked_in}`],
            ['Paid / partial / unpaid', `${t.paid} / ${t.partial} / ${t.unpaid}`],
            ['Waived', `${t.waived}`],
            ['Collected', money(t.collected)],
            ['Expected', money(t.expected)],
          ].map(([label, value]) => (
            <div key={label} className="rounded-card border border-line bg-surface p-3">
              <div className="text-lg font-bold text-ink">{value}</div>
              <div className="text-xs text-ink-secondary">{label}</div>
            </div>
          ))}
        </div>
      )}

      <Card padding="compact" className="space-y-2">
        <h2 className="text-sm font-semibold text-ink">Register a member or record a payment</h2>
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
          <Input className="pl-9" placeholder="Search member name or number" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        {found.length > 0 && (
          <ul className="divide-y divide-line">
            {found.map((m) => (
              <li key={m.member_id} className="py-2">
                {row(m)}
                {memberActions(m.member_id, m.payment)}
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card padding="compact">
        <h2 className="mb-2 text-sm font-semibold text-ink">Registrations ({data?.members.length ?? 0})</h2>
        {(data?.members.length ?? 0) === 0 ? (
          <p className="text-sm text-ink-muted">No registrations yet.</p>
        ) : (
          <ul className="divide-y divide-line">
            {data!.members.map((m) => (
              <li key={m.member_id} className="py-2">
                {row(m)}
                {m.checked_in && <p className="text-xs font-medium text-success-700">Checked in</p>}
                {m.payments.length > 0 && (
                  <ul className="mt-1 space-y-0.5">
                    {m.payments.map((p) => (
                      <li key={p.payment_id} className="flex items-center justify-between gap-2 text-xs text-ink-secondary">
                        <span>
                          {money(p.amount)} · {PAYMENT_METHODS.find((x) => x.value === p.payment_method)?.label} ·{' '}
                          {formatNyDateShort(p.recorded_at)}
                        </span>
                        {openMember === m.member_id && (
                          <button
                            type="button"
                            className="text-danger-700 hover:underline disabled:opacity-50"
                            disabled={busy}
                            onClick={() => {
                              if (window.confirm(`Void the ${money(p.amount)} payment? Use this only for a payment entered by mistake.`)) {
                                run(() => voidEventPayment(orgId!, p.payment_id));
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
                {memberActions(m.member_id, m.payment)}
              </li>
            ))}
          </ul>
        )}
      </Card>

      <EventGuestsCard orgId={orgId!} eventId={eventId!} eventTitle={event.title} hosts={data?.members ?? []} />
    </div>
  );
}

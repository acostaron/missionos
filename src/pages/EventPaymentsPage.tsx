// Event fee and payments (Pass 9.13, written by Claude 2026-10-16).
// For the event organizers and the Treasurer / Finance Coordinator: set the fee, record payments,
// waive the fee, void a payment entered by mistake.
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
  invalidatePayments,
  money,
  recordEventPayment,
  setEventFee,
  setFeeWaiver,
  useEventPaymentAccess,
  useEventPayments,
  usePaymentMemberSearch,
  voidEventPayment,
  type PaymentState,
  type PaymentStatus,
} from '../features/events/payments';
import { RecordPaymentForm } from '../features/events/components/RecordPaymentForm';
import { formatNyDateShort } from '../lib/ny-time';
import { Alert, Badge, Button, Card, Input } from '../components/ui';
import type { BadgeVariant } from '../components/ui';

const STATUS_VARIANT: Record<PaymentStatus, BadgeVariant> = {
  free: 'neutral',
  waived: 'info',
  paid: 'success',
  partial: 'warning',
  unpaid: 'danger',
};

function StatusBadge({ p }: { p: PaymentState }) {
  return (
    <Badge variant={STATUS_VARIANT[p.status]}>
      {PAYMENT_STATUS_LABELS[p.status]}
      {p.status === 'partial' ? ` · ${money(p.balance)} due` : ''}
    </Badge>
  );
}

export default function EventPaymentsPage() {
  const { eventId } = useParams<{ eventId: string }>();
  const qc = useQueryClient();
  const { organization } = useCurrentOrganization();
  const orgId = organization?.id ?? null;
  const { data: event } = useEvent(orgId, eventId ?? null);
  const { data: access, isLoading: accessLoading } = useEventPaymentAccess(orgId, eventId ?? null);
  const canManage = !!access?.can_manage_payments;
  const { data } = useEventPayments(orgId, eventId ?? null, canManage);

  const [feeText, setFeeText] = useState<string | null>(null);
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
      <Alert variant="warning" title="Payments">
        Only the event organizers and the Treasurer / Finance Coordinator can manage payments.
      </Alert>
    );
  }

  const fee = data?.fee_amount ?? access?.fee_amount ?? null;
  const feeValue = feeText ?? (fee ? String(fee) : '');

  const memberActions = (memberId: string, p: PaymentState) =>
    openMember === memberId && (
      <div className="mt-2 space-y-2 rounded-card border border-line bg-surface-muted p-3">
        {p.status !== 'waived' && (
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
        <Button
          size="sm"
          variant="ghost"
          disabled={busy}
          onClick={() => run(() => setFeeWaiver(orgId!, eventId!, memberId, p.status !== 'waived'))}
        >
          {p.status === 'waived' ? 'Remove waiver' : 'Waive fee'}
        </Button>
      </div>
    );

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <Link to={`/app/calendar/${event.id}`} className="inline-flex items-center gap-1 text-sm text-ink-secondary hover:text-ink">
        <ArrowLeft className="h-4 w-4" /> Back to event
      </Link>
      <div>
        <h1 className="text-xl font-bold text-ink">Payments</h1>
        <p className="text-sm text-ink-secondary">
          {event.title} · {formatNyDateShort(event.starts_at)}
        </p>
      </div>

      {errorText && (
        <Alert variant="danger" title="Could not save">
          {errorText}
        </Alert>
      )}

      <Card padding="compact" className="space-y-2">
        <h2 className="text-sm font-semibold text-ink">Event fee (per member)</h2>
        <form
          className="flex flex-wrap items-end gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            const v = feeValue.trim() === '' ? null : Number(feeValue);
            if (v !== null && (!Number.isFinite(v) || v < 0)) return;
            run(async () => {
              await setEventFee(orgId!, eventId!, v);
              setFeeText(null);
            });
          }}
        >
          <label className="block w-36">
            <span className="mb-1 block text-xs font-medium text-ink-secondary">Fee ($) — blank = free</span>
            <Input type="number" inputMode="decimal" min="0" step="0.01" value={feeValue} onChange={(e) => setFeeText(e.target.value)} />
          </label>
          <Button type="submit" variant="outline" disabled={busy || feeText === null}>
            Save fee
          </Button>
        </form>
        <p className="text-xs text-ink-muted">
          {fee
            ? 'At the QR check-in desk, members who have not paid in full are not checked in until they pay or the fee is waived.'
            : 'This is a free event. Set a fee to require payment at check-in.'}
        </p>
      </Card>

      {fee ? (
        <>
          {data && (
            <div className="grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
              {[
                ['Paid', data.totals.paid],
                ['Partial', data.totals.partial],
                ['Waived', data.totals.waived],
                ['Collected', money(data.totals.collected)],
              ].map(([label, value]) => (
                <div key={label} className="rounded-card border border-line bg-surface p-3">
                  <div className="text-lg font-bold text-ink">{value}</div>
                  <div className="text-xs text-ink-secondary">{label}</div>
                </div>
              ))}
            </div>
          )}

          <Card padding="compact" className="space-y-2">
            <h2 className="text-sm font-semibold text-ink">Record a payment</h2>
            <div className="relative">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
              <Input
                className="pl-9"
                placeholder="Search member name or number"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
            </div>
            {found.length > 0 && (
              <ul className="divide-y divide-line">
                {found.map((m) => (
                  <li key={m.member_id} className="py-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between gap-2 text-left"
                      onClick={() => setOpenMember(openMember === m.member_id ? null : m.member_id)}
                    >
                      <span className="text-sm text-ink">
                        {m.display_name}
                        {m.member_number && <span className="ml-2 text-xs text-ink-muted">{m.member_number}</span>}
                      </span>
                      <StatusBadge p={m.payment} />
                    </button>
                    {memberActions(m.member_id, m.payment)}
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card padding="compact">
            <h2 className="mb-2 text-sm font-semibold text-ink">Payments and waivers ({data?.members.length ?? 0})</h2>
            {(data?.members.length ?? 0) === 0 ? (
              <p className="text-sm text-ink-muted">No payments recorded yet.</p>
            ) : (
              <ul className="divide-y divide-line">
                {data!.members.map((m) => (
                  <li key={m.member_id} className="py-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between gap-2 text-left"
                      onClick={() => setOpenMember(openMember === m.member_id ? null : m.member_id)}
                    >
                      <span className="text-sm text-ink">
                        {m.display_name}
                        {m.member_number && <span className="ml-2 text-xs text-ink-muted">{m.member_number}</span>}
                      </span>
                      <StatusBadge p={m.payment} />
                    </button>
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
        </>
      ) : null}
    </div>
  );
}

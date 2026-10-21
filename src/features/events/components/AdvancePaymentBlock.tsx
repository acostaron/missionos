// My Events: pay in advance by Zelle or PayPal, then report it for the treasurer to confirm (Pass 9.29, Ron 2026-10-21).
// Pass 9.30 (Ron 2026-10-21): also check or cash — report one already given, or say "I'll pay at the event".
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { ExternalLink } from 'lucide-react';
import { getEventErrorMessage } from '../error-message';
import { invalidatePayments, money } from '../payments';
import {
  REPORT_METHOD_LABELS,
  paypalUrl,
  reportMyPayment,
  usePaymentDetails,
  withdrawMyPaymentReport,
  type MyPaymentReport,
  type ReportKind,
  type ReportMethod,
} from '../advance-payments';
import { Badge, Button, Input, Select } from '../../../components/ui';

const REFERENCE_PLACEHOLDER: Record<ReportMethod, string> = {
  zelle: 'e.g. Zelle confirmation #',
  paypal: 'e.g. PayPal transaction ID',
  check: 'Check number',
  cash: 'e.g. Given to the chapter treasurer',
};

export function AdvancePaymentBlock({
  orgId,
  eventId,
  balance,
  reports,
}: {
  orgId: string;
  eventId: string;
  balance: number;
  reports: MyPaymentReport[];
}) {
  const qc = useQueryClient();
  const { data: details } = usePaymentDetails(orgId, eventId);
  const [form, setForm] = useState<ReportKind | null>(null);
  const [method, setMethod] = useState<ReportMethod>('check');
  const [amount, setAmount] = useState(balance > 0 ? String(balance) : '');
  const [reference, setReference] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pending = reports.filter((r) => r.report_status === 'pending');
  const pendingTotal = pending.reduce((s, r) => s + Number(r.amount), 0);
  const payingAtEvent = pending.some((r) => r.report_kind === 'at_event');
  const hasZelle = !!details?.zelle_recipient;
  const hasPaypal = !!details?.paypal_link;
  const hasCheck = !!details?.check_payable_to || !!details?.check_mailing_address;
  const value = Number(amount);
  const ok = Number.isFinite(value) && value > 0 && value <= 10000;
  const sentMethods: ReportMethod[] = [
    ...(hasZelle ? (['zelle'] as const) : []),
    ...(hasPaypal ? (['paypal'] as const) : []),
    'check',
    'cash',
  ];

  const openForm = (kind: ReportKind) => {
    setError(null);
    setReference('');
    setAmount(balance - pendingTotal > 0 ? String(balance - pendingTotal) : '');
    setMethod(kind === 'sent' ? sentMethods[0] : 'cash');
    setForm(kind);
  };

  const submit = async () => {
    if (!form) return;
    try {
      setBusy(true);
      setError(null);
      await reportMyPayment(orgId, eventId, method, Math.round(value * 100) / 100, reference, form);
      await invalidatePayments(qc);
      setForm(null);
      setReference('');
    } catch (e) {
      setError(getEventErrorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  const withdraw = async (id: string) => {
    try {
      setBusy(true);
      setError(null);
      await withdrawMyPaymentReport(orgId, id);
      await invalidatePayments(qc);
    } catch (e) {
      setError(getEventErrorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  const methodOptions: ReportMethod[] = form === 'at_event' ? ['cash', 'check'] : sentMethods;

  return (
    <div className="space-y-2 rounded-lg border border-line bg-surface-muted p-3">
      <p className="text-xs font-semibold text-ink">Pay in advance or at the event</p>
      <div className="space-y-1 text-xs text-ink-secondary">
        {hasZelle && (
          <p>
            <span className="font-medium text-ink">Zelle:</span> send {money(balance)} to{' '}
            <span className="font-medium text-ink">{details!.zelle_recipient}</span>
            {details!.zelle_name ? ` (${details!.zelle_name})` : ''}
          </p>
        )}
        {hasPaypal && (
          <a
            href={paypalUrl(details!.paypal_link!, balance)}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 font-medium text-primary hover:underline"
          >
            Pay {money(balance)} with PayPal <ExternalLink className="h-3.5 w-3.5" />
          </a>
        )}
        {details?.payment_note && (hasZelle || hasPaypal) && <p className="text-ink-muted">{details.payment_note}</p>}
        {hasCheck && (
          <p>
            <span className="font-medium text-ink">Check:</span>
            {details!.check_payable_to && (
              <>
                {' '}
                payable to <span className="font-medium text-ink">{details!.check_payable_to}</span>
              </>
            )}
            {details!.check_mailing_address && <> · mail to {details!.check_mailing_address}</>}
          </p>
        )}
        <p>
          <span className="font-medium text-ink">Cash or check:</span>{' '}
          {details?.cash_check_note || 'give it to the treasurer, or pay at the event.'}
        </p>
      </div>

      {reports.length > 0 && (
        <ul className="space-y-1">
          {reports.map((r) => (
            <li key={r.report_id} className="flex flex-wrap items-center gap-2 text-xs text-ink-secondary">
              <span>
                {r.report_kind === 'at_event' ? 'At the event: ' : ''}
                {REPORT_METHOD_LABELS[r.payment_method]} {money(r.amount)}
                {r.reference ? ` · ${r.reference}` : ''}
              </span>
              {r.report_status === 'pending' &&
                (r.report_kind === 'at_event' ? (
                  <Badge variant="info">Paying at the event</Badge>
                ) : (
                  <Badge variant="warning">Awaiting confirmation</Badge>
                ))}
              {r.report_status === 'confirmed' && <Badge variant="success">Confirmed</Badge>}
              {r.report_status === 'declined' && (
                <Badge variant="danger">Not confirmed{r.decline_reason ? `: ${r.decline_reason}` : ''}</Badge>
              )}
              {r.report_status === 'pending' && (
                <button type="button" disabled={busy} className="text-ink-muted hover:underline" onClick={() => void withdraw(r.report_id)}>
                  Withdraw
                </button>
              )}
            </li>
          ))}
        </ul>
      )}

      {balance - pendingTotal > 0 && !form && (
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="outline" onClick={() => openForm('sent')}>
            I sent payment
          </Button>
          {!payingAtEvent && (
            <Button size="sm" variant="ghost" onClick={() => openForm('at_event')}>
              I&rsquo;ll pay at the event
            </Button>
          )}
        </div>
      )}
      {form && (
        <form
          className="flex flex-wrap items-end gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (ok && !busy) void submit();
          }}
        >
          <label className="block w-28">
            <span className="mb-1 block text-xs font-medium text-ink-secondary">
              {form === 'at_event' ? 'Will pay by' : 'Paid by'}
            </span>
            <Select value={method} onChange={(e) => setMethod(e.target.value as ReportMethod)}>
              {methodOptions.map((m) => (
                <option key={m} value={m}>
                  {REPORT_METHOD_LABELS[m]}
                </option>
              ))}
            </Select>
          </label>
          <label className="block w-24">
            <span className="mb-1 block text-xs font-medium text-ink-secondary">Amount ($)</span>
            <Input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </label>
          {form === 'sent' && (
            <label className="block min-w-[10rem] flex-1">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">
                {method === 'check' ? 'Check number (optional)' : 'Reference / note (optional)'}
              </span>
              <Input
                maxLength={120}
                value={reference}
                placeholder={REFERENCE_PLACEHOLDER[method]}
                onChange={(e) => setReference(e.target.value)}
              />
            </label>
          )}
          <Button size="sm" type="submit" disabled={!ok || busy} loading={busy}>
            {form === 'at_event' ? 'Let the treasurer know' : 'Send to treasurer'}
          </Button>
          <Button size="sm" variant="ghost" type="button" onClick={() => setForm(null)}>
            Cancel
          </Button>
        </form>
      )}
      {error && <p className="text-xs text-danger-700">{error}</p>}
    </div>
  );
}

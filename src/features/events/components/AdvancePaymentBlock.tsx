// My Events: pay in advance by Zelle or PayPal, then report it for the treasurer to confirm (Pass 9.29, Ron 2026-10-21).
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
  type ReportMethod,
} from '../advance-payments';
import { Badge, Button, Input, Select } from '../../../components/ui';

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
  const [open, setOpen] = useState(false);
  const [method, setMethod] = useState<ReportMethod>('zelle');
  const [amount, setAmount] = useState(balance > 0 ? String(balance) : '');
  const [reference, setReference] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pending = reports.filter((r) => r.report_status === 'pending');
  const pendingTotal = pending.reduce((s, r) => s + Number(r.amount), 0);
  const hasZelle = !!details?.zelle_recipient;
  const hasPaypal = !!details?.paypal_link;
  const value = Number(amount);
  const ok = Number.isFinite(value) && value > 0 && value <= 10000;

  const submit = async () => {
    try {
      setBusy(true);
      setError(null);
      await reportMyPayment(orgId, eventId, method, Math.round(value * 100) / 100, reference);
      await invalidatePayments(qc);
      setOpen(false);
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

  return (
    <div className="space-y-2 rounded-lg border border-line bg-surface-muted p-3">
      <p className="text-xs font-semibold text-ink">Pay in advance</p>
      {!hasZelle && !hasPaypal ? (
        <p className="text-xs text-ink-secondary">Please pay the registration team or the treasurer before the event.</p>
      ) : (
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
          {details?.payment_note && <p className="text-ink-muted">{details.payment_note}</p>}
        </div>
      )}

      {reports.length > 0 && (
        <ul className="space-y-1">
          {reports.map((r) => (
            <li key={r.report_id} className="flex flex-wrap items-center gap-2 text-xs text-ink-secondary">
              <span>
                {REPORT_METHOD_LABELS[r.payment_method]} {money(r.amount)}
                {r.reference ? ` · ${r.reference}` : ''}
              </span>
              {r.report_status === 'pending' && <Badge variant="warning">Awaiting confirmation</Badge>}
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

      {(hasZelle || hasPaypal) && balance - pendingTotal > 0 && !open && (
        <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
          I sent payment
        </Button>
      )}
      {open && (
        <form
          className="flex flex-wrap items-end gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (ok && !busy) void submit();
          }}
        >
          <label className="block w-28">
            <span className="mb-1 block text-xs font-medium text-ink-secondary">Paid by</span>
            <Select value={method} onChange={(e) => setMethod(e.target.value as ReportMethod)}>
              {hasZelle && <option value="zelle">Zelle</option>}
              {hasPaypal && <option value="paypal">PayPal</option>}
            </Select>
          </label>
          <label className="block w-24">
            <span className="mb-1 block text-xs font-medium text-ink-secondary">Amount ($)</span>
            <Input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </label>
          <label className="block min-w-[10rem] flex-1">
            <span className="mb-1 block text-xs font-medium text-ink-secondary">Reference / note (optional)</span>
            <Input maxLength={120} value={reference} placeholder="e.g. Zelle confirmation #" onChange={(e) => setReference(e.target.value)} />
          </label>
          <Button size="sm" type="submit" disabled={!ok || busy} loading={busy}>
            Send to treasurer
          </Button>
          <Button size="sm" variant="ghost" type="button" onClick={() => setOpen(false)}>
            Cancel
          </Button>
        </form>
      )}
      {error && <p className="text-xs text-danger-700">{error}</p>}
    </div>
  );
}

// Registrations page: payments members reported (Zelle / PayPal) for the treasurer to confirm or decline
// (Pass 9.29, Ron 2026-10-21). Confirming records the payment as if entered here.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { getEventErrorMessage } from '../error-message';
import { invalidatePayments, money } from '../payments';
import { REPORT_METHOD_LABELS, reviewPaymentReport, useEventPaymentReports } from '../advance-payments';
import { formatNyDateShort } from '../../../lib/ny-time';
import { Alert, Badge, Button, Card } from '../../../components/ui';

export function PaymentReportsCard({ orgId, eventId }: { orgId: string; eventId: string }) {
  const qc = useQueryClient();
  const { data: reports = [] } = useEventPaymentReports(orgId, eventId, true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const review = async (id: string, confirm: boolean) => {
    let reason: string | undefined;
    if (!confirm) {
      const r = window.prompt('Reason (shown to the member), e.g. "Not received yet":');
      if (r === null) return;
      reason = r;
    }
    try {
      setBusy(id);
      setError(null);
      await reviewPaymentReport(orgId, id, confirm, reason);
      await invalidatePayments(qc);
    } catch (e) {
      setError(getEventErrorMessage(e));
    } finally {
      setBusy(null);
    }
  };

  if (reports.length === 0) return null;
  const pending = reports.filter((r) => r.report_status === 'pending');
  return (
    <Card padding="compact" className="space-y-2">
      <h2 className="text-sm font-semibold text-ink">
        Payments reported by members {pending.length > 0 && <Badge variant="warning">{pending.length} to confirm</Badge>}
      </h2>
      <p className="text-xs text-ink-muted">
        Check your Zelle / PayPal account, then Confirm (the payment is recorded) or Decline (the member sees the reason).
      </p>
      {error && (
        <Alert variant="danger" title="Could not save">
          {error}
        </Alert>
      )}
      <ul className="divide-y divide-line">
        {reports.map((r) => (
          <li key={r.report_id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
            <div>
              <p className="font-medium text-ink">
                {r.display_name} {r.member_number && <span className="text-xs text-ink-muted">{r.member_number}</span>}
              </p>
              <p className="text-xs text-ink-secondary">
                {REPORT_METHOD_LABELS[r.payment_method]} {money(r.amount)} · reported {formatNyDateShort(r.reported_at)}
                {r.reference ? ` · ${r.reference}` : ''}
              </p>
            </div>
            {r.report_status === 'pending' ? (
              <div className="flex gap-2">
                <Button size="sm" loading={busy === r.report_id} onClick={() => void review(r.report_id, true)}>
                  Confirm
                </Button>
                <Button size="sm" variant="ghost" disabled={busy === r.report_id} onClick={() => void review(r.report_id, false)}>
                  Decline
                </Button>
              </div>
            ) : (
              <Badge variant={r.report_status === 'confirmed' ? 'success' : 'neutral'}>
                {r.report_status === 'confirmed' ? 'Confirmed' : `Declined${r.decline_reason ? `: ${r.decline_reason}` : ''}`}
              </Badge>
            )}
          </li>
        ))}
      </ul>
    </Card>
  );
}

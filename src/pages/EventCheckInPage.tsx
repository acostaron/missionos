// QR check-in desk for an event (Pass 9.12, written by Claude 2026-10-16).
// Scan the member's QR (My Card on the phone, or the ID card) with the camera or a handheld scanner.
// A member checks in once per event day; a second scan shows a warning. First check-in = kit and T-shirt given.
import { useCallback, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, ArrowLeft, CheckCircle2, CircleDollarSign, ScanLine, XCircle } from 'lucide-react';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { useEvent, eventKeys } from '../features/events/queries';
import { getEventErrorMessage } from '../features/events/error-message';
import { QrScanner } from '../features/events/components/QrScanner';
import {
  INVALID_REASONS,
  checkInKeys,
  scanCheckIn,
  useCheckInSummary,
  type ScanResult,
} from '../features/events/check-in';
import { MemberAvatar } from '../features/self-service/components/MemberAvatar';
import { invalidatePayments, money, recordEventPayment, registerForEvent, type PaymentMethod } from '../features/events/payments';
import { RecordPaymentForm } from '../features/events/components/RecordPaymentForm';
import { formatNyDateShort, formatNyTime } from '../lib/ny-time';
import { Alert, Button, Card, Input } from '../components/ui';

function beep(ok: boolean) {
  try {
    const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) return;
    const ctx = new AC();
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.frequency.value = ok ? 880 : 220;
    g.gain.value = 0.15;
    o.connect(g).connect(ctx.destination);
    o.start();
    o.stop(ctx.currentTime + (ok ? 0.15 : 0.45));
    o.onended = () => ctx.close();
  } catch {
    /* sound is optional */
  }
  try {
    navigator.vibrate?.(ok ? 80 : [200, 100, 200]);
  } catch {
    /* vibration is optional */
  }
}

function when(iso: string | null) {
  return iso ? `${formatNyDateShort(iso)} at ${formatNyTime(iso)}` : '';
}

export default function EventCheckInPage() {
  const { eventId } = useParams<{ eventId: string }>();
  const qc = useQueryClient();
  const { organization } = useCurrentOrganization();
  const orgId = organization?.id ?? null;
  const { data: event, isLoading } = useEvent(orgId, eventId ?? null);
  const { data: summary } = useCheckInSummary(orgId, eventId ?? null);

  const [result, setResult] = useState<ScanResult | null>(null);
  const [errorText, setErrorText] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [manual, setManual] = useState('');
  const lastPayload = useRef('');
  const busyRef = useRef(false);
  const resumeTimer = useRef<number | undefined>(undefined);

  const submit = useCallback(
    async (payload: string) => {
      if (!orgId || !eventId || busyRef.current || !payload.trim()) return;
      busyRef.current = true;
      lastPayload.current = payload.trim();
      setBusy(true);
      setErrorText(null);
      window.clearTimeout(resumeTimer.current);
      try {
        const r = await scanCheckIn(orgId, eventId, payload.trim());
        setResult(r);
        beep(r.result === 'checked_in');
        if (r.result === 'checked_in') {
          // keep the desk moving: clear a success automatically
          resumeTimer.current = window.setTimeout(() => setResult(null), 4000);
        }
        await Promise.all([
          qc.invalidateQueries({ queryKey: checkInKeys.summary(orgId, eventId) }),
          qc.invalidateQueries({ queryKey: eventKeys.all }),
        ]);
      } catch (e) {
        setResult(null);
        setErrorText(getEventErrorMessage(e));
        beep(false);
      } finally {
        busyRef.current = false;
        setBusy(false);
      }
    },
    [orgId, eventId, qc],
  );

  const waitingForTap = result !== null && result.result !== 'checked_in';

  // Paid events: record the payment at the desk, then check the member in with the same QR.
  const payAndCheckIn = async (memberId: string, amount: number, method: PaymentMethod, walkIn = false) => {
    if (!orgId || !eventId) return;
    try {
      setBusy(true);
      setErrorText(null);
      if (walkIn) await registerForEvent(orgId, eventId, memberId, true);
      await recordEventPayment(orgId, eventId, memberId, amount, method);
      await invalidatePayments(qc);
    } catch (e) {
      setErrorText(getEventErrorMessage(e));
      setBusy(false);
      return;
    }
    setBusy(false);
    await submit(lastPayload.current);
  };

  if (isLoading || !event) {
    return <div className="p-8 text-center text-sm text-ink-muted">Loading event…</div>;
  }

  return (
    <div className="mx-auto max-w-xl space-y-4">
      <Link to={`/app/calendar/${event.id}`} className="inline-flex items-center gap-1 text-sm text-ink-secondary hover:text-ink">
        <ArrowLeft className="h-4 w-4" /> Back to event
      </Link>
      <div>
        <h1 className="text-xl font-bold text-ink">QR check-in</h1>
        <p className="text-sm text-ink-secondary">
          {event.title} · {formatNyDateShort(event.starts_at)}
        </p>
      </div>

      {event.is_program_session ? (
        <Alert variant="warning" title="Not available for program sessions">
          Use Take attendance for program sessions.
        </Alert>
      ) : (
        <>
          {summary && (
            <div className="flex gap-3 text-sm">
              <div className="flex-1 rounded-card border border-line bg-surface p-3">
                <div className="text-2xl font-bold text-ink">{summary.checked_in_today}</div>
                <div className="text-xs text-ink-secondary">checked in today</div>
              </div>
              {summary.first_day !== summary.last_day && (
                <div className="flex-1 rounded-card border border-line bg-surface p-3">
                  <div className="text-2xl font-bold text-ink">{summary.attended_total}</div>
                  <div className="text-xs text-ink-secondary">attended (all days)</div>
                </div>
              )}
            </div>
          )}

          <QrScanner paused={busy || waitingForTap} onDetect={submit} />

          {errorText && (
            <Alert variant="danger" title="Could not check in">
              {errorText}
            </Alert>
          )}

          {result && (
            <Card
              padding="comfortable"
              className={
                result.result === 'checked_in'
                  ? 'border-2 border-success-600 bg-success-50'
                  : result.result === 'already_checked_in'
                    ? 'border-2 border-warning-600 bg-warning-50'
                    : 'border-2 border-danger-600 bg-danger-50'
              }
            >
              <div className="flex items-start gap-3" role="status" aria-live="assertive">
                {result.result === 'checked_in' ? (
                  <CheckCircle2 className="h-8 w-8 shrink-0 text-success-700" />
                ) : result.result === 'already_checked_in' ? (
                  <AlertTriangle className="h-8 w-8 shrink-0 text-warning-700" />
                ) : (
                  <XCircle className="h-8 w-8 shrink-0 text-danger-700" />
                )}
                <div className="min-w-0 flex-1 space-y-1">
                  <p className="text-base font-bold text-ink">
                    {result.result === 'checked_in'
                      ? 'Checked in'
                      : result.result === 'already_checked_in'
                        ? 'Already checked in'
                        : result.result === 'payment_required'
                          ? 'Not paid — not checked in'
                          : result.result === 'not_registered'
                            ? 'Not registered — walk-in'
                          : 'Not checked in'}
                  </p>
                  {result.member && (
                    <div className="flex items-center gap-2">
                      <MemberAvatar path={result.member.photo_path} name={result.member.display_name} size="md" />
                      <div>
                        <p className="font-semibold text-ink">{result.member.display_name}</p>
                        {result.member.member_number && (
                          <p className="text-xs text-ink-secondary">{result.member.member_number}</p>
                        )}
                      </div>
                    </div>
                  )}
                  {result.result === 'checked_in' && (
                    <p className="text-sm text-ink">
                      {result.first_check_in
                        ? 'First check-in for this event — give the kit and T-shirt.'
                        : `Checked in for today. Kit already given ${when(result.kit_given_at)}.`}
                    </p>
                  )}
                  {result.result === 'already_checked_in' && (
                    <p className="text-sm text-ink">
                      This QR was already scanned today at {formatNyTime(result.checked_in_at)}.
                      {result.kit_given_at ? ` Kit already given ${when(result.kit_given_at)}.` : ''} Do not give another kit.
                    </p>
                  )}
                  {result.result === 'checked_in' && result.payment && ['paid', 'waived'].includes(result.payment.status) && (
                    <p className="text-xs font-medium text-success-700">
                      {result.payment.status === 'paid' ? `Paid ${money(result.payment.paid)}` : 'Fee waived'}
                    </p>
                  )}
                  {result.result === 'not_registered' && (
                    <div className="space-y-2">
                      <p className="flex items-center gap-1 text-sm font-semibold text-danger-700">
                        <CircleDollarSign className="h-4 w-4" />
                        No reservation. Walk-in price {money(result.payment.walk_in_fee ?? result.payment.fee)}
                      </p>
                      {result.can_register ? (
                        <RecordPaymentForm
                          defaultAmount={result.payment.walk_in_fee ?? result.payment.fee}
                          submitLabel="Register walk-in, pay & check in"
                          busy={busy}
                          onSubmit={(amount, method) => payAndCheckIn(result.member.member_id, amount, method, true)}
                        />
                      ) : (
                        <p className="text-sm text-ink">Do not give the kit. Send the member to the registration table.</p>
                      )}
                    </div>
                  )}
                  {result.result === 'payment_required' && (
                    <div className="space-y-2">
                      <p className="flex items-center gap-1 text-sm font-semibold text-danger-700">
                        <CircleDollarSign className="h-4 w-4" />
                        Balance due {money(result.payment.balance)}
                        {result.payment.paid > 0 ? ` (paid ${money(result.payment.paid)} of ${money(result.payment.fee)})` : ''}
                      </p>
                      {result.can_record_payment ? (
                        <RecordPaymentForm
                          defaultAmount={result.payment.balance}
                          submitLabel="Record payment & check in"
                          busy={busy}
                          onSubmit={(amount, method) => payAndCheckIn(result.member.member_id, amount, method)}
                        />
                      ) : (
                        <p className="text-sm text-ink">Do not give the kit. Send the member to the payment table.</p>
                      )}
                    </div>
                  )}
                  {result.result === 'invalid' && (
                    <p className="text-sm text-ink">{INVALID_REASONS[result.reason] ?? 'This QR code cannot be used.'}</p>
                  )}
                </div>
              </div>
              {waitingForTap && (
                <div className="mt-3 flex justify-end">
                  <Button onClick={() => setResult(null)} icon={<ScanLine className="h-4 w-4" />}>
                    Scan next
                  </Button>
                </div>
              )}
            </Card>
          )}

          <form
            className="flex gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              const v = manual;
              setManual('');
              submit(v);
            }}
          >
            <Input
              value={manual}
              onChange={(e) => setManual(e.target.value)}
              placeholder="Handheld scanner or typed code"
              aria-label="QR code text"
              autoComplete="off"
            />
            <Button type="submit" variant="outline" disabled={busy || !manual.trim()}>
              Check in
            </Button>
          </form>

          {summary && summary.recent.length > 0 && (
            <Card padding="compact">
              <h2 className="mb-2 text-sm font-semibold text-ink">Latest check-ins today</h2>
              <ul className="divide-y divide-line">
                {summary.recent.map((r) => (
                  <li key={r.member_id + r.recorded_at} className="flex justify-between gap-2 py-1.5 text-sm">
                    <span className="truncate text-ink">{r.display_name}</span>
                    <span className="shrink-0 text-ink-muted">{formatNyTime(r.recorded_at)}</span>
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </>
      )}
    </div>
  );
}

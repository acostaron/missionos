// QR check-in desk for an event (Pass 9.12, written by Claude 2026-10-16).
// Scan the member's QR (My Card on the phone, or the ID card) with the camera or a handheld scanner.
// A member checks in once per event day; a second scan shows a warning. First check-in = kit and T-shirt given.
// Pass 9.15: guests (non-members) check in with their guest pass (MFCNYG1:<code>) or by name from the guest list.
// Pass 9.37: the QR on the old MFCNY ID cards is also accepted until administrators switch it off.
import { useCallback, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, ArrowLeft, CheckCircle2, CircleDollarSign, ScanLine, UserRound, XCircle } from 'lucide-react';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { useEvent, eventKeys } from '../features/events/queries';
import { getEventErrorMessage } from '../features/events/error-message';
import { QrScanner } from '../features/events/components/QrScanner';
import {
  GUEST_INVALID_REASONS,
  INVALID_REASONS,
  checkInKeys,
  isLegacyIdCard,
  scanCheckIn,
  useCheckInSettings,
  useCheckInSummary,
  useSetAcceptLegacyIdCards,
  type ScanResult,
} from '../features/events/check-in';
import { MemberAvatar } from '../features/self-service/components/MemberAvatar';
import {
  GUEST_PASS_PREFIX,
  PAYMENT_STATUS_LABELS,
  checkInEventGuest,
  invalidatePayments,
  money,
  recordEventGuestPayment,
  recordEventPayment,
  registerForEvent,
  useEventGuests,
  type PaymentMethod,
} from '../features/events/payments';
import { RecordPaymentForm } from '../features/events/components/RecordPaymentForm';
import { formatNyDateShort, formatNyTime } from '../lib/ny-time';
import { Alert, Badge, Button, Card, Input } from '../components/ui';

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

const SUCCESS = new Set<ScanResult['result']>(['checked_in', 'guest_checked_in']);
const WARNING = new Set<ScanResult['result']>(['already_checked_in', 'guest_already_checked_in']);

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
  const { data: settings } = useCheckInSettings(orgId);
  const setLegacy = useSetAcceptLegacyIdCards(orgId);
  const [lastWasLegacy, setLastWasLegacy] = useState(false);

  const [result, setResult] = useState<ScanResult | null>(null);
  const [errorText, setErrorText] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [manual, setManual] = useState('');
  const [showGuests, setShowGuests] = useState(false);
  const [guestQuery, setGuestQuery] = useState('');
  const { data: guestList } = useEventGuests(orgId, eventId ?? null, showGuests);
  const lastPayload = useRef('');
  const busyRef = useRef(false);
  const resumeTimer = useRef<number | undefined>(undefined);

  const process = useCallback(
    async (fetcher: () => Promise<ScanResult>) => {
      if (!orgId || !eventId || busyRef.current) return;
      busyRef.current = true;
      setBusy(true);
      setErrorText(null);
      window.clearTimeout(resumeTimer.current);
      try {
        const r = await fetcher();
        setResult(r);
        beep(SUCCESS.has(r.result));
        if (SUCCESS.has(r.result)) {
          // keep the desk moving: clear a success automatically
          resumeTimer.current = window.setTimeout(() => setResult(null), 4000);
        }
        await Promise.all([
          qc.invalidateQueries({ queryKey: checkInKeys.summary(orgId, eventId) }),
          qc.invalidateQueries({ queryKey: eventKeys.all }),
          invalidatePayments(qc),
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

  const submit = useCallback(
    async (payload: string) => {
      if (!orgId || !eventId || !payload.trim()) return;
      lastPayload.current = payload.trim();
      setLastWasLegacy(isLegacyIdCard(payload));
      await process(() => scanCheckIn(orgId, eventId, payload.trim()));
    },
    [orgId, eventId, process],
  );

  // Guest without a pass: check in by name from the guest list
  const checkInGuest = async (guestId: string) => {
    if (!orgId) return;
    lastPayload.current = '';
    setLastWasLegacy(false);
    await process(async () => (await checkInEventGuest(orgId, guestId)) as unknown as ScanResult);
  };

  const waitingForTap = result !== null && !SUCCESS.has(result.result);

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

  // Guests: record the payment, then check in again (same pass, or from the list)
  const payGuestAndCheckIn = async (guestId: string, amount: number, method: PaymentMethod) => {
    if (!orgId) return;
    try {
      setBusy(true);
      setErrorText(null);
      await recordEventGuestPayment(orgId, guestId, amount, method);
    } catch (e) {
      setErrorText(getEventErrorMessage(e));
      setBusy(false);
      return;
    }
    setBusy(false);
    if (lastPayload.current.toUpperCase().startsWith(GUEST_PASS_PREFIX)) await submit(lastPayload.current);
    else await checkInGuest(guestId);
  };

  const q = guestQuery.trim().toLowerCase();
  const matchedGuests = (guestList?.guests ?? []).filter(
    (g) => q.length >= 2 && (g.display_name.toLowerCase().includes(q) || (g.host_name ?? '').toLowerCase().includes(q)),
  );

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
              {(summary.guests_today ?? 0) > 0 && (
                <div className="flex-1 rounded-card border border-line bg-surface p-3">
                  <div className="text-2xl font-bold text-ink">{summary.guests_today}</div>
                  <div className="text-xs text-ink-secondary">guests today</div>
                </div>
              )}
            </div>
          )}

          <QrScanner paused={busy || waitingForTap} onDetect={submit} />

          {settings && (
            <div className="flex flex-wrap items-center gap-2 text-xs text-ink-secondary">
              <span>
                Old MFCNY ID cards:{' '}
                <span className="font-medium text-ink">{settings.accept_legacy_id_cards ? 'accepted' : 'not accepted'}</span>
              </span>
              {settings.can_manage && (
                <Button
                  size="sm"
                  variant="ghost"
                  loading={setLegacy.isPending}
                  onClick={() => setLegacy.mutate(!settings.accept_legacy_id_cards)}
                >
                  {settings.accept_legacy_id_cards ? 'Stop accepting old cards' : 'Accept old cards again'}
                </Button>
              )}
            </div>
          )}

          {errorText && (
            <Alert variant="danger" title="Could not check in">
              {errorText}
            </Alert>
          )}

          {result && (
            <Card
              padding="comfortable"
              className={
                SUCCESS.has(result.result)
                  ? 'border-2 border-success-600 bg-success-50'
                  : WARNING.has(result.result)
                    ? 'border-2 border-warning-600 bg-warning-50'
                    : 'border-2 border-danger-600 bg-danger-50'
              }
            >
              <div className="flex items-start gap-3" role="status" aria-live="assertive">
                {SUCCESS.has(result.result) ? (
                  <CheckCircle2 className="h-8 w-8 shrink-0 text-success-700" />
                ) : WARNING.has(result.result) ? (
                  <AlertTriangle className="h-8 w-8 shrink-0 text-warning-700" />
                ) : (
                  <XCircle className="h-8 w-8 shrink-0 text-danger-700" />
                )}
                <div className="min-w-0 flex-1 space-y-1">
                  <p className="text-base font-bold text-ink">
                    {result.result === 'checked_in'
                      ? 'Checked in'
                      : result.result === 'guest_checked_in'
                        ? 'Guest checked in'
                        : WARNING.has(result.result)
                          ? 'Already checked in'
                          : result.result === 'payment_required' || result.result === 'guest_payment_required'
                            ? 'Donation not complete — not checked in'
                            : result.result === 'not_registered'
                              ? 'Not registered — walk-in'
                              : 'Not checked in'}
                  </p>
                  {'guest' in result && result.guest && (
                    <div className="flex items-center gap-2">
                      <UserRound className="h-8 w-8 shrink-0 text-ink-muted" />
                      <div>
                        <p className="font-semibold text-ink">{result.guest.display_name}</p>
                        <p className="text-xs text-ink-secondary">
                          {result.guest.host_name ? `Guest of ${result.guest.host_name}` : 'Guest (non-member)'}
                        </p>
                      </div>
                    </div>
                  )}
                  {'member' in result && result.member && (
                    <div className="flex items-center gap-2">
                      <MemberAvatar path={result.member.photo_path} name={result.member.display_name} size="md" />
                      <div>
                        <p className="font-semibold text-ink">{result.member.display_name}</p>
                        {result.member.member_number && (
                          <p className="text-xs text-ink-secondary">{result.member.member_number}</p>
                        )}
                        {lastWasLegacy && (
                          <Badge variant="neutral" className="mt-0.5">Old ID card</Badge>
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
                      {result.payment.status === 'paid' ? `Donated ${money(result.payment.paid)}` : 'Donation waived'}
                    </p>
                  )}
                  {result.result === 'not_registered' && (
                    <div className="space-y-2">
                      <p className="flex items-center gap-1 text-sm font-semibold text-danger-700">
                        <CircleDollarSign className="h-4 w-4" />
                        No reservation. Walk-in donation {money(result.payment.walk_in_fee ?? result.payment.fee)}
                      </p>
                      {result.can_register ? (
                        <RecordPaymentForm
                          defaultAmount={result.payment.walk_in_fee ?? result.payment.fee}
                          submitLabel="Register walk-in, record donation & check in"
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
                        Donation pending {money(result.payment.balance)}
                        {result.payment.paid > 0 ? ` (donated ${money(result.payment.paid)} of ${money(result.payment.fee)})` : ''}
                      </p>
                      {result.can_record_payment ? (
                        <RecordPaymentForm
                          defaultAmount={result.payment.balance}
                          submitLabel="Record donation & check in"
                          busy={busy}
                          onSubmit={(amount, method) => payAndCheckIn(result.member.member_id, amount, method)}
                        />
                      ) : (
                        <p className="text-sm text-ink">Do not give the kit. Send the member to the donation table.</p>
                      )}
                    </div>
                  )}
                  {result.result === 'guest_checked_in' && (
                    <p className="text-sm text-ink">
                      {result.first_check_in
                        ? 'First check-in for this event — give the guest kit.'
                        : `Checked in for today. Kit already given ${when(result.kit_given_at)}.`}
                      {result.payment.status === 'paid' ? ` Donated ${money(result.payment.paid)}.` : ''}
                      {result.payment.status === 'waived' ? ' Donation waived.' : ''}
                    </p>
                  )}
                  {result.result === 'guest_already_checked_in' && (
                    <p className="text-sm text-ink">
                      This guest already checked in today at {formatNyTime(result.checked_in_at)}.
                      {result.kit_given_at ? ` Kit already given ${when(result.kit_given_at)}.` : ''} Do not give another kit.
                    </p>
                  )}
                  {result.result === 'guest_payment_required' && (
                    <div className="space-y-2">
                      <p className="flex items-center gap-1 text-sm font-semibold text-danger-700">
                        <CircleDollarSign className="h-4 w-4" />
                        Donation pending {money(result.payment.balance)}
                        {result.payment.paid > 0 ? ` (donated ${money(result.payment.paid)} of ${money(result.payment.fee)})` : ''}
                      </p>
                      {result.can_record_payment ? (
                        <RecordPaymentForm
                          defaultAmount={result.payment.balance}
                          submitLabel="Record donation & check in"
                          busy={busy}
                          onSubmit={(amount, method) => payGuestAndCheckIn(result.guest.guest_id, amount, method)}
                        />
                      ) : (
                        <p className="text-sm text-ink">Do not give the kit. Send the guest to the donation table.</p>
                      )}
                    </div>
                  )}
                  {result.result === 'guest_invalid' && (
                    <p className="text-sm text-ink">{GUEST_INVALID_REASONS[result.reason] ?? 'This guest pass cannot be used.'}</p>
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

          <Card padding="compact" className="space-y-2">
            {!showGuests ? (
              <Button size="sm" variant="ghost" icon={<UserRound className="h-4 w-4" />} onClick={() => setShowGuests(true)}>
                Guest without a pass? Find by name
              </Button>
            ) : (
              <>
                <h2 className="text-sm font-semibold text-ink">Find a guest</h2>
                <Input
                  value={guestQuery}
                  onChange={(e) => setGuestQuery(e.target.value)}
                  placeholder="Guest or host name"
                  aria-label="Guest or host name"
                  autoComplete="off"
                />
                {q.length >= 2 && matchedGuests.length === 0 && (
                  <p className="text-sm text-ink-muted">No guest found. Organizers can add walk-in guests on the Registrations page.</p>
                )}
                <ul className="divide-y divide-line">
                  {matchedGuests.map((g) => (
                    <li key={g.guest_id} className="flex items-center justify-between gap-2 py-1.5">
                      <span className="min-w-0 text-sm text-ink">
                        {g.display_name}
                        <span className="block text-xs text-ink-secondary">
                          {g.host_name ? `Guest of ${g.host_name}` : 'No host member'}
                        </span>
                      </span>
                      <span className="flex shrink-0 items-center gap-2">
                        {g.checked_in_today ? (
                          <Badge variant="success">Checked in</Badge>
                        ) : (
                          <>
                            {(g.payment.status === 'unpaid' || g.payment.status === 'partial') && (
                              <Badge variant="warning">{PAYMENT_STATUS_LABELS[g.payment.status]}</Badge>
                            )}
                            <Button size="sm" variant="outline" disabled={busy} onClick={() => checkInGuest(g.guest_id)}>
                              Check in
                            </Button>
                          </>
                        )}
                      </span>
                    </li>
                  ))}
                </ul>
              </>
            )}
          </Card>

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

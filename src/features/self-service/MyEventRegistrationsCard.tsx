// My Events: events open for registration — register, see my balance, cancel (Pass 9.14, Claude 2026-10-16).
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Ticket } from 'lucide-react';
import { formatNyDateShort, formatNyTime } from '../../lib/ny-time';
import { getEventErrorMessage } from '../events/error-message';
import {
  PRICE_TIER_LABELS,
  cancelEventRegistration,
  invalidatePayments,
  money,
  registerForEvent,
  useMyEventRegistrations,
  type MyEventRegistration,
} from '../events/payments';
import { Alert, Badge, Button, Card } from '../../components/ui';

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

export function MyEventRegistrationsCard({ organizationId }: { organizationId: string | null }) {
  const qc = useQueryClient();
  const { data: events = [] } = useMyEventRegistrations(organizationId);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [errorText, setErrorText] = useState<string | null>(null);

  if (!organizationId || events.length === 0) return null;

  const run = async (eventId: string, fn: () => Promise<unknown>) => {
    try {
      setBusyId(eventId);
      setErrorText(null);
      await fn();
      await invalidatePayments(qc);
    } catch (e) {
      setErrorText(getEventErrorMessage(e));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <Card padding="compact" className="space-y-3">
      <div className="flex items-center gap-2">
        <Ticket className="h-5 w-5 text-primary" />
        <h2 className="text-base font-semibold text-ink">Event registration</h2>
      </div>
      {errorText && (
        <Alert variant="danger" title="Could not save">
          {errorText}
        </Alert>
      )}
      <ul className="divide-y divide-line">
        {events.map((e) => {
          const my = e.my;
          const busy = busyId === e.event_id;
          return (
            <li key={e.event_id} className="space-y-1.5 py-3">
              <div>
                <p className="font-medium text-ink">{e.title}</p>
                <p className="text-xs text-ink-secondary">
                  {formatNyDateShort(e.starts_at)} · {formatNyTime(e.starts_at)}
                  {e.location_text ? ` · ${e.location_text}` : ''}
                </p>
                <p className="text-xs text-ink-muted">{priceText(e)}</p>
              </div>
              {my.registered ? (
                <div className="space-y-1">
                  <div className="flex flex-wrap items-center gap-2 text-sm">
                    <Badge variant="success">Registered</Badge>
                    {my.status === 'paid' && <Badge variant="success">Paid</Badge>}
                    {my.status === 'waived' && <Badge variant="info">Fee waived</Badge>}
                    {(my.status === 'unpaid' || my.status === 'partial') && (
                      <Badge variant="warning">{money(my.balance)} due</Badge>
                    )}
                    {my.price_tier && my.price_tier !== 'free' && (
                      <span className="text-xs text-ink-muted">
                        {PRICE_TIER_LABELS[my.price_tier]} price {money(my.fee)}
                      </span>
                    )}
                  </div>
                  {(my.status === 'unpaid' || my.status === 'partial') && (
                    <p className="text-xs text-ink-secondary">
                      Please pay the registration team or the treasurer before the event. You will be checked in with
                      your QR (My Card) once paid.
                    </p>
                  )}
                  {my.paid === 0 && !e.checked_in && (
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={busy}
                      onClick={() => {
                        if (window.confirm('Cancel your registration?')) {
                          run(e.event_id, () => cancelEventRegistration(organizationId, e.event_id, null));
                        }
                      }}
                    >
                      Cancel registration
                    </Button>
                  )}
                </div>
              ) : (
                e.registration_open && (
                  <Button size="sm" loading={busy} onClick={() => run(e.event_id, () => registerForEvent(organizationId, e.event_id, null))}>
                    Register{e.fee_amount ? ` · ${money(e.price_now.amount)}` : ''}
                  </Button>
                )
              )}
            </li>
          );
        })}
      </ul>
    </Card>
  );
}

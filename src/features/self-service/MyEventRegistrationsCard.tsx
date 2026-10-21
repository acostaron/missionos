// My Events: events open for registration — register, see my balance, cancel (Pass 9.14, Claude 2026-10-16).
// Pass 9.15: add my guests (non-members), see what they owe, show their guest pass, remove an unpaid guest.
import { useState } from 'react';
import { MapLink } from '../../components/MapLink';
import { useQueryClient } from '@tanstack/react-query';
import { QrCode, Ticket, UserPlus } from 'lucide-react';
import { formatNyDateShort, formatNyTime } from '../../lib/ny-time';
import { getEventErrorMessage } from '../events/error-message';
import {
  PRICE_TIER_LABELS,
  addEventGuest,
  cancelEventGuest,
  invalidatePayments,
  money,
  useMyEventGuests,
  useMyEventRegistrations,
  type EventGuest,
  type MyEventRegistration,
} from '../events/payments';
import { GuestForm } from '../events/components/GuestForm';
import { GuestPassModal } from '../events/components/GuestPassModal';
import { AdvancePaymentBlock } from '../events/components/AdvancePaymentBlock';
import { useMyPaymentReports } from '../events/advance-payments';
import { invalidateReplies, setMyReply } from '../replies/api';
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
  const { data: guests = [] } = useMyEventGuests(organizationId);
  const { data: myReports = [] } = useMyPaymentReports(organizationId);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [addingFor, setAddingFor] = useState<string | null>(null);
  const [pass, setPass] = useState<{ guest: EventGuest; title: string } | null>(null);
  const [errorText, setErrorText] = useState<string | null>(null);

  if (!organizationId || events.length === 0) return null;

  const run = async (eventId: string, fn: () => Promise<unknown>) => {
    try {
      setBusyId(eventId);
      setErrorText(null);
      await fn();
      await invalidatePayments(qc);
      await invalidateReplies(qc);
      return true;
    } catch (e) {
      setErrorText(getEventErrorMessage(e));
      return false;
    } finally {
      setBusyId(null);
    }
  };

  const guestsBlock = (e: MyEventRegistration) => {
    const mine = guests.filter((g) => g.event_id === e.event_id);
    const busy = busyId === e.event_id;
    return (
      <div className="space-y-1.5 pt-1">
        {mine.length > 0 && (
          <ul className="space-y-1">
            {mine.map((g) => {
              const p = g.payment;
              const due = p.status === 'unpaid' || p.status === 'partial';
              return (
                <li key={g.guest_id} className="flex flex-wrap items-center gap-2 text-sm">
                  <span className="text-ink">Guest: {g.display_name}</span>
                  {p.status === 'paid' && <Badge variant="success">Paid</Badge>}
                  {p.status === 'waived' && <Badge variant="info">Fee waived</Badge>}
                  {due && <Badge variant="warning">{money(p.balance)} due</Badge>}
                  {g.checked_in_today && <Badge variant="success">Checked in</Badge>}
                  <Button size="sm" variant="ghost" icon={<QrCode className="h-4 w-4" />} onClick={() => setPass({ guest: g, title: e.title })}>
                    Guest pass
                  </Button>
                  {p.paid === 0 && !g.checked_in_ever && (
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={busy}
                      onClick={() => {
                        if (window.confirm(`Remove ${g.display_name} from your guests?`)) {
                          run(e.event_id, () => cancelEventGuest(organizationId, g.guest_id));
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
        {mine.some((g) => g.payment.status === 'unpaid' || g.payment.status === 'partial') && (
          <p className="text-xs text-ink-secondary">Pay for your guests with the registration team or the treasurer.</p>
        )}
        {e.registration_open &&
          (addingFor === e.event_id ? (
            <div className="rounded-card border border-line p-3">
              <p className="mb-2 text-xs font-semibold text-ink-secondary">
                Add a guest (non-member)
              </p>
              <GuestForm
                submitLabel="Add guest"
                busy={busy}
                onSubmit={async (f) => {
                  const ok = await run(e.event_id, () => addEventGuest(organizationId, e.event_id, f, { asStaff: false }));
                  if (ok) setAddingFor(null);
                  return ok;
                }}
                extra={
                  <Button type="button" size="sm" variant="ghost" onClick={() => setAddingFor(null)}>
                    Cancel
                  </Button>
                }
              />
            </div>
          ) : (
            <Button size="sm" variant="outline" icon={<UserPlus className="h-4 w-4" />} onClick={() => setAddingFor(e.event_id)}>
              Add a guest
            </Button>
          ))}
      </div>
    );
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
                </p>
                <MapLink location={e.location_text} className="text-xs text-ink-secondary" />
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
                    <AdvancePaymentBlock
                      orgId={organizationId}
                      eventId={e.event_id}
                      balance={Number(my.balance)}
                      reports={myReports.filter((r) => r.event_id === e.event_id)}
                    />
                  )}
                  {my.paid === 0 && !e.checked_in && (
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={busy}
                      onClick={() => {
                        if (window.confirm('Cancel your registration?')) {
                          // Pass 9.29: cancelling = replying Not attending (cancels the unpaid registration)
                          run(e.event_id, () => setMyReply(organizationId, { eventId: e.event_id }, 'not_attending'));
                        }
                      }}
                    >
                      Cancel registration
                    </Button>
                  )}
                  {guestsBlock(e)}
                </div>
              ) : (
                e.registration_open && (
                  <Button
                    size="sm"
                    loading={busy}
                    // Pass 9.29: registering = replying Attending (registers while registration is open)
                    onClick={() => run(e.event_id, () => setMyReply(organizationId, { eventId: e.event_id }, 'attending'))}
                  >
                    Register{e.fee_amount ? ` · ${money(e.price_now.amount)}` : ''}
                  </Button>
                )
              )}
            </li>
          );
        })}
      </ul>
      {pass && <GuestPassModal guest={pass.guest} eventTitle={pass.title} onClose={() => setPass(null)} />}
    </Card>
  );
}

// Registrations page: Zelle / PayPal details members see in My Events (Pass 9.29, Ron 2026-10-21);
// check and cash instructions (Pass 9.30).
// Organization default (administrator / finance coordinator) and an optional override for this event.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { getEventErrorMessage } from '../error-message';
import { invalidatePayments } from '../payments';
import { setPaymentDetails, usePaymentDetails, type PaymentDetailsFields } from '../advance-payments';
import { Alert, Button, Card, Input } from '../../../components/ui';

const EMPTY: PaymentDetailsFields = {
  zelle_recipient: null,
  zelle_name: null,
  paypal_link: null,
  payment_note: null,
  check_payable_to: null,
  check_mailing_address: null,
  cash_check_note: null,
};

function DetailsForm({
  title,
  hint,
  initial,
  onSave,
}: {
  title: string;
  hint: string;
  initial: PaymentDetailsFields;
  onSave: (f: PaymentDetailsFields) => Promise<void>;
}) {
  const [f, setF] = useState<PaymentDetailsFields>(initial);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const field = (k: keyof PaymentDetailsFields, label: string, placeholder: string) => (
    <label className="block">
      <span className="mb-1 block text-xs font-medium text-ink-secondary">{label}</span>
      <Input
        value={f[k] ?? ''}
        placeholder={placeholder}
        onChange={(e) => {
          setSaved(false);
          setF({ ...f, [k]: e.target.value });
        }}
      />
    </label>
  );
  return (
    <form
      className="space-y-2"
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        try {
          await onSave(f);
          setSaved(true);
        } catch {
          // the error is shown by the card
        } finally {
          setBusy(false);
        }
      }}
    >
      <p className="text-xs font-semibold text-ink">{title}</p>
      <p className="text-xs text-ink-muted">{hint}</p>
      <div className="grid gap-2 sm:grid-cols-2">
        {field('zelle_recipient', 'Zelle email or phone', 'treasurer@example.org')}
        {field('zelle_name', 'Zelle name shown to members', 'MFC New York')}
        {field('paypal_link', 'PayPal link', 'https://paypal.me/yourname')}
        {field('payment_note', 'Zelle / PayPal note (optional)', 'Put your name and the event in the memo')}
        {field('check_payable_to', 'Checks payable to', 'MFC New York')}
        {field('check_mailing_address', 'Mail checks to (optional)', 'Street, City, NY ZIP')}
        {field('cash_check_note', 'Cash / check note (optional)', 'Hand to your chapter treasurer or give at the registration table')}
      </div>
      <div className="flex items-center gap-2">
        <Button size="sm" type="submit" loading={busy}>
          Save
        </Button>
        {saved && <span className="text-xs text-success-700">Saved</span>}
      </div>
    </form>
  );
}

export function PaymentDetailsCard({ orgId, eventId }: { orgId: string; eventId: string }) {
  const qc = useQueryClient();
  const { data } = usePaymentDetails(orgId, eventId);
  const [error, setError] = useState<string | null>(null);
  if (!data || (!data.can_edit_organization && !data.can_edit_event)) return null;

  const save = (target: string | null) => async (f: PaymentDetailsFields) => {
    try {
      setError(null);
      await setPaymentDetails(orgId, target, f);
      await invalidatePayments(qc);
    } catch (e) {
      setError(getEventErrorMessage(e));
      throw e;
    }
  };

  return (
    <Card padding="compact" className="space-y-4">
      <h2 className="text-sm font-semibold text-ink">Donation options (Zelle / PayPal / check / cash)</h2>
      {error && (
        <Alert variant="danger" title="Could not save">
          {error}
        </Alert>
      )}
      {data.can_edit_organization && (
        <DetailsForm
          title="For all events"
          hint="Shown to members on My Events for every event with a suggested donation, unless this event has its own details below."
          initial={data.organization ?? EMPTY}
          onSave={save(null)}
        />
      )}
      {data.can_edit_event && (
        <DetailsForm
          title="Only for this event (optional)"
          hint="Fill in only what differs for this event; leave blank to use the details for all events."
          initial={data.event ?? EMPTY}
          onSave={save(eventId)}
        />
      )}
    </Card>
  );
}

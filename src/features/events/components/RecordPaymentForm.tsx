// Amount + method + Save, used on the payments page and at the check-in desk (Pass 9.13, Claude 2026-10-16).
import { useState } from 'react';
import { Button, Input, Select } from '../../../components/ui';
import { PAYMENT_METHODS, type PaymentMethod } from '../payments';

export function RecordPaymentForm({
  defaultAmount,
  submitLabel,
  busy,
  onSubmit,
}: {
  defaultAmount: number;
  submitLabel: string;
  busy: boolean;
  onSubmit: (amount: number, method: PaymentMethod) => void;
}) {
  const [amount, setAmount] = useState(defaultAmount > 0 ? String(defaultAmount) : '');
  const [method, setMethod] = useState<PaymentMethod>('cash');
  const value = Number(amount);
  const ok = Number.isFinite(value) && value > 0 && value <= 10000;
  return (
    <form
      className="flex flex-wrap items-end gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        if (ok && !busy) onSubmit(Math.round(value * 100) / 100, method);
      }}
    >
      <label className="block w-28">
        <span className="mb-1 block text-xs font-medium text-ink-secondary">Amount ($)</span>
        <Input type="number" inputMode="decimal" min="0.01" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
      </label>
      <label className="block w-32">
        <span className="mb-1 block text-xs font-medium text-ink-secondary">Given by</span>
        <Select value={method} onChange={(e) => setMethod(e.target.value as PaymentMethod)}>
          {PAYMENT_METHODS.map((m) => (
            <option key={m.value} value={m.value}>
              {m.label}
            </option>
          ))}
        </Select>
      </label>
      <Button type="submit" disabled={!ok || busy} loading={busy}>
        {submitLabel}
      </Button>
    </form>
  );
}

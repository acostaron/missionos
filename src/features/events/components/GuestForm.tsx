// Add a guest (non-member): first and last name, optional phone or email (Pass 9.15, Claude 2026-10-16).
import { useState, type ReactNode } from 'react';
import { Button, Input } from '../../../components/ui';
import type { GuestFields } from '../payments';

const EMPTY: GuestFields = { firstName: '', lastName: '', phone: '', email: '', isChild: false };

export function GuestForm({
  submitLabel,
  busy,
  onSubmit,
  extra,
}: {
  submitLabel: string;
  busy: boolean;
  /** resolve true to clear the form */
  onSubmit: (f: GuestFields) => Promise<boolean>;
  extra?: ReactNode;
}) {
  const [f, setF] = useState<GuestFields>(EMPTY);
  const ok = f.firstName.trim().length > 0 && f.lastName.trim().length > 0;
  const set = (patch: Partial<GuestFields>) => setF((prev) => ({ ...prev, ...patch }));
  return (
    <form
      className="space-y-2"
      onSubmit={async (e) => {
        e.preventDefault();
        if (!ok || busy) return;
        if (await onSubmit(f)) setF(EMPTY);
      }}
    >
      <div className="grid grid-cols-2 gap-2">
        <label className="block">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">First name</span>
          <Input value={f.firstName} maxLength={80} autoComplete="off" onChange={(e) => set({ firstName: e.target.value })} />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">Last name</span>
          <Input value={f.lastName} maxLength={80} autoComplete="off" onChange={(e) => set({ lastName: e.target.value })} />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">Phone (optional)</span>
          <Input type="tel" value={f.phone} maxLength={30} autoComplete="off" onChange={(e) => set({ phone: e.target.value })} />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">Email (optional)</span>
          <Input type="email" value={f.email} maxLength={120} autoComplete="off" onChange={(e) => set({ email: e.target.value })} />
        </label>
      </div>
      {/* Pass 9.32: children get the event's child donation */}
      <label className="flex items-center gap-2 text-sm text-ink">
        <input type="checkbox" checked={!!f.isChild} onChange={(e) => set({ isChild: e.target.checked })} />
        Child (under 18)
      </label>
      {extra}
      <div className="flex justify-end">
        <Button type="submit" size="sm" disabled={!ok || busy} loading={busy}>
          {submitLabel}
        </Button>
      </div>
    </form>
  );
}

// My Profile: email reminders on / off (Pass 9.33, Ron 2026-10-21).
// Reminders go out 3 days and 1 day before my household meetings and events (Attending / registered), and a
// "Will you attend?" note when I have not replied.
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { BellRing } from 'lucide-react';
import { normalizeError } from '../../lib/supabase/errors';
import { setMyReminderPreferences, useMyReminderPreferences } from './api';
import { Card } from '../../components/ui';

export function ReminderPreferencesCard({ organizationId, enabled }: { organizationId: string | null; enabled: boolean }) {
  const qc = useQueryClient();
  const { data } = useMyReminderPreferences(organizationId, enabled);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (!organizationId || !enabled || !data) return null;

  const toggle = async (on: boolean) => {
    try {
      setBusy(true);
      setError(null);
      await setMyReminderPreferences(qc, organizationId, on);
    } catch (e) {
      setError(normalizeError(e).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card padding="comfortable" className="space-y-2">
      <div className="flex items-center gap-2">
        <BellRing className="h-5 w-5 text-primary" />
        <h2 className="text-base font-semibold text-ink">Reminders</h2>
      </div>
      <label className="flex items-start gap-2 text-sm text-ink">
        <input
          type="checkbox"
          className="mt-1"
          checked={data.email_enabled}
          disabled={busy}
          onChange={(e) => void toggle(e.target.checked)}
        />
        <span>
          Email me reminders 3 days and 1 day before my household meetings and events
          <span className="block text-xs text-ink-muted">
            Sent when you replied Attending or registered, and a &ldquo;Will you attend?&rdquo; note when you have not
            replied yet. Not attending = no reminder.
          </span>
        </span>
      </label>
      {!data.has_email && (
        <p className="text-xs text-warning-700">Add an email address above to receive reminders.</p>
      )}
      {error && <p className="text-xs text-danger-700">{error}</p>}
    </Card>
  );
}

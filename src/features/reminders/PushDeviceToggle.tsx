// My Profile → Reminders: push notifications on this device (Pass 9.34, Claude 2026-10-21).
import { useEffect, useState } from 'react';
import { Smartphone } from 'lucide-react';
import { normalizeError } from '../../lib/supabase/errors';
import { currentSubscription, disablePush, enablePush, pushSupport } from '../../lib/push';
import { Button } from '../../components/ui';

export function PushDeviceToggle({ organizationId }: { organizationId: string }) {
  const support = pushSupport();
  const [on, setOn] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    currentSubscription()
      .then((s) => alive && setOn(!!s))
      .catch(() => alive && setOn(false));
    return () => {
      alive = false;
    };
  }, []);

  const run = async (enable: boolean) => {
    try {
      setBusy(true);
      setError(null);
      if (enable) await enablePush(organizationId);
      else await disablePush(organizationId);
      setOn(enable);
    } catch (e) {
      setError(e instanceof Error && !('code' in e) ? e.message : normalizeError(e).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-1.5 border-t border-line pt-3">
      <div className="flex items-center gap-2 text-sm font-medium text-ink">
        <Smartphone className="h-4 w-4 text-primary" /> Notifications on this device
      </div>
      {support === 'ios_needs_home_screen' && (
        <p className="text-xs text-ink-secondary">
          On iPhone or iPad: open app.mfcny.net in Safari, tap <span className="font-medium">Share</span> →{' '}
          <span className="font-medium">Add to Home Screen</span>, then open MissionOS from the Home Screen and come back
          here to turn notifications on.
        </p>
      )}
      {support === 'unsupported' && (
        <p className="text-xs text-ink-secondary">This browser cannot show notifications. Try Chrome, Edge or Safari.</p>
      )}
      {support === 'supported' && on !== null && (
        <div className="flex flex-wrap items-center gap-2">
          {on ? (
            <>
              <span className="text-xs text-success-700">On for this device</span>
              <Button size="sm" variant="ghost" loading={busy} onClick={() => void run(false)}>
                Turn off
              </Button>
            </>
          ) : (
            <Button size="sm" variant="outline" loading={busy} onClick={() => void run(true)}>
              Turn on notifications
            </Button>
          )}
        </div>
      )}
      <p className="text-xs text-ink-muted">Same reminders as the emails, shown on your phone or computer.</p>
      {error && <p className="text-xs text-danger-700">{error}</p>}
    </div>
  );
}

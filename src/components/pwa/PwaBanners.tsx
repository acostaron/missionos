import { useState, useEffect } from 'react';
import { useRegisterSW } from 'virtual:pwa-register/react';
import { Button } from '../ui/Button';
import { WifiOff } from 'lucide-react';

export function PwaBanners() {
  const [isOnline, setIsOnline] = useState<boolean>(() =>
    typeof navigator !== 'undefined' ? navigator.onLine : true
  );

  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  const {
    needRefresh: [needRefresh],
    updateServiceWorker,
  } = useRegisterSW({
    onRegisterError(error) {
      console.error('PWA service worker registration error:', error);
    },
  });

  return (
    <>
      {!isOnline && (
        <aside
          role="status"
          aria-live="polite"
          className="sticky top-0 z-50 flex items-center justify-center gap-2 border-b border-warning-100 bg-warning-50 px-4 py-1.5 text-small font-medium text-warning-700 shadow-sm"
        >
          <WifiOff className="h-4 w-4 shrink-0" aria-hidden="true" />
          <span>You're offline. MissionOS needs a connection.</span>
        </aside>
      )}

      {needRefresh && (
        <aside
          role="status"
          aria-live="polite"
          className="fixed bottom-4 right-4 z-50 flex items-center gap-3 rounded-card border border-line-strong bg-surface p-3 shadow-card"
        >
          <p className="text-small font-medium text-ink">A new version is available.</p>
          <Button
            size="sm"
            variant="primary"
            onClick={() => {
              void updateServiceWorker(true);
            }}
          >
            Refresh
          </Button>
        </aside>
      )}
    </>
  );
}

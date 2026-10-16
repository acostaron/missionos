// On-screen guest pass: QR "MFCNYG1:<code>" + the code in text, for the desk to scan or type (Pass 9.15, Claude 2026-10-16).
// The host can show it on their phone, screenshot it, or print it for the guest.
import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { Button, Modal } from '../../../components/ui';
import { guestPassPayload, type EventGuest } from '../payments';

export function GuestPassModal({ guest, eventTitle, onClose }: { guest: EventGuest; eventTitle: string; onClose: () => void }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    QRCode.toDataURL(guestPassPayload(guest.guest_code), { errorCorrectionLevel: 'M', margin: 2, width: 320 })
      .then(setUrl)
      .catch(() => setUrl(null));
  }, [guest.guest_code]);

  return (
    <Modal
      open
      onClose={onClose}
      title="Guest pass"
      description={eventTitle}
      footer={
        <div className="flex w-full justify-end gap-2">
          <Button variant="outline" onClick={() => window.print()}>
            Print
          </Button>
          <Button variant="ghost" onClick={onClose}>
            Close
          </Button>
        </div>
      }
    >
      <div className="space-y-2 text-center">
        <p className="text-lg font-bold text-ink">{guest.display_name}</p>
        {guest.host_name && <p className="text-xs text-ink-secondary">Guest of {guest.host_name}</p>}
        {url ? (
          <img src={url} alt={`Guest pass QR for ${guest.display_name}`} className="mx-auto h-64 w-64" />
        ) : (
          <p className="text-sm text-ink-muted">Preparing the code…</p>
        )}
        <p className="font-mono text-sm tracking-widest text-ink">{guestPassPayload(guest.guest_code)}</p>
        <p className="text-xs text-ink-muted">
          Show this at the registration desk. A guest without a phone can also give their name at the desk.
        </p>
      </div>
    </Modal>
  );
}

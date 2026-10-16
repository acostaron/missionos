import { useState, useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import QRCode from 'qrcode';
import { Download, RefreshCw, Sun, User, ShieldAlert } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { useMyMemberCard, useReissueMemberCard, type MemberCard } from '../features/self-service/portal-api';
import { MemberAvatar } from '../features/self-service/components/MemberAvatar';
import { getEventErrorMessage } from '../features/events/error-message';
import { Alert, Button, Card, EmptyState, Modal } from '../components/ui';

interface OfflineCardData {
  payload: string;
  display_name: string;
  member_number: string | null;
  photo_path: string | null;
  organizational_context: {
    area: string | null;
    section: string | null;
    chapter: string | null;
    unit: string | null;
  };
  household_name: string | null;
  card_public_id: string | null;
  saved_at: string;
}

export default function MyCardPage() {
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;

  const { data: card, isLoading, error } = useMyMemberCard(orgId);
  const reissueMutation = useReissueMemberCard();

  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const [offlineData, setOfflineData] = useState<OfflineCardData | null>(null);
  const [isReplaceModalOpen, setIsReplaceModalOpen] = useState(false);
  const [replaceError, setReplaceError] = useState<string | null>(null);
  const [replaceSuccess, setReplaceSuccess] = useState<string | null>(null);
  const [isEnlarged, setIsEnlarged] = useState(false);

  const qrButtonRef = useRef<HTMLButtonElement>(null);
  const overlayRef = useRef<HTMLDivElement>(null);
  const prevEnlargedRef = useRef(false);

  // Focus management between button and overlay
  useEffect(() => {
    if (isEnlarged) {
      overlayRef.current?.focus();
    } else if (prevEnlargedRef.current) {
      qrButtonRef.current?.focus();
    }
    prevEnlargedRef.current = isEnlarged;
  }, [isEnlarged]);

  // Close overlay on Escape
  useEffect(() => {
    if (!isEnlarged) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setIsEnlarged(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isEnlarged]);

  // Keep screen awake while QR overlay is enlarged
  useEffect(() => {
    if (!isEnlarged) return;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let wakeLock: any = null;
    let isCancelled = false;

    const requestLock = async () => {
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const nav = navigator as any;
        if ('wakeLock' in nav && nav.wakeLock?.request) {
          const lock = await nav.wakeLock.request('screen');
          if (isCancelled) {
            await lock.release();
          } else {
            wakeLock = lock;
          }
        }
      } catch {
        // ignore wake lock errors
      }
    };

    requestLock();

    return () => {
      isCancelled = true;
      if (wakeLock) {
        wakeLock.release().catch(() => undefined);
      }
    };
  }, [isEnlarged]);

  const localStorageKey = orgId ? `missionos.myCard.${orgId}` : null;

  // On successful card load, cache in localStorage and generate QR
  useEffect(() => {
    if (card && localStorageKey) {
      const payload = card.qr_payload;

      QRCode.toDataURL(payload, { errorCorrectionLevel: 'M', margin: 2, width: 320 })
        .then((url) => setQrDataUrl(url))
        .catch(() => setQrDataUrl(null));

      try {
        const toSave: OfflineCardData = {
          payload,
          display_name: card.display_name,
          member_number: card.member_number,
          photo_path: card.photo_path,
          organizational_context: card.organizational_context,
          household_name: card.household_name,
          card_public_id: card.card_public_id,
          saved_at: new Date().toISOString(),
        };
        localStorage.setItem(localStorageKey, JSON.stringify(toSave));
      } catch {
        // ignore localStorage quota errors
      }
    }
  }, [card, localStorageKey]);

  // On query error, check if offline copy exists
  useEffect(() => {
    if (error && localStorageKey) {
      try {
        const saved = localStorage.getItem(localStorageKey);
        if (saved) {
          const parsed = JSON.parse(saved) as OfflineCardData;
          setOfflineData(parsed);

          QRCode.toDataURL(parsed.payload, { errorCorrectionLevel: 'M', margin: 2, width: 320 })
            .then((url) => setQrDataUrl(url))
            .catch(() => setQrDataUrl(null));
        }
      } catch {
        // fallback
      }
    }
  }, [error, localStorageKey]);

  const activeCard: MemberCard | OfflineCardData | null = card || offlineData;

  const handleDownloadQr = () => {
    if (!qrDataUrl) return;
    const link = document.createElement('a');
    const memberNum = activeCard?.member_number || 'member';
    link.download = `MFC-ID-${memberNum}.png`;
    link.href = qrDataUrl;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const handleReplaceQrConfirm = async () => {
    if (!orgId) return;
    setReplaceError(null);
    setReplaceSuccess(null);

    try {
      await reissueMutation.mutateAsync({
        organizationId: orgId,
        memberId: null,
        reason: 'Replaced by the member',
      });
      setReplaceSuccess('New QR issued successfully.');
      setIsReplaceModalOpen(false);
    } catch (err) {
      setReplaceError(getEventErrorMessage(err));
    }
  };

  if (isOrgLoading || (isLoading && !offlineData)) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center">
        <div className="text-sm text-ink-muted">Loading your ID card…</div>
      </div>
    );
  }

  const errObj = error as { code?: string; message?: string } | null;
  const isNotLinked = errObj?.code === 'P0002' || (errObj?.message && errObj.message.toLowerCase().includes('not linked'));

  if (isNotLinked && !offlineData) {
    return (
      <div className="mx-auto max-w-md px-4 py-8">
        <Card padding="comfortable">
          <EmptyState
            icon={<User />}
            title="Account Not Linked"
            message="Your MissionOS account is not currently linked to a member record. Once your servant leader or administrator connects your profile, your ID card will appear here."
            action={
              <Link
                to="/app/dashboard"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Return to Home
              </Link>
            }
          />
        </Card>
      </div>
    );
  }

  if ((error && !offlineData) || !activeCard || !orgId) {
    return (
      <div className="mx-auto max-w-md px-4 py-8">
        <Card padding="comfortable">
          <EmptyState
            icon={<ShieldAlert />}
            title="Unable to load card"
            message={error ? getEventErrorMessage(error) : 'Please select an active organization.'}
            action={
              <Link
                to="/app/dashboard"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Return to Home
              </Link>
            }
          />
        </Card>
      </div>
    );
  }

  // Format organization line: section · chapter · unit (skip nulls)
  const orgParts = [
    activeCard.organizational_context.section,
    activeCard.organizational_context.chapter,
    activeCard.organizational_context.unit,
  ].filter(Boolean);

  const cardIdShort = activeCard.card_public_id ? activeCard.card_public_id.slice(0, 8) : null;

  // Pass 9.17 (Ron, 2026-10-16): the whole card, QR included, fits on one phone screen without scrolling.
  // The QR shrinks with the screen height (between 8rem and 16rem); 31rem is everything else on the page
  // (app header, title, card details, buttons and the bottom navigation), measured at about 30rem.
  const qrSize = 'clamp(8rem, min(100vw - 7rem, 100dvh - 31rem), 16rem)';

  return (
    <div className="mx-auto max-w-md space-y-3 sm:space-y-6 sm:py-4">
      <div>
        {/* Pass 9.18 (Ron): show MEMBER, centered, instead of the page title (title kept for screen readers) */}
        <h1 className="sr-only">My MFC ID</h1>
        <p aria-hidden="true" className="text-center text-lg font-bold uppercase tracking-[0.3em] text-ink sm:text-page-title">
          Member
        </p>
        <p className="hidden text-center text-body text-ink-secondary sm:block">
          Show this digital ID card to check in at assemblies and community gatherings.
        </p>
      </div>

      {offlineData && !card && (
        <Alert variant="info">
          Offline copy saved {new Date(offlineData.saved_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}.
        </Alert>
      )}

      {replaceSuccess && (
        <Alert variant="success">
          {replaceSuccess}
        </Alert>
      )}

      {/* ID Card Display */}
      <div className="space-y-2 rounded-2xl border-2 border-line bg-white p-3 text-center text-slate-900 shadow-md sm:space-y-4 sm:p-6">
        {/* Header */}
        <div className="border-b border-slate-200 pb-2">
          <p className="text-[11px] font-bold uppercase tracking-widest text-primary-blue sm:text-xs">
            Missionary Families of Christ · New York
          </p>
        </div>

        {/* Member Avatar & Details */}
        <div className="flex items-center gap-3 text-left">
          <MemberAvatar
            path={activeCard.photo_path}
            name={activeCard.display_name}
            size="lg"
            className="shrink-0 ring-2 ring-primary-blue/20"
          />
          <div className="min-w-0 space-y-0.5">
            <h2 className="text-lg font-bold leading-tight text-slate-900">{activeCard.display_name}</h2>
            <p className="font-mono text-base font-bold tracking-wider text-slate-900">
              {activeCard.member_number || 'Not yet assigned'}
            </p>
            {orgParts.length > 0 && (
              <p className="truncate text-xs font-medium text-slate-600">{orgParts.join(' · ')}</p>
            )}
            {cardIdShort && <p className="text-[10px] font-mono text-slate-400">Card {cardIdShort}</p>}
          </div>
        </div>

        {/* QR Code Container */}
        <div className="flex flex-col items-center justify-center rounded-xl border border-slate-200 bg-white p-2 shadow-inner">
          {qrDataUrl ? (
            <button
              ref={qrButtonRef}
              type="button"
              aria-label="Enlarge QR code"
              onClick={() => setIsEnlarged(true)}
              className="cursor-pointer focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-blue rounded-lg"
            >
              <img
                src={qrDataUrl}
                alt="Your member QR code"
                className="aspect-square h-auto w-56 object-contain"
                style={{ width: qrSize }}
              />
            </button>
          ) : (
            <div
              className="flex aspect-square w-56 items-center justify-center text-xs text-slate-400"
              style={{ width: qrSize }}
            >
              Generating QR…
            </div>
          )}
        </div>

        <p className="flex items-center justify-center gap-1.5 text-[11px] text-slate-500">
          <Sun className="h-3.5 w-3.5 shrink-0 text-amber-500" />
          <span>Turn brightness up to scan · tap the QR to enlarge</span>
        </p>
      </div>

      {/* Action Buttons */}
      <div className="flex gap-2 sm:gap-3">
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="flex-1 gap-2"
          onClick={handleDownloadQr}
          disabled={!qrDataUrl}
        >
          <Download className="h-4 w-4" />
          Save QR image
        </Button>

        <Button
          type="button"
          variant="outline"
          size="sm"
          className="flex-1 gap-2 text-ink-secondary hover:text-ink"
          onClick={() => setIsReplaceModalOpen(true)}
        >
          <RefreshCw className="h-4 w-4" />
          Replace my QR
        </Button>
      </div>

      {/* Replace Confirmation Modal */}
      <Modal
        open={isReplaceModalOpen}
        onClose={() => setIsReplaceModalOpen(false)}
        title="Replace Your QR Code?"
        size="md"
        footer={
          <>
            <Button
              type="button"
              variant="outline"
              onClick={() => setIsReplaceModalOpen(false)}
              disabled={reissueMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="danger"
              onClick={handleReplaceQrConfirm}
              loading={reissueMutation.isPending}
            >
              Replace QR Code
            </Button>
          </>
        }
      >
        <div className="space-y-3">
          {replaceError && <Alert variant="danger">{replaceError}</Alert>}
          <p className="text-small text-ink-secondary">
            Your old QR code (including any screenshots or printed copies) will stop working immediately.
          </p>
          <p className="text-small text-ink-secondary">
            A new QR code will be generated and linked to your member number.
          </p>
        </div>
      </Modal>

      {/* Full-screen Enlarged QR Overlay */}
      {isEnlarged && qrDataUrl && activeCard && (
        <div
          ref={overlayRef}
          tabIndex={-1}
          role="dialog"
          aria-modal="true"
          aria-label="Enlarged QR code"
          onClick={() => setIsEnlarged(false)}
          className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-white p-4 cursor-pointer select-none outline-none"
        >
          <img
            src={qrDataUrl}
            alt="Your member QR code"
            style={{
              width: 'min(92vw, 92vh)',
              height: 'min(92vw, 92vh)',
              imageRendering: 'pixelated',
            }}
            className="max-w-none object-contain"
          />
          <div className="mt-4 text-2xl font-bold text-slate-900 text-center">
            {activeCard.display_name}
          </div>
          <div className="mt-1 font-mono text-xl font-bold text-slate-700 text-center">
            {activeCard.member_number
              ? `Member No. ${activeCard.member_number}`
              : 'Member No. not yet assigned'}
          </div>
          <div className="mt-3 text-sm text-slate-400 text-center">
            Tap anywhere to close
          </div>
        </div>
      )}
    </div>
  );
}

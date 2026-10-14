import { useState, useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import QRCode from 'qrcode';
import { ArrowLeft, Download, RefreshCw, Sun, User, ShieldAlert } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { useMyMemberCard, useReissueMemberCard, type MemberCard } from '../features/self-service/portal-api';
import { MemberAvatar } from '../features/self-service/components/MemberAvatar';
import { getEventErrorMessage } from '../features/events/error-message';
import { Alert, Button, Card, EmptyState, Modal, PageHeader } from '../components/ui';

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

  return (
    <div className="mx-auto max-w-md space-y-6 px-4 py-8">
      <PageHeader
        title="My MFC ID"
        description="Show this digital ID card to check in at assemblies and community gatherings."
        breadcrumb={
          <nav aria-label="Breadcrumb" className="flex items-center gap-2 text-xs text-ink-muted">
            <Link
              to="/app/profile"
              className="inline-flex items-center gap-1 hover:text-ink transition-colors"
            >
              <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
              My Profile
            </Link>
            <span aria-hidden="true">/</span>
            <span className="font-medium text-ink">My Card</span>
          </nav>
        }
      />

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
      <div className="rounded-2xl border-2 border-line bg-white p-6 shadow-md text-slate-900 space-y-5 text-center">
        {/* Header */}
        <div className="border-b border-slate-200 pb-3">
          <p className="text-xs font-bold uppercase tracking-widest text-primary-blue">
            Missionary Families of Christ
          </p>
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">
            New York
          </p>
        </div>

        {/* Member Avatar & Details */}
        <div className="flex flex-col items-center space-y-2">
          <MemberAvatar
            path={activeCard.photo_path}
            name={activeCard.display_name}
            size="lg"
            className="ring-2 ring-primary-blue/20"
          />
          <h2 className="text-xl font-bold text-slate-900 pt-1">
            {activeCard.display_name}
          </h2>

          <div className="rounded-md bg-slate-50 px-3 py-1.5 border border-slate-200">
            <p className="text-[11px] font-medium uppercase tracking-wider text-slate-500">
              Member No.
            </p>
            <p className="font-mono text-lg font-bold tracking-wider text-slate-900">
              {activeCard.member_number || 'Member No. not yet assigned'}
            </p>
          </div>

          {orgParts.length > 0 && (
            <p className="text-xs font-medium text-slate-600">
              {orgParts.join(' · ')}
            </p>
          )}

          {activeCard.household_name && (
            <p className="text-xs text-slate-500">
              {activeCard.household_name}
            </p>
          )}
        </div>

        {/* QR Code Container */}
        <div className="flex flex-col items-center justify-center p-3 rounded-xl bg-white border border-slate-200 shadow-inner">
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
                className="h-56 w-56 object-contain"
              />
            </button>
          ) : (
            <div className="flex h-56 w-56 items-center justify-center text-xs text-slate-400">
              Generating QR…
            </div>
          )}
        </div>

        {cardIdShort && (
          <p className="text-[11px] font-mono text-slate-400">
            Card {cardIdShort}
          </p>
        )}
      </div>

      {/* Tip & Action Buttons */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 rounded-lg bg-surface-muted p-3 text-xs text-ink-secondary">
          <Sun className="h-4 w-4 shrink-0 text-amber-500" />
          <span>Tip: Turn your screen brightness up when scanning.</span>
        </div>

        <div className="flex flex-col sm:flex-row gap-3">
          <Button
            type="button"
            variant="outline"
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
            className="flex-1 gap-2 text-ink-secondary hover:text-ink"
            onClick={() => setIsReplaceModalOpen(true)}
          >
            <RefreshCw className="h-4 w-4" />
            Replace my QR
          </Button>
        </div>
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

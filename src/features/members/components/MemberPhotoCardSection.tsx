import { useState } from 'react';
import { Camera, QrCode } from 'lucide-react';
import { MemberPhotoUploader } from '../../self-service/components/MemberPhotoUploader';
import { useReissueMemberCard } from '../../self-service/portal-api';
import { getEventErrorMessage } from '../../events/error-message';
import { Alert, Button, FormField, Modal, Textarea } from '../../../components/ui';

export interface MemberPhotoCardSectionProps {
  organizationId: string;
  memberId: string;
  memberName: string;
  initialPhotoPath?: string | null;
}

export function MemberPhotoCardSection({
  organizationId,
  memberId,
  memberName,
  initialPhotoPath = null,
}: MemberPhotoCardSectionProps) {
  const [photoPath, setPhotoPath] = useState<string | null>(initialPhotoPath);
  const [isQrModalOpen, setIsQrModalOpen] = useState(false);
  const [reissueReason, setReissueReason] = useState('');
  const [qrSuccessMsg, setQrSuccessMsg] = useState<string | null>(null);
  const [qrErrorMsg, setQrErrorMsg] = useState<string | null>(null);

  const reissueMutation = useReissueMemberCard();

  const handleReissueQr = async (e: React.FormEvent) => {
    e.preventDefault();
    if (reissueReason.trim().length < 5) return;

    setQrErrorMsg(null);
    setQrSuccessMsg(null);

    try {
      await reissueMutation.mutateAsync({
        organizationId,
        memberId,
        reason: reissueReason.trim(),
      });
      setQrSuccessMsg("A new QR was issued. The member's old QR no longer works.");
      setIsQrModalOpen(false);
      setReissueReason('');
    } catch (err) {
      setQrErrorMsg(getEventErrorMessage(err));
    }
  };

  return (
    <div className="rounded-xl border border-line bg-surface-muted overflow-hidden shadow-xs">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-ink-muted">
            <Camera className="h-4 w-4" />
          </span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
            Photo & ID Card
          </h2>
        </div>
      </div>

      <div className="p-5 space-y-5">
        {qrSuccessMsg && (
          <Alert variant="success">
            {qrSuccessMsg}
          </Alert>
        )}

        {qrErrorMsg && (
          <Alert variant="danger">
            {qrErrorMsg}
          </Alert>
        )}

        {/* Photo Uploader */}
        <MemberPhotoUploader
          organizationId={organizationId}
          memberId={memberId}
          effectiveMemberId={memberId}
          currentPath={photoPath}
          memberName={memberName}
          onPhotoChanged={setPhotoPath}
        />

        {/* QR Reissue */}
        <div className="border-t border-line pt-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div>
            <p className="text-small font-medium text-ink">Member QR Code</p>
            <p className="text-caption text-ink-muted">
              If the member lost their printed card or needs a new QR code, leaders may issue a replacement.
            </p>
          </div>

          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => {
              setQrErrorMsg(null);
              setIsQrModalOpen(true);
            }}
            className="gap-1.5 shrink-0"
          >
            <QrCode className="h-4 w-4" />
            Replace member&apos;s QR
          </Button>
        </div>
      </div>

      {/* Reissue QR Modal */}
      <Modal
        open={isQrModalOpen}
        onClose={() => setIsQrModalOpen(false)}
        title="Replace Member's QR Code"
        size="md"
        footer={
          <>
            <Button
              type="button"
              variant="outline"
              onClick={() => setIsQrModalOpen(false)}
              disabled={reissueMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="danger"
              disabled={reissueReason.trim().length < 5 || reissueMutation.isPending}
              loading={reissueMutation.isPending}
              onClick={handleReissueQr}
            >
              Issue New QR
            </Button>
          </>
        }
      >
        <form onSubmit={handleReissueQr} className="space-y-4">
          <p className="text-small text-ink-secondary">
            The member&apos;s previous QR code will immediately be invalidated. Please provide a reason for the audit log (at least 5 characters).
          </p>

          <FormField label="Reason for replacement" required>
            <Textarea
              value={reissueReason}
              onChange={(e) => setReissueReason(e.target.value)}
              placeholder="e.g. Member lost physical ID card / requested reset"
              required
              rows={3}
              minLength={5}
            />
          </FormField>
        </form>
      </Modal>
    </div>
  );
}

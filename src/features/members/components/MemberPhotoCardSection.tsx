import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Camera, Download, QrCode } from 'lucide-react';
import QRCode from 'qrcode';
import { MemberPhotoUploader } from '../../self-service/components/MemberPhotoUploader';
import { useMyMemberCard, useReissueMemberCard } from '../../self-service/portal-api';
import { useMemberPhotoPath } from '../queries';
import { usePermissions } from '../../../hooks/use-permissions';
import { Permissions } from '../../../types/permissions';
import { getEventErrorMessage } from '../../events/error-message';
import { Alert, Button, FormField, Modal, Textarea } from '../../../components/ui';

export interface MemberPhotoCardSectionProps {
  organizationId: string;
  memberId: string;
  memberName: string;
  memberNumber?: string | null;
  canEditPhoto?: boolean;
  canManageQr?: boolean;
}

export function MemberPhotoCardSection({
  organizationId,
  memberId,
  memberName,
  memberNumber,
  canEditPhoto = true,
  canManageQr: canManageQrProp,
}: MemberPhotoCardSectionProps) {
  const queryClient = useQueryClient();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const canManageQr = canManageQrProp !== undefined ? canManageQrProp : (!isPermLoading && hasPermission(Permissions.MembersQrManage));

  const { data: photoData } = useMemberPhotoPath(organizationId, memberId);
  const [localPhotoPath, setLocalPhotoPath] = useState<string | null | undefined>(undefined);

  const photoPath = localPhotoPath !== undefined ? localPhotoPath : (photoData?.photo_path ?? null);

  const handlePhotoChanged = (newPath: string | null) => {
    setLocalPhotoPath(newPath);
    queryClient.invalidateQueries({
      queryKey: ['members', 'photo-path', organizationId, memberId],
    });
    queryClient.invalidateQueries({
      queryKey: ['members', 'photo-urls'],
    });
  };
  const [isQrModalOpen, setIsQrModalOpen] = useState(false);
  const [reissueReason, setReissueReason] = useState('');
  const [qrSuccessMsg, setQrSuccessMsg] = useState<string | null>(null);
  const [qrErrorMsg, setQrErrorMsg] = useState<string | null>(null);
  const [issuedQrPayload, setIssuedQrPayload] = useState<string | null>(null);

  const { data: myCard } = useMyMemberCard(organizationId);
  const isOwnProfile = myCard?.member_id === memberId;
  const activeQrPayload = issuedQrPayload || (isOwnProfile ? myCard?.qr_payload : null);

  const reissueMutation = useReissueMemberCard();

  const handleSaveQrImage = async () => {
    if (!activeQrPayload) return;
    try {
      const dataUrl = await QRCode.toDataURL(activeQrPayload, {
        errorCorrectionLevel: 'M',
        margin: 2,
        width: 320,
      });
      const link = document.createElement('a');
      const num = memberNumber || 'member';
      link.download = `MFCNY-${num}-QR.png`;
      link.href = dataUrl;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    } catch {
      setQrErrorMsg('Failed to generate QR image for download.');
    }
  };

  const handleReissueQr = async (e: React.FormEvent) => {
    e.preventDefault();
    if (reissueReason.trim().length < 5) return;

    setQrErrorMsg(null);
    setQrSuccessMsg(null);

    try {
      const newCard = await reissueMutation.mutateAsync({
        organizationId,
        memberId,
        reason: reissueReason.trim(),
      });
      setIssuedQrPayload(newCard.qr_payload);
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
        {canEditPhoto && (
          <MemberPhotoUploader
            organizationId={organizationId}
            memberId={memberId}
            effectiveMemberId={memberId}
            currentPath={photoPath}
            memberName={memberName}
            onPhotoChanged={handlePhotoChanged}
          />
        )}

        {/* QR Management */}
        {canManageQr && (
          <div className={`${canEditPhoto ? 'border-t border-line pt-4 ' : ''}flex flex-col sm:flex-row sm:items-center justify-between gap-3`}>
            <div>
              <p className="text-small font-medium text-ink">Member QR Code</p>
              <p className="text-caption text-ink-muted">
                If this member lost their card or needs a new QR code, authorized administrators may replace it.
              </p>
            </div>

            <div className="flex items-center gap-2 shrink-0">
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={handleSaveQrImage}
                disabled={!activeQrPayload}
                className="gap-1.5"
                title={!activeQrPayload ? 'Reissue or replace QR to export the active image' : 'Save QR Image'}
              >
                <Download className="h-4 w-4" />
                Save QR Image
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => {
                  setQrErrorMsg(null);
                  setIsQrModalOpen(true);
                }}
                className="gap-1.5"
              >
                <QrCode className="h-4 w-4" />
                Replace QR
              </Button>
            </div>
          </div>
        )}
      </div>

      {/* Reissue QR Modal */}
      {canManageQr && (
        <Modal
          open={isQrModalOpen}
          onClose={() => setIsQrModalOpen(false)}
          title="Replace this member's QR code?"
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
                Replace QR
              </Button>
            </>
          }
        >
          <form onSubmit={handleReissueQr} className="space-y-4">
            <p className="text-small text-ink-secondary">
              The current QR code will stop working immediately. If this member has a printed ID card, a new ID card or QR label will need to be issued.
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
      )}
    </div>
  );
}

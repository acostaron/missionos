import { useState, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Camera, Trash2 } from 'lucide-react';
import { MemberAvatar } from './MemberAvatar';
import { uploadMemberPhoto, removeMemberPhoto } from '../photo';
import { selfServiceKeys } from '../api';
import { Alert, Button, Modal } from '../../../components/ui';

export interface MemberPhotoUploaderProps {
  organizationId: string;
  memberId: string | null; // null = myself for RPC
  effectiveMemberId: string; // actual member UUID for storage path
  currentPath: string | null;
  memberName: string;
  onPhotoChanged?: (newPath: string | null) => void;
}

export function MemberPhotoUploader({
  organizationId,
  memberId,
  effectiveMemberId,
  currentPath,
  memberName,
  onPhotoChanged,
}: MemberPhotoUploaderProps) {
  const queryClient = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [isUploading, setIsUploading] = useState(false);
  const [isRemoving, setIsRemoving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [isRemoveModalOpen, setIsRemoveModalOpen] = useState(false);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setErrorMsg(null);
    setSuccessMsg(null);
    setIsUploading(true);

    try {
      const newPath = await uploadMemberPhoto({
        organizationId,
        memberId,
        effectiveMemberId,
        file,
      });

      queryClient.invalidateQueries({ queryKey: selfServiceKeys.all });
      queryClient.invalidateQueries({ queryKey: ['members'] });
      setSuccessMsg('Photo updated successfully.');
      onPhotoChanged?.(newPath);
    } catch (err) {
      const msg = (err as Error).message || 'Failed to upload photo.';
      setErrorMsg(msg);
    } finally {
      setIsUploading(false);
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  };

  const handleConfirmRemove = async () => {
    setErrorMsg(null);
    setSuccessMsg(null);
    setIsRemoving(true);

    try {
      await removeMemberPhoto({
        organizationId,
        memberId,
        currentPath,
      });

      queryClient.invalidateQueries({ queryKey: selfServiceKeys.all });
      queryClient.invalidateQueries({ queryKey: ['members'] });
      setSuccessMsg('Photo removed.');
      setIsRemoveModalOpen(false);
      onPhotoChanged?.(null);
    } catch (err) {
      const msg = (err as Error).message || 'Failed to remove photo.';
      setErrorMsg(msg);
    } finally {
      setIsRemoving(false);
    }
  };

  return (
    <div className="space-y-4">
      {errorMsg && (
        <Alert variant="danger">
          {errorMsg}
        </Alert>
      )}

      {successMsg && (
        <Alert variant="success">
          {successMsg}
        </Alert>
      )}

      <div className="flex flex-col sm:flex-row items-center gap-5">
        <MemberAvatar path={currentPath} name={memberName} size="xl" />

        <div className="space-y-2 text-center sm:text-left">
          <div className="flex flex-wrap items-center justify-center sm:justify-start gap-2.5">
            <input
              type="file"
              ref={fileInputRef}
              onChange={handleFileChange}
              accept="image/jpeg,image/png,image/webp"
              className="hidden"
            />
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => fileInputRef.current?.click()}
              loading={isUploading}
              disabled={isUploading || isRemoving}
              className="gap-1.5"
            >
              <Camera className="h-4 w-4" />
              {currentPath ? 'Change photo' : 'Add photo'}
            </Button>

            {currentPath && (
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => setIsRemoveModalOpen(true)}
                disabled={isUploading || isRemoving}
                className="gap-1.5 text-danger-700 hover:bg-danger-50 hover:border-danger-200"
              >
                <Trash2 className="h-4 w-4" />
                Remove photo
              </Button>
            )}
          </div>

          <p className="text-caption text-ink-muted">
            Accepts JPG, PNG, or WebP up to 15 MB. Photos are automatically resized to 800px.
          </p>
        </div>
      </div>

      <Modal
        open={isRemoveModalOpen}
        onClose={() => setIsRemoveModalOpen(false)}
        title="Remove Photo?"
        size="sm"
        footer={
          <>
            <Button
              type="button"
              variant="outline"
              onClick={() => setIsRemoveModalOpen(false)}
              disabled={isRemoving}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="danger"
              onClick={handleConfirmRemove}
              loading={isRemoving}
            >
              Remove Photo
            </Button>
          </>
        }
      >
        <p className="text-small text-ink-secondary">
          Are you sure you want to remove this photo? Your profile will show your initials instead.
        </p>
      </Modal>
    </div>
  );
}

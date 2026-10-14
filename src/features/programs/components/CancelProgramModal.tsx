import { useState, useId } from 'react';
import {
  Modal,
  Button,
  FormField,
  Textarea,
  Alert,
} from '../../../components/ui';
import { useSetProgramRunStatus } from '../queries';
import { getEventErrorMessage } from '../../events/error-message';

interface CancelProgramModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  runId: string;
  programTitle: string;
  onSuccess?: () => void;
}

export function CancelProgramModal({
  open,
  onClose,
  organizationId,
  runId,
  programTitle,
  onSuccess,
}: CancelProgramModalProps) {
  const [reason, setReason] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const reasonId = useId();

  const cancelMutation = useSetProgramRunStatus();
  const isSubmitting = cancelMutation.isPending;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const trimmedReason = reason.trim();
    if (trimmedReason.length < 5) {
      setErrorMessage('Please provide a reason of at least 5 characters.');
      return;
    }

    try {
      await cancelMutation.mutateAsync({
        organizationId,
        runId,
        status: 'cancelled',
        reason: trimmedReason,
      });
      onSuccess?.();
      onClose();
    } catch (err) {
      setErrorMessage(getEventErrorMessage(err));
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Cancel Program"
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={onClose} disabled={isSubmitting}>
            Keep Program
          </Button>
          <Button
            type="submit"
            form="cancel-program-form"
            loading={isSubmitting}
            variant="danger"
          >
            Cancel Program
          </Button>
        </div>
      }
    >
      <form id="cancel-program-form" onSubmit={handleSubmit} className="space-y-4">
        <p className="text-body text-ink-secondary">
          Are you sure you want to cancel <strong className="text-ink">{programTitle}</strong>?
          This will also cancel all scheduled sessions of this program that have not had attendance recorded.
        </p>

        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        <FormField label="Reason for cancellation" required>
          <Textarea
            id={reasonId}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Explain why this program is being cancelled (min. 5 characters)..."
            disabled={isSubmitting}
            rows={3}
            required
          />
        </FormField>
      </form>
    </Modal>
  );
}

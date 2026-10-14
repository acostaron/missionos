import { useState, useId } from 'react';
import {
  Modal,
  Button,
  FormField,
  Textarea,
  Alert,
} from '../../../components/ui';
import { useSetEventStatus } from '../queries';
import { getEventErrorMessage } from '../error-message';

interface CancelEventModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  eventId: string;
  eventTitle: string;
  onSuccess?: () => void;
}

export function CancelEventModal({
  open,
  onClose,
  organizationId,
  eventId,
  eventTitle,
  onSuccess,
}: CancelEventModalProps) {
  const [reason, setReason] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const statusMutation = useSetEventStatus();
  const reasonId = useId();

  const handleCancel = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const trimmed = reason.trim();
    if (trimmed.length < 5) {
      setErrorMessage('A reason of at least 5 characters is required to cancel an event.');
      return;
    }

    try {
      await statusMutation.mutateAsync({
        organizationId,
        eventId,
        status: 'cancelled',
        reason: trimmed,
      });
      setReason('');
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
      title="Cancel Event"
      description={`Are you sure you want to cancel "${eventTitle}"?`}
      size="sm"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={onClose} disabled={statusMutation.isPending}>
            Back
          </Button>
          <Button
            type="submit"
            form="cancel-event-form"
            variant="danger"
            loading={statusMutation.isPending}
          >
            Cancel Event
          </Button>
        </div>
      }
    >
      <form id="cancel-event-form" onSubmit={handleCancel} className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        <FormField
          label="Cancellation Reason"
          hint="Minimum 5 characters. This will be visible on the event details."
          required
        >
          <Textarea
            id={reasonId}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. Inclement weather, rescheduled..."
            rows={3}
            disabled={statusMutation.isPending}
            required
          />
        </FormField>
      </form>
    </Modal>
  );
}

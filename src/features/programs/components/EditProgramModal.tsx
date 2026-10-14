import { useState, useEffect, useId } from 'react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Textarea,
  Alert,
} from '../../../components/ui';
import { useUpdateProgramRun } from '../queries';
import { getEventErrorMessage } from '../../events/error-message';
import type { ProgramRunSummary } from '../types';

interface EditProgramModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  run: ProgramRunSummary;
  onSuccess?: () => void;
}

export function EditProgramModal({
  open,
  onClose,
  organizationId,
  run,
  onSuccess,
}: EditProgramModalProps) {
  const updateMutation = useUpdateProgramRun();
  const isSubmitting = updateMutation.isPending;

  const [title, setTitle] = useState(run.title);
  const [description, setDescription] = useState(run.description || '');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const descId = useId();

  useEffect(() => {
    if (open) {
      setTitle(run.title);
      setDescription(run.description || '');
      setErrorMessage(null);
    }
  }, [open, run]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const trimmed = title.trim();
    if (trimmed.length < 3) {
      setErrorMessage('Program title must be at least 3 characters.');
      return;
    }

    try {
      await updateMutation.mutateAsync({
        organizationId,
        runId: run.id,
        title: trimmed,
        description: description.trim() || undefined,
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
      title="Edit Program"
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={onClose} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="edit-program-form"
            loading={isSubmitting}
            variant="primary"
          >
            Save Changes
          </Button>
        </div>
      }
    >
      <form id="edit-program-form" onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        <FormField label="Title" required>
          <Input
            id={titleId}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            disabled={isSubmitting}
            maxLength={200}
            required
          />
        </FormField>

        <FormField label="Description (optional)">
          <Textarea
            id={descId}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            disabled={isSubmitting}
            maxLength={2000}
            rows={3}
          />
        </FormField>
      </form>
    </Modal>
  );
}

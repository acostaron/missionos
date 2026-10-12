import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import {
  useVoidFormationProgramRecord,
  useVoidFormationTalkRecord,
} from '../queries';
import {
  voidFormationRecordSchema,
  type VoidFormationRecordFormValues,
} from '../form-schemas';
import { normalizeError } from '../../../lib/supabase/errors';
import { Alert, Button, FormField, Modal, Textarea } from '../../../components/ui';

interface VoidFormationRecordModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  mode: 'program' | 'talk';
  recordId: string;
  recordTitle: string;
  onSuccessToast?: (msg: string) => void;
}

export function VoidFormationRecordModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  mode,
  recordId,
  recordTitle,
  onSuccessToast,
}: VoidFormationRecordModalProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const voidProgramMutation = useVoidFormationProgramRecord(memberId);
  const voidTalkMutation = useVoidFormationTalkRecord(memberId);

  const isPending = voidProgramMutation.isPending || voidTalkMutation.isPending;

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<VoidFormationRecordFormValues>({
    resolver: zodResolver(voidFormationRecordSchema),
    defaultValues: {
      voidReason: '',
    },
  });

  useEffect(() => {
    if (isOpen) {
      setErrorMessage(null);
      reset({ voidReason: '' });
    }
  }, [isOpen, reset]);

  const copyText =
    mode === 'program'
      ? 'This record will be removed from the transcript. Its talks will be removed too. History is kept for audit. To fix a mistake, remove it and record it again.'
      : 'This talk record will be removed from the transcript.';

  const onSubmit = async (data: VoidFormationRecordFormValues) => {
    setErrorMessage(null);

    try {
      if (mode === 'program') {
        await voidProgramMutation.mutateAsync({
          organizationId,
          recordId,
          voidReason: data.voidReason.trim(),
        });
        onSuccessToast?.('Program record removed');
      } else {
        await voidTalkMutation.mutateAsync({
          organizationId,
          talkRecordId: recordId,
          voidReason: data.voidReason.trim(),
        });
        onSuccessToast?.('Talk record removed');
      }

      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      setErrorMessage(normalized.technicalMessage || normalized.message);
    }
  };

  return (
    <Modal
      open={isOpen}
      onClose={onClose}
      title={mode === 'program' ? 'Remove Formation Program Record' : 'Remove Talk Record'}
      description={`Remove record for "${recordTitle}".`}
      size="sm"
      closeOnBackdrop={false}
      footer={
        <div className="flex items-center justify-end gap-3">
          <Button type="button" variant="outline" onClick={onClose} disabled={isPending}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="void-formation-record-form"
            variant="danger"
            loading={isPending}
          >
            {mode === 'program' ? 'Remove Record' : 'Remove Talk'}
          </Button>
        </div>
      }
    >
      <form
        id="void-formation-record-form"
        onSubmit={handleSubmit(onSubmit)}
        className="space-y-4 py-1"
      >
        {errorMessage && (
          <Alert variant="danger">{errorMessage}</Alert>
        )}

        <div className="rounded-lg border border-danger-600/30 bg-danger-50/50 p-3 text-xs text-danger-700 leading-relaxed">
          {copyText}
        </div>

        <FormField
          label="Reason for removal"
          required
          error={errors.voidReason?.message}
          hint="Minimum 5 characters describing the correction reason"
        >
          <Textarea
            rows={3}
            placeholder="e.g. Recorded under wrong member, duplicate entry, incorrect course selection"
            {...register('voidReason')}
          />
        </FormField>
      </form>
    </Modal>
  );
}

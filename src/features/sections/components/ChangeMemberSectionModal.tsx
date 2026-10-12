import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Alert } from '../../../components/ui/Alert';
import { useChangeMemberSection } from '../queries';
import {
  changeSectionSchema,
  localToday,
  type ChangeSectionFormValues,
} from '../schemas';
import { getSectionErrorMessage } from '../error-message';
import { SECTION_OPTIONS } from '../types';

interface ChangeMemberSectionModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  currentSectionCode?: string | null;
  onSuccessToast?: (msg: string) => void;
}

export function ChangeMemberSectionModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  currentSectionCode,
  onSuccessToast,
}: ChangeMemberSectionModalProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const titleId = useId();
  const today = localToday();

  const changeSectionMutation = useChangeMemberSection();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<ChangeSectionFormValues>({
    resolver: zodResolver(changeSectionSchema),
    defaultValues: {
      sectionCode: currentSectionCode || '',
      effectiveFrom: today,
      reason: '',
    },
  });

  const handleClose = () => {
    setErrorMessage(null);
    reset({
      sectionCode: currentSectionCode || '',
      effectiveFrom: localToday(),
      reason: '',
    });
    onClose();
  };

  const onSubmit = async (data: ChangeSectionFormValues) => {
    setErrorMessage(null);
    try {
      await changeSectionMutation.mutateAsync({
        organizationId,
        memberId,
        sectionCode: data.sectionCode,
        effectiveFrom: data.effectiveFrom,
        reason: data.reason.trim(),
      });

      if (onSuccessToast) {
        onSuccessToast('Member section changed successfully.');
      }
      handleClose();
    } catch (err) {
      setErrorMessage(getSectionErrorMessage(err));
    }
  };

  return (
    <Modal
      open={isOpen}
      onClose={handleClose}
      title={<span id={titleId}>Change Section</span>}
      description="Select the new pastoral section for this member. Changing sections may affect couple pairings and leadership roles."
      footer={
        <div className="flex w-full justify-end gap-3">
          <Button
            type="button"
            variant="outline"
            onClick={handleClose}
            disabled={isSubmitting}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            form="change-section-form"
            loading={isSubmitting}
          >
            Change Section
          </Button>
        </div>
      }
    >
      <form
        id="change-section-form"
        onSubmit={handleSubmit(onSubmit)}
        className="space-y-4"
        noValidate
      >
        {errorMessage && (
          <Alert variant="danger" title="Unable to change section">
            {errorMessage}
          </Alert>
        )}

        <div>
          <label
            htmlFor="sectionCode"
            className="block text-xs font-medium text-ink"
          >
            New Section <span className="text-danger-600">*</span>
          </label>
          <select
            id="sectionCode"
            {...register('sectionCode')}
            disabled={isSubmitting}
            className="mt-1 block w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus disabled:bg-surface-muted"
          >
            <option value="">Select a section...</option>
            {SECTION_OPTIONS.map((sec) => (
              <option key={sec.code} value={sec.code}>
                {sec.name} {sec.code === currentSectionCode ? '(Current)' : ''}
              </option>
            ))}
          </select>
          {errors.sectionCode && (
            <p className="mt-1 text-xs text-danger-600">{errors.sectionCode.message}</p>
          )}
        </div>

        <div>
          <label
            htmlFor="effectiveFrom"
            className="block text-xs font-medium text-ink"
          >
            Effective Date <span className="text-danger-600">*</span>
          </label>
          <input
            type="date"
            id="effectiveFrom"
            max={today}
            {...register('effectiveFrom')}
            disabled={isSubmitting}
            className="mt-1 block w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus disabled:bg-surface-muted"
          />
          {errors.effectiveFrom && (
            <p className="mt-1 text-xs text-danger-600">{errors.effectiveFrom.message}</p>
          )}
        </div>

        <div>
          <label
            htmlFor="reason"
            className="block text-xs font-medium text-ink"
          >
            Reason for Change <span className="text-danger-600">*</span>
          </label>
          <textarea
            id="reason"
            rows={3}
            placeholder="Provide a reason (minimum 5 characters)..."
            {...register('reason')}
            disabled={isSubmitting}
            className="mt-1 block w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus disabled:bg-surface-muted"
          />
          {errors.reason && (
            <p className="mt-1 text-xs text-danger-600">{errors.reason.message}</p>
          )}
        </div>
      </form>
    </Modal>
  );
}

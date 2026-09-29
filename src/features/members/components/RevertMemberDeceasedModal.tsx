import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useRevertMemberDeceased } from '../api/revert-member-deceased';
import { normalizeError } from '../../../lib/supabase/errors';

const today = new Date().toISOString().split('T')[0];

const revertDeceasedSchema = z.object({
  effectiveFrom: z
    .string()
    .min(1, 'Effective date is required')
    .refine((d) => d <= today, { message: 'Correction date cannot be in the future' }),
  reason: z
    .string()
    .min(1, 'A correction reason is required')
    .max(500, 'Reason must not exceed 500 characters')
    .refine((val) => val.trim().length > 0, { message: 'Reason cannot be blank' }),
});

type RevertDeceasedFormValues = z.infer<typeof revertDeceasedSchema>;

interface RevertMemberDeceasedModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  displayName: string;
  onSuccessToast?: (msg: string) => void;
}

export function RevertMemberDeceasedModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  displayName,
  onSuccessToast,
}: RevertMemberDeceasedModalProps) {
  const titleId = useId();
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const revert = useRevertMemberDeceased();

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<RevertDeceasedFormValues>({
    resolver: zodResolver(revertDeceasedSchema),
    defaultValues: {
      effectiveFrom: today,
      reason: '',
    },
  });

  const onSubmit = async (data: RevertDeceasedFormValues) => {
    try {
      setErrorMessage(null);
      await revert.mutateAsync({
        organizationId,
        memberId,
        effectiveFrom: data.effectiveFrom,
        reason: data.reason,
      });
      onSuccessToast?.('Deceased status corrected. Status history has been preserved.');
      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '28000') {
        setErrorMessage('Authentication required: your session may have expired.');
      } else if (normalized.code === '42501') {
        setErrorMessage('Access denied: you do not have permission to revert deceased status.');
      } else if (normalized.code === '22023') {
        setErrorMessage(normalized.message || 'Validation error: please check the form and try again.');
      } else if (normalized.code === 'P0002') {
        setErrorMessage('Member not found or not accessible.');
      } else {
        setErrorMessage(normalized.message || 'Failed to correct deceased status.');
      }
    }
  };

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm overflow-y-auto"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-lg rounded-2xl border border-amber-900/60 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="space-y-1">
            <h2 id={titleId} className="text-lg font-semibold text-slate-100 flex items-center gap-2">
              <span className="text-amber-400">
                <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </span>
              Correct Deceased Status
            </h2>
            <p className="text-xs text-slate-400">
              Correction record for <span className="font-medium text-slate-200">{displayName}</span>
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            aria-label="Close"
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Error */}
        {errorMessage && (
          <div className="rounded-lg border border-red-500/40 bg-red-950/40 p-3 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        {/* Informational Callout */}
        <div className="rounded-xl border border-amber-800/40 bg-amber-950/20 p-4 space-y-2 text-xs">
          <p className="font-medium text-amber-200">
            This corrects an erroneous deceased designation.
          </p>
          <p className="text-slate-400 leading-relaxed">
            The original lifecycle history is preserved and a corrective status entry will be added. The previous
            membership status is automatically restored from history — no selection is needed.
          </p>
          <p className="text-slate-400 leading-relaxed">
            Record status, archive state, governance placement, family relationships, member number, and account
            access are not changed.
          </p>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* Effective Date */}
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-slate-300">
              Correction effective date <span className="text-red-400">*</span>
            </label>
            <input
              type="date"
              {...register('effectiveFrom')}
              max={today}
              disabled={isSubmitting}
              id="revert-deceased-effective-from"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
            />
            {errors.effectiveFrom && (
              <p className="text-xs text-red-400">{errors.effectiveFrom.message}</p>
            )}
          </div>

          {/* Correction Reason */}
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-slate-300">
              Correction reason <span className="text-red-400">*</span>
            </label>
            <textarea
              {...register('reason')}
              disabled={isSubmitting}
              rows={3}
              placeholder="Explain why this correction is being made (e.g. clerical error, incorrect reporting)"
              id="revert-deceased-reason-input"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none resize-none"
            />
            {errors.reason && (
              <p className="text-xs text-red-400">{errors.reason.message}</p>
            )}
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="rounded-lg px-4 py-2 text-xs font-medium text-slate-300 hover:bg-slate-800 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              id="submit-revert-deceased-button"
              className="inline-flex items-center gap-1.5 rounded-lg bg-amber-700 px-4 py-2 text-xs font-semibold text-white hover:bg-amber-600 disabled:opacity-50 transition-colors shadow-sm"
            >
              {isSubmitting ? (
                <>
                  <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                  </svg>
                  Correcting...
                </>
              ) : (
                'Correct Deceased Status'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

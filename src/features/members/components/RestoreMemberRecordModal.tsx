import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useRestoreMemberRecord } from '../api/restore-member-record';
import { normalizeError } from '../../../lib/supabase/errors';

const restoreMemberRecordSchema = z.object({
  reason: z
    .string()
    .min(1, 'A restore reason is required')
    .max(500, 'Reason must not exceed 500 characters')
    .refine((val) => val.trim().length > 0, { message: 'Reason cannot be blank' }),
});

type RestoreMemberRecordFormValues = z.infer<typeof restoreMemberRecordSchema>;

interface RestoreMemberRecordModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  displayName: string;
  onSuccessToast?: (msg: string) => void;
}

export function RestoreMemberRecordModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  displayName,
  onSuccessToast,
}: RestoreMemberRecordModalProps) {
  const titleId = useId();
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const restore = useRestoreMemberRecord();

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<RestoreMemberRecordFormValues>({
    resolver: zodResolver(restoreMemberRecordSchema),
    defaultValues: {
      reason: '',
    },
  });

  const onSubmit = async (data: RestoreMemberRecordFormValues) => {
    try {
      setErrorMessage(null);
      await restore.mutateAsync({
        organizationId,
        memberId,
        reason: data.reason,
      });
      onSuccessToast?.('Member record restored to active directory.');
      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '28000') {
        setErrorMessage('Authentication required: your session may have expired.');
      } else if (normalized.code === '42501') {
        setErrorMessage('Access denied: you do not have permission to restore member records.');
      } else if (normalized.code === '22023') {
        setErrorMessage(normalized.message || 'Validation error: please check the form and try again.');
      } else if (normalized.code === 'P0002') {
        setErrorMessage('Member not found or not accessible.');
      } else {
        setErrorMessage(normalized.message || 'Failed to restore member record.');
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
      <div className="relative w-full max-w-lg rounded-2xl border border-emerald-900/60 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="space-y-1">
            <h2 id={titleId} className="text-lg font-semibold text-slate-100 flex items-center gap-2">
              <span className="text-emerald-400">
                <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
              </span>
              Restore Archived Member Record
            </h2>
            <p className="text-xs text-slate-400">
              Restoring record for <span className="font-medium text-slate-200">{displayName}</span>
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
        <div className="rounded-xl border border-emerald-800/40 bg-emerald-950/20 p-4 space-y-2 text-xs">
          <p className="font-medium text-emerald-200">
            This returns the record to active directory visibility.
          </p>
          <p className="text-slate-400 leading-relaxed">
            Historical archive and restore actions remain preserved in the audit trail. Membership status,
            status history, governance placement, family relationships, member number, and account access
            are not changed.
          </p>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* Restore Reason */}
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-slate-300">
              Restore reason <span className="text-red-400">*</span>
            </label>
            <textarea
              {...register('reason')}
              disabled={isSubmitting}
              rows={3}
              placeholder="Explain why this record is being returned to active status"
              id="restore-record-reason-input"
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
              id="submit-restore-record-button"
              className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-700 px-4 py-2 text-xs font-semibold text-white hover:bg-emerald-600 disabled:opacity-50 transition-colors shadow-sm"
            >
              {isSubmitting ? (
                <>
                  <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                  </svg>
                  Restoring...
                </>
              ) : (
                'Restore Record'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys, type GovernancePlacement } from '../queries';
import { archiveMemberRecord } from '../api/archive-member-record';
import { normalizeError } from '../../../lib/supabase/errors';

const archiveMemberRecordSchema = z.object({
  reason: z
    .string()
    .min(1, 'An archive reason is required')
    .max(500, 'Reason must not exceed 500 characters')
    .refine((val) => val.trim().length > 0, {
      message: 'Reason cannot be blank',
    }),
});

type ArchiveMemberRecordFormValues = z.infer<typeof archiveMemberRecordSchema>;

interface ArchiveMemberRecordModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  displayName: string;
  governancePlacement: GovernancePlacement | null;
  onSuccessToast?: (msg: string) => void;
}

export function ArchiveMemberRecordModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  displayName,
  governancePlacement,
  onSuccessToast,
}: ArchiveMemberRecordModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<ArchiveMemberRecordFormValues>({
    resolver: zodResolver(archiveMemberRecordSchema),
    defaultValues: {
      reason: '',
    },
  });

  const onSubmit = async (data: ArchiveMemberRecordFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await archiveMemberRecord({
        organizationId,
        memberId,
        reason: data.reason,
      });

      // Invalidate profile query to transition to archived banner, and lists to remove from active directory
      await queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, memberId),
      });
      await queryClient.invalidateQueries({
        queryKey: memberKeys.lists(),
      });

      onSuccessToast?.('Member record archived.');
      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '22023') {
        setErrorMessage(normalized.message || 'Validation error: please enter a valid archive reason.');
      } else if (normalized.code === '42501') {
        setErrorMessage('Access denied: you do not have permission to archive member records.');
      } else {
        setErrorMessage(normalized.message || 'Failed to archive member record.');
      }
    } finally {
      setIsSubmitting(false);
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
      <div className="relative w-full max-w-lg rounded-2xl border border-rose-900/60 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="space-y-1">
            <h2 id={titleId} className="text-lg font-semibold text-slate-100 flex items-center gap-2">
              <span className="text-rose-400">
                <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
                </svg>
              </span>
              Archive Member Record
            </h2>
            <p className="text-xs text-slate-400">
              Archiving record for <span className="font-medium text-slate-200">{displayName}</span>
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

        {/* Error message */}
        {errorMessage && (
          <div className="rounded-lg border border-red-500/40 bg-red-950/40 p-3 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        {/* Informational Callout */}
        <div className="rounded-xl border border-slate-700/80 bg-slate-800/60 p-4 space-y-2 text-xs text-slate-300">
          <p className="font-medium text-slate-200">
            Archiving hides this member from standard active directory searches while preserving the complete historical record.
          </p>
          <p className="text-slate-400 leading-relaxed">
            Membership status, family relationships, member number, assignments, and account access are not automatically changed.
          </p>
        </div>

        {/* Active Governance Assignment Warning */}
        {governancePlacement && (
          <div className="rounded-xl border border-amber-800/50 bg-amber-950/20 p-3.5 flex items-start gap-2.5 text-xs text-amber-300/90">
            <svg className="h-4 w-4 shrink-0 text-amber-400 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <div>
              <span className="font-semibold text-amber-200">Active Governance Assignment:</span>{' '}
              This member currently has an active placement ({governancePlacement.node_name}). Archiving the record does not end that assignment.
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* Reason */}
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-slate-300">
              Administrative reason <span className="text-red-400">*</span>
            </label>
            <textarea
              {...register('reason')}
              disabled={isSubmitting}
              rows={3}
              placeholder="Administrative reason for archiving this record"
              id="archive-reason-input"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none resize-none"
            />
            {errors.reason && (
              <p className="text-xs text-red-400">{errors.reason.message}</p>
            )}
          </div>

          {/* Action buttons */}
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
              id="submit-archive-record-button"
              className="inline-flex items-center gap-1.5 rounded-lg bg-rose-700 px-4 py-2 text-xs font-semibold text-white hover:bg-rose-600 disabled:opacity-50 transition-colors shadow-sm"
            >
              {isSubmitting ? (
                <>
                  <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                  </svg>
                  Archiving...
                </>
              ) : (
                'Archive Record'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

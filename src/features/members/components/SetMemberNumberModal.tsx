import { useState, useEffect, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useSetMemberNumber } from '../api/set-member-number';
import { normalizeError } from '../../../lib/supabase/errors';

export interface SetMemberNumberModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  currentMemberNumber?: string | null;
  onSuccessToast?: (msg: string) => void;
}

export function SetMemberNumberModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  currentMemberNumber,
  onSuccessToast,
}: SetMemberNumberModalProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const titleId = useId();

  const hasExistingNumber = Boolean(currentMemberNumber && currentMemberNumber.trim().length > 0);

  const setMemberNumberSchema = z.object({
    memberNumber: z
      .string()
      .trim()
      .min(1, 'Member number is required')
      .refine((val) => {
        const clean = val.replace(/\s+/g, '');
        return /^NY\d{5}$/i.test(clean);
      }, 'Use NY followed by 5 digits, e.g. NY10560'),
    reason: hasExistingNumber
      ? z
          .string()
          .trim()
          .min(5, 'A reason of at least 5 characters is required to change a member number')
      : z.string().trim().optional(),
  });

  type FormValues = z.infer<typeof setMemberNumberSchema>;

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(setMemberNumberSchema),
    defaultValues: {
      memberNumber: currentMemberNumber ?? '',
      reason: '',
    },
  });

  useEffect(() => {
    if (isOpen) {
      reset({
        memberNumber: currentMemberNumber ?? '',
        reason: '',
      });
      setErrorMessage(null);
    }
  }, [isOpen, currentMemberNumber, reset]);

  const { mutateAsync: setNumberMutation, isPending } = useSetMemberNumber();

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setErrorMessage(null);
    onClose();
  };

  const onSubmit = async (data: FormValues) => {
    setErrorMessage(null);
    try {
      await setNumberMutation({
        organizationId,
        memberId,
        memberNumber: data.memberNumber.trim(),
        reason: data.reason || null,
      });

      onSuccessToast?.('Member number saved.');
      handleClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      setErrorMessage(normalized.message || 'An error occurred while saving the member number.');
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm animate-fade-in"
    >
      <div className="relative w-full max-w-md rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-4">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-100">
              {hasExistingNumber ? 'Change Member Number' : 'Set Member Number'}
            </h2>
            <p className="mt-0.5 text-xs text-slate-400">
              {hasExistingNumber
                ? 'Update the Finance envelope number for this member.'
                : 'Assign the Finance envelope number for this member.'}
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            disabled={isPending}
            aria-label="Close dialog"
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Server Error Message */}
        {errorMessage && (
          <div className="rounded-xl border border-red-700 bg-red-900/30 p-3 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* Member Number input */}
          <div className="space-y-1.5">
            <label htmlFor="modal-memberNumber" className="block text-xs font-semibold uppercase tracking-wider text-slate-300">
              Member number (from Finance) <span className="text-rose-400">*</span>
            </label>
            <input
              id="modal-memberNumber"
              type="text"
              placeholder="e.g. NY10560"
              {...register('memberNumber')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 font-mono"
            />
            <p className="text-xs text-slate-400">
              Use the envelope number assigned by the Finance Group (NY followed by 5 digits).
            </p>
            {errors.memberNumber && (
              <p className="text-xs text-rose-400">{errors.memberNumber.message}</p>
            )}
          </div>

          {/* Reason input (required only when hasExistingNumber) */}
          <div className="space-y-1.5">
            <label htmlFor="modal-reason" className="block text-xs font-semibold uppercase tracking-wider text-slate-300">
              Reason {hasExistingNumber ? <span className="text-rose-400">*</span> : <span className="text-[11px] font-normal lowercase text-slate-500">(optional)</span>}
            </label>
            <textarea
              id="modal-reason"
              rows={3}
              placeholder={hasExistingNumber ? 'Administrative reason for changing the member number (min 5 characters)' : 'Optional administrative reason'}
              {...register('reason')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-200 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.reason && (
              <p className="text-xs text-rose-400">{errors.reason.message}</p>
            )}
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={handleClose}
              disabled={isPending}
              className="rounded-lg border border-slate-700 bg-slate-800/80 px-4 py-2 text-xs font-semibold text-slate-300 hover:bg-slate-700 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              id="save-member-number-button"
              disabled={isPending}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-semibold text-white shadow-sm hover:bg-indigo-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isPending ? 'Saving...' : 'Save Member Number'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

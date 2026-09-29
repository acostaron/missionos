import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys } from '../queries';
import { recordMemberDeceased } from '../api/record-member-deceased';
import {
  recordMemberDeceasedSchema,
  type RecordMemberDeceasedFormValues,
} from './record-member-deceased-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface RecordMemberDeceasedModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  displayName: string;
  onSuccessToast?: (msg: string) => void;
}

export function RecordMemberDeceasedModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  displayName,
  onSuccessToast,
}: RecordMemberDeceasedModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const today = new Date().toISOString().split('T')[0];
  const currentMonth = today.slice(0, 7);
  const currentYear = today.slice(0, 4);

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors },
  } = useForm<RecordMemberDeceasedFormValues>({
    resolver: zodResolver(recordMemberDeceasedSchema),
    defaultValues: {
      deceasedOnPrecision: 'unknown',
      exactDate: today,
      monthAndYear: currentMonth,
      yearOnly: currentYear,
      effectiveFrom: today,
      reason: '',
    },
  });

  const precision = watch('deceasedOnPrecision');

  const onSubmit = async (data: RecordMemberDeceasedFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      let deceasedOn: string | null = null;
      if (data.deceasedOnPrecision === 'exact') {
        deceasedOn = data.exactDate ?? null;
      } else if (data.deceasedOnPrecision === 'month_and_year') {
        // Canonical date representation: 1st of month
        deceasedOn = data.monthAndYear ? `${data.monthAndYear}-01` : null;
      } else if (data.deceasedOnPrecision === 'year_only') {
        // Canonical date representation: Jan 1st of year
        deceasedOn = data.yearOnly ? `${data.yearOnly}-01-01` : null;
      } else {
        deceasedOn = null;
      }

      await recordMemberDeceased({
        organizationId,
        memberId,
        deceasedOn,
        deceasedOnPrecision: data.deceasedOnPrecision,
        effectiveFrom: data.effectiveFrom,
        reason: data.reason,
      });

      // Invalidate profile, lists, and status history
      await queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, memberId),
      });
      await queryClient.invalidateQueries({
        queryKey: memberKeys.lists(),
      });
      await queryClient.invalidateQueries({
        queryKey: memberKeys.statusHistory(organizationId, memberId),
      });

      onSuccessToast?.('Member recorded as deceased.');
      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '22023') {
        setErrorMessage(normalized.message || 'Validation error: please check the dates and precision.');
      } else if (normalized.code === '42501') {
        setErrorMessage('Access denied: you do not have permission to record deceased members.');
      } else {
        setErrorMessage(normalized.message || 'Failed to record member as deceased.');
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
      <div className="relative w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="space-y-1">
            <h2 id={titleId} className="text-lg font-semibold text-slate-100 flex items-center gap-2">
              <span className="text-amber-400">
                <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </span>
              Record Member as Deceased
            </h2>
            <p className="text-xs text-slate-400">
              Recording passing for <span className="font-medium text-slate-200">{displayName}</span>
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
            This records the member as deceased and transitions their membership status to Deceased.
          </p>
          <p className="text-slate-400 leading-relaxed">
            Historical records, family relationships, member number, and existing records are preserved.
            Governance and account access are managed separately.
          </p>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* Date Precision */}
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-slate-300">
              Date precision <span className="text-red-400">*</span>
            </label>
            <select
              {...register('deceasedOnPrecision')}
              disabled={isSubmitting}
              id="deceased-precision-select"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
            >
              <option value="exact">Exact date</option>
              <option value="month_and_year">Month and year</option>
              <option value="year_only">Year only</option>
              <option value="unknown">Unknown</option>
            </select>
          </div>

          {/* Precision-conditional inputs */}
          {precision === 'exact' && (
            <div className="space-y-1.5">
              <label className="block text-xs font-medium text-slate-300">
                Date of death <span className="text-red-400">*</span>
              </label>
              <input
                type="date"
                max={today}
                {...register('exactDate')}
                disabled={isSubmitting}
                id="deceased-exact-date-input"
                className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
              />
              {errors.exactDate && (
                <p className="text-xs text-red-400">{errors.exactDate.message}</p>
              )}
            </div>
          )}

          {precision === 'month_and_year' && (
            <div className="space-y-1.5">
              <label className="block text-xs font-medium text-slate-300">
                Month and year of death <span className="text-red-400">*</span>
              </label>
              <input
                type="month"
                max={currentMonth}
                {...register('monthAndYear')}
                disabled={isSubmitting}
                id="deceased-month-year-input"
                className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
              />
              {errors.monthAndYear && (
                <p className="text-xs text-red-400">{errors.monthAndYear.message}</p>
              )}
            </div>
          )}

          {precision === 'year_only' && (
            <div className="space-y-1.5">
              <label className="block text-xs font-medium text-slate-300">
                Year of death <span className="text-red-400">*</span>
              </label>
              <input
                type="number"
                min="1900"
                max={currentYear}
                placeholder="YYYY"
                {...register('yearOnly')}
                disabled={isSubmitting}
                id="deceased-year-only-input"
                className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
              />
              {errors.yearOnly && (
                <p className="text-xs text-red-400">{errors.yearOnly.message}</p>
              )}
            </div>
          )}

          {precision === 'unknown' && (
            <p className="text-xs text-slate-400 italic bg-slate-800/40 p-2.5 rounded-lg border border-slate-700/50">
              Date of death will be recorded as unknown.
            </p>
          )}

          {/* Membership Status Effective Date */}
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-slate-300">
              Membership status effective date <span className="text-red-400">*</span>
            </label>
            <input
              type="date"
              max={today}
              {...register('effectiveFrom')}
              disabled={isSubmitting}
              id="deceased-effective-from-input"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
            />
            <p className="text-[11px] text-slate-400">
              Date this membership status change takes effect in MissionOS.
            </p>
            {errors.effectiveFrom && (
              <p className="text-xs text-red-400">{errors.effectiveFrom.message}</p>
            )}
          </div>

          {/* Administrative Note */}
          <div className="space-y-1.5">
            <label className="block text-xs font-medium text-slate-300">
              Administrative note <span className="text-slate-500">(optional)</span>
            </label>
            <textarea
              {...register('reason')}
              disabled={isSubmitting}
              rows={3}
              placeholder="Optional administrative note (confidential pastoral and medical details should not be entered)"
              id="deceased-reason-input"
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
              id="submit-record-deceased-button"
              className="inline-flex items-center gap-1.5 rounded-lg bg-amber-600 px-4 py-2 text-xs font-semibold text-white hover:bg-amber-500 disabled:opacity-50 transition-colors shadow-sm"
            >
              {isSubmitting ? (
                <>
                  <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                  </svg>
                  Recording...
                </>
              ) : (
                'Record as Deceased'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

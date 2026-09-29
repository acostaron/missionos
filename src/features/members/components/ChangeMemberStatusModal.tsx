import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys, type MemberStatus } from '../queries';
import { useMemberStatuses } from '../api/get-member-statuses';
import { changeMemberMembershipStatus } from '../api/change-member-membership-status';
import {
  changeMemberStatusSchema,
  type ChangeMemberStatusFormValues,
} from './member-status-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface ChangeMemberStatusModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  currentStatus: MemberStatus | null;
  onSuccessToast?: (msg: string) => void;
}

export function ChangeMemberStatusModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  currentStatus,
  onSuccessToast,
}: ChangeMemberStatusModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const today = new Date().toISOString().split('T')[0];

  // Fetch active selectable membership statuses (excluding deceased and archived)
  const {
    data: statuses,
    isLoading: isStatusesLoading,
    error: statusesError,
  } = useMemberStatuses(organizationId, isOpen);

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors },
  } = useForm<ChangeMemberStatusFormValues>({
    resolver: zodResolver(changeMemberStatusSchema),
    defaultValues: {
      targetStatusId: '',
      effectiveFrom: today,
      reason: '',
    },
  });

  const selectedTargetStatusId = watch('targetStatusId');
  const isSameStatus = !!(
    currentStatus?.id &&
    selectedTargetStatusId &&
    selectedTargetStatusId === currentStatus.id
  );

  // Selected status details for informational notice
  const selectedStatus = statuses?.find((s) => s.status_id === selectedTargetStatusId);
  const isTerminalLike =
    selectedStatus?.code === 'transferred' || selectedStatus?.code === 'resigned';

  const onSubmit = async (data: ChangeMemberStatusFormValues) => {
    if (isSameStatus) return;

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await changeMemberMembershipStatus({
        organizationId,
        memberId,
        targetStatusId: data.targetStatusId,
        effectiveFrom: data.effectiveFrom,
        reason: data.reason,
      });

      // Invalidate profile query to refresh status badge and lists query for directory filters
      await queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, memberId),
      });
      await queryClient.invalidateQueries({
        queryKey: memberKeys.lists(),
      });
      await queryClient.invalidateQueries({
        queryKey: memberKeys.statusHistory(organizationId, memberId),
      });

      onSuccessToast?.('Membership status updated.');
      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '22023') {
        if (normalized.message.includes('Member already has')) {
          setErrorMessage('Member already has this membership status.');
        } else if (normalized.message.includes('cannot precede current status start date')) {
          setErrorMessage(
            "The effective date cannot be earlier than the member's current status record."
          );
        } else {
          setErrorMessage(normalized.message);
        }
      } else if (normalized.code === '42501') {
        setErrorMessage(
          'Access denied: You do not have permission or governance scope to change membership status for this member.'
        );
      } else {
        setErrorMessage(normalized.message || 'Failed to update membership status.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm animate-fade-in"
    >
      <div className="relative w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-4">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-100">
              Change Membership Status
            </h2>
            <p className="mt-0.5 text-xs text-slate-400">
              Transition the member&apos;s administrative standing within the organization.
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            aria-label="Close dialog"
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
          >
            <svg
              className="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth={2}
            >
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Global Error Banner */}
        {errorMessage && (
          <div className="rounded-xl border border-red-700 bg-red-900/30 p-3 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        {/* Informational Notice */}
        <div className="rounded-lg border border-indigo-900/40 bg-indigo-950/30 p-3 text-xs text-indigo-300">
          Membership status changes are recorded in the member&apos;s lifecycle history.
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
          {/* Current Status Display */}
          <div className="rounded-xl border border-slate-700/60 bg-slate-800/40 p-3.5">
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">
              Current Status
            </p>
            <div className="mt-1.5 flex items-center justify-between">
              {currentStatus ? (
                <div className="flex items-center gap-3">
                  <span
                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                      currentStatus.is_active_membership
                        ? 'bg-emerald-950/80 text-emerald-300 border border-emerald-800/60'
                        : 'bg-slate-800 text-slate-300 border border-slate-700'
                    }`}
                  >
                    {currentStatus.name}
                  </span>
                  <span className="text-xs text-slate-400 capitalize">
                    Category: {currentStatus.status_category.replace('_', ' ')}
                  </span>
                </div>
              ) : (
                <p className="text-sm font-medium text-slate-400 italic">None</p>
              )}
            </div>
          </div>

          {/* New Status Selection */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400">
              New Status <span className="text-rose-400">*</span>
            </label>

            {isStatusesLoading && (
              <div className="space-y-2">
                <div className="h-12 animate-pulse rounded-lg bg-slate-800" />
                <div className="h-20 animate-pulse rounded-lg bg-slate-800" />
              </div>
            )}

            {statusesError && (
              <div className="rounded-lg border border-red-700 bg-red-900/20 p-3 text-xs text-red-300">
                Failed to load membership statuses. Please try again.
              </div>
            )}

            {!isStatusesLoading && (
              <div className="max-h-60 overflow-y-auto space-y-2 pr-1 rounded-xl border border-slate-700/60 p-2 bg-slate-950/40">
                {statuses?.map((st) => {
                  const isCurrent = currentStatus?.id === st.status_id;
                  const isSelected = selectedTargetStatusId === st.status_id;

                  return (
                    <label
                      key={st.status_id}
                      className={`flex flex-col rounded-lg border p-3 cursor-pointer transition-colors ${
                        isSelected
                          ? 'border-indigo-500 bg-indigo-950/30 text-indigo-100'
                          : 'border-slate-800 bg-slate-900/60 text-slate-300 hover:border-slate-700 hover:bg-slate-800/50'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2.5">
                          <input
                            type="radio"
                            value={st.status_id}
                            {...register('targetStatusId')}
                            className="h-4 w-4 border-slate-700 bg-slate-800 text-indigo-600 focus:ring-indigo-500 focus:ring-offset-slate-900"
                          />
                          <span className="font-semibold text-sm text-slate-100">{st.name}</span>
                        </div>
                        {isCurrent && (
                          <span className="text-[11px] font-medium text-slate-400 bg-slate-800 px-2 py-0.5 rounded border border-slate-700">
                            Current
                          </span>
                        )}
                      </div>
                      {st.description && (
                        <p className="mt-1 ml-6.5 text-xs text-slate-400">{st.description}</p>
                      )}
                    </label>
                  );
                })}
              </div>
            )}

            {errors.targetStatusId && (
              <p className="text-xs text-rose-400">{errors.targetStatusId.message}</p>
            )}

            {isSameStatus && (
              <p className="text-xs text-amber-400/90 font-medium">
                This member already has this membership status.
              </p>
            )}
          </div>

          {/* Terminal-like notice for Transferred/Resigned */}
          {isTerminalLike && (
            <div className="rounded-lg border border-amber-800/40 bg-amber-950/20 p-3 text-xs text-amber-300">
              This changes the member&apos;s membership status only. Other assignments and account
              access are managed separately.
            </div>
          )}

          {/* Effective Date */}
          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400">
              Effective Date <span className="text-rose-400">*</span>
            </label>
            <input
              type="date"
              max={today}
              {...register('effectiveFrom')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-200 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.effectiveFrom && (
              <p className="text-xs text-rose-400">{errors.effectiveFrom.message}</p>
            )}
          </div>

          {/* Reason */}
          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400">
              Reason for status change{' '}
              <span className="text-[11px] font-normal lowercase text-slate-500">(optional)</span>
            </label>
            <textarea
              rows={2}
              placeholder="Optional administrative reason"
              {...register('reason')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-200 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.reason && <p className="text-xs text-rose-400">{errors.reason.message}</p>}
          </div>

          {/* Footer Actions */}
          <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="rounded-lg border border-slate-700 bg-slate-800/80 px-4 py-2 text-xs font-semibold text-slate-300 hover:bg-slate-700 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              id="save-membership-status-button"
              disabled={isSubmitting || isSameStatus || !selectedTargetStatusId}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-semibold text-white shadow-sm hover:bg-indigo-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

import { useState, useId, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { endHouseholdMembership } from '../api/end-household-membership';
import {
  endHouseholdMembershipSchema,
  type EndHouseholdMembershipFormValues,
} from '../schemas';
import type { EndHouseholdMembershipBlockedResult } from '../types';
import { normalizeError } from '../../../lib/supabase/errors';

interface EndHouseholdMembershipModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  memberName: string;
  currentHouseholdId: string;
  currentHouseholdName: string;
  onSuccessToast?: (msg: string) => void;
}

export function EndHouseholdMembershipModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  memberName,
  currentHouseholdId,
  currentHouseholdName,
  onSuccessToast,
}: EndHouseholdMembershipModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [blocker, setBlocker] = useState<EndHouseholdMembershipBlockedResult | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const todayStr = new Date().toISOString().split('T')[0];

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    reset,
    formState: { errors },
  } = useForm<EndHouseholdMembershipFormValues>({
    resolver: zodResolver(endHouseholdMembershipSchema),
    defaultValues: {
      member_id: memberId,
      effective_to: todayStr,
      reason: '',
    },
  });

  const effectiveTo = watch('effective_to');

  useEffect(() => {
    if (isOpen) {
      setValue('member_id', memberId);
    }
  }, [isOpen, memberId, setValue]);

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setBlocker(null);
    setErrorMessage(null);
    onClose();
  };

  const onSubmit = async (values: EndHouseholdMembershipFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      setBlocker(null);

      const result = await endHouseholdMembership(organizationId, {
        member_id: values.member_id,
        effective_to: values.effective_to,
        reason: values.reason,
      });

      if (result.status === 'blocked') {
        setBlocker(result);
        return;
      }

      // Success
      queryClient.invalidateQueries({ queryKey: householdKeys.profile(organizationId, currentHouseholdId) });
      queryClient.invalidateQueries({ queryKey: householdKeys.lists() });
      queryClient.invalidateQueries({ queryKey: householdKeys.membersWithoutHousehold(organizationId) });
      queryClient.invalidateQueries({ queryKey: householdKeys.member(organizationId, values.member_id) });

      onSuccessToast?.(
        `Pastoral household assignment on ${currentHouseholdName} ended for ${memberName}. History preserved.`
      );
      handleClose();
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm overflow-y-auto animate-in fade-in duration-150"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-md rounded-xl border border-slate-700 bg-slate-900 shadow-2xl p-6 text-slate-100 my-8">
        {/* Header */}
        <div className="flex items-center justify-between pb-4 border-b border-slate-800">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-100">
              End Household Assignment
            </h2>
            <p className="text-xs text-slate-400 mt-0.5">
              Conclude active placement without transferring to a new household.
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
            aria-label="Close"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Member and Household Info */}
        <div className="mt-4 p-3 bg-slate-800/60 border border-slate-700/60 rounded-lg text-xs space-y-1.5">
          <div className="flex justify-between">
            <span className="text-slate-400">Member:</span>
            <span className="font-semibold text-slate-200">{memberName}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-slate-400">Current Household:</span>
            <span className="font-semibold text-slate-200">{currentHouseholdName}</span>
          </div>
        </div>

        {/* Error message */}
        {errorMessage && (
          <div className="mt-4 p-3 bg-rose-950/40 border border-rose-800/80 rounded-lg text-rose-200 text-xs">
            {errorMessage}
          </div>
        )}

        {/* Blocker alert */}
        {blocker && (
          <div className="mt-4 p-3.5 bg-amber-950/40 border border-amber-800/80 rounded-lg text-amber-200 text-xs space-y-2">
            <p className="font-semibold flex items-center gap-1.5 text-amber-300">
              <svg className="h-4 w-4 text-amber-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              Ending Blocked
            </p>
            <p className="text-slate-300 leading-relaxed">{blocker.message}</p>
            {blocker.blocker_type === 'active_household_leadership' && (
              <p className="text-[11px] text-amber-300/80">
                Action required: Conclude or reassign the member's pastoral leadership appointment before ending their household membership.
              </p>
            )}
            {blocker.blocker_type === 'leadership_role_inconsistency' && (
              <p className="text-[11px] text-amber-300/80">
                Action required: Resolve this member's formal leadership appointment data before ending their household membership.
              </p>
            )}
            <div className="pt-2 flex justify-end">
              <button
                type="button"
                onClick={() => setBlocker(null)}
                className="px-3 py-1.5 text-xs text-slate-300 hover:text-white"
              >
                Close
              </button>
            </div>
          </div>
        )}

        {!blocker && (
          <form onSubmit={handleSubmit(onSubmit)} className="mt-4 space-y-4 text-xs">
            {/* Effective End Date */}
            <div>
              <label htmlFor="end_effective_to" className="block font-medium text-slate-300 mb-1">
                Effective End Date <span className="text-rose-400">*</span>
              </label>
              <input
                type="date"
                id="end_effective_to"
                max={todayStr}
                value={effectiveTo}
                onChange={(e) => setValue('effective_to', e.target.value)}
                className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none"
              />
              {errors.effective_to && (
                <p className="text-rose-400 text-[11px] mt-1">{errors.effective_to.message}</p>
              )}
            </div>

            {/* Ending Reason */}
            <div>
              <label htmlFor="end_reason" className="block font-medium text-slate-300 mb-1">
                Reason for Ending Assignment <span className="text-rose-400">*</span>
              </label>
              <textarea
                id="end_reason"
                rows={3}
                {...register('reason')}
                placeholder="Explain why the member is leaving this household without transfer…"
                className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none"
              />
              {errors.reason && (
                <p className="text-rose-400 text-[11px] mt-1">{errors.reason.message}</p>
              )}
            </div>

            {/* Warning Callout */}
            <div className="p-3 rounded-lg bg-amber-950/20 border border-amber-900/40 text-[11px] text-amber-300/90 leading-relaxed">
              This removes the member's current pastoral household assignment but preserves the assignment history. The member will appear in the directory of members without a household until assigned to another household.
            </div>

            {/* Modal Actions */}
            <div className="pt-3 border-t border-slate-800 flex justify-end gap-2.5">
              <button
                type="button"
                onClick={handleClose}
                disabled={isSubmitting}
                className="px-4 py-2 text-xs font-semibold text-slate-300 hover:text-slate-100 transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isSubmitting}
                className="px-4 py-2 text-xs font-semibold bg-rose-600 hover:bg-rose-500 disabled:opacity-50 text-white rounded-lg shadow-sm transition-colors"
              >
                {isSubmitting ? 'Ending…' : 'End Assignment'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

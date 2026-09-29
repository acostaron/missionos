import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { familyKeys } from '../queries';
import { endFamilyMembership } from '../api/end-family-membership';
import type { FamilyProfileMember } from '../types';
import {
  endFamilyMembershipSchema,
  type EndFamilyMembershipFormValues,
} from '../schemas/end-family-membership-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface EndFamilyMembershipModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  familyId: string;
  member: FamilyProfileMember | null;
}

export function EndFamilyMembershipModal({
  isOpen,
  onClose,
  organizationId,
  familyId,
  member,
}: EndFamilyMembershipModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const todayStr = new Date().toISOString().split('T')[0];

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<EndFamilyMembershipFormValues>({
    resolver: zodResolver(endFamilyMembershipSchema),
    defaultValues: {
      effective_to: todayStr,
      reason: '',
    },
  });

  const handleClose = () => {
    reset();
    setErrorMessage(null);
    onClose();
  };

  const executeEnd = async (data: EndFamilyMembershipFormValues) => {
    if (!member) return;

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await endFamilyMembership({
        organizationId,
        familyMemberId: member.family_member_id,
        effectiveTo: data.effective_to,
        reason: data.reason,
      });

      // Invalidate family profile & member-family summaries
      await queryClient.invalidateQueries({
        queryKey: familyKeys.profile(organizationId, familyId),
      });
      await queryClient.invalidateQueries({
        queryKey: ['members', 'families'],
      });

      handleClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage('You do not have permission to end family memberships.');
      } else if (normalized.code === '22023') {
        const msg = normalized.technicalMessage || '';
        if (msg.includes('already ended')) {
          setErrorMessage('This family membership is already ended.');
        } else if (msg.includes('status')) {
          setErrorMessage('Membership changes are not allowed for this family in its current status.');
        } else if (msg.includes('earlier than')) {
          setErrorMessage('Effective end date cannot be earlier than the membership start date.');
        } else {
          setErrorMessage(msg || 'Invalid end date or membership status.');
        }
      } else if (normalized.code === '23502') {
        setErrorMessage('An end membership reason is required.');
      } else if (normalized.code === 'P0002') {
        setErrorMessage('Family membership was not found or is not accessible.');
      } else {
        setErrorMessage(normalized.message || 'Failed to end family membership.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isOpen || !member) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-md bg-white dark:bg-slate-900 rounded-xl shadow-2xl border border-slate-200 dark:border-slate-800 overflow-hidden flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 dark:border-slate-800 flex items-center justify-between">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-900 dark:text-white">
              End Family Membership
            </h2>
            <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
              Member: <span className="font-semibold text-slate-700 dark:text-slate-300">{member.display_name}</span>
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="p-1 rounded-lg text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
            aria-label="Close"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Content Body */}
        <div className="p-6 space-y-4">
          {/* Explanation Callout */}
          <div className="p-3 bg-amber-50/80 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900/50 rounded-lg text-xs text-amber-850 dark:text-amber-300 leading-relaxed">
            <span className="font-semibold">Important:</span> This ends the member&apos;s current family membership. It does not delete the member or the family and does not remove historical relationships.
          </div>

          {/* Error Banner */}
          {errorMessage && (
            <div className="p-3 bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-900/50 rounded-lg text-sm text-red-700 dark:text-red-300 flex items-start gap-2">
              <svg className="w-4 h-4 mt-0.5 shrink-0 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>{errorMessage}</span>
            </div>
          )}

          {/* Form */}
          <form id="end-family-membership-form" onSubmit={handleSubmit(executeEnd)} className="space-y-4">
            {/* Effective To Date */}
            <div>
              <label htmlFor="end-effective-to-input" className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1">
                Effective End Date <span className="text-red-500">*</span>
              </label>
              <input
                id="end-effective-to-input"
                type="date"
                max={todayStr}
                {...register('effective_to')}
                className="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-700 rounded-lg text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
              {errors.effective_to && (
                <p className="text-xs text-red-500 mt-1">{errors.effective_to.message}</p>
              )}
            </div>

            {/* Reason */}
            <div>
              <label htmlFor="end-reason-input" className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1">
                Reason for Ending Membership <span className="text-red-500">*</span>
              </label>
              <textarea
                id="end-reason-input"
                rows={3}
                placeholder="E.g., Independent household established, moved away, custody change..."
                {...register('reason')}
                className="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-700 rounded-lg text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
              {errors.reason && (
                <p className="text-xs text-red-500 mt-1">{errors.reason.message}</p>
              )}
            </div>
          </form>
        </div>

        {/* Footer Actions */}
        <div className="px-6 py-4 border-t border-slate-100 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-900/50 flex items-center justify-end gap-3">
          <button
            type="button"
            onClick={handleClose}
            disabled={isSubmitting}
            className="px-4 py-2 text-xs font-medium text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-lg transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            form="end-family-membership-form"
            disabled={isSubmitting}
            className="px-4 py-2 text-xs font-medium bg-amber-600 hover:bg-amber-700 text-white rounded-lg shadow-sm transition-colors disabled:opacity-50 flex items-center gap-1.5"
          >
            {isSubmitting ? (
              <>
                <svg className="animate-spin w-3.5 h-3.5" viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
                <span>Ending...</span>
              </>
            ) : (
              'End Membership'
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { archiveHousehold } from '../api/archive-household';
import { archiveHouseholdSchema, type ArchiveHouseholdFormValues } from '../schemas';
import type { HouseholdProfileData } from '../types';
import { normalizeError } from '../../../lib/supabase/errors';

interface ArchiveHouseholdModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdData: HouseholdProfileData;
  onSuccessToast?: (msg: string) => void;
}

export function ArchiveHouseholdModal({
  isOpen,
  onClose,
  organizationId,
  householdData,
  onSuccessToast,
}: ArchiveHouseholdModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [blocker, setBlocker] = useState<{
    type: 'active_household_memberships' | 'active_leadership_assignments';
    message: string;
    count: number;
  } | null>(null);

  const titleId = useId();
  const { household, counts, leaders } = householdData;

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<ArchiveHouseholdFormValues>({
    resolver: zodResolver(archiveHouseholdSchema),
    defaultValues: {
      reason: '',
    },
  });

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setErrorMessage(null);
    setBlocker(null);
    onClose();
  };

  const onSubmit = async (data: ArchiveHouseholdFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      setBlocker(null);

      const result = await archiveHousehold(
        organizationId,
        household.id,
        data.reason
      );

      if (result.status === 'blocked') {
        setBlocker({
          type: result.blocker_type,
          message: result.message,
          count:
            result.blocker_type === 'active_household_memberships'
              ? result.active_member_count ?? counts.active_member_count
              : result.active_leadership_count ?? leaders.length,
        });
        return;
      }

      // Invalidate household queries
      await queryClient.invalidateQueries({
        queryKey: householdKeys.profile(organizationId, household.id),
      });
      await queryClient.invalidateQueries({
        queryKey: householdKeys.lists(),
      });
      await queryClient.invalidateQueries({
        queryKey: householdKeys.members(),
      });

      onSuccessToast?.(`Household "${household.name}" archived successfully.`);
      handleClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      setErrorMessage(normalized.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  // Pre-emptive frontend blocker detection (if active members or leaders exist on data)
  const hasActiveMembers = counts.active_member_count > 0;
  const hasActiveLeaders = leaders.some((l) => l.assignment_status === 'active');

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-slate-950/80 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-4">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-100">
              Archive Household
            </h2>
            <p className="text-xs text-slate-400 mt-1">
              Safely archive {household.name} ({household.code}).
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

        {/* Informational Banner */}
        <div className="rounded-xl border border-slate-700/60 bg-slate-800/40 p-3.5 text-xs text-slate-300 space-y-1.5 leading-relaxed">
          <p>
            Archiving preserves the household record and its history. Members and
            leadership appointments must be concluded or transferred before the household
            can be archived.
          </p>
        </div>

        {/* Dynamic Blocker Warning */}
        {(blocker || hasActiveMembers || hasActiveLeaders) && (
          <div className="rounded-xl border border-amber-600/50 bg-amber-950/30 p-4 space-y-2 text-xs text-amber-200">
            <div className="flex items-center gap-2 font-semibold text-amber-300">
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <span>Pastoral Safety Rule: Archive Blocked</span>
            </div>
            {hasActiveMembers && (
              <p>
                This household has{' '}
                <span className="font-semibold text-amber-100">
                  {counts.active_member_count} active member{counts.active_member_count === 1 ? '' : 's'}
                </span>
                . Members must be transferred or ended through household assignment management before archiving.
              </p>
            )}
            {hasActiveLeaders && (
              <p>
                This household has{' '}
                <span className="font-semibold text-amber-100">
                  {leaders.length} formal leadership assignment{leaders.length === 1 ? '' : 's'}
                </span>
                . Conclude all formal servant appointments before archiving.
              </p>
            )}
            {blocker && !hasActiveMembers && !hasActiveLeaders && (
              <p>{blocker.message}</p>
            )}
          </div>
        )}

        {/* Error message */}
        {errorMessage && (
          <div className="rounded-xl border border-red-700 bg-red-900/30 p-3.5 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div>
            <label className="block text-xs font-medium text-slate-300">
              Archive Reason <span className="text-rose-400">*</span>
            </label>
            <textarea
              {...register('reason')}
              rows={3}
              placeholder="Explain why this household is being archived (e.g. Consolidated into neighboring household)…"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.reason && (
              <p className="mt-1 text-xs text-rose-400">{errors.reason.message}</p>
            )}
          </div>

          {/* Action buttons */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-slate-800">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="rounded-lg px-4 py-2 text-xs font-medium text-slate-300 hover:bg-slate-800 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || hasActiveMembers || hasActiveLeaders}
              className="inline-flex items-center gap-2 rounded-lg bg-amber-600 px-4 py-2 text-xs font-medium text-white hover:bg-amber-500 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {isSubmitting ? (
                <>
                  <div className="h-3 w-3 animate-spin rounded-full border-2 border-white border-t-transparent" />
                  <span>Archiving…</span>
                </>
              ) : (
                'Archive Household'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

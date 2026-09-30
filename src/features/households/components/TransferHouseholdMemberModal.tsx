import { useState, useId, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { transferHouseholdMember } from '../api/transfer-household-member';
import { searchHouseholds } from '../api/search-households';
import {
  transferHouseholdMemberSchema,
  type TransferHouseholdMemberFormValues,
} from '../schemas';
import type {
  HouseholdSummary,
  TransferHouseholdMemberBlockedResult,
  TransferHouseholdMemberWarningResult,
} from '../types';
import { normalizeError } from '../../../lib/supabase/errors';

interface TransferHouseholdMemberModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  memberName: string;
  currentHouseholdId: string;
  currentHouseholdName: string;
  onSuccessToast?: (msg: string) => void;
}

export function TransferHouseholdMemberModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  memberName,
  currentHouseholdId,
  currentHouseholdName,
  onSuccessToast,
}: TransferHouseholdMemberModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [destinationSearch, setDestinationSearch] = useState('');
  const [activeHouseholds, setActiveHouseholds] = useState<HouseholdSummary[]>([]);
  const [isLoadingHouseholds, setIsLoadingHouseholds] = useState(false);
  const [selectedDestination, setSelectedDestination] = useState<HouseholdSummary | null>(null);

  const [warning, setWarning] = useState<TransferHouseholdMemberWarningResult | null>(null);
  const [blocker, setBlocker] = useState<TransferHouseholdMemberBlockedResult | null>(null);
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
  } = useForm<TransferHouseholdMemberFormValues>({
    resolver: zodResolver(transferHouseholdMemberSchema),
    defaultValues: {
      member_id: memberId,
      destination_household_id: '',
      effective_date: todayStr,
      reason: '',
      confirm_governance_mismatch: false,
    },
  });

  const effectiveDate = watch('effective_date');

  useEffect(() => {
    if (!isOpen) return;

    setValue('member_id', memberId);

    let active = true;
    setIsLoadingHouseholds(true);
    searchHouseholds(organizationId, {
      search: destinationSearch || undefined,
      lifecycleStatus: 'active',
      limit: 25,
    })
      .then((res) => {
        if (active) {
          // Exclude current household
          setActiveHouseholds(res.households.filter((h) => h.household_id !== currentHouseholdId));
          setIsLoadingHouseholds(false);
        }
      })
      .catch((err) => {
        if (active) {
          setErrorMessage(normalizeError(err).message);
          setIsLoadingHouseholds(false);
        }
      });

    return () => {
      active = false;
    };
  }, [isOpen, organizationId, destinationSearch, currentHouseholdId, memberId, setValue]);

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setSelectedDestination(null);
    setDestinationSearch('');
    setWarning(null);
    setBlocker(null);
    setErrorMessage(null);
    onClose();
  };

  const handleSelectDestination = (hh: HouseholdSummary) => {
    setSelectedDestination(hh);
    setValue('destination_household_id', hh.household_id);
    setWarning(null);
    setBlocker(null);
    setErrorMessage(null);
  };

  const onSubmit = async (values: TransferHouseholdMemberFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await transferHouseholdMember(organizationId, {
        member_id: values.member_id,
        destination_household_id: values.destination_household_id,
        effective_date: values.effective_date,
        reason: values.reason,
        confirm_governance_mismatch: values.confirm_governance_mismatch,
      });

      if (result.status === 'blocked') {
        setBlocker(result);
        setWarning(null);
        return;
      }

      if (result.status === 'warning') {
        setWarning(result);
        return;
      }

      // Success
      queryClient.invalidateQueries({ queryKey: householdKeys.profile(organizationId, currentHouseholdId) });
      queryClient.invalidateQueries({ queryKey: householdKeys.profile(organizationId, values.destination_household_id) });
      queryClient.invalidateQueries({ queryKey: householdKeys.lists() });
      queryClient.invalidateQueries({ queryKey: householdKeys.member(organizationId, values.member_id) });

      onSuccessToast?.(
        `${memberName} successfully transferred from ${currentHouseholdName} to ${selectedDestination?.name ?? 'new household'}.`
      );
      handleClose();
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleConfirmMismatch = () => {
    setValue('confirm_governance_mismatch', true);
    handleSubmit(onSubmit)();
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm overflow-y-auto animate-in fade-in duration-150"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-lg rounded-xl border border-slate-700 bg-slate-900 shadow-2xl p-6 text-slate-100 my-8">
        {/* Header */}
        <div className="flex items-center justify-between pb-4 border-b border-slate-800">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-100">
              Transfer Household Member
            </h2>
            <p className="text-xs text-slate-400 mt-0.5">
              Member: <span className="text-slate-200 font-semibold">{memberName}</span>
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

        {/* Current Household Context */}
        <div className="mt-4 p-3 bg-slate-800/60 border border-slate-700/60 rounded-lg text-xs space-y-1">
          <span className="text-slate-400">Current Pastoral Household:</span>
          <p className="font-semibold text-slate-200">{currentHouseholdName}</p>
        </div>

        {/* Error Notice */}
        {errorMessage && (
          <div className="mt-4 p-3 bg-rose-950/40 border border-rose-800/80 rounded-lg text-rose-200 text-xs">
            {errorMessage}
          </div>
        )}

        {/* Blocker Alert (e.g. active leadership blocker) */}
        {blocker && (
          <div className="mt-4 p-3.5 bg-amber-950/40 border border-amber-800/80 rounded-lg text-amber-200 text-xs space-y-2">
            <p className="font-semibold flex items-center gap-1.5 text-amber-300">
              <svg className="h-4 w-4 text-amber-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              Transfer Blocked
            </p>
            <p className="text-slate-300 leading-relaxed">{blocker.message}</p>
            {blocker.blocker_type === 'active_household_leadership' && (
              <p className="text-[11px] text-amber-300/80">
                Action required: Conclude or reassign the member's pastoral leadership role on {currentHouseholdName} before transferring them to another household.
              </p>
            )}
            {blocker.blocker_type === 'leadership_role_inconsistency' && (
              <p className="text-[11px] text-amber-300/80">
                Action required: Resolve this member's formal leadership appointment data before transferring them to another household.
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

        {/* Warning Alert (Governance Mismatch) */}
        {warning && (
          <div className="mt-4 p-3.5 bg-indigo-950/40 border border-indigo-700/80 rounded-lg text-indigo-200 text-xs space-y-2">
            <div className="flex items-center gap-2 text-indigo-300 font-semibold">
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>Governance Notice</span>
            </div>
            <p className="text-slate-300 leading-relaxed">{warning.message}</p>
            <p className="text-[11px] text-slate-400 italic">
              Note: Household pastoral transfer does NOT modify the member's Unit/Chapter governance placement.
            </p>
            <div className="pt-2 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setWarning(null)}
                className="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmMismatch}
                disabled={isSubmitting}
                className="px-3 py-1.5 text-xs font-semibold bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition-colors"
              >
                {isSubmitting ? 'Transferring…' : 'Transfer Anyway'}
              </button>
            </div>
          </div>
        )}

        {!warning && !blocker && (
          <form onSubmit={handleSubmit(onSubmit)} className="mt-4 space-y-4 text-xs">
            {/* Step 1: Destination Household Selector */}
            <div>
              <label className="block font-medium text-slate-300 mb-1.5">
                Destination Active Household <span className="text-rose-400">*</span>
              </label>

              {selectedDestination ? (
                <div className="flex items-center justify-between p-3 bg-slate-800/80 border border-slate-700 rounded-lg">
                  <div>
                    <p className="font-semibold text-slate-100">{selectedDestination.name}</p>
                    <p className="text-[11px] text-slate-400 mt-0.5">
                      Code: {selectedDestination.code}
                      {selectedDestination.parent_node_name && ` • Parent: ${selectedDestination.parent_node_name}`}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      setSelectedDestination(null);
                      setValue('destination_household_id', '');
                    }}
                    className="text-xs text-indigo-400 hover:text-indigo-300 underline"
                  >
                    Change
                  </button>
                </div>
              ) : (
                <div className="space-y-2">
                  <input
                    type="text"
                    placeholder="Search active households by name or code…"
                    value={destinationSearch}
                    onChange={(e) => setDestinationSearch(e.target.value)}
                    className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none"
                  />

                  <div className="max-h-48 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950 divide-y divide-slate-800/60">
                    {isLoadingHouseholds ? (
                      <p className="p-3 text-center text-slate-500 italic">Searching households…</p>
                    ) : activeHouseholds.length === 0 ? (
                      <p className="p-3 text-center text-slate-500 italic">
                        No other active households found.
                      </p>
                    ) : (
                      activeHouseholds.map((h) => (
                        <button
                          key={h.household_id}
                          type="button"
                          onClick={() => handleSelectDestination(h)}
                          className="w-full text-left p-2.5 hover:bg-slate-800/60 transition-colors flex items-center justify-between"
                        >
                          <div>
                            <p className="font-medium text-slate-200">{h.name}</p>
                            <p className="text-[10px] text-slate-400">
                              Code: {h.code}
                              {h.parent_node_name && ` • ${h.parent_node_name}`}
                            </p>
                          </div>
                          <span className="text-[11px] text-indigo-400 font-medium">Select</span>
                        </button>
                      ))
                    )}
                  </div>
                </div>
              )}
              {errors.destination_household_id && (
                <p className="text-rose-400 text-[11px] mt-1">{errors.destination_household_id.message}</p>
              )}
            </div>

            {/* Effective Transfer Date */}
            <div>
              <label htmlFor="transfer_effective_date" className="block font-medium text-slate-300 mb-1">
                Effective Transfer Date <span className="text-rose-400">*</span>
              </label>
              <input
                type="date"
                id="transfer_effective_date"
                max={todayStr}
                value={effectiveDate}
                onChange={(e) => setValue('effective_date', e.target.value)}
                className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none"
              />
              {errors.effective_date && (
                <p className="text-rose-400 text-[11px] mt-1">{errors.effective_date.message}</p>
              )}
            </div>

            {/* Transfer Reason */}
            <div>
              <label htmlFor="transfer_reason" className="block font-medium text-slate-300 mb-1">
                Transfer Reason <span className="text-rose-400">*</span>
              </label>
              <textarea
                id="transfer_reason"
                rows={3}
                {...register('reason')}
                placeholder="Explain the pastoral or logistical reason for this household transfer…"
                className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none"
              />
              {errors.reason && (
                <p className="text-rose-400 text-[11px] mt-1">{errors.reason.message}</p>
              )}
            </div>

            {/* History notice */}
            <div className="p-2.5 rounded-lg bg-slate-800/40 border border-slate-800 text-[11px] text-slate-400">
              The previous assignment on <span className="text-slate-300">{currentHouseholdName}</span> will be concluded and permanently preserved in history.
            </div>

            {/* Actions */}
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
                disabled={isSubmitting || !selectedDestination}
                className="px-4 py-2 text-xs font-semibold bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white rounded-lg shadow-sm transition-colors"
              >
                {isSubmitting ? 'Transferring…' : 'Transfer Member'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

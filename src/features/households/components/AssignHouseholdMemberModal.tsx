import { useState, useId, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { assignHouseholdMember } from '../api/assign-household-member';
import { searchMembersWithoutHousehold } from '../api/search-members-without-household';
import {
  assignHouseholdMemberSchema,
  type AssignHouseholdMemberFormValues,
} from '../schemas';
import type {
  MemberWithoutHousehold,
  AssignHouseholdMemberWarningResult,
  AssignHouseholdMemberBlockedResult,
} from '../types';
import { normalizeError } from '../../../lib/supabase/errors';

interface AssignHouseholdMemberModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdId: string;
  householdName: string;
  parentGovernanceName?: string | null;
  preselectedMember?: MemberWithoutHousehold | null;
  onSuccessToast?: (msg: string) => void;
}

export function AssignHouseholdMemberModal({
  isOpen,
  onClose,
  organizationId,
  householdId,
  householdName,
  parentGovernanceName,
  preselectedMember,
  onSuccessToast,
}: AssignHouseholdMemberModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [candidateList, setCandidateList] = useState<MemberWithoutHousehold[]>([]);
  const [isLoadingSearch, setIsLoadingSearch] = useState(false);
  const [selectedMember, setSelectedMember] = useState<MemberWithoutHousehold | null>(null);

  const [warning, setWarning] = useState<AssignHouseholdMemberWarningResult | null>(null);
  const [blocker, setBlocker] = useState<AssignHouseholdMemberBlockedResult | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();

  const todayStr = new Date().toISOString().split('T')[0];

  const {
    handleSubmit,
    setValue,
    watch,
    reset,
    formState: { errors },
  } = useForm<AssignHouseholdMemberFormValues>({
    resolver: zodResolver(assignHouseholdMemberSchema),
    defaultValues: {
      member_id: '',
      household_id: householdId,
      effective_from: todayStr,
      confirm_governance_mismatch: false,
    },
  });

  const effectiveFrom = watch('effective_from');

  // Load search members
  useEffect(() => {
    if (!isOpen) return;

    if (preselectedMember) {
      setSelectedMember(preselectedMember);
      setValue('member_id', preselectedMember.member_id);
      return;
    }

    let active = true;
    setIsLoadingSearch(true);
    searchMembersWithoutHousehold(organizationId, {
      search: searchQuery || undefined,
      limit: 20,
    })
      .then((res) => {
        if (active) {
          setCandidateList(res.members);
          setIsLoadingSearch(false);
        }
      })
      .catch((err) => {
        if (active) {
          setErrorMessage(normalizeError(err).message);
          setIsLoadingSearch(false);
        }
      });

    return () => {
      active = false;
    };
  }, [isOpen, organizationId, searchQuery, preselectedMember, setValue]);

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setSelectedMember(null);
    setSearchQuery('');
    setWarning(null);
    setBlocker(null);
    setErrorMessage(null);
    onClose();
  };

  const handleSelectMember = (m: MemberWithoutHousehold) => {
    setSelectedMember(m);
    setValue('member_id', m.member_id);
    setWarning(null);
    setBlocker(null);
    setErrorMessage(null);
  };

  const onSubmit = async (values: AssignHouseholdMemberFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await assignHouseholdMember(organizationId, {
        member_id: values.member_id,
        household_id: householdId,
        effective_from: values.effective_from,
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
      queryClient.invalidateQueries({ queryKey: householdKeys.profile(organizationId, householdId) });
      queryClient.invalidateQueries({ queryKey: householdKeys.lists() });
      queryClient.invalidateQueries({ queryKey: householdKeys.membersWithoutHousehold(organizationId) });
      queryClient.invalidateQueries({ queryKey: householdKeys.member(organizationId, values.member_id) });

      onSuccessToast?.(
        `${selectedMember?.display_name ?? 'Member'} successfully assigned to ${householdName}.`
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
              Assign Member to Household
            </h2>
            <p className="text-xs text-slate-400 mt-0.5">
              Household: <span className="text-indigo-400 font-semibold">{householdName}</span>
              {parentGovernanceName && (
                <span className="text-slate-500"> ({parentGovernanceName})</span>
              )}
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

        {/* Generic Error */}
        {errorMessage && (
          <div className="mt-4 p-3 bg-rose-950/40 border border-rose-800/80 rounded-lg text-rose-200 text-xs">
            {errorMessage}
          </div>
        )}

        {/* Blocker Alert */}
        {blocker && (
          <div className="mt-4 p-3 bg-amber-950/40 border border-amber-800/80 rounded-lg text-amber-200 text-xs space-y-1">
            <p className="font-semibold flex items-center gap-1.5">
              <svg className="h-4 w-4 text-amber-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              Assignment Blocked
            </p>
            <p>{blocker.message}</p>
          </div>
        )}

        {/* Warning Alert (Governance Mismatch / Unplaced) */}
        {warning && (
          <div className="mt-4 p-3.5 bg-indigo-950/40 border border-indigo-700/80 rounded-lg text-indigo-200 text-xs space-y-2">
            <div className="flex items-center gap-2 text-indigo-300 font-semibold">
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>Pastoral Placement Notice</span>
            </div>
            <p className="text-slate-300 leading-relaxed">{warning.message}</p>
            <p className="text-[11px] text-slate-400 italic">
              Note: Household pastoral assignment does NOT modify the member's Unit/Chapter governance placement.
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
                {isSubmitting ? 'Assigning…' : 'Assign Anyway'}
              </button>
            </div>
          </div>
        )}

        {!warning && (
          <form onSubmit={handleSubmit(onSubmit)} className="mt-4 space-y-4 text-xs">
            {/* Step 1: Member Selection */}
            {!preselectedMember && (
              <div>
                <label className="block font-medium text-slate-300 mb-1.5">
                  Select Unassigned Member <span className="text-rose-400">*</span>
                </label>
                {selectedMember ? (
                  <div className="flex items-center justify-between p-3 bg-slate-800/80 border border-slate-700 rounded-lg">
                    <div>
                      <p className="font-semibold text-slate-100">{selectedMember.display_name}</p>
                      <p className="text-[11px] text-slate-400 mt-0.5">
                        {selectedMember.member_number ? `#${selectedMember.member_number}` : 'No member number'}
                        {selectedMember.primary_governance_name && (
                          <> • Governance: {selectedMember.primary_governance_name}</>
                        )}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedMember(null);
                        setValue('member_id', '');
                        setBlocker(null);
                        setWarning(null);
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
                      placeholder="Search unassigned active members by name…"
                      value={searchQuery}
                      onChange={(e) => setSearchQuery(e.target.value)}
                      className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none"
                    />

                    <div className="max-h-48 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950 divide-y divide-slate-800/60">
                      {isLoadingSearch ? (
                        <p className="p-3 text-center text-slate-500 italic">Searching members…</p>
                      ) : candidateList.length === 0 ? (
                        <p className="p-3 text-center text-slate-500 italic">
                          No members without a household found.
                        </p>
                      ) : (
                        candidateList.map((m) => (
                          <button
                            key={m.member_id}
                            type="button"
                            onClick={() => handleSelectMember(m)}
                            className="w-full text-left p-2.5 hover:bg-slate-800/60 transition-colors flex items-center justify-between"
                          >
                            <div>
                              <p className="font-medium text-slate-200">{m.display_name}</p>
                              <p className="text-[10px] text-slate-400">
                                {m.member_number ? `#${m.member_number}` : 'No number'}
                                {m.primary_governance_name && ` • ${m.primary_governance_name}`}
                              </p>
                            </div>
                            <span className="text-[11px] text-indigo-400 font-medium">Select</span>
                          </button>
                        ))
                      )}
                    </div>
                  </div>
                )}
                {errors.member_id && (
                  <p className="text-rose-400 text-[11px] mt-1">{errors.member_id.message}</p>
                )}
              </div>
            )}

            {/* If Preselected Member, show banner */}
            {preselectedMember && (
              <div className="p-3 bg-slate-800/80 border border-slate-700 rounded-lg">
                <p className="text-[11px] text-slate-400">Assigning Member:</p>
                <p className="font-semibold text-slate-100 text-sm mt-0.5">
                  {preselectedMember.display_name}
                </p>
                <p className="text-[11px] text-slate-400 mt-0.5">
                  {preselectedMember.member_number ? `#${preselectedMember.member_number}` : ''}
                  {preselectedMember.primary_governance_name &&
                    ` • Placement: ${preselectedMember.primary_governance_name}`}
                </p>
              </div>
            )}

            {/* Effective Date */}
            <div>
              <label htmlFor="assign_effective_from" className="block font-medium text-slate-300 mb-1">
                Effective Assignment Date <span className="text-rose-400">*</span>
              </label>
              <input
                type="date"
                id="assign_effective_from"
                max={todayStr}
                value={effectiveFrom}
                onChange={(e) => setValue('effective_from', e.target.value)}
                className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none"
              />
              {errors.effective_from && (
                <p className="text-rose-400 text-[11px] mt-1">{errors.effective_from.message}</p>
              )}
            </div>

            {/* Notice */}
            <div className="p-2.5 rounded-lg bg-slate-800/40 border border-slate-800 text-[11px] text-slate-400">
              Household membership is a pastoral placement with role <span className="text-slate-200 font-semibold">Member</span>. Servant roles are managed separately under household leadership appointments.
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
                disabled={isSubmitting || !selectedMember}
                className="px-4 py-2 text-xs font-semibold bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white rounded-lg shadow-sm transition-colors"
              >
                {isSubmitting ? 'Assigning…' : 'Assign Member'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

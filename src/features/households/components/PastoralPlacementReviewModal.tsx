import { useState, useId, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { getPastoralPlacementReview } from '../api/get-pastoral-placement-review';
import { executePastoralPlacement } from '../api/execute-pastoral-placement';
import {
  executePastoralPlacementSchema,
  type ExecutePastoralPlacementFormValues,
} from '../schemas';
import type {
  PastoralPlacementReview,
  PastoralPlacementDestination,
} from '../types';
import { normalizeError } from '../../../lib/supabase/errors';

interface PastoralPlacementReviewModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  leadershipAssignmentId: string;
  onSuccessToast?: (msg: string) => void;
}

export function PastoralPlacementReviewModal({
  isOpen,
  onClose,
  organizationId,
  leadershipAssignmentId,
  onSuccessToast,
}: PastoralPlacementReviewModalProps) {
  const queryClient = useQueryClient();
  const [isLoading, setIsLoading] = useState(true);
  const [review, setReview] = useState<PastoralPlacementReview | null>(null);
  const [selectedDestination, setSelectedDestination] = useState<PastoralPlacementDestination | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const todayStr = new Date().toISOString().split('T')[0];

  const {
    handleSubmit,
    setValue,
    watch,
    reset,
    formState: { errors },
  } = useForm<ExecutePastoralPlacementFormValues>({
    resolver: zodResolver(executePastoralPlacementSchema),
    defaultValues: {
      destination_household_id: '',
      effective_date: todayStr,
      reason: '',
      include_verified_spouse: true,
    },
  });

  const includeVerifiedSpouse = watch('include_verified_spouse');
  const selectedDestId = watch('destination_household_id');

  // Load review data on open
  useEffect(() => {
    if (!isOpen || !leadershipAssignmentId) return;

    let active = true;
    setIsLoading(true);
    setErrorMessage(null);

    getPastoralPlacementReview(organizationId, leadershipAssignmentId)
      .then((data) => {
        if (!active) return;
        setReview(data);
        // Pre-select first eligible destination if available
        const eligible = data.available_destination_households.find((d) => d.is_eligible);
        if (eligible) {
          setSelectedDestination(eligible);
          setValue('destination_household_id', eligible.household_id);
        }
        setIsLoading(false);
      })
      .catch((err) => {
        if (!active) return;
        setErrorMessage(normalizeError(err).message);
        setIsLoading(false);
      });

    return () => {
      active = false;
    };
  }, [isOpen, organizationId, leadershipAssignmentId, setValue]);

  if (!isOpen) return null;

  const onSubmit = async (values: ExecutePastoralPlacementFormValues) => {
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const res = await executePastoralPlacement({
        organizationId,
        leadershipAssignmentId,
        destinationHouseholdId: values.destination_household_id,
        effectiveDate: values.effective_date,
        reason: values.reason,
        includeVerifiedSpouse: values.include_verified_spouse,
      });

      // Invalidate relevant queries
      await queryClient.invalidateQueries({ queryKey: householdKeys.all });

      onSuccessToast?.(
        res.couples_placement
          ? `Placed leader and spouse into ${res.destination_household_name}.`
          : `Placed leader into ${res.destination_household_name}.`
      );

      reset();
      onClose();
    } catch (err: unknown) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm overflow-y-auto"
    >
      <div className="bg-slate-900 border border-slate-800 rounded-xl shadow-2xl w-full max-w-2xl max-h-[90vh] flex flex-col overflow-hidden text-slate-100">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-800 bg-slate-900/50">
          <div>
            <h2 id={titleId} className="text-lg font-semibold text-white">
              Pastoral Placement Review
            </h2>
            <p className="text-xs text-slate-400 mt-0.5">
              Review and assign or transfer servant leaders to their pastoral nourishment households.
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="text-slate-400 hover:text-white transition-colors p-1"
          >
            ✕
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {isLoading ? (
            <div className="py-12 text-center text-slate-400 text-sm">
              Loading pastoral placement review...
            </div>
          ) : errorMessage && !review ? (
            <div className="p-4 bg-red-950/40 border border-red-800/60 rounded-lg text-sm text-red-300">
              {errorMessage}
            </div>
          ) : review ? (
            <>
              {/* Guidance & Echelon Summary Card */}
              <div className="bg-slate-800/50 border border-slate-700/60 rounded-lg p-4 space-y-3">
                <div className="grid grid-cols-2 gap-3 text-xs">
                  <div>
                    <span className="text-slate-400 block">Formal Office:</span>
                    <span className="font-medium text-white">{review.formal_role_name}</span>
                    <span className="text-slate-500 block text-[11px]">at {review.formal_governance_node_name}</span>
                  </div>
                  <div>
                    <span className="text-slate-400 block">Leader:</span>
                    <span className="font-medium text-white">{review.leader_member_name}</span>
                  </div>
                  <div>
                    <span className="text-slate-400 block">Recommended Pastoral Level:</span>
                    <span className="font-medium text-amber-300 uppercase tracking-wide">
                      {review.recommended_pastoral_level} Household
                    </span>
                  </div>
                  <div>
                    <span className="text-slate-400 block">Recommended Scope:</span>
                    <span className="font-medium text-white">{review.recommended_scope_node_name}</span>
                  </div>
                </div>

                <div className="border-t border-slate-700/50 pt-2 flex items-center justify-between text-xs">
                  <div>
                    <span className="text-slate-400 mr-1.5">Current Placement:</span>
                    <span className="font-medium text-slate-200">
                      {review.current_primary_household_name || 'No Primary Household'}
                    </span>
                  </div>
                  <div>
                    <span className="text-slate-400 mr-1.5">Workflow Status:</span>
                    <span
                      className={`inline-flex px-2 py-0.5 rounded text-[11px] font-semibold ${
                        review.workflow_status === 'already_correct'
                          ? 'bg-emerald-950/60 border border-emerald-700/60 text-emerald-300'
                          : review.workflow_status.startsWith('blocked')
                          ? 'bg-red-950/60 border border-red-700/60 text-red-300'
                          : 'bg-indigo-950/60 border border-indigo-700/60 text-indigo-300'
                      }`}
                    >
                      {review.workflow_status}
                    </span>
                  </div>
                </div>
              </div>

              {/* Couples Context Details if Applicable */}
              {review.couples_context_status === 'couples' && (
                <div className="bg-slate-800/40 border border-slate-700/50 rounded-lg p-4 space-y-3">
                  <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider">
                    Couples Section Pastoral Care
                  </h4>
                  <div className="grid grid-cols-2 gap-4 text-xs">
                    <div className="bg-slate-900/60 p-3 rounded border border-slate-800">
                      <span className="text-slate-400 block text-[11px]">Husband (Formal Leader)</span>
                      <span className="font-medium text-white block mt-0.5">{review.leader_member_name}</span>
                      <span className="text-slate-500 block text-[11px] mt-1">
                        Current: {review.current_primary_household_name || 'Unassigned'}
                      </span>
                    </div>
                    <div className="bg-slate-900/60 p-3 rounded border border-slate-800">
                      <span className="text-slate-400 block text-[11px]">Wife (Pastoral Partner)</span>
                      <span className="font-medium text-white block mt-0.5">
                        {review.spouse_context.spouse_name || 'No Spouse Found'}
                      </span>
                      <span className="text-slate-500 block text-[11px] mt-1">
                        Current: {review.spouse_current_primary_household.household_name || 'Unassigned'}
                      </span>
                      {!review.spouse_context.has_verified_spouse && (
                        <span className="text-amber-400 block text-[11px] mt-1">
                          ⚠️ Spouse verification review required
                        </span>
                      )}
                    </div>
                  </div>
                </div>
              )}

              {/* Ambiguous Couples Context Display */}
              {review.couples_context_status === 'ambiguous' && (
                <div className="bg-amber-950/30 border border-amber-800/60 rounded-lg p-4 space-y-3">
                  <div className="flex items-start gap-2">
                    <span className="text-amber-400 text-sm">⚠️</span>
                    <div>
                      <h4 className="text-xs font-semibold text-amber-200">
                        Couples ministry context requires review before pastoral placement.
                      </h4>
                      <p className="text-xs text-amber-300/80 mt-1">
                        The ministry section context for this servant leader cannot be determined authoritatively from existing section assignments or household lineage. Marriage alone does not determine Couples context, but unverified ministry intent requires review before placement.
                      </p>
                    </div>
                  </div>
                  {review.spouse_context.has_spouse && (
                    <div className="bg-slate-900/60 p-3 rounded border border-slate-800 text-xs">
                      <span className="text-slate-400 block text-[11px]">Identified Spouse:</span>
                      <span className="font-medium text-white block mt-0.5">
                        {review.spouse_context.spouse_name}
                        {review.spouse_context.has_verified_spouse ? ' (Verified)' : ' (Unverified)'}
                      </span>
                      <span className="text-slate-400 block text-[11px] mt-1">
                        Placement remains blocked until section or household ministry context is established.
                      </span>
                    </div>
                  )}
                </div>
              )}

              {/* Already Correct Notice */}
              {review.workflow_status === 'already_correct' && (
                <div className="p-4 bg-emerald-950/40 border border-emerald-800/60 rounded-lg text-sm text-emerald-300">
                  ✓ This servant leader is already correctly placed in their recommended pastoral household. No action is required.
                </div>
              )}

              {/* Blocked Notice */}
              {review.workflow_status === 'blocked_no_destination' && (
                <div className="p-4 bg-amber-950/40 border border-amber-800/60 rounded-lg text-sm text-amber-300">
                  ⚠️ No active destination {review.recommended_pastoral_level} household exists under {review.recommended_scope_node_name}. Please create a destination household before placing this leader.
                </div>
              )}

              {review.workflow_status === 'blocked_spouse_review' && (
                <div className="p-4 bg-red-950/40 border border-red-800/60 rounded-lg text-sm text-red-300">
                  ⚠️ The Couples Section requires husband and wife to receive pastoral care together, but the spouse record is absent or unverified. Verify the marriage in Family Relationships before proceeding.
                </div>
              )}

              {review.workflow_status === 'manual_review_required' && review.couples_context_status !== 'ambiguous' && (
                <div className="p-4 bg-amber-950/40 border border-amber-800/60 rounded-lg text-sm text-amber-300">
                  ⚠️ Manual pastoral review is required before this placement can be executed.
                </div>
              )}

              {/* Form / Execution Section */}
              {review.workflow_status !== 'already_correct' &&
               review.workflow_status !== 'manual_review_required' &&
               !review.workflow_status.startsWith('blocked') && (
                <form id="pastoral-placement-form" onSubmit={handleSubmit(onSubmit)} className="space-y-4">
                  {/* Destination Household Selector */}
                  <div>
                    <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider mb-2">
                      Select Destination Household ({review.recommended_pastoral_level} level)
                    </label>
                    <div className="space-y-2">
                      {review.available_destination_households.map((dest) => {
                        const isSelected = selectedDestId === dest.household_id;
                        return (
                          <div
                            key={dest.household_id}
                            onClick={() => {
                              if (dest.is_eligible) {
                                setSelectedDestination(dest);
                                setValue('destination_household_id', dest.household_id);
                              }
                            }}
                            className={`p-3 rounded-lg border transition-all text-xs flex items-center justify-between cursor-pointer ${
                              !dest.is_eligible
                                ? 'bg-slate-900/40 border-slate-800/60 opacity-50 cursor-not-allowed'
                                : isSelected
                                ? 'bg-indigo-950/60 border-indigo-500 shadow-md shadow-indigo-950/50'
                                : 'bg-slate-800/40 border-slate-700/60 hover:border-slate-600'
                            }`}
                          >
                            <div>
                              <span className="font-medium text-white block">{dest.household_name}</span>
                              <span className="text-slate-400 block text-[11px] mt-0.5">
                                {dest.pastoral_level} level • {dest.is_couple_household ? 'Couples Household' : 'Standard Household'}
                              </span>
                            </div>
                            <div className="text-right">
                              <span
                                className={`inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium ${
                                  dest.capacity_status === 'full' || dest.capacity_status === 'not_accepting'
                                    ? 'bg-red-950/60 text-red-400 border border-red-800/50'
                                    : dest.capacity_status === 'at_target'
                                    ? 'bg-amber-950/60 text-amber-400 border border-amber-800/50'
                                    : 'bg-emerald-950/60 text-emerald-400 border border-emerald-800/50'
                                }`}
                              >
                                {dest.capacity_status}
                              </span>
                              <span className="text-slate-500 block text-[11px] mt-0.5">
                                {dest.current_member_count}
                                {dest.maximum_member_count !== null ? ` / ${dest.maximum_member_count}` : ''} members
                              </span>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                    {errors.destination_household_id && (
                      <p className="text-xs text-red-400 mt-1">{errors.destination_household_id.message}</p>
                    )}
                  </div>

                  {/* Couples Include Checkbox */}
                  {review.couples_context_status === 'couples' && review.spouse_context.has_verified_spouse && (
                    <div className="bg-slate-800/30 border border-slate-700/40 rounded p-3 text-xs flex items-center justify-between">
                      <div>
                        <span className="font-medium text-white block">Place Verified Wife Together</span>
                        <span className="text-slate-400 block text-[11px]">
                          Assigns or transfers {review.spouse_context.spouse_name} to the same destination household.
                        </span>
                      </div>
                      <input
                        type="checkbox"
                        checked={includeVerifiedSpouse}
                        onChange={(e) => setValue('include_verified_spouse', e.target.checked)}
                        className="rounded border-slate-700 bg-slate-800 text-indigo-600 focus:ring-indigo-500 h-4 w-4"
                      />
                    </div>
                  )}

                  {/* Effective Date */}
                  <div>
                    <label className="block text-xs text-slate-300 mb-1">Effective Date</label>
                    <input
                      type="date"
                      max={todayStr}
                      value={watch('effective_date')}
                      onChange={(e) => setValue('effective_date', e.target.value)}
                      className="w-full bg-slate-950 border border-slate-700 rounded px-3 py-2 text-xs text-white"
                    />
                    {errors.effective_date && (
                      <p className="text-xs text-red-400 mt-1">{errors.effective_date.message}</p>
                    )}
                  </div>

                  {/* Reason */}
                  <div>
                    <label className="block text-xs text-slate-300 mb-1">
                      Reason for Pastoral Placement <span className="text-red-400">*</span>
                    </label>
                    <textarea
                      rows={2}
                      placeholder="e.g. Pastoral nourishment echelon assignment following servant leader appointment"
                      onChange={(e) => setValue('reason', e.target.value)}
                      value={watch('reason')}
                      className="w-full bg-slate-950 border border-slate-700 rounded px-3 py-2 text-xs text-white"
                    />
                    {errors.reason && (
                      <p className="text-xs text-red-400 mt-1">{errors.reason.message}</p>
                    )}
                  </div>

                  {/* Confirmation Disclosure */}
                  <div className="bg-slate-950/60 border border-slate-800 rounded p-3 text-[11px] text-slate-400">
                    <p className="font-semibold text-slate-300 mb-0.5">Notice:</p>
                    This changes pastoral household membership only. It does not change the formal servant-leader appointment or software access.
                  </div>

                  {errorMessage && (
                    <div className="p-3 bg-red-950/40 border border-red-800/60 rounded text-xs text-red-300">
                      {errorMessage}
                    </div>
                  )}
                </form>
              )}
            </>
          ) : null}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 px-6 py-4 border-t border-slate-800 bg-slate-900/50">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="px-4 py-2 text-xs font-medium text-slate-300 hover:text-white bg-slate-800 hover:bg-slate-700 rounded-lg transition-colors"
          >
            {review?.workflow_status === 'already_correct' ? 'Close' : 'Cancel'}
          </button>
          {review &&
            review.workflow_status !== 'already_correct' &&
            review.workflow_status !== 'manual_review_required' &&
            !review.workflow_status.startsWith('blocked') && (
            <button
              type="submit"
              form="pastoral-placement-form"
              disabled={isSubmitting || !selectedDestination}
              className="px-4 py-2 text-xs font-medium text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg shadow-lg shadow-indigo-600/30 transition-all"
            >
              {isSubmitting
                ? 'Placing...'
                : review.recommended_action === 'assign'
                ? `Assign to ${review.recommended_pastoral_level} Household`
                : `Transfer to ${review.recommended_pastoral_level} Household`}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

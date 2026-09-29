import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys, type GovernancePlacement } from '../queries';
import { usePlacementNodes } from '../api/get-placement-nodes';
import { changeMemberGovernanceAssignment } from '../api/change-member-governance-assignment';
import { normalizeError } from '../../../lib/supabase/errors';

interface ChangeGovernancePlacementModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  currentPlacement: GovernancePlacement | null;
  onSuccessToast?: (msg: string) => void;
}

export function ChangeGovernancePlacementModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  currentPlacement,
  onSuccessToast,
}: ChangeGovernancePlacementModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();

  // Load selectable Chapter and Unit placement nodes (only when modal is open)
  const {
    data: nodes,
    isLoading: isNodesLoading,
    error: nodesError,
  } = usePlacementNodes(organizationId, isOpen);

  // Current placement ID (or empty string for unplaced)
  const currentPlacementNodeId = currentPlacement?.governance_node_id ?? '';
  const currentEffectiveFrom = currentPlacement?.effective_from ?? null;

  // Validation Schema
  const schema = z
    .object({
      targetGovernanceNodeId: z.string(), // empty string = unplaced
      effectiveFrom: z
        .string()
        .trim()
        .min(1, 'Effective date is required')
        .refine((val) => !isNaN(new Date(val).getTime()), 'Invalid date format'),
      reason: z.string().optional(),
    })
    .superRefine((data, ctx) => {
      if (currentEffectiveFrom && data.effectiveFrom) {
        if (data.effectiveFrom < currentEffectiveFrom) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['effectiveFrom'],
            message: `Effective date cannot precede current placement start date (${currentEffectiveFrom})`,
          });
        }
      }
    });

  type FormData = z.infer<typeof schema>;

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors },
  } = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: {
      targetGovernanceNodeId: currentPlacementNodeId,
      effectiveFrom: new Date().toISOString().split('T')[0],
      reason: '',
    },
  });

  if (!isOpen) return null;

  const selectedNodeId = watch('targetGovernanceNodeId');
  const isSamePlacement = selectedNodeId === currentPlacementNodeId;
  const isBothUnplaced = !currentPlacementNodeId && !selectedNodeId;

  const getSamePlacementMessage = () => {
    if (isBothUnplaced) {
      return 'This member is already unplaced.';
    }
    if (isSamePlacement) {
      return 'This member is already assigned to this placement.';
    }
    return null;
  };

  const samePlacementMessage = getSamePlacementMessage();

  // Group chapters and units
  const chapters = nodes?.filter((n) => n.node_type_code === 'chapter') || [];
  const units = nodes?.filter((n) => n.node_type_code === 'unit') || [];

  const onSubmit = async (data: FormData) => {
    if (isSamePlacement) return;

    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      await changeMemberGovernanceAssignment({
        organizationId,
        memberId,
        targetGovernanceNodeId: data.targetGovernanceNodeId ? data.targetGovernanceNodeId : null,
        effectiveFrom: data.effectiveFrom,
        reason: data.reason,
      });

      // Invalidate profile query
      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, memberId),
      });

      // Invalidate member directory lists (scoping/visibility depends on placement)
      queryClient.invalidateQueries({
        queryKey: memberKeys.lists(),
      });

      if (onSuccessToast) {
        onSuccessToast('Member placement updated.');
      }

      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage(
          'Access denied: You do not have permission to place this member or the target node is outside your authorized scope.'
        );
      } else if (normalized.code === '22023') {
        setErrorMessage(
          normalized.message || 'Invalid target node type or date sequencing.'
        );
      } else if (normalized.code === 'P0002') {
        setErrorMessage(
          'Target governance node not found or inactive.'
        );
      } else {
        setErrorMessage(normalized.message);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 p-4 backdrop-blur-sm overflow-y-auto"
    >
      <div className="w-full max-w-xl rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-6 my-8">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-3">
          <div>
            <h2 id={titleId} className="text-lg font-bold tracking-tight text-slate-100">
              Change Governance Placement
            </h2>
            <p className="mt-0.5 text-xs text-slate-400">
              Transfer this member to another Chapter or Unit, or set as unplaced.
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            aria-label="Close dialog"
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
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

        {/* Notice */}
        <div className="rounded-lg border border-indigo-900/40 bg-indigo-950/30 p-3 text-xs text-indigo-300">
          Changing placement preserves the previous assignment in the member&apos;s history.
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
          {/* Current Placement display */}
          <div className="rounded-xl border border-slate-700/60 bg-slate-800/40 p-3.5">
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">
              Current Placement
            </p>
            <div className="mt-1 flex items-center justify-between">
              {currentPlacement ? (
                <div>
                  <p className="text-sm font-semibold text-slate-100">
                    {currentPlacement.node_name}
                  </p>
                  <p className="text-xs text-slate-400">
                    Code: <span className="font-mono text-slate-300">{currentPlacement.node_code}</span> · Active since {currentPlacement.effective_from}
                  </p>
                </div>
              ) : (
                <p className="text-sm font-medium text-slate-400 italic">
                  Unplaced
                </p>
              )}
            </div>
          </div>

          {/* New Placement hierarchy selector */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400">
              New Placement <span className="text-rose-400">*</span>
            </label>

            {isNodesLoading && (
              <div className="space-y-2">
                <div className="h-12 animate-pulse rounded-lg bg-slate-800" />
                <div className="h-24 animate-pulse rounded-lg bg-slate-800" />
              </div>
            )}

            {nodesError && (
              <div className="rounded-lg border border-red-700 bg-red-900/20 p-3 text-xs text-red-300">
                Failed to load placement hierarchy. Please try again.
              </div>
            )}

            {!isNodesLoading && (
              <div className="max-h-60 overflow-y-auto space-y-2 pr-1 rounded-xl border border-slate-700/60 p-2 bg-slate-950/40">
                {/* Option: Unplaced */}
                <label
                  className={`flex items-center justify-between rounded-lg border p-3 cursor-pointer transition-colors ${
                    !selectedNodeId
                      ? 'border-indigo-500 bg-indigo-950/30 text-indigo-100'
                      : 'border-slate-800 bg-slate-900/40 hover:bg-slate-800/60 text-slate-300'
                  }`}
                >
                  <div className="flex items-center gap-2.5">
                    <input
                      type="radio"
                      value=""
                      {...register('targetGovernanceNodeId')}
                      className="h-4 w-4 border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500"
                    />
                    <div>
                      <p className="text-xs font-semibold text-slate-200">Unplaced</p>
                      <p className="text-[10px] text-slate-400">
                        Leave member without an active primary Chapter or Unit.
                      </p>
                    </div>
                  </div>
                  <span className="text-[10px] uppercase font-mono text-slate-500">Unplaced</span>
                </label>

                {/* Chapters & Units */}
                {chapters.map((ch) => {
                  const childUnits = units.filter(
                    (u) => u.parent_governance_node_id === ch.governance_node_id
                  );
                  const isChapterSelected = selectedNodeId === ch.governance_node_id;

                  return (
                    <div
                      key={ch.governance_node_id}
                      className="rounded-lg border border-slate-800 bg-slate-900/30 overflow-hidden"
                    >
                      {/* Chapter Item */}
                      <label
                        className={`flex items-center justify-between p-2.5 cursor-pointer transition-colors ${
                          isChapterSelected
                            ? 'bg-indigo-950/40 text-indigo-100'
                            : 'hover:bg-slate-800/40 text-slate-200'
                        }`}
                      >
                        <div className="flex items-center gap-2.5">
                          <input
                            type="radio"
                            value={ch.governance_node_id}
                            {...register('targetGovernanceNodeId')}
                            className="h-4 w-4 border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500"
                          />
                          <div>
                            <p className="text-xs font-semibold">{ch.node_name}</p>
                            <p className="text-[10px] text-slate-400">Chapter</p>
                          </div>
                        </div>
                        <span className="rounded bg-slate-800 px-1.5 py-0.5 text-[10px] font-mono uppercase text-slate-400">
                          {ch.node_code}
                        </span>
                      </label>

                      {/* Child Units */}
                      {childUnits.length > 0 && (
                        <div className="border-t border-slate-800/60 bg-slate-950/20 pl-6 pr-2 py-1.5 space-y-1">
                          {childUnits.map((u) => {
                            const isUnitSelected = selectedNodeId === u.governance_node_id;

                            return (
                              <label
                                key={u.governance_node_id}
                                className={`flex items-center justify-between rounded p-2 cursor-pointer transition-colors ${
                                  isUnitSelected
                                    ? 'bg-indigo-950/40 text-indigo-100'
                                    : 'hover:bg-slate-800/30 text-slate-300'
                                }`}
                              >
                                <div className="flex items-center gap-2">
                                  <span className="text-slate-600 text-xs">└</span>
                                  <input
                                    type="radio"
                                    value={u.governance_node_id}
                                    {...register('targetGovernanceNodeId')}
                                    className="h-3.5 w-3.5 border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500"
                                  />
                                  <div>
                                    <p className="text-xs font-medium">{u.node_name}</p>
                                    <p className="text-[10px] text-slate-400">
                                      Unit under {ch.node_name}
                                    </p>
                                  </div>
                                </div>
                                <span className="text-[10px] font-mono text-slate-500 uppercase">
                                  {u.node_code}
                                </span>
                              </label>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Same placement indicator */}
          {samePlacementMessage && (
            <div className="rounded-lg border border-amber-600/40 bg-amber-950/20 p-2.5 text-xs text-amber-300">
              {samePlacementMessage}
            </div>
          )}

          {/* Effective Date & Reason */}
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="effectiveFrom" className="block text-xs font-medium text-slate-300">
                Effective Date <span className="text-rose-400">*</span>
              </label>
              <input
                id="effectiveFrom"
                type="date"
                min={currentEffectiveFrom ?? undefined}
                {...register('effectiveFrom')}
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
              {errors.effectiveFrom && (
                <p className="mt-1 text-xs text-rose-400">{errors.effectiveFrom.message}</p>
              )}
              {currentEffectiveFrom && (
                <p className="mt-1 text-[11px] text-slate-500">
                  Cannot precede current placement start date ({currentEffectiveFrom})
                </p>
              )}
            </div>

            <div>
              <label htmlFor="reason" className="block text-xs font-medium text-slate-300">
                Reason for Change <span className="text-slate-500">(optional)</span>
              </label>
              <input
                id="reason"
                type="text"
                {...register('reason')}
                placeholder="e.g. Transferred by administration"
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 border-t border-slate-800 pt-4">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="rounded-lg border border-slate-700 px-4 py-2 text-xs font-medium text-slate-300 hover:bg-slate-800 transition-colors disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || !!samePlacementMessage}
              className="inline-flex items-center justify-center rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors shadow-sm disabled:opacity-50"
            >
              {isSubmitting ? (
                <>
                  <svg className="mr-2 h-3.5 w-3.5 animate-spin text-white" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                  </svg>
                  Saving…
                </>
              ) : (
                'Save Placement'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { endFamilyRelationship } from '../api/end-family-relationship';
import { familyKeys } from '../queries';
import {
  endFamilyRelationshipSchema,
  type EndFamilyRelationshipFormValues,
} from '../schemas/end-family-relationship-schema';
import type { FamilyProfileRelationship, FamilyProfileMember } from '../types';

interface EndFamilyRelationshipModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  familyId: string;
  relationship: FamilyProfileRelationship | null;
  members: FamilyProfileMember[];
}

export function EndFamilyRelationshipModal({
  isOpen,
  onClose,
  organizationId,
  familyId,
  relationship,
  members,
}: EndFamilyRelationshipModalProps) {
  const queryClient = useQueryClient();
  const [serverError, setServerError] = useState<string | null>(null);

  const titleId = useId();
  const descId = useId();

  const todayStr = new Date().toISOString().split('T')[0];

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<EndFamilyRelationshipFormValues>({
    resolver: zodResolver(endFamilyRelationshipSchema),
    defaultValues: {
      reason: '',
      effective_to: todayStr,
    },
  });

  const fromMember = members.find((m) => m.member_id === relationship?.from_member_id);
  const toMember = members.find((m) => m.member_id === relationship?.to_member_id);
  const fromName = fromMember?.display_name || 'Member';
  const toName = toMember?.display_name || 'Member';
  const relLabel =
    relationship?.relationship_type.name ||
    relationship?.relationship_type.code
      .replace(/_/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase()) ||
    'Relationship';

  const mutation = useMutation({
    mutationFn: (values: EndFamilyRelationshipFormValues) => {
      if (!relationship) throw new Error('No relationship selected');
      return endFamilyRelationship({
        organizationId,
        relationshipId: relationship.relationship_id,
        effectiveTo: values.effective_to || undefined,
        reason: values.reason,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: familyKeys.profile(organizationId, familyId),
      });
      handleClose();
    },
    onError: (err: unknown) => {
      const errorObj = err as { code?: string; message?: string };
      const rawMessage = errorObj?.message || '';

      if (rawMessage.includes('not currently active')) {
        setServerError('This relationship is not currently active.');
      } else if (rawMessage.includes('current status')) {
        setServerError('Relationship changes are not allowed for this family in its current status.');
      } else if (errorObj?.code === '42501') {
        setServerError('You do not have permission to end relationships in this family.');
      } else if (errorObj?.code === 'P0002') {
        setServerError('Relationship record not found or inaccessible.');
      } else {
        setServerError(rawMessage || 'Failed to end family relationship.');
      }
    },
  });

  function handleClose() {
    reset();
    setServerError(null);
    onClose();
  }

  if (!isOpen || !relationship) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      aria-describedby={descId}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm overflow-y-auto"
    >
      <div className="relative w-full max-w-md rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-5 my-8">
        {/* Header */}
        <div className="flex items-start justify-between border-b border-slate-800 pb-4">
          <div>
            <h2 id={titleId} className="text-lg font-semibold text-slate-100">
              End Family Relationship
            </h2>
            <p id={descId} className="text-xs text-slate-400 mt-0.5">
              Conclude this active relationship record.
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
            aria-label="Close modal"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Relationship Summary Card */}
        <div className="rounded-xl border border-slate-700 bg-slate-800/80 p-4 space-y-2">
          <span className="text-[10px] font-semibold uppercase tracking-wider text-slate-400 block">
            Target Relationship
          </span>
          <div className="flex items-center gap-2 flex-wrap text-sm">
            <span className="font-semibold text-slate-100">{fromName}</span>
            <span className="inline-flex items-center rounded-full border border-indigo-700/60 bg-indigo-950/40 px-2.5 py-0.5 text-xs font-medium text-indigo-300">
              {relLabel}
            </span>
            <span className="font-semibold text-slate-100">{toName}</span>
          </div>
          {!relationship.relationship_type.is_symmetric && (
            <p className="text-[11px] text-slate-400 italic">
              Ending this relationship also concludes its reciprocal link.
            </p>
          )}
        </div>

        {/* Explanatory Banner */}
        <div className="rounded-lg border border-amber-800/50 bg-amber-950/20 p-3.5 flex items-start gap-2.5 text-xs text-amber-300/90">
          <svg className="h-4 w-4 text-amber-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <p>
            This ends the current relationship record. Historical data is preserved. Neither member nor family record is deleted.
          </p>
        </div>

        {/* Server Error Banner */}
        {serverError && (
          <div className="rounded-lg border border-rose-800/80 bg-rose-950/40 p-3.5 flex items-start gap-2.5">
            <svg className="h-5 w-5 text-rose-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <div className="text-xs text-rose-300 space-y-1">
              <p className="font-semibold">Unable to end relationship</p>
              <p>{serverError}</p>
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit((values) => mutation.mutate(values))} className="space-y-4">
          {/* Effective To */}
          <div>
            <label htmlFor="end_rel_effective_to" className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-1.5">
              Effective End Date
            </label>
            <input
              type="date"
              id="end_rel_effective_to"
              max={todayStr}
              {...register('effective_to')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.effective_to && (
              <p className="text-xs text-rose-400 mt-1">{errors.effective_to.message}</p>
            )}
          </div>

          {/* Reason */}
          <div>
            <label htmlFor="end_rel_reason" className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-1.5">
              Reason <span className="text-rose-400">*</span>
            </label>
            <textarea
              id="end_rel_reason"
              rows={3}
              placeholder="e.g. Correction of relationship entry, legal separation, etc."
              {...register('reason')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.reason && (
              <p className="text-xs text-rose-400 mt-1">{errors.reason.message}</p>
            )}
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={handleClose}
              className="rounded-lg border border-slate-700 bg-slate-800 px-4 py-2 text-xs font-medium text-slate-300 hover:bg-slate-700 hover:text-white transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              id="confirm-end-relationship-btn"
              disabled={mutation.isPending}
              className="inline-flex items-center gap-1.5 rounded-lg border border-rose-800/80 bg-rose-950/40 px-4 py-2 text-xs font-medium text-rose-300 shadow-sm hover:bg-rose-900/60 hover:text-rose-200 focus:outline-none focus:ring-2 focus:ring-rose-500 focus:ring-offset-2 focus:ring-offset-slate-900 disabled:opacity-50 transition-colors"
            >
              {mutation.isPending ? 'Ending...' : 'End Relationship'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { repairFamilyRelationshipReciprocal } from '../api/repair-family-relationship-reciprocal';
import { familyKeys } from '../queries';
import {
  repairFamilyRelationshipSchema,
  type RepairFamilyRelationshipFormValues,
} from '../schemas/repair-family-relationship-schema';
import type { FamilyProfileRelationship, FamilyProfileMember } from '../types';

interface RepairFamilyRelationshipModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  familyId: string;
  relationship: FamilyProfileRelationship | null;
  members: FamilyProfileMember[];
}

function formatRelationshipCode(code: string): string {
  if (code === 'parent_of') return 'Parent of';
  if (code === 'child_of') return 'Child of';
  return code.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

export function RepairFamilyRelationshipModal({
  isOpen,
  onClose,
  organizationId,
  familyId,
  relationship,
  members,
}: RepairFamilyRelationshipModalProps) {
  const queryClient = useQueryClient();
  const [serverError, setServerError] = useState<string | null>(null);

  const titleId = useId();
  const descId = useId();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<RepairFamilyRelationshipFormValues>({
    resolver: zodResolver(repairFamilyRelationshipSchema),
    defaultValues: {
      reason: '',
    },
  });

  const fromMember = members.find((m) => m.member_id === relationship?.from_member_id);
  const toMember = members.find((m) => m.member_id === relationship?.to_member_id);
  const fromName = fromMember?.display_name || 'Member';
  const toName = toMember?.display_name || 'Member';

  const relCode = relationship?.relationship_type.code || '';
  const relLabel = relationship?.relationship_type.name || formatRelationshipCode(relCode);

  const inverseCode = relationship?.relationship_type.inverse_code || '';
  const inverseLabel = formatRelationshipCode(inverseCode);

  const mutation = useMutation({
    mutationFn: (values: RepairFamilyRelationshipFormValues) => {
      if (!relationship) throw new Error('No relationship selected');
      return repairFamilyRelationshipReciprocal({
        organizationId,
        relationshipId: relationship.relationship_id,
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

      if (rawMessage.includes('already exists')) {
        setServerError('Reciprocal relationship already exists.');
      } else if (rawMessage.includes('symmetric')) {
        setServerError('Cannot repair reciprocal relationship for symmetric relationship type.');
      } else if (rawMessage.includes('current status')) {
        setServerError('Relationship changes are not allowed for this family in its current status.');
      } else if (errorObj?.code === '42501') {
        setServerError('You do not have permission to repair relationships in this family.');
      } else if (errorObj?.code === 'P0002') {
        setServerError('Relationship record not found or inaccessible.');
      } else {
        setServerError(rawMessage || 'Failed to repair family relationship.');
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
      <div className="relative w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-5 my-8">
        {/* Header */}
        <div className="flex items-start justify-between border-b border-slate-800 pb-4">
          <div>
            <h2 id={titleId} className="text-lg font-semibold text-slate-100">
              Repair Missing Reciprocal Relationship
            </h2>
            <p id={descId} className="text-xs text-slate-400 mt-0.5">
              Restore the required inverse relationship row for this historical entry.
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

        {/* Existing vs Will Add Comparison */}
        <div className="space-y-3">
          {/* Existing */}
          <div className="rounded-xl border border-slate-700 bg-slate-800/80 p-3.5 space-y-1.5">
            <span className="text-[10px] font-semibold uppercase tracking-wider text-slate-400 block">
              Existing
            </span>
            <div className="flex items-center gap-2 flex-wrap text-sm text-slate-200 font-medium">
              <span>{fromName}</span>
              <span className="text-slate-400">—</span>
              <span className="inline-flex items-center rounded-full border border-indigo-700/60 bg-indigo-950/40 px-2.5 py-0.5 text-xs font-semibold text-indigo-300">
                {relLabel}
              </span>
              <span className="text-slate-400">—</span>
              <span>{toName}</span>
            </div>
          </div>

          {/* Will Add */}
          <div className="rounded-xl border border-emerald-800/60 bg-emerald-950/30 p-3.5 space-y-1.5">
            <span className="text-[10px] font-semibold uppercase tracking-wider text-emerald-400 block">
              Will add
            </span>
            <div className="flex items-center gap-2 flex-wrap text-sm text-emerald-100 font-medium">
              <span>{toName}</span>
              <span className="text-emerald-400/60">—</span>
              <span className="inline-flex items-center rounded-full border border-emerald-700/60 bg-emerald-950/60 px-2.5 py-0.5 text-xs font-semibold text-emerald-300">
                {inverseLabel}
              </span>
              <span className="text-emerald-400/60">—</span>
              <span>{fromName}</span>
            </div>
          </div>
        </div>

        {/* Informational Explanation */}
        <div className="rounded-lg border border-indigo-800/50 bg-indigo-950/20 p-3.5 flex items-start gap-2.5 text-xs text-indigo-200">
          <svg className="h-4 w-4 text-indigo-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <p>
            This adds the missing reciprocal relationship required by the current family relationship model. The existing relationship will not be deleted or changed.
          </p>
        </div>

        {/* Server Error Banner */}
        {serverError && (
          <div className="rounded-lg border border-rose-800/80 bg-rose-950/40 p-3.5 flex items-start gap-2.5">
            <svg className="h-5 w-5 text-rose-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <div className="text-xs text-rose-300 space-y-1">
              <p className="font-semibold">Unable to repair relationship</p>
              <p>{serverError}</p>
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit((values) => mutation.mutate(values))} className="space-y-4">
          {/* Reason */}
          <div>
            <label htmlFor="repair_rel_reason" className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-1.5">
              Correction Reason <span className="text-rose-400">*</span>
            </label>
            <textarea
              id="repair_rel_reason"
              rows={3}
              placeholder="e.g. Historical legacy import had missing inverse reciprocal row"
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
              id="confirm-repair-relationship-btn"
              disabled={mutation.isPending}
              className="inline-flex items-center gap-1.5 rounded-lg border border-indigo-700/80 bg-indigo-600 px-4 py-2 text-xs font-medium text-white shadow-sm hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 focus:ring-offset-slate-900 disabled:opacity-50 transition-colors"
            >
              {mutation.isPending ? 'Repairing...' : 'Repair relationship'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

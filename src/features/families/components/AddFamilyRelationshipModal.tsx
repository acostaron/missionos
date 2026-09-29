import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { addFamilyRelationship } from '../api/add-family-relationship';
import { useFamilyRelationshipTypes } from '../api/get-family-relationship-types';
import { familyKeys } from '../queries';
import {
  addFamilyRelationshipSchema,
  type AddFamilyRelationshipFormValues,
} from '../schemas/add-family-relationship-schema';
import type { FamilyProfileMember } from '../types';

interface AddFamilyRelationshipModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  familyId: string;
  familyName: string;
  members: FamilyProfileMember[];
}

export function AddFamilyRelationshipModal({
  isOpen,
  onClose,
  organizationId,
  familyId,
  familyName,
  members,
}: AddFamilyRelationshipModalProps) {
  const queryClient = useQueryClient();
  const [serverError, setServerError] = useState<string | null>(null);

  const titleId = useId();
  const descId = useId();

  // Load relationship types catalog
  const { data: relationshipTypes, isLoading: isLoadingTypes } = useFamilyRelationshipTypes(
    organizationId,
    isOpen
  );

  const todayStr = new Date().toISOString().split('T')[0];

  const {
    register,
    handleSubmit,
    reset,
    watch,
    formState: { errors },
  } = useForm<AddFamilyRelationshipFormValues>({
    resolver: zodResolver(addFamilyRelationshipSchema),
    defaultValues: {
      from_member_id: '',
      to_member_id: '',
      relationship_type_code: '',
      effective_from: todayStr,
    },
  });

  const fromMemberId = watch('from_member_id');
  const toMemberId = watch('to_member_id');
  const relationshipTypeCode = watch('relationship_type_code');

  const selectedType = relationshipTypes?.find((t) => t.code === relationshipTypeCode);
  const fromMember = members.find((m) => m.member_id === fromMemberId);
  const toMember = members.find((m) => m.member_id === toMemberId);

  const mutation = useMutation({
    mutationFn: (values: AddFamilyRelationshipFormValues) =>
      addFamilyRelationship({
        organizationId,
        familyId,
        fromMemberId: values.from_member_id,
        toMemberId: values.to_member_id,
        relationshipTypeCode: values.relationship_type_code,
        effectiveFrom: values.effective_from || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: familyKeys.profile(organizationId, familyId),
      });
      handleClose();
    },
    onError: (err: unknown) => {
      const errorObj = err as { code?: string; message?: string };
      const rawMessage = errorObj?.message || '';

      if (rawMessage.includes('already recorded')) {
        setServerError('This relationship is already recorded.');
      } else if (rawMessage.includes('multiple active spouses')) {
        setServerError('A member cannot have multiple active spouses in the same family.');
      } else if (rawMessage.includes('Both members must currently belong')) {
        setServerError('Both members must currently belong to this family.');
      } else if (rawMessage.includes('current status')) {
        setServerError('Relationship changes are not allowed for this family in its current status.');
      } else if (rawMessage.includes('deceased')) {
        setServerError('Cannot create a family relationship involving a deceased member.');
      } else if (rawMessage.includes('archived')) {
        setServerError('Cannot create a family relationship involving an archived member record.');
      } else if (rawMessage.includes('themselves')) {
        setServerError('A member cannot have a relationship with themselves.');
      } else if (errorObj?.code === '42501') {
        setServerError('You do not have permission to add relationships in this family.');
      } else if (errorObj?.code === 'P0002') {
        setServerError('Family or member record not found or inaccessible.');
      } else {
        setServerError(rawMessage || 'Failed to add family relationship.');
      }
    },
  });

  function handleClose() {
    reset();
    setServerError(null);
    onClose();
  }

  if (!isOpen) return null;

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
              Add Family Relationship
            </h2>
            <p id={descId} className="text-xs text-slate-400 mt-0.5">
              Record an interpersonal relationship within <strong className="text-slate-200">{familyName}</strong>.
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

        {/* Server Error Banner */}
        {serverError && (
          <div className="rounded-lg border border-rose-800/80 bg-rose-950/40 p-3.5 flex items-start gap-2.5">
            <svg className="h-5 w-5 text-rose-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <div className="text-xs text-rose-300 space-y-1">
              <p className="font-semibold">Unable to add relationship</p>
              <p>{serverError}</p>
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit((values) => mutation.mutate(values))} className="space-y-4">
          {/* From Member */}
          <div>
            <label htmlFor="from_member_id" className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-1.5">
              From Member <span className="text-rose-400">*</span>
            </label>
            <select
              id="from_member_id"
              {...register('from_member_id')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              <option value="">Select a family member...</option>
              {members.map((m) => (
                <option key={m.member_id} value={m.member_id}>
                  {m.display_name} {m.family_role ? `(${m.family_role.replace(/_/g, ' ')})` : ''}
                </option>
              ))}
            </select>
            {errors.from_member_id && (
              <p className="text-xs text-rose-400 mt-1">{errors.from_member_id.message}</p>
            )}
          </div>

          {/* Relationship Type */}
          <div>
            <label htmlFor="relationship_type_code" className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-1.5">
              Relationship Type <span className="text-rose-400">*</span>
            </label>
            <select
              id="relationship_type_code"
              {...register('relationship_type_code')}
              disabled={isLoadingTypes}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 disabled:opacity-50"
            >
              <option value="">
                {isLoadingTypes ? 'Loading types...' : 'Select relationship type...'}
              </option>
              {relationshipTypes?.map((t) => (
                <option key={t.type_id} value={t.code}>
                  {t.name}
                </option>
              ))}
            </select>
            {errors.relationship_type_code && (
              <p className="text-xs text-rose-400 mt-1">{errors.relationship_type_code.message}</p>
            )}
            {selectedType?.is_symmetric && (
              <p className="text-[11px] text-sky-400 mt-1 italic">
                Spouse relationships are mutual and recorded as a single canonical pair.
              </p>
            )}
            {selectedType && !selectedType.is_symmetric && selectedType.inverse_code && (
              <p className="text-[11px] text-indigo-400 mt-1 italic">
                Recording this automatically creates the reciprocal relationship ({selectedType.inverse_code.replace(/_/g, ' ')}).
              </p>
            )}
          </div>

          {/* To Member */}
          <div>
            <label htmlFor="to_member_id" className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-1.5">
              To Member <span className="text-rose-400">*</span>
            </label>
            <select
              id="to_member_id"
              {...register('to_member_id')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              <option value="">Select a family member...</option>
              {members.map((m) => (
                <option
                  key={m.member_id}
                  value={m.member_id}
                  disabled={m.member_id === fromMemberId}
                >
                  {m.display_name} {m.family_role ? `(${m.family_role.replace(/_/g, ' ')})` : ''}
                  {m.member_id === fromMemberId ? ' (Cannot be self)' : ''}
                </option>
              ))}
            </select>
            {errors.to_member_id && (
              <p className="text-xs text-rose-400 mt-1">{errors.to_member_id.message}</p>
            )}
          </div>

          {/* Direction Preview */}
          {fromMember && toMember && selectedType && (
            <div className="rounded-lg border border-slate-800 bg-slate-950/60 p-3 space-y-1">
              <span className="text-[10px] font-semibold uppercase tracking-wider text-slate-500 block">
                Relationship Preview
              </span>
              <p className="text-xs text-slate-200 flex items-center gap-1.5 flex-wrap">
                <span className="font-semibold text-slate-100">{fromMember.display_name}</span>
                <span className="inline-flex items-center rounded-full border border-indigo-700/60 bg-indigo-950/40 px-2 py-0.5 text-[11px] font-medium text-indigo-300">
                  {selectedType.name}
                </span>
                <span className="font-semibold text-slate-100">{toMember.display_name}</span>
              </p>
            </div>
          )}

          {/* Effective From */}
          <div>
            <label htmlFor="effective_from" className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-1.5">
              Effective From
            </label>
            <input
              type="date"
              id="effective_from"
              max={todayStr}
              {...register('effective_from')}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.effective_from && (
              <p className="text-xs text-rose-400 mt-1">{errors.effective_from.message}</p>
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
              id="confirm-add-relationship-btn"
              disabled={mutation.isPending}
              className="inline-flex items-center gap-1.5 rounded-lg border border-indigo-600 bg-indigo-600 px-4 py-2 text-xs font-medium text-white shadow-sm hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 focus:ring-offset-slate-900 disabled:opacity-50 transition-colors"
            >
              {mutation.isPending ? 'Adding...' : 'Add Relationship'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

import { useState, useId, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { familyKeys } from '../queries';
import { updateFamilyIdentity } from '../api/update-family-identity';
import { FAMILY_TYPES, type FamilyIdentity } from '../types';
import {
  editFamilySchema,
  type EditFamilyFormValues,
} from '../schemas/edit-family-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface EditFamilyModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  family: FamilyIdentity;
}

export function EditFamilyModal({
  isOpen,
  onClose,
  organizationId,
  family,
}: EditFamilyModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<EditFamilyFormValues>({
    resolver: zodResolver(editFamilySchema),
    defaultValues: {
      display_name: family.display_name || '',
      family_name: family.family_name || '',
      family_type: (family.family_type as EditFamilyFormValues['family_type']) || 'household_family',
      formed_on: family.formed_on || '',
    },
  });

  // Re-sync form when family changes or modal opens
  useEffect(() => {
    if (isOpen) {
      reset({
        display_name: family.display_name || '',
        family_name: family.family_name || '',
        family_type: (family.family_type as EditFamilyFormValues['family_type']) || 'household_family',
        formed_on: family.formed_on || '',
      });
      setErrorMessage(null);
    }
  }, [isOpen, family, reset]);

  const handleClose = () => {
    setErrorMessage(null);
    onClose();
  };

  const onSubmit = async (data: EditFamilyFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await updateFamilyIdentity({
        organizationId,
        familyId: family.id,
        displayName: data.display_name,
        familyName: data.family_name,
        familyType: data.family_type,
        formedOn: data.formed_on?.trim() ? data.formed_on.trim() : null,
      });

      // Invalidate family profile query
      await queryClient.invalidateQueries({
        queryKey: familyKeys.profile(organizationId, family.id),
      });

      // Invalidate member-family summaries so member cards reflect updated family name
      await queryClient.invalidateQueries({
        queryKey: ['members', 'families'],
      });

      handleClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage('You do not have permission to update family records.');
      } else if (normalized.code === '22023') {
        setErrorMessage(normalized.technicalMessage || 'This family record cannot be edited in its current status.');
      } else if (normalized.code === '23502') {
        setErrorMessage('Required family information is missing.');
      } else if (normalized.code === 'P0002') {
        setErrorMessage('Family record not found or unavailable.');
      } else {
        setErrorMessage(normalized.message || 'Failed to update family identity.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm overflow-y-auto"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-5">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="space-y-1">
            <h2 id={titleId} className="text-lg font-semibold text-slate-100 flex items-center gap-2">
              <svg className="h-5 w-5 text-indigo-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
              </svg>
              Edit Family Identity
            </h2>
            <p className="text-xs text-slate-400">
              Update identity information for <span className="font-medium text-slate-200">{family.display_name}</span>.
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            disabled={isSubmitting}
            aria-label="Close"
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Error message */}
        {errorMessage && (
          <div className="rounded-lg border border-red-500/40 bg-red-950/40 p-3 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* Display Name */}
          <div className="space-y-1">
            <label htmlFor="edit-family-display-name" className="block text-xs font-medium text-slate-300">
              Display name <span className="text-red-400">*</span>
            </label>
            <input
              {...register('display_name')}
              id="edit-family-display-name"
              disabled={isSubmitting}
              type="text"
              placeholder="e.g. Acosta Family"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
            />
            <p className="text-[11px] text-slate-500">
              Shown in MissionOS, e.g. Acosta Family
            </p>
            {errors.display_name && (
              <p className="text-xs text-red-400">{errors.display_name.message}</p>
            )}
          </div>

          {/* Family Name */}
          <div className="space-y-1">
            <label htmlFor="edit-family-name" className="block text-xs font-medium text-slate-300">
              Family name <span className="text-red-400">*</span>
            </label>
            <input
              {...register('family_name')}
              id="edit-family-name"
              disabled={isSubmitting}
              type="text"
              placeholder="e.g. Acosta"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
            />
            <p className="text-[11px] text-slate-500">
              Family identity/surname label, e.g. Acosta
            </p>
            {errors.family_name && (
              <p className="text-xs text-red-400">{errors.family_name.message}</p>
            )}
          </div>

          {/* Family Type */}
          <div className="space-y-1">
            <label htmlFor="edit-family-type" className="block text-xs font-medium text-slate-300">
              Family type
            </label>
            <select
              {...register('family_type')}
              id="edit-family-type"
              disabled={isSubmitting}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
            >
              {FAMILY_TYPES.map((type) => (
                <option key={type.value} value={type.value}>
                  {type.label}
                </option>
              ))}
            </select>
          </div>

          {/* Formed On */}
          <div className="space-y-1">
            <label htmlFor="edit-family-formed-on" className="block text-xs font-medium text-slate-300">
              Formed on <span className="text-slate-500 font-normal">(optional)</span>
            </label>
            <input
              {...register('formed_on')}
              id="edit-family-formed-on"
              disabled={isSubmitting}
              type="date"
              max={new Date().toISOString().split('T')[0]}
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none"
            />
            {errors.formed_on && (
              <p className="text-xs text-red-400">{errors.formed_on.message}</p>
            )}
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-800">
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
              disabled={isSubmitting}
              id="submit-edit-family-button"
              className="inline-flex items-center gap-1.5 rounded-lg bg-indigo-600 px-4 py-2 text-xs font-semibold text-white hover:bg-indigo-500 disabled:opacity-50 transition-colors shadow-sm"
            >
              {isSubmitting ? (
                <>
                  <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                  </svg>
                  Saving...
                </>
              ) : (
                'Save Changes'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

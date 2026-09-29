import { useState, useId } from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { familyKeys } from '../queries';
import { createFamily } from '../api/create-family';
import { FAMILY_TYPES, type CreateFamilyWarningResponse } from '../types';
import {
  createFamilySchema,
  type CreateFamilyFormValues,
} from '../schemas/create-family-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface CreateFamilyModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
}

export function CreateFamilyModal({
  isOpen,
  onClose,
  organizationId,
}: CreateFamilyModalProps) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [warningData, setWarningData] = useState<CreateFamilyWarningResponse | null>(null);

  const titleId = useId();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<CreateFamilyFormValues>({
    resolver: zodResolver(createFamilySchema),
    defaultValues: {
      display_name: '',
      family_name: '',
      family_type: 'household_family',
      formed_on: '',
    },
  });

  const handleClose = () => {
    reset();
    setErrorMessage(null);
    setWarningData(null);
    onClose();
  };

  const executeCreate = async (
    data: CreateFamilyFormValues,
    confirmDuplicate: boolean = false
  ) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const res = await createFamily({
        organizationId,
        displayName: data.display_name,
        familyName: data.family_name,
        familyType: data.family_type,
        formedOn: data.formed_on || null,
        confirmDuplicate,
      });

      if (res.status === 'warning') {
        setWarningData(res);
        return;
      }

      // Success
      await queryClient.invalidateQueries({
        queryKey: familyKeys.all,
      });

      handleClose();
      navigate(`/app/families/${res.family_id}`);
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage('You do not have permission to create family records.');
      } else if (normalized.code === '22023') {
        setErrorMessage(normalized.technicalMessage || 'Invalid family information provided.');
      } else if (normalized.code === '23502') {
        setErrorMessage('Required family information is missing.');
      } else {
        setErrorMessage(normalized.message || 'Failed to create family record.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const onSubmit = (data: CreateFamilyFormValues) => {
    executeCreate(data, false);
  };

  const onConfirmDuplicate = (data: CreateFamilyFormValues) => {
    executeCreate(data, true);
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
                <path strokeLinecap="round" strokeLinejoin="round" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
              </svg>
              Create Family
            </h2>
            <p className="text-xs text-slate-400">
              Create a new family identity record in the organization.
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

        {/* Informational Callout */}
        <div className="rounded-xl border border-indigo-900/40 bg-indigo-950/20 p-3.5 text-xs text-indigo-300">
          <p className="leading-relaxed">
            This creates the family entity record. Members can be added to this family in a later step.
          </p>
        </div>

        {/* Error message */}
        {errorMessage && (
          <div className="rounded-lg border border-red-500/40 bg-red-950/40 p-3 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        {/* Duplicate Warning Panel */}
        {warningData && (
          <div className="rounded-xl border border-amber-800/60 bg-amber-950/30 p-4 space-y-3 text-xs text-amber-200">
            <div className="flex items-start gap-2.5">
              <svg className="h-4 w-4 shrink-0 text-amber-400 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <div className="space-y-1">
                <p className="font-semibold text-amber-100">
                  A similar family record already exists. Confirm only if this is a separate family.
                </p>
                <p className="text-amber-300/80">
                  {warningData.warning_count} matching {warningData.warning_count === 1 ? 'record' : 'records'} found in this organization:
                </p>
              </div>
            </div>

            <div className="max-h-36 overflow-y-auto space-y-1.5 rounded-lg border border-amber-900/40 bg-slate-900/60 p-2.5">
              {warningData.warnings.map((match) => (
                <div key={match.family_id} className="flex items-center justify-between text-[11px] text-slate-300 py-0.5 border-b border-slate-800/60 last:border-0">
                  <span className="font-medium text-slate-100">{match.display_name} ({match.family_name})</span>
                  <div className="flex items-center gap-2 text-slate-400">
                    <span className="capitalize">{match.family_status}</span>
                    {match.formed_on && <span>· Formed {match.formed_on}</span>}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit(warningData ? onConfirmDuplicate : onSubmit)} className="space-y-4">
          {/* Display Name */}
          <div className="space-y-1">
            <label htmlFor="create-family-display-name" className="block text-xs font-medium text-slate-300">
              Display name <span className="text-red-400">*</span>
            </label>
            <input
              {...register('display_name')}
              id="create-family-display-name"
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
            <label htmlFor="create-family-name" className="block text-xs font-medium text-slate-300">
              Family name <span className="text-red-400">*</span>
            </label>
            <input
              {...register('family_name')}
              id="create-family-name"
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
            <label htmlFor="create-family-type" className="block text-xs font-medium text-slate-300">
              Family type
            </label>
            <select
              {...register('family_type')}
              id="create-family-type"
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
            <label htmlFor="create-family-formed-on" className="block text-xs font-medium text-slate-300">
              Formed on <span className="text-slate-500 font-normal">(optional)</span>
            </label>
            <input
              {...register('formed_on')}
              id="create-family-formed-on"
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
            {warningData ? (
              <button
                type="submit"
                disabled={isSubmitting}
                id="confirm-create-family-button"
                className="inline-flex items-center gap-1.5 rounded-lg bg-amber-600 px-4 py-2 text-xs font-semibold text-white hover:bg-amber-500 disabled:opacity-50 transition-colors shadow-sm"
              >
                {isSubmitting ? 'Creating anyway...' : 'Create anyway'}
              </button>
            ) : (
              <button
                type="submit"
                disabled={isSubmitting}
                id="submit-create-family-button"
                className="inline-flex items-center gap-1.5 rounded-lg bg-indigo-600 px-4 py-2 text-xs font-semibold text-white hover:bg-indigo-500 disabled:opacity-50 transition-colors shadow-sm"
              >
                {isSubmitting ? (
                  <>
                    <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                    </svg>
                    Creating...
                  </>
                ) : (
                  'Create Family'
                )}
              </button>
            )}
          </div>
        </form>
      </div>
    </div>
  );
}

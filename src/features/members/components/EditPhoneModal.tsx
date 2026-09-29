import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys } from '../queries';
import { setMemberContactPoint } from '../api/set-member-contact-point';
import {
  phoneSchema,
  COUNTRY_OPTIONS,
  type PhoneFormData,
} from './contact-schemas';
import { normalizeError } from '../../../lib/supabase/errors';

interface EditPhoneModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  mode: 'add' | 'replace';
  existingRawPhone?: string | null;
  hasExistingPrimary: boolean;
  onSuccessToast?: (msg: string) => void;
}

export function EditPhoneModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  mode,
  existingRawPhone,
  hasExistingPrimary,
  onSuccessToast,
}: EditPhoneModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const isReplace = mode === 'replace';

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<PhoneFormData>({
    resolver: zodResolver(phoneSchema),
    defaultValues: {
      countryCode: isReplace ? '' : 'US',
      phoneNumber: isReplace && existingRawPhone ? existingRawPhone : '',
      setAsPrimary: isReplace ? true : !hasExistingPrimary,
    },
  });

  if (!isOpen) return null;

  const onSubmit = async (data: PhoneFormData) => {
    setIsSubmitting(true);
    setErrorMessage(null);

    const operation = isReplace || data.setAsPrimary ? 'replace_primary' : 'add';

    try {
      await setMemberContactPoint({
        organizationId,
        memberId,
        contactType: 'phone',
        operation,
        value: data.phoneNumber,
        phoneCountryCode: data.countryCode, // 2-letter ISO code e.g. 'US'
      });

      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, memberId),
      });

      if (onSuccessToast) {
        onSuccessToast(
          isReplace || data.setAsPrimary
            ? 'Primary phone updated.'
            : 'Phone added.'
        );
      }

      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage(
          'Access denied: You do not have permission to manage member contacts.'
        );
      } else if (normalized.code === '22023') {
        setErrorMessage(
          normalized.message || 'Invalid phone format or operation.'
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
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 p-4 backdrop-blur-sm"
    >
      <div className="w-full max-w-md rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-5">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-3">
          <h2 id={titleId} className="text-lg font-bold tracking-tight text-slate-100">
            {isReplace ? 'Replace Primary Phone' : 'Add Phone'}
          </h2>
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

        {isReplace && (
          <div className="rounded-lg border border-indigo-900/40 bg-indigo-950/30 p-3 text-xs text-indigo-300">
            The previous primary phone will be retained in contact history.
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div>
            <label htmlFor="phoneNumber" className="block text-xs font-medium text-slate-300">
              Phone Number <span className="text-rose-400">*</span>
            </label>
            <div className="mt-1 flex gap-2">
              <select
                id="countryCode"
                {...register('countryCode')}
                className="w-40 rounded-lg border border-slate-700 bg-slate-800 px-2 py-2 text-xs text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              >
                <option value="">Select country</option>
                {COUNTRY_OPTIONS.map((opt) => (
                  <option key={opt.code} value={opt.code}>
                    {opt.name}
                  </option>
                ))}
              </select>
              <input
                id="phoneNumber"
                type="tel"
                autoFocus
                {...register('phoneNumber')}
                placeholder="212-555-0199"
                className="block w-full flex-1 rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
            </div>
            {errors.countryCode && (
              <p className="mt-1 text-xs text-rose-400">{errors.countryCode.message}</p>
            )}
            {errors.phoneNumber && (
              <p className="mt-1 text-xs text-rose-400">{errors.phoneNumber.message}</p>
            )}
            <p className="mt-1 text-[11px] text-slate-500">
              Enter the number as normally written. MissionOS will normalize it when possible.
            </p>
          </div>


          {!isReplace && (
            <label className="flex items-center gap-2 cursor-pointer pt-1">
              <input
                type="checkbox"
                {...register('setAsPrimary')}
                className="h-4 w-4 rounded border-slate-700 bg-slate-800 text-indigo-600 focus:ring-indigo-500"
              />
              <span className="text-xs text-slate-300">
                Set as primary phone
              </span>
            </label>
          )}

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
              disabled={isSubmitting}
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
              ) : isReplace ? (
                'Replace Primary'
              ) : (
                'Add Phone'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

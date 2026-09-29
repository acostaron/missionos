import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys, type MemberAddress } from '../queries';
import { setMemberContactPoint } from '../api/set-member-contact-point';
import {
  addressSchema,
  ADDRESS_COUNTRY_OPTIONS,
  type AddressFormData,
} from './contact-schemas';
import { normalizeError } from '../../../lib/supabase/errors';

interface EditAddressModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  existingPrimaryAddress?: MemberAddress | null;
  onSuccessToast?: (msg: string) => void;
}

export function EditAddressModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  existingPrimaryAddress,
  onSuccessToast,
}: EditAddressModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const isReplace = !!existingPrimaryAddress;

  const currentAddr = existingPrimaryAddress?.address;

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<AddressFormData>({
    resolver: zodResolver(addressSchema),
    defaultValues: {
      line1: currentAddr?.address_line_1 ?? '',
      line2: currentAddr?.address_line_2 ?? '',
      city: currentAddr?.city_name ?? '',
      state: currentAddr?.state_province_name ?? '',
      postal: currentAddr?.postal_code ?? '',
      country: currentAddr?.country_code ?? 'US',
      effectiveDate: new Date().toISOString().split('T')[0],
    },
  });

  if (!isOpen) return null;

  const onSubmit = async (data: AddressFormData) => {
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      await setMemberContactPoint({
        organizationId,
        memberId,
        contactType: 'address',
        operation: 'replace_primary', // Both initial add and replacement use replace_primary
        addressData: {
          line1: data.line1,
          line2: data.line2,
          city: data.city,
          state: data.state,
          postal: data.postal,
          country: data.country,
        },
        effectiveFrom: data.effectiveDate,
      });

      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, memberId),
      });

      if (onSuccessToast) {
        onSuccessToast(
          isReplace
            ? 'Residential address replaced.'
            : 'Residential address added.'
        );
      }

      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage(
          'Access denied: You do not have permission to manage member addresses.'
        );
      } else if (normalized.code === '22023') {
        setErrorMessage(
          normalized.message || 'Invalid address input or date sequencing.'
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
      <div className="w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-5 my-8">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-3">
          <h2 id={titleId} className="text-lg font-bold tracking-tight text-slate-100">
            {isReplace ? 'Replace Residential Address' : 'Add Residential Address'}
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

        {/* Notice for replacement */}
        {isReplace && (
          <div className="rounded-lg border border-indigo-900/40 bg-indigo-950/30 p-3 text-xs text-indigo-300">
            Replacing this address preserves the previous address in the member&apos;s history.
          </div>
        )}

        {/* Global Error Banner */}
        {errorMessage && (
          <div className="rounded-xl border border-red-700 bg-red-900/30 p-3 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div>
            <label htmlFor="line1" className="block text-xs font-medium text-slate-300">
              Street Address (Line 1) <span className="text-rose-400">*</span>
            </label>
            <input
              id="line1"
              type="text"
              autoFocus
              {...register('line1')}
              placeholder="123 Main St"
              className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.line1 && (
              <p className="mt-1 text-xs text-rose-400">{errors.line1.message}</p>
            )}
          </div>

          <div>
            <label htmlFor="line2" className="block text-xs font-medium text-slate-300">
              Apartment, Suite, Unit (Line 2) <span className="text-slate-500">(optional)</span>
            </label>
            <input
              id="line2"
              type="text"
              {...register('line2')}
              placeholder="Apt 4B"
              className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="city" className="block text-xs font-medium text-slate-300">
                City <span className="text-rose-400">*</span>
              </label>
              <input
                id="city"
                type="text"
                {...register('city')}
                placeholder="New York"
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
              {errors.city && (
                <p className="mt-1 text-xs text-rose-400">{errors.city.message}</p>
              )}
            </div>

            <div>
              <label htmlFor="state" className="block text-xs font-medium text-slate-300">
                State / Province <span className="text-slate-500">(optional)</span>
              </label>
              <input
                id="state"
                type="text"
                {...register('state')}
                placeholder="NY"
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="postal" className="block text-xs font-medium text-slate-300">
                Postal Code <span className="text-slate-500">(optional)</span>
              </label>
              <input
                id="postal"
                type="text"
                {...register('postal')}
                placeholder="10001"
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
            </div>

            <div>
              <label htmlFor="country" className="block text-xs font-medium text-slate-300">
                Country
              </label>
              <select
                id="country"
                {...register('country')}
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              >
                {ADDRESS_COUNTRY_OPTIONS.map((opt) => (
                  <option key={opt.code} value={opt.code}>
                    {opt.name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div>
            <label htmlFor="effectiveDate" className="block text-xs font-medium text-slate-300">
              Effective Date <span className="text-rose-400">*</span>
            </label>
            <input
              id="effectiveDate"
              type="date"
              {...register('effectiveDate')}
              className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.effectiveDate && (
              <p className="mt-1 text-xs text-rose-400">{errors.effectiveDate.message}</p>
            )}
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
                'Replace Address'
              ) : (
                'Add Address'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

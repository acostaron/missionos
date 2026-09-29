import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys } from '../queries';
import { setMemberContactPoint } from '../api/set-member-contact-point';
import { emailSchema, type EmailFormData } from './contact-schemas';
import { normalizeError } from '../../../lib/supabase/errors';

interface EditEmailModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  mode: 'add' | 'replace';
  existingEmail?: string | null;
  hasExistingPrimary: boolean;
  onSuccessToast?: (msg: string) => void;
}

export function EditEmailModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  mode,
  existingEmail,
  hasExistingPrimary,
  onSuccessToast,
}: EditEmailModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const isReplace = mode === 'replace';

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<EmailFormData>({
    resolver: zodResolver(emailSchema),
    defaultValues: {
      email: isReplace && existingEmail ? existingEmail : '',
      // If replacing, it's always replacing primary.
      // If adding: default true if no primary exists yet, else false.
      setAsPrimary: isReplace ? true : !hasExistingPrimary,
    },
  });

  if (!isOpen) return null;

  const onSubmit = async (data: EmailFormData) => {
    setIsSubmitting(true);
    setErrorMessage(null);

    const operation = isReplace || data.setAsPrimary ? 'replace_primary' : 'add';

    try {
      await setMemberContactPoint({
        organizationId,
        memberId,
        contactType: 'email',
        operation,
        value: data.email,
      });

      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, memberId),
      });

      if (onSuccessToast) {
        onSuccessToast(
          isReplace || data.setAsPrimary
            ? 'Primary email updated.'
            : 'Email added.'
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
          normalized.message || 'Invalid email format or operation.'
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
            {isReplace ? 'Replace Primary Email' : 'Add Email'}
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
            The previous primary email will be retained in contact history.
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div>
            <label htmlFor="email" className="block text-xs font-medium text-slate-300">
              Email Address <span className="text-rose-400">*</span>
            </label>
            <input
              id="email"
              type="email"
              autoFocus
              {...register('email')}
              placeholder="name@example.com"
              className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            {errors.email && (
              <p className="mt-1 text-xs text-rose-400">{errors.email.message}</p>
            )}
          </div>

          {!isReplace && (
            <label className="flex items-center gap-2 cursor-pointer pt-1">
              <input
                type="checkbox"
                {...register('setAsPrimary')}
                className="h-4 w-4 rounded border-slate-700 bg-slate-800 text-indigo-600 focus:ring-indigo-500"
              />
              <span className="text-xs text-slate-300">
                Set as primary email
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
                'Add Email'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

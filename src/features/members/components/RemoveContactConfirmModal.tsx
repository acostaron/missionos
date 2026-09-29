import { useState, useId } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys } from '../queries';
import { setMemberContactPoint } from '../api/set-member-contact-point';
import { normalizeError } from '../../../lib/supabase/errors';

export type RemoveTargetType = 'email' | 'phone' | 'address';

interface RemoveContactConfirmModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  contactType: RemoveTargetType;
  targetId: string;
  label: string;
  isPrimary: boolean;
  hasSecondaryContacts: boolean;
  onSuccessToast?: (msg: string) => void;
}

export function RemoveContactConfirmModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  contactType,
  targetId,
  label,
  isPrimary,
  hasSecondaryContacts,
  onSuccessToast,
}: RemoveContactConfirmModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();

  if (!isOpen) return null;

  const getQuestion = () => {
    switch (contactType) {
      case 'email':
        return "Remove this email from the member's active contact information?";
      case 'phone':
        return "Remove this phone number from the member's active contact information?";
      case 'address':
        return "Remove this residential address from the member's active profile?";
    }
  };

  const getSuccessMessage = () => {
    switch (contactType) {
      case 'email':
        return isPrimary ? 'Primary email removed.' : 'Email removed.';
      case 'phone':
        return isPrimary ? 'Primary phone removed.' : 'Phone removed.';
      case 'address':
        return 'Residential address removed.';
    }
  };

  const onConfirm = async () => {
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      await setMemberContactPoint({
        organizationId,
        memberId,
        contactType,
        operation: 'remove',
        targetId,
      });

      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, memberId),
      });

      if (onSuccessToast) {
        onSuccessToast(getSuccessMessage());
      }

      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage(
          'Access denied: You do not have permission to remove this contact.'
        );
      } else if (normalized.code === '22023') {
        setErrorMessage(
          normalized.message || 'Invalid removal operation or target ID.'
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
            Confirm Removal
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

        <div className="space-y-3">
          <p className="text-sm font-medium text-slate-200">
            {getQuestion()}
          </p>

          <div className="rounded-lg border border-slate-800 bg-slate-800/40 px-3 py-2 text-xs font-mono text-slate-300">
            {label}
          </div>

          <p className="text-xs text-slate-400 leading-relaxed">
            This preserves the historical record; it does not permanently delete it.
          </p>

          {/* Primary removal warning */}
          {isPrimary && (contactType === 'email' || contactType === 'phone') && hasSecondaryContacts && (
            <div className="rounded-lg border border-amber-600/40 bg-amber-950/30 p-3 text-xs text-amber-300">
              <span className="font-semibold block mb-0.5">Warning:</span>
              This is the current primary contact. Removing it will leave the member without a primary {contactType} until another contact is made primary.
            </div>
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
            type="button"
            onClick={onConfirm}
            disabled={isSubmitting}
            className="inline-flex items-center justify-center rounded-lg bg-rose-600 px-4 py-2 text-xs font-medium text-white hover:bg-rose-500 transition-colors shadow-sm disabled:opacity-50"
          >
            {isSubmitting ? (
              <>
                <svg className="mr-2 h-3.5 w-3.5 animate-spin text-white" viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                </svg>
                Removing…
              </>
            ) : (
              'Confirm Remove'
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

import { useState, useId, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { familyKeys } from '../queries';
import { updateFamilyMember } from '../api/update-family-member';
import {
  FAMILY_ROLES,
  type FamilyProfileMember,
} from '../types';
import {
  editFamilyMemberSchema,
  type EditFamilyMemberFormValues,
} from '../schemas/edit-family-member-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface EditFamilyMemberModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  familyId: string;
  member: FamilyProfileMember | null;
}

export function EditFamilyMemberModal({
  isOpen,
  onClose,
  organizationId,
  familyId,
  member,
}: EditFamilyMemberModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();

  const {
    register,
    handleSubmit,
    reset,
  } = useForm<EditFamilyMemberFormValues>({
    resolver: zodResolver(editFamilyMemberSchema),
    defaultValues: {
      family_role: member?.family_role || '',
      is_primary_contact: member?.is_primary_contact || false,
      is_dependent: member?.is_dependent || false,
    },
  });

  // Keep form values in sync when selected member changes
  useEffect(() => {
    if (member) {
      reset({
        family_role: member.family_role || '',
        is_primary_contact: member.is_primary_contact || false,
        is_dependent: member.is_dependent || false,
      });
    }
  }, [member, reset]);

  const handleClose = () => {
    setErrorMessage(null);
    onClose();
  };

  const executeUpdate = async (data: EditFamilyMemberFormValues) => {
    if (!member) return;

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await updateFamilyMember({
        organizationId,
        familyMemberId: member.family_member_id,
        familyRole: data.family_role || null,
        isPrimaryContact: data.is_primary_contact,
        isDependent: data.is_dependent,
      });

      // Invalidate family profile & member-family summaries
      await queryClient.invalidateQueries({
        queryKey: familyKeys.profile(organizationId, familyId),
      });
      await queryClient.invalidateQueries({
        queryKey: ['members', 'families'],
      });

      handleClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage('You do not have permission to update family members.');
      } else if (normalized.code === '22023') {
        const msg = normalized.technicalMessage || '';
        if (msg.includes('status')) {
          setErrorMessage('Membership changes are not allowed for this family in its current status.');
        } else if (msg.includes('Only active family memberships')) {
          setErrorMessage('Only active family memberships can be edited.');
        } else {
          setErrorMessage(msg || 'Invalid membership update information provided.');
        }
      } else if (normalized.code === 'P0002') {
        setErrorMessage('Family membership was not found or is not accessible.');
      } else {
        setErrorMessage(normalized.message || 'Failed to update family membership.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isOpen || !member) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-md bg-white dark:bg-slate-900 rounded-xl shadow-2xl border border-slate-200 dark:border-slate-800 overflow-hidden flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 dark:border-slate-800 flex items-center justify-between">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-900 dark:text-white">
              Edit Membership
            </h2>
            <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
              Member: <span className="font-semibold text-slate-700 dark:text-slate-300">{member.display_name}</span>
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="p-1 rounded-lg text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
            aria-label="Close"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Content Body */}
        <div className="p-6 space-y-4">
          {/* Error Banner */}
          {errorMessage && (
            <div className="p-3 bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-900/50 rounded-lg text-sm text-red-700 dark:text-red-300 flex items-start gap-2">
              <svg className="w-4 h-4 mt-0.5 shrink-0 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>{errorMessage}</span>
            </div>
          )}

          {/* Form */}
          <form id="edit-family-member-form" onSubmit={handleSubmit(executeUpdate)} className="space-y-4">
            {/* Family Role */}
            <div>
              <label htmlFor="edit-family-role-select" className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1">
                Family Role
              </label>
              <select
                id="edit-family-role-select"
                {...register('family_role')}
                className="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-700 rounded-lg text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">None / Unspecified</option>
                {FAMILY_ROLES.map((role) => (
                  <option key={role.value} value={role.value}>
                    {role.label}
                  </option>
                ))}
              </select>
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
                Administrative descriptor only; does not affect family relationships.
              </p>
            </div>

            {/* Flags: Primary Contact & Dependent */}
            <div className="space-y-2.5 pt-1">
              <label className="flex items-start gap-2.5 p-3 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800/50 cursor-pointer transition-colors">
                <input
                  type="checkbox"
                  {...register('is_primary_contact')}
                  className="mt-0.5 rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                />
                <div>
                  <span className="text-xs font-semibold text-slate-800 dark:text-slate-200 block">
                    Primary Contact
                  </span>
                  <span className="text-[11px] text-slate-500 dark:text-slate-400">
                    Family administrative point of contact
                  </span>
                </div>
              </label>

              <label className="flex items-start gap-2.5 p-3 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800/50 cursor-pointer transition-colors">
                <input
                  type="checkbox"
                  {...register('is_dependent')}
                  className="mt-0.5 rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                />
                <div>
                  <span className="text-xs font-semibold text-slate-800 dark:text-slate-200 block">
                    Dependent
                  </span>
                  <span className="text-[11px] text-slate-500 dark:text-slate-400">
                    Mark as household or tax dependent
                  </span>
                </div>
              </label>
            </div>
          </form>
        </div>

        {/* Footer Actions */}
        <div className="px-6 py-4 border-t border-slate-100 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-900/50 flex items-center justify-end gap-3">
          <button
            type="button"
            onClick={handleClose}
            disabled={isSubmitting}
            className="px-4 py-2 text-xs font-medium text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-lg transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            form="edit-family-member-form"
            disabled={isSubmitting}
            className="px-4 py-2 text-xs font-medium bg-blue-600 hover:bg-blue-700 text-white rounded-lg shadow-sm transition-colors disabled:opacity-50 flex items-center gap-1.5"
          >
            {isSubmitting ? (
              <>
                <svg className="animate-spin w-3.5 h-3.5" viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
                <span>Saving...</span>
              </>
            ) : (
              'Save Changes'
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

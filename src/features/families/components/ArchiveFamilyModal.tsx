import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { familyKeys } from '../queries';
import { archiveFamilyRecord } from '../api/archive-family-record';
import type { ArchiveFamilyWarningResponse } from '../types';
import {
  archiveFamilySchema,
  type ArchiveFamilyFormValues,
} from '../schemas/archive-family-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface ArchiveFamilyModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  familyId: string;
  familyName: string;
}

export function ArchiveFamilyModal({
  isOpen,
  onClose,
  organizationId,
  familyId,
  familyName,
}: ArchiveFamilyModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [warningData, setWarningData] = useState<ArchiveFamilyWarningResponse | null>(null);

  const titleId = useId();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<ArchiveFamilyFormValues>({
    resolver: zodResolver(archiveFamilySchema),
    defaultValues: {
      reason: '',
    },
  });

  const handleClose = () => {
    reset();
    setErrorMessage(null);
    setWarningData(null);
    onClose();
  };

  const executeArchive = async (
    data: ArchiveFamilyFormValues,
    confirmWithActiveMembers: boolean = false
  ) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const res = await archiveFamilyRecord({
        organizationId,
        familyId,
        reason: data.reason,
        confirmWithActiveMembers,
      });

      if (res.status === 'warning') {
        setWarningData(res);
        return;
      }

      // Invalidate family profile and member family summaries
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
        setErrorMessage('You do not have permission to archive family records.');
      } else if (normalized.code === '22023') {
        setErrorMessage(normalized.technicalMessage || 'This family record cannot be archived in its current status.');
      } else if (normalized.code === '23502') {
        setErrorMessage('An archive reason is required.');
      } else if (normalized.code === 'P0002') {
        setErrorMessage('Family record not found or unavailable.');
      } else {
        setErrorMessage(normalized.message || 'Failed to archive family record.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const onSubmit = (data: ArchiveFamilyFormValues) => {
    executeArchive(data, false);
  };

  const onConfirmWarning = (data: ArchiveFamilyFormValues) => {
    executeArchive(data, true);
  };

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm overflow-y-auto"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-lg rounded-2xl border border-rose-900/60 bg-slate-900 p-6 shadow-2xl space-y-5">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="space-y-1">
            <h2 id={titleId} className="text-lg font-semibold text-slate-100 flex items-center gap-2">
              <span className="text-rose-400">
                <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
                </svg>
              </span>
              Archive Family Record
            </h2>
            <p className="text-xs text-slate-400">
              Archiving record for <span className="font-medium text-slate-200">{familyName}</span>
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

        {/* Informational Callout */}
        <div className="rounded-xl border border-slate-700/80 bg-slate-800/60 p-4 space-y-2 text-xs text-slate-300">
          <p className="font-medium text-slate-200">
            Archiving marks this family historical while preserving all existing relational data:
          </p>
          <ul className="text-slate-400 space-y-1 list-disc pl-4 leading-relaxed">
            <li>Marks the family record historical and records the conclusion date</li>
            <li>Removes the family from active member-profile cards</li>
            <li>Preserves all linked family members and historical relationships</li>
            <li>Does not alter member statuses, governance, or household assignments</li>
          </ul>
        </div>

        {/* Active-Member Warning Panel */}
        {warningData && (
          <div className="rounded-xl border border-amber-800/60 bg-amber-950/30 p-4 space-y-2.5 text-xs text-amber-200">
            <div className="flex items-start gap-2.5">
              <svg className="h-4 w-4 shrink-0 text-amber-400 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <div className="space-y-1">
                <span className="font-semibold text-amber-100">Active Member Links Present:</span>
                <p className="text-amber-300/90 leading-relaxed">
                  This family currently has <span className="font-semibold text-amber-100">{warningData.active_member_count} active {warningData.active_member_count === 1 ? 'member' : 'members'}</span> and {warningData.active_relationship_count} active {warningData.active_relationship_count === 1 ? 'relationship' : 'relationships'}. Archiving will preserve those links for history, but the family will no longer appear as a current family record.
                </p>
              </div>
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit(warningData ? onConfirmWarning : onSubmit)} className="space-y-4">
          {/* Reason */}
          <div className="space-y-1.5">
            <label htmlFor="archive-family-reason" className="block text-xs font-medium text-slate-300">
              Administrative reason <span className="text-red-400">*</span>
            </label>
            <textarea
              {...register('reason')}
              id="archive-family-reason"
              disabled={isSubmitting}
              rows={3}
              placeholder="e.g. Administrative re-organization, household dissolution, or records reconciliation"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs text-slate-200 focus:border-indigo-500 focus:outline-none resize-none"
            />
            {errors.reason && (
              <p className="text-xs text-red-400">{errors.reason.message}</p>
            )}
          </div>

          {/* Action buttons */}
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
                id="confirm-archive-family-button"
                className="inline-flex items-center gap-1.5 rounded-lg bg-rose-700 px-4 py-2 text-xs font-semibold text-white hover:bg-rose-600 disabled:opacity-50 transition-colors shadow-sm"
              >
                {isSubmitting ? 'Archiving anyway...' : 'Archive anyway'}
              </button>
            ) : (
              <button
                type="submit"
                disabled={isSubmitting}
                id="submit-archive-family-button"
                className="inline-flex items-center gap-1.5 rounded-lg bg-rose-700 px-4 py-2 text-xs font-semibold text-white hover:bg-rose-600 disabled:opacity-50 transition-colors shadow-sm"
              >
                {isSubmitting ? (
                  <>
                    <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                    </svg>
                    Archiving...
                  </>
                ) : (
                  'Archive Family'
                )}
              </button>
            )}
          </div>
        </form>
      </div>
    </div>
  );
}

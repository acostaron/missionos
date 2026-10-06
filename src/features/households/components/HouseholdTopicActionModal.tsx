import { useState, useId, useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { rescheduleHouseholdTopic } from '../api/reschedule-household-topic';
import { skipHouseholdTopic } from '../api/skip-household-topic';
import { cancelHouseholdTopicAssignment } from '../api/cancel-household-topic-assignment';
import { invalidateFormationQueries, REASON_CODE_OPTIONS } from './formation-labels';
import { normalizeError } from '../../../lib/supabase/errors';
import type { HouseholdTopicReasonCode } from '../types';

export type HouseholdTopicActionMode = 'reschedule' | 'skip' | 'cancel';

interface HouseholdTopicActionModalProps {
  isOpen: boolean;
  onClose: () => void;
  mode: HouseholdTopicActionMode;
  organizationId: string;
  householdName: string;
  assignmentId: string;
  topicTitle: string;
  currentPlannedDate?: string | null;
  onSuccessToast?: (msg: string) => void;
}

const COPY: Record<HouseholdTopicActionMode, { title: string; submit: string; busy: string; done: string }> = {
  reschedule: { title: 'Reschedule Topic', submit: 'Reschedule', busy: 'Saving…', done: 'rescheduled' },
  skip: { title: 'Skip Topic', submit: 'Skip Topic', busy: 'Skipping…', done: 'skipped' },
  cancel: { title: 'Cancel Topic Assignment', submit: 'Cancel Assignment', busy: 'Cancelling…', done: 'cancelled' },
};

export function HouseholdTopicActionModal({
  isOpen,
  onClose,
  mode,
  organizationId,
  householdName,
  assignmentId,
  topicTitle,
  currentPlannedDate,
  onSuccessToast,
}: HouseholdTopicActionModalProps) {
  const queryClient = useQueryClient();
  const titleId = useId();

  const defaultReason: HouseholdTopicReasonCode = mode === 'cancel' ? 'schedule_change' : 'not_applicable';
  const [plannedDate, setPlannedDate] = useState('');
  const [reasonCode, setReasonCode] = useState<HouseholdTopicReasonCode>(defaultReason);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (isOpen) {
      setPlannedDate(currentPlannedDate ?? '');
      setReasonCode(mode === 'cancel' ? 'schedule_change' : 'not_applicable');
      setErrorMessage(null);
    }
  }, [isOpen, mode, currentPlannedDate]);

  if (!isOpen) return null;

  const copy = COPY[mode];

  const handleClose = () => {
    setErrorMessage(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (mode === 'reschedule' && !plannedDate) return;
    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      if (mode === 'reschedule') {
        await rescheduleHouseholdTopic(organizationId, assignmentId, plannedDate);
      } else if (mode === 'skip') {
        await skipHouseholdTopic(organizationId, assignmentId, reasonCode);
      } else {
        await cancelHouseholdTopicAssignment(organizationId, assignmentId, reasonCode);
      }
      await invalidateFormationQueries(queryClient);
      onSuccessToast?.(`Topic "${topicTitle}" ${copy.done} for ${householdName}.`);
      handleClose();
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const inputClass =
    'block w-full rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500';

  return (
    <div role="dialog" aria-modal="true" aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      <div
        className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm"
        onClick={handleClose}
        aria-hidden="true"
      />
      <div className="relative z-10 w-full max-w-md rounded-xl border border-slate-700 bg-slate-900 shadow-2xl">
        <div className="flex items-center justify-between border-b border-slate-700/60 px-6 py-4">
          <div>
            <h2 id={titleId} className="text-sm font-semibold text-slate-100">
              {copy.title}
            </h2>
            <p className="mt-0.5 text-xs text-slate-400">
              {topicTitle} · {householdName}
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 px-6 py-5">
          {errorMessage && (
            <div className="rounded-lg border border-red-700/60 bg-red-950/40 p-3 text-xs text-red-300">
              {errorMessage}
            </div>
          )}

          {mode === 'reschedule' ? (
            <div>
              <label htmlFor={`${titleId}-date`} className="block text-xs font-medium text-slate-300 mb-1.5">
                New Planned Date <span className="text-red-400">*</span>
              </label>
              <input
                id={`${titleId}-date`}
                type="date"
                required
                value={plannedDate}
                onChange={(e) => setPlannedDate(e.target.value)}
                className={inputClass}
              />
            </div>
          ) : (
            <div>
              <label htmlFor={`${titleId}-reason`} className="block text-xs font-medium text-slate-300 mb-1.5">
                Reason
              </label>
              <select
                id={`${titleId}-reason`}
                value={reasonCode}
                onChange={(e) => setReasonCode(e.target.value as HouseholdTopicReasonCode)}
                className={inputClass}
              >
                {REASON_CODE_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="rounded-lg border border-slate-600 px-4 py-2 text-xs font-medium text-slate-300 hover:bg-slate-800 transition-colors disabled:opacity-50"
            >
              Close
            </button>
            <button
              type="submit"
              disabled={isSubmitting || (mode === 'reschedule' && !plannedDate)}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? copy.busy : copy.submit}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
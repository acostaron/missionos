import { useState, useId, useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useHouseholdMeetingHistory } from '../api/get-household-meeting-history';
import { completeHouseholdTopic } from '../api/complete-household-topic';
import { invalidateFormationQueries } from './formation-labels';
import { normalizeError } from '../../../lib/supabase/errors';

interface CompleteHouseholdTopicModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdId: string;
  householdName: string;
  assignmentId: string;
  topicTitle: string;
  onSuccessToast?: (msg: string) => void;
}

function formatMeetingType(value: string | null | undefined) {
  if (!value) return 'Meeting';
  return value.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

export function CompleteHouseholdTopicModal({
  isOpen,
  onClose,
  organizationId,
  householdId,
  householdName,
  assignmentId,
  topicTitle,
  onSuccessToast,
}: CompleteHouseholdTopicModalProps) {
  const queryClient = useQueryClient();
  const titleId = useId();

  const [meetingId, setMeetingId] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const { data, isLoading, error } = useHouseholdMeetingHistory(
    organizationId,
    householdId,
    0,
    50,
    isOpen
  );

  useEffect(() => {
    if (isOpen) {
      setMeetingId('');
      setErrorMessage(null);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  // Only completed meetings of this household are valid completion evidence.
  const completedMeetings = (data?.meetings ?? []).filter((m) => m.meeting_status === 'completed');

  const handleClose = () => {
    setErrorMessage(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!meetingId) return;
    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      await completeHouseholdTopic(organizationId, assignmentId, meetingId);
      await invalidateFormationQueries(queryClient);
      onSuccessToast?.(`Topic "${topicTitle}" marked completed for ${householdName}.`);
      handleClose();
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

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
              Mark Topic Completed
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
          {error && (
            <div className="rounded-lg border border-red-700/60 bg-red-950/40 p-3 text-xs text-red-300">
              Failed to load household meetings.
            </div>
          )}

          {!isLoading && !error && completedMeetings.length === 0 ? (
            <p className="rounded-lg border border-slate-700/60 bg-slate-800/40 p-4 text-xs text-slate-400">
              This household has no completed meetings yet. Complete a meeting first, then mark the
              topic completed using that meeting.
            </p>
          ) : (
            <div>
              <label htmlFor={`${titleId}-meeting`} className="block text-xs font-medium text-slate-300 mb-1.5">
                Completed Meeting <span className="text-red-400">*</span>
              </label>
              <select
                id={`${titleId}-meeting`}
                required
                value={meetingId}
                onChange={(e) => setMeetingId(e.target.value)}
                disabled={isLoading}
                className="block w-full rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              >
                <option value="">{isLoading ? 'Loading meetings…' : '— Select a meeting —'}</option>
                {completedMeetings.map((m) => (
                  <option key={m.household_meeting_id} value={m.household_meeting_id}>
                    {m.meeting_date} · {formatMeetingType(m.meeting_type)}
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
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || !meetingId}
              className="rounded-lg bg-emerald-600 px-4 py-2 text-xs font-medium text-white hover:bg-emerald-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? 'Saving…' : 'Mark Completed'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
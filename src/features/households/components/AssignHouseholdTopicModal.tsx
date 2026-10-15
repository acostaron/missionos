import { useState, useId, useEffect, useMemo } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { assignHouseholdTopic } from '../api/assign-household-topic';
import { useHouseholdMeetingHistory } from '../api/get-household-meeting-history';
import { assignTopicToMeeting, invalidateMeetingTopicQueries, useTopicChoices } from '../api/meeting-topics';
import { invalidateFormationQueries } from './formation-labels';
import { normalizeError } from '../../../lib/supabase/errors';
import { formatNyTime } from '../../../lib/ny-time';

interface AssignHouseholdTopicModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdId: string;
  householdName: string;
  pastoralLevel?: string | null;
  onSuccessToast?: (msg: string) => void;
}

const NO_MEETING = 'none';

function formatMeetingOption(date: string, startAt: string | null) {
  const [y, m, d] = date.split('-').map(Number);
  const label = new Intl.DateTimeFormat('en-US', {
    weekday: 'short', month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC',
  }).format(new Date(Date.UTC(y, m - 1, d, 12)));
  return startAt ? `${label} · ${formatNyTime(startAt)}` : label;
}

export function AssignHouseholdTopicModal({
  isOpen,
  onClose,
  organizationId,
  householdId,
  householdName,
  pastoralLevel,
  onSuccessToast,
}: AssignHouseholdTopicModalProps) {
  const queryClient = useQueryClient();
  const titleId = useId();

  const [topicId, setTopicId] = useState('');
  const [meetingId, setMeetingId] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const { data: choices, isLoading, error } = useTopicChoices(organizationId, pastoralLevel ?? null, isOpen);
  const { data: history, isLoading: isMeetingsLoading } = useHouseholdMeetingHistory(
    organizationId, householdId, 0, 50, isOpen,
  );

  const today = new Date().toISOString().slice(0, 10);
  const upcoming = useMemo(
    () =>
      (history?.meetings ?? [])
        .filter((m) => m.meeting_status === 'scheduled' && m.meeting_date >= today)
        .sort((a, b) => a.meeting_date.localeCompare(b.meeting_date)),
    [history, today],
  );

  useEffect(() => {
    if (isOpen) {
      setTopicId('');
      setMeetingId('');
      setErrorMessage(null);
    }
  }, [isOpen]);

  // Default to the next scheduled meeting once meetings load.
  const selectedMeeting = meetingId || (upcoming[0]?.household_meeting_id ?? NO_MEETING);

  if (!isOpen) return null;

  const libraryGroups = choices?.library ?? [];
  const otherTopics = choices?.other ?? [];
  const noCatalog = !isLoading && !error && libraryGroups.length === 0 && otherTopics.length === 0;

  const handleClose = () => {
    setErrorMessage(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!topicId) return;
    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      let title: string;
      if (selectedMeeting !== NO_MEETING) {
        const r = await assignTopicToMeeting(organizationId, householdId, topicId, selectedMeeting);
        title = r.topic_title;
      } else {
        const r = await assignHouseholdTopic(organizationId, householdId, topicId, null, null);
        title = r.topic_title;
      }
      await Promise.all([invalidateFormationQueries(queryClient), invalidateMeetingTopicQueries(queryClient)]);
      onSuccessToast?.(`Topic "${title}" assigned to ${householdName}.`);
      handleClose();
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const inputClass =
    'block w-full rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500';

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
              Assign Household Topic
            </h2>
            <p className="mt-0.5 text-xs text-slate-400">{householdName}</p>
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
              Failed to load Household Topics.
            </div>
          )}

          {noCatalog ? (
            <p className="rounded-lg border border-slate-700/60 bg-slate-800/40 p-4 text-xs text-slate-400">
              No Household Topics are available in the Household Topic Library yet.
            </p>
          ) : (
            <>
              <div>
                <label htmlFor={`${titleId}-topic`} className="block text-xs font-medium text-slate-300 mb-1.5">
                  Household Topic <span className="text-red-400">*</span>
                </label>
                <select
                  id={`${titleId}-topic`}
                  required
                  value={topicId}
                  onChange={(e) => setTopicId(e.target.value)}
                  disabled={isLoading}
                  className={inputClass}
                >
                  <option value="">{isLoading ? 'Loading topics…' : '— Select a topic —'}</option>
                  {libraryGroups.map((g) => (
                    <optgroup key={g.label} label={g.label}>
                      {g.topics.map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.title}
                        </option>
                      ))}
                    </optgroup>
                  ))}
                  {otherTopics.length > 0 && (
                    <optgroup label="Other topics">
                      {otherTopics.map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.topic_code ? `${t.topic_code} · ` : ''}
                          {t.title}
                        </option>
                      ))}
                    </optgroup>
                  )}
                </select>
              </div>

              <div>
                <label htmlFor={`${titleId}-meeting`} className="block text-xs font-medium text-slate-300 mb-1.5">
                  Meeting
                </label>
                <select
                  id={`${titleId}-meeting`}
                  value={selectedMeeting}
                  onChange={(e) => setMeetingId(e.target.value)}
                  disabled={isMeetingsLoading}
                  className={inputClass}
                >
                  {upcoming.map((m) => (
                    <option key={m.household_meeting_id} value={m.household_meeting_id}>
                      {formatMeetingOption(m.meeting_date, m.scheduled_start_at)}
                    </option>
                  ))}
                  <option value={NO_MEETING}>No meeting yet — plan without a date</option>
                </select>
                <p className="mt-1 text-[11px] text-slate-400">
                  {upcoming.length === 0 && !isMeetingsLoading
                    ? 'No upcoming meeting is scheduled. Schedule one under Meeting History to link this topic to it.'
                    : 'The topic is marked completed when this meeting is marked completed.'}
                </p>
              </div>
            </>
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
              disabled={isSubmitting || !topicId || noCatalog}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? 'Assigning…' : 'Assign Household Topic'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
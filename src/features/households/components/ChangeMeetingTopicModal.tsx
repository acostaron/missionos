// Record that a different topic was used at a household meeting (Pass 9.4, Claude 2026-10-15)
import { useEffect, useId, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import {
  CHANGE_REASONS,
  changeMeetingTopic,
  type ChangeReasonCode,
  invalidateMeetingTopicQueries,
  useTopicChoices,
  type MeetingTopic,
} from '../api/meeting-topics';
import { invalidateFormationQueries } from './formation-labels';
import { normalizeError } from '../../../lib/supabase/errors';

const OTHER = 'other';

export function ChangeMeetingTopicModal({
  isOpen,
  onClose,
  organizationId,
  meetingId,
  meetingDate,
  plannedTopics,
  pastoralLevel,
  onSuccessToast,
}: {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  meetingId: string;
  meetingDate: string;
  plannedTopics: MeetingTopic[];
  pastoralLevel?: string | null;
  onSuccessToast?: (msg: string) => void;
}) {
  const queryClient = useQueryClient();
  const titleId = useId();
  const { data: choices, isLoading } = useTopicChoices(organizationId, pastoralLevel ?? null, isOpen);

  const [replacedId, setReplacedId] = useState<string>('');
  const [newTopic, setNewTopic] = useState<string>('');
  const [otherTitle, setOtherTitle] = useState('');
  const [reason, setReason] = useState<ChangeReasonCode | ''>('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const firstPlannedId = plannedTopics[0]?.assignment_id ?? '';
  useEffect(() => {
    if (isOpen) {
      setReplacedId(firstPlannedId);
      setNewTopic('');
      setOtherTitle('');
      setReason('');
      setErrorMessage(null);
    }
  }, [isOpen, firstPlannedId]);

  if (!isOpen) return null;

  const hasPlanned = plannedTopics.length > 0;
  const replacedTopicId = plannedTopics.find((t) => t.assignment_id === replacedId)?.topic_id;
  const canSubmit =
    !isSubmitting &&
    reason !== '' &&
    (newTopic === OTHER ? otherTitle.trim().length > 0 && !!replacedId : !!newTopic);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;
    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      const r = await changeMeetingTopic({
        organizationId,
        meetingId,
        replacedAssignmentId: replacedId || null,
        newTopicId: newTopic === OTHER ? null : newTopic,
        otherTitle: newTopic === OTHER ? otherTitle.trim() : null,
        reasonCode: reason as ChangeReasonCode,
      });
      await Promise.all([invalidateMeetingTopicQueries(queryClient), invalidateFormationQueries(queryClient)]);
      onSuccessToast?.(`Recorded "${r.used_title}" as the topic used on ${meetingDate}.`);
      onClose();
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const inputClass =
    'block w-full rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500';

  return (
    <div role="dialog" aria-modal="true" aria-labelledby={titleId} className="fixed inset-0 z-[60] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm" onClick={onClose} aria-hidden="true" />
      <div className="relative z-10 w-full max-w-md rounded-xl border border-slate-700 bg-slate-900 shadow-2xl">
        <div className="flex items-center justify-between border-b border-slate-700/60 px-6 py-4">
          <div>
            <h2 id={titleId} className="text-sm font-semibold text-slate-100">
              {hasPlanned ? 'Change topic used' : 'Record topic used'}
            </h2>
            <p className="mt-0.5 text-xs text-slate-400">Meeting on {meetingDate}</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 px-6 py-5">
          {errorMessage && (
            <div className="rounded-lg border border-red-700/60 bg-red-950/40 p-3 text-xs text-red-300">{errorMessage}</div>
          )}

          {hasPlanned && (
            <div>
              <label htmlFor={`${titleId}-old`} className="mb-1.5 block text-xs font-medium text-slate-300">
                Planned topic being replaced
              </label>
              <select id={`${titleId}-old`} value={replacedId} onChange={(e) => setReplacedId(e.target.value)} className={inputClass}>
                {plannedTopics.map((t) => (
                  <option key={t.assignment_id} value={t.assignment_id}>
                    {t.title}
                  </option>
                ))}
                <option value="">None — this was an additional topic</option>
              </select>
            </div>
          )}

          <div>
            <label htmlFor={`${titleId}-new`} className="mb-1.5 block text-xs font-medium text-slate-300">
              Topic actually used <span className="text-red-400">*</span>
            </label>
            <select
              id={`${titleId}-new`}
              value={newTopic}
              onChange={(e) => setNewTopic(e.target.value)}
              disabled={isLoading}
              className={inputClass}
            >
              <option value="">{isLoading ? 'Loading topics…' : '— Select a topic —'}</option>
              {(choices?.library ?? []).map((g) => (
                <optgroup key={g.label} label={g.label}>
                  {g.topics
                    .filter((t) => t.id !== replacedTopicId)
                    .map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.title}
                      </option>
                    ))}
                </optgroup>
              ))}
              {(choices?.other ?? []).length > 0 && (
                <optgroup label="Other topics">
                  {(choices?.other ?? [])
                    .filter((t) => t.id !== replacedTopicId)
                    .map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.title}
                      </option>
                    ))}
                </optgroup>
              )}
              {replacedId && <option value={OTHER}>Not in the list — type the topic</option>}
            </select>
          </div>

          {newTopic === OTHER && (
            <div>
              <label htmlFor={`${titleId}-other`} className="mb-1.5 block text-xs font-medium text-slate-300">
                Topic title <span className="text-red-400">*</span>
              </label>
              <input
                id={`${titleId}-other`}
                type="text"
                maxLength={200}
                value={otherTitle}
                onChange={(e) => setOtherTitle(e.target.value)}
                className={inputClass}
              />
            </div>
          )}

          <div>
            <label htmlFor={`${titleId}-reason`} className="mb-1.5 block text-xs font-medium text-slate-300">
              Reason for the change <span className="text-red-400">*</span>
            </label>
            <select
              id={`${titleId}-reason`}
              value={reason}
              onChange={(e) => setReason(e.target.value as ChangeReasonCode | '')}
              className={inputClass}
            >
              <option value="">— Select a reason —</option>
              {CHANGE_REASONS.map((r) => (
                <option key={r.code} value={r.code}>
                  {r.label}
                </option>
              ))}
            </select>
            <p className="mt-1 text-[11px] text-slate-400">
              The planned topic stays in the history as “Replaced”, with this reason.
            </p>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="rounded-lg border border-slate-600 px-4 py-2 text-xs font-medium text-slate-300 hover:bg-slate-800 transition-colors disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!canSubmit}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? 'Saving…' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

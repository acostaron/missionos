import { useState, useId, useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useFormationTopics } from '../api/search-formation-topics';
import { assignHouseholdTopic } from '../api/assign-household-topic';
import { invalidateFormationQueries } from './formation-labels';
import { normalizeError } from '../../../lib/supabase/errors';

interface AssignHouseholdTopicModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdId: string;
  householdName: string;
  pastoralLevel?: string | null;
  onSuccessToast?: (msg: string) => void;
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

  const [search, setSearch] = useState('');
  const [topicId, setTopicId] = useState('');
  const [plannedDate, setPlannedDate] = useState('');
  const [sequence, setSequence] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const { data, isLoading, error } = useFormationTopics(
    organizationId,
    search,
    pastoralLevel ?? null,
    isOpen
  );

  useEffect(() => {
    if (isOpen) {
      setSearch('');
      setTopicId('');
      setPlannedDate('');
      setSequence('');
      setErrorMessage(null);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const topics = data?.topics ?? [];
  const noCatalog = !isLoading && !error && topics.length === 0 && search.trim() === '';

  const handleClose = () => {
    setErrorMessage(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!topicId) return;
    const seqNumber = sequence.trim() === '' ? null : Number.parseInt(sequence, 10);
    if (seqNumber !== null && (Number.isNaN(seqNumber) || seqNumber < 1)) {
      setErrorMessage('Sequence must be a positive whole number.');
      return;
    }

    try {
      setIsSubmitting(true);
      setErrorMessage(null);
      const result = await assignHouseholdTopic(
        organizationId,
        householdId,
        topicId,
        plannedDate || null,
        seqNumber
      );
      await invalidateFormationQueries(queryClient);
      onSuccessToast?.(`Topic "${result.topic_title}" assigned to ${householdName}.`);
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
              Assign Topic
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
              Failed to load formation topics.
            </div>
          )}

          {noCatalog ? (
            <p className="rounded-lg border border-slate-700/60 bg-slate-800/40 p-4 text-xs text-slate-400">
              No formation topics are available yet.
            </p>
          ) : (
            <>
              <div>
                <label htmlFor={`${titleId}-search`} className="block text-xs font-medium text-slate-300 mb-1.5">
                  Search Topics
                </label>
                <input
                  id={`${titleId}-search`}
                  type="text"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Title, code or scripture…"
                  maxLength={100}
                  className={inputClass}
                />
              </div>

              <div>
                <label htmlFor={`${titleId}-topic`} className="block text-xs font-medium text-slate-300 mb-1.5">
                  Topic <span className="text-red-400">*</span>
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
                  {topics.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.topic_code ? `${t.topic_code} · ` : ''}
                      {t.title}
                    </option>
                  ))}
                </select>
                {!isLoading && topics.length === 0 && (
                  <p className="mt-1 text-[11px] text-slate-500">No topics match your search.</p>
                )}
              </div>

              <div>
                <label htmlFor={`${titleId}-date`} className="block text-xs font-medium text-slate-300 mb-1.5">
                  Planned Date
                </label>
                <input
                  id={`${titleId}-date`}
                  type="date"
                  value={plannedDate}
                  onChange={(e) => setPlannedDate(e.target.value)}
                  className={inputClass}
                />
              </div>

              <div>
                <label htmlFor={`${titleId}-seq`} className="block text-xs font-medium text-slate-300 mb-1.5">
                  Sequence (optional)
                </label>
                <input
                  id={`${titleId}-seq`}
                  type="number"
                  min={1}
                  step={1}
                  value={sequence}
                  onChange={(e) => setSequence(e.target.value)}
                  className={inputClass}
                />
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
              {isSubmitting ? 'Assigning…' : 'Assign Topic'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
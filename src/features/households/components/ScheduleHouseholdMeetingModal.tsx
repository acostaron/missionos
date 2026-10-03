import { useState, useId, useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { meetingKeys } from '../api/get-household-meeting-history';
import { createHouseholdMeeting } from '../api/create-household-meeting';
import { normalizeError } from '../../../lib/supabase/errors';

const MEETING_TYPES = [
  { value: 'regular_household', label: 'Regular Household' },
  { value: 'special_household', label: 'Special Household' },
  { value: 'fellowship', label: 'Fellowship' },
  { value: 'formation', label: 'Formation' },
  { value: 'prayer', label: 'Prayer' },
  { value: 'other', label: 'Other' },
] as const;

const LOCATION_TYPES = [
  { value: '', label: '— None specified —' },
  { value: 'in_person', label: 'In Person' },
  { value: 'virtual', label: 'Virtual' },
  { value: 'hybrid', label: 'Hybrid' },
] as const;

interface ScheduleHouseholdMeetingModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdId: string;
  householdName: string;
  onSuccessToast?: (msg: string) => void;
}

export function ScheduleHouseholdMeetingModal({
  isOpen,
  onClose,
  organizationId,
  householdId,
  householdName,
  onSuccessToast,
}: ScheduleHouseholdMeetingModalProps) {
  const queryClient = useQueryClient();
  const titleId = useId();

  const todayStr = new Date().toISOString().split('T')[0];

  const [meetingDate, setMeetingDate] = useState(todayStr);
  const [meetingType, setMeetingType] = useState<string>('regular_household');
  const [locationType, setLocationType] = useState<string>('');
  const [locationText, setLocationText] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (isOpen) {
      setMeetingDate(todayStr);
      setMeetingType('regular_household');
      setLocationType('');
      setLocationText('');
      setErrorMessage(null);
    }
  }, [isOpen, todayStr]);

  if (!isOpen) return null;

  const handleClose = () => {
    setErrorMessage(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!meetingDate) return;

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      await createHouseholdMeeting(organizationId, {
        household_id: householdId,
        meeting_date: meetingDate,
        meeting_type: meetingType,
        location_type: locationType || null,
        location_text: locationText.trim() || null,
      });

      await queryClient.invalidateQueries({
        queryKey: meetingKeys.history(organizationId, householdId),
      });

      onSuccessToast?.(`Meeting scheduled for ${householdName} on ${meetingDate}.`);
      handleClose();
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
    >
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm"
        onClick={handleClose}
        aria-hidden="true"
      />

      <div className="relative z-10 w-full max-w-md rounded-xl border border-slate-700 bg-slate-900 shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-700/60 px-6 py-4">
          <div>
            <h2 id={titleId} className="text-sm font-semibold text-slate-100">
              Schedule Meeting
            </h2>
            <p className="mt-0.5 text-xs text-slate-400">{householdName}</p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
            aria-label="Close"
          >
            <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Body */}
        <form onSubmit={handleSubmit} className="space-y-4 px-6 py-5">
          {errorMessage && (
            <div className="rounded-lg border border-red-700/60 bg-red-950/40 p-3 text-xs text-red-300">
              {errorMessage}
            </div>
          )}

          {/* Meeting Date */}
          <div>
            <label htmlFor={`${titleId}-date`} className="block text-xs font-medium text-slate-300 mb-1.5">
              Meeting Date <span className="text-red-400">*</span>
            </label>
            <input
              id={`${titleId}-date`}
              type="date"
              required
              value={meetingDate}
              onChange={(e) => setMeetingDate(e.target.value)}
              className="block w-full rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
          </div>

          {/* Meeting Type */}
          <div>
            <label htmlFor={`${titleId}-type`} className="block text-xs font-medium text-slate-300 mb-1.5">
              Meeting Type
            </label>
            <select
              id={`${titleId}-type`}
              value={meetingType}
              onChange={(e) => setMeetingType(e.target.value)}
              className="block w-full rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              {MEETING_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>

          {/* Location Type */}
          <div>
            <label htmlFor={`${titleId}-loc-type`} className="block text-xs font-medium text-slate-300 mb-1.5">
              Location Type
            </label>
            <select
              id={`${titleId}-loc-type`}
              value={locationType}
              onChange={(e) => setLocationType(e.target.value)}
              className="block w-full rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              {LOCATION_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>

          {/* Location Text */}
          {locationType && (
            <div>
              <label htmlFor={`${titleId}-loc-text`} className="block text-xs font-medium text-slate-300 mb-1.5">
                Location Details
              </label>
              <input
                id={`${titleId}-loc-text`}
                type="text"
                value={locationText}
                onChange={(e) => setLocationText(e.target.value)}
                placeholder="e.g. Room 4, Zoom link..."
                maxLength={200}
                className="block w-full rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
            </div>
          )}

          {/* Actions */}
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
              disabled={isSubmitting || !meetingDate}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? 'Scheduling…' : 'Schedule Meeting'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

import { useState, useId } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { meetingKeys } from '../api/get-household-meeting-history';
import { recordHouseholdMeetingAttendance } from '../api/record-household-meeting-attendance';
import { normalizeError } from '../../../lib/supabase/errors';
import type { HouseholdMeetingRosterMember, AttendanceStatusValue } from '../types';

interface RecordHouseholdAttendanceModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdId: string;
  meetingId: string;
  meetingDate: string;
  expectedRoster: HouseholdMeetingRosterMember[];
  onSuccessToast?: (msg: string) => void;
}

const STATUS_OPTIONS: { value: AttendanceStatusValue; label: string; className: string }[] = [
  { value: 'present', label: 'Present', className: 'bg-emerald-950/50 text-emerald-300 border-emerald-700/60' },
  { value: 'absent', label: 'Absent', className: 'bg-rose-950/50 text-rose-300 border-rose-700/60' },
  { value: 'excused', label: 'Excused', className: 'bg-amber-950/50 text-amber-300 border-amber-700/60' },
];

export function RecordHouseholdAttendanceModal({
  isOpen,
  onClose,
  organizationId,
  householdId,
  meetingId,
  meetingDate,
  expectedRoster,
  onSuccessToast,
}: RecordHouseholdAttendanceModalProps) {
  const queryClient = useQueryClient();
  const titleId = useId();

  const [attendance, setAttendance] = useState<Record<string, AttendanceStatusValue>>(() => {
    const init: Record<string, AttendanceStatusValue> = {};
    for (const m of expectedRoster) {
      init[m.member_id] = 'present';
    }
    return init;
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleClose = () => {
    setErrorMessage(null);
    onClose();
  };

  const handleStatusChange = (memberId: string, status: AttendanceStatusValue) => {
    setAttendance((prev) => ({ ...prev, [memberId]: status }));
  };

  const handleMarkAll = (status: AttendanceStatusValue) => {
    const next: Record<string, AttendanceStatusValue> = {};
    for (const m of expectedRoster) {
      next[m.member_id] = status;
    }
    setAttendance(next);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (expectedRoster.length === 0) return;

    const payload = expectedRoster.map((m) => ({
      member_id: m.member_id,
      attendance_status: attendance[m.member_id] ?? 'present',
    }));

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await recordHouseholdMeetingAttendance(organizationId, meetingId, payload);

      await Promise.all([
        queryClient.invalidateQueries({ queryKey: meetingKeys.detail(organizationId, meetingId) }),
        queryClient.invalidateQueries({ queryKey: meetingKeys.history(organizationId, householdId) }),
      ]);

      const { present_count, expected_member_count } = result.attendance_summary;
      onSuccessToast?.(
        `Attendance recorded: ${present_count} of ${expected_member_count} present on ${meetingDate}.`
      );
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
      <div
        className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm"
        onClick={handleClose}
        aria-hidden="true"
      />

      <div className="relative z-10 w-full max-w-lg rounded-xl border border-slate-700 bg-slate-900 shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-700/60 px-6 py-4">
          <div>
            <h2 id={titleId} className="text-sm font-semibold text-slate-100">
              Record Attendance
            </h2>
            <p className="mt-0.5 text-xs text-slate-400">Meeting date: {meetingDate}</p>
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

        <form onSubmit={handleSubmit}>
          <div className="px-6 py-4">
            {errorMessage && (
              <div className="mb-4 rounded-lg border border-red-700/60 bg-red-950/40 p-3 text-xs text-red-300">
                {errorMessage}
              </div>
            )}

            {expectedRoster.length === 0 ? (
              <p className="text-xs text-slate-400 text-center py-4">
                No eligible members in the expected roster for this meeting date.
              </p>
            ) : (
              <>
                {/* Quick-mark all */}
                <div className="mb-3 flex items-center gap-2">
                  <span className="text-xs text-slate-400">Mark all:</span>
                  {STATUS_OPTIONS.map((opt) => (
                    <button
                      key={opt.value}
                      type="button"
                      onClick={() => handleMarkAll(opt.value)}
                      className={`rounded border px-2 py-0.5 text-[10px] font-medium transition-colors ${opt.className}`}
                    >
                      {opt.label}
                    </button>
                  ))}
                </div>

                {/* Roster table */}
                <div className="max-h-72 overflow-y-auto rounded-lg border border-slate-700/60">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-700/60 bg-slate-800/60">
                        <th className="px-3 py-2 text-left font-medium text-slate-400">Member</th>
                        <th className="px-3 py-2 text-left font-medium text-slate-400">Attendance</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-700/40">
                      {expectedRoster.map((member) => {
                        const current = attendance[member.member_id] ?? 'present';
                        return (
                          <tr key={member.member_id} className="hover:bg-slate-800/30 transition-colors">
                            <td className="px-3 py-2.5">
                              <div className="font-medium text-slate-200">{member.display_name}</div>
                              {member.membership_role && (
                                <div className="text-[10px] text-slate-500 capitalize">
                                  {member.membership_role.replace(/_/g, ' ')}
                                </div>
                              )}
                            </td>
                            <td className="px-3 py-2.5">
                              <div className="flex gap-1.5">
                                {STATUS_OPTIONS.map((opt) => (
                                  <button
                                    key={opt.value}
                                    type="button"
                                    onClick={() => handleStatusChange(member.member_id, opt.value)}
                                    className={`rounded border px-2 py-0.5 text-[10px] font-medium transition-all ${
                                      current === opt.value
                                        ? opt.className + ' ring-1 ring-offset-1 ring-offset-slate-900 ring-current'
                                        : 'border-slate-600 bg-slate-800 text-slate-400 hover:border-slate-500'
                                    }`}
                                  >
                                    {opt.label}
                                  </button>
                                ))}
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>

                <p className="mt-2 text-[10px] text-slate-500">
                  {expectedRoster.length} eligible member{expectedRoster.length !== 1 ? 's' : ''} ·
                  Only primary household members as of {meetingDate} are listed.
                </p>
              </>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-end gap-2 border-t border-slate-700/60 px-6 py-4">
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
              disabled={isSubmitting || expectedRoster.length === 0}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? 'Saving…' : 'Save Attendance'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

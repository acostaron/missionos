import { useState, useId } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { meetingKeys } from '../api/get-household-meeting-history';
import { useHouseholdMeetingDetail } from '../api/get-household-meeting-detail';
import { completeHouseholdMeeting } from '../api/complete-household-meeting';
import { cancelHouseholdMeeting } from '../api/cancel-household-meeting';
import { RecordHouseholdAttendanceModal } from './RecordHouseholdAttendanceModal';
import { normalizeError } from '../../../lib/supabase/errors';
import type { HouseholdMeetingStatus } from '../types';

function formatMeetingType(t: string) {
  return t
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

function formatLocationType(t: string | null) {
  if (!t) return null;
  return { in_person: 'In Person', virtual: 'Virtual', hybrid: 'Hybrid' }[t] ?? t;
}

function MeetingStatusBadge({ status }: { status: HouseholdMeetingStatus }) {
  const cls =
    status === 'completed'
      ? 'border-emerald-700/60 bg-emerald-950/40 text-emerald-300'
      : status === 'scheduled'
        ? 'border-indigo-700/60 bg-indigo-950/40 text-indigo-300'
        : 'border-slate-600 bg-slate-800 text-slate-400';
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-semibold capitalize ${cls}`}>
      {status}
    </span>
  );
}

interface HouseholdMeetingDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdId: string;
  meetingId: string;
  canManage: boolean;
  canRecordAttendance: boolean;
  onSuccessToast?: (msg: string) => void;
}

export function HouseholdMeetingDetailModal({
  isOpen,
  onClose,
  organizationId,
  householdId,
  meetingId,
  canManage,
  canRecordAttendance,
  onSuccessToast,
}: HouseholdMeetingDetailModalProps) {
  const queryClient = useQueryClient();
  const titleId = useId();

  const { data: detail, isLoading, error: loadError } = useHouseholdMeetingDetail(
    organizationId,
    meetingId,
    isOpen
  );

  const [isCompleting, setIsCompleting] = useState(false);
  const [isCancelling, setIsCancelling] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [isAttendanceOpen, setIsAttendanceOpen] = useState(false);

  if (!isOpen) return null;

  const handleClose = () => {
    setActionError(null);
    onClose();
  };

  const handleComplete = async () => {
    if (!detail) return;
    try {
      setIsCompleting(true);
      setActionError(null);
      await completeHouseholdMeeting(organizationId, meetingId);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: meetingKeys.detail(organizationId, meetingId) }),
        queryClient.invalidateQueries({ queryKey: meetingKeys.history(organizationId, householdId) }),
      ]);
      onSuccessToast?.(`Meeting on ${detail.meeting_date} marked as completed.`);
    } catch (err) {
      setActionError(normalizeError(err).message);
    } finally {
      setIsCompleting(false);
    }
  };

  const handleCancel = async () => {
    if (!detail) return;
    try {
      setIsCancelling(true);
      setActionError(null);
      await cancelHouseholdMeeting(organizationId, meetingId);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: meetingKeys.detail(organizationId, meetingId) }),
        queryClient.invalidateQueries({ queryKey: meetingKeys.history(organizationId, householdId) }),
      ]);
      onSuccessToast?.(`Meeting on ${detail.meeting_date} was cancelled.`);
      handleClose();
    } catch (err) {
      setActionError(normalizeError(err).message);
    } finally {
      setIsCancelling(false);
    }
  };

  const today = new Date().toISOString().split('T')[0];
  const isPast = detail ? detail.meeting_date <= today : false;
  const isScheduled = detail?.meeting_status === 'scheduled';
  const isCompleted = detail?.meeting_status === 'completed';

  return (
    <>
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

        <div className="relative z-10 w-full max-w-xl rounded-xl border border-slate-700 bg-slate-900 shadow-2xl max-h-[90vh] flex flex-col">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-slate-700/60 px-6 py-4 flex-shrink-0">
            <div>
              <h2 id={titleId} className="text-sm font-semibold text-slate-100">
                Meeting Detail
              </h2>
              {detail && (
                <p className="mt-0.5 text-xs text-slate-400">
                  {detail.household_name} · {detail.meeting_date}
                </p>
              )}
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

          {/* Content */}
          <div className="overflow-y-auto flex-1 px-6 py-4 space-y-4">
            {isLoading && (
              <div className="space-y-3">
                <div className="h-4 w-32 animate-pulse rounded bg-slate-800" />
                <div className="h-24 animate-pulse rounded-lg bg-slate-800/60" />
              </div>
            )}

            {loadError && (
              <p className="text-xs text-red-400">Failed to load meeting details.</p>
            )}

            {actionError && (
              <div className="rounded-lg border border-red-700/60 bg-red-950/40 p-3 text-xs text-red-300">
                {actionError}
              </div>
            )}

            {detail && (
              <>
                {/* Status row */}
                <div className="flex items-center gap-3 flex-wrap">
                  <MeetingStatusBadge status={detail.meeting_status} />
                  <span className="text-xs text-slate-400">{formatMeetingType(detail.meeting_type)}</span>
                  {detail.location_type && (
                    <span className="text-xs text-slate-400">· {formatLocationType(detail.location_type)}</span>
                  )}
                </div>

                {/* Key info grid */}
                <dl className="grid grid-cols-2 gap-x-6 gap-y-3 text-xs">
                  {detail.facilitator_display_name && (
                    <>
                      <dt className="text-slate-400">Facilitator</dt>
                      <dd className="text-slate-200">{detail.facilitator_display_name}</dd>
                    </>
                  )}
                  {detail.host_display_name && (
                    <>
                      <dt className="text-slate-400">Host</dt>
                      <dd className="text-slate-200">{detail.host_display_name}</dd>
                    </>
                  )}
                  {detail.location_text && (
                    <>
                      <dt className="text-slate-400">Location</dt>
                      <dd className="text-slate-200">{detail.location_text}</dd>
                    </>
                  )}
                  {detail.attendance_recorded_at && (
                    <>
                      <dt className="text-slate-400">Attendance Recorded</dt>
                      <dd className="text-slate-200">
                        {new Date(detail.attendance_recorded_at).toLocaleDateString()}
                      </dd>
                    </>
                  )}
                </dl>

                {/* Attendance Summary */}
                {isCompleted && (
                  <div className="rounded-lg border border-slate-700/60 bg-slate-800/40 p-4">
                    <div className="flex items-center justify-between mb-3">
                      <h3 className="text-xs font-semibold text-slate-300">Attendance Summary</h3>
                      {!detail.attendance_summary.attendance_complete && canRecordAttendance && (
                        <button
                          type="button"
                          onClick={() => setIsAttendanceOpen(true)}
                          className="rounded-lg border border-indigo-700/60 bg-indigo-950/40 px-3 py-1 text-[10px] font-medium text-indigo-300 hover:bg-indigo-950/70 transition-colors"
                        >
                          Record / Update
                        </button>
                      )}
                    </div>
                    <div className="grid grid-cols-4 gap-2 text-center">
                      {[
                        { label: 'Expected', value: detail.attendance_summary.expected_member_count, color: 'text-slate-300' },
                        { label: 'Present', value: detail.attendance_summary.present_count, color: 'text-emerald-300' },
                        { label: 'Absent', value: detail.attendance_summary.absent_count, color: 'text-rose-300' },
                        { label: 'Excused', value: detail.attendance_summary.excused_count, color: 'text-amber-300' },
                      ].map(({ label, value, color }) => (
                        <div key={label}>
                          <div className={`text-lg font-bold ${color}`}>{value}</div>
                          <div className="text-[10px] text-slate-500">{label}</div>
                        </div>
                      ))}
                    </div>
                    {detail.attendance_summary.attendance_complete && (
                      <p className="mt-2 text-center text-[10px] text-emerald-400">
                        ✓ Attendance complete
                      </p>
                    )}
                  </div>
                )}

                {/* Expected Roster */}
                {detail.expected_roster.length > 0 && (
                  <div>
                    <h3 className="text-xs font-semibold text-slate-300 mb-2">
                      Expected Roster ({detail.expected_roster.length})
                    </h3>
                    <div className="rounded-lg border border-slate-700/60 overflow-hidden">
                      <table className="w-full text-xs">
                        <tbody className="divide-y divide-slate-700/40">
                          {detail.expected_roster.map((member) => {
                            const recorded = detail.recorded_attendance.find(
                              (a) => a.member_id === member.member_id
                            );
                            const statusCls = recorded
                              ? recorded.attendance_status === 'present'
                                ? 'text-emerald-300'
                                : recorded.attendance_status === 'absent'
                                  ? 'text-rose-300'
                                  : 'text-amber-300'
                              : 'text-slate-500';
                            return (
                              <tr key={member.member_id} className="hover:bg-slate-800/30 px-3 py-2 flex items-center justify-between">
                                <td className="px-3 py-2 text-slate-200">{member.display_name}</td>
                                <td className={`px-3 py-2 capitalize font-medium ${statusCls}`}>
                                  {recorded?.attendance_status ?? '—'}
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}
              </>
            )}
          </div>

          {/* Footer actions */}
          {detail && canManage && isScheduled && (
            <div className="border-t border-slate-700/60 px-6 py-4 flex-shrink-0 flex items-center gap-2 flex-wrap">
              {isPast && (
                <button
                  type="button"
                  onClick={handleComplete}
                  disabled={isCompleting || isCancelling}
                  className="rounded-lg bg-emerald-700 px-4 py-2 text-xs font-medium text-white hover:bg-emerald-600 transition-colors disabled:opacity-50"
                >
                  {isCompleting ? 'Completing…' : 'Mark Completed'}
                </button>
              )}
              {canRecordAttendance && isCompleted && !detail.attendance_summary.attendance_complete && (
                <button
                  type="button"
                  onClick={() => setIsAttendanceOpen(true)}
                  className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors"
                >
                  Record Attendance
                </button>
              )}
              <button
                type="button"
                onClick={handleCancel}
                disabled={isCompleting || isCancelling}
                className="rounded-lg border border-red-700/60 bg-red-950/40 px-4 py-2 text-xs font-medium text-red-300 hover:bg-red-950/70 transition-colors disabled:opacity-50"
              >
                {isCancelling ? 'Cancelling…' : 'Cancel Meeting'}
              </button>
            </div>
          )}

          {/* Record Attendance button for completed meetings */}
          {detail && canRecordAttendance && isCompleted && (
            <div className="border-t border-slate-700/60 px-6 py-4 flex-shrink-0 flex justify-end">
              <button
                type="button"
                onClick={() => setIsAttendanceOpen(true)}
                className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors"
              >
                {detail.attendance_summary.attendance_complete ? 'Update Attendance' : 'Record Attendance'}
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Attendance sub-modal */}
      {detail && isAttendanceOpen && (
        <RecordHouseholdAttendanceModal
          isOpen={isAttendanceOpen}
          onClose={() => setIsAttendanceOpen(false)}
          organizationId={organizationId}
          householdId={householdId}
          meetingId={meetingId}
          meetingDate={detail.meeting_date}
          expectedRoster={detail.expected_roster}
          onSuccessToast={onSuccessToast}
        />
      )}
    </>
  );
}

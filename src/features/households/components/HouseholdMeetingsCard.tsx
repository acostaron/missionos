import { useState } from 'react';
import { useHouseholdMeetingHistory } from '../api/get-household-meeting-history';
import { ScheduleHouseholdMeetingModal } from './ScheduleHouseholdMeetingModal';
import { HouseholdMeetingDetailModal } from './HouseholdMeetingDetailModal';
import type { HouseholdMeetingRow, HouseholdMeetingStatus, AttendanceSummary } from '../types';

function formatMeetingType(t: string) {
  return t
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

function MeetingStatusBadge({ status }: { status: HouseholdMeetingStatus }) {
  const cls =
    status === 'completed'
      ? 'border-success-600/30 bg-success-50 text-success-700'
      : status === 'scheduled'
        ? 'border-navy-100 bg-navy-50 text-primary-blue'
        : 'border-line-strong bg-surface-muted text-ink-muted';
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-semibold capitalize ${cls}`}>
      {status}
    </span>
  );
}

function AttendanceMiniSummary({ summary, status }: { summary: AttendanceSummary; status: HouseholdMeetingStatus }) {
  if (status !== 'completed') return null;
  if (summary.expected_member_count === 0) {
    return <span className="text-[10px] text-ink-muted">No roster</span>;
  }
  const pct = Math.round((summary.present_count / summary.expected_member_count) * 100);
  const color = pct >= 80 ? 'text-success-700' : pct >= 50 ? 'text-warning-700' : 'text-danger-700';
  return (
    <span className={`text-[10px] font-medium ${color}`}>
      {summary.present_count}/{summary.expected_member_count} present
      {!summary.attendance_complete && (
        <span className="ml-1 text-warning-700">· pending</span>
      )}
    </span>
  );
}

interface HouseholdMeetingsCardProps {
  organizationId: string;
  householdId: string;
  householdName: string;
  canView: boolean;
  canManage: boolean;
  canRecordAttendance: boolean;
  onSuccessToast?: (msg: string) => void;
}

const PAGE_SIZE = 10;

export function HouseholdMeetingsCard({
  organizationId,
  householdId,
  householdName,
  canView,
  canManage,
  canRecordAttendance,
  onSuccessToast,
}: HouseholdMeetingsCardProps) {
  const [page, setPage] = useState(0);
  const [isScheduleOpen, setIsScheduleOpen] = useState(false);
  const [selectedMeetingId, setSelectedMeetingId] = useState<string | null>(null);

  const {
    data: history,
    isLoading,
    error,
  } = useHouseholdMeetingHistory(organizationId, householdId, page, PAGE_SIZE, canView);

  if (!canView) {
    return (
      <div className="rounded-xl border border-line bg-surface-muted p-6">
        <p className="text-xs text-ink-muted">
          You do not have permission to view meeting history for this household.
        </p>
      </div>
    );
  }

  const totalPages = history ? Math.ceil(history.total_count / PAGE_SIZE) : 0;

  return (
    <>
      <div className="rounded-xl border border-line bg-surface-muted">
        {/* Card header */}
        <div className="flex items-center justify-between border-b border-line px-5 py-4">
          <div>
            <h3 className="text-sm font-semibold text-ink">Meeting History</h3>
            {history && (
              <p className="mt-0.5 text-xs text-ink-muted">
                {history.total_count} meeting{history.total_count !== 1 ? 's' : ''}
              </p>
            )}
          </div>
          {canManage && (
            <button
              type="button"
              onClick={() => setIsScheduleOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-navy-100 bg-navy-50 px-3 py-1.5 text-xs font-medium text-primary-blue hover:bg-navy-100 transition-colors"
            >
              <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
              </svg>
              Schedule
            </button>
          )}
        </div>

        {/* Content */}
        <div className="px-5 py-4">
          {isLoading && (
            <div className="space-y-2">
              {[1, 2, 3].map((i) => (
                <div key={i} className="h-10 animate-pulse rounded-lg bg-surface-muted" />
              ))}
            </div>
          )}

          {error && (
            <p className="text-xs text-danger-700">Failed to load meeting history.</p>
          )}

          {!isLoading && !error && history && history.meetings.length === 0 && (
            <div className="py-8 text-center">
              <div className="mb-2 text-2xl">📅</div>
              <p className="text-xs text-ink-muted">No meetings recorded yet.</p>
              {canManage && (
                <button
                  type="button"
                  onClick={() => setIsScheduleOpen(true)}
                  className="mt-3 text-xs text-primary-blue hover:text-primary-blue underline underline-offset-2"
                >
                  Schedule the first meeting
                </button>
              )}
            </div>
          )}

          {!isLoading && !error && history && history.meetings.length > 0 && (
            <>
              <div className="space-y-1.5">
                {history.meetings.map((meeting: HouseholdMeetingRow) => (
                  <button
                    key={meeting.household_meeting_id}
                    type="button"
                    onClick={() => setSelectedMeetingId(meeting.household_meeting_id)}
                    className="w-full rounded-lg border border-line bg-surface-muted px-4 py-3 text-left hover:bg-surface-muted hover:border-line-strong transition-all group"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <div className="flex items-center gap-3 min-w-0">
                        <MeetingStatusBadge status={meeting.meeting_status} />
                        <span className="text-xs font-medium text-ink tabular-nums">
                          {meeting.meeting_date}
                        </span>
                        <span className="text-[10px] text-ink-muted">
                          {formatMeetingType(meeting.meeting_type)}
                        </span>
                      </div>
                      <div className="flex items-center gap-3 flex-shrink-0">
                        <AttendanceMiniSummary
                          summary={meeting.attendance_summary}
                          status={meeting.meeting_status}
                        />
                        <svg
                          className="h-3.5 w-3.5 text-ink-muted group-hover:text-ink-secondary transition-colors"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke="currentColor"
                        >
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                        </svg>
                      </div>
                    </div>
                    {meeting.facilitator_display_name && (
                      <div className="mt-1 text-[10px] text-ink-muted">
                        Facilitator: {meeting.facilitator_display_name}
                      </div>
                    )}
                  </button>
                ))}
              </div>

              {/* Pagination */}
              {totalPages > 1 && (
                <div className="mt-4 flex items-center justify-between">
                  <button
                    type="button"
                    onClick={() => setPage((p) => Math.max(0, p - 1))}
                    disabled={page === 0}
                    className="rounded-lg border border-line-strong px-3 py-1.5 text-xs text-ink-secondary hover:bg-surface-muted transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    ← Previous
                  </button>
                  <span className="text-[10px] text-ink-muted">
                    Page {page + 1} of {totalPages}
                  </span>
                  <button
                    type="button"
                    onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
                    disabled={page >= totalPages - 1}
                    className="rounded-lg border border-line-strong px-3 py-1.5 text-xs text-ink-secondary hover:bg-surface-muted transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    Next →
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* Schedule modal */}
      {canManage && (
        <ScheduleHouseholdMeetingModal
          isOpen={isScheduleOpen}
          onClose={() => setIsScheduleOpen(false)}
          organizationId={organizationId}
          householdId={householdId}
          householdName={householdName}
          onSuccessToast={onSuccessToast}
        />
      )}

      {/* Detail modal */}
      {selectedMeetingId && (
        <HouseholdMeetingDetailModal
          isOpen={!!selectedMeetingId}
          onClose={() => setSelectedMeetingId(null)}
          organizationId={organizationId}
          householdId={householdId}
          meetingId={selectedMeetingId}
          canManage={canManage}
          canRecordAttendance={canRecordAttendance}
          onSuccessToast={onSuccessToast}
        />
      )}
    </>
  );
}

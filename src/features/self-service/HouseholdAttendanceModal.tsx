// Record or update attendance for a household meeting from the household card (Pass 9.9, written by Claude 2026-10-16).
// Saving also marks a scheduled meeting completed (its planned topic is then completed automatically).
// Before the meeting day it opens read-only: the expected members, no saving (Pass 9.9A, Ron 2026-10-16).
import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { formatNyDateShort, getTodayNyDate } from '../../lib/ny-time';
import { normalizeError } from '../../lib/supabase/errors';
import { Alert, Button, Modal } from '../../components/ui';
import {
  ATTENDANCE_LABELS,
  invalidateHouseholdCards,
  recordAttendance,
  useMeetingAttendance,
  type AttendanceStatus,
  type CardMeeting,
} from './household-card-api';

const STATUSES: AttendanceStatus[] = ['present', 'absent', 'excused'];
const ACTIVE: Record<AttendanceStatus, string> = {
  present: 'border-success-600 bg-success-50 text-success-700',
  absent: 'border-danger-600 bg-danger-50 text-danger-700',
  excused: 'border-warning-600 bg-warning-50 text-warning-700',
};

export function HouseholdAttendanceModal({
  organizationId,
  householdName,
  meeting,
  onClose,
}: {
  organizationId: string;
  householdName: string;
  meeting: CardMeeting;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const { data, isLoading, error } = useMeetingAttendance(organizationId, meeting.household_meeting_id, true);
  const [marks, setMarks] = useState<Record<string, AttendanceStatus>>({});
  const [isSaving, setIsSaving] = useState(false);
  const [errorText, setErrorText] = useState<string | null>(null);

  useEffect(() => {
    if (!data) return;
    const init: Record<string, AttendanceStatus> = {};
    for (const m of data.roster) init[m.member_id] = m.attendance_status ?? 'present';
    setMarks(init);
  }, [data]);

  const roster = data?.roster ?? [];
  const isEarly = meeting.meeting_date > getTodayNyDate();
  const willComplete = meeting.meeting_status === 'scheduled';

  const markAll = (s: AttendanceStatus) => {
    const next: Record<string, AttendanceStatus> = {};
    for (const m of roster) next[m.member_id] = s;
    setMarks(next);
  };

  const save = async () => {
    try {
      setIsSaving(true);
      setErrorText(null);
      await recordAttendance(
        organizationId,
        meeting.household_meeting_id,
        roster.map((m) => ({ member_id: m.member_id, attendance_status: marks[m.member_id] ?? 'present' })),
      );
      await invalidateHouseholdCards(qc);
      onClose();
    } catch (e) {
      setErrorText(normalizeError(e).message);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      closeOnBackdrop={false}
      title={isEarly ? 'Expected members' : 'Attendance'}
      description={`${householdName} · ${formatNyDateShort(meeting.meeting_date)}`}
      footer={
        isEarly ? (
          <div className="flex w-full justify-end">
            <Button variant="ghost" onClick={onClose}>
              Close
            </Button>
          </div>
        ) : (
        <div className="flex w-full justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={isSaving}>
            Cancel
          </Button>
          <Button onClick={save} disabled={isSaving || roster.length === 0} loading={isSaving}>
            {willComplete ? 'Save and complete meeting' : 'Save'}
          </Button>
        </div>
        )
      }
    >
      <div className="space-y-4">
        {errorText && (
          <Alert variant="danger" title="Could not save">
            {errorText}
          </Alert>
        )}
        {error && (
          <Alert variant="danger" title="Could not load the members">
            {normalizeError(error).message}
          </Alert>
        )}
        {isLoading ? (
          <p className="text-sm text-ink-muted">Loading members…</p>
        ) : roster.length === 0 ? (
          <p className="text-sm text-ink-muted">This household has no members on the meeting date.</p>
        ) : isEarly ? (
          <>
            <p className="text-xs text-ink-muted">
              Attendance opens on {formatNyDateShort(meeting.meeting_date)}. {roster.length} member
              {roster.length === 1 ? '' : 's'} expected.
            </p>
            <ul className="divide-y divide-line">
              {roster.map((m) => (
                <li key={m.member_id} className="py-2 text-sm text-ink">
                  {m.display_name}
                </li>
              ))}
            </ul>
          </>
        ) : (
          <>
            <div className="flex flex-wrap items-center gap-2 text-xs text-ink-secondary">
              <span>Mark everyone:</span>
              {STATUSES.map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => markAll(s)}
                  className="rounded border border-line px-2 py-0.5 hover:bg-surface-muted"
                >
                  {ATTENDANCE_LABELS[s]}
                </button>
              ))}
            </div>
            <ul className="divide-y divide-line">
              {roster.map((m) => (
                <li key={m.member_id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                  <span className="text-sm text-ink">{m.display_name}</span>
                  <div className="flex gap-1" role="radiogroup" aria-label={m.display_name}>
                    {STATUSES.map((s) => {
                      const on = marks[m.member_id] === s;
                      return (
                        <button
                          key={s}
                          type="button"
                          role="radio"
                          aria-checked={on}
                          onClick={() => setMarks((prev) => ({ ...prev, [m.member_id]: s }))}
                          className={`rounded border px-2 py-1 text-xs font-medium transition-colors ${
                            on ? ACTIVE[s] : 'border-line text-ink-secondary hover:bg-surface-muted'
                          }`}
                        >
                          {ATTENDANCE_LABELS[s]}
                        </button>
                      );
                    })}
                  </div>
                </li>
              ))}
            </ul>
            {willComplete && (
              <p className="text-xs text-ink-muted">
                Saving also marks this meeting completed, and its planned topic as used.
              </p>
            )}
          </>
        )}
      </div>
    </Modal>
  );
}

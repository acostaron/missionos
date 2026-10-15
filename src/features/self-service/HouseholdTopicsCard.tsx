// Household card in My Events — one place to run the household (Pass 9.9, written by Claude 2026-10-16;
// grew from the 9.6 Fraternal topics card and the 9.7 household topics card).
// Everyone sees their household's meetings, topics and their own attendance. can_edit (servant leaders, spouse in
// couple leadership, administrators, any member of a Fraternal household) adds: schedule / edit / cancel / complete
// meetings, record attendance, choose / change topics. The server decides can_edit and checks it again on save.
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { BookOpenText, CalendarPlus, MapPin } from 'lucide-react';
import { supabase } from '../../lib/supabase/client';
import { formatNyDateShort, formatNyTime, getTodayNyDate } from '../../lib/ny-time';
import { normalizeError } from '../../lib/supabase/errors';
import { formatTopicMonth, materialKindLabel, useTopicLibrary } from '../library/api';
import { CHANGE_REASONS, changeReasonLabel, type ChangeReasonCode } from '../households/api/meeting-topics';
import { Alert, Badge, Button, Card, Input, Modal, Select } from '../../components/ui';
import {
  ATTENDANCE_LABELS,
  LOCATION_TYPES,
  invalidateHouseholdCards,
  setMeetingStatus,
  useMyHouseholdCards,
  type CardHousehold,
  type CardMeeting,
} from './household-card-api';
import { HouseholdMeetingFormModal } from './HouseholdMeetingFormModal';
import { HouseholdAttendanceModal } from './HouseholdAttendanceModal';

type FraternalMeeting = CardMeeting;

type MeetingDialog =
  | { kind: 'schedule'; household: CardHousehold }
  | { kind: 'edit'; household: CardHousehold; meeting: CardMeeting }
  | { kind: 'attendance'; household: CardHousehold; meeting: CardMeeting }
  | { kind: 'complete' | 'cancel'; household: CardHousehold; meeting: CardMeeting }
  | null;

type Dialog =
  | { kind: 'assign'; meeting: FraternalMeeting }
  | { kind: 'change'; meeting: FraternalMeeting }
  | null;

export function HouseholdTopicsCard({ organizationId }: { organizationId: string | null }) {
  const qc = useQueryClient();
  const { data: households = [] } = useMyHouseholdCards(organizationId);
  const [meetingDialog, setMeetingDialog] = useState<MeetingDialog>(null);
  const { data: library } = useTopicLibrary(households.length > 0 ? organizationId : null);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [topicId, setTopicId] = useState('');
  const [replacedId, setReplacedId] = useState('');
  const [otherTitle, setOtherTitle] = useState('');
  const [reason, setReason] = useState<ChangeReasonCode | ''>('');
  const [errorText, setErrorText] = useState<string | null>(null);

  const libraryByMonth = useMemo(() => {
    const groups = new Map<string, { topic_id: string; title: string; kind: string }[]>();
    for (const i of library?.items ?? []) {
      if (!i.has_content) continue;
      const k = i.topic_month.slice(0, 10);
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k)!.push({ topic_id: i.topic_id, title: i.title, kind: i.material_kind });
    }
    return Array.from(groups.entries()).sort((a, b) => b[0].localeCompare(a[0]));
  }, [library]);

  const save = useMutation({
    mutationFn: async () => {
      if (!dialog || !organizationId) return;
      if (dialog.kind === 'assign') {
        const { error } = await supabase.rpc('member_assign_household_topic', {
          p_organization_id: organizationId,
          p_meeting_id: dialog.meeting.household_meeting_id,
          p_topic_id: topicId,
        });
        if (error) throw error;
      } else {
        const { error } = await supabase.rpc('member_change_household_meeting_topic', {
          p_organization_id: organizationId,
          p_meeting_id: dialog.meeting.household_meeting_id,
          p_reason_code: reason as ChangeReasonCode,
          p_replaced_assignment_id: replacedId || undefined,
          p_new_topic_id: topicId === 'other' ? undefined : topicId,
          p_other_title: topicId === 'other' ? otherTitle.trim() : undefined,
        });
        if (error) throw error;
      }
    },
    onSuccess: async () => {
      await invalidateHouseholdCards(qc);
      setDialog(null);
    },
    onError: (e) => setErrorText(normalizeError(e).message),
  });

  const statusChange = useMutation({
    mutationFn: async () => {
      if (!organizationId || !meetingDialog || (meetingDialog.kind !== 'complete' && meetingDialog.kind !== 'cancel')) return;
      await setMeetingStatus(
        organizationId,
        meetingDialog.meeting.household_meeting_id,
        meetingDialog.kind === 'complete' ? 'completed' : 'cancelled',
      );
    },
    onSuccess: async () => {
      await invalidateHouseholdCards(qc);
      setMeetingDialog(null);
    },
  });

  if (households.length === 0 || !organizationId) return null;

  const open = (d: Exclude<Dialog, null>) => {
    setDialog(d);
    setTopicId('');
    setOtherTitle('');
    setReason('');
    setErrorText(null);
    const active = d.meeting.topics.filter((t) => t.assignment_status !== 'skipped');
    setReplacedId(d.kind === 'change' ? (active[0]?.assignment_id ?? '') : '');
  };

  const today = getTodayNyDate();
  const canSave =
    !save.isPending &&
    (dialog?.kind === 'assign'
      ? !!topicId
      : reason !== '' && (topicId === 'other' ? otherTitle.trim().length > 0 && !!replacedId : !!topicId));

  return (
    <>
      {households.map((hh) => (
        <Card key={hh.household_id} padding="compact" className="space-y-3">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h2 className="text-base font-semibold text-ink">{hh.household_name}</h2>
              <p className="text-xs text-ink-secondary">
                {hh.pastoral_level === 'fraternal'
                  ? 'Fraternal household: members take turns facilitating. Schedule meetings, plan topics and record attendance here.'
                  : hh.can_edit
                    ? 'You lead this household: schedule meetings, plan topics and record attendance here.'
                    : 'Your household meetings and topics. Open a topic to read it during the meeting.'}
              </p>
            </div>
            {hh.can_edit && (
              <Button
                size="sm"
                variant="outline"
                icon={<CalendarPlus className="h-4 w-4" />}
                onClick={() => setMeetingDialog({ kind: 'schedule', household: hh })}
              >
                Schedule meeting
              </Button>
            )}
          </div>
          {hh.meetings.length === 0 ? (
            <p className="text-sm text-ink-muted">No meetings scheduled yet.</p>
          ) : (
            <ul className="divide-y divide-line">
              {hh.meetings.map((m) => {
                const active = m.topics.filter((t) => t.assignment_status !== 'skipped');
                const replaced = m.topics.filter((t) => t.assignment_status === 'skipped');
                const upcoming = m.meeting_status === 'scheduled' && m.meeting_date >= today;
                const dueOrPast = m.meeting_status === 'scheduled' && m.meeting_date <= today;
                const sum = m.attendance_summary;
                const cancelled = m.meeting_status === 'cancelled';
                const place = [m.location_type ? (LOCATION_TYPES[m.location_type] ?? m.location_type) : null, m.location_text]
                  .filter(Boolean)
                  .join(' · ');
                return (
                  <li key={m.household_meeting_id} className={`space-y-1.5 py-3 ${cancelled ? 'opacity-70' : ''}`}>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className={`text-sm font-medium ${cancelled ? 'text-ink-muted line-through' : 'text-ink'}`}>
                        {formatNyDateShort(m.meeting_date)}
                        {m.scheduled_start_at ? ` · ${formatNyTime(m.scheduled_start_at)}` : ''}
                      </span>
                      <Badge variant={cancelled ? 'danger' : m.meeting_status === 'completed' ? 'success' : 'info'}>
                        {cancelled ? 'Cancelled' : m.meeting_status === 'completed' ? 'Completed' : 'Scheduled'}
                      </Badge>
                    </div>
                    {(place || m.host_name) && (
                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-ink-secondary">
                        {place && (
                          <span className="flex items-center gap-1">
                            <MapPin className="h-3.5 w-3.5 text-ink-muted" />
                            {place}
                          </span>
                        )}
                        {m.host_name && <span className="text-ink-muted">Host: {m.host_name}</span>}
                      </div>
                    )}
                    {!cancelled && hh.can_edit && sum && (sum.recorded_attendance_count > 0 || m.meeting_status === 'completed') && (
                      <p className="text-xs text-ink-secondary">
                        {sum.recorded_attendance_count > 0
                          ? `Attendance: ${sum.present_count} present · ${sum.absent_count} absent · ${sum.excused_count} excused` +
                            (sum.attendance_complete ? '' : ` (${sum.expected_member_count - sum.recorded_attendance_count} not marked)`)
                          : 'Attendance not recorded yet.'}
                      </p>
                    )}
                    {!cancelled && !hh.can_edit && m.my_attendance && (
                      <p className="text-xs text-ink-secondary">You: {ATTENDANCE_LABELS[m.my_attendance]}</p>
                    )}
                    {active.map((t) => (
                      <div key={t.assignment_id} className="text-sm text-ink">
                        <span className="text-ink-secondary">
                          {t.assignment_status === 'completed' ? 'Used: ' : 'Topic: '}
                        </span>
                        {t.title}
                        {t.is_library_topic && (
                          <Link to={`/app/library/${t.topic_id}`} className="ml-2 text-primary hover:underline">
                            Open topic
                          </Link>
                        )}
                        {t.replaces_title && (
                          <span className="block text-xs text-ink-muted">
                            Used instead of “{t.replaces_title}” — {changeReasonLabel(t.change_reason_code)}
                          </span>
                        )}
                      </div>
                    ))}
                    {replaced.map((t) => (
                      <div key={t.assignment_id} className="text-xs text-ink-muted">
                        <span className="line-through">{t.title}</span> — replaced
                        {t.replaced_by_title ? ` by “${t.replaced_by_title}”` : ''}
                        {t.change_reason_code ? ` (${changeReasonLabel(t.change_reason_code)})` : ''}
                      </div>
                    ))}
                    {!hh.can_edit && !cancelled && active.length === 0 && (
                      <p className="text-xs text-ink-muted">No topic planned yet.</p>
                    )}
                    {hh.can_edit && !cancelled && (<div className="flex flex-wrap gap-2 pt-1">
                      {m.meeting_date <= today && (
                        <Button
                          size="sm"
                          variant={dueOrPast ? 'primary' : 'outline'}
                          onClick={() => setMeetingDialog({ kind: 'attendance', household: hh, meeting: m })}
                        >
                          {sum && sum.recorded_attendance_count > 0 ? 'Update attendance' : 'Record attendance'}
                        </Button>
                      )}
                      {dueOrPast && (
                        <Button size="sm" variant="outline" onClick={() => { statusChange.reset(); setMeetingDialog({ kind: 'complete', household: hh, meeting: m }); }}>
                          Mark completed
                        </Button>
                      )}
                      {upcoming && active.length === 0 && (
                        <Button size="sm" variant="outline" onClick={() => open({ kind: 'assign', meeting: m })}>
                          Choose topic
                        </Button>
                      )}
                      {(active.length > 0 || m.meeting_status === 'completed') && (
                        <Button size="sm" variant="ghost" onClick={() => open({ kind: 'change', meeting: m })}>
                          {active.length > 0 ? 'Change topic used' : 'Record topic used'}
                        </Button>
                      )}
                      {m.meeting_status === 'scheduled' && (
                        <>
                          <Button size="sm" variant="ghost" onClick={() => setMeetingDialog({ kind: 'edit', household: hh, meeting: m })}>
                            Edit / reschedule
                          </Button>
                          <Button size="sm" variant="ghost" onClick={() => { statusChange.reset(); setMeetingDialog({ kind: 'cancel', household: hh, meeting: m }); }}>
                            Cancel meeting
                          </Button>
                        </>
                      )}
                    </div>)}
                  </li>
                );
              })}
            </ul>
          )}
        </Card>
      ))}

      {(meetingDialog?.kind === 'schedule' || meetingDialog?.kind === 'edit') && (
        <HouseholdMeetingFormModal
          organizationId={organizationId}
          householdId={meetingDialog.household.household_id}
          householdName={meetingDialog.household.household_name}
          meeting={meetingDialog.kind === 'edit' ? meetingDialog.meeting : null}
          onClose={() => setMeetingDialog(null)}
        />
      )}

      {meetingDialog?.kind === 'attendance' && (
        <HouseholdAttendanceModal
          organizationId={organizationId}
          householdName={meetingDialog.household.household_name}
          meeting={meetingDialog.meeting}
          onClose={() => setMeetingDialog(null)}
        />
      )}

      {(meetingDialog?.kind === 'complete' || meetingDialog?.kind === 'cancel') && (
        <Modal
          open
          onClose={() => setMeetingDialog(null)}
          title={meetingDialog.kind === 'complete' ? 'Mark meeting completed?' : 'Cancel this meeting?'}
          description={`${meetingDialog.household.household_name} · ${formatNyDateShort(meetingDialog.meeting.meeting_date)}`}
          footer={
            <div className="flex w-full justify-end gap-2">
              <Button variant="ghost" onClick={() => setMeetingDialog(null)} disabled={statusChange.isPending}>
                Back
              </Button>
              <Button
                variant={meetingDialog.kind === 'cancel' ? 'danger' : 'primary'}
                onClick={() => statusChange.mutate()}
                loading={statusChange.isPending}
              >
                {meetingDialog.kind === 'complete' ? 'Mark completed' : 'Cancel meeting'}
              </Button>
            </div>
          }
        >
          <div className="space-y-3">
            {statusChange.error && (
              <Alert variant="danger" title="Could not save">
                {normalizeError(statusChange.error).message}
              </Alert>
            )}
            <p className="text-sm text-ink-secondary">
              {meetingDialog.kind === 'complete'
                ? 'Its planned topic is marked as used. You can still record attendance afterwards.'
                : 'Members will see it as cancelled. A planned topic stays planned and can be chosen for another meeting.'}
            </p>
          </div>
        </Modal>
      )}

      {dialog && (
        <Modal
          open
          onClose={() => setDialog(null)}
          title={dialog.kind === 'assign' ? 'Choose topic' : 'Topic used'}
          description={`Meeting on ${formatNyDateShort(dialog.meeting.meeting_date)}`}
          footer={
            <div className="flex w-full justify-end gap-2">
              <Button variant="ghost" onClick={() => setDialog(null)} disabled={save.isPending}>
                Cancel
              </Button>
              <Button onClick={() => save.mutate()} disabled={!canSave} loading={save.isPending}>
                Save
              </Button>
            </div>
          }
        >
          <div className="space-y-4">
            {errorText && <Alert variant="danger" title="Could not save">{errorText}</Alert>}

            {dialog.kind === 'change' &&
              dialog.meeting.topics.some((t) => t.assignment_status !== 'skipped') && (
                <label className="block">
                  <span className="mb-1 block text-xs font-medium text-ink-secondary">Planned topic being replaced</span>
                  <Select value={replacedId} onChange={(e) => setReplacedId(e.target.value)}>
                    {dialog.meeting.topics
                      .filter((t) => t.assignment_status !== 'skipped')
                      .map((t) => (
                        <option key={t.assignment_id} value={t.assignment_id}>
                          {t.title}
                        </option>
                      ))}
                    <option value="">None — this was an additional topic</option>
                  </Select>
                </label>
              )}

            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">
                {dialog.kind === 'assign' ? 'Household topic' : 'Topic actually used'}
              </span>
              <Select value={topicId} onChange={(e) => setTopicId(e.target.value)}>
                <option value="">— Select a topic —</option>
                {libraryByMonth.map(([month, list]) => (
                  <optgroup key={month} label={`Household Library — ${formatTopicMonth(month)}`}>
                    {list.map((t) => (
                      <option key={t.topic_id} value={t.topic_id}>
                        {t.title} ({materialKindLabel(t.kind)})
                      </option>
                    ))}
                  </optgroup>
                ))}
                {dialog.kind === 'change' && replacedId && <option value="other">Not in the list — type the topic</option>}
              </Select>
            </label>

            {dialog.kind === 'change' && topicId === 'other' && (
              <label className="block">
                <span className="mb-1 block text-xs font-medium text-ink-secondary">Topic title</span>
                <Input value={otherTitle} maxLength={200} onChange={(e) => setOtherTitle(e.target.value)} />
              </label>
            )}

            {dialog.kind === 'change' && (
              <label className="block">
                <span className="mb-1 block text-xs font-medium text-ink-secondary">Reason for the change</span>
                <Select value={reason} onChange={(e) => setReason(e.target.value as ChangeReasonCode | '')}>
                  <option value="">— Select a reason —</option>
                  {CHANGE_REASONS.map((r) => (
                    <option key={r.code} value={r.code}>
                      {r.label}
                    </option>
                  ))}
                </Select>
              </label>
            )}

            {libraryByMonth.length === 0 && (
              <p className="flex items-center gap-2 text-xs text-ink-muted">
                <BookOpenText className="h-4 w-4" /> No approved topics in the Household Library yet.
              </p>
            )}
          </div>
        </Modal>
      )}
    </>
  );
}

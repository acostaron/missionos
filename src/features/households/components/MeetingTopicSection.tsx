// Topic(s) for one household meeting, with "Open topic" and "Change topic used" (Pass 9.4, Claude 2026-10-15)
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { changeReasonLabel, useHouseholdMeetingTopics, type MeetingTopic } from '../api/meeting-topics';
import { ChangeMeetingTopicModal } from './ChangeMeetingTopicModal';

export function MeetingTopicSection({
  organizationId,
  householdId,
  meetingId,
  meetingDate,
  meetingStatus,
  pastoralLevel,
  canManage,
  onSuccessToast,
}: {
  organizationId: string;
  householdId: string;
  meetingId: string;
  meetingDate: string;
  meetingStatus: 'scheduled' | 'completed' | 'cancelled';
  pastoralLevel?: string | null;
  canManage: boolean;
  onSuccessToast?: (msg: string) => void;
}) {
  const { data: all = [], isLoading } = useHouseholdMeetingTopics(organizationId, householdId);
  const [isChangeOpen, setIsChangeOpen] = useState(false);

  const topics = all.filter((t) => t.household_meeting_id === meetingId);
  const active = topics.filter((t) => t.assignment_status !== 'skipped');
  const replaced = topics.filter((t) => t.assignment_status === 'skipped');

  const label = (t: MeetingTopic) =>
    t.assignment_status === 'completed' ? 'Used' : 'Planned';

  return (
    <div className="rounded-lg border border-slate-700/60 bg-slate-800/40 p-4">
      <div className="mb-2 flex items-center justify-between gap-2">
        <h3 className="text-xs font-semibold text-slate-300">Topic</h3>
        {canManage && meetingStatus !== 'cancelled' && (
          <button
            type="button"
            onClick={() => setIsChangeOpen(true)}
            className="rounded-lg border border-indigo-700/60 bg-indigo-950/40 px-3 py-1 text-[10px] font-medium text-indigo-300 hover:bg-indigo-950/70 transition-colors"
          >
            {active.length > 0 ? 'Change topic used' : 'Record topic used'}
          </button>
        )}
      </div>

      {isLoading ? (
        <p className="text-xs text-slate-500">Loading…</p>
      ) : active.length === 0 && replaced.length === 0 ? (
        <p className="text-xs text-slate-400">No topic is linked to this meeting. Use “Assign Household Topic” to plan one.</p>
      ) : (
        <ul className="space-y-2">
          {active.map((t) => (
            <li key={t.assignment_id} className="text-xs">
              <div className="flex flex-wrap items-center gap-2">
                <span className="rounded-full border border-slate-600 px-2 py-0.5 text-[10px] text-slate-300">{label(t)}</span>
                <span className="font-medium text-slate-100">{t.title}</span>
                {t.is_library_topic && (
                  <Link to={`/app/library/${t.topic_id}`} className="text-indigo-300 underline-offset-2 hover:underline">
                    Open topic
                  </Link>
                )}
              </div>
              {t.replaces_title && (
                <p className="mt-1 text-[11px] text-slate-400">
                  Used instead of “{t.replaces_title}”{t.change_reason_code ? ` — ${changeReasonLabel(t.change_reason_code)}` : ''}
                </p>
              )}
            </li>
          ))}
          {replaced.map((t) => (
            <li key={t.assignment_id} className="text-xs">
              <div className="flex flex-wrap items-center gap-2">
                <span className="rounded-full border border-amber-700/60 px-2 py-0.5 text-[10px] text-amber-300">Replaced</span>
                <span className="text-slate-400 line-through">{t.title}</span>
              </div>
              <p className="mt-1 text-[11px] text-slate-400">
                {t.replaced_by_title ? `Replaced by “${t.replaced_by_title}”` : 'Replaced'}
                {t.change_reason_code ? ` — ${changeReasonLabel(t.change_reason_code)}` : ''}
              </p>
            </li>
          ))}
        </ul>
      )}

      {canManage && isChangeOpen && (
        <ChangeMeetingTopicModal
          isOpen={isChangeOpen}
          onClose={() => setIsChangeOpen(false)}
          organizationId={organizationId}
          meetingId={meetingId}
          meetingDate={meetingDate}
          plannedTopics={active}
          pastoralLevel={pastoralLevel}
          onSuccessToast={onSuccessToast}
        />
      )}
    </div>
  );
}

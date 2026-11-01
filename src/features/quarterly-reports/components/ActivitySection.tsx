import { Badge, Card } from '../../../components/ui';
import type { AnyReportActivity, ReportFormationItem } from '../types';
import { activityTitle } from '../types';
import {
  NONE_REPORTED,
  completionLabel,
  formatDateRange,
  hierarchyLabel,
  humanize,
  participantsLabel,
  priorityLabel,
} from '../format';

function ActivityCard({ a, kindLabel }: { a: AnyReportActivity; kindLabel: string }) {
  const formation = 'source_kind' in a ? (a as ReportFormationItem) : null;
  return (
    <li className="rounded-lg border border-slate-200 p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <h3 className="font-semibold text-slate-900">{activityTitle(a)}</h3>
        <div className="flex gap-1">
          <Badge variant="neutral">{kindLabel}</Badge>
          <Badge variant={a.report_priority === 'major_highlight' ? 'success' : 'info'}>{priorityLabel(a.report_priority)}</Badge>
        </div>
      </div>
      <p className="mt-1 text-xs text-slate-500">
        {formatDateRange(a.activity_start_date, a.activity_end_date)} · {a.location ?? 'Venue not recorded'} · {hierarchyLabel(a)}
      </p>
      {a.report_highlight?.trim() ? (
        <p className="mt-2 whitespace-pre-line text-sm text-slate-700">{a.report_highlight}</p>
      ) : (
        <p className="mt-2 text-sm italic text-slate-400">No reporting highlight recorded.</p>
      )}
      {formation && (
        <p className="mt-2 text-xs text-slate-600">
          Participants: {participantsLabel(formation)} · Attendance: {formation.attendance_count ?? 'Not recorded'} · Completion:{' '}
          {completionLabel(formation)}
        </p>
      )}
      {!formation && a.participant_count !== null && (
        <p className="mt-2 text-xs text-slate-600">Registered participants: {a.participant_count}</p>
      )}
      {a.speakers.length > 0 && (
        <p className="mt-2 text-xs text-slate-600">
          <span className="font-medium">Speakers:</span>{' '}
          {a.speakers
            .map((s) => `${s.name ?? 'Unnamed'} (${humanize(s.speaker_role)}${s.topic_title ? `; ${s.topic_title}` : ''}${!s.is_member && s.external_organization ? `; ${s.external_organization}` : ''})`)
            .join(' · ')}
        </p>
      )}
      {a.service_team.length > 0 && (
        <p className="mt-1 text-xs text-slate-600">
          <span className="font-medium">Service team:</span>{' '}
          {a.service_team.map((m) => `${m.name ?? 'Unnamed'} (${m.role_label ?? humanize(m.role_code)})`).join(' · ')}
        </p>
      )}
      <p className="mt-1 text-xs text-slate-400">{a.selected_photos.length} selected photo(s)</p>
    </li>
  );
}

interface Props {
  title: string;
  items: AnyReportActivity[];
  kindLabel: (a: AnyReportActivity) => string;
  groups?: { label: string; filter: (a: AnyReportActivity) => boolean }[];
}

export function ActivitySection({ title, items, kindLabel, groups }: Props) {
  const renderList = (list: AnyReportActivity[]) =>
    list.length ? (
      <ul className="space-y-3">
        {list.map((a) => (
          <ActivityCard key={a.source_id} a={a} kindLabel={kindLabel(a)} />
        ))}
      </ul>
    ) : (
      <p className="text-sm italic text-slate-400">{NONE_REPORTED}</p>
    );
  return (
    <Card>
      <h2 className="mb-3 text-base font-semibold text-slate-900">{title}</h2>
      {groups
        ? groups.map((g) => (
            <div key={g.label} className="mb-4 last:mb-0">
              <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-amber-700">{g.label}</h3>
              {renderList(items.filter(g.filter))}
            </div>
          ))
        : renderList(items)}
    </Card>
  );
}

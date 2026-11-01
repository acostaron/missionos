import { Card, StatCard } from '../../../components/ui';
import type { ReportSummary } from '../types';
import { COMPLETION_NOT_RECORDED } from '../format';

export function SummarySection({ summary: s }: { summary: ReportSummary }) {
  const completion =
    s.completion_known_activities === 0
      ? COMPLETION_NOT_RECORDED
      : `${s.known_completions ?? 0} known`;
  return (
    <Card>
      <h2 className="mb-3 text-base font-semibold text-slate-900">Quarter Summary</h2>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatCard label="Active members" value={s.total_active_members ?? '—'} context="From census snapshot" />
        {s.branch_totals.map((b) => (
          <StatCard key={b.branch_name} label={b.branch_name} value={b.active_member_count} />
        ))}
        <StatCard label="Reportable Events" value={s.reportable_events} />
        <StatCard label="Reportable Programs" value={s.reportable_programs} />
        <StatCard label="CLS conducted" value={s.cls_count} context={`${s.cls_registered_participants} registered`} />
        <StatCard label="LCS conducted" value={s.lcs_count} context={`${s.lcs_registered_participants} registered`} />
        <StatCard label="Formation sessions" value={s.formation_count} />
        <StatCard
          label="Completions"
          value={completion}
          context={`Unavailable for ${s.completion_unavailable_activities} activities`}
        />
        <StatCard label="Selected photos" value={s.selected_photos} />
        <StatCard label="Speakers / Service" value={`${s.speaker_assignments} / ${s.service_team_assignments}`} />
      </div>
    </Card>
  );
}

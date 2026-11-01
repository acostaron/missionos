import { Alert, Card } from '../../../components/ui';
import type { ReportCensus } from '../types';
import { formatDate, humanize } from '../format';

export function CensusSection({ census }: { census: ReportCensus }) {
  return (
    <Card>
      <h2 className="mb-3 text-base font-semibold text-slate-900">Quarterly Census</h2>
      {!census.available ? (
        <Alert variant="danger" title="No census snapshot">
          This reporting period has no census snapshot. The report cannot be approved until the quarterly census is captured
          and approved.
        </Alert>
      ) : (
        <>
          <p className="mb-3 text-xs text-slate-500">
            Snapshot {formatDate(census.snapshot_date)} · census status {humanize(census.census_period_status)}
          </p>
          <div className="mb-4 flex flex-wrap gap-3">
            <div className="rounded-lg bg-slate-50 px-4 py-2">
              <p className="text-xs text-slate-500">Total active members</p>
              <p className="text-xl font-semibold tabular-nums">{census.total_active_members}</p>
            </div>
            {(census.branches ?? []).map((b) => (
              <div key={b.branch_name} className="rounded-lg bg-slate-50 px-4 py-2">
                <p className="text-xs text-slate-500">{b.branch_name}</p>
                <p className="text-xl font-semibold tabular-nums">{b.active_member_count}</p>
              </div>
            ))}
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-left text-xs uppercase text-slate-500">
                <tr>
                  <th className="py-1 pr-3">Branch</th>
                  <th className="py-1 pr-3">Section</th>
                  <th className="py-1 pr-3">Category</th>
                  <th className="py-1 text-right">Active</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {(census.sections ?? []).map((r) => (
                  <tr key={r.section_code}>
                    <td className="py-1 pr-3">{r.branch_name ?? '—'}</td>
                    <td className="py-1 pr-3">{r.section_name}</td>
                    <td className="py-1 pr-3">{humanize(r.section_category)}</td>
                    <td className="py-1 text-right tabular-nums">{r.active_member_count}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </Card>
  );
}

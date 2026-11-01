import { Badge, Select } from '../../../components/ui';
import type { QuarterlyPeriodSummary } from '../types';
import { STATUS_BADGE } from '../format';

interface Props {
  periods: QuarterlyPeriodSummary[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}

export function QuarterSelector({ periods, selectedId, onSelect }: Props) {
  const selected = periods.find((p) => p.reporting_period_id === selectedId);
  return (
    <div className="flex flex-wrap items-end gap-3">
      <div className="min-w-[220px]">
        <label htmlFor="quarterly-report-period" className="mb-1 block text-xs font-medium text-slate-600">
          Reporting quarter
        </label>
        <Select
          id="quarterly-report-period"
          value={selectedId ?? ''}
          onChange={(e) => onSelect(e.target.value)}
        >
          {periods.map((p) => (
            <option key={p.reporting_period_id} value={p.reporting_period_id}>
              {p.period_label} — {STATUS_BADGE[p.report.status].label}
            </option>
          ))}
        </Select>
      </div>
      {selected && (
        <div className="flex items-center gap-2 pb-2 text-sm">
          <Badge variant={STATUS_BADGE[selected.report.status].variant}>
            Report: {STATUS_BADGE[selected.report.status].label}
          </Badge>
          <Badge variant={selected.census_status === 'approved' ? 'success' : 'neutral'}>
            Census: {selected.census_status}
          </Badge>
        </div>
      )}
    </div>
  );
}

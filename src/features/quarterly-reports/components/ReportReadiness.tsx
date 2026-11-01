import { AlertTriangle, CheckCircle2, XCircle } from 'lucide-react';
import { Card } from '../../../components/ui';
import type { QuarterlyReportDocument } from '../types';

function Row({ ok, label, detail, blocking }: { ok: boolean; label: string; detail: string; blocking?: boolean }) {
  const Icon = ok ? CheckCircle2 : blocking ? XCircle : AlertTriangle;
  const color = ok ? 'text-emerald-600' : blocking ? 'text-red-600' : 'text-amber-600';
  return (
    <li className="flex items-start gap-2 py-1.5">
      <Icon className={`mt-0.5 h-4 w-4 shrink-0 ${color}`} aria-hidden />
      <div>
        <p className="text-sm font-medium text-slate-800">{label}</p>
        <p className="text-xs text-slate-500">{detail}</p>
      </div>
    </li>
  );
}

export function ReportReadiness({ doc }: { doc: QuarterlyReportDocument }) {
  const { blocking, warnings } = doc.readiness;
  const activities = doc.major_highlights.length + doc.other_activities.length + doc.formation_items.length;
  return (
    <Card>
      <h2 className="mb-2 text-base font-semibold text-slate-900">Readiness</h2>
      <ul className="grid gap-x-6 sm:grid-cols-2">
        <Row
          blocking
          ok={blocking.census_snapshot_exists}
          label="Census snapshot"
          detail={blocking.census_snapshot_exists ? 'Ready' : 'Missing — approval is blocked'}
        />
        <Row
          blocking
          ok={blocking.census_approved}
          label="Census approved"
          detail={blocking.census_approved ? 'Ready' : 'Approve the quarterly census first — approval is blocked'}
        />
        <Row ok label="Reportable activities" detail={String(activities)} />
        <Row ok label="Selected photos" detail={String(doc.summary.selected_photos)} />
        <Row ok={warnings.missing_highlight === 0} label="Missing highlights" detail={`${warnings.missing_highlight} activities`} />
        <Row ok={warnings.missing_photos === 0} label="No selected photo" detail={`${warnings.missing_photos} activities`} />
        <Row ok={warnings.missing_speakers === 0} label="No speakers" detail={`${warnings.missing_speakers} activities`} />
        <Row ok={warnings.missing_service_team === 0} label="No service team" detail={`${warnings.missing_service_team} activities`} />
        <Row
          ok={warnings.completion_unavailable === 0}
          label="Completion data"
          detail={
            warnings.completion_unavailable === 0
              ? 'Recorded for all CLS/LCS/Formation items'
              : `Not recorded for ${warnings.completion_unavailable} CLS/LCS/Formation items`
          }
        />
      </ul>
      <p className="mt-2 text-xs text-slate-500">Warnings are informational and do not block approval.</p>
    </Card>
  );
}

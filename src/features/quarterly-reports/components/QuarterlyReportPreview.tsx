import type { QuarterlyReportDocument, ReportActivity, ReportFormationItem } from '../types';
import { SOURCE_KIND_LABEL, humanize } from '../format';
import { SummarySection } from './SummarySection';
import { CensusSection } from './CensusSection';
import { ActivitySection } from './ActivitySection';
import { PhotoSection } from './PhotoSection';

const genericKind = (a: ReportActivity) => (a.activity_kind === 'program' ? humanize(a.activity_type) : 'Event');

/** Screen preview in the same order as the PDF: summary, census, highlights, other, formation, photos. */
export function QuarterlyReportPreview({ doc }: { doc: QuarterlyReportDocument }) {
  return (
    <div className="space-y-4">
      <SummarySection summary={doc.summary} />
      <CensusSection census={doc.census} />
      <ActivitySection
        title="Major Highlights"
        items={doc.major_highlights}
        kindLabel={(a) => genericKind(a as ReportActivity)}
      />
      <ActivitySection
        title="Other Ministry Activities"
        items={doc.other_activities}
        kindLabel={(a) => genericKind(a as ReportActivity)}
      />
      <ActivitySection
        title="CLS / LCS / Formal Formation"
        items={doc.formation_items}
        kindLabel={(a) => SOURCE_KIND_LABEL[(a as ReportFormationItem).source_kind]}
        groups={(['cls', 'lcs', 'formation'] as const).map((k) => ({
          label: SOURCE_KIND_LABEL[k],
          filter: (a) => (a as ReportFormationItem).source_kind === k,
        }))}
      />
      <PhotoSection activities={[...doc.major_highlights, ...doc.other_activities, ...doc.formation_items]} />
    </div>
  );
}

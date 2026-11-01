import ExcelJS from 'exceljs';
import type { AnyReportActivity, QuarterlyReportDocument } from '../types';
import { activityTitle } from '../types';
import { SOURCE_KIND_LABEL, STAGE_SHEET_STATUS, formatTimestamp, humanize, priorityLabel, sortedPhotos } from '../format';
import type { ExportStage } from '../format';

export const EXCEL_SHEETS = [
  'Summary',
  'Census',
  'Activities',
  'CLS-LCS-Formation',
  'Speakers',
  'Service Team',
  'Photos',
] as const;

const NOT_RECORDED = 'Not recorded';

function styleHeader(ws: ExcelJS.Worksheet) {
  const row = ws.getRow(1);
  row.font = { bold: true, color: { argb: 'FFFFFFFF' } };
  row.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1E2952' } };
  ws.views = [{ state: 'frozen', ySplit: 1 }];
}

function kindOf(a: AnyReportActivity): string {
  return 'source_kind' in a ? SOURCE_KIND_LABEL[a.source_kind] : humanize(a.activity_kind);
}

/**
 * Workbook built purely from a report document (approved snapshot or draft).
 * Photos are referenced by photo ID + storage path; no signed URLs are written.
 */
export async function buildQuarterlyReportWorkbook(
  doc: QuarterlyReportDocument,
  opts: { stage: ExportStage }
): Promise<ArrayBuffer> {
  const wb = new ExcelJS.Workbook();
  wb.creator = 'MissionOS';
  wb.created = new Date(doc.header.generated_at);
  const h = doc.header;
  const s = doc.summary;

  const summary = wb.addWorksheet('Summary');
  summary.columns = [
    { header: 'Field', key: 'k', width: 40 },
    { header: 'Value', key: 'v', width: 60 },
  ];
  const sRows: [string, string | number | null][] = [
    ['Organization', h.organization_name],
    ['Area', h.area_name],
    ['Report', h.report_title],
    ['Reporting year', h.period_year],
    ['Reporting quarter', h.period_quarter],
    ['Period start', h.period_start],
    ['Period end', h.period_end],
    ['Report status', STAGE_SHEET_STATUS[opts.stage]],
    ['Generated', formatTimestamp(h.generated_at)],
    ['Approved at', doc.approval ? formatTimestamp(doc.approval.approved_at) : null],
    ['Approved by', doc.approval?.approved_by_name ?? null],
    ['Schema version', doc.schema_version],
    ['Total active members', s.total_active_members],
    ...s.branch_totals.map((b) => [`${b.branch_name} total`, b.active_member_count] as [string, number]),
    ['Reportable Events', s.reportable_events],
    ['Reportable Programs', s.reportable_programs],
    ['CLS conducted', s.cls_count],
    ['LCS conducted', s.lcs_count],
    ['Formal Formation sessions', s.formation_count],
    ['Registered CLS participants', s.cls_registered_participants],
    ['Registered LCS participants', s.lcs_registered_participants],
    ['Known completions', s.known_completions ?? NOT_RECORDED],
    ['Activities with completion data', s.completion_known_activities],
    ['Activities without completion data', s.completion_unavailable_activities],
    ['Selected report photos', s.selected_photos],
    ['Speaker assignments', s.speaker_assignments],
    ['Service-team assignments', s.service_team_assignments],
  ];
  sRows.forEach(([k, v]) => summary.addRow({ k, v: v ?? '' }));
  styleHeader(summary);

  const census = wb.addWorksheet('Census');
  census.columns = [
    { header: 'Branch / Sub-area', key: 'branch', width: 24 },
    { header: 'Section code', key: 'code', width: 16 },
    { header: 'Section', key: 'name', width: 32 },
    { header: 'Category', key: 'cat', width: 16 },
    { header: 'Active members', key: 'count', width: 16 },
  ];
  if (doc.census.available) {
    (doc.census.sections ?? []).forEach((r) =>
      census.addRow({ branch: r.branch_name ?? '', code: r.section_code, name: r.section_name, cat: r.section_category ?? '', count: r.active_member_count })
    );
    if (doc.census.uncategorized_active_members) {
      census.addRow({ name: 'Uncategorized', count: doc.census.uncategorized_active_members });
    }
    census.addRow({ name: 'Total active members', count: doc.census.total_active_members ?? 0 }).font = { bold: true };
  } else {
    census.addRow({ name: 'No census snapshot exists for this reporting period' });
  }
  styleHeader(census);

  const generic = [...doc.major_highlights, ...doc.other_activities];
  const acts = wb.addWorksheet('Activities');
  acts.columns = [
    { header: 'Date', key: 'date', width: 12 },
    { header: 'End date', key: 'end', width: 12 },
    { header: 'Kind', key: 'kind', width: 10 },
    { header: 'Type', key: 'type', width: 18 },
    { header: 'Title', key: 'title', width: 40 },
    { header: 'Branch', key: 'branch', width: 18 },
    { header: 'Section', key: 'section', width: 28 },
    { header: 'Chapter', key: 'chapter', width: 18 },
    { header: 'Audience', key: 'aud', width: 22 },
    { header: 'Venue', key: 'venue', width: 28 },
    { header: 'Meeting type', key: 'mt', width: 14 },
    { header: 'Registered participants', key: 'pc', width: 14 },
    { header: 'Priority', key: 'prio', width: 18 },
    { header: 'Highlight', key: 'hl', width: 60 },
  ];
  generic.forEach((a) =>
    acts.addRow({
      date: a.activity_start_date ?? '',
      end: a.activity_end_date ?? '',
      kind: humanize(a.activity_kind),
      type: humanize(a.activity_type),
      title: a.title,
      branch: a.branch_name ?? '',
      section: a.section_names.join(', '),
      chapter: a.chapter_name ?? '',
      aud: a.audience_name ?? '',
      venue: a.location ?? '',
      mt: humanize(a.meeting_type),
      pc: a.participant_count ?? '',
      prio: priorityLabel(a.report_priority),
      hl: a.report_highlight ?? '',
    })
  );
  styleHeader(acts);

  const form = wb.addWorksheet('CLS-LCS-Formation');
  form.columns = [
    { header: 'source_kind', key: 'kind', width: 12 },
    { header: 'Title', key: 'title', width: 40 },
    { header: 'Formation program', key: 'fp', width: 26 },
    { header: 'Formation talk', key: 'ft', width: 26 },
    { header: 'Date', key: 'date', width: 12 },
    { header: 'End date', key: 'end', width: 12 },
    { header: 'Venue', key: 'venue', width: 28 },
    { header: 'Branch', key: 'branch', width: 18 },
    { header: 'Section', key: 'section', width: 28 },
    { header: 'Chapter', key: 'chapter', width: 18 },
    { header: 'Participants', key: 'pc', width: 14 },
    { header: 'Attendance', key: 'att', width: 12 },
    { header: 'Attendance definition', key: 'attdef', width: 40 },
    { header: 'Completion', key: 'comp', width: 14 },
    { header: 'completion_data_available', key: 'compok', width: 14 },
    { header: 'Priority', key: 'prio', width: 18 },
    { header: 'Highlight', key: 'hl', width: 60 },
  ];
  doc.formation_items.forEach((f) =>
    form.addRow({
      kind: f.source_kind,
      title: f.source_title,
      fp: f.formation_program_title ?? '',
      ft: f.formation_talk_title ?? '',
      date: f.activity_start_date ?? '',
      end: f.activity_end_date ?? '',
      venue: f.location ?? '',
      branch: f.branch_name ?? '',
      section: f.section_names.join(', '),
      chapter: f.chapter_name ?? '',
      pc: f.participant_count_is_authoritative && f.participant_count !== null ? f.participant_count : 'Not tracked',
      att: f.attendance_count ?? NOT_RECORDED,
      attdef: f.attendance_count_definition ?? '',
      comp: f.completion_data_available && f.completion_count !== null ? f.completion_count : NOT_RECORDED,
      compok: f.completion_data_available ? 'Yes' : 'No',
      prio: priorityLabel(f.report_priority),
      hl: f.report_highlight ?? '',
    })
  );
  styleHeader(form);

  const all: AnyReportActivity[] = [...generic, ...doc.formation_items];

  const spk = wb.addWorksheet('Speakers');
  spk.columns = [
    { header: 'Activity', key: 'act', width: 40 },
    { header: 'Activity kind', key: 'kind', width: 16 },
    { header: 'Speaker', key: 'name', width: 28 },
    { header: 'Member', key: 'mem', width: 10 },
    { header: 'Role', key: 'role', width: 18 },
    { header: 'Topic', key: 'topic', width: 32 },
    { header: 'Session', key: 'sess', width: 18 },
    { header: 'External title', key: 'xt', width: 20 },
    { header: 'Organization / parish', key: 'xo', width: 28 },
  ];
  all.forEach((a) =>
    a.speakers.forEach((sp) =>
      spk.addRow({
        act: activityTitle(a),
        kind: kindOf(a),
        name: sp.name ?? '',
        mem: sp.is_member ? 'Yes' : 'No',
        role: humanize(sp.speaker_role),
        topic: sp.topic_title ?? '',
        sess: sp.session_label ?? (sp.session_number ? `Session ${sp.session_number}` : ''),
        xt: sp.external_title ?? '',
        xo: sp.external_organization ?? '',
      })
    )
  );
  styleHeader(spk);

  const svc = wb.addWorksheet('Service Team');
  svc.columns = [
    { header: 'Activity', key: 'act', width: 40 },
    { header: 'Activity kind', key: 'kind', width: 16 },
    { header: 'Name', key: 'name', width: 28 },
    { header: 'Member', key: 'mem', width: 10 },
    { header: 'Service role', key: 'role', width: 24 },
    { header: 'Team group', key: 'grp', width: 20 },
  ];
  all.forEach((a) =>
    a.service_team.forEach((m) =>
      svc.addRow({
        act: activityTitle(a),
        kind: kindOf(a),
        name: m.name ?? '',
        mem: m.is_member ? 'Yes' : 'No',
        role: m.role_label ?? humanize(m.role_code),
        grp: m.team_group ?? '',
      })
    )
  );
  styleHeader(svc);

  const ph = wb.addWorksheet('Photos');
  ph.columns = [
    { header: 'Activity', key: 'act', width: 40 },
    { header: 'Activity kind', key: 'kind', width: 16 },
    { header: 'Caption', key: 'cap', width: 50 },
    { header: 'report_sort_order', key: 'ord', width: 16 },
    { header: 'Session', key: 'sess', width: 10 },
    { header: 'Photo ID', key: 'id', width: 38 },
    { header: 'Storage reference', key: 'ref', width: 60 },
  ];
  all.forEach((a) =>
    sortedPhotos(a.selected_photos).forEach((p) =>
      ph.addRow({
        act: activityTitle(a),
        kind: kindOf(a),
        cap: p.caption ?? '',
        ord: p.report_sort_order ?? '',
        sess: p.session_number ?? '',
        id: p.photo_id,
        ref: `${p.storage_bucket}/${p.storage_path}`,
      })
    )
  );
  styleHeader(ph);

  return (await wb.xlsx.writeBuffer()) as ArrayBuffer;
}

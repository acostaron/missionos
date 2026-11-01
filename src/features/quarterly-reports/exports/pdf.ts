import { jsPDF } from 'jspdf';
import autoTable from 'jspdf-autotable';
import type { AnyReportActivity, QuarterlyReportDocument, ReportFormationItem, ReportPhoto } from '../types';
import { activityTitle } from '../types';
import {
  COMPLETION_NOT_RECORDED,
  NONE_REPORTED,
  PDF_PHOTOS_PER_ACTIVITY,
  SOURCE_KIND_LABEL,
  completionLabel,
  formatDate,
  formatDateRange,
  formatTimestamp,
  hierarchyLabel,
  humanize,
  participantsLabel,
  priorityLabel,
  sortedPhotos,
  STAGE_STATUS_TEXT,
  STAGE_WATERMARK,
} from '../format';
import type { ExportStage } from '../format';

/** Loaded image ready for jsPDF (JPEG data URL + intrinsic size). */
export interface LoadedImage {
  dataUrl: string;
  width: number;
  height: number;
}

export type ImageLoader = (photo: ReportPhoto) => Promise<LoadedImage | null>;

export interface PdfBuildOptions {
  stage: ExportStage;
  loadImage?: ImageLoader;
}

export interface PdfBuildResult {
  bytes: ArrayBuffer;
  warnings: string[];
}

const NAVY: [number, number, number] = [30, 41, 82];
const GOLD: [number, number, number] = [176, 137, 64];
const GREY: [number, number, number] = [100, 106, 120];
const MARGIN = 48;

/**
 * Deterministic client-side PDF built purely from a report document.
 * For approved reports the document is the immutable approved snapshot.
 */
export async function buildQuarterlyReportPdf(
  doc: QuarterlyReportDocument,
  opts: PdfBuildOptions
): Promise<PdfBuildResult> {
  const warnings: string[] = [];
  const pdf = new jsPDF({ unit: 'pt', format: 'letter', compress: true });
  const pageW = pdf.internal.pageSize.getWidth();
  const pageH = pdf.internal.pageSize.getHeight();
  const contentW = pageW - MARGIN * 2;
  const h = doc.header;
  const s = doc.summary;
  let y = MARGIN;

  const ensure = (needed: number) => {
    if (y + needed > pageH - MARGIN - 20) {
      pdf.addPage();
      y = MARGIN;
    }
  };
  const lastY = () => (pdf as unknown as { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y;

  const sectionTitle = (title: string) => {
    ensure(48);
    y += 10;
    pdf.setFont('helvetica', 'bold').setFontSize(14).setTextColor(...NAVY);
    pdf.text(title, MARGIN, y);
    y += 6;
    pdf.setDrawColor(...GOLD).setLineWidth(1.2).line(MARGIN, y, MARGIN + contentW, y);
    y += 16;
  };
  const paragraph = (text: string, size = 10, color: [number, number, number] = [33, 37, 41], style = 'normal') => {
    pdf.setFont('helvetica', style).setFontSize(size).setTextColor(...color);
    const lines = pdf.splitTextToSize(text, contentW) as string[];
    for (const line of lines) {
      ensure(size + 4);
      pdf.text(line, MARGIN, y);
      y += size + 4;
    }
  };
  const table = (head: string[], body: (string | number)[][], columnStyles?: Record<number, object>) => {
    autoTable(pdf, {
      startY: y,
      head: [head],
      body: body.map((r) => r.map((c) => String(c))),
      margin: { left: MARGIN, right: MARGIN },
      styles: { fontSize: 9, cellPadding: 4, textColor: [33, 37, 41] },
      headStyles: { fillColor: NAVY, textColor: 255, fontStyle: 'bold' },
      alternateRowStyles: { fillColor: [246, 247, 250] },
      columnStyles,
    });
    y = lastY() + 14;
  };

  // ---- 1. Header / cover ---------------------------------------------------
  pdf.setFillColor(...NAVY).rect(0, 0, pageW, 132, 'F');
  pdf.setFont('helvetica', 'bold').setFontSize(22).setTextColor(255, 255, 255);
  pdf.text(h.organization_name, MARGIN, 56);
  pdf.setFont('helvetica', 'normal').setFontSize(13);
  pdf.text(h.area_name, MARGIN, 80);
  pdf.setTextColor(...GOLD).setFont('helvetica', 'bold').setFontSize(15);
  pdf.text(`Quarterly National Report — ${h.period_year} Q${h.period_quarter}`, MARGIN, 108);
  y = 160;
  const status = STAGE_STATUS_TEXT[opts.stage];
  const meta: [string, string][] = [
    ['Reporting period', `${formatDate(h.period_start)} – ${formatDate(h.period_end)}`],
    ['Report status', status],
    ['Generated', formatTimestamp(h.generated_at)],
    ['Approved', doc.approval ? formatTimestamp(doc.approval.approved_at) : '—'],
    ['Approved by', doc.approval?.approved_by_name ?? '—'],
  ];
  for (const [k, v] of meta) {
    pdf.setFont('helvetica', 'bold').setFontSize(10).setTextColor(...GREY).text(k, MARGIN, y);
    pdf.setFont('helvetica', 'normal').setTextColor(33, 37, 41).text(v, MARGIN + 120, y);
    y += 16;
  }

  // ---- 2. Summary ----------------------------------------------------------
  sectionTitle('Quarter Summary');
  const completionText =
    s.completion_known_activities === 0
      ? `${COMPLETION_NOT_RECORDED} (${s.completion_unavailable_activities} activities)`
      : `Known completions ${s.known_completions ?? 0}; completion data unavailable for ${s.completion_unavailable_activities} activities`;
  table(
    ['Measure', 'Value'],
    [
      ['Total active members (census)', s.total_active_members ?? 'Census snapshot missing'],
      ...s.branch_totals.map((b) => [`${b.branch_name} total`, b.active_member_count] as [string, number]),
      ['Reportable Events', s.reportable_events],
      ['Reportable Programs', s.reportable_programs],
      ['CLS conducted', s.cls_count],
      ['LCS conducted', s.lcs_count],
      ['Formal Formation sessions', s.formation_count],
      ['Registered CLS participants', s.cls_registered_participants],
      ['Registered LCS participants', s.lcs_registered_participants],
      ['Completion', completionText],
      ['Selected report photos', s.selected_photos],
      ['Speaker assignments', s.speaker_assignments],
      ['Service-team assignments', s.service_team_assignments],
    ],
    { 0: { cellWidth: 220, fontStyle: 'bold' } }
  );

  // ---- 3. Census -----------------------------------------------------------
  sectionTitle('Quarterly Census');
  const c = doc.census;
  if (!c.available) {
    paragraph('No census snapshot exists for this reporting period. This report cannot be approved.', 10, [176, 42, 42], 'bold');
  } else {
    paragraph(`Snapshot date ${formatDate(c.snapshot_date)} · census status ${humanize(c.census_period_status)}`, 9, GREY);
    y += 4;
    table(
      ['Branch / Sub-area', 'Section', 'Category', 'Active members'],
      [
        ...(c.sections ?? []).map((r) => [r.branch_name ?? '—', r.section_name, humanize(r.section_category), r.active_member_count]),
        ...(c.uncategorized_active_members ? [['—', 'Uncategorized', '—', c.uncategorized_active_members]] : []),
        ['', 'Total active members', '', c.total_active_members ?? 0],
      ],
      { 3: { halign: 'right' } }
    );
  }

  // ---- 4/5. Activities -----------------------------------------------------
  const activityBlock = (a: AnyReportActivity, kindLabel: string) => {
    ensure(70);
    pdf.setFont('helvetica', 'bold').setFontSize(11.5).setTextColor(...NAVY);
    const titleLines = pdf.splitTextToSize(activityTitle(a), contentW) as string[];
    for (const line of titleLines) {
      ensure(16);
      pdf.text(line, MARGIN, y);
      y += 15;
    }
    paragraph(
      [
        kindLabel,
        formatDateRange(a.activity_start_date, a.activity_end_date),
        a.location ?? 'Venue not recorded',
        hierarchyLabel(a),
        priorityLabel(a.report_priority),
      ].join('  ·  '),
      8.5,
      GREY
    );
    if (a.report_highlight && a.report_highlight.trim()) {
      paragraph(a.report_highlight.trim(), 10);
    } else {
      paragraph('No reporting highlight recorded.', 9, GREY, 'italic');
    }
    if ('source_kind' in a) {
      const f = a as ReportFormationItem;
      paragraph(
        `Participants: ${participantsLabel(f)}   ·   Attendance: ${f.attendance_count ?? 'Not recorded'}   ·   Completion: ${completionLabel(f)}`,
        9
      );
    } else if (a.participant_count !== null) {
      paragraph(`Registered participants: ${a.participant_count}`, 9);
    }
    if (a.speakers.length) {
      paragraph(
        'Speakers: ' +
          a.speakers
            .map((sp) => {
              const extra = [sp.topic_title, sp.is_member ? null : sp.external_organization].filter(Boolean).join(', ');
              return `${sp.name ?? 'Unnamed'} (${humanize(sp.speaker_role)}${extra ? `; ${extra}` : ''})`;
            })
            .join('; '),
        9
      );
    }
    if (a.service_team.length) {
      paragraph(
        'Service team: ' +
          a.service_team.map((m) => `${m.name ?? 'Unnamed'} (${m.role_label ?? humanize(m.role_code)})`).join('; '),
        9
      );
    }
    y += 8;
  };

  sectionTitle('Major Highlights');
  if (!doc.major_highlights.length) paragraph(NONE_REPORTED, 10, GREY, 'italic');
  doc.major_highlights.forEach((a) => activityBlock(a, humanize(a.activity_kind === 'program' ? a.activity_type : 'event')));

  sectionTitle('Other Ministry Activities');
  if (!doc.other_activities.length) paragraph(NONE_REPORTED, 10, GREY, 'italic');
  doc.other_activities.forEach((a) => activityBlock(a, humanize(a.activity_kind === 'program' ? a.activity_type : 'event')));

  // ---- 6. CLS / LCS / Formation -------------------------------------------
  sectionTitle('CLS / LCS / Formal Formation');
  for (const kind of ['cls', 'lcs', 'formation'] as const) {
    const items = doc.formation_items.filter((f) => f.source_kind === kind);
    ensure(30);
    pdf.setFont('helvetica', 'bold').setFontSize(11).setTextColor(...GOLD);
    pdf.text(SOURCE_KIND_LABEL[kind], MARGIN, y);
    y += 16;
    if (!items.length) paragraph(NONE_REPORTED, 9.5, GREY, 'italic');
    items.forEach((f) => activityBlock(f, SOURCE_KIND_LABEL[kind]));
  }

  // ---- 7. Photos -----------------------------------------------------------
  sectionTitle('Selected Photos');
  const all: AnyReportActivity[] = [...doc.major_highlights, ...doc.other_activities, ...doc.formation_items];
  const withPhotos = all.filter((a) => a.selected_photos.length);
  if (!withPhotos.length) paragraph(NONE_REPORTED, 10, GREY, 'italic');
  const gap = 10;
  const cellW = (contentW - gap * (PDF_PHOTOS_PER_ACTIVITY - 1)) / PDF_PHOTOS_PER_ACTIVITY;
  const cellH = cellW * 0.75;
  for (const a of withPhotos) {
    const photos = sortedPhotos(a.selected_photos);
    ensure(cellH + 60);
    pdf.setFont('helvetica', 'bold').setFontSize(10.5).setTextColor(...NAVY);
    pdf.text(pdf.splitTextToSize(activityTitle(a), contentW)[0] as string, MARGIN, y);
    y += 12;
    const shown = photos.slice(0, PDF_PHOTOS_PER_ACTIVITY);
    let maxCaption = 0;
    for (let i = 0; i < shown.length; i++) {
      const p = shown[i];
      const x = MARGIN + i * (cellW + gap);
      let img: LoadedImage | null = null;
      try {
        img = opts.loadImage ? await opts.loadImage(p) : null;
      } catch {
        img = null;
      }
      if (img) {
        const ratio = Math.min(cellW / img.width, cellH / img.height);
        const w = img.width * ratio;
        const hh = img.height * ratio;
        try {
          pdf.addImage(img.dataUrl, 'JPEG', x + (cellW - w) / 2, y + (cellH - hh) / 2, w, hh);
        } catch {
          img = null;
        }
      }
      if (!img) {
        warnings.push(`Photo could not be loaded: ${p.caption ?? p.photo_id}`);
        pdf.setDrawColor(200).setFillColor(243, 244, 246).rect(x, y, cellW, cellH, 'FD');
        pdf.setFont('helvetica', 'italic').setFontSize(8).setTextColor(...GREY);
        pdf.text('Photo unavailable', x + cellW / 2, y + cellH / 2, { align: 'center' });
      }
      pdf.setFont('helvetica', 'normal').setFontSize(8).setTextColor(33, 37, 41);
      const cap = pdf.splitTextToSize(p.caption ?? '', cellW).slice(0, 3) as string[];
      cap.forEach((line, li) => pdf.text(line, x, y + cellH + 11 + li * 10));
      maxCaption = Math.max(maxCaption, cap.length);
    }
    y += cellH + 14 + maxCaption * 10;
    if (photos.length > PDF_PHOTOS_PER_ACTIVITY) {
      paragraph(
        `${photos.length - PDF_PHOTOS_PER_ACTIVITY} additional selected photo(s) are listed in the Excel workbook.`,
        8,
        GREY,
        'italic'
      );
    }
    y += 6;
  }

  // ---- Footer on every page ------------------------------------------------
  const pages = pdf.getNumberOfPages();
  for (let i = 1; i <= pages; i++) {
    pdf.setPage(i);
    pdf.setFont('helvetica', 'normal').setFontSize(8).setTextColor(...GREY);
    pdf.text(
      `MFC New York · Quarterly National Report ${h.period_year} Q${h.period_quarter}${STAGE_WATERMARK[opts.stage]}`,
      MARGIN,
      pageH - 24
    );
    pdf.text(`Page ${i} of ${pages}`, pageW - MARGIN, pageH - 24, { align: 'right' });
  }

  return { bytes: pdf.output('arraybuffer'), warnings };
}

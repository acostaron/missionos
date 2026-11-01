import type { QuarterlyReportDocument, ReportPhoto } from '../types';
import { recordQuarterlyReportExport, signPhotoUrl } from '../api';
import { reportFilename } from '../format';
import type { ExportStage } from '../format';
import type { LoadedImage } from './pdf';

const MAX_PX = 1200;

/** Browser image loader: signs a short-lived URL, downsizes to JPEG via canvas. Nothing is persisted. */
async function loadPhotoForPdf(photo: ReportPhoto): Promise<LoadedImage | null> {
  const url = await signPhotoUrl(photo.storage_bucket, photo.storage_path);
  if (!url) return null;
  const res = await fetch(url);
  if (!res.ok) return null;
  const bitmap = await createImageBitmap(await res.blob());
  const scale = Math.min(1, MAX_PX / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  return { dataUrl: canvas.toDataURL('image/jpeg', 0.82), width: canvas.width, height: canvas.height };
}

function download(bytes: ArrayBuffer, filename: string, mime: string) {
  const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export interface ExportOutcome {
  filename: string;
  warnings: string[];
}

export async function exportQuarterlyReport(
  periodId: string,
  doc: QuarterlyReportDocument,
  format: 'pdf' | 'xlsx',
  stage: ExportStage
): Promise<ExportOutcome> {
  const filename = reportFilename(doc.header.period_year, doc.header.period_quarter, format, stage);
  let warnings: string[] = [];
  if (format === 'pdf') {
    const { buildQuarterlyReportPdf } = await import('./pdf');
    const result = await buildQuarterlyReportPdf(doc, { stage, loadImage: loadPhotoForPdf });
    warnings = result.warnings;
    download(result.bytes, filename, 'application/pdf');
  } else {
    const { buildQuarterlyReportWorkbook } = await import('./excel');
    const bytes = await buildQuarterlyReportWorkbook(doc, { stage });
    download(bytes, filename, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }
  try {
    await recordQuarterlyReportExport(periodId, format);
  } catch {
    warnings.push('Export downloaded, but the audit entry could not be recorded.');
  }
  return { filename, warnings };
}

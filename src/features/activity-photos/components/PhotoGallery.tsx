import { useEffect, useRef, useState } from 'react';
import { Camera, ImageOff, Star, Upload } from 'lucide-react';
import { Alert, Badge, Button, Card, FormField, Input, Modal, Select, Skeleton, Textarea } from '../../../components/ui';
import { getEventErrorMessage } from '../../events/error-message';
import {
  useActivityPhotos,
  useDeleteActivityPhoto,
  usePhotoUrl,
  useUpdateActivityPhoto,
  useUploadActivityPhoto,
} from '../queries';
import { PHOTO_CAPTION_MAX, type ActivityPhoto, type PhotoTarget } from '../types';

export interface PhotoSessionOption {
  eventId: string;
  label: string;
}

interface PhotoGalleryProps {
  organizationId: string;
  target: PhotoTarget;
  /** Program mode: allow uploading to a specific session event. */
  sessionOptions?: PhotoSessionOption[];
  locked?: boolean;
}

const CAPTION_HELP = 'Describe what is happening in this photo so it can be understood in the quarterly report.';

function PhotoThumb({ photo, onClick, showSession }: { photo: ActivityPhoto; onClick: () => void; showSession: boolean }) {
  const { data: url, isError } = usePhotoUrl(photo.storage_path);
  return (
    <button
      type="button"
      onClick={onClick}
      className="group relative aspect-square overflow-hidden rounded-control border border-line bg-surface-muted text-left focus:outline-none focus:ring-2 focus:ring-primary"
    >
      {url ? (
        <img
          src={url}
          alt={photo.alt_text || photo.caption || 'Ministry photo'}
          loading="lazy"
          className="h-full w-full object-cover transition-transform duration-200 group-hover:scale-105"
        />
      ) : isError ? (
        <div className="flex h-full items-center justify-center text-ink-muted"><ImageOff className="h-6 w-6" /></div>
      ) : (
        <Skeleton className="h-full w-full" />
      )}
      <div className="absolute left-1.5 top-1.5 flex flex-wrap gap-1">
        {showSession && photo.session_number != null && <Badge variant="neutral">Session {photo.session_number}</Badge>}
        {photo.include_in_quarterly_report && (
          <Badge variant="warning"><Star className="mr-0.5 inline h-3 w-3" />Report</Badge>
        )}
      </div>
      {photo.caption && (
        <p className="absolute inset-x-0 bottom-0 line-clamp-2 bg-gradient-to-t from-black/70 to-transparent p-2 pt-6 text-caption text-white">
          {photo.caption}
        </p>
      )}
    </button>
  );
}

function UploadModal({
  open, onClose, organizationId, target, sessionOptions,
}: { open: boolean; onClose: () => void; organizationId: string; target: PhotoTarget; sessionOptions?: PhotoSessionOption[] }) {
  const [file, setFile] = useState<File | null>(null);
  const [caption, setCaption] = useState('');
  const [altText, setAltText] = useState('');
  const [include, setInclude] = useState(false);
  const [session, setSession] = useState('');
  const [error, setError] = useState<string | null>(null);
  const upload = useUploadActivityPhoto();
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) { setFile(null); setCaption(''); setAltText(''); setInclude(false); setSession(''); setError(null); }
  }, [open]);

  const handleSave = async () => {
    setError(null);
    if (!file) { setError('Choose a photo.'); return; }
    const t: PhotoTarget = target.programRunId && session ? { eventId: session } : target;
    try {
      await upload.mutateAsync({ organizationId, target: t, file, caption, altText, includeInQuarterlyReport: include });
      onClose();
    } catch (err) {
      setError(err instanceof Error && !('code' in err) ? err.message : getEventErrorMessage(err));
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Upload photo"
      size="md"
      footer={
        <div className="flex w-full justify-end gap-2">
          <Button variant="outline" onClick={onClose} disabled={upload.isPending}>Cancel</Button>
          <Button variant="primary" onClick={handleSave} loading={upload.isPending}>Upload</Button>
        </div>
      }
    >
      <div className="space-y-4">
        {error && <Alert variant="danger">{error}</Alert>}
        <div>
          <input
            ref={inputRef}
            id="activity-photo-file"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="hidden"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          />
          <Button variant="outline" icon={<Upload className="h-4 w-4" />} onClick={() => inputRef.current?.click()}>
            {file ? 'Choose a different photo' : 'Choose photo'}
          </Button>
          <p className="mt-1 text-caption text-ink-muted">
            {file ? file.name : 'JPG, PNG or WebP, up to 10 MB. Large photos are resized automatically.'}
          </p>
        </div>
        {sessionOptions && sessionOptions.length > 0 && (
          <FormField label="Session">
            <Select value={session} onChange={(e) => setSession(e.target.value)}>
              <option value="">Whole program</option>
              {sessionOptions.map((s) => <option key={s.eventId} value={s.eventId}>{s.label}</option>)}
            </Select>
          </FormField>
        )}
        <FormField label="Photo Caption">
          <Textarea value={caption} onChange={(e) => setCaption(e.target.value)} rows={3} maxLength={PHOTO_CAPTION_MAX} placeholder={CAPTION_HELP} />
        </FormField>
        <p className="-mt-2 text-caption text-ink-muted">{CAPTION_HELP} ({caption.length}/{PHOTO_CAPTION_MAX})</p>
        <FormField label="Alt Text (optional, for accessibility)">
          <Input value={altText} onChange={(e) => setAltText(e.target.value)} maxLength={300} />
        </FormField>
        <label className="flex items-center gap-2 text-small text-ink">
          <input type="checkbox" checked={include} onChange={(e) => setInclude(e.target.checked)} />
          Include in Quarterly Report
        </label>
      </div>
    </Modal>
  );
}

function PreviewModal({
  photo, onClose, organizationId, canManage,
}: { photo: ActivityPhoto | null; onClose: () => void; organizationId: string; canManage: boolean }) {
  const { data: url } = usePhotoUrl(photo?.storage_path ?? null);
  const [caption, setCaption] = useState('');
  const [altText, setAltText] = useState('');
  const [include, setInclude] = useState(false);
  const [reportOrder, setReportOrder] = useState('0');
  const [error, setError] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const update = useUpdateActivityPhoto();
  const del = useDeleteActivityPhoto();

  useEffect(() => {
    if (!photo) return;
    setCaption(photo.caption ?? '');
    setAltText(photo.alt_text ?? '');
    setInclude(!!photo.include_in_quarterly_report);
    setReportOrder(String(photo.report_sort_order ?? 0));
    setError(null);
    setConfirmDelete(false);
  }, [photo]);

  if (!photo) return null;

  const handleSave = async () => {
    setError(null);
    try {
      await update.mutateAsync({
        organizationId, photoId: photo.id, caption, altText,
        includeInQuarterlyReport: include, reportSortOrder: Math.max(0, parseInt(reportOrder, 10) || 0),
      });
      onClose();
    } catch (err) { setError(getEventErrorMessage(err)); }
  };
  const handleDelete = async () => {
    setError(null);
    try { await del.mutateAsync({ organizationId, photoId: photo.id }); onClose(); }
    catch (err) { setError(err instanceof Error && !('code' in err) ? err.message : getEventErrorMessage(err)); }
  };

  return (
    <Modal
      open={!!photo}
      onClose={onClose}
      title={photo.session_number != null ? `Photo · Session ${photo.session_number}` : 'Photo'}
      size="lg"
      footer={canManage ? (
        <div className="flex w-full items-center justify-between gap-2">
          {confirmDelete ? (
            <div className="flex items-center gap-2">
              <span className="text-small text-danger-700">Delete this photo?</span>
              <Button size="sm" variant="primary" className="bg-danger-600 hover:bg-danger-700" loading={del.isPending} onClick={handleDelete}>Delete</Button>
              <Button size="sm" variant="outline" onClick={() => setConfirmDelete(false)}>Keep</Button>
            </div>
          ) : (
            <Button variant="ghost" className="text-danger-600 hover:text-danger-700" onClick={() => setConfirmDelete(true)}>Delete photo</Button>
          )}
          <div className="flex gap-2">
            <Button variant="outline" onClick={onClose}>Close</Button>
            <Button variant="primary" loading={update.isPending} onClick={handleSave}>Save</Button>
          </div>
        </div>
      ) : (
        <div className="flex w-full justify-end"><Button variant="outline" onClick={onClose}>Close</Button></div>
      )}
    >
      <div className="space-y-4">
        {error && <Alert variant="danger">{error}</Alert>}
        <div className="flex max-h-[60vh] items-center justify-center overflow-hidden rounded-control bg-black/90">
          {url ? (
            <img src={url} alt={photo.alt_text || photo.caption || 'Ministry photo'} className="max-h-[60vh] w-auto object-contain" />
          ) : (
            <Skeleton className="h-64 w-full" />
          )}
        </div>
        {canManage ? (
          <>
            <FormField label="Photo Caption">
              <Textarea value={caption} onChange={(e) => setCaption(e.target.value)} rows={3} maxLength={PHOTO_CAPTION_MAX} />
            </FormField>
            <p className="-mt-2 text-caption text-ink-muted">{CAPTION_HELP} ({caption.length}/{PHOTO_CAPTION_MAX})</p>
            <FormField label="Alt Text (optional)">
              <Input value={altText} onChange={(e) => setAltText(e.target.value)} maxLength={300} />
            </FormField>
            <div className="flex flex-wrap items-end gap-4">
              <label className="flex items-center gap-2 text-small text-ink">
                <input type="checkbox" checked={include} onChange={(e) => setInclude(e.target.checked)} />
                Include in Quarterly Report
              </label>
              {include && (
                <FormField label="Report order">
                  <Input type="number" min={0} max={10000} value={reportOrder} onChange={(e) => setReportOrder(e.target.value)} className="w-24" />
                </FormField>
              )}
            </div>
            {photo.uploaded_at && (
              <p className="text-caption text-ink-muted">
                Uploaded {new Date(photo.uploaded_at).toLocaleString()}{photo.uploaded_by_name ? ` by ${photo.uploaded_by_name}` : ''}
              </p>
            )}
          </>
        ) : (
          photo.caption && <p className="whitespace-pre-line text-body text-ink">{photo.caption}</p>
        )}
      </div>
    </Modal>
  );
}

export function PhotoGallery({ organizationId, target, sessionOptions, locked }: PhotoGalleryProps) {
  const { data, isLoading, error } = useActivityPhotos(organizationId, target);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  if (isLoading) return <Skeleton className="h-40" />;
  if (error || !data) return null;

  const canManage = data.can_manage;
  const selected = data.photos.find((p) => p.id === selectedId) ?? null;
  const isProgram = !!target.programRunId;

  return (
    <Card padding="comfortable" className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Camera className="h-4 w-4 text-ink-muted" />
          <h2 className="text-h3 font-semibold text-ink">Photos</h2>
          {canManage && data.total_count > 0 && (
            <span className="text-caption text-ink-muted">
              {data.total_count} photo{data.total_count === 1 ? '' : 's'} · {data.selected_count ?? 0} selected for report
            </span>
          )}
        </div>
        {canManage && !locked && (
          <Button id="upload-activity-photo" variant="outline" size="sm" icon={<Upload className="h-3.5 w-3.5" />} onClick={() => setUploadOpen(true)}>
            Upload Photo
          </Button>
        )}
      </div>

      {data.photos.length === 0 ? (
        <p className="py-4 text-center text-small text-ink-muted">No photos yet.</p>
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          {data.photos.map((p) => (
            <PhotoThumb key={p.id} photo={p} showSession={isProgram} onClick={() => setSelectedId(p.id)} />
          ))}
        </div>
      )}

      {canManage && !locked && (
        <UploadModal open={uploadOpen} onClose={() => setUploadOpen(false)} organizationId={organizationId} target={target} sessionOptions={sessionOptions} />
      )}
      <PreviewModal photo={selected} onClose={() => setSelectedId(null)} organizationId={organizationId} canManage={canManage && !locked} />
    </Card>
  );
}

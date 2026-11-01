import { useEffect, useState } from 'react';
import { Card } from '../../../components/ui';
import type { AnyReportActivity, ReportPhoto } from '../types';
import { activityTitle } from '../types';
import { NONE_REPORTED, PDF_PHOTOS_PER_ACTIVITY, sortedPhotos } from '../format';
import { signPhotoUrl } from '../api';

function Thumb({ photo }: { photo: ReportPhoto }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let alive = true;
    signPhotoUrl(photo.storage_bucket, photo.storage_path).then((u) => {
      if (!alive) return;
      if (u) setUrl(u);
      else setFailed(true);
    });
    return () => {
      alive = false;
    };
  }, [photo.storage_bucket, photo.storage_path]);
  return (
    <figure className="w-40">
      <div className="flex h-28 w-40 items-center justify-center overflow-hidden rounded-md bg-slate-100">
        {url && !failed ? (
          <img src={url} alt={photo.alt_text ?? photo.caption ?? ''} className="h-full w-full object-cover" onError={() => setFailed(true)} />
        ) : (
          <span className="text-xs text-slate-400">{failed ? 'Unavailable' : 'Loading…'}</span>
        )}
      </div>
      <figcaption className="mt-1 line-clamp-2 text-xs text-slate-600">{photo.caption ?? 'No caption'}</figcaption>
    </figure>
  );
}

export function PhotoSection({ activities }: { activities: AnyReportActivity[] }) {
  const withPhotos = activities.filter((a) => a.selected_photos.length > 0);
  return (
    <Card>
      <h2 className="mb-1 text-base font-semibold text-slate-900">Selected Photos</h2>
      <p className="mb-3 text-xs text-slate-500">
        The PDF shows the first {PDF_PHOTOS_PER_ACTIVITY} photos per activity by report order; all selected photos are kept in the
        report record and Excel workbook.
      </p>
      {!withPhotos.length && <p className="text-sm italic text-slate-400">{NONE_REPORTED}</p>}
      <div className="space-y-4">
        {withPhotos.map((a) => {
          const photos = sortedPhotos(a.selected_photos);
          return (
            <div key={a.source_id}>
              <h3 className="mb-2 text-sm font-medium text-slate-800">
                {activityTitle(a)} <span className="text-xs text-slate-400">({photos.length})</span>
              </h3>
              <div className="flex flex-wrap gap-3">
                {photos.map((p, i) => (
                  <div key={p.photo_id} className={i >= PDF_PHOTOS_PER_ACTIVITY ? 'opacity-60' : undefined}>
                    <Thumb photo={p} />
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </Card>
  );
}

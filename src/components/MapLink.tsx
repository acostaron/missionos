// Location with a pin that opens Google Maps (Pass 9.28, Ron 2026-10-21).
import { MapPin } from 'lucide-react';
import { mapsUrl } from '../lib/maps';

/** Location text with a pin; tapping it opens Google Maps when the text is an address. */
export function MapLink({ location, label, className = '' }: { location: string | null | undefined; label?: string; className?: string }) {
  const text = (location ?? '').trim();
  if (!text) return null;
  const url = mapsUrl(text);
  const shown = label ?? text;
  return (
    <span className={`inline-flex items-center gap-1 ${className}`}>
      <MapPin className="h-3.5 w-3.5 shrink-0 text-ink-muted" />
      {url ? (
        <a href={url} target="_blank" rel="noopener noreferrer" className="text-primary underline-offset-2 hover:underline">
          {shown}
        </a>
      ) : (
        <span>{shown}</span>
      )}
    </span>
  );
}

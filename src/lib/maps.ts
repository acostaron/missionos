// Google Maps link for a venue / meeting address (Pass 9.28, Ron 2026-10-21).
// Free-text locations are searched on Google Maps; web links (e.g. video-call links) are not turned into map links.
export function mapsUrl(location: string | null | undefined): string | null {
  const text = (location ?? '').trim();
  if (!text || /^https?:\/\//i.test(text) || /\b(zoom|google meet|teams)\b/i.test(text)) return null;
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(text)}`;
}

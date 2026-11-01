// Pass 9.50: Event + Program photos.

export const PHOTO_BUCKET = 'activity-photos';
export const PHOTO_MAX_BYTES = 10 * 1024 * 1024;
export const PHOTO_ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export const PHOTO_CAPTION_MAX = 500;

export interface ActivityPhoto {
  id: string;
  event_id: string | null;
  program_run_id: string | null;
  session_number: number | null;
  event_title: string | null;
  storage_path: string;
  mime_type: string;
  caption: string | null;
  alt_text: string | null;
  sort_order: number;
  // Manager-only (null for viewers)
  include_in_quarterly_report: boolean | null;
  report_sort_order: number | null;
  original_filename: string | null;
  file_size_bytes: number | null;
  uploaded_at: string | null;
  uploaded_by_name: string | null;
}

export interface ActivityPhotosResponse {
  can_manage: boolean;
  photos: ActivityPhoto[];
  total_count: number;
  selected_count: number | null;
}

export interface PhotoTarget {
  eventId?: string | null;
  programRunId?: string | null;
}

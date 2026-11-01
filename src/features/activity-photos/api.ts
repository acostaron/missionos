import { supabase } from '../../lib/supabase/client';
import {
  PHOTO_ALLOWED_TYPES,
  PHOTO_BUCKET,
  PHOTO_MAX_BYTES,
  type ActivityPhotosResponse,
  type PhotoTarget,
} from './types';

const MAX_DIMENSION = 2400;

export async function getActivityPhotos(organizationId: string, target: PhotoTarget): Promise<ActivityPhotosResponse> {
  const { data, error } = await supabase.rpc('get_activity_photos', {
    p_organization_id: organizationId,
    p_event_id: target.eventId ?? undefined,
    p_program_run_id: target.programRunId ?? undefined,
  });
  if (error) throw error;
  return data as unknown as ActivityPhotosResponse;
}

/** Validate type/size; downscale very large images to JPEG to keep uploads reasonable. */
export async function preparePhoto(file: File): Promise<{ blob: Blob; mime: string }> {
  const type = file.type.toLowerCase();
  if (!(PHOTO_ALLOWED_TYPES as readonly string[]).includes(type)) {
    throw new Error('Please choose a JPG, PNG, or WebP photo.');
  }
  if (file.size > 25 * 1024 * 1024) {
    throw new Error('Photo is too large. Please choose one under 25 MB.');
  }

  const bitmap = await createImageBitmap(file).catch(() => null);
  if (!bitmap) throw new Error('Could not read this image. Please verify the file is not corrupted.');
  const { width, height } = bitmap;
  const needsResize = Math.max(width, height) > MAX_DIMENSION || file.size > PHOTO_MAX_BYTES;
  if (!needsResize) {
    bitmap.close();
    return { blob: file, mime: type };
  }
  const scale = Math.min(1, MAX_DIMENSION / Math.max(width, height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Could not process this image.');
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.86));
  if (!blob) throw new Error('Could not process this image.');
  if (blob.size > PHOTO_MAX_BYTES) throw new Error('Photo must be 10 MB or smaller.');
  return { blob, mime: 'image/jpeg' };
}

export interface UploadPhotoParams {
  organizationId: string;
  target: PhotoTarget;
  file: File;
  caption?: string;
  altText?: string;
  includeInQuarterlyReport?: boolean;
}

/** request permission -> upload object -> finalize metadata (with orphan cleanup). */
export async function uploadActivityPhoto(params: UploadPhotoParams) {
  const { blob, mime } = await preparePhoto(params.file);

  const { data: req, error: reqError } = await supabase.rpc('create_activity_photo_upload', {
    p_organization_id: params.organizationId,
    p_event_id: params.target.eventId ?? undefined,
    p_program_run_id: params.target.programRunId ?? undefined,
    p_mime_type: mime,
    p_file_size_bytes: blob.size,
  });
  if (reqError) throw reqError;
  const path = (req as unknown as { storage_path: string }).storage_path;

  const { error: upError } = await supabase.storage
    .from(PHOTO_BUCKET)
    .upload(path, blob, { contentType: mime, upsert: false });
  if (upError) throw new Error(upError.message || 'Failed to upload photo.');

  const { data, error } = await supabase.rpc('finalize_activity_photo', {
    p_organization_id: params.organizationId,
    p_storage_path: path,
    p_original_filename: params.file.name,
    p_caption: params.caption || undefined,
    p_alt_text: params.altText || undefined,
    p_include_in_quarterly_report: params.includeInQuarterlyReport ?? false,
  });
  if (error) {
    await supabase.storage.from(PHOTO_BUCKET).remove([path]).catch(() => undefined);
    throw error;
  }
  return data;
}

export interface UpdatePhotoParams {
  organizationId: string;
  photoId: string;
  caption?: string | null;
  altText?: string | null;
  includeInQuarterlyReport?: boolean | null;
  reportSortOrder?: number | null;
  sortOrder?: number | null;
}

export async function updateActivityPhoto(p: UpdatePhotoParams) {
  const { data, error } = await supabase.rpc('update_activity_photo', {
    p_organization_id: p.organizationId,
    p_photo_id: p.photoId,
    p_caption: p.caption ?? undefined,
    p_alt_text: p.altText ?? undefined,
    p_include_in_quarterly_report: p.includeInQuarterlyReport ?? undefined,
    p_report_sort_order: p.reportSortOrder ?? undefined,
    p_sort_order: p.sortOrder ?? undefined,
  });
  if (error) throw error;
  return data;
}

/** Remove the record first, then the object. Surfaces object-removal failures. */
export async function deleteActivityPhoto(organizationId: string, photoId: string) {
  const { data, error } = await supabase.rpc('delete_activity_photo', {
    p_organization_id: organizationId,
    p_photo_id: photoId,
  });
  if (error) throw error;
  const path = (data as unknown as { storage_path: string }).storage_path;
  const { error: rmError } = await supabase.storage.from(PHOTO_BUCKET).remove([path]);
  if (rmError) {
    throw new Error('The photo was removed from the page, but its file could not be deleted from storage. Please tell an administrator.');
  }
}

export async function getPhotoSignedUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage.from(PHOTO_BUCKET).createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

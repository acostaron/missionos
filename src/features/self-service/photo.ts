import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export const MAX_PHOTO_FILE_SIZE = 15 * 1024 * 1024; // 15 MB
export const MAX_PHOTO_DIMENSION = 800; // max width or height in px

/**
 * Resizes an image file to max 800px on the longest side and exports as JPEG quality 0.85.
 */
export async function resizeImageToJpeg(file: File): Promise<Blob> {
  if (file.size > MAX_PHOTO_FILE_SIZE) {
    throw new Error('File size exceeds 15 MB. Please choose a smaller photo.');
  }

  const name = file.name.toLowerCase();
  const type = file.type.toLowerCase();

  if (type === 'image/heic' || type === 'image/heif' || name.endsWith('.heic') || name.endsWith('.heif')) {
    throw new Error('Please choose a JPG or PNG photo.');
  }

  if (!['image/jpeg', 'image/jpg', 'image/png', 'image/webp'].includes(type) && !name.match(/\.(jpe?g|png|webp)$/)) {
    throw new Error('Please choose a JPG, PNG, or WebP photo.');
  }

  return new Promise((resolve, reject) => {
    const objectUrl = URL.createObjectURL(file);
    const img = new Image();

    img.onload = () => {
      URL.revokeObjectURL(objectUrl);

      let { width, height } = img;
      if (width > MAX_PHOTO_DIMENSION || height > MAX_PHOTO_DIMENSION) {
        if (width > height) {
          height = Math.round((height * MAX_PHOTO_DIMENSION) / width);
          width = MAX_PHOTO_DIMENSION;
        } else {
          width = Math.round((width * MAX_PHOTO_DIMENSION) / height);
          height = MAX_PHOTO_DIMENSION;
        }
      }

      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;

      const ctx = canvas.getContext('2d');
      if (!ctx) {
        reject(new Error('Could not initialize canvas image processing.'));
        return;
      }

      ctx.drawImage(img, 0, 0, width, height);

      canvas.toBlob(
        (blob) => {
          if (!blob) {
            reject(new Error('Could not convert canvas to JPEG.'));
            return;
          }
          resolve(blob);
        },
        'image/jpeg',
        0.85
      );
    };

    img.onerror = () => {
      URL.revokeObjectURL(objectUrl);
      reject(new Error('Could not load image file. Please verify the file is not corrupted.'));
    };

    img.src = objectUrl;
  });
}

/**
 * Uploads a resized photo to Supabase storage and attaches it to the member record via RPC.
 */
export async function uploadMemberPhoto({
  organizationId,
  memberId,
  effectiveMemberId,
  file,
}: {
  organizationId: string;
  memberId: string | null; // null = myself for RPC
  effectiveMemberId: string; // actual member UUID for path
  file: File;
}): Promise<string> {
  const blob = await resizeImageToJpeg(file);
  const randomId = crypto.randomUUID();
  const storagePath = `${organizationId}/${effectiveMemberId}/${randomId}.jpg`;

  const { error: uploadError } = await supabase.storage
    .from('member-photos')
    .upload(storagePath, blob, {
      contentType: 'image/jpeg',
      upsert: false,
    });

  if (uploadError) {
    throw new Error(uploadError.message || 'Failed to upload photo to storage.');
  }

  const { data, error: rpcError } = await supabase.rpc('set_member_photo', {
    p_organization_id: organizationId,
    p_member_id: memberId ?? undefined,
    p_storage_path: storagePath,
  });

  if (rpcError) {
    // Best-effort cleanup of newly uploaded object
    await supabase.storage
      .from('member-photos')
      .remove([storagePath])
      .catch(() => undefined);
    throw new Error(rpcError.message || 'Failed to attach photo to profile.');
  }

  const result = data as {
    status: string;
    member_id: string;
    photo_path: string | null;
    previous_photo_path: string | null;
  };

  // Best-effort removal of old photo if one existed
  if (result.previous_photo_path && result.previous_photo_path !== storagePath) {
    await supabase.storage
      .from('member-photos')
      .remove([result.previous_photo_path])
      .catch(() => undefined);
  }

  return storagePath;
}

/**
 * Removes a member photo via RPC and deletes the storage object.
 */
export async function removeMemberPhoto({
  organizationId,
  memberId,
  currentPath,
}: {
  organizationId: string;
  memberId: string | null;
  currentPath: string | null;
}): Promise<void> {
  const { data, error: rpcError } = await supabase.rpc('set_member_photo', {
    p_organization_id: organizationId,
    p_member_id: memberId ?? undefined,
    p_storage_path: undefined,
  });

  if (rpcError) {
    throw new Error(rpcError.message || 'Failed to remove member photo.');
  }

  const result = data as {
    previous_photo_path?: string | null;
  };

  const pathToRemove = result.previous_photo_path || currentPath;
  if (pathToRemove) {
    await supabase.storage
      .from('member-photos')
      .remove([pathToRemove])
      .catch(() => undefined);
  }
}

/**
 * Hook to retrieve a 1-hour signed URL for a member photo, cached for 50 minutes.
 */
export function useMemberPhotoUrl(path: string | null | undefined) {
  return useQuery<string | null>({
    queryKey: ['member-photo-url', path],
    queryFn: async () => {
      if (!path) return null;
      const { data, error } = await supabase.storage
        .from('member-photos')
        .createSignedUrl(path, 3600);
      if (error) throw error;
      return data.signedUrl;
    },
    enabled: !!path,
    staleTime: 50 * 60 * 1000,
  });
}

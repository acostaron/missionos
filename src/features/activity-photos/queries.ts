import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  deleteActivityPhoto,
  getActivityPhotos,
  getPhotoSignedUrl,
  updateActivityPhoto,
  uploadActivityPhoto,
  type UpdatePhotoParams,
  type UploadPhotoParams,
} from './api';
import type { PhotoTarget } from './types';

export const activityPhotoKeys = {
  all: ['activity-photos'] as const,
  list: (orgId: string, t: PhotoTarget) =>
    [...activityPhotoKeys.all, 'list', orgId, t.eventId ?? null, t.programRunId ?? null] as const,
  url: (path: string) => [...activityPhotoKeys.all, 'url', path] as const,
};

export function useActivityPhotos(organizationId: string | null, target: PhotoTarget) {
  const has = !!(target.eventId || target.programRunId);
  return useQuery({
    queryKey: organizationId && has ? activityPhotoKeys.list(organizationId, target) : ['activity-photos', 'empty'],
    queryFn: () => getActivityPhotos(organizationId!, target),
    enabled: !!organizationId && has,
  });
}

export function usePhotoUrl(path: string | null) {
  return useQuery({
    queryKey: path ? activityPhotoKeys.url(path) : ['activity-photos', 'url', 'empty'],
    queryFn: () => getPhotoSignedUrl(path!),
    enabled: !!path,
    staleTime: 50 * 60 * 1000,
  });
}

function useInvalidate() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries({ queryKey: [...activityPhotoKeys.all, 'list'] });
}

export function useUploadActivityPhoto() {
  const invalidate = useInvalidate();
  return useMutation({ mutationFn: (p: UploadPhotoParams) => uploadActivityPhoto(p), onSuccess: invalidate });
}

export function useUpdateActivityPhoto() {
  const invalidate = useInvalidate();
  return useMutation({ mutationFn: (p: UpdatePhotoParams) => updateActivityPhoto(p), onSuccess: invalidate });
}

export function useDeleteActivityPhoto() {
  const invalidate = useInvalidate();
  return useMutation({
    mutationFn: (p: { organizationId: string; photoId: string }) => deleteActivityPhoto(p.organizationId, p.photoId),
    onSettled: invalidate,
  });
}

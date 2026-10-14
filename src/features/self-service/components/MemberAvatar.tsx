import { useState } from 'react';
import { useMemberPhotoUrl } from '../photo';

export type AvatarSize = 'sm' | 'md' | 'lg' | 'xl';

export interface MemberAvatarProps {
  path?: string | null;
  name: string;
  size?: AvatarSize;
  className?: string;
}

const SIZE_CLASSES: Record<AvatarSize, { container: string; text: string }> = {
  sm: { container: 'h-8 w-8', text: 'text-xs' },
  md: { container: 'h-12 w-12', text: 'text-sm' },
  lg: { container: 'h-20 w-20', text: 'text-xl' },
  xl: { container: 'h-28 w-28', text: 'text-2xl' },
};

export function MemberAvatar({
  path,
  name,
  size = 'md',
  className = '',
}: MemberAvatarProps) {
  const { data: photoUrl, isLoading } = useMemberPhotoUrl(path);
  const [imgError, setImgError] = useState(false);

  const initials = name
    .trim()
    .split(/\s+/)
    .map((w) => w[0])
    .filter(Boolean)
    .slice(0, 2)
    .join('')
    .toUpperCase() || '?';

  const sizeStyle = SIZE_CLASSES[size];

  if (photoUrl && !imgError && !isLoading) {
    return (
      <div
        className={`relative inline-block overflow-hidden rounded-full border border-line bg-surface-muted shrink-0 ${sizeStyle.container} ${className}`}
      >
        <img
          src={photoUrl}
          alt={name}
          onError={() => setImgError(true)}
          className="h-full w-full object-cover"
        />
      </div>
    );
  }

  return (
    <div
      className={`inline-flex shrink-0 items-center justify-center rounded-full bg-navy-50 font-semibold text-primary border border-navy-100 ${sizeStyle.container} ${sizeStyle.text} ${className}`}
      aria-label={name}
    >
      {initials}
    </div>
  );
}

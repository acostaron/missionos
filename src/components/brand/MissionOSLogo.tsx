// Official MissionOS logo (Ron, 2026-10-16): the Good Shepherd with the lamb, the path to the Cross, a family walking it.
// Round badge with transparent corners; 128px and 256px files for sharp display on phones (Claude, Pass 9.16).
export function MissionOSLogo({ size = 36, className = '' }: { size?: number; className?: string }) {
  const src = size > 64 ? '/brand/missionos-logo-256.png' : '/brand/missionos-logo-128.png';
  return (
    <img
      src={src}
      width={size}
      height={size}
      alt="MissionOS logo"
      className={`shrink-0 select-none rounded-full ${className}`}
      draggable={false}
    />
  );
}

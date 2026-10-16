import { Link } from 'react-router-dom';

/** Compact Home metric tile (Pass 9.19): short label on phones, full label on wider screens; optional link. */
export default function HomeStat({
  label,
  shortLabel,
  value,
  to,
}: {
  label: string;
  shortLabel: string;
  value: number;
  to?: string;
}) {
  const body = (
    <>
      <p className="text-xl font-semibold tabular-nums text-ink sm:text-2xl">{value}</p>
      <p className="text-[11px] leading-tight text-ink-secondary sm:text-small">
        <span className="sm:hidden">{shortLabel}</span>
        <span className="hidden sm:inline">{label}</span>
      </p>
    </>
  );
  const cls = 'block rounded-card border border-line bg-surface p-2 text-center sm:p-4 sm:text-left';
  return to ? (
    <Link
      to={to}
      aria-label={`${label}: ${value}`}
      className={`${cls} hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus`}
    >
      {body}
    </Link>
  ) : (
    <div className={cls} aria-label={`${label}: ${value}`}>
      {body}
    </div>
  );
}

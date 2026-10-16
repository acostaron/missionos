type Props = {
  name: string;
  organizationName?: string | null;
  /** Translated responsibility labels (never raw codes). */
  responsibilities?: string[];
};

// Pass 9.19 (Ron, 2026-10-16): compact header so Home fits one phone screen; the organization name
// ("Missionary Families of Christ — New York") is shown once, without the extra "Missionary Families of Christ" line.
export default function HomeWelcomeHeader({ name, organizationName, responsibilities = [] }: Props) {
  return (
    <header className="space-y-0.5">
      <h1 className="text-xl font-semibold tracking-tight text-ink sm:text-page-title">Welcome, {name}</h1>
      {organizationName && <p className="text-small text-ink-secondary sm:text-body">{organizationName}</p>}
      {responsibilities.length > 0 && (
        <p className="flex flex-wrap items-center gap-x-2 text-xs font-medium text-primary-blue sm:text-small">
          {responsibilities.map((r, i) => (
            <span key={i} className="inline-flex items-center">
              {i > 0 && (
                <span className="mr-2 text-ink-muted" aria-hidden="true">
                  ·
                </span>
              )}
              {r}
            </span>
          ))}
        </p>
      )}
    </header>
  );
}

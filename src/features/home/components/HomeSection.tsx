import type { ReactNode } from 'react';

type Props = { title: string; description?: string; children: ReactNode };

export default function HomeSection({ title, description, children }: Props) {
  return (
    <section aria-label={title} className="space-y-2 sm:space-y-3">
      <div>
        <h2 className="text-small font-semibold uppercase tracking-wide text-ink-secondary sm:text-card-title sm:normal-case sm:tracking-normal sm:text-ink">
          {title}
        </h2>
        {description && <p className="text-small text-ink-muted">{description}</p>}
      </div>
      {children}
    </section>
  );
}

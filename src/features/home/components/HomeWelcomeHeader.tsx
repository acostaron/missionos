import type { ReactNode } from 'react';
import { PageHeader } from '../../../components/ui';

type Props = {
  name: string;
  organizationName?: string | null;
  /** Translated responsibility labels (never raw codes). */
  responsibilities?: string[];
};

export default function HomeWelcomeHeader({ name, organizationName, responsibilities = [] }: Props) {
  const description: ReactNode = (
    <>
      <span className="block">Missionary Families of Christ</span>
      {organizationName && <span className="block text-small text-ink-muted">{organizationName}</span>}
      {responsibilities.length > 0 && (
        <span className="mt-1 block text-small font-medium text-primary-blue">
          {responsibilities.join(' · ')}
        </span>
      )}
    </>
  );
  return <PageHeader title={`Welcome, ${name}`} description={description} />;
}

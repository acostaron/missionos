import { Link } from 'react-router-dom';
import { ChevronRight } from 'lucide-react';
import { Badge, Card } from '../../../components/ui';

export type AttentionItem = {
  key: string;
  label: string;
  count: number;
  detail?: string;
  tone: 'neutral' | 'warning' | 'danger';
  to?: string;
};

const BADGE = { neutral: 'neutral', warning: 'warning', danger: 'danger' } as const;

export default function AttentionList({ items }: { items: AttentionItem[] }) {
  if (items.length === 0) {
    return (
      <Card padding="compact">
        <p className="text-small text-ink-secondary">Nothing needs your attention right now.</p>
      </Card>
    );
  }
  return (
    <Card padding="none">
      <ul className="divide-y divide-line">
        {items.map((item) => {
          const body = (
            <div className="flex items-center gap-3 px-4 py-3">
              <div className="min-w-0 flex-1">
                <p className="text-body font-medium text-ink">{item.label}</p>
                {item.detail && <p className="text-small text-ink-muted">{item.detail}</p>}
              </div>
              <Badge variant={BADGE[item.tone]}>{item.count}</Badge>
              {item.to && <ChevronRight size={16} aria-hidden="true" className="text-ink-muted" />}
            </div>
          );
          return (
            <li key={item.key}>
              {item.to ? (
                <Link
                  to={item.to}
                  className="block hover:bg-surface-muted focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-focus"
                >
                  {body}
                </Link>
              ) : (
                body
              )}
            </li>
          );
        })}
      </ul>
    </Card>
  );
}

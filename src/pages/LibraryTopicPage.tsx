// Household Library — reading view for one topic (Pass 9.2, written by Claude 2026-10-15)
import { useState } from 'react';
import type { ReactNode } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowUpRight, Check, X } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import {
  formatCopiedAt,
  formatTopicMonth,
  materialKindLabel,
  useReviewTopicVersion,
  useTopicLibraryItem,
  type ContentBlock,
} from '../features/library/api';
import { Alert, Badge, Button, Card, EmptyState, Skeleton } from '../components/ui';

function TopicBlocks({ blocks, skipTitle }: { blocks: ContentBlock[]; skipTitle?: string }) {
  // The page title usually repeats as the first heading; skip it.
  const list =
    blocks.length > 0 && blocks[0].type === 'heading' && skipTitle && blocks[0].text.trim().toLowerCase() === skipTitle.trim().toLowerCase()
      ? blocks.slice(1)
      : blocks;

  const out: ReactNode[] = [];
  let bullets: string[] = [];
  const flush = (key: string) => {
    if (bullets.length) {
      out.push(
        <ul key={key} className="list-disc space-y-1 pl-6 text-base leading-relaxed text-ink">
          {bullets.map((b, i) => (
            <li key={i}>{b}</li>
          ))}
        </ul>,
      );
      bullets = [];
    }
  };
  list.forEach((b, i) => {
    if (b.type === 'list_item') {
      bullets.push(b.text);
      return;
    }
    flush(`ul-${i}`);
    if (b.type === 'heading') {
      out.push(
        <h2 key={i} className="pt-4 text-lg font-semibold text-ink first:pt-0">
          {b.text}
        </h2>,
      );
    } else {
      out.push(
        <p key={i} className="whitespace-pre-line text-base leading-relaxed text-ink">
          {b.text}
        </p>,
      );
    }
  });
  flush('ul-end');
  return <div className="space-y-3">{out}</div>;
}

export default function LibraryTopicPage() {
  const { topicId = null } = useParams<{ topicId: string }>();
  const { activeOrganization } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;
  const { data: topic, isLoading, error, isFetching } = useTopicLibraryItem(orgId, topicId);
  const review = useReviewTopicVersion(orgId);
  const [showPending, setShowPending] = useState(false);
  const [message, setMessage] = useState<{ kind: 'success' | 'danger'; text: string } | null>(null);

  if (isLoading && !topic) {
    return (
      <div className="mx-auto max-w-3xl space-y-4 px-4 py-8 sm:px-6">
        <Skeleton className="h-8 w-2/3" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  if (!topic) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-8 sm:px-6">
        <EmptyState
          title="Topic not available"
          message={error ? (error as Error).message : 'This topic is not in the library.'}
          action={
            <Link to="/app/library" className="text-sm font-medium text-primary hover:underline">
              Open the Household Library
            </Link>
          }
        />
      </div>
    );
  }

  const canManage = topic.can_manage;
  const pending = canManage ? topic.pending : null;
  const viewing = showPending && pending ? pending : (topic.approved ?? pending);
  const isViewingPending = !!pending && viewing?.version_id === pending.version_id;

  const decide = async (decision: 'approve' | 'reject') => {
    if (!pending) return;
    setMessage(null);
    try {
      await review.mutateAsync({ versionId: pending.version_id, decision });
      setShowPending(false);
      setMessage({
        kind: 'success',
        text: decision === 'approve' ? 'Approved. Members can now read this copy.' : 'Copy rejected.',
      });
    } catch (e) {
      setMessage({ kind: 'danger', text: (e as Error).message });
    }
  };

  return (
    <div className="mx-auto max-w-3xl space-y-6 px-4 py-8 sm:px-6">
      <header className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="info">{materialKindLabel(topic.material_kind)}</Badge>
          <span className="text-sm text-ink-muted">{formatTopicMonth(topic.topic_month)}</span>
          {topic.series_title && <span className="text-sm text-ink-muted">· {topic.series_title}</span>}
        </div>
        <h1 className="text-page-title font-semibold tracking-tight text-ink">{topic.title}</h1>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
          {viewing && (
            <span className="text-ink-muted">
              {isViewingPending ? 'New copy from' : 'Copied'} {formatCopiedAt(viewing.copied_at)}
            </span>
          )}
          <a
            href={topic.source_url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 font-medium text-primary hover:underline"
          >
            View current version <ArrowUpRight className="h-4 w-4" aria-hidden="true" />
          </a>
        </div>
        {!isFetching && error && topic.approved && (
          <p className="text-xs text-ink-muted">Showing the copy saved on this device.</p>
        )}
      </header>

      {message && <Alert variant={message.kind} title={message.kind === 'success' ? 'Done' : 'Could not save'}>{message.text}</Alert>}

      {pending && (
        <Card variant="subtle" padding="compact" className="space-y-3">
          <p className="text-sm font-medium text-ink">
            {topic.approved
              ? 'The MFC page has changed. A new copy is waiting for your approval.'
              : 'This copy is waiting for your approval. Members cannot see it yet.'}
          </p>
          <p className="text-xs text-ink-secondary">
            Compare it with the official page (“View current version”) before approving.
          </p>
          <div className="flex flex-wrap gap-2">
            {topic.approved && (
              <Button variant="outline" size="sm" onClick={() => setShowPending((v) => !v)}>
                {isViewingPending ? 'Show approved copy' : 'Show new copy'}
              </Button>
            )}
            <Button size="sm" icon={<Check size={16} />} loading={review.isPending} onClick={() => decide('approve')}>
              Approve
            </Button>
            <Button variant="outline" size="sm" icon={<X size={16} />} disabled={review.isPending} onClick={() => decide('reject')}>
              Reject
            </Button>
          </div>
        </Card>
      )}

      <Card>
        {viewing ? (
          <TopicBlocks blocks={viewing.blocks} skipTitle={topic.title} />
        ) : (
          <EmptyState title="No copy yet" message="Open the current version on the MFC site." />
        )}
      </Card>
    </div>
  );
}

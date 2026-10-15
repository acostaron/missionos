// "Check MFC site" — preview, then copy MFC monthly topics into the library (Pass 9.2, Claude 2026-10-15)
import { useEffect, useState } from 'react';
import { Alert, Badge, Button, Modal } from '../../components/ui';
import { formatTopicMonth, materialKindLabel, useSyncTopicLibrary, type SyncResult } from './api';

const RESULT_LABELS: Record<string, { label: string; variant: 'neutral' | 'info' | 'success' | 'warning' | 'danger' }> = {
  dry_run: { label: 'Ready to copy', variant: 'info' },
  new_topic: { label: 'Copied — new', variant: 'success' },
  changed: { label: 'Copied — updated', variant: 'success' },
  unchanged: { label: 'No change', variant: 'neutral' },
  parse_failed: { label: 'Could not read', variant: 'danger' },
};

function resultBadge(result: string) {
  const known = RESULT_LABELS[result];
  if (known) return <Badge variant={known.variant}>{known.label}</Badge>;
  return <Badge variant="danger">{result.startsWith('fetch_failed') ? 'Could not open page' : 'Error'}</Badge>;
}

export function SyncTopicLibraryModal({
  open,
  onClose,
  organizationId,
}: {
  open: boolean;
  onClose: () => void;
  organizationId: string | null;
}) {
  const sync = useSyncTopicLibrary(organizationId);
  const [preview, setPreview] = useState<SyncResult | null>(null);
  const [copied, setCopied] = useState<SyncResult | null>(null);
  const [errorText, setErrorText] = useState<string | null>(null);

  // Run the preview each time the dialog opens.
  useEffect(() => {
    if (!open) return;
    setPreview(null);
    setCopied(null);
    setErrorText(null);
    sync
      .mutateAsync({ mode: 'dry_run' })
      .then(setPreview)
      .catch((e: Error) => setErrorText(e.message));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const onCopy = async () => {
    setErrorText(null);
    try {
      setCopied(await sync.mutateAsync({ mode: 'ingest' }));
    } catch (e) {
      setErrorText((e as Error).message);
    }
  };

  const shown = copied ?? preview;
  const readable = preview?.results.filter((r) => r.result === 'dry_run').length ?? 0;
  const problems = shown?.results.filter((r) => !['dry_run', 'new_topic', 'changed', 'unchanged'].includes(r.result)) ?? [];

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="lg"
      closeOnBackdrop={!sync.isPending}
      title="Check MFC site"
      description="Reads the 2026 Rooted in Christ topics page on missionaryfamiliesofchrist.org. Copies wait for your approval before members can see them."
      footer={
        <div className="flex w-full flex-wrap justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={sync.isPending}>
            {copied ? 'Done' : 'Cancel'}
          </Button>
          {!copied && (
            <Button onClick={onCopy} loading={sync.isPending && !!preview} disabled={!preview || readable === 0 || sync.isPending}>
              Copy into Library
            </Button>
          )}
        </div>
      }
    >
      <div className="space-y-4">
        {sync.isPending && !preview && <p className="text-sm text-ink-secondary">Reading the MFC site… this can take up to a minute.</p>}

        {errorText && <Alert variant="danger" title="Something went wrong">{errorText}</Alert>}

        {copied && (
          <Alert variant="success" title="Copied">
            New and updated copies are marked “Awaiting approval” in the library. Open each one to review and approve it.
          </Alert>
        )}

        {shown && (
          <>
            <p className="text-sm text-ink-secondary">
              Found {shown.discovered_count} topic links. Newest month: {formatTopicMonth(`${shown.newest_month}-01`)}.
              {shown.from_month && <> Only {formatTopicMonth(`${shown.from_month}-01`)} and later are copied.</>}
              {' '}The Personal Sharing and Chapter Assembly guides are copied for the newest month only.
            </p>

            {problems.length > 0 && (
              <Alert variant="warning" title={`${problems.length} page(s) could not be read`}>
                These will be skipped. Send Claude a screenshot of this list.
              </Alert>
            )}

            {shown.unclassified_links.length > 0 && (
              <Alert variant="info" title="Links not recognised">
                <ul className="list-disc pl-5">
                  {shown.unclassified_links.map((t) => (
                    <li key={t}>{t}</li>
                  ))}
                </ul>
              </Alert>
            )}

            <div className="max-h-[50vh] overflow-y-auto rounded-control border border-line">
              <table className="w-full text-left text-sm">
                <thead className="sticky top-0 bg-surface-muted text-xs uppercase text-ink-muted">
                  <tr>
                    <th className="px-3 py-2">Month</th>
                    <th className="px-3 py-2">Type</th>
                    <th className="px-3 py-2">Sections</th>
                    <th className="px-3 py-2">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {shown.results.map((r) => (
                    <tr key={`${r.month}|${r.kind}|${r.url}`} className="border-t border-line align-top">
                      <td className="whitespace-nowrap px-3 py-2 text-ink">{formatTopicMonth(`${r.month}-01`)}</td>
                      <td className="px-3 py-2 text-ink">
                        <a href={r.url} target="_blank" rel="noopener noreferrer" className="text-primary underline-offset-2 hover:underline">
                          {materialKindLabel(r.kind)}
                        </a>
                      </td>
                      <td className="px-3 py-2 text-ink-secondary">
                        {r.heading_count ?? '–'}
                        {r.block_count !== undefined && (
                          <span className="block text-xs text-ink-muted">{r.block_count} lines</span>
                        )}
                        {r.headings && r.headings.length > 0 && (
                          <span className="block text-xs text-ink-muted">{r.headings.join(' · ')}</span>
                        )}
                      </td>
                      <td className="px-3 py-2">{resultBadge(r.result)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}

// Library > Official Documents (Pass 9.36, Ron 2026-10-21): official MFC documents and guidelines from the MFCNY
// shared Google Drive, for Unit Servant Leaders and up. Grouped by category (the Drive subfolder).
import { useMemo, useState } from 'react';
import { ExternalLink, FileText, FolderSync, Search } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { normalizeError } from '../lib/supabase/errors';
import { formatNyDateShort, formatNyTime } from '../lib/ny-time';
import {
  fileTypeLabel,
  formatFileSize,
  openOfficialDocument,
  parseDriveFolderId,
  useOfficialDocuments,
  useOfficialDocumentsServiceAccount,
  useSetOfficialDocumentsFolder,
  useSyncOfficialDocuments,
  type OfficialDocument,
  type OfficialDocumentsList,
} from '../features/official-documents/api';
import { Alert, Badge, Button, Card, EmptyState, Input, PageHeader, Select, Skeleton } from '../components/ui';

function when(iso: string): string {
  return `${formatNyDateShort(iso)} ${formatNyTime(iso)}`;
}

function DriveSetupCard({ orgId, data }: { orgId: string; data: OfficialDocumentsList }) {
  const [link, setLink] = useState('');
  const [editing, setEditing] = useState(!data.folder_set);
  const [formError, setFormError] = useState<string | null>(null);
  const info = useOfficialDocumentsServiceAccount(orgId, true);
  const setFolder = useSetOfficialDocumentsFolder(orgId);
  const sync = useSyncOfficialDocuments(orgId);
  const r = sync.data;
  const last = data.last_sync;

  const save = async () => {
    setFormError(null);
    const id = parseDriveFolderId(link);
    if (!id) {
      setFormError('Paste the link of the Google Drive folder (it contains “/folders/”).');
      return;
    }
    try {
      await setFolder.mutateAsync(id);
      setEditing(false);
      setLink('');
      sync.mutate();
    } catch (e) {
      setFormError(normalizeError(e).message);
    }
  };

  return (
    <Card padding="compact" className="space-y-3">
      <div className="flex items-center gap-2">
        <FolderSync className="h-5 w-5 text-ink-muted" aria-hidden="true" />
        <h2 className="text-sm font-semibold text-ink">Google Drive folder (administrators)</h2>
      </div>

      {info.data && !info.data.key_set && (
        <Alert variant="warning" title="Google key not set yet">
          The Google service account key has not been added to MissionOS yet.
        </Alert>
      )}
      {info.data?.service_account_email && (
        <p className="text-xs text-ink-secondary">
          Share the folder (or the shared drive) in Google Drive with{' '}
          <span className="break-all font-medium text-ink">{info.data.service_account_email}</span> as <b>Viewer</b>.
          Each subfolder becomes a category. MissionOS checks the folder every night.
        </p>
      )}

      {editing ? (
        <div className="space-y-2">
          <Input
            placeholder="https://drive.google.com/drive/folders/…"
            value={link}
            onChange={(e) => setLink(e.target.value)}
            aria-label="Drive folder link"
          />
          {formError && <p className="text-xs text-danger-700">{formError}</p>}
          <div className="flex gap-2">
            <Button size="sm" onClick={save} loading={setFolder.isPending}>
              Save folder
            </Button>
            {data.folder_set && (
              <Button size="sm" variant="ghost" onClick={() => setEditing(false)}>
                Cancel
              </Button>
            )}
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap items-center gap-2">
          {data.folder_id && (
            <a
              href={`https://drive.google.com/drive/folders/${data.folder_id}`}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 text-sm text-primary hover:underline"
            >
              Open folder in Drive <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
            </a>
          )}
          <Button size="sm" variant="ghost" onClick={() => setEditing(true)}>
            Change folder
          </Button>
          <Button size="sm" variant="outline" className="ml-auto" onClick={() => sync.mutate()} loading={sync.isPending}>
            Sync now
          </Button>
        </div>
      )}

      {sync.isPending && <p className="text-xs text-ink-muted">Copying documents from Drive… this can take a minute or two.</p>}
      {sync.error && (
        <Alert variant="danger" title="Sync did not finish">
          {(sync.error as Error).message}
        </Alert>
      )}
      {r && (
        <div className="space-y-1 text-xs text-ink-secondary">
          <p>
            {r.listed_count} documents in the folder: {r.copied_count} added, {r.updated_count} updated,{' '}
            {r.removed_count} removed{r.pending_count > 0 ? `, ${r.pending_count} still to copy (tap Sync now again)` : ''}.
          </p>
          {r.failed.length > 0 && (
            <p className="text-danger-700">
              Could not copy: {r.failed.map((f) => `${f.title} (${f.error})`).join('; ')}
            </p>
          )}
          {r.skipped.length > 0 && <p>Skipped (file type not supported): {r.skipped.join(', ')}</p>}
        </div>
      )}
      {!r && last && (
        <p className="text-xs text-ink-muted">
          Last sync ({last.trigger_source === 'scheduled' ? 'nightly' : 'by hand'}) {when(last.ran_at)}:{' '}
          {last.error
            ? last.error
            : `${last.listed_count} documents, ${last.new_count} added, ${last.updated_count} updated, ${last.removed_count} removed` +
              (last.failed_count > 0 ? `, ${last.failed_count} could not be copied` : '') +
              (last.pending_count > 0 ? `, ${last.pending_count} still to copy` : '') +
              '.'}
        </p>
      )}
    </Card>
  );
}

export default function OfficialDocumentsPage() {
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;
  const { data, isLoading, error } = useOfficialDocuments(orgId);
  const [q, setQ] = useState('');
  const [category, setCategory] = useState('all');
  const [openError, setOpenError] = useState<string | null>(null);

  const items = useMemo(() => data?.items ?? [], [data]);
  const categories = useMemo(() => Array.from(new Set(items.map((i) => i.category))), [items]);

  const groups = useMemo(() => {
    const term = q.trim().toLowerCase();
    const map = new Map<string, OfficialDocument[]>();
    for (const i of items) {
      if (category !== 'all' && i.category !== category) continue;
      if (term && !`${i.title} ${i.category} ${i.folder_path ?? ''}`.toLowerCase().includes(term)) continue;
      if (!map.has(i.category)) map.set(i.category, []);
      map.get(i.category)!.push(i);
    }
    return Array.from(map.entries());
  }, [items, q, category]);

  const open = async (doc: OfficialDocument) => {
    setOpenError(null);
    try {
      await openOfficialDocument(doc);
    } catch (e) {
      setOpenError(normalizeError(e).message);
    }
  };

  if (isOrgLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center">
        <div className="text-sm text-ink-muted">Loading…</div>
      </div>
    );
  }

  if (error) {
    const e = normalizeError(error);
    return (
      <div className="mx-auto max-w-3xl px-4 py-8 sm:px-6">
        <Alert variant="warning" title="Official Documents">
          {e.code === '42501' ? 'Official Documents are for Unit Servant Leaders and up.' : e.message}
        </Alert>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6 px-4 py-8 sm:px-6">
      <PageHeader
        title="Official Documents and Guidelines"
        description="Official MFC documents for Unit Servant Leaders and up, from the MFCNY shared Google Drive."
      />

      {data?.can_manage && orgId && <DriveSetupCard orgId={orgId} data={data} />}
      {openError && <Alert variant="danger" title="Could not open the document">{openError}</Alert>}

      {isLoading ? (
        <div className="space-y-3">
          <Skeleton className="h-16 w-full" />
          <Skeleton className="h-16 w-full" />
          <Skeleton className="h-16 w-full" />
        </div>
      ) : items.length === 0 ? (
        <EmptyState
          icon={<FileText />}
          title="No documents yet"
          message={
            data?.can_manage
              ? 'Set the Google Drive folder above and tap Sync now.'
              : 'The documents have not been added yet.'
          }
        />
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">Search</span>
              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
                <Input className="pl-9" placeholder="Title or category" value={q} onChange={(e) => setQ(e.target.value)} />
              </div>
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-ink-secondary">Category</span>
              <Select value={category} onChange={(e) => setCategory(e.target.value)}>
                <option value="all">All categories</option>
                {categories.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </Select>
            </label>
          </div>

          {groups.length === 0 ? (
            <EmptyState title="Nothing here" message="No documents match your search." />
          ) : (
            groups.map(([cat, list]) => (
              <section key={cat} className="space-y-3">
                <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">
                  {cat} <span className="font-normal normal-case">({list.length})</span>
                </h2>
                <ul className="space-y-2">
                  {list.map((d) => (
                    <li key={d.id}>
                      <button
                        type="button"
                        onClick={() => void open(d)}
                        className="block w-full rounded-card text-left focus-visible:outline-2 focus-visible:outline-focus"
                      >
                        <Card variant="interactive" padding="compact" className="flex items-center gap-3">
                          <FileText className="h-5 w-5 shrink-0 text-ink-muted" aria-hidden="true" />
                          <div className="min-w-0 flex-1 space-y-0.5">
                            <p className="text-base font-medium text-ink">{d.title}</p>
                            <p className="text-xs text-ink-muted">
                              {d.folder_path ? `${d.folder_path} · ` : ''}Updated {formatNyDateShort(d.updated_at)}
                              {d.file_size ? ` · ${formatFileSize(d.file_size)}` : ''}
                            </p>
                          </div>
                          <Badge variant={d.file_extension === 'pdf' ? 'info' : 'neutral'}>{fileTypeLabel(d.file_extension)}</Badge>
                        </Card>
                      </button>
                    </li>
                  ))}
                </ul>
              </section>
            ))
          )}
        </>
      )}
    </div>
  );
}

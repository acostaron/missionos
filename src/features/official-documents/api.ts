// Library > Official Documents (Pass 9.36, Ron 2026-10-21): official MFC documents and guidelines copied from the
// MFCNY shared Google Drive folder. Unit Servant Leaders and up; administrators set the folder and sync.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export interface OfficialDocument {
  id: string;
  title: string;
  category: string;
  folder_path: string | null;
  mime_type: string;
  file_extension: string;
  file_size: number | null;
  updated_at: string;
  copied_at: string | null;
  storage_path: string;
}

export interface OfficialDocumentsSyncRun {
  ran_at: string;
  trigger_source: 'scheduled' | 'manual';
  listed_count: number;
  new_count: number;
  updated_count: number;
  removed_count: number;
  skipped_count: number;
  failed_count: number;
  pending_count: number;
  error: string | null;
}

export interface OfficialDocumentsList {
  can_manage: boolean;
  folder_set: boolean;
  folder_id: string | null;
  last_sync: OfficialDocumentsSyncRun | null;
  items: OfficialDocument[];
}

export interface OfficialDocumentsSyncResult {
  listed_count: number;
  copied_count: number;
  updated_count: number;
  unchanged_count: number;
  removed_count: number;
  pending_count: number;
  skipped: string[];
  failed: { title: string; error: string }[];
}

const keys = {
  access: (orgId: string | null) => ['official-documents', 'access', orgId] as const,
  list: (orgId: string | null) => ['official-documents', 'list', orgId] as const,
  info: (orgId: string | null) => ['official-documents', 'info', orgId] as const,
};

/** For the Library tab: can this person see the documents? */
export function useOfficialDocumentsAccess(orgId: string | null) {
  return useQuery<{ can_view: boolean; can_manage: boolean }>({
    queryKey: keys.access(orgId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_official_documents_access', { p_organization_id: orgId! });
      if (error) throw error;
      return data as unknown as { can_view: boolean; can_manage: boolean };
    },
    enabled: !!orgId,
    staleTime: 5 * 60 * 1000,
  });
}

export function useOfficialDocuments(orgId: string | null) {
  return useQuery<OfficialDocumentsList>({
    queryKey: keys.list(orgId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_official_documents', { p_organization_id: orgId! });
      if (error) throw error;
      return data as unknown as OfficialDocumentsList;
    },
    enabled: !!orgId,
  });
}

/** Folder id from a Drive folder link (or the id itself). Null when it cannot be read. */
export function parseDriveFolderId(input: string): string | null {
  const t = input.trim();
  if (!t) return null;
  const m = t.match(/\/folders\/([A-Za-z0-9_-]{10,100})/) ?? t.match(/[?&]id=([A-Za-z0-9_-]{10,100})/);
  if (m) return m[1];
  return /^[A-Za-z0-9_-]{10,100}$/.test(t) ? t : null;
}

export function useSetOfficialDocumentsFolder(orgId: string | null) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (folderId: string | null) => {
      const { data, error } = await supabase.rpc('set_official_documents_folder', {
        p_organization_id: orgId!,
        p_drive_folder_id: folderId ?? '',
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['official-documents'] }),
  });
}

async function invokeSync<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('sync-official-documents', { body });
  if (error) {
    let message = error.message;
    try {
      const ctx = (error as { context?: Response }).context;
      if (ctx && typeof ctx.json === 'function') {
        const b = await ctx.json();
        if (b?.error) message = String(b.error);
      }
    } catch {
      // keep the generic message
    }
    throw new Error(message);
  }
  return data as T;
}

/** Administrators: the service account email to share the Drive folder with. */
export function useOfficialDocumentsServiceAccount(orgId: string | null, enabled: boolean) {
  return useQuery<{ service_account_email: string | null; key_set: boolean }>({
    queryKey: keys.info(orgId),
    queryFn: () => invokeSync({ organization_id: orgId, action: 'info' }),
    enabled: !!orgId && enabled,
    staleTime: 30 * 60 * 1000,
    retry: false,
  });
}

/** Sync now; repeats (up to 6 runs) while copies are still pending. */
export function useSyncOfficialDocuments(orgId: string | null) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      const total: OfficialDocumentsSyncResult = {
        listed_count: 0, copied_count: 0, updated_count: 0, unchanged_count: 0, removed_count: 0,
        pending_count: 0, skipped: [], failed: [],
      };
      for (let run = 0; run < 6; run++) {
        const r = await invokeSync<OfficialDocumentsSyncResult>({ organization_id: orgId });
        total.listed_count = r.listed_count;
        total.copied_count += r.copied_count;
        total.updated_count += r.updated_count;
        total.removed_count += r.removed_count;
        total.pending_count = r.pending_count;
        total.skipped = r.skipped;
        total.failed = r.failed;
        if (run === 0) total.unchanged_count = r.unchanged_count;
        if (r.pending_count === 0) break;
      }
      return total;
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ['official-documents'] }),
  });
}

const SIGNED_SECONDS = 600;

/**
 * Opens a document in a new tab (a short-lived private link). The tab is opened before the link is made so that
 * phones do not block it.
 */
export async function openOfficialDocument(doc: OfficialDocument): Promise<void> {
  const win = window.open('', '_blank');
  try {
    const isPdf = doc.mime_type === 'application/pdf';
    const { data, error } = await supabase.storage
      .from('official-documents')
      .createSignedUrl(doc.storage_path, SIGNED_SECONDS, isPdf ? undefined : { download: `${doc.title}.${doc.file_extension}` });
    if (error) throw error;
    if (win) win.location.href = data.signedUrl;
    else window.location.assign(data.signedUrl);
  } catch (e) {
    win?.close();
    throw e;
  }
}

export function fileTypeLabel(ext: string): string {
  switch (ext.toLowerCase()) {
    case 'pdf': return 'PDF';
    case 'doc': case 'docx': return 'Word';
    case 'xls': case 'xlsx': return 'Excel';
    case 'ppt': case 'pptx': return 'PowerPoint';
    default: return ext.toUpperCase();
  }
}

export function formatFileSize(bytes: number | null): string {
  if (!bytes) return '';
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

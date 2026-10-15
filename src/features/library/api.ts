// Household Library — MFC monthly topics (Pass 9.2, written by Claude 2026-10-15)
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { z } from 'zod';
import { supabase } from '../../lib/supabase/client';

// ---------------------------------------------------------------------------
// Labels
// ---------------------------------------------------------------------------

export const MATERIAL_KINDS = [
  'household_topic',
  'family_household_topic',
  'date_night_topic',
  'personal_sharing_guide',
  'chapter_teaching',
  'chapter_assembly_guide',
] as const;
export type MaterialKind = (typeof MATERIAL_KINDS)[number];

export const MATERIAL_KIND_LABELS: Record<MaterialKind, string> = {
  household_topic: 'Household Topic',
  family_household_topic: 'Family Household Topic',
  date_night_topic: 'Date Night Topic',
  personal_sharing_guide: 'Personal Sharing Guide',
  chapter_teaching: 'Chapter Teaching Topic',
  chapter_assembly_guide: 'Chapter Assembly Guide',
};

export function materialKindLabel(kind: string): string {
  return (MATERIAL_KIND_LABELS as Record<string, string>)[kind] ?? kind;
}

/** '2026-10-01' -> 'October 2026' (date-only, no timezone shift) */
export function formatTopicMonth(topicMonth: string): string {
  const [y, m] = topicMonth.slice(0, 10).split('-').map(Number);
  if (!y || !m) return topicMonth;
  return new Intl.DateTimeFormat('en-US', { year: 'numeric', month: 'long', timeZone: 'UTC' }).format(
    new Date(Date.UTC(y, m - 1, 15)),
  );
}

export function formatCopiedAt(iso: string | null | undefined): string {
  if (!iso) return '';
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'America/New_York',
  }).format(new Date(iso));
}

// ---------------------------------------------------------------------------
// Schemas
// ---------------------------------------------------------------------------

export const contentBlockSchema = z.object({
  type: z.enum(['heading', 'paragraph', 'list_item']),
  text: z.string(),
  level: z.number().optional(),
});
export type ContentBlock = z.infer<typeof contentBlockSchema>;

export const libraryItemSchema = z.object({
  topic_id: z.string(),
  title: z.string(),
  topic_code: z.string().nullable(),
  series_code: z.string().nullable(),
  series_title: z.string().nullable(),
  topic_month: z.string(),
  material_kind: z.string(),
  source_url: z.string(),
  has_content: z.boolean(),
  copied_at: z.string().nullable(),
  has_pending: z.boolean(),
});
export type LibraryItem = z.infer<typeof libraryItemSchema>;

export const libraryListSchema = z.object({
  can_manage: z.boolean(),
  pending_review_count: z.number(),
  items: z.array(libraryItemSchema),
});
export type LibraryList = z.infer<typeof libraryListSchema>;

const versionSchema = z.object({
  version_id: z.string(),
  version_number: z.number(),
  copied_at: z.string(),
  approved_at: z.string().nullable().optional(),
  blocks: z.array(contentBlockSchema),
});

export const libraryTopicSchema = z.object({
  topic_id: z.string(),
  title: z.string(),
  topic_code: z.string().nullable(),
  series_code: z.string().nullable(),
  series_title: z.string().nullable(),
  topic_month: z.string(),
  material_kind: z.string(),
  source_url: z.string(),
  can_manage: z.boolean(),
  approved: versionSchema.nullable(),
  pending: versionSchema.nullable(),
});
export type LibraryTopic = z.infer<typeof libraryTopicSchema>;

export const syncResultSchema = z.object({
  mode: z.enum(['dry_run', 'ingest']),
  series_code: z.string(),
  newest_month: z.string(),
  discovered_count: z.number(),
  processed_count: z.number(),
  unclassified_links: z.array(z.string()),
  results: z.array(
    z.object({
      month: z.string(),
      kind: z.string(),
      url: z.string(),
      result: z.string(),
      block_count: z.number().optional(),
      heading_count: z.number().optional(),
      headings: z.array(z.string()).optional(),
    }),
  ),
});
export type SyncResult = z.infer<typeof syncResultSchema>;

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

export const libraryKeys = {
  all: ['topic-library'] as const,
  list: (orgId: string | null) => [...libraryKeys.all, 'list', orgId] as const,
  item: (orgId: string | null, topicId: string | null) => [...libraryKeys.all, 'item', orgId, topicId] as const,
};

// Topics a member has opened are kept on the device so they can be read
// during a meeting with a weak signal. Only approved copies are stored.
const OFFLINE_PREFIX = 'missionos.library.topic.';

function readOffline(orgId: string, topicId: string): LibraryTopic | undefined {
  try {
    const raw = window.localStorage.getItem(`${OFFLINE_PREFIX}${orgId}.${topicId}`);
    if (!raw) return undefined;
    const parsed = libraryTopicSchema.safeParse(JSON.parse(raw));
    return parsed.success ? parsed.data : undefined;
  } catch {
    return undefined;
  }
}

function writeOffline(orgId: string, topic: LibraryTopic) {
  try {
    if (!topic.approved) return;
    const slim: LibraryTopic = { ...topic, pending: null, can_manage: false };
    window.localStorage.setItem(`${OFFLINE_PREFIX}${orgId}.${topic.topic_id}`, JSON.stringify(slim));
  } catch {
    // storage full or blocked — reading online still works
  }
}

// ---------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------

export function useTopicLibrary(organizationId: string | null) {
  return useQuery<LibraryList>({
    queryKey: libraryKeys.list(organizationId),
    queryFn: async () => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('list_topic_library', {
        p_organization_id: organizationId,
      });
      if (error) throw error;
      return libraryListSchema.parse(data);
    },
    enabled: !!organizationId,
    staleTime: 60_000,
  });
}

export function useTopicLibraryItem(organizationId: string | null, topicId: string | null) {
  return useQuery<LibraryTopic>({
    queryKey: libraryKeys.item(organizationId, topicId),
    queryFn: async () => {
      if (!organizationId || !topicId) throw new Error('Topic is required');
      const { data, error } = await supabase.rpc('get_topic_library_item', {
        p_organization_id: organizationId,
        p_topic_id: topicId,
      });
      if (error) throw error;
      const topic = libraryTopicSchema.parse(data);
      writeOffline(organizationId, topic);
      return topic;
    },
    enabled: !!organizationId && !!topicId,
    staleTime: 60_000,
    initialData: () => (organizationId && topicId ? readOffline(organizationId, topicId) : undefined),
    initialDataUpdatedAt: 0,
  });
}

export function useReviewTopicVersion(organizationId: string | null) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { versionId: string; decision: 'approve' | 'reject'; notes?: string }) => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('review_topic_content_version', {
        p_organization_id: organizationId,
        p_version_id: args.versionId,
        p_decision: args.decision,
        p_notes: args.notes ?? undefined,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: libraryKeys.all });
    },
  });
}

export function useSyncTopicLibrary(organizationId: string | null) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { mode: 'dry_run' | 'ingest'; months?: string[] }) => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.functions.invoke('sync-topic-library', {
        body: { organization_id: organizationId, mode: args.mode, months: args.months },
      });
      if (error) {
        // FunctionsHttpError carries the JSON body in error.context
        let message = error.message;
        try {
          const ctx = (error as { context?: Response }).context;
          if (ctx && typeof ctx.json === 'function') {
            const body = await ctx.json();
            if (body?.error) message = String(body.error);
          }
        } catch {
          // keep the generic message
        }
        throw new Error(message);
      }
      return syncResultSchema.parse(data);
    },
    onSuccess: (_d, args) => {
      if (args.mode === 'ingest') qc.invalidateQueries({ queryKey: libraryKeys.all });
    },
  });
}

import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import type { FormationTopicSearchResult } from '../types';
import { formationKeys } from './get-household-formation-plan';

export async function searchFormationTopics(
  organizationId: string,
  search: string | null = null,
  pastoralLevel: string | null = null,
  limit = 50,
  offset = 0
): Promise<FormationTopicSearchResult> {
  const { data, error } = await supabase.rpc('search_formation_topics', {
    p_organization_id: organizationId,
    p_search: search ?? undefined,
    p_pastoral_level: pastoralLevel ?? undefined,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) throw error;
  return data as unknown as FormationTopicSearchResult;
}

export function useFormationTopics(
  organizationId: string | null,
  search: string,
  pastoralLevel: string | null,
  enabled = true
) {
  return useQuery({
    queryKey: organizationId
      ? [...formationKeys.topics(organizationId, search), pastoralLevel ?? 'any']
      : ['household-formation', 'topics-disabled'],
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      return searchFormationTopics(organizationId, search.trim() || null, pastoralLevel);
    },
    enabled: !!organizationId && enabled,
    staleTime: 60_000,
  });
}
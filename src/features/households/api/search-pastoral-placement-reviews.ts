import { supabase } from '../../../lib/supabase/client';
import type { PastoralPlacementQueueItem } from '../types';

export interface SearchPastoralPlacementReviewsParams {
  organizationId: string;
  includeCorrect?: boolean;
  limit?: number;
  offset?: number;
}

export interface SearchPastoralPlacementReviewsResult {
  total_count: number;
  items: PastoralPlacementQueueItem[];
}

export async function searchPastoralPlacementReviews({
  organizationId,
  includeCorrect = false,
  limit = 50,
  offset = 0,
}: SearchPastoralPlacementReviewsParams): Promise<SearchPastoralPlacementReviewsResult> {
  const { data, error } = await supabase.rpc(
    'search_servant_leaders_needing_pastoral_placement',
    {
      p_organization_id: organizationId,
      p_include_correct: includeCorrect,
      p_limit: limit,
      p_offset: offset,
    }
  );

  if (error) {
    throw error;
  }

  return data as unknown as SearchPastoralPlacementReviewsResult;
}

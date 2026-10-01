import { supabase } from '../../../lib/supabase/client';
import type { PastoralPlacementReview } from '../types';

export async function getPastoralPlacementReview(
  organizationId: string,
  leadershipAssignmentId: string
): Promise<PastoralPlacementReview> {
  const { data, error } = await supabase.rpc('get_pastoral_placement_review', {
    p_organization_id: organizationId,
    p_leadership_assignment_id: leadershipAssignmentId,
  });

  if (error) {
    throw error;
  }

  return data as unknown as PastoralPlacementReview;
}

import { supabase } from '../../../lib/supabase/client';
import type {
  PastoralPlacementExecutionInput,
  PastoralPlacementExecutionResult,
} from '../types';

export async function executePastoralPlacement({
  organizationId,
  leadershipAssignmentId,
  destinationHouseholdId,
  effectiveDate,
  reason,
  includeVerifiedSpouse = true,
}: PastoralPlacementExecutionInput): Promise<PastoralPlacementExecutionResult> {
  const { data, error } = await supabase.rpc('execute_pastoral_placement', {
    p_organization_id: organizationId,
    p_leadership_assignment_id: leadershipAssignmentId,
    p_destination_household_id: destinationHouseholdId,
    p_effective_date: effectiveDate,
    p_reason: reason,
    p_include_verified_spouse: includeVerifiedSpouse,
  });

  if (error) {
    throw error;
  }

  return data as unknown as PastoralPlacementExecutionResult;
}

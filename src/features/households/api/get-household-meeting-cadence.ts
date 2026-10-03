import { supabase } from '../../../lib/supabase/client';
import type { HouseholdMeetingCadence } from '../types';

export async function getHouseholdMeetingCadence(
  organizationId: string,
  householdId: string
): Promise<HouseholdMeetingCadence> {
  const { data, error } = await supabase.rpc('get_household_meeting_cadence', {
    p_organization_id: organizationId,
    p_household_id: householdId,
  });

  if (error) throw error;
  return data as unknown as HouseholdMeetingCadence;
}

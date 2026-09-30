import { supabase } from '../../../lib/supabase/client';
import type { UpdateHouseholdInput, UpdateHouseholdResult } from '../types';

export async function updateHousehold(
  organizationId: string,
  input: UpdateHouseholdInput
): Promise<UpdateHouseholdResult> {
  const { data, error } = await supabase.rpc('update_household', {
    p_organization_id: organizationId,
    p_household_id: input.household_id,
    p_name: input.name,
    p_code: input.code,
    p_household_category: input.household_category ?? 'pastoral',
    p_meeting_frequency: input.meeting_frequency ?? 'weekly',
    p_meeting_day_of_week: input.meeting_day_of_week ?? undefined,
    p_meeting_start_time: input.meeting_start_time ?? undefined,
    p_meeting_timezone_name: input.meeting_timezone_name ?? 'America/New_York',
    p_meeting_location_type: input.meeting_location_type ?? 'residence',
    p_meeting_location_text: input.meeting_location_text ?? undefined,
    p_target_member_count: input.target_member_count ?? undefined,
    p_maximum_member_count: input.maximum_member_count ?? undefined,
    p_accepts_new_members: input.accepts_new_members ?? true,
    p_language_code: input.language_code ?? 'en',
    p_is_couple_household: input.is_couple_household ?? false,
  });

  if (error) {
    throw error;
  }

  return data as unknown as UpdateHouseholdResult;
}

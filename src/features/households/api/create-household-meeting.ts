import { supabase } from '../../../lib/supabase/client';

export interface CreateHouseholdMeetingInput {
  household_id: string;
  meeting_date: string;
  meeting_type?: string;
  scheduled_start_at?: string | null;
  scheduled_end_at?: string | null;
  location_type?: string | null;
  location_text?: string | null;
  facilitator_member_id?: string | null;
  host_member_id?: string | null;
}

export interface CreateHouseholdMeetingResult {
  household_meeting_id: string;
  household_node_id: string;
  meeting_date: string;
  meeting_status: 'scheduled';
  meeting_type: string;
}

export async function createHouseholdMeeting(
  organizationId: string,
  input: CreateHouseholdMeetingInput
): Promise<CreateHouseholdMeetingResult> {
  const { data, error } = await supabase.rpc('create_household_meeting', {
    p_organization_id: organizationId,
    p_household_id: input.household_id,
    p_meeting_date: input.meeting_date,
    p_meeting_type: input.meeting_type ?? 'regular_household',
    p_scheduled_start_at: input.scheduled_start_at ?? undefined,
    p_scheduled_end_at: input.scheduled_end_at ?? undefined,
    p_location_type: input.location_type ?? undefined,
    p_location_text: input.location_text ?? undefined,
    p_facilitator_member_id: input.facilitator_member_id ?? undefined,
    p_host_member_id: input.host_member_id ?? undefined,
    // p_notes_summary deliberately omitted — reserved/unused in Phase 6B-8
  });

  if (error) throw error;
  return data as unknown as CreateHouseholdMeetingResult;
}

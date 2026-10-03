import { supabase } from '../../../lib/supabase/client';
import type { Json } from '../../../types/database';
import type { AttendanceSummary } from '../types';

export type AttendanceStatus = 'present' | 'absent' | 'excused';

export interface AttendanceItem {
  member_id: string;
  attendance_status: AttendanceStatus;
}

export interface RecordAttendanceResult {
  household_meeting_id: string;
  rows_inserted: number;
  rows_updated: number;
  has_correction: boolean;
  attendance_summary: AttendanceSummary;
}

export async function recordHouseholdMeetingAttendance(
  organizationId: string,
  meetingId: string,
  attendance: AttendanceItem[]
): Promise<RecordAttendanceResult> {
  const { data, error } = await supabase.rpc('record_household_meeting_attendance', {
    p_organization_id: organizationId,
    p_meeting_id: meetingId,
    p_attendance: attendance as unknown as Json,
  });

  if (error) throw error;
  return data as unknown as RecordAttendanceResult;
}

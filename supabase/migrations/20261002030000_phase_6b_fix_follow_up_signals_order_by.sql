-- =============================================================================
-- Migration: 20261002030000_phase_6b_fix_follow_up_signals_order_by.sql
-- Phase:     Phase 6B-8 — Household Meetings, Attendance & Pastoral Follow-up
--            Bug fix for private.get_member_follow_up_signals
--
-- Root Cause:
--   In 20261002000000 (line 1261), array_agg uses ORDER BY meeting_date DESC
--   against the subquery alias `sub` which only SELECTs `id`. PostgreSQL
--   defers this column resolution to execution time, so the function compiles
--   successfully but raises:
--     ERROR 42703: column "meeting_date" does not exist
--   at runtime when the subquery returns rows.
--
-- Fix:
--   The inner subquery already orders by meeting_date DESC LIMIT 3, guaranteeing
--   correct row order before aggregation. The outer ORDER BY in array_agg is
--   redundant and incorrect. Remove it.
--
-- Impact:
--   - The aggregated uuid[] order is now determined solely by the inner subquery
--     ORDER BY meeting_date DESC, which is the correct semantic behavior.
--   - v_last_3_meetings[1] is still the most-recent completed meeting id.
--   - No behavioral change for the zero-meeting case.
--   - No DDL changes. No data mutations. No permission changes.
--
-- Frozen migrations (DO NOT EDIT):
--   20261002000000 — original 38 statements
--   20261002010000 — 3 statements, record_status correction
--   20261002020000 — 29 statements, notes_summary restriction + dashboard extension
-- =============================================================================

create or replace function private.get_member_follow_up_signals(
  p_organization_id   uuid,
  p_member_id         uuid,
  p_household_node_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_last_3_meetings   uuid[];
  v_absent_count      integer := 0;
  v_total_recent      integer := 0;
  v_last_status       text;
  v_missed_last       boolean := false;
  v_multiple_absences boolean := false;
begin
  -- FIX (020300): Removed erroneous ORDER BY meeting_date in outer array_agg.
  -- The inner subquery already orders by meeting_date DESC LIMIT 3, so the
  -- outer aggregation order is correct without repeating the ORDER BY clause.
  -- The original ORDER BY meeting_date in array_agg() referenced a column not
  -- projected by `sub` (which only SELECTs id), causing a runtime 42703 error.
  select array_agg(id)
  into v_last_3_meetings
  from (
    select id
    from public.household_meetings
    where household_node_id = p_household_node_id
      and organization_id   = p_organization_id
      and meeting_status    = 'completed'
    order by meeting_date desc
    limit 3
  ) sub;

  if v_last_3_meetings is null or array_length(v_last_3_meetings, 1) = 0 then
    return jsonb_build_object(
      'multiple_recent_absences', false,
      'missed_last_meeting',      false,
      'attendance_not_recorded',  false,
      'absence_count_in_last_3',  0,
      'meetings_checked',         0
    );
  end if;

  v_total_recent := array_length(v_last_3_meetings, 1);

  -- Count only 'absent' rows; 'excused' is NOT counted as absence
  select count(*) into v_absent_count
  from public.household_meeting_attendance
  where organization_id      = p_organization_id
    and household_meeting_id = any(v_last_3_meetings)
    and member_id            = p_member_id
    and attendance_status    = 'absent';

  -- Last meeting status (v_last_3_meetings[1] = most-recent, per inner ORDER BY)
  select attendance_status into v_last_status
  from public.household_meeting_attendance
  where organization_id      = p_organization_id
    and household_meeting_id = v_last_3_meetings[1]
    and member_id            = p_member_id;

  v_missed_last       := (v_last_status = 'absent');
  v_multiple_absences := (v_absent_count >= 2);

  return jsonb_build_object(
    'multiple_recent_absences', v_multiple_absences,
    'missed_last_meeting',      v_missed_last,
    'absence_count_in_last_3',  v_absent_count,
    'meetings_checked',         v_total_recent,
    'attendance_not_recorded',  (v_last_status is null and v_total_recent > 0)
  );
end;
$$;

comment on function private.get_member_follow_up_signals(uuid, uuid, uuid) is
  'Returns follow-up signals for a member in a household based on attendance in the last 3 '
  'completed meetings. multiple_recent_absences=true when absent_count >= 2. '
  'excused does not count as absent. 020300: Fixed runtime 42703 by removing erroneous '
  'ORDER BY meeting_date in outer array_agg (column not projected by subquery).';

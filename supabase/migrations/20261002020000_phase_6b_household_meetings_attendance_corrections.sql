-- =============================================================================
-- Migration: 20261002020000_phase_6b_household_meetings_attendance_corrections.sql
-- Phase:     Phase 6B-8 — Household Meetings, Attendance & Pastoral Follow-up
--            Corrective patch for 20261002000000 + 20261002010000
--
-- Corrections Applied:
--
--  A. NOTES_SUMMARY POLICY
--     household_meetings.notes_summary is RESERVED and UNUSED in Phase 6B-8.
--     - create_household_meeting: p_notes_summary non-null → SQLSTATE 22023
--     - complete_household_meeting: p_notes_summary non-null → SQLSTATE 22023
--     - cancel_household_meeting: cancellation reason no longer written to notes_summary
--     - get_household_meeting_detail: notes_summary removed from return payload
--     - DB COMMENT added to household_meetings.notes_summary column
--
--  B. PRIMARY HOUSEHOLD ROSTER RULE
--     private.get_household_expected_roster now requires hm.is_primary = true.
--     Only a member's primary household counts for expected attendance.
--
--  C. ATTENDANCE COMPLETENESS SEMANTICS
--     - private.compute_attendance_summary: recorded count is now joined to
--       the expected roster (eligible members only), not the raw attendance table.
--     - Zero-member household: attendance_complete = false (not trivially true).
--     - attendance_complete = expected_count > 0 AND recorded_count = expected_count
--       where recorded_count counts only eligible-roster rows with a status.
--
--  D. ATTENDANCE RECORDING ELIGIBILITY ENFORCEMENT
--     - record_household_meeting_attendance: server-side check that each submitted
--       member_id is in the historical primary-household expected roster as of
--       meeting_date. Rejects ineligible members with SQLSTATE P0002.
--
--  E. CADENCE & MEETING OPERATIONAL STATUS
--     - New private function: private.get_household_meeting_cadence(...)
--       Returns last_completed_meeting_date, next_scheduled_meeting_date,
--       days_since_last_completed_meeting, meeting_frequency, cadence_status,
--       meeting_operational_status.
--
--  F. DASHBOARD EXTENSION
--     - get_pastoral_operations_dashboard extended with meeting_operations_summary
--       (scope-aware aggregate: upcoming_meetings, meetings_this_month,
--        attendance_pending, households_without_meeting_history,
--        households_overdue, member_follow_up_signals).
--
-- Frozen migrations (DO NOT EDIT):
--   20261002000000 — original 38 statements, members.lifecycle_status preserved
--   20261002010000 — 3 statements, record_status correction
--
-- Scope:
--   - All changes delivered via CREATE OR REPLACE FUNCTION / COMMENT ON COLUMN
--   - No DDL ALTER TABLE / DROP TABLE
--   - No data mutations
--   - No changes to permissions or role_permission grants (already correct)
-- =============================================================================

-- =============================================================================
-- SECTION A.1: Column comment — notes_summary reserved
-- =============================================================================

comment on column public.household_meetings.notes_summary is
  'RESERVED. Not in use for Phase 6B-8 public workflow. This column must NOT '
  'be used to store pastoral case notes, counseling content, marital concerns, '
  'medical details, spiritual assessments, or any confidential information. '
  'Pastoral case management is a future separate domain. The column is retained '
  'for schema compatibility only. All Phase 6B-8 write RPCs reject non-null values.';

-- =============================================================================
-- SECTION A.2: create_household_meeting — enforce notes_summary null
-- Preserves exact function signature from 020000 / 020100.
-- Adds: p_notes_summary non-null → SQLSTATE 22023
-- Uses record_status (from 020100) for facilitator/host checks.
-- =============================================================================

create or replace function public.create_household_meeting(
  p_organization_id       uuid,
  p_household_id          uuid,
  p_meeting_date          date,
  p_meeting_type          text        default 'regular_household',
  p_scheduled_start_at    timestamptz default null,
  p_scheduled_end_at      timestamptz default null,
  p_location_type         text        default null,
  p_location_text         text        default null,
  p_facilitator_member_id uuid        default null,
  p_host_member_id        uuid        default null,
  p_notes_summary         text        default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id      uuid;
  v_household_node  public.governance_nodes%rowtype;
  v_meeting_id      uuid;
  v_meeting_type    text;
  v_loc_type        text;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household meetings.';
  end if;

  select * into v_household_node
  from public.governance_nodes
  where id = p_household_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.manage', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  if p_meeting_date is null then
    raise exception using errcode = '22023', message = 'Meeting date is required.';
  end if;

  v_meeting_type := coalesce(trim(p_meeting_type), 'regular_household');
  if v_meeting_type not in (
    'regular_household', 'special_household', 'fellowship', 'formation', 'prayer', 'other'
  ) then
    raise exception using errcode = '22023',
      message = 'Invalid meeting type. Valid: regular_household, special_household, fellowship, formation, prayer, other.';
  end if;

  v_loc_type := nullif(trim(coalesce(p_location_type, '')), '');
  if v_loc_type is not null and v_loc_type not in ('in_person', 'virtual', 'hybrid') then
    raise exception using errcode = '22023',
      message = 'Invalid location type. Valid: in_person, virtual, hybrid.';
  end if;

  if p_scheduled_start_at is not null
    and p_scheduled_end_at is not null
    and p_scheduled_end_at <= p_scheduled_start_at
  then
    raise exception using errcode = '22023', message = 'Scheduled end must be after scheduled start.';
  end if;

  -- POLICY: notes_summary is reserved and unused in Phase 6B-8.
  if p_notes_summary is not null then
    raise exception using errcode = '22023',
      message = 'Free-text household meeting notes are not supported in this phase.';
  end if;

  if p_facilitator_member_id is not null then
    if not exists (
      select 1 from public.members
      where id = p_facilitator_member_id
        and organization_id = p_organization_id
        and record_status = 'active'   -- FIX: use record_status (not lifecycle_status)
    ) then
      raise exception using errcode = 'P0002',
        message = 'Facilitator member not found, not active, or not in this organization.';
    end if;
  end if;

  if p_host_member_id is not null then
    if not exists (
      select 1 from public.members
      where id = p_host_member_id
        and organization_id = p_organization_id
        and record_status = 'active'   -- FIX: use record_status (not lifecycle_status)
    ) then
      raise exception using errcode = 'P0002',
        message = 'Host member not found, not active, or not in this organization.';
    end if;
  end if;

  insert into public.household_meetings (
    organization_id,
    household_node_id,
    meeting_date,
    scheduled_start_at,
    scheduled_end_at,
    meeting_status,
    meeting_type,
    location_type,
    location_text,
    facilitator_member_id,
    host_member_id,
    -- notes_summary deliberately omitted; column stays null
    created_by_profile_id,
    updated_by_profile_id
  )
  values (
    p_organization_id,
    p_household_id,
    p_meeting_date,
    p_scheduled_start_at,
    p_scheduled_end_at,
    'scheduled',
    v_meeting_type,
    v_loc_type,
    nullif(trim(coalesce(p_location_text, '')), ''),
    p_facilitator_member_id,
    p_host_member_id,
    v_profile_id,
    v_profile_id
  )
  returning id into v_meeting_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => v_meeting_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', v_meeting_id,
      'household_node_id',    p_household_id,
      'household_node_name',  v_household_node.name,
      'meeting_date',         p_meeting_date,
      'meeting_type',         v_meeting_type
    )
  );

  return jsonb_build_object(
    'household_meeting_id', v_meeting_id,
    'household_node_id',    p_household_id,
    'meeting_date',         p_meeting_date,
    'meeting_status',       'scheduled',
    'meeting_type',         v_meeting_type
  );
end;
$$;

revoke execute on function public.create_household_meeting(uuid,uuid,date,text,timestamptz,timestamptz,text,text,uuid,uuid,text) from public, anon;
grant  execute on function public.create_household_meeting(uuid,uuid,date,text,timestamptz,timestamptz,text,text,uuid,uuid,text) to authenticated, service_role;

-- =============================================================================
-- SECTION A.3: cancel_household_meeting — stop writing cancellation reason
--              to notes_summary (column is reserved)
-- =============================================================================

create or replace function public.cancel_household_meeting(
  p_organization_id  uuid,
  p_meeting_id       uuid,
  p_reason           text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_meeting     public.household_meetings%rowtype;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household meetings.';
  end if;

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.manage', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  if v_meeting.meeting_status != 'scheduled' then
    raise exception using errcode = '23514',
      message = format('Cannot cancel a meeting in status ''%s''. Only scheduled meetings can be cancelled.', v_meeting.meeting_status);
  end if;

  -- POLICY: notes_summary is reserved. Cancellation reason is NOT persisted to notes_summary.
  update public.household_meetings
  set
    meeting_status        = 'cancelled',
    updated_at            = now(),
    updated_by_profile_id = v_profile_id
  where id = p_meeting_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.cancelled',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => p_meeting_id,
    p_action           => 'cancel',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', p_meeting_id,
      'household_node_id',    v_meeting.household_node_id,
      'meeting_date',         v_meeting.meeting_date,
      'cancellation_reason',  p_reason   -- stored in audit only, not in notes_summary
    )
  );

  return jsonb_build_object(
    'household_meeting_id', p_meeting_id,
    'meeting_status',       'cancelled'
  );
end;
$$;

revoke execute on function public.cancel_household_meeting(uuid,uuid,text) from public, anon;
grant  execute on function public.cancel_household_meeting(uuid,uuid,text) to authenticated, service_role;

-- =============================================================================
-- SECTION A.4: complete_household_meeting — enforce notes_summary null
-- =============================================================================

create or replace function public.complete_household_meeting(
  p_organization_id   uuid,
  p_meeting_id        uuid,
  p_actual_start_at   timestamptz default null,
  p_actual_end_at     timestamptz default null,
  p_notes_summary     text        default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_meeting     public.household_meetings%rowtype;
  v_summary     jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household meetings.';
  end if;

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.manage', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  if v_meeting.meeting_status != 'scheduled' then
    raise exception using errcode = '23514',
      message = format('Cannot complete a meeting in status ''%s''. Only scheduled meetings can be completed.', v_meeting.meeting_status);
  end if;

  if v_meeting.meeting_date > current_date then
    raise exception using errcode = '23514',
      message = 'Cannot complete a meeting scheduled for a future date.';
  end if;

  -- POLICY: notes_summary is reserved and unused in Phase 6B-8.
  if p_notes_summary is not null then
    raise exception using errcode = '22023',
      message = 'Free-text household meeting notes are not supported in this phase.';
  end if;

  update public.household_meetings
  set
    meeting_status        = 'completed',
    actual_start_at       = coalesce(p_actual_start_at, actual_start_at),
    actual_end_at         = coalesce(p_actual_end_at, actual_end_at),
    -- notes_summary deliberately NOT updated; column stays as-is (null)
    updated_at            = now(),
    updated_by_profile_id = v_profile_id
  where id = p_meeting_id;

  v_summary := private.compute_attendance_summary(
    p_meeting_id,
    p_organization_id,
    v_meeting.meeting_date,
    v_meeting.household_node_id
  );

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.completed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => p_meeting_id,
    p_action           => 'complete',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', p_meeting_id,
      'household_node_id',    v_meeting.household_node_id,
      'meeting_date',         v_meeting.meeting_date,
      'attendance_summary',   v_summary
    )
  );

  return jsonb_build_object(
    'household_meeting_id', p_meeting_id,
    'meeting_status',       'completed',
    'attendance_summary',   v_summary
  );
end;
$$;

revoke execute on function public.complete_household_meeting(uuid,uuid,timestamptz,timestamptz,text) from public, anon;
grant  execute on function public.complete_household_meeting(uuid,uuid,timestamptz,timestamptz,text) to authenticated, service_role;

-- =============================================================================
-- SECTION B: get_household_expected_roster — require is_primary = true
-- Canonical rule: attendance eligibility = primary household membership only.
-- Same-day transfer semantics: status filter is authoritative (ended rows excluded).
-- =============================================================================

create or replace function private.get_household_expected_roster(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_as_of_date        date
)
returns table (
  member_id       uuid,
  display_name    text,
  membership_role text
)
language sql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
  -- PRIMARY HOUSEHOLD RULE (Phase 6B-8 canonical):
  --   A member's expected household attendance is determined by their PRIMARY
  --   household membership (is_primary = true) as of the meeting date.
  --
  --   Same-day transfer semantics:
  --     ended predecessor: membership_status = 'ended' → excluded by status filter
  --     active successor:  membership_status = 'active', effective_from = transfer_date → included
  --
  --   Zero-member household: returns empty set → compute_attendance_summary returns false.
  select
    hm.member_id,
    coalesce(mn.full_name, 'Unknown Member') as display_name,
    hm.membership_role
  from public.household_memberships hm
  join public.members m
    on m.id = hm.member_id
    and m.organization_id = p_organization_id
  left join (
    select mn2.member_id, mn2.full_name
    from public.member_names mn2
    where mn2.is_primary = true
      and mn2.effective_to is null
  ) mn on mn.member_id = hm.member_id
  where hm.household_node_id = p_household_node_id
    and hm.organization_id   = p_organization_id
    and hm.is_primary        = true            -- PRIMARY HOUSEHOLD ONLY
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from    <= p_as_of_date
    and (hm.effective_to is null or hm.effective_to >= p_as_of_date)
  order by display_name;
$$;

revoke execute on function private.get_household_expected_roster(uuid, uuid, date) from public, anon;
grant  execute on function private.get_household_expected_roster(uuid, uuid, date) to authenticated, service_role;

-- =============================================================================
-- SECTION C: compute_attendance_summary — correct semantics
-- recorded_count = attendance rows joined to expected roster (eligible only)
-- zero-member household → attendance_complete = false
-- attendance_complete = expected_count > 0 AND recorded_count = expected_count
-- =============================================================================

create or replace function private.compute_attendance_summary(
  p_meeting_id        uuid,
  p_organization_id   uuid,
  p_meeting_date      date,
  p_household_node_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_expected_count  integer := 0;
  v_recorded_count  integer := 0;
  v_present_count   integer := 0;
  v_absent_count    integer := 0;
  v_excused_count   integer := 0;
  v_complete        boolean := false;
begin
  -- Expected count: primary-household eligible members as of meeting date
  select count(*) into v_expected_count
  from private.get_household_expected_roster(p_organization_id, p_household_node_id, p_meeting_date);

  -- Recorded counts: only rows for members in the expected roster
  -- This prevents ineligible attendance rows from inflating recorded_count
  -- or prematurely setting attendance_complete = true.
  select
    count(*),
    count(*) filter (where a.attendance_status = 'present'),
    count(*) filter (where a.attendance_status = 'absent'),
    count(*) filter (where a.attendance_status = 'excused')
  into v_recorded_count, v_present_count, v_absent_count, v_excused_count
  from public.household_meeting_attendance a
  where a.household_meeting_id = p_meeting_id
    and a.organization_id      = p_organization_id
    and exists (
      select 1
      from private.get_household_expected_roster(p_organization_id, p_household_node_id, p_meeting_date) r
      where r.member_id = a.member_id
    );

  -- Zero-member household → attendance_complete = false (no meaningful set to complete).
  -- Non-zero household → complete when every expected member has a recorded status.
  v_complete := (v_expected_count > 0 and v_recorded_count = v_expected_count);

  return jsonb_build_object(
    'expected_member_count',     v_expected_count,
    'recorded_attendance_count', v_recorded_count,
    'present_count',             v_present_count,
    'absent_count',              v_absent_count,
    'excused_count',             v_excused_count,
    'attendance_complete',       v_complete
  );
end;
$$;

revoke execute on function private.compute_attendance_summary(uuid, uuid, date, uuid) from public, anon;
grant  execute on function private.compute_attendance_summary(uuid, uuid, date, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION D: record_household_meeting_attendance — server-side eligibility
-- Each submitted member_id must appear in the historical primary-household roster.
-- =============================================================================

create or replace function public.record_household_meeting_attendance(
  p_organization_id  uuid,
  p_meeting_id       uuid,
  p_attendance       jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id      uuid;
  v_meeting         public.household_meetings%rowtype;
  v_item            jsonb;
  v_member_id       uuid;
  v_status          text;
  v_inserted        integer := 0;
  v_updated         integer := 0;
  v_existing_status text;
  v_any_correction  boolean := false;
  v_summary         jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.attendance.record', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to record attendance.';
  end if;

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.attendance.record', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- Future-date guard
  if v_meeting.meeting_date > current_date then
    raise exception using errcode = '23514',
      message = 'Attendance cannot be recorded for a future meeting date.';
  end if;

  if v_meeting.meeting_status = 'cancelled' then
    raise exception using errcode = '23514',
      message = 'Attendance cannot be recorded for a cancelled meeting.';
  end if;

  if p_attendance is null or jsonb_typeof(p_attendance) != 'array' then
    raise exception using errcode = '22023',
      message = 'p_attendance must be a JSON array of {member_id, attendance_status} objects.';
  end if;

  if jsonb_array_length(p_attendance) = 0 then
    raise exception using errcode = '22023',
      message = 'p_attendance array must not be empty.';
  end if;

  for v_item in select * from jsonb_array_elements(p_attendance)
  loop
    begin
      v_member_id := (v_item->>'member_id')::uuid;
    exception when others then
      raise exception using errcode = '22023',
        message = format('Invalid member_id in attendance array: %s', v_item->>'member_id');
    end;

    if v_member_id is null then
      raise exception using errcode = '22023',
        message = 'Each attendance item must include a non-null member_id.';
    end if;

    v_status := trim(v_item->>'attendance_status');
    if v_status not in ('present', 'absent', 'excused') then
      raise exception using errcode = '22023',
        message = format('Invalid attendance_status ''%s''. Valid: present, absent, excused.', v_status);
    end if;

    -- SERVER-SIDE ELIGIBILITY CHECK (Phase 6B-8 canonical):
    -- Member must appear in the historical primary-household expected roster
    -- as of the meeting date. This enforces:
    --   - is_primary = true membership requirement
    --   - membership_status in ('active', 'temporary')
    --   - date range overlap as of meeting date
    --   - same organization
    --   - correct household
    -- Rejects: cross-org members, secondary memberships, non-members,
    --          members who left before or joined after the meeting date.
    if not exists (
      select 1
      from private.get_household_expected_roster(
        p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date
      ) r
      where r.member_id = v_member_id
    ) then
      raise exception using errcode = 'P0002',
        message = format(
          'Member %s is not eligible for attendance at this meeting. '
          'Eligible members are those with an active primary household membership '
          'in this household as of %s.',
          v_member_id, v_meeting.meeting_date
        );
    end if;

    -- Check if attendance already exists (correction tracking)
    select attendance_status into v_existing_status
    from public.household_meeting_attendance
    where household_meeting_id = p_meeting_id
      and organization_id = p_organization_id
      and member_id = v_member_id;

    if found then
      update public.household_meeting_attendance
      set
        attendance_status     = v_status,
        updated_at            = now(),
        updated_by_profile_id = v_profile_id
      where household_meeting_id = p_meeting_id
        and organization_id = p_organization_id
        and member_id = v_member_id;

      v_updated := v_updated + 1;
      if v_existing_status != v_status then
        v_any_correction := true;
      end if;
    else
      insert into public.household_meeting_attendance (
        organization_id,
        household_meeting_id,
        member_id,
        attendance_status,
        recorded_at,
        recorded_by_profile_id,
        updated_at,
        updated_by_profile_id
      )
      values (
        p_organization_id,
        p_meeting_id,
        v_member_id,
        v_status,
        now(),
        v_profile_id,
        now(),
        v_profile_id
      );

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  -- Stamp attendance_recorded_at on first recording pass
  update public.household_meetings
  set
    attendance_recorded_at            = coalesce(attendance_recorded_at, now()),
    attendance_recorded_by_profile_id = coalesce(attendance_recorded_by_profile_id, v_profile_id),
    updated_at                        = now(),
    updated_by_profile_id             = v_profile_id
  where id = p_meeting_id;

  v_summary := private.compute_attendance_summary(
    p_meeting_id,
    p_organization_id,
    v_meeting.meeting_date,
    v_meeting.household_node_id
  );

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => case when v_any_correction
                               then 'household_meeting.attendance_corrected'
                               else 'household_meeting.attendance_recorded'
                          end,
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => p_meeting_id,
    p_action           => 'record_attendance',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', p_meeting_id,
      'household_node_id',    v_meeting.household_node_id,
      'meeting_date',         v_meeting.meeting_date,
      'rows_inserted',        v_inserted,
      'rows_updated',         v_updated,
      'has_correction',       v_any_correction,
      'attendance_summary',   v_summary
    )
  );

  return jsonb_build_object(
    'household_meeting_id', p_meeting_id,
    'rows_inserted',        v_inserted,
    'rows_updated',         v_updated,
    'has_correction',       v_any_correction,
    'attendance_summary',   v_summary
  );
end;
$$;

revoke execute on function public.record_household_meeting_attendance(uuid,uuid,jsonb) from public, anon;
grant  execute on function public.record_household_meeting_attendance(uuid,uuid,jsonb) to authenticated, service_role;

-- =============================================================================
-- SECTION A.5: get_household_meeting_detail — remove notes_summary from return
-- =============================================================================

create or replace function public.get_household_meeting_detail(
  p_organization_id  uuid,
  p_meeting_id       uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_meeting     public.household_meetings%rowtype;
  v_household   public.governance_nodes%rowtype;
  v_summary     jsonb;
  v_expected    jsonb;
  v_recorded    jsonb;
  v_fac_name    text;
  v_host_name   text;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household meetings.';
  end if;

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.view', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  select * into v_household from public.governance_nodes where id = v_meeting.household_node_id;

  if v_meeting.facilitator_member_id is not null then
    select full_name into v_fac_name
    from public.member_names
    where member_id = v_meeting.facilitator_member_id
      and is_primary = true
      and effective_to is null
    limit 1;
  end if;

  if v_meeting.host_member_id is not null then
    select full_name into v_host_name
    from public.member_names
    where member_id = v_meeting.host_member_id
      and is_primary = true
      and effective_to is null
    limit 1;
  end if;

  v_summary := private.compute_attendance_summary(
    p_meeting_id, p_organization_id, v_meeting.meeting_date, v_meeting.household_node_id
  );

  -- Historical expected roster: primary-household membership as of meeting_date
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'member_id',       r.member_id,
      'display_name',    r.display_name,
      'membership_role', r.membership_role
    ) order by r.display_name
  ), '[]'::jsonb)
  into v_expected
  from private.get_household_expected_roster(
    p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date
  ) r;

  -- Recorded attendance (privacy-minimized: no PII beyond display_name)
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'member_id',         a.member_id,
      'display_name',      mn.full_name,
      'attendance_status', a.attendance_status,
      'arrival_time',      a.arrival_time,
      'recorded_at',       a.recorded_at
    ) order by mn.full_name
  ), '[]'::jsonb)
  into v_recorded
  from public.household_meeting_attendance a
  left join (
    select member_id, full_name from public.member_names
    where is_primary = true and effective_to is null
  ) mn on mn.member_id = a.member_id
  where a.household_meeting_id = p_meeting_id
    and a.organization_id      = p_organization_id;

  return jsonb_build_object(
    -- Meeting identity (no notes_summary — reserved/unused in Phase 6B-8)
    'household_meeting_id',     v_meeting.id,
    'household_node_id',        v_meeting.household_node_id,
    'household_name',           v_household.name,
    'meeting_date',             v_meeting.meeting_date,
    'meeting_status',           v_meeting.meeting_status,
    'meeting_type',             v_meeting.meeting_type,
    'location_type',            v_meeting.location_type,
    'location_text',            v_meeting.location_text,
    'scheduled_start_at',       v_meeting.scheduled_start_at,
    'scheduled_end_at',         v_meeting.scheduled_end_at,
    'actual_start_at',          v_meeting.actual_start_at,
    'actual_end_at',            v_meeting.actual_end_at,
    'facilitator_member_id',    v_meeting.facilitator_member_id,
    'facilitator_display_name', v_fac_name,
    'host_member_id',           v_meeting.host_member_id,
    'host_display_name',        v_host_name,
    -- notes_summary deliberately OMITTED from return (reserved, potentially hazardous)
    'attendance_recorded_at',   v_meeting.attendance_recorded_at,
    'attendance_summary',       v_summary,
    'expected_roster',          v_expected,
    'recorded_attendance',      v_recorded,
    'created_at',               v_meeting.created_at
  );
end;
$$;

revoke execute on function public.get_household_meeting_detail(uuid,uuid) from public, anon;
grant  execute on function public.get_household_meeting_detail(uuid,uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION E: Cadence & Meeting Operational Status
-- private.get_household_meeting_cadence(...)
-- Returns factual read-only cadence data for a household.
-- No recurrence generation. Simple date arithmetic for structured frequencies.
-- =============================================================================

create or replace function private.get_household_meeting_cadence(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_meeting_frequency text  -- from households.meeting_frequency
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_last_completed_date    date;
  v_next_scheduled_date    date;
  v_days_since_last        integer;
  v_expected_next          date;
  v_cadence_status         text;
  v_meeting_op_status      text;
  v_attendance_pending     boolean := false;
begin
  -- Last completed meeting date
  select meeting_date into v_last_completed_date
  from public.household_meetings
  where household_node_id = p_household_node_id
    and organization_id   = p_organization_id
    and meeting_status    = 'completed'
  order by meeting_date desc
  limit 1;

  -- Next scheduled (future) meeting date
  select meeting_date into v_next_scheduled_date
  from public.household_meetings
  where household_node_id = p_household_node_id
    and organization_id   = p_organization_id
    and meeting_status    = 'scheduled'
    and meeting_date      >= current_date
  order by meeting_date asc
  limit 1;

  -- Days since last completed
  if v_last_completed_date is not null then
    v_days_since_last := current_date - v_last_completed_date;
  end if;

  -- Attendance pending: any completed meeting without complete attendance
  select exists (
    select 1
    from public.household_meetings hm
    where hm.household_node_id = p_household_node_id
      and hm.organization_id   = p_organization_id
      and hm.meeting_status    = 'completed'
      and hm.meeting_date      <= current_date
      and not (
        private.compute_attendance_summary(
          hm.id, p_organization_id, hm.meeting_date, p_household_node_id
        )->>'attendance_complete'
      )::boolean
    limit 1
  ) into v_attendance_pending;

  -- Cadence status & expected next date
  case p_meeting_frequency
    when 'weekly'    then v_expected_next := v_last_completed_date + interval '7 days';
    when 'biweekly'  then v_expected_next := v_last_completed_date + interval '14 days';
    when 'monthly'   then v_expected_next := v_last_completed_date + interval '1 month';
    when 'quarterly' then v_expected_next := v_last_completed_date + interval '3 months';
    else                  v_expected_next := null;   -- seasonal, variable, null
  end case;

  if p_meeting_frequency is null or p_meeting_frequency in ('seasonal', 'variable') then
    v_cadence_status := 'not_configured';
  elsif v_last_completed_date is null then
    v_cadence_status := 'no_meeting_history';
  elsif v_expected_next is not null and v_expected_next < current_date then
    v_cadence_status := 'overdue';
  else
    v_cadence_status := 'current';
  end if;

  -- Meeting operational status (separate from household operational_status)
  -- Precedence:
  --  1. attendance_pending  — completed meeting has incomplete attendance
  --  2. scheduled           — future scheduled meeting exists
  --  3. no_meeting_history  — no completed and no scheduled meeting
  --  4. overdue             — structured frequency and expected-next < today
  --  5. current             — structured frequency and expected-next >= today
  --  6. not_configured      — seasonal/variable/null
  if v_attendance_pending then
    v_meeting_op_status := 'attendance_pending';
  elsif v_next_scheduled_date is not null then
    v_meeting_op_status := 'scheduled';
  elsif v_last_completed_date is null then
    v_meeting_op_status := 'no_meeting_history';
  elsif v_cadence_status = 'overdue' then
    v_meeting_op_status := 'overdue';
  elsif v_cadence_status = 'current' then
    v_meeting_op_status := 'current';
  else
    v_meeting_op_status := 'not_configured';
  end if;

  return jsonb_build_object(
    'last_completed_meeting_date',   v_last_completed_date,
    'next_scheduled_meeting_date',   v_next_scheduled_date,
    'days_since_last_completed_meeting', v_days_since_last,
    'meeting_frequency',             p_meeting_frequency,
    'cadence_status',                v_cadence_status,
    'meeting_operational_status',    v_meeting_op_status,
    'attendance_pending',            v_attendance_pending
  );
end;
$$;

revoke execute on function private.get_household_meeting_cadence(uuid, uuid, text) from public, anon;
grant  execute on function private.get_household_meeting_cadence(uuid, uuid, text) to authenticated, service_role;

-- =============================================================================
-- SECTION F: Dashboard extension — meeting_operations_summary
-- Extends get_pastoral_operations_dashboard with scope-aware meeting metrics.
-- Uses CREATE OR REPLACE to preserve all existing output keys.
-- New key added: meeting_operations_summary
-- =============================================================================

create or replace function public.get_pastoral_operations_dashboard(
  p_organization_id    uuid,
  p_governance_node_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id             uuid;
  v_caller_member_id       uuid;
  v_caller_display_name    text;
  v_can_review_placement   boolean;
  v_can_view_leadership    boolean;
  v_can_view_roster        boolean;
  v_target_scope_node_id   uuid;
  v_identity_json          jsonb;
  v_serving_assignments    jsonb := '[]'::jsonb;
  v_pastoral_membership    jsonb := null;
  v_care_responsibilities  jsonb := '[]'::jsonb;
  v_households_summary     jsonb := '[]'::jsonb;
  v_leadership_vacancies   jsonb := '[]'::jsonb;
  v_capacity_summary       jsonb;
  v_operational_summary    jsonb;
  v_placement_summary      jsonb;
  v_unassigned_count       integer := 0;
  v_meeting_ops_summary    jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Dedicated Dashboard Permission check
  if not private.has_permission('leadership.pastoral_dashboard.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view the pastoral operations dashboard.';
  end if;

  -- 4. Scope verification if specific node supplied
  if p_governance_node_id is not null then
    if not private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, p_governance_node_id) then
      raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
    end if;
    v_target_scope_node_id := p_governance_node_id;
  end if;

  -- 5. Sub-domain permission checks for safe field filtering
  v_can_review_placement := private.has_permission('leadership.pastoral_placement.review', p_organization_id);
  v_can_view_leadership  := private.has_permission('governance.leadership.view', p_organization_id);
  v_can_view_roster      := private.has_permission('members.households.view', p_organization_id);

  -- 6. Resolve caller profile and member link (if exists)
  select pml.member_id, coalesce(m.display_name, p.display_name)
  into v_caller_member_id, v_caller_display_name
  from public.profiles p
  left join public.profile_member_links pml
    on pml.profile_id = p.id
   and pml.organization_id = p_organization_id
   and pml.is_primary = true
   and pml.link_type = 'self'
   and pml.link_status = 'verified'
   and pml.ended_at is null
  left join public.members m
    on m.id = pml.member_id
   and m.organization_id = p_organization_id
  where p.id = v_profile_id;

  if v_caller_display_name is null then
    select display_name into v_caller_display_name from public.profiles where id = v_profile_id;
  end if;

  -- 7. If linked to member, resolve Where I Serve (active formal servant roles)
  if v_caller_member_id is not null then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', la.id,
        'role_code',                lrd.code,
        'role_name',                lrd.name,
        'governance_node_id',       la.governance_node_id,
        'governance_node_name',     gn.name,
        'pastoral_level',           h.pastoral_level,
        'effective_from',           la.effective_from,
        'effective_to',             la.effective_to
      ) order by la.effective_from desc
    ), '[]'::jsonb)
    into v_serving_assignments
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join public.governance_nodes gn on gn.id = la.governance_node_id
    left join public.households h on h.id = la.governance_node_id
    where la.organization_id = p_organization_id
      and la.member_id = v_caller_member_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader');

    -- Where I Receive Pastoral Care (current primary household)
    select jsonb_build_object(
      'household_id',            h.id,
      'household_name',          gn.name,
      'pastoral_level',          h.pastoral_level,
      'scope_node_id',           p_rel.parent_node_id,
      'scope_node_name',         pn.name,
      'membership_role',         hm.membership_role,
      'effective_from',          hm.effective_from,
      'meeting_frequency',       h.meeting_frequency,
      'meeting_day_of_week',     h.meeting_day_of_week,
      'meeting_start_time',      to_char(h.meeting_start_time, 'HH24:MI:SS'),
      'meeting_timezone_name',   h.meeting_timezone_name,
      'is_fraternal',            (h.pastoral_level = 'fraternal')
    )
    into v_pastoral_membership
    from public.household_memberships hm
    join public.households h on h.id = hm.household_node_id
    join public.governance_nodes gn on gn.id = h.id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn on pn.id = p_rel.parent_node_id
    where hm.organization_id = p_organization_id
      and hm.member_id = v_caller_member_id
      and hm.is_primary = true
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    limit 1;
  end if;

  -- 8. Build Identity Block
  v_identity_json := jsonb_build_object(
    'profile_id',                          v_profile_id,
    'member_id',                           v_caller_member_id,
    'display_name',                        v_caller_display_name,
    'has_linked_member',                   (v_caller_member_id is not null),
    'serving_assignments',                 v_serving_assignments,
    'pastoral_membership',                 v_pastoral_membership,
    'pastoral_household_placement_needed', (v_caller_member_id is not null and v_pastoral_membership is null and jsonb_array_length(v_serving_assignments) > 0)
  );

  -- 9. Care Responsibilities (preserved from 20261001020000 — no changes)
  if v_caller_member_id is not null and jsonb_array_length(v_serving_assignments) > 0 then
    with caller_roles as (
      select
        (item->>'leadership_assignment_id')::uuid as assignment_id,
        item->>'role_code' as role_code,
        (item->>'governance_node_id')::uuid as node_id,
        item->>'governance_node_name' as node_name
      from jsonb_array_elements(v_serving_assignments) item
    ),
    hsl_care as (
      select
        cr.assignment_id,
        'household'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'household_members',
          'household_id', cr.node_id,
          'household_name', cr.node_name,
          'member_count', count(hm.id),
          'members', case when v_can_view_roster then coalesce(jsonb_agg(
            jsonb_build_object(
              'member_id', m.id,
              'display_name', m.display_name,
              'member_number', m.member_number,
              'membership_role', hm.membership_role,
              'effective_from', hm.effective_from
            ) order by m.display_name
          ), '[]'::jsonb) else '[]'::jsonb end
        ) as care_payload
      from caller_roles cr
      join public.households h on h.id = cr.node_id and h.pastoral_level = 'member'
      left join public.household_memberships hm
        on hm.household_node_id = cr.node_id
       and hm.organization_id = p_organization_id
       and hm.membership_status in ('active', 'temporary')
       and hm.effective_from <= current_date
       and (hm.effective_to is null or hm.effective_to >= current_date)
      left join public.members m on m.id = hm.member_id
      where cr.role_code = 'household_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    usl_care as (
      select
        cr.assignment_id,
        'unit'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'household_leaders',
          'unit_id', cr.node_id,
          'unit_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'household_id', h.id,
              'household_name', gn.name,
              'is_couple_household', h.is_couple_household,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'has_derived_spouse', (h.is_couple_household and sp.id is not null),
              'derived_spouse_name', case when h.is_couple_household then sp.display_name else null end,
              'derived_pastoral_title', case when h.is_couple_household and sp.id is not null then 'Household Leaders' else 'Household Servant Leader' end
            ) order by gn.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.households h on h.id = gnr.child_node_id and h.pastoral_level = 'member'
      join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = h.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'household_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
      where cr.role_code = 'unit_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    csl_care as (
      select
        cr.assignment_id,
        'chapter'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'unit_leaders',
          'chapter_id', cr.node_id,
          'chapter_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'unit_id', un.id,
              'unit_name', un.name,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'couples_context_status', g_guidance.couples_status,
              'has_derived_spouse', (g_guidance.couples_status = 'couples' and sp.id is not null),
              'derived_spouse_name', case when g_guidance.couples_status = 'couples' then sp.display_name else null end,
              'derived_pastoral_title', case when g_guidance.couples_status = 'couples' and sp.id is not null then 'Unit Leaders' else 'Unit Servant Leader' end
            ) order by un.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.governance_nodes un on un.id = gnr.child_node_id and un.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = un.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'unit_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select
          case
            when exists (
              select 1 from public.governance_nodes sn
              join public.governance_node_types snt on snt.id = sn.governance_node_type_id
              where sn.id = lm.primary_section_node_id and (snt.code = 'couples' or sn.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when lm.primary_section_node_id is not null then 'non_couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and (gnt_mga.code = 'couples' or gn_mga.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and gnt_mga.code in ('singles', 'youth', 'handmaids', 'servants', 'men', 'women')
            ) then 'non_couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = true
            ) then 'couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = false
            ) then 'non_couples'
            when not exists (
              select 1 from public.family_relationships fr_chk
              where (fr_chk.from_member_id = lm.id or fr_chk.to_member_id = lm.id)
                and fr_chk.organization_id = p_organization_id and fr_chk.relationship_status = 'active'
            ) then 'non_couples'
            else 'ambiguous'
          end as couples_status
      ) g_guidance on true
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
      where cr.role_code = 'chapter_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    asl_care as (
      select
        cr.assignment_id,
        'area'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'chapter_leaders',
          'area_id', cr.node_id,
          'area_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'chapter_id', chn.id,
              'chapter_name', chn.name,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'couples_context_status', g_guidance.couples_status,
              'has_derived_spouse', (g_guidance.couples_status = 'couples' and sp.id is not null),
              'derived_spouse_name', case when g_guidance.couples_status = 'couples' then sp.display_name else null end,
              'derived_pastoral_title', case when g_guidance.couples_status = 'couples' and sp.id is not null then 'Chapter Leaders' else 'Chapter Servant Leader' end
            ) order by chn.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.governance_nodes chn on chn.id = gnr.child_node_id and chn.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = chn.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'chapter_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select
          case
            when exists (
              select 1 from public.governance_nodes sn
              join public.governance_node_types snt on snt.id = sn.governance_node_type_id
              where sn.id = lm.primary_section_node_id and (snt.code = 'couples' or sn.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when lm.primary_section_node_id is not null then 'non_couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and (gnt_mga.code = 'couples' or gn_mga.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and gnt_mga.code in ('singles', 'youth', 'handmaids', 'servants', 'men', 'women')
            ) then 'non_couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = true
            ) then 'couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = false
            ) then 'non_couples'
            when not exists (
              select 1 from public.family_relationships fr_chk
              where (fr_chk.from_member_id = lm.id or fr_chk.to_member_id = lm.id)
                and fr_chk.organization_id = p_organization_id and fr_chk.relationship_status = 'active'
            ) then 'non_couples'
            else 'ambiguous'
          end as couples_status
      ) g_guidance on true
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
      where cr.role_code = 'area_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', assignment_id,
        'responsibility_level',     responsibility_level,
        'scope_id',                 scope_id,
        'scope_name',               scope_name,
        'details',                  care_payload
      )
    ), '[]'::jsonb)
    into v_care_responsibilities
    from (
      select * from hsl_care
      union all
      select * from usl_care
      union all
      select * from csl_care
      union all
      select * from asl_care
    ) u;
  end if;

  -- 10. Households Summary & Operational Calculation (unchanged from 20261001020000)
  with scoped_households as (
    select
      h.id as household_id,
      gn.name as household_name,
      h.pastoral_level,
      h.household_category,
      gn.lifecycle_status,
      h.is_couple_household,
      p_rel.parent_node_id as scope_node_id,
      pn.name as scope_node_name,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      count(hm.id) filter (
        where hm.membership_status in ('active', 'temporary')
          and hm.effective_from <= current_date
          and (hm.effective_to is null or hm.effective_to >= current_date)
      ) as member_count
    from public.households h
    join public.governance_nodes gn on gn.id = h.id and gn.organization_id = p_organization_id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn on pn.id = p_rel.parent_node_id
    left join public.household_memberships hm
      on hm.household_node_id = h.id
     and hm.organization_id = p_organization_id
    where h.organization_id = p_organization_id
      and (
        v_target_scope_node_id is null
        or h.id = v_target_scope_node_id
        or p_rel.parent_node_id = v_target_scope_node_id
        or exists (
          select 1 from public.governance_node_relationships anc
          where anc.parent_node_id = v_target_scope_node_id
            and anc.child_node_id = p_rel.parent_node_id
            and anc.organization_id = p_organization_id
            and anc.relationship_status = 'active'
        )
      )
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h.id)
    group by
      h.id, gn.name, h.pastoral_level, h.household_category, gn.lifecycle_status,
      h.is_couple_household, p_rel.parent_node_id, pn.name, h.target_member_count,
      h.maximum_member_count, h.accepts_new_members, h.meeting_frequency,
      h.meeting_day_of_week, h.meeting_start_time
  ),
  household_leaders as (
    select
      sh.household_id,
      case
        when sh.pastoral_level = 'member' then la_hh.id
        when sh.pastoral_level = 'unit' then la_scope.id
        when sh.pastoral_level = 'chapter' then la_scope.id
        when sh.pastoral_level = 'area' then la_scope.id
        else null
      end as leadership_assignment_id,
      case
        when sh.pastoral_level = 'member' then lm_hh.id
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lm_scope.id
        else null
      end as leader_member_id,
      case
        when sh.pastoral_level = 'member' then lm_hh.display_name
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lm_scope.display_name
        else null
      end as leader_name,
      case
        when sh.pastoral_level = 'member' then lrd_hh.code
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lrd_scope.code
        else null
      end as role_code,
      case
        when sh.pastoral_level = 'member' then lrd_hh.name
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lrd_scope.name
        else null
      end as role_name,
      case
        when sh.pastoral_level = 'fraternal' then null
        when sh.is_couple_household and sh.pastoral_level = 'member' and sp_hh.id is not null then sp_hh.display_name
        when sh.is_couple_household and sh.pastoral_level in ('unit', 'chapter', 'area') and sp_scope.id is not null then sp_scope.display_name
        else null
      end as derived_spouse_name
    from scoped_households sh
    left join public.leadership_assignments la_hh
      on la_hh.governance_node_id = sh.household_id
     and la_hh.organization_id = p_organization_id
     and la_hh.assignment_status = 'active'
     and la_hh.effective_from <= current_date
     and (la_hh.effective_to is null or la_hh.effective_to >= current_date)
    left join public.leadership_role_definitions lrd_hh
      on lrd_hh.id = la_hh.leadership_role_definition_id
     and lrd_hh.code = 'household_servant_leader'
    left join public.members lm_hh on lm_hh.id = la_hh.member_id
    left join lateral (
      select m_sp.id, m_sp.display_name
      from public.family_relationships fr
      join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      join public.members m_sp on m_sp.id = case when fr.from_member_id = lm_hh.id then fr.to_member_id else fr.from_member_id end
      where fr.organization_id = p_organization_id
        and (fr.from_member_id = lm_hh.id or fr.to_member_id = lm_hh.id)
        and fr.relationship_status = 'active'
        and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
        and (fr.effective_to is null or fr.effective_to >= current_date)
      limit 1
    ) sp_hh on true
    left join public.leadership_assignments la_scope
      on la_scope.governance_node_id = sh.scope_node_id
     and la_scope.organization_id = p_organization_id
     and la_scope.assignment_status = 'active'
     and la_scope.effective_from <= current_date
     and (la_scope.effective_to is null or la_scope.effective_to >= current_date)
    left join public.leadership_role_definitions lrd_scope
      on lrd_scope.id = la_scope.leadership_role_definition_id
     and lrd_scope.code in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    left join public.members lm_scope on lm_scope.id = la_scope.member_id
    left join lateral (
      select m_sp.id, m_sp.display_name
      from public.family_relationships fr
      join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      join public.members m_sp on m_sp.id = case when fr.from_member_id = lm_scope.id then fr.to_member_id else fr.from_member_id end
      where fr.organization_id = p_organization_id
        and (fr.from_member_id = lm_scope.id or fr.to_member_id = lm_scope.id)
        and fr.relationship_status = 'active'
        and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
        and (fr.effective_to is null or fr.effective_to >= current_date)
      limit 1
    ) sp_scope on true
  ),
  classified_households as (
    select
      sh.*,
      hl.leadership_assignment_id,
      hl.leader_member_id,
      hl.leader_name,
      hl.role_code as leader_role_code,
      hl.role_name as leader_role_name,
      hl.derived_spouse_name,
      case
        when sh.pastoral_level = 'fraternal' then 'not_applicable'
        when hl.leader_member_id is not null then 'assigned'
        else 'vacant'
      end as leadership_status,
      case
        when not sh.accepts_new_members then 'not_accepting'
        when sh.maximum_member_count is not null and sh.member_count >= sh.maximum_member_count then 'full'
        when sh.target_member_count is not null and sh.member_count >= sh.target_member_count then 'at_target'
        else 'available'
      end as capacity_status,
      -- FIX from 20261001020000: hl.role_name (not hl.leader_role_name)
      case
        when sh.pastoral_level = 'fraternal' then 'Rotating facilitation — no permanent formal servant leader'
        when hl.derived_spouse_name is not null then
          case sh.pastoral_level
            when 'member' then 'Household Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'unit' then 'Unit Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'chapter' then 'Chapter Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'area' then 'Area Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            else hl.leader_name || ' & ' || hl.derived_spouse_name
          end
        when hl.leader_name is not null then hl.leader_name || ' (' || coalesce(hl.role_name, 'Leader') || ')'
        else 'Vacant'
      end as leader_display_label
    from scoped_households sh
    join household_leaders hl on hl.household_id = sh.household_id
  ),
  with_operational_status as (
    select
      ch.*,
      case
        when ch.lifecycle_status != 'active' then 'inactive'
        when ch.pastoral_level != 'fraternal' and ch.leadership_status = 'vacant' then 'needs_leader'
        when ch.capacity_status = 'full' then 'at_capacity'
        when ch.capacity_status = 'not_accepting' then 'not_accepting'
        when ch.accepts_new_members and ch.target_member_count is not null and ch.member_count < ch.target_member_count then 'needs_members'
        else 'ready'
      end as operational_status
    from classified_households ch
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'household_id',            wos.household_id,
      'household_name',          wos.household_name,
      'pastoral_level',          wos.pastoral_level,
      'household_category',      wos.household_category,
      'lifecycle_status',        wos.lifecycle_status,
      'is_couple_household',     wos.is_couple_household,
      'scope_node_id',           wos.scope_node_id,
      'scope_node_name',         wos.scope_node_name,
      'formal_leader', case when wos.leader_member_id is not null then jsonb_build_object(
        'leadership_assignment_id', wos.leadership_assignment_id,
        'member_id',                wos.leader_member_id,
        'display_name',             wos.leader_name,
        'role_code',                wos.leader_role_code,
        'role_name',                wos.leader_role_name
      ) else null end,
      'derived_leader_spouse',   wos.derived_spouse_name,
      'leader_display_label',    wos.leader_display_label,
      'member_count',            wos.member_count,
      'target_member_count',     wos.target_member_count,
      'maximum_member_count',    wos.maximum_member_count,
      'accepts_new_members',     wos.accepts_new_members,
      'capacity_status',         wos.capacity_status,
      'leadership_status',       wos.leadership_status,
      'operational_status',      wos.operational_status,
      'meeting_frequency',       wos.meeting_frequency,
      'meeting_day_of_week',     wos.meeting_day_of_week,
      'meeting_start_time',      wos.meeting_start_time
    ) order by
      case wos.pastoral_level
        when 'fraternal' then 1
        when 'area' then 2
        when 'chapter' then 3
        when 'unit' then 4
        when 'member' then 5
      end,
      wos.household_name
  ), '[]'::jsonb)
  into v_households_summary
  from with_operational_status wos;

  -- 11. Capacity & Operational Aggregates
  select jsonb_build_object(
    'available',     count(*) filter (where item->>'capacity_status' = 'available'),
    'at_target',     count(*) filter (where item->>'capacity_status' = 'at_target'),
    'full',          count(*) filter (where item->>'capacity_status' = 'full'),
    'not_accepting', count(*) filter (where item->>'capacity_status' = 'not_accepting'),
    'total',         count(*)
  )
  into v_capacity_summary
  from jsonb_array_elements(v_households_summary) item;

  select jsonb_build_object(
    'ready',                     count(*) filter (where item->>'operational_status' = 'ready'),
    'needs_leader',              count(*) filter (where item->>'operational_status' = 'needs_leader'),
    'needs_members',             count(*) filter (where item->>'operational_status' = 'needs_members'),
    'at_capacity',               count(*) filter (where item->>'operational_status' = 'at_capacity'),
    'not_accepting',             count(*) filter (where item->>'operational_status' = 'not_accepting'),
    'placement_review_required', count(*) filter (where item->>'operational_status' = 'placement_review_required'),
    'inactive',                  count(*) filter (where item->>'operational_status' = 'inactive'),
    'total',                     count(*)
  )
  into v_operational_summary
  from jsonb_array_elements(v_households_summary) item;

  -- 12. Leadership Vacancies (unchanged from 20261001020000)
  with vacant_nodes as (
    select
      h_vac.id as governance_node_id,
      gn_vac.name as governance_node_name,
      'household_servant_leader'::text as role_code,
      'Household Servant Leader'::text as role_name,
      'member'::text as pastoral_level
    from public.households h_vac
    join public.governance_nodes gn_vac on gn_vac.id = h_vac.id
    where h_vac.organization_id = p_organization_id
      and h_vac.pastoral_level = 'member'
      and gn_vac.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h_vac.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = h_vac.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'household_servant_leader'
      )
    union all
    select
      un.id as governance_node_id,
      un.name as governance_node_name,
      'unit_servant_leader'::text as role_code,
      'Unit Servant Leader'::text as role_name,
      'unit'::text as pastoral_level
    from public.governance_nodes un
    join public.governance_node_types unt on unt.id = un.governance_node_type_id and unt.code = 'unit'
    where un.organization_id = p_organization_id
      and un.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, un.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = un.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'unit_servant_leader'
      )
    union all
    select
      chn.id as governance_node_id,
      chn.name as governance_node_name,
      'chapter_servant_leader'::text as role_code,
      'Chapter Servant Leader'::text as role_name,
      'chapter'::text as pastoral_level
    from public.governance_nodes chn
    join public.governance_node_types chnt on chnt.id = chn.governance_node_type_id and chnt.code = 'chapter'
    where chn.organization_id = p_organization_id
      and chn.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, chn.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = chn.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'chapter_servant_leader'
      )
    union all
    select
      arn.id as governance_node_id,
      arn.name as governance_node_name,
      'area_servant_leader'::text as role_code,
      'Area Servant Leader'::text as role_name,
      'area'::text as pastoral_level
    from public.governance_nodes arn
    join public.governance_node_types arnt on arnt.id = arn.governance_node_type_id and arnt.code = 'area_state'
    where arn.organization_id = p_organization_id
      and arn.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, arn.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = arn.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'area_servant_leader'
      )
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'governance_node_id',   vn.governance_node_id,
      'governance_node_name', vn.governance_node_name,
      'role_code',            vn.role_code,
      'role_name',            vn.role_name,
      'pastoral_level',       vn.pastoral_level,
      'vacancy_status',       'vacant'
    ) order by vn.governance_node_name
  ), '[]'::jsonb)
  into v_leadership_vacancies
  from vacant_nodes vn;

  -- 13. Placement Review Summary Integration (unchanged)
  if v_can_review_placement then
    declare
      v_search_res jsonb;
    begin
      v_search_res := public.search_servant_leaders_needing_pastoral_placement(
        p_organization_id    => p_organization_id,
        p_include_correct    => false,
        p_limit              => 100,
        p_offset             => 0
      );

      select jsonb_build_object(
        'missing_household',               count(*) filter (where item->>'placement_status' = 'missing_household'),
        'different_level',                 count(*) filter (where item->>'placement_status' = 'different_level'),
        'no_matching_household_available', count(*) filter (where item->>'placement_status' = 'no_matching_household_available'),
        'manual_review_required',          count(*) filter (where item->>'placement_status' = 'manual_review_required'),
        'total',                           coalesce(v_search_res->>'total_count', '0')::integer,
        'actionable_items',                v_search_res->'items'
      )
      into v_placement_summary
      from jsonb_array_elements(coalesce(v_search_res->'items', '[]'::jsonb)) item;

      if v_placement_summary is null then
        v_placement_summary := jsonb_build_object(
          'missing_household', 0,
          'different_level', 0,
          'no_matching_household_available', 0,
          'manual_review_required', 0,
          'total', 0,
          'actionable_items', '[]'::jsonb
        );
      end if;
    end;
  else
    v_placement_summary := jsonb_build_object(
      'missing_household', 0,
      'different_level', 0,
      'no_matching_household_available', 0,
      'manual_review_required', 0,
      'total', 0,
      'actionable_items', '[]'::jsonb
    );
  end if;

  -- 14. Unassigned Members Count (unchanged)
  select count(m.id)
  into v_unassigned_count
  from public.members m
  where m.organization_id = p_organization_id
    and m.record_status = 'active'
    and not exists (
      select 1
      from public.household_memberships hm
      where hm.member_id = m.id
        and hm.organization_id = p_organization_id
        and hm.is_primary = true
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
    )
    and (
      private.can_access_member('leadership.pastoral_dashboard.view', p_organization_id, m.id)
      or private.can_access_member('households.records.view', p_organization_id, m.id)
    );

  -- 15. Meeting Operations Summary (NEW in 020200)
  -- Scope-aware aggregate of meeting activity in caller's accessible households.
  -- No confidential content. All values are counts or dates.
  select jsonb_build_object(
    'upcoming_meetings',               count(*) filter (
                                         where hm_dash.meeting_status = 'scheduled'
                                           and hm_dash.meeting_date >= current_date
                                       ),
    'meetings_this_month',             count(*) filter (
                                         where hm_dash.meeting_status = 'completed'
                                           and date_trunc('month', hm_dash.meeting_date) = date_trunc('month', current_date)
                                       ),
    'attendance_pending',              count(*) filter (
                                         where hm_dash.meeting_status = 'completed'
                                           and not (
                                             private.compute_attendance_summary(
                                               hm_dash.id,
                                               p_organization_id,
                                               hm_dash.meeting_date,
                                               hm_dash.household_node_id
                                             )->>'attendance_complete'
                                           )::boolean
                                       ),
    'households_without_meeting_history', (
      select count(distinct h_no_mtg.id)
      from public.households h_no_mtg
      join public.governance_nodes gn_no_mtg on gn_no_mtg.id = h_no_mtg.id
      where h_no_mtg.organization_id = p_organization_id
        and gn_no_mtg.lifecycle_status = 'active'
        and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h_no_mtg.id)
        and not exists (
          select 1 from public.household_meetings hm_ex
          where hm_ex.household_node_id = h_no_mtg.id
            and hm_ex.organization_id   = p_organization_id
            and hm_ex.meeting_status    = 'completed'
        )
    ),
    'households_overdue',              (
      -- Households with structured meeting_frequency where expected-next-date < today
      select count(distinct h_od.id)
      from public.households h_od
      join public.governance_nodes gn_od on gn_od.id = h_od.id
      where h_od.organization_id = p_organization_id
        and gn_od.lifecycle_status = 'active'
        and h_od.meeting_frequency in ('weekly', 'biweekly', 'monthly', 'quarterly')
        and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h_od.id)
        and exists (
          -- Has at least one completed meeting
          select 1 from public.household_meetings hm_od_chk
          where hm_od_chk.household_node_id = h_od.id
            and hm_od_chk.organization_id   = p_organization_id
            and hm_od_chk.meeting_status    = 'completed'
        )
        and (
          select
            case h_od.meeting_frequency
              when 'weekly'    then max(hm_od.meeting_date) + interval '7 days'
              when 'biweekly'  then max(hm_od.meeting_date) + interval '14 days'
              when 'monthly'   then max(hm_od.meeting_date) + interval '1 month'
              when 'quarterly' then max(hm_od.meeting_date) + interval '3 months'
            end < current_date
          from public.household_meetings hm_od
          where hm_od.household_node_id = h_od.id
            and hm_od.organization_id   = p_organization_id
            and hm_od.meeting_status    = 'completed'
        )
    ),
    'member_follow_up_signals',        (
      -- Count of distinct members with multiple_recent_absences = true
      -- Avoids N+1 by using inline aggregation over accessible primary memberships
      select count(distinct hm_fu.member_id)
      from public.household_memberships hm_fu
      join public.households h_fu on h_fu.id = hm_fu.household_node_id
      where hm_fu.organization_id   = p_organization_id
        and hm_fu.is_primary        = true
        and hm_fu.membership_status in ('active', 'temporary')
        and hm_fu.effective_from    <= current_date
        and (hm_fu.effective_to is null or hm_fu.effective_to >= current_date)
        and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, hm_fu.household_node_id)
        and (
          private.get_member_follow_up_signals(
            p_organization_id, hm_fu.member_id, hm_fu.household_node_id
          )->>'multiple_recent_absences'
        )::boolean = true
    )
  )
  into v_meeting_ops_summary
  from public.household_meetings hm_dash
  where hm_dash.organization_id = p_organization_id
    and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, hm_dash.household_node_id);

  -- 16. Return Unified Operational Dashboard Payload (extended with meeting_operations_summary)
  return jsonb_build_object(
    'organization_id',           p_organization_id,
    'identity',                  v_identity_json,
    'care_responsibilities',     v_care_responsibilities,
    'household_summary',         v_households_summary,
    'leadership_vacancies',      v_leadership_vacancies,
    'capacity_summary',          v_capacity_summary,
    'operational_summary',       v_operational_summary,
    'placement_review_summary',  v_placement_summary,
    'unassigned_members_count',  coalesce(v_unassigned_count, 0),
    'meeting_operations_summary', coalesce(v_meeting_ops_summary, jsonb_build_object(
      'upcoming_meetings',                  0,
      'meetings_this_month',                0,
      'attendance_pending',                 0,
      'households_without_meeting_history', 0,
      'households_overdue',                 0,
      'member_follow_up_signals',           0
    ))
  );
end;
$$;

revoke all on function public.get_pastoral_operations_dashboard(uuid, uuid) from public, anon;
grant execute on function public.get_pastoral_operations_dashboard(uuid, uuid) to authenticated, service_role;

comment on function public.get_pastoral_operations_dashboard(uuid, uuid) is
  'Read-only operational dashboard. Phase 6B-8 extension (020200): added meeting_operations_summary '
  'block (upcoming_meetings, meetings_this_month, attendance_pending, households_without_meeting_history, '
  'households_overdue, member_follow_up_signals). All scope-aware. No confidential content.';

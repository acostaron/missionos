-- =============================================================================
-- Migration: 20261010085000_household_card_meetings_attendance.sql
-- MissionOS Pass 9.9 (written by Claude, 2026-10-16)
-- Ron: make the household card in My Events the one place where servant leaders run their household.
-- Ron's decisions (2026-10-16):
--   * Who manages from the card: the same people who can change topics (private.member_can_edit_household_topics):
--     the household's servant leaders, their spouse in couple leadership, organization administrators, and any
--     active member of a Fraternal household.
--   * What ordinary members see about attendance: only their own status.
--   * Card actions: schedule a meeting, edit / reschedule, cancel, mark completed, record attendance.
-- Attendance roster on the card:
--   * regular households: the existing primary-household expected roster (private.get_household_expected_roster);
--   * Fraternal households: every active / temporary member of the Fraternal household (members belong to a
--     Fraternal household in addition to their own household).
-- Privacy: no free-text notes; cancel takes no reason text; hosts are chosen from the household roster only.
-- Existing leader-workspace RPCs are NOT changed. public.list_my_household_topics is replaced (guarded).
-- =============================================================================
do $guard$
declare
  v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'list_my_household_topics';
  if v_md5 is distinct from '932b4028922e76c906b7c1402203e676' then
    raise exception 'STOP: public.list_my_household_topics differs from 20261010084000 (md5 %).', v_md5;
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- 1. Card roster and attendance summary
-- -----------------------------------------------------------------------------
create or replace function private.household_card_roster(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_as_of_date        date
)
returns table (member_id uuid, display_name text)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select r.member_id, r.display_name
  from private.get_household_expected_roster(p_organization_id, p_household_node_id, p_as_of_date) r
  where not exists (select 1 from public.households h
                    where h.id = p_household_node_id and h.pastoral_level = 'fraternal')
  union
  select hm.member_id, coalesce(mn.full_name, 'Unknown Member')
  from public.households h
  join public.household_memberships hm
    on hm.household_node_id = h.id and hm.organization_id = h.organization_id
  join public.members m on m.id = hm.member_id and m.organization_id = p_organization_id
  left join public.member_names mn
    on mn.member_id = hm.member_id and mn.is_primary = true and mn.effective_to is null
  where h.id = p_household_node_id
    and h.organization_id = p_organization_id
    and h.pastoral_level = 'fraternal'
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= p_as_of_date
    and (hm.effective_to is null or hm.effective_to >= p_as_of_date)
$$;
revoke all on function private.household_card_roster(uuid, uuid, date) from public, anon, authenticated;

create or replace function private.household_card_attendance_summary(
  p_organization_id uuid,
  p_meeting_id      uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_meeting  public.household_meetings%rowtype;
  v_expected integer := 0;
  v_recorded integer := 0;
  v_present  integer := 0;
  v_absent   integer := 0;
  v_excused  integer := 0;
begin
  select * into v_meeting from public.household_meetings
  where id = p_meeting_id and organization_id = p_organization_id;
  if not found then
    return null;
  end if;

  select count(*) into v_expected
  from private.household_card_roster(p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date);

  select count(*),
         count(*) filter (where a.attendance_status = 'present'),
         count(*) filter (where a.attendance_status = 'absent'),
         count(*) filter (where a.attendance_status = 'excused')
    into v_recorded, v_present, v_absent, v_excused
  from public.household_meeting_attendance a
  where a.household_meeting_id = p_meeting_id
    and a.organization_id = p_organization_id
    and exists (select 1 from private.household_card_roster(p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date) r
                where r.member_id = a.member_id);

  return jsonb_build_object(
    'expected_member_count',     v_expected,
    'recorded_attendance_count', v_recorded,
    'present_count',             v_present,
    'absent_count',              v_absent,
    'excused_count',             v_excused,
    'attendance_complete',       v_expected > 0 and v_recorded = v_expected);
end;
$$;
revoke all on function private.household_card_attendance_summary(uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Permission checks (same rule as household topics)
-- -----------------------------------------------------------------------------
create or replace function private.assert_member_can_manage_household(p_organization_id uuid, p_household_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  if not exists (select 1 from public.households h
                 join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
                 where h.id = p_household_id and h.organization_id = p_organization_id) then
    raise exception using errcode = 'P0002', message = 'Household not found.';
  end if;
  if not private.member_can_edit_household_topics(p_organization_id, v_member_id, private.current_profile_id(), p_household_id) then
    raise exception using errcode = '42501', message = 'Only this household''s servant leaders can manage its meetings.';
  end if;
  return v_member_id;
end;
$$;
revoke all on function private.assert_member_can_manage_household(uuid, uuid) from public, anon, authenticated;

create or replace function private.household_card_check_meeting_fields(
  p_organization_id    uuid,
  p_household_id       uuid,
  p_meeting_date       date,
  p_location_type      text,
  p_location_text      text,
  p_host_member_id     uuid
)
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if p_meeting_date is null then
    raise exception using errcode = '22023', message = 'Meeting date is required.';
  end if;
  if p_meeting_date < current_date - 30 or p_meeting_date > current_date + 90 then
    raise exception using errcode = '22023', message = 'Choose a date from the last 30 days up to 90 days ahead.';
  end if;
  if p_location_type is not null and p_location_type not in ('in_person', 'virtual', 'hybrid') then
    raise exception using errcode = '22023', message = 'Invalid location type. Valid: in_person, virtual, hybrid.';
  end if;
  if p_location_text is not null and length(p_location_text) > 200 then
    raise exception using errcode = '22023', message = 'Location is too long (200 characters at most).';
  end if;
  if p_host_member_id is not null and not exists (
       select 1 from private.household_card_roster(p_organization_id, p_household_id, p_meeting_date) r
       where r.member_id = p_host_member_id) then
    raise exception using errcode = '22023', message = 'The host must be a member of this household.';
  end if;
end;
$$;
revoke all on function private.household_card_check_meeting_fields(uuid, uuid, date, text, text, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Schedule / edit / cancel / complete
-- -----------------------------------------------------------------------------
create or replace function public.member_schedule_household_meeting(
  p_organization_id    uuid,
  p_household_id       uuid,
  p_meeting_date       date,
  p_scheduled_start_at timestamptz default null,
  p_location_type      text default null,
  p_location_text      text default null,
  p_host_member_id     uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile_id uuid;
  v_loc_type   text := nullif(trim(coalesce(p_location_type, '')), '');
  v_loc_text   text := nullif(trim(coalesce(p_location_text, '')), '');
  v_id         uuid;
begin
  perform private.assert_member_can_manage_household(p_organization_id, p_household_id);
  v_profile_id := private.current_profile_id();
  perform private.household_card_check_meeting_fields(
    p_organization_id, p_household_id, p_meeting_date, v_loc_type, v_loc_text, p_host_member_id);

  if exists (select 1 from public.household_meetings m
             where m.organization_id = p_organization_id and m.household_node_id = p_household_id
               and m.meeting_date = p_meeting_date and m.meeting_status in ('scheduled', 'completed')) then
    raise exception using errcode = '23505', message = 'This household already has a meeting on that date.';
  end if;

  insert into public.household_meetings (
    organization_id, household_node_id, meeting_date, scheduled_start_at, meeting_status, meeting_type,
    location_type, location_text, host_member_id, created_by_profile_id, updated_by_profile_id)
  values (
    p_organization_id, p_household_id, p_meeting_date, p_scheduled_start_at, 'scheduled', 'regular_household',
    v_loc_type, v_loc_text, p_host_member_id, v_profile_id, v_profile_id)
  returning id into v_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => v_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => 'household_card',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', v_id, 'household_node_id', p_household_id,
      'meeting_date', p_meeting_date, 'source', 'household_card'));

  return jsonb_build_object('household_meeting_id', v_id, 'meeting_date', p_meeting_date, 'meeting_status', 'scheduled');
end;
$$;
revoke all on function public.member_schedule_household_meeting(uuid, uuid, date, timestamptz, text, text, uuid) from public, anon;
grant execute on function public.member_schedule_household_meeting(uuid, uuid, date, timestamptz, text, text, uuid) to authenticated;

create or replace function public.member_update_household_meeting(
  p_organization_id    uuid,
  p_meeting_id         uuid,
  p_meeting_date       date,
  p_scheduled_start_at timestamptz default null,
  p_location_type      text default null,
  p_location_text      text default null,
  p_host_member_id     uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile_id uuid;
  v_meeting    public.household_meetings%rowtype;
  v_loc_type   text := nullif(trim(coalesce(p_location_type, '')), '');
  v_loc_text   text := nullif(trim(coalesce(p_location_text, '')), '');
begin
  select * into v_meeting from public.household_meetings
  where id = p_meeting_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;
  perform private.assert_member_can_manage_household(p_organization_id, v_meeting.household_node_id);
  v_profile_id := private.current_profile_id();

  if v_meeting.meeting_status <> 'scheduled' then
    raise exception using errcode = '23514', message = 'Only a scheduled meeting can be changed.';
  end if;
  perform private.household_card_check_meeting_fields(
    p_organization_id, v_meeting.household_node_id, p_meeting_date, v_loc_type, v_loc_text, p_host_member_id);
  if p_meeting_date <> v_meeting.meeting_date and exists (
       select 1 from public.household_meetings m
       where m.organization_id = p_organization_id and m.household_node_id = v_meeting.household_node_id
         and m.id <> v_meeting.id and m.meeting_date = p_meeting_date
         and m.meeting_status in ('scheduled', 'completed')) then
    raise exception using errcode = '23505', message = 'This household already has a meeting on that date.';
  end if;

  update public.household_meetings
     set meeting_date          = p_meeting_date,
         scheduled_start_at    = p_scheduled_start_at,
         scheduled_end_at      = case when p_scheduled_start_at is not null and scheduled_end_at > p_scheduled_start_at
                                      then scheduled_end_at end,
         location_type         = v_loc_type,
         location_text         = v_loc_text,
         host_member_id        = p_host_member_id,
         updated_at            = now(),
         updated_by_profile_id = v_profile_id
   where id = v_meeting.id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.updated',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => v_meeting.id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => 'household_card',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', v_meeting.id, 'household_node_id', v_meeting.household_node_id,
      'old_meeting_date', v_meeting.meeting_date, 'new_meeting_date', p_meeting_date,
      'source', 'household_card'));

  return jsonb_build_object('household_meeting_id', v_meeting.id, 'meeting_date', p_meeting_date);
end;
$$;
revoke all on function public.member_update_household_meeting(uuid, uuid, date, timestamptz, text, text, uuid) from public, anon;
grant execute on function public.member_update_household_meeting(uuid, uuid, date, timestamptz, text, text, uuid) to authenticated;

create or replace function public.member_set_household_meeting_status(
  p_organization_id uuid,
  p_meeting_id      uuid,
  p_new_status      text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile_id uuid;
  v_meeting    public.household_meetings%rowtype;
begin
  if p_new_status is null or p_new_status not in ('completed', 'cancelled') then
    raise exception using errcode = '22023', message = 'Status must be completed or cancelled.';
  end if;
  select * into v_meeting from public.household_meetings
  where id = p_meeting_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;
  perform private.assert_member_can_manage_household(p_organization_id, v_meeting.household_node_id);
  v_profile_id := private.current_profile_id();

  if v_meeting.meeting_status <> 'scheduled' then
    raise exception using errcode = '23514', message = 'Only a scheduled meeting can be completed or cancelled.';
  end if;
  if p_new_status = 'completed' and v_meeting.meeting_date > current_date then
    raise exception using errcode = '23514', message = 'A meeting can be marked completed on or after its date.';
  end if;

  -- trg_household_meetings_sync_topics completes (or unlinks) the planned topics
  update public.household_meetings
     set meeting_status        = p_new_status,
         updated_at            = now(),
         updated_by_profile_id = v_profile_id
   where id = v_meeting.id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => case p_new_status when 'completed' then 'household_meeting.completed'
                                            else 'household_meeting.cancelled' end,
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => v_meeting.id,
    p_action           => case p_new_status when 'completed' then 'complete' else 'cancel' end,
    p_outcome          => 'success',
    p_access_reason    => 'household_card',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', v_meeting.id, 'household_node_id', v_meeting.household_node_id,
      'meeting_date', v_meeting.meeting_date, 'source', 'household_card'));

  return jsonb_build_object('household_meeting_id', v_meeting.id, 'meeting_status', p_new_status);
end;
$$;
revoke all on function public.member_set_household_meeting_status(uuid, uuid, text) from public, anon;
grant execute on function public.member_set_household_meeting_status(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Roster (for the host picker) and attendance
-- -----------------------------------------------------------------------------
create or replace function public.member_household_roster(p_organization_id uuid, p_household_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  perform private.assert_member_can_manage_household(p_organization_id, p_household_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object('member_id', r.member_id, 'display_name', r.display_name)
                     order by r.display_name)
    from private.household_card_roster(p_organization_id, p_household_id, current_date) r), '[]'::jsonb);
end;
$$;
revoke all on function public.member_household_roster(uuid, uuid) from public, anon;
grant execute on function public.member_household_roster(uuid, uuid) to authenticated;

create or replace function public.member_get_household_attendance(p_organization_id uuid, p_meeting_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_meeting public.household_meetings%rowtype;
begin
  select * into v_meeting from public.household_meetings
  where id = p_meeting_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;
  perform private.assert_member_can_manage_household(p_organization_id, v_meeting.household_node_id);

  return jsonb_build_object(
    'household_meeting_id', v_meeting.id,
    'meeting_date',         v_meeting.meeting_date,
    'meeting_status',       v_meeting.meeting_status,
    'summary',              private.household_card_attendance_summary(p_organization_id, v_meeting.id),
    'roster', coalesce((
      select jsonb_agg(jsonb_build_object(
               'member_id',         r.member_id,
               'display_name',      r.display_name,
               'attendance_status', a.attendance_status)
             order by r.display_name)
      from private.household_card_roster(p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date) r
      left join public.household_meeting_attendance a
        on a.household_meeting_id = v_meeting.id and a.organization_id = p_organization_id
       and a.member_id = r.member_id), '[]'::jsonb));
end;
$$;
revoke all on function public.member_get_household_attendance(uuid, uuid) from public, anon;
grant execute on function public.member_get_household_attendance(uuid, uuid) to authenticated;

create or replace function public.member_record_household_attendance(
  p_organization_id  uuid,
  p_meeting_id       uuid,
  p_attendance       jsonb,
  p_complete_meeting boolean default true
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile_id uuid;
  v_meeting    public.household_meetings%rowtype;
  v_item       jsonb;
  v_member_id  uuid;
  v_status     text;
  v_existing   text;
  v_inserted   integer := 0;
  v_updated    integer := 0;
  v_correction boolean := false;
  v_completed  boolean := false;
  v_summary    jsonb;
begin
  select * into v_meeting from public.household_meetings
  where id = p_meeting_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;
  perform private.assert_member_can_manage_household(p_organization_id, v_meeting.household_node_id);
  v_profile_id := private.current_profile_id();

  if v_meeting.meeting_date > current_date then
    raise exception using errcode = '23514', message = 'Attendance cannot be recorded before the meeting date.';
  end if;
  if v_meeting.meeting_status = 'cancelled' then
    raise exception using errcode = '23514', message = 'Attendance cannot be recorded for a cancelled meeting.';
  end if;
  if p_attendance is null or jsonb_typeof(p_attendance) <> 'array' or jsonb_array_length(p_attendance) = 0 then
    raise exception using errcode = '22023', message = 'Mark at least one member.';
  end if;

  for v_item in select * from jsonb_array_elements(p_attendance)
  loop
    begin
      v_member_id := (v_item->>'member_id')::uuid;
    exception when others then
      raise exception using errcode = '22023', message = 'Invalid member in the attendance list.';
    end;
    v_status := trim(v_item->>'attendance_status');
    if v_member_id is null or v_status is null or v_status not in ('present', 'absent', 'excused') then
      raise exception using errcode = '22023', message = 'Each member must be marked present, absent or excused.';
    end if;
    if not exists (select 1 from private.household_card_roster(p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date) r
                   where r.member_id = v_member_id) then
      raise exception using errcode = 'P0002', message = 'A member in the list is not part of this household on the meeting date.';
    end if;

    select a.attendance_status into v_existing
    from public.household_meeting_attendance a
    where a.household_meeting_id = v_meeting.id and a.organization_id = p_organization_id and a.member_id = v_member_id;

    if found then
      update public.household_meeting_attendance
         set attendance_status = v_status, updated_at = now(), updated_by_profile_id = v_profile_id
       where household_meeting_id = v_meeting.id and organization_id = p_organization_id and member_id = v_member_id;
      v_updated := v_updated + 1;
      if v_existing <> v_status then
        v_correction := true;
      end if;
    else
      insert into public.household_meeting_attendance (
        organization_id, household_meeting_id, member_id, attendance_status,
        recorded_at, recorded_by_profile_id, updated_at, updated_by_profile_id)
      values (p_organization_id, v_meeting.id, v_member_id, v_status, now(), v_profile_id, now(), v_profile_id);
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  update public.household_meetings
     set attendance_recorded_at            = coalesce(attendance_recorded_at, now()),
         attendance_recorded_by_profile_id = coalesce(attendance_recorded_by_profile_id, v_profile_id),
         meeting_status                    = case when coalesce(p_complete_meeting, true) and meeting_status = 'scheduled'
                                                  then 'completed' else meeting_status end,
         updated_at                        = now(),
         updated_by_profile_id             = v_profile_id
   where id = v_meeting.id;
  v_completed := coalesce(p_complete_meeting, true) and v_meeting.meeting_status = 'scheduled';

  v_summary := private.household_card_attendance_summary(p_organization_id, v_meeting.id);

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => case when v_correction then 'household_meeting.attendance_corrected'
                               else 'household_meeting.attendance_recorded' end,
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => v_meeting.id,
    p_action           => 'record_attendance',
    p_outcome          => 'success',
    p_access_reason    => 'household_card',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', v_meeting.id, 'household_node_id', v_meeting.household_node_id,
      'meeting_date', v_meeting.meeting_date, 'rows_inserted', v_inserted, 'rows_updated', v_updated,
      'has_correction', v_correction, 'meeting_completed', v_completed,
      'attendance_summary', v_summary, 'source', 'household_card'));

  if v_completed then
    perform private.write_audit_event(
      p_organization_id  => p_organization_id,
      p_event_code       => 'household_meeting.completed',
      p_event_category   => 'governance',
      p_actor_profile_id => v_profile_id,
      p_entity_type      => 'household_meeting',
      p_entity_id        => v_meeting.id,
      p_action           => 'complete',
      p_outcome          => 'success',
      p_access_reason    => 'household_card',
      p_correlation_id   => null,
      p_metadata         => jsonb_build_object(
        'household_meeting_id', v_meeting.id, 'household_node_id', v_meeting.household_node_id,
        'meeting_date', v_meeting.meeting_date, 'source', 'household_card'));
  end if;

  return jsonb_build_object(
    'household_meeting_id', v_meeting.id,
    'rows_inserted',        v_inserted,
    'rows_updated',         v_updated,
    'meeting_completed',    v_completed,
    'summary',              v_summary);
end;
$$;
revoke all on function public.member_record_household_attendance(uuid, uuid, jsonb, boolean) from public, anon;
grant execute on function public.member_record_household_attendance(uuid, uuid, jsonb, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. The card's data: + host_member_id, my_attendance (own status only),
--    attendance_summary (only for those who can manage the household)
-- -----------------------------------------------------------------------------
create or replace function public.list_my_household_topics(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id  uuid;
  v_profile_id uuid;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  v_profile_id := private.current_profile_id();

  return coalesce((
    with my_hh as (
      select hm.household_node_id as household_id
      from public.household_memberships hm
      where hm.organization_id = p_organization_id
        and hm.member_id = v_member_id
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
      union
      select l.household_id from private.member_led_household_ids(p_organization_id, v_member_id) l
    ),
    hh as (
      select h.id, h.pastoral_level, gn.name,
             private.member_can_edit_household_topics(p_organization_id, v_member_id, v_profile_id, h.id) as can_edit
      from my_hh
      join public.households h on h.id = my_hh.household_id and h.organization_id = p_organization_id
      join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
    )
    select jsonb_agg(jsonb_build_object(
             'household_id',   hh.id,
             'household_name', hh.name,
             'pastoral_level', hh.pastoral_level,
             'can_edit',       hh.can_edit,
             'meetings', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'household_meeting_id', mt.id,
                        'meeting_date',         mt.meeting_date,
                        'scheduled_start_at',   mt.scheduled_start_at,
                        'meeting_status',       mt.meeting_status,
                        'location_type',        mt.location_type,
                        'location_text',        mt.location_text,
                        'host_member_id',       mt.host_member_id,
                        'host_name',            host_m.display_name,
                        'my_attendance', (
                          select a.attendance_status from public.household_meeting_attendance a
                          where a.household_meeting_id = mt.id and a.organization_id = p_organization_id
                            and a.member_id = v_member_id),
                        'attendance_summary', case when hh.can_edit and mt.meeting_status <> 'cancelled'
                                                   then private.household_card_attendance_summary(p_organization_id, mt.id) end,
                        'topics', coalesce((
                          select jsonb_agg(jsonb_build_object(
                                   'assignment_id',      a.id,
                                   'topic_id',           a.topic_id,
                                   'title',              ft.title,
                                   'is_library_topic',   ft.series_code is not null,
                                   'assignment_status',  a.assignment_status,
                                   'change_reason_code', a.change_reason_code,
                                   'replaced_by_title',  coalesce(rb_ft.title, a.used_topic_title),
                                   'replaces_title',     rp_ft.title)
                                 order by a.assignment_status, ft.title)
                          from public.household_topic_assignments a
                          join public.formation_topics ft on ft.id = a.topic_id
                          left join public.household_topic_assignments rb on rb.id = a.replaced_by_assignment_id
                          left join public.formation_topics rb_ft on rb_ft.id = rb.topic_id
                          left join public.household_topic_assignments rp on rp.id = a.replaces_assignment_id
                          left join public.formation_topics rp_ft on rp_ft.id = rp.topic_id
                          where coalesce(a.completed_household_meeting_id, a.planned_household_meeting_id) = mt.id
                            and a.assignment_status in ('planned', 'completed', 'skipped')), '[]'::jsonb))
                      order by mt.meeting_date, mt.scheduled_start_at nulls last)
               from public.household_meetings mt
               left join public.members host_m
                 on host_m.id = mt.host_member_id and host_m.organization_id = mt.organization_id
               where mt.organization_id = p_organization_id
                 and mt.household_node_id = hh.id
                 and (mt.meeting_status in ('scheduled', 'completed')
                      or (mt.meeting_status = 'cancelled' and mt.meeting_date >= current_date))
                 and mt.meeting_date between current_date - 30 and current_date + 90), '[]'::jsonb))
           order by hh.name)
    from hh
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_household_topics(uuid) from public, anon;
grant execute on function public.list_my_household_topics(uuid) to authenticated;

-- =============================================================================
-- Migration: 20261002000000_phase_6b_household_meetings_attendance.sql
-- Phase:     Phase 6B-8 — Household Meetings, Attendance & Pastoral Follow-up
--
-- Authoritative Architecture:
--   1. New Permissions (3):
--        households.meetings.view      – read meeting history and detail
--        households.meetings.manage    – schedule, cancel, complete meetings
--        households.attendance.record  – record and correct attendance
--      All granted initially to organization_administrator only.
--
--   2. New Tables:
--        public.household_meetings         – one row per scheduled/completed meeting
--        public.household_meeting_attendance – one row per (meeting, member)
--
--   3. Meeting Status Vocabulary:
--        scheduled | completed | cancelled
--
--   4. Meeting Type Vocabulary:
--        regular_household | special_household | fellowship | formation | prayer | other
--
--   5. Attendance Status Vocabulary:
--        present | absent | excused
--
--   6. Public RPCs:
--        create_household_meeting(...)
--        cancel_household_meeting(...)
--        complete_household_meeting(...)
--        record_household_meeting_attendance(...)
--        get_household_meeting_history(...)
--        get_household_meeting_detail(...)
--
--   7. Historical Roster Semantics:
--      Expected attendance derived from household_memberships where
--        membership_status IN ('active','temporary')
--        AND effective_from <= meeting_date
--        AND (effective_to IS NULL OR effective_to >= meeting_date)
--      Never relies on members.primary_household_node_id alone.
--
--   8. Facilitator Model:
--      facilitator_member_id is purely operational.
--      Does NOT create leadership_assignments.
--      Especially important for Fraternal rotating facilitation.
--
--   9. Follow-up Signal:
--      multiple_recent_absences = 2+ absences in last 3 completed meetings.
--      excused does NOT count as absent. Threshold hardcoded, clearly documented.
--
--  10. Privacy:
--      No freeform pastoral notes beyond 1000-char operational summary.
--      No emails, phones, addresses, financial or confidential fields exposed.
--
--  11. Security:
--      All RPCs SECURITY DEFINER with fixed search_path.
--      Future attendance guard: meeting_date > current_date blocked.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Permissions Catalog & Role Permissions
-- =============================================================================

insert into public.permissions (
  code,
  name,
  description,
  domain_code,
  action_code,
  scope_type,
  risk_level,
  requires_access_reason,
  requires_access_logging,
  is_active
)
values
  (
    'households.meetings.view',
    'View household meeting history',
    'View scheduled meetings, meeting history, attendance summaries, and facilitator information for pastoral households.',
    'households',
    'view',
    'governance',
    'standard',
    false,
    false,
    true
  ),
  (
    'households.meetings.manage',
    'Manage household meetings',
    'Schedule, cancel, and complete pastoral household meetings.',
    'households',
    'manage',
    'governance',
    'standard',
    false,
    false,
    true
  ),
  (
    'households.attendance.record',
    'Record household meeting attendance',
    'Record and correct attendance for pastoral household meetings.',
    'households',
    'record',
    'governance',
    'standard',
    false,
    false,
    true
  )
on conflict (code) do update
set
  name                    = excluded.name,
  description             = excluded.description,
  domain_code             = excluded.domain_code,
  action_code             = excluded.action_code,
  scope_type              = excluded.scope_type,
  risk_level              = excluded.risk_level,
  requires_access_reason  = excluded.requires_access_reason,
  requires_access_logging = excluded.requires_access_logging,
  is_active               = excluded.is_active;

-- Grant all three permissions to organization_administrator (null-safe, no duplicates)
insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  effective_from_at,
  effective_to_at,
  approval_status,
  approved_at,
  created_at,
  updated_at
)
select
  r.organization_id,
  r.id as app_role_id,
  p.id as permission_id,
  'allow',
  now(),
  null,
  'approved',
  now(),
  now(),
  now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and p.code in (
    'households.meetings.view',
    'households.meetings.manage',
    'households.attendance.record'
  )
  and not exists (
    select 1
    from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and (
        rp.organization_id = r.organization_id
        or (rp.organization_id is null and r.organization_id is null)
      )
  );

-- =============================================================================
-- SECTION 2: household_meetings Table
-- =============================================================================

create table public.household_meetings (
  id                            uuid        not null default gen_random_uuid(),
  organization_id               uuid        not null,
  household_node_id             uuid        not null,

  meeting_date                  date        not null,
  scheduled_start_at            timestamptz,
  scheduled_end_at              timestamptz,
  actual_start_at               timestamptz,
  actual_end_at                 timestamptz,

  meeting_status                text        not null default 'scheduled',
  meeting_type                  text        not null default 'regular_household',

  location_type                 text,
  location_text                 text,

  facilitator_member_id         uuid,
  host_member_id                uuid,

  attendance_recorded_at        timestamptz,
  attendance_recorded_by_profile_id uuid,

  -- Non-confidential operational summary only (max 1000 chars)
  notes_summary                 text        check (notes_summary is null or length(trim(notes_summary)) <= 1000),

  created_at                    timestamptz not null default now(),
  created_by_profile_id         uuid,
  updated_at                    timestamptz not null default now(),
  updated_by_profile_id         uuid,

  constraint pk_household_meetings
    primary key (id),

  constraint fk_household_meetings__organization
    foreign key (organization_id)
    references public.organizations(id)
    on delete restrict,

  constraint fk_household_meetings__household_node
    foreign key (household_node_id)
    references public.governance_nodes(id)
    on delete restrict,

  constraint fk_household_meetings__facilitator
    foreign key (facilitator_member_id)
    references public.members(id)
    on delete set null,

  constraint fk_household_meetings__host
    foreign key (host_member_id)
    references public.members(id)
    on delete set null,

  constraint ck_household_meetings__status
    check (meeting_status in ('scheduled', 'completed', 'cancelled')),

  constraint ck_household_meetings__type
    check (meeting_type in (
      'regular_household', 'special_household', 'fellowship',
      'formation', 'prayer', 'other'
    )),

  constraint ck_household_meetings__location_type
    check (location_type is null or location_type in (
      'in_person', 'virtual', 'hybrid'
    )),

  constraint ck_household_meetings__start_end_order
    check (
      scheduled_start_at is null
      or scheduled_end_at is null
      or scheduled_end_at > scheduled_start_at
    )
);

create index ix_household_meetings__organization
  on public.household_meetings (organization_id);

create index ix_household_meetings__household_node
  on public.household_meetings (household_node_id, meeting_date desc);

create index ix_household_meetings__org_date
  on public.household_meetings (organization_id, meeting_date desc);

create index ix_household_meetings__status
  on public.household_meetings (organization_id, meeting_status)
  where meeting_status in ('scheduled', 'completed');

-- =============================================================================
-- SECTION 3: household_meeting_attendance Table
-- =============================================================================

create table public.household_meeting_attendance (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null,
  household_meeting_id      uuid        not null,
  member_id                 uuid        not null,

  attendance_status         text        not null,

  arrival_time              timestamptz,

  recorded_at               timestamptz not null default now(),
  recorded_by_profile_id    uuid,

  updated_at                timestamptz not null default now(),
  updated_by_profile_id     uuid,

  constraint pk_household_meeting_attendance
    primary key (id),

  constraint fk_hma__organization
    foreign key (organization_id)
    references public.organizations(id)
    on delete restrict,

  constraint fk_hma__meeting
    foreign key (household_meeting_id)
    references public.household_meetings(id)
    on delete restrict,

  constraint fk_hma__member
    foreign key (member_id)
    references public.members(id)
    on delete restrict,

  -- One attendance row per meeting per member
  constraint ux_hma__meeting_member
    unique (organization_id, household_meeting_id, member_id),

  constraint ck_hma__status
    check (attendance_status in ('present', 'absent', 'excused'))
);

create index ix_hma__meeting
  on public.household_meeting_attendance (household_meeting_id);

create index ix_hma__member
  on public.household_meeting_attendance (organization_id, member_id);

create index ix_hma__org_meeting
  on public.household_meeting_attendance (organization_id, household_meeting_id);

-- =============================================================================
-- SECTION 4: Private Helper – Expected Roster as of a Date
-- =============================================================================

create or replace function private.get_household_expected_roster(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_as_of_date        date
)
returns table (
  member_id       uuid,
  display_name    text,   -- built from full_name
  membership_role text
)
language sql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
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
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from    <= p_as_of_date
    and (hm.effective_to is null or hm.effective_to >= p_as_of_date)
  order by display_name;
$$;

revoke execute on function private.get_household_expected_roster(uuid, uuid, date) from public, anon;
grant  execute on function private.get_household_expected_roster(uuid, uuid, date) to authenticated, service_role;

-- =============================================================================
-- SECTION 5: Private Helper – Attendance Completeness Summary
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
  select count(*) into v_expected_count
  from private.get_household_expected_roster(p_organization_id, p_household_node_id, p_meeting_date);

  select
    count(*),
    count(*) filter (where attendance_status = 'present'),
    count(*) filter (where attendance_status = 'absent'),
    count(*) filter (where attendance_status = 'excused')
  into v_recorded_count, v_present_count, v_absent_count, v_excused_count
  from public.household_meeting_attendance
  where household_meeting_id = p_meeting_id
    and organization_id      = p_organization_id;

  if v_expected_count > 0 then
    v_complete := (v_recorded_count >= v_expected_count);
  else
    v_complete := true;
  end if;

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
-- SECTION 6: Public RPC – Create Household Meeting
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
  v_notes           text;
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

  if p_facilitator_member_id is not null then
    if not exists (
      select 1 from public.members
      where id = p_facilitator_member_id
        and organization_id = p_organization_id
        and lifecycle_status = 'active'
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
        and lifecycle_status = 'active'
    ) then
      raise exception using errcode = 'P0002',
        message = 'Host member not found, not active, or not in this organization.';
    end if;
  end if;

  v_notes := nullif(trim(coalesce(p_notes_summary, '')), '');
  if v_notes is not null and length(v_notes) > 1000 then
    raise exception using errcode = '22023',
      message = 'Notes summary must not exceed 1000 characters.';
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
    notes_summary,
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
    v_notes,
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
-- SECTION 7: Public RPC – Cancel Household Meeting
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

  update public.household_meetings
  set
    meeting_status        = 'cancelled',
    notes_summary         = case
                              when p_reason is not null
                              then coalesce(notes_summary || ' | Cancellation: ', 'Cancellation: ') || left(trim(p_reason), 500)
                              else notes_summary
                            end,
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
      'meeting_date',         v_meeting.meeting_date
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
-- SECTION 8: Public RPC – Complete Household Meeting
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
  v_notes       text;
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

  v_notes := nullif(trim(coalesce(p_notes_summary, '')), '');

  update public.household_meetings
  set
    meeting_status        = 'completed',
    actual_start_at       = coalesce(p_actual_start_at, actual_start_at),
    actual_end_at         = coalesce(p_actual_end_at, actual_end_at),
    notes_summary         = coalesce(v_notes, notes_summary),
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
-- SECTION 9: Public RPC – Record Household Meeting Attendance (Atomic Bulk Upsert)
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

    -- Server-side org membership check
    if not exists (
      select 1 from public.members
      where id = v_member_id
        and organization_id = p_organization_id
    ) then
      raise exception using errcode = 'P0002',
        message = format('Member %s is not a member of this organization.', v_member_id);
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
    attendance_recorded_at              = coalesce(attendance_recorded_at, now()),
    attendance_recorded_by_profile_id   = coalesce(attendance_recorded_by_profile_id, v_profile_id),
    updated_at                          = now(),
    updated_by_profile_id               = v_profile_id
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
-- SECTION 10: Public RPC – Get Household Meeting History (paginated)
-- =============================================================================

create or replace function public.get_household_meeting_history(
  p_organization_id  uuid,
  p_household_id     uuid,
  p_limit            integer default 20,
  p_offset           integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_household   public.governance_nodes%rowtype;
  v_total_count integer;
  v_meetings    jsonb;
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

  select * into v_household
  from public.governance_nodes
  where id = p_household_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  p_limit  := least(greatest(coalesce(p_limit, 20), 1), 100);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  select count(*) into v_total_count
  from public.household_meetings
  where household_node_id = p_household_id
    and organization_id   = p_organization_id;

  select coalesce(jsonb_agg(m_row order by (m_row->>'meeting_date') desc), '[]'::jsonb)
  into v_meetings
  from (
    select jsonb_build_object(
      'household_meeting_id',     hm.id,
      'meeting_date',             hm.meeting_date,
      'meeting_status',           hm.meeting_status,
      'meeting_type',             hm.meeting_type,
      'location_type',            hm.location_type,
      'location_text',            hm.location_text,
      'facilitator_member_id',    hm.facilitator_member_id,
      'facilitator_display_name', fac_mn.full_name,
      'host_member_id',           hm.host_member_id,
      'host_display_name',        host_mn.full_name,
      'attendance_recorded_at',   hm.attendance_recorded_at,
      'attendance_summary',       private.compute_attendance_summary(
                                    hm.id, p_organization_id, hm.meeting_date, p_household_id
                                  ),
      'scheduled_start_at',       hm.scheduled_start_at,
      'scheduled_end_at',         hm.scheduled_end_at,
      'created_at',               hm.created_at
    ) as m_row
    from public.household_meetings hm
    left join (
      select member_id, full_name from public.member_names
      where is_primary = true and effective_to is null
    ) fac_mn on fac_mn.member_id = hm.facilitator_member_id
    left join (
      select member_id, full_name from public.member_names
      where is_primary = true and effective_to is null
    ) host_mn on host_mn.member_id = hm.host_member_id
    where hm.household_node_id = p_household_id
      and hm.organization_id   = p_organization_id
    order by hm.meeting_date desc
    limit p_limit
    offset p_offset
  ) sub;

  return jsonb_build_object(
    'household_id',   p_household_id,
    'household_name', v_household.name,
    'total_count',    v_total_count,
    'limit',          p_limit,
    'offset',         p_offset,
    'meetings',       v_meetings
  );
end;
$$;

revoke execute on function public.get_household_meeting_history(uuid,uuid,integer,integer) from public, anon;
grant  execute on function public.get_household_meeting_history(uuid,uuid,integer,integer) to authenticated, service_role;

-- =============================================================================
-- SECTION 11: Public RPC – Get Household Meeting Detail
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

  -- Historical expected roster: membership as of meeting_date
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

  -- Recorded attendance (privacy-minimized: no PII beyond full_name)
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
    'notes_summary',            v_meeting.notes_summary,
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
-- SECTION 12: Private Helper – Member Follow-up Signals
-- Threshold: 2+ absences in last 3 completed meetings (excused != absent)
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
  select array_agg(id order by meeting_date desc)
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

  -- Last meeting status
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

revoke execute on function private.get_member_follow_up_signals(uuid, uuid, uuid) from public, anon;
grant  execute on function private.get_member_follow_up_signals(uuid, uuid, uuid) to authenticated, service_role;

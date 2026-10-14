-- Pass 7.1: Event Calendar foundation (assemblies, teachings, formation talks) with attendance.
-- Written by Claude, 2026-10-13. Ministry facts confirmed by Ron (2026-10-13):
--   * Monthly assemblies are for MFC New York members (sub-area mfc_ny); FMC members may be invited
--     and are welcome to attend (they are recorded and counted as guests, not as expected attendees).
--   * Attendance at assemblies and teachings is taken by admins, and by anyone assigned as a greeter
--     for that specific event.
--   * The calendar is for leaders and admins first (members' view comes later).
-- Household prayer meetings keep using household_meetings / household_meeting_attendance (unchanged).
-- All client access is through the RPCs below (RLS on, no policies), like the formation tables.

-- =============================================================================
-- 1. Tables
-- =============================================================================
create table if not exists public.events (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_type             text not null check (event_type in ('assembly', 'teaching', 'formation_talk', 'other')),
  title                  text not null check (length(btrim(title)) between 3 and 200),
  description            text null check (description is null or length(description) <= 2000),
  starts_at              timestamptz not null,
  ends_at                timestamptz null,
  location_text          text null check (location_text is null or length(location_text) <= 300),
  audience_node_id       uuid null references public.governance_nodes(id) on delete restrict,
  formation_program_id   uuid null references public.formation_programs(id) on delete restrict,
  formation_talk_id      uuid null references public.formation_talks(id) on delete restrict,
  event_status           text not null default 'scheduled' check (event_status in ('scheduled', 'held', 'cancelled')),
  cancel_reason          text null,
  formation_posted_at    timestamptz null,
  formation_posted_by_profile_id uuid null references public.profiles(id) on delete set null,
  created_by_profile_id  uuid not null references public.profiles(id) on delete restrict,
  created_at             timestamptz not null default now(),
  updated_by_profile_id  uuid null references public.profiles(id) on delete set null,
  updated_at             timestamptz not null default now(),
  constraint chk_events_end_after_start check (ends_at is null or ends_at >= starts_at),
  constraint chk_events_formation_link check (
    (event_type = 'formation_talk' and formation_talk_id is not null and formation_program_id is not null)
    or (event_type <> 'formation_talk' and formation_talk_id is null and formation_program_id is null)
  ),
  constraint chk_events_cancel_reason check (event_status <> 'cancelled' or cancel_reason is not null)
);

create index if not exists idx_events_org_starts on public.events (organization_id, starts_at);

create table if not exists public.event_greeters (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid not null references public.events(id) on delete restrict,
  member_id              uuid not null references public.members(id) on delete restrict,
  assigned_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  assigned_at            timestamptz not null default now(),
  removed_at             timestamptz null,
  removed_by_profile_id  uuid null references public.profiles(id) on delete set null
);

create unique index if not exists uq_event_greeters_active
  on public.event_greeters (event_id, member_id) where removed_at is null;

create table if not exists public.event_attendance (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid not null references public.events(id) on delete restrict,
  member_id              uuid not null references public.members(id) on delete restrict,
  check_in_method        text not null default 'tick' check (check_in_method in ('tick', 'qr')),
  recorded_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  recorded_at            timestamptz not null default now(),
  removed_at             timestamptz null,
  removed_by_profile_id  uuid null references public.profiles(id) on delete set null
);

create unique index if not exists uq_event_attendance_active
  on public.event_attendance (event_id, member_id) where removed_at is null;
create index if not exists idx_event_attendance_member on public.event_attendance (member_id) where removed_at is null;

alter table public.events enable row level security;
alter table public.event_greeters enable row level security;
alter table public.event_attendance enable row level security;

-- =============================================================================
-- 2. Permissions
-- =============================================================================
insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
)
select v.* from (values
  ('events.view', 'View event calendar',
   'Allows viewing the community event calendar (assemblies, teachings, formation talks) and attendance counts.',
   'events', 'view', 'organization', 'standard', false, false, true),
  ('events.manage', 'Manage events',
   'Allows creating, editing, cancelling events and assigning greeters.',
   'events', 'manage', 'organization', 'standard', false, false, true),
  ('events.attendance.record', 'Record event attendance',
   'Allows recording attendance for any event. Greeters can record attendance only for events they are assigned to.',
   'events', 'record', 'organization', 'standard', false, false, true)
) as v(code, name, description, domain_code, action_code, scope_type, risk_level, requires_access_reason, requires_access_logging, is_active)
where not exists (select 1 from public.permissions p where p.code = v.code);

-- Organization Administrator: all three
insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and r.is_system_role
  and p.code in ('events.view', 'events.manage', 'events.attendance.record')
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

-- Servant leader access roles: view the calendar only
insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code in (
    'household_servant_leader_access',
    'unit_servant_leader_access',
    'chapter_servant_leader_access',
    'area_servant_leader_access'
  )
  and r.is_system_role
  and p.code = 'events.view'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

-- =============================================================================
-- 3. Private helpers
-- =============================================================================

-- Member ids linked (verified, current) to the calling profile
create or replace function private.current_member_ids(p_organization_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select pml.member_id
  from public.profile_member_links pml
  where pml.organization_id = p_organization_id
    and pml.profile_id = private.current_profile_id()
    and pml.link_status = 'verified'
    and pml.ended_at is null
$$;
revoke all on function private.current_member_ids(uuid) from public, anon, authenticated;

create or replace function private.is_event_greeter(p_organization_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select exists (
    select 1
    from public.event_greeters g
    where g.organization_id = p_organization_id
      and g.event_id = p_event_id
      and g.removed_at is null
      and g.member_id in (select private.current_member_ids(p_organization_id))
  )
$$;
revoke all on function private.is_event_greeter(uuid, uuid) from public, anon, authenticated;

create or replace function private.can_record_event_attendance(p_organization_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.has_organization_access(p_organization_id)
     and (private.has_permission('events.attendance.record', p_organization_id)
          or private.is_event_greeter(p_organization_id, p_event_id))
$$;
revoke all on function private.can_record_event_attendance(uuid, uuid) from public, anon, authenticated;

-- Sub-area node id of a member's current primary section (null if none)
create or replace function private.member_section_sub_area(p_organization_id uuid, p_member_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.node_sub_area(sm.section_node_id)
  from public.section_memberships sm
  where sm.organization_id = p_organization_id
    and sm.member_id = p_member_id
    and sm.membership_status = 'active'
    and sm.is_primary = true
    and (sm.effective_to is null or sm.effective_to >= current_date)
  order by sm.effective_from desc
  limit 1
$$;
revoke all on function private.member_section_sub_area(uuid, uuid) from public, anon, authenticated;

-- Event summary (counts) as jsonb
create or replace function private.event_summary_json(p_event public.events)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with present as (
    select a.member_id
    from public.event_attendance a
    where a.event_id = p_event.id and a.removed_at is null
  ),
  expected as (
    select m.id
    from public.members m
    where m.organization_id = p_event.organization_id
      and m.record_status = 'active'
      and m.archived_at is null
      and (p_event.audience_node_id is null
           or private.member_section_sub_area(m.organization_id, m.id) = p_event.audience_node_id)
  )
  select jsonb_build_object(
    'id', p_event.id,
    'event_type', p_event.event_type,
    'title', p_event.title,
    'description', p_event.description,
    'starts_at', p_event.starts_at,
    'ends_at', p_event.ends_at,
    'location_text', p_event.location_text,
    'event_status', p_event.event_status,
    'cancel_reason', p_event.cancel_reason,
    'audience_node_id', p_event.audience_node_id,
    'audience_code', (select n.code from public.governance_nodes n where n.id = p_event.audience_node_id),
    'audience_name', coalesce((select n.name from public.governance_nodes n where n.id = p_event.audience_node_id), 'All members'),
    'formation_program_id', p_event.formation_program_id,
    'formation_program_name', (select fp.title from public.formation_programs fp where fp.id = p_event.formation_program_id),
    'formation_talk_id', p_event.formation_talk_id,
    'formation_talk_title', (select ft.title from public.formation_talks ft where ft.id = p_event.formation_talk_id),
    'formation_posted_at', p_event.formation_posted_at,
    'expected_count', (select count(*) from expected),
    'present_count', (select count(*) from present),
    'present_expected_count', (select count(*) from present p where p.member_id in (select id from expected)),
    'guest_count', (select count(*) from present p where p.member_id not in (select id from expected)),
    'is_greeter', private.is_event_greeter(p_event.organization_id, p_event.id),
    'can_record', private.can_record_event_attendance(p_event.organization_id, p_event.id),
    'can_manage', private.has_permission('events.manage', p_event.organization_id)
  )
$$;
revoke all on function private.event_summary_json(public.events) from public, anon, authenticated;

-- Shared validation of event fields; returns the resolved audience node id
create or replace function private.validate_event_fields(
  p_organization_id uuid,
  p_event_type text,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_audience_code text,
  p_formation_talk_id uuid,
  out o_audience_node_id uuid,
  out o_formation_program_id uuid
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if p_event_type is null or p_event_type not in ('assembly', 'teaching', 'formation_talk', 'other') then
    raise exception using errcode = '22023', message = 'Event type must be assembly, teaching, formation_talk or other.';
  end if;
  if p_title is null or length(btrim(p_title)) < 3 then
    raise exception using errcode = '22023', message = 'Event title must be at least 3 characters.';
  end if;
  if p_starts_at is null then
    raise exception using errcode = '22023', message = 'Event start date and time are required.';
  end if;
  if p_ends_at is not null and p_ends_at < p_starts_at then
    raise exception using errcode = '22023', message = 'Event end must be after its start.';
  end if;

  o_audience_node_id := null;
  if p_audience_code is not null and btrim(p_audience_code) <> '' then
    select n.id into o_audience_node_id
    from public.governance_nodes n
    join public.governance_node_types t on t.id = n.governance_node_type_id and t.code = 'area_state'
    where n.organization_id = p_organization_id
      and n.code = btrim(p_audience_code)
      and n.lifecycle_status = 'active'
      and private.node_sub_area(n.id) = n.id;
    if o_audience_node_id is null then
      raise exception using errcode = '22023', message = 'Audience must be a sub-area (for example mfc_ny or fmc_ny), or empty for all members.';
    end if;
  end if;

  o_formation_program_id := null;
  if p_event_type = 'formation_talk' then
    if p_formation_talk_id is null then
      raise exception using errcode = '22023', message = 'A formation talk event must be linked to a talk.';
    end if;
    select ft.program_id into o_formation_program_id
    from public.formation_talks ft
    join public.formation_programs fp on fp.id = ft.program_id
    where ft.id = p_formation_talk_id
      and (fp.organization_id = p_organization_id or fp.organization_id is null)
      and fp.is_active = true
      and ft.is_active = true;
    if o_formation_program_id is null then
      raise exception using errcode = '22023', message = 'Formation talk not found or not active.';
    end if;
  elsif p_formation_talk_id is not null then
    raise exception using errcode = '22023', message = 'Only formation talk events can be linked to a talk.';
  end if;
end;
$$;
revoke all on function private.validate_event_fields(uuid, text, text, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;

-- =============================================================================
-- 4. Public RPCs
-- =============================================================================

-- 4a. create_event
create or replace function public.create_event(
  p_organization_id uuid,
  p_event_type text,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz default null,
  p_location_text text default null,
  p_description text default null,
  p_audience_code text default 'mfc_ny',
  p_formation_talk_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_audience uuid;
  v_program uuid;
  v_event public.events%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if not private.has_permission('events.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.manage.';
  end if;

  select o_audience_node_id, o_formation_program_id into v_audience, v_program
  from private.validate_event_fields(p_organization_id, p_event_type, p_title, p_starts_at, p_ends_at, p_audience_code, p_formation_talk_id);

  insert into public.events (
    organization_id, event_type, title, description, starts_at, ends_at, location_text,
    audience_node_id, formation_program_id, formation_talk_id, event_status,
    created_by_profile_id, updated_by_profile_id
  ) values (
    p_organization_id, p_event_type, btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''),
    p_starts_at, p_ends_at, nullif(btrim(coalesce(p_location_text, '')), ''),
    v_audience, v_program, p_formation_talk_id, 'scheduled',
    v_actor, v_actor
  ) returning * into v_event;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => v_event.id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('event_type', v_event.event_type, 'starts_at', v_event.starts_at,
                                             'audience_node_id', v_event.audience_node_id, 'formation_talk_id', v_event.formation_talk_id)
  );

  return jsonb_build_object('status', 'success', 'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.create_event(uuid, text, text, timestamptz, timestamptz, text, text, text, uuid) from public, anon;
grant execute on function public.create_event(uuid, text, text, timestamptz, timestamptz, text, text, text, uuid) to authenticated;

-- 4b. update_event (all fields replaced; event type may not change once attendance exists)
create or replace function public.update_event(
  p_organization_id uuid,
  p_event_id uuid,
  p_event_type text,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz default null,
  p_location_text text default null,
  p_description text default null,
  p_audience_code text default 'mfc_ny',
  p_formation_talk_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_audience uuid;
  v_program uuid;
  v_event public.events%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if not private.has_permission('events.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.manage.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'A cancelled event cannot be edited. Restore it first.';
  end if;
  if v_event.formation_posted_at is not null
     and (p_event_type is distinct from v_event.event_type or p_formation_talk_id is distinct from v_event.formation_talk_id) then
    raise exception using errcode = '22023', message = 'Attendance was already posted to formation records; the event type and talk can no longer change.';
  end if;

  select o_audience_node_id, o_formation_program_id into v_audience, v_program
  from private.validate_event_fields(p_organization_id, p_event_type, p_title, p_starts_at, p_ends_at, p_audience_code, p_formation_talk_id);

  update public.events
  set event_type = p_event_type,
      title = btrim(p_title),
      description = nullif(btrim(coalesce(p_description, '')), ''),
      starts_at = p_starts_at,
      ends_at = p_ends_at,
      location_text = nullif(btrim(coalesce(p_location_text, '')), ''),
      audience_node_id = v_audience,
      formation_program_id = v_program,
      formation_talk_id = p_formation_talk_id,
      updated_by_profile_id = v_actor,
      updated_at = now()
  where id = v_event.id
  returning * into v_event;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.updated',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => v_event.id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('event_type', v_event.event_type, 'starts_at', v_event.starts_at)
  );

  return jsonb_build_object('status', 'success', 'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.update_event(uuid, uuid, text, text, timestamptz, timestamptz, text, text, text, uuid) from public, anon;
grant execute on function public.update_event(uuid, uuid, text, text, timestamptz, timestamptz, text, text, text, uuid) to authenticated;

-- 4c. set_event_status: scheduled | held | cancelled (cancel needs a reason)
create or replace function public.set_event_status(
  p_organization_id uuid,
  p_event_id uuid,
  p_status text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_event public.events%rowtype;
  v_old text;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if not private.has_permission('events.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.manage.';
  end if;
  if p_status is null or p_status not in ('scheduled', 'held', 'cancelled') then
    raise exception using errcode = '22023', message = 'Status must be scheduled, held or cancelled.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  v_old := v_event.event_status;
  if v_old = p_status then
    raise exception using errcode = '22023', message = 'The event already has status ' || p_status || '.';
  end if;
  if p_status = 'cancelled' and (p_reason is null or length(btrim(p_reason)) < 5) then
    raise exception using errcode = '22023', message = 'A reason of at least 5 characters is required to cancel an event.';
  end if;
  if p_status = 'cancelled' and exists (
    select 1 from public.event_attendance a where a.event_id = v_event.id and a.removed_at is null
  ) then
    raise exception using errcode = '22023', message = 'This event has attendance recorded. Remove the attendance before cancelling it.';
  end if;

  update public.events
  set event_status = p_status,
      cancel_reason = case when p_status = 'cancelled' then btrim(p_reason) else null end,
      updated_by_profile_id = v_actor,
      updated_at = now()
  where id = v_event.id
  returning * into v_event;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.status_changed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => v_event.id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('previous_status', v_old, 'status', p_status,
                                             'reason', nullif(btrim(coalesce(p_reason, '')), ''))
  );

  return jsonb_build_object('status', 'success', 'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.set_event_status(uuid, uuid, text, text) from public, anon;
grant execute on function public.set_event_status(uuid, uuid, text, text) to authenticated;

-- 4d. set_event_greeter: assign (p_assign = true) or remove a greeter. Greeter must have a verified login.
create or replace function public.set_event_greeter(
  p_organization_id uuid,
  p_event_id uuid,
  p_member_id uuid,
  p_assign boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_event public.events%rowtype;
  v_existing uuid;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if not private.has_permission('events.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.manage.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;

  perform pg_advisory_xact_lock(hashtext('event_greeter_' || p_event_id::text || '_' || p_member_id::text));

  select g.id into v_existing
  from public.event_greeters g
  where g.event_id = p_event_id and g.member_id = p_member_id and g.removed_at is null;

  if coalesce(p_assign, true) then
    if v_event.event_status = 'cancelled' then
      raise exception using errcode = '22023', message = 'Greeters cannot be assigned to a cancelled event.';
    end if;
    if v_existing is not null then
      raise exception using errcode = '23505', message = 'This member is already a greeter for this event.';
    end if;
    if not exists (
      select 1 from public.members m
      where m.id = p_member_id and m.organization_id = p_organization_id
        and m.record_status = 'active' and m.archived_at is null
    ) then
      raise exception using errcode = 'P0002', message = 'Member not found or not active.';
    end if;
    if not exists (
      select 1 from public.profile_member_links pml
      where pml.organization_id = p_organization_id and pml.member_id = p_member_id
        and pml.link_status = 'verified' and pml.ended_at is null
    ) then
      raise exception using errcode = '22023', message = 'This member has no MissionOS login yet, so they cannot be a greeter.';
    end if;

    insert into public.event_greeters (organization_id, event_id, member_id, assigned_by_profile_id)
    values (p_organization_id, p_event_id, p_member_id, v_actor);
  else
    if v_existing is null then
      raise exception using errcode = 'P0002', message = 'This member is not a greeter for this event.';
    end if;
    update public.event_greeters
    set removed_at = now(), removed_by_profile_id = v_actor
    where id = v_existing;
  end if;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => case when coalesce(p_assign, true) then 'event.greeter.assigned' else 'event.greeter.removed' end,
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => p_event_id,
    p_action           => case when coalesce(p_assign, true) then 'assign' else 'end' end,
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('member_id', p_member_id)
  );

  return jsonb_build_object('status', 'success', 'event_id', p_event_id, 'member_id', p_member_id,
                            'assigned', coalesce(p_assign, true));
end;
$$;
revoke all on function public.set_event_greeter(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.set_event_greeter(uuid, uuid, uuid, boolean) to authenticated;

-- 4e. list_events: events in a date range (America/New_York dates, inclusive).
--     events.view sees all; otherwise only events where the caller is a greeter.
create or replace function public.list_events(
  p_organization_id uuid,
  p_from date,
  p_to date
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_can_view boolean;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    raise exception using errcode = '22023', message = 'Give a date range of at most 400 days.';
  end if;

  v_can_view := private.has_permission('events.view', p_organization_id);

  return jsonb_build_object(
    'can_view_all', v_can_view,
    'can_manage', private.has_permission('events.manage', p_organization_id),
    'events', coalesce((
      select jsonb_agg(private.event_summary_json(e) order by e.starts_at, e.title)
      from public.events e
      where e.organization_id = p_organization_id
        and (e.starts_at at time zone 'America/New_York')::date between p_from and p_to
        and (v_can_view or private.is_event_greeter(p_organization_id, e.id))
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.list_events(uuid, date, date) from public, anon;
grant execute on function public.list_events(uuid, date, date) to authenticated;

-- 4f. get_event: one event with its greeters
create or replace function public.get_event(
  p_organization_id uuid,
  p_event_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_event public.events%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;

  if not (private.has_permission('events.view', p_organization_id) or private.is_event_greeter(p_organization_id, p_event_id)) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.view.';
  end if;

  return private.event_summary_json(v_event) || jsonb_build_object(
    'greeters', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', m.id, 'display_name', m.display_name,
                                          'member_number', m.member_number) order by m.sort_name)
      from public.event_greeters g
      join public.members m on m.id = g.member_id
      where g.event_id = v_event.id and g.removed_at is null
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_event(uuid, uuid) from public, anon;
grant execute on function public.get_event(uuid, uuid) to authenticated;

-- 4g. get_event_attendance_roster: every active member, with present flag, section, placement, in_audience.
--     Only for callers who can record attendance for this event.
create or replace function public.get_event_attendance_roster(
  p_organization_id uuid,
  p_event_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_event public.events%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;

  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'Access denied: you cannot record attendance for this event.';
  end if;

  return jsonb_build_object(
    'event', private.event_summary_json(v_event),
    'members', coalesce((
      select jsonb_agg(row_to_json(x)::jsonb order by x.sort_name)
      from (
        select
          m.id as member_id,
          m.member_number,
          m.display_name,
          m.sort_name,
          sec.name as section_name,
          sub.code as sub_area_code,
          sub.name as sub_area_name,
          plc.name as placement_name,
          (v_event.audience_node_id is null or sub.id = v_event.audience_node_id) as in_audience,
          (a.id is not null) as is_present,
          a.check_in_method,
          a.recorded_at
        from public.members m
        left join lateral (
          select sm.section_node_id
          from public.section_memberships sm
          where sm.organization_id = m.organization_id and sm.member_id = m.id
            and sm.membership_status = 'active' and sm.is_primary = true
            and (sm.effective_to is null or sm.effective_to >= current_date)
          order by sm.effective_from desc
          limit 1
        ) s on true
        left join public.governance_nodes sec on sec.id = s.section_node_id
        left join public.governance_nodes sub on sub.id = private.node_sub_area(s.section_node_id)
        left join lateral (
          select mga.governance_node_id
          from public.member_governance_assignments mga
          where mga.organization_id = m.organization_id and mga.member_id = m.id
            and mga.is_primary = true and mga.assignment_status = 'active' and mga.effective_to is null
          order by mga.effective_from desc
          limit 1
        ) p on true
        left join public.governance_nodes plc on plc.id = p.governance_node_id
        left join public.event_attendance a
          on a.event_id = v_event.id and a.member_id = m.id and a.removed_at is null
        where m.organization_id = p_organization_id
          and m.record_status = 'active'
          and m.archived_at is null
      ) x
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_event_attendance_roster(uuid, uuid) from public, anon;
grant execute on function public.get_event_attendance_roster(uuid, uuid) to authenticated;

-- 4h. set_event_attendance: mark members present (p_present = true) or remove them (false).
create or replace function public.set_event_attendance(
  p_organization_id uuid,
  p_event_id uuid,
  p_member_ids uuid[],
  p_present boolean default true,
  p_check_in_method text default 'tick'
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_event public.events%rowtype;
  v_ids uuid[];
  v_bad int;
  v_changed int := 0;
  v_unchanged int := 0;
  v_mid uuid;
  v_row uuid;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;

  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'Access denied: you cannot record attendance for this event.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'Attendance cannot be recorded for a cancelled event.';
  end if;
  if (v_event.starts_at at time zone 'America/New_York')::date > (now() at time zone 'America/New_York')::date then
    raise exception using errcode = '22023', message = 'Attendance can be recorded on or after the day of the event.';
  end if;
  if p_check_in_method is null or p_check_in_method not in ('tick', 'qr') then
    raise exception using errcode = '22023', message = 'Check-in method must be tick or qr.';
  end if;

  select array_agg(distinct x) into v_ids from unnest(coalesce(p_member_ids, '{}'::uuid[])) as x where x is not null;
  if v_ids is null or array_length(v_ids, 1) = 0 then
    raise exception using errcode = '22023', message = 'Select at least one member.';
  end if;
  if array_length(v_ids, 1) > 500 then
    raise exception using errcode = '22023', message = 'At most 500 members can be updated at once.';
  end if;

  if coalesce(p_present, true) then
    select count(*) into v_bad
    from unnest(v_ids) as x
    where not exists (
      select 1 from public.members m
      where m.id = x and m.organization_id = p_organization_id
        and m.record_status = 'active' and m.archived_at is null
    );
    if v_bad > 0 then
      raise exception using errcode = '22023', message = format('%s selected member(s) are not active members of this organization.', v_bad);
    end if;
  end if;

  foreach v_mid in array v_ids loop
    select a.id into v_row
    from public.event_attendance a
    where a.event_id = p_event_id and a.member_id = v_mid and a.removed_at is null;

    if coalesce(p_present, true) then
      if v_row is null then
        insert into public.event_attendance (organization_id, event_id, member_id, check_in_method, recorded_by_profile_id)
        values (p_organization_id, p_event_id, v_mid, p_check_in_method, v_actor);
        v_changed := v_changed + 1;
      else
        v_unchanged := v_unchanged + 1;
      end if;
    else
      if v_row is not null then
        update public.event_attendance
        set removed_at = now(), removed_by_profile_id = v_actor
        where id = v_row;
        v_changed := v_changed + 1;
      else
        v_unchanged := v_unchanged + 1;
      end if;
    end if;
  end loop;

  if v_changed > 0 then
    perform private.write_audit_event(
      p_organization_id  => p_organization_id,
      p_event_code       => case when coalesce(p_present, true) then 'event.attendance.recorded' else 'event.attendance.removed' end,
      p_event_category   => 'governance',
      p_actor_profile_id => v_actor,
      p_entity_type      => 'event',
      p_entity_id        => p_event_id,
      p_action           => case when coalesce(p_present, true) then 'record_attendance' else 'void' end,
      p_outcome          => 'success',
      p_access_reason    => null,
      p_correlation_id   => null,
      p_metadata         => jsonb_build_object('changed_count', v_changed, 'unchanged_count', v_unchanged,
                                               'check_in_method', p_check_in_method,
                                               'as_greeter', not private.has_permission('events.attendance.record', p_organization_id))
    );
  end if;

  return jsonb_build_object('status', 'success', 'changed_count', v_changed, 'unchanged_count', v_unchanged,
                            'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.set_event_attendance(uuid, uuid, uuid[], boolean, text) from public, anon;
grant execute on function public.set_event_attendance(uuid, uuid, uuid[], boolean, text) to authenticated;

-- 4i. post_event_attendance_to_formation: for a held formation_talk event, write a talk record
--     ('attended', attended_date = event day) for every present member who does not already have one
--     for this talk in their active attempt. Opens an in_progress program attempt (attendance_roll) if the
--     member has none. Requires events.manage and formation.records.record. Can be run again later to
--     post members added afterwards.
create or replace function public.post_event_attendance_to_formation(
  p_organization_id uuid,
  p_event_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_event public.events%rowtype;
  v_day date;
  v_rec record;
  v_prog_rec_id uuid;
  v_next_attempt int;
  v_posted int := 0;
  v_already int := 0;
  v_completed int := 0;
  v_opened int := 0;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if not private.has_permission('events.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.manage.';
  end if;
  if not private.has_permission('formation.records.record', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission formation.records.record.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if v_event.event_type <> 'formation_talk' then
    raise exception using errcode = '22023', message = 'Only formation talk events can be posted to formation records.';
  end if;
  if v_event.event_status <> 'held' then
    raise exception using errcode = '22023', message = 'Mark the event as held before posting attendance to formation records.';
  end if;

  v_day := (v_event.starts_at at time zone 'America/New_York')::date;

  for v_rec in
    select a.member_id
    from public.event_attendance a
    join public.members m on m.id = a.member_id
    where a.event_id = v_event.id and a.removed_at is null
      and m.record_status = 'active'
    order by m.sort_name
  loop
    -- Already has an active record for this talk in any active attempt?
    if exists (
      select 1
      from public.member_formation_talk_records tr
      join public.member_formation_program_records pr on pr.id = tr.program_record_id
      where tr.member_id = v_rec.member_id and tr.talk_id = v_event.formation_talk_id
        and tr.record_status = 'active' and pr.record_status = 'active'
    ) then
      v_already := v_already + 1;
      continue;
    end if;

    -- Program already completed or waived: do not reopen it
    if exists (
      select 1 from public.member_formation_program_records pr
      where pr.member_id = v_rec.member_id and pr.program_id = v_event.formation_program_id
        and pr.record_status = 'active' and pr.status in ('completed', 'waived')
    ) then
      v_completed := v_completed + 1;
      continue;
    end if;

    select pr.id into v_prog_rec_id
    from public.member_formation_program_records pr
    where pr.organization_id = p_organization_id and pr.member_id = v_rec.member_id
      and pr.program_id = v_event.formation_program_id
      and pr.record_status = 'active' and pr.status = 'in_progress'
    limit 1;

    if v_prog_rec_id is null then
      select coalesce(max(pr.attempt_number), 0) + 1 into v_next_attempt
      from public.member_formation_program_records pr
      where pr.member_id = v_rec.member_id and pr.program_id = v_event.formation_program_id
        and pr.record_status = 'active';

      insert into public.member_formation_program_records (
        organization_id, member_id, program_id, attempt_number, status, record_status,
        date_precision, verification_method, source_reference, recorded_by_profile_id
      ) values (
        p_organization_id, v_rec.member_id, v_event.formation_program_id, v_next_attempt, 'in_progress', 'active',
        'unknown', 'attendance_roll', 'event:' || v_event.id::text, v_actor
      ) returning id into v_prog_rec_id;
      v_opened := v_opened + 1;
    end if;

    insert into public.member_formation_talk_records (
      organization_id, member_id, program_id, program_record_id, talk_id,
      session_status, attended_date, record_status, recorded_by_profile_id, notes
    ) values (
      p_organization_id, v_rec.member_id, v_event.formation_program_id, v_prog_rec_id, v_event.formation_talk_id,
      'attended', v_day, 'active', v_actor, 'From event attendance: ' || v_event.title
    );
    v_posted := v_posted + 1;
  end loop;

  update public.events
  set formation_posted_at = now(), formation_posted_by_profile_id = v_actor, updated_at = now(), updated_by_profile_id = v_actor
  where id = v_event.id
  returning * into v_event;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.attendance.posted_to_formation',
    p_event_category   => 'formation',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => v_event.id,
    p_action           => 'record',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('program_id', v_event.formation_program_id, 'talk_id', v_event.formation_talk_id,
                                             'posted_count', v_posted, 'already_recorded_count', v_already,
                                             'program_already_completed_count', v_completed, 'attempts_opened_count', v_opened)
  );

  return jsonb_build_object('status', 'success', 'posted_count', v_posted, 'already_recorded_count', v_already,
                            'program_already_completed_count', v_completed, 'attempts_opened_count', v_opened,
                            'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.post_event_attendance_to_formation(uuid, uuid) from public, anon;
grant execute on function public.post_event_attendance_to_formation(uuid, uuid) to authenticated;

-- 4j. list_event_formation_talks: active talks for the "link to a course talk" picker
create or replace function public.list_event_formation_talks(
  p_organization_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if not private.has_permission('events.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.manage.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'talk_id', ft.id, 'talk_title', ft.title, 'talk_code', ft.talk_code, 'sequence_order', ft.sequence_order,
             'program_id', fp.id, 'program_name', fp.title)
           order by fp.title, ft.sequence_order)
    from public.formation_talks ft
    join public.formation_programs fp on fp.id = ft.program_id
    where (fp.organization_id = p_organization_id or fp.organization_id is null)
      and fp.is_active = true
      and ft.is_active = true
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_event_formation_talks(uuid) from public, anon;
grant execute on function public.list_event_formation_talks(uuid) to authenticated;

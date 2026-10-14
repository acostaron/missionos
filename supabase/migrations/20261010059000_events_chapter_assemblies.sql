-- Pass 7.2B: Chapter & Section Assemblies, chapter-servant / section-coordinator event management, renamed types
-- (written by Claude, 2026-10-14).
-- Ministry facts confirmed by Ron (2026-10-14):
--   * New event type "Chapter Assembly": only the members of that chapter are expected to attend.
--     Any chapter may be chosen (Albany, Brooklyn Queens, New York, Rockville Center, Handmaids New York,
--     FMC New York Chapter, FMC Handmaids New York Chapter).
--   * "Course Talk" is renamed "Pastoral Formation Talk"; the talk is the title (no separate title field).
--   * "Teaching" is renamed "Programs & Retreat" (label only; the stored code stays 'teaching').
--   * New event type "Section Assembly": only the members of that section are expected. Any active section may be
--     chosen (MFC and FMC sections).
--   * Chapter servants (logged in with chapter servant leader access) can create, edit and take attendance for
--     events of their own chapter. Members outside the event's audience who attend are counted as guests.
--   * Section coordinators (active area_section_coordinator appointment on that section, logged in with a verified
--     member link) can create, edit and take attendance for their own section's events. Their authority comes from
--     the leadership appointment itself; no extra role grant is needed.
-- Who is expected:
--   * sub-area audience (mfc_ny / fmc_ny): members whose current primary section is in that sub-area (unchanged);
--   * chapter audience: members whose current placement is the chapter or a unit under it;
--   * section audience: members whose current primary section is that section;
--   * no audience: all active members.
-- Rule for managing/recording: (permission AND governance scope over the event's audience node or over the
-- organization's root area) OR (caller is a coordinator of the event's section). Greeters keep recording rights for
-- their assigned events only.

-- =============================================================================
-- 1. Event type: add chapter_assembly
-- =============================================================================
alter table public.events drop constraint if exists events_event_type_check;
alter table public.events add constraint events_event_type_check
  check (event_type in ('assembly', 'chapter_assembly', 'section_assembly', 'teaching', 'formation_talk', 'other'));

-- =============================================================================
-- 2. Permissions for chapter servants (scope is enforced inside the RPCs)
-- =============================================================================
insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code = 'chapter_servant_leader_access'
  and r.is_system_role
  and p.code in ('events.manage', 'events.attendance.record')
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

-- =============================================================================
-- 3. Helpers
-- =============================================================================

-- Root area node of the organization (area_state with no active primary parent)
create or replace function private.org_root_area_node(p_organization_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select n.id
  from public.governance_nodes n
  join public.governance_node_types t on t.id = n.governance_node_type_id and t.code = 'area_state'
  where n.organization_id = p_organization_id
    and n.lifecycle_status = 'active'
    and not exists (
      select 1 from public.governance_node_relationships r
      where r.child_node_id = n.id and r.relationship_type = 'primary_parent'
        and r.is_primary = true and r.relationship_status = 'active' and r.effective_to is null
    )
  order by n.created_at
  limit 1
$$;
revoke all on function private.org_root_area_node(uuid) from public, anon, authenticated;

-- true when p_node_id is p_ancestor_id or lies under it
create or replace function private.node_is_within(p_node_id uuid, p_ancestor_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with recursive up(node_id, depth) as (
    select p_node_id, 0
    union all
    select r.parent_node_id, up.depth + 1
    from up
    join public.governance_node_relationships r
      on r.child_node_id = up.node_id
     and r.relationship_type = 'primary_parent'
     and r.is_primary = true
     and r.relationship_status = 'active'
     and r.effective_to is null
    where up.depth < 20
  )
  select p_node_id is not null and p_ancestor_id is not null
     and exists (select 1 from up where up.node_id = p_ancestor_id)
$$;
revoke all on function private.node_is_within(uuid, uuid) from public, anon, authenticated;

-- Is the member in the event's expected audience?
create or replace function private.member_in_event_audience(p_organization_id uuid, p_member_id uuid, p_audience_node_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_type text;
  v_placement uuid;
begin
  if p_audience_node_id is null then
    return true;
  end if;

  select t.code into v_type
  from public.governance_nodes n
  join public.governance_node_types t on t.id = n.governance_node_type_id
  where n.id = p_audience_node_id;

  if v_type = 'chapter' then
    select m.primary_governance_node_id into v_placement
    from public.members m
    where m.id = p_member_id and m.organization_id = p_organization_id;
    return coalesce(private.node_is_within(v_placement, p_audience_node_id), false);
  end if;

  if v_type = 'section' then
    return exists (
      select 1 from public.section_memberships sm
      where sm.organization_id = p_organization_id
        and sm.member_id = p_member_id
        and sm.section_node_id = p_audience_node_id
        and sm.membership_status = 'active'
        and sm.is_primary = true
        and (sm.effective_to is null or sm.effective_to >= current_date)
    );
  end if;

  return private.member_section_sub_area(p_organization_id, p_member_id) is not distinct from p_audience_node_id;
end;
$$;
revoke all on function private.member_in_event_audience(uuid, uuid, uuid) from public, anon, authenticated;

-- Does the caller's governance scope cover this node (directly, or via scope over the organization's root area)?
create or replace function private.caller_covers_node(p_organization_id uuid, p_node_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
  select coalesce(private.profile_has_governance_scope(auth.uid(), p_organization_id,
                    coalesce(p_node_id, private.org_root_area_node(p_organization_id)), now()), false)
      or coalesce(private.profile_has_governance_scope(auth.uid(), p_organization_id,
                    private.org_root_area_node(p_organization_id), now()), false)
$$;
revoke all on function private.caller_covers_node(uuid, uuid) from public, anon, authenticated;

-- Is the caller (via a verified member link) an active section coordinator of this section node?
-- Couple coordinators: either spouse counts (own appointment, or named as couple partner in the appointment).
create or replace function private.is_section_coordinator_of(p_organization_id uuid, p_section_node_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select p_section_node_id is not null and exists (
    select 1
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    where la.organization_id = p_organization_id
      and la.governance_node_id = p_section_node_id
      and lrd.code = 'area_section_coordinator'
      and la.assignment_status = 'active'
      and (la.effective_to is null or la.effective_to >= current_date)
      and (
        la.member_id in (select private.current_member_ids(p_organization_id))
        or nullif(la.metadata->>'couple_partner_member_id', '')::uuid in (select private.current_member_ids(p_organization_id))
      )
  )
$$;
revoke all on function private.is_section_coordinator_of(uuid, uuid) from public, anon, authenticated;

-- Is the caller an active section coordinator of any section?
create or replace function private.is_any_section_coordinator(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select exists (
    select 1
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    where la.organization_id = p_organization_id
      and lrd.code = 'area_section_coordinator'
      and la.assignment_status = 'active'
      and (la.effective_to is null or la.effective_to >= current_date)
      and (
        la.member_id in (select private.current_member_ids(p_organization_id))
        or nullif(la.metadata->>'couple_partner_member_id', '')::uuid in (select private.current_member_ids(p_organization_id))
      )
  )
$$;
revoke all on function private.is_any_section_coordinator(uuid) from public, anon, authenticated;

-- May the caller create/manage events for this audience node (null = all members)?
create or replace function private.caller_can_manage_audience(p_organization_id uuid, p_audience_node_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.has_organization_access(p_organization_id)
     and (
       (private.has_permission('events.manage', p_organization_id)
        and private.caller_covers_node(p_organization_id, p_audience_node_id))
       or private.is_section_coordinator_of(p_organization_id, p_audience_node_id)
     )
$$;
revoke all on function private.caller_can_manage_audience(uuid, uuid) from public, anon, authenticated;

-- Can the caller manage this event?
create or replace function private.can_manage_event(p_organization_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce((
    select private.caller_can_manage_audience(p_organization_id, e.audience_node_id)
    from public.events e
    where e.id = p_event_id and e.organization_id = p_organization_id
  ), false)
$$;
revoke all on function private.can_manage_event(uuid, uuid) from public, anon, authenticated;

-- Replaced: greeter, or (attendance permission + scope), or coordinator of the event's section
create or replace function private.can_record_event_attendance(p_organization_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.has_organization_access(p_organization_id)
     and (
       private.is_event_greeter(p_organization_id, p_event_id)
       or coalesce((
         select (private.has_permission('events.attendance.record', p_organization_id)
                 and private.caller_covers_node(p_organization_id, e.audience_node_id))
             or private.is_section_coordinator_of(p_organization_id, e.audience_node_id)
         from public.events e
         where e.id = p_event_id and e.organization_id = p_organization_id
       ), false)
     )
$$;
revoke all on function private.can_record_event_attendance(uuid, uuid) from public, anon, authenticated;

-- Replaced (OUT parameters change, so drop first): validation now also returns the title and accepts chapters
drop function if exists private.validate_event_fields(uuid, text, text, timestamptz, timestamptz, text, uuid);
create function private.validate_event_fields(
  p_organization_id uuid,
  p_event_type text,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_audience_code text,
  p_formation_talk_id uuid,
  out o_audience_node_id uuid,
  out o_formation_program_id uuid,
  out o_title text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_audience_type text;
begin
  if p_event_type is null or p_event_type not in ('assembly', 'chapter_assembly', 'section_assembly', 'teaching', 'formation_talk', 'other') then
    raise exception using errcode = '22023', message = 'Event type must be assembly, chapter_assembly, section_assembly, teaching, formation_talk or other.';
  end if;
  if p_starts_at is null then
    raise exception using errcode = '22023', message = 'Event start date and time are required.';
  end if;
  if p_ends_at is not null and p_ends_at < p_starts_at then
    raise exception using errcode = '22023', message = 'Event end must be after its start.';
  end if;

  o_audience_node_id := null;
  v_audience_type := null;
  if p_audience_code is not null and btrim(p_audience_code) <> '' then
    select n.id, t.code into o_audience_node_id, v_audience_type
    from public.governance_nodes n
    join public.governance_node_types t on t.id = n.governance_node_type_id
    where n.organization_id = p_organization_id
      and n.code = btrim(p_audience_code)
      and n.lifecycle_status = 'active'
      and (t.code in ('chapter', 'section') or (t.code = 'area_state' and private.node_sub_area(n.id) = n.id));
    if o_audience_node_id is null then
      raise exception using errcode = '22023', message = 'Audience must be a sub-area (mfc_ny or fmc_ny), a chapter, a section, or empty for all members.';
    end if;
  end if;

  if p_event_type = 'chapter_assembly' and v_audience_type is distinct from 'chapter' then
    raise exception using errcode = '22023', message = 'A chapter assembly must be for one chapter.';
  end if;
  if p_event_type = 'section_assembly' and v_audience_type is distinct from 'section' then
    raise exception using errcode = '22023', message = 'A section assembly must be for one section.';
  end if;

  o_formation_program_id := null;
  if p_event_type = 'formation_talk' then
    if p_formation_talk_id is null then
      raise exception using errcode = '22023', message = 'A pastoral formation talk event must be linked to a talk.';
    end if;
    select ft.program_id, ft.title into o_formation_program_id, o_title
    from public.formation_talks ft
    join public.formation_programs fp on fp.id = ft.program_id
    where ft.id = p_formation_talk_id
      and (fp.organization_id = p_organization_id or fp.organization_id is null)
      and fp.is_active = true
      and ft.is_active = true;
    if o_formation_program_id is null then
      raise exception using errcode = '22023', message = 'Formation talk not found or not active.';
    end if;
    -- The talk is the title
    o_title := left(btrim(o_title), 200);
  else
    if p_formation_talk_id is not null then
      raise exception using errcode = '22023', message = 'Only pastoral formation talk events can be linked to a talk.';
    end if;
    if p_title is null or length(btrim(p_title)) < 3 then
      raise exception using errcode = '22023', message = 'Event title must be at least 3 characters.';
    end if;
    o_title := btrim(p_title);
  end if;
end;
$$;
revoke all on function private.validate_event_fields(uuid, text, text, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;

-- Replaced: expected audience via member_in_event_audience; can_manage per event; audience_type
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
      and private.member_in_event_audience(m.organization_id, m.id, p_event.audience_node_id)
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
    'audience_type', (select t.code from public.governance_nodes n
                      join public.governance_node_types t on t.id = n.governance_node_type_id
                      where n.id = p_event.audience_node_id),
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
    'can_manage', private.can_manage_event(p_event.organization_id, p_event.id)
  )
$$;
revoke all on function private.event_summary_json(public.events) from public, anon, authenticated;

-- =============================================================================
-- 4. Public RPCs (replaced)
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
  v_title text;
  v_event public.events%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  select o_audience_node_id, o_formation_program_id, o_title into v_audience, v_program, v_title
  from private.validate_event_fields(p_organization_id, p_event_type, p_title, p_starts_at, p_ends_at, p_audience_code, p_formation_talk_id);

  if not private.caller_can_manage_audience(p_organization_id, v_audience) then
    raise exception using errcode = '42501', message = 'You can only create events for the area, chapter or section you serve.';
  end if;

  insert into public.events (
    organization_id, event_type, title, description, starts_at, ends_at, location_text,
    audience_node_id, formation_program_id, formation_talk_id, event_status,
    created_by_profile_id, updated_by_profile_id
  ) values (
    p_organization_id, p_event_type, v_title, nullif(btrim(coalesce(p_description, '')), ''),
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
  v_title text;
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
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_manage_event(p_organization_id, v_event.id) then
    raise exception using errcode = '42501', message = 'You can only manage events for the area, chapter or section you serve.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'A cancelled event cannot be edited. Restore it first.';
  end if;
  if v_event.formation_posted_at is not null
     and (p_event_type is distinct from v_event.event_type or p_formation_talk_id is distinct from v_event.formation_talk_id) then
    raise exception using errcode = '22023', message = 'Attendance was already posted to formation records; the event type and talk can no longer change.';
  end if;

  select o_audience_node_id, o_formation_program_id, o_title into v_audience, v_program, v_title
  from private.validate_event_fields(p_organization_id, p_event_type, p_title, p_starts_at, p_ends_at, p_audience_code, p_formation_talk_id);

  if not private.caller_can_manage_audience(p_organization_id, v_audience) then
    raise exception using errcode = '42501', message = 'You can only move events to the area, chapter or section you serve.';
  end if;

  update public.events
  set event_type = p_event_type,
      title = v_title,
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
  if p_status is null or p_status not in ('scheduled', 'held', 'cancelled') then
    raise exception using errcode = '22023', message = 'Status must be scheduled, held or cancelled.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_manage_event(p_organization_id, v_event.id) then
    raise exception using errcode = '42501', message = 'You can only manage events for the area, chapter or section you serve.';
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

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_manage_event(p_organization_id, v_event.id) then
    raise exception using errcode = '42501', message = 'You can only manage events for the area, chapter or section you serve.';
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

  v_can_view := private.has_permission('events.view', p_organization_id)
                or private.is_any_section_coordinator(p_organization_id);

  return jsonb_build_object(
    'can_view_all', v_can_view,
    'can_manage', private.has_permission('events.manage', p_organization_id)
                  or private.is_any_section_coordinator(p_organization_id),
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

  if not (private.has_permission('events.view', p_organization_id)
          or private.is_any_section_coordinator(p_organization_id)
          or private.is_event_greeter(p_organization_id, p_event_id)) then
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
          private.member_in_event_audience(m.organization_id, m.id, v_event.audience_node_id) as in_audience,
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

-- 4j. list_event_formation_talks (coordinators may also pick talks): active talks for the "link to a course talk" picker
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
  if not (private.has_permission('events.manage', p_organization_id)
          or private.is_any_section_coordinator(p_organization_id)) then
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

-- 4k. list_event_audience_options: audiences the caller may create events for
--     (sub-areas, chapters and sections), plus whether "All members" is allowed.
create or replace function public.list_event_audience_options(
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
  if not (private.has_permission('events.manage', p_organization_id)
          or private.is_any_section_coordinator(p_organization_id)) then
    raise exception using errcode = '42501', message = 'Access denied: you cannot create events.';
  end if;

  return jsonb_build_object(
    'allow_all_members', private.caller_can_manage_audience(p_organization_id, null),
    'options', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', x.code, 'name', x.name, 'type', x.type_code,
               'sub_area_code', x.sub_area_code, 'sub_area_name', x.sub_area_name)
             order by x.type_rank, x.sub_area_code nulls first, x.name)
      from (
        select n.code, n.name, t.code as type_code,
               case t.code when 'area_state' then 0 when 'chapter' then 1 else 2 end as type_rank,
               sa.code as sub_area_code, sa.name as sub_area_name
        from public.governance_nodes n
        join public.governance_node_types t on t.id = n.governance_node_type_id
        left join public.governance_nodes sa on sa.id = private.node_sub_area(n.id)
        where n.organization_id = p_organization_id
          and n.lifecycle_status = 'active'
          and (t.code in ('chapter', 'section') or (t.code = 'area_state' and private.node_sub_area(n.id) = n.id))
          and private.caller_can_manage_audience(p_organization_id, n.id)
      ) x
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.list_event_audience_options(uuid) from public, anon;
grant execute on function public.list_event_audience_options(uuid) to authenticated;

-- 4l. get_my_event_access: what the calendar menu should show for the caller
create or replace function public.get_my_event_access(
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

  return jsonb_build_object(
    'can_view_calendar', private.has_permission('events.view', p_organization_id)
                         or private.is_any_section_coordinator(p_organization_id),
    'can_create_events', private.has_permission('events.manage', p_organization_id)
                         or private.is_any_section_coordinator(p_organization_id),
    'coordinated_sections', coalesce((
      select jsonb_agg(distinct jsonb_build_object('code', n.code, 'name', n.name,
                                                   'sub_area_code', sa.code, 'sub_area_name', sa.name))
      from public.governance_nodes n
      left join public.governance_nodes sa on sa.id = private.node_sub_area(n.id)
      where n.organization_id = p_organization_id
        and private.is_section_coordinator_of(p_organization_id, n.id)
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_my_event_access(uuid) from public, anon;
grant execute on function public.get_my_event_access(uuid) to authenticated;

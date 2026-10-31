-- =============================================================================
-- Migration: 20261010125000_event_program_speakers_service_teams.sql
-- Pass 9.49: Structured Speakers + Service Teams for Events and Programs
--
-- Design:
--   * Two assignment tables shared by Events and Programs:
--       public.activity_speakers
--       public.activity_service_assignments
--     Each row targets EXACTLY ONE of:
--       event_id        -> public.events(id)        (standalone event OR program session)
--       program_run_id  -> public.program_runs(id)  (program-level, not tied to a session)
--     Both are real foreign keys + a CHECK (num_nonnulls = 1). No generic
--     "entity_type/entity_id" polymorphism.
--   * Program sessions are already events (events.program_run_id), so a
--     session speaker is stored on the session event and aggregated to the
--     Program through events.program_run_id. No duplication across levels.
--   * Identity XOR: member_id (internal MFC member) OR external_name (guest).
--     No fake member records. No contact fields for external people.
--   * Service roles: controlled lookup public.activity_service_roles.
--     These are operational Event/Program assignments only; they never
--     create or modify formal governance offices.
--   * Writes only via SECURITY DEFINER RPCs; actor = private.current_profile_id().
--     Direct table access is revoked from anon/authenticated (RLS on, no policies).
--   * Authorization reuses private.can_manage_event / private.can_manage_program_run.
--   * Reads reuse Event/Program view rules; notes + audit fields are manager-only.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Service role lookup
-- -----------------------------------------------------------------------------
create table if not exists public.activity_service_roles (
  code        text primary key check (code ~ '^[a-z][a-z0-9_]{1,40}$'),
  label       text not null check (length(btrim(label)) between 2 and 80),
  sort_order  integer not null default 100,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

insert into public.activity_service_roles (code, label, sort_order) values
  ('coordinator',            'Coordinator',            10),
  ('assistant_coordinator',  'Assistant Coordinator',  20),
  ('speaker_support',        'Speaker Support',        30),
  ('worship_leader',         'Worship Leader',         40),
  ('music_ministry',         'Music Ministry',         50),
  ('emcee',                  'Emcee',                  60),
  ('facilitator',            'Facilitator',            70),
  ('registration',           'Registration',           80),
  ('secretariat',            'Secretariat',            90),
  ('logistics',              'Logistics',             100),
  ('technical',              'Technical',             110),
  ('hospitality',            'Hospitality',           120),
  ('food',                   'Food',                  130),
  ('transportation',         'Transportation',        140),
  ('prayer_team',            'Prayer Team',           150),
  ('photographer',           'Photographer',          160),
  ('medical',                'Medical',               170),
  ('finance',                'Finance',               180),
  ('communications',         'Communications',        190),
  ('other',                  'Other',                 999)
on conflict (code) do nothing;

alter table public.activity_service_roles enable row level security;
revoke all on table public.activity_service_roles from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Speakers
-- -----------------------------------------------------------------------------
create table if not exists public.activity_speakers (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid null references public.events(id) on delete cascade,
  program_run_id         uuid null references public.program_runs(id) on delete cascade,
  member_id              uuid null references public.members(id) on delete restrict,
  external_name          text null check (external_name is null or length(btrim(external_name)) between 2 and 150),
  external_title         text null check (external_title is null or length(btrim(external_title)) between 1 and 40),
  external_organization  text null check (external_organization is null or length(btrim(external_organization)) between 1 and 200),
  speaker_role           text not null default 'speaker' check (speaker_role in (
                           'speaker', 'facilitator', 'testimony', 'exhortation',
                           'trainer', 'panelist', 'moderator', 'other')),
  topic_title            text null check (topic_title is null or length(btrim(topic_title)) between 1 and 200),
  session_label          text null check (session_label is null or length(btrim(session_label)) between 1 and 100),
  sort_order             integer not null default 0 check (sort_order between 0 and 10000),
  notes                  text null check (notes is null or length(notes) <= 1000),
  created_at             timestamptz not null default now(),
  created_by_profile_id  uuid not null references public.profiles(id) on delete restrict,
  updated_at             timestamptz not null default now(),
  updated_by_profile_id  uuid null references public.profiles(id) on delete set null,
  constraint chk_activity_speakers_target check (num_nonnulls(event_id, program_run_id) = 1),
  constraint chk_activity_speakers_identity check (
    (member_id is not null and external_name is null and external_title is null and external_organization is null)
    or (member_id is null and external_name is not null)
  )
);

create index if not exists idx_activity_speakers_event on public.activity_speakers (event_id) where event_id is not null;
create index if not exists idx_activity_speakers_run on public.activity_speakers (program_run_id) where program_run_id is not null;
create index if not exists idx_activity_speakers_member on public.activity_speakers (member_id) where member_id is not null;

-- Duplicate prevention: same person + same role + same session label on the same target
create unique index if not exists uq_activity_speakers_event_member
  on public.activity_speakers (event_id, member_id, speaker_role, lower(coalesce(session_label, '')))
  where event_id is not null and member_id is not null;
create unique index if not exists uq_activity_speakers_event_external
  on public.activity_speakers (event_id, lower(btrim(external_name)), speaker_role, lower(coalesce(session_label, '')))
  where event_id is not null and external_name is not null;
create unique index if not exists uq_activity_speakers_run_member
  on public.activity_speakers (program_run_id, member_id, speaker_role, lower(coalesce(session_label, '')))
  where program_run_id is not null and member_id is not null;
create unique index if not exists uq_activity_speakers_run_external
  on public.activity_speakers (program_run_id, lower(btrim(external_name)), speaker_role, lower(coalesce(session_label, '')))
  where program_run_id is not null and external_name is not null;

alter table public.activity_speakers enable row level security;
revoke all on table public.activity_speakers from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Service team
-- -----------------------------------------------------------------------------
create table if not exists public.activity_service_assignments (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid null references public.events(id) on delete cascade,
  program_run_id         uuid null references public.program_runs(id) on delete cascade,
  member_id              uuid null references public.members(id) on delete restrict,
  external_name          text null check (external_name is null or length(btrim(external_name)) between 2 and 150),
  role_code              text not null references public.activity_service_roles(code) on delete restrict,
  role_label             text null check (role_label is null or length(btrim(role_label)) between 1 and 80),
  team_group             text null check (team_group is null or length(btrim(team_group)) between 1 and 80),
  sort_order             integer not null default 0 check (sort_order between 0 and 10000),
  notes                  text null check (notes is null or length(notes) <= 1000),
  created_at             timestamptz not null default now(),
  created_by_profile_id  uuid not null references public.profiles(id) on delete restrict,
  updated_at             timestamptz not null default now(),
  updated_by_profile_id  uuid null references public.profiles(id) on delete set null,
  constraint chk_activity_service_target check (num_nonnulls(event_id, program_run_id) = 1),
  constraint chk_activity_service_identity check (num_nonnulls(member_id, external_name) = 1)
);

create index if not exists idx_activity_service_event on public.activity_service_assignments (event_id) where event_id is not null;
create index if not exists idx_activity_service_run on public.activity_service_assignments (program_run_id) where program_run_id is not null;
create index if not exists idx_activity_service_member on public.activity_service_assignments (member_id) where member_id is not null;

-- Duplicate prevention: same person + same role on the same target (multiple roles allowed)
create unique index if not exists uq_activity_service_event_member
  on public.activity_service_assignments (event_id, member_id, role_code)
  where event_id is not null and member_id is not null;
create unique index if not exists uq_activity_service_event_external
  on public.activity_service_assignments (event_id, lower(btrim(external_name)), role_code)
  where event_id is not null and external_name is not null;
create unique index if not exists uq_activity_service_run_member
  on public.activity_service_assignments (program_run_id, member_id, role_code)
  where program_run_id is not null and member_id is not null;
create unique index if not exists uq_activity_service_run_external
  on public.activity_service_assignments (program_run_id, lower(btrim(external_name)), role_code)
  where program_run_id is not null and external_name is not null;

alter table public.activity_service_assignments enable row level security;
revoke all on table public.activity_service_assignments from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. Private helpers
-- -----------------------------------------------------------------------------

-- Manage rule for an event target: program sessions follow the Program's rule
-- (or the event's own audience rule); standalone events follow can_manage_event.
create or replace function private.can_manage_activity_event(p_organization_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce((
    select case
             when e.program_run_id is not null then
               private.can_manage_program_run(p_organization_id, e.program_run_id)
               or private.can_manage_event(p_organization_id, e.id)
             else private.can_manage_event(p_organization_id, e.id)
           end
    from public.events e
    where e.id = p_event_id and e.organization_id = p_organization_id
  ), false)
$$;
revoke all on function private.can_manage_activity_event(uuid, uuid) from public, anon, authenticated;

-- Resolve + authorize a write target. Exactly one of event/program must be given.
create or replace function private.assert_activity_target(
  p_organization_id uuid,
  p_event_id uuid,
  p_program_run_id uuid
) returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if num_nonnulls(p_event_id, p_program_run_id) <> 1 then
    raise exception using errcode = '22023', message = 'Choose exactly one event or program.';
  end if;
  if p_event_id is not null then
    if not exists (select 1 from public.events e where e.id = p_event_id and e.organization_id = p_organization_id) then
      raise exception using errcode = 'P0002', message = 'Event not found.';
    end if;
    if not private.can_manage_activity_event(p_organization_id, p_event_id) then
      raise exception using errcode = '42501', message = 'You can only manage events for the area, chapter or section you serve.';
    end if;
  else
    if not exists (select 1 from public.program_runs r where r.id = p_program_run_id and r.organization_id = p_organization_id) then
      raise exception using errcode = 'P0002', message = 'Program not found.';
    end if;
    if not private.can_manage_program_run(p_organization_id, p_program_run_id) then
      raise exception using errcode = '42501', message = 'You can only manage programs for the area, chapter or section you serve.';
    end if;
  end if;
end;
$$;
revoke all on function private.assert_activity_target(uuid, uuid, uuid) from public, anon, authenticated;

-- Common caller preamble: authenticated profile + org access.
create or replace function private.assert_activity_caller(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  return v_actor;
end;
$$;
revoke all on function private.assert_activity_caller(uuid) from public, anon, authenticated;

-- Validate an internal member for a NEW assignment.
create or replace function private.assert_activity_member(p_organization_id uuid, p_member_id uuid)
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if not exists (
    select 1 from public.members m
    where m.id = p_member_id and m.organization_id = p_organization_id
      and m.record_status = 'active' and m.archived_at is null
  ) then
    raise exception using errcode = '22023', message = 'Member not found, not active, or not in this organization.';
  end if;
end;
$$;
revoke all on function private.assert_activity_member(uuid, uuid) from public, anon, authenticated;

-- Speaker JSON (report-ready). Notes/audit only when p_manage.
create or replace function private.activity_speaker_json(s public.activity_speakers, p_manage boolean)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select jsonb_build_object(
    'id', s.id,
    'event_id', s.event_id,
    'program_run_id', coalesce(s.program_run_id, e.program_run_id),
    'session_number', e.session_number,
    'event_title', e.title,
    'event_starts_at', e.starts_at,
    'person_type', case when s.member_id is not null then 'member' else 'external' end,
    'member_id', s.member_id,
    'member_number', m.member_number,
    'display_name', case
                      when s.member_id is not null then m.display_name
                      else btrim(concat_ws(' ', nullif(btrim(s.external_title), ''), btrim(s.external_name)))
                    end,
    'external_name', s.external_name,
    'external_title', s.external_title,
    'external_organization', s.external_organization,
    'speaker_role', s.speaker_role,
    'topic_title', s.topic_title,
    'session_label', s.session_label,
    'sort_order', s.sort_order,
    'notes', case when p_manage then s.notes end,
    'created_at', case when p_manage then s.created_at end,
    'updated_at', case when p_manage then s.updated_at end
  )
  from (select 1) one
  left join public.members m on m.id = s.member_id
  left join public.events e on e.id = s.event_id
$$;
revoke all on function private.activity_speaker_json(public.activity_speakers, boolean) from public, anon, authenticated;

create or replace function private.activity_service_json(a public.activity_service_assignments, p_manage boolean)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select jsonb_build_object(
    'id', a.id,
    'event_id', a.event_id,
    'program_run_id', coalesce(a.program_run_id, e.program_run_id),
    'session_number', e.session_number,
    'event_title', e.title,
    'person_type', case when a.member_id is not null then 'member' else 'external' end,
    'member_id', a.member_id,
    'member_number', m.member_number,
    'display_name', case when a.member_id is not null then m.display_name else btrim(a.external_name) end,
    'external_name', a.external_name,
    'role_code', a.role_code,
    'role_label', coalesce(nullif(btrim(a.role_label), ''), r.label),
    'custom_role_label', a.role_label,
    'team_group', a.team_group,
    'sort_order', a.sort_order,
    'notes', case when p_manage then a.notes end,
    'created_at', case when p_manage then a.created_at end,
    'updated_at', case when p_manage then a.updated_at end
  )
  from (select 1) one
  left join public.members m on m.id = a.member_id
  left join public.events e on e.id = a.event_id
  left join public.activity_service_roles r on r.code = a.role_code
$$;
revoke all on function private.activity_service_json(public.activity_service_assignments, boolean) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5. Read RPC (report-ready): get_activity_team
--    Event: rows on that event.
--    Program: program-level rows + rows on its non-cancelled session events.
-- -----------------------------------------------------------------------------
create or replace function public.get_activity_team(
  p_organization_id uuid,
  p_event_id uuid default null,
  p_program_run_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_manage boolean;
begin
  perform private.assert_activity_caller(p_organization_id);
  if num_nonnulls(p_event_id, p_program_run_id) <> 1 then
    raise exception using errcode = '22023', message = 'Choose exactly one event or program.';
  end if;

  if p_event_id is not null then
    if not exists (select 1 from public.events e where e.id = p_event_id and e.organization_id = p_organization_id) then
      raise exception using errcode = 'P0002', message = 'Event not found.';
    end if;
    v_manage := private.can_manage_activity_event(p_organization_id, p_event_id);
    if not (v_manage
            or private.has_permission('events.view', p_organization_id)
            or private.is_any_section_coordinator(p_organization_id)
            or private.is_event_greeter(p_organization_id, p_event_id)) then
      raise exception using errcode = '42501', message = 'Access denied: missing required permission events.view.';
    end if;

    return jsonb_build_object(
      'can_manage', v_manage,
      'speakers', coalesce((
        select jsonb_agg(private.activity_speaker_json(s, v_manage) order by s.sort_order, s.created_at)
        from public.activity_speakers s
        where s.event_id = p_event_id and s.organization_id = p_organization_id
      ), '[]'::jsonb),
      'service_team', coalesce((
        select jsonb_agg(private.activity_service_json(a, v_manage) order by a.sort_order, a.created_at)
        from public.activity_service_assignments a
        where a.event_id = p_event_id and a.organization_id = p_organization_id
      ), '[]'::jsonb)
    );
  end if;

  if not exists (select 1 from public.program_runs r where r.id = p_program_run_id and r.organization_id = p_organization_id) then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  v_manage := private.can_manage_program_run(p_organization_id, p_program_run_id);
  if not (v_manage
          or private.has_permission('events.view', p_organization_id)
          or private.is_any_section_coordinator(p_organization_id)) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.view.';
  end if;

  return jsonb_build_object(
    'can_manage', v_manage,
    'speakers', coalesce((
      select jsonb_agg(private.activity_speaker_json(s, v_manage)
                       order by coalesce(e.session_number, 0), s.sort_order, s.created_at)
      from public.activity_speakers s
      left join public.events e on e.id = s.event_id
      where s.organization_id = p_organization_id
        and (s.program_run_id = p_program_run_id
             or (e.program_run_id = p_program_run_id and e.event_status <> 'cancelled'))
    ), '[]'::jsonb),
    'service_team', coalesce((
      select jsonb_agg(private.activity_service_json(a, v_manage)
                       order by coalesce(e.session_number, 0), a.sort_order, a.created_at)
      from public.activity_service_assignments a
      left join public.events e on e.id = a.event_id
      where a.organization_id = p_organization_id
        and (a.program_run_id = p_program_run_id
             or (e.program_run_id = p_program_run_id and e.event_status <> 'cancelled'))
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_activity_team(uuid, uuid, uuid) from public, anon;
grant execute on function public.get_activity_team(uuid, uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Service role list
-- -----------------------------------------------------------------------------
create or replace function public.list_activity_service_roles(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  perform private.assert_activity_caller(p_organization_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object('code', r.code, 'label', r.label) order by r.sort_order, r.label)
    from public.activity_service_roles r
    where r.is_active
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_activity_service_roles(uuid) from public, anon;
grant execute on function public.list_activity_service_roles(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Member picker (scoped to callers who may manage the target)
-- -----------------------------------------------------------------------------
create or replace function public.search_members_for_activity_team(
  p_organization_id uuid,
  p_event_id uuid default null,
  p_program_run_id uuid default null,
  p_query text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_q text := lower(btrim(coalesce(p_query, '')));
begin
  perform private.assert_activity_caller(p_organization_id);
  perform private.assert_activity_target(p_organization_id, p_event_id, p_program_run_id);
  if length(v_q) < 2 then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('member_id', x.id, 'display_name', x.display_name,
                                        'member_number', x.member_number)
                     order by lower(x.sort_name))
    from (select m.id, m.display_name, m.member_number, m.sort_name
          from public.members m
          where m.organization_id = p_organization_id and m.record_status = 'active' and m.archived_at is null
            and (lower(m.display_name) like '%' || v_q || '%' or lower(coalesce(m.member_number, '')) like '%' || v_q || '%')
          order by lower(m.sort_name) limit 20) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.search_members_for_activity_team(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.search_members_for_activity_team(uuid, uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. Speaker write RPCs
-- -----------------------------------------------------------------------------
create or replace function public.save_activity_speaker(
  p_organization_id uuid,
  p_speaker_id uuid default null,
  p_event_id uuid default null,
  p_program_run_id uuid default null,
  p_member_id uuid default null,
  p_external_name text default null,
  p_external_title text default null,
  p_external_organization text default null,
  p_speaker_role text default 'speaker',
  p_topic_title text default null,
  p_session_label text default null,
  p_sort_order integer default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_existing public.activity_speakers%rowtype;
  v_row public.activity_speakers%rowtype;
  v_event uuid := p_event_id;
  v_run uuid := p_program_run_id;
  v_name text := nullif(btrim(coalesce(p_external_name, '')), '');
  v_title text := nullif(btrim(coalesce(p_external_title, '')), '');
  v_org text := nullif(btrim(coalesce(p_external_organization, '')), '');
  v_role text := coalesce(nullif(btrim(p_speaker_role), ''), 'speaker');
  v_sort integer;
begin
  v_actor := private.assert_activity_caller(p_organization_id);

  if p_speaker_id is not null then
    select * into v_existing from public.activity_speakers
    where id = p_speaker_id and organization_id = p_organization_id
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'Speaker assignment not found.';
    end if;
    -- Caller must manage the current target
    perform private.assert_activity_target(p_organization_id, v_existing.event_id, v_existing.program_run_id);
    if v_event is null and v_run is null then
      v_event := v_existing.event_id;
      v_run := v_existing.program_run_id;
    end if;
  end if;

  -- Caller must manage the (new) target
  perform private.assert_activity_target(p_organization_id, v_event, v_run);

  if num_nonnulls(p_member_id, v_name) <> 1 then
    raise exception using errcode = '22023', message = 'Choose either a member or an external speaker name (not both).';
  end if;
  if p_member_id is not null then
    if p_speaker_id is null or v_existing.member_id is distinct from p_member_id then
      perform private.assert_activity_member(p_organization_id, p_member_id);
    end if;
    v_title := null;
    v_org := null;
  end if;
  if v_role not in ('speaker', 'facilitator', 'testimony', 'exhortation', 'trainer', 'panelist', 'moderator', 'other') then
    raise exception using errcode = '22023', message = 'Invalid speaker role.';
  end if;

  if p_sort_order is not null then
    v_sort := p_sort_order;
  elsif p_speaker_id is not null then
    v_sort := v_existing.sort_order;
  else
    select coalesce(max(sort_order) + 1, 0) into v_sort from public.activity_speakers
    where (v_event is not null and event_id = v_event) or (v_run is not null and program_run_id = v_run);
  end if;

  begin
    if p_speaker_id is null then
      insert into public.activity_speakers (
        organization_id, event_id, program_run_id, member_id,
        external_name, external_title, external_organization,
        speaker_role, topic_title, session_label, sort_order, notes,
        created_by_profile_id, updated_by_profile_id
      ) values (
        p_organization_id, v_event, v_run, p_member_id,
        v_name, v_title, v_org,
        v_role, nullif(btrim(coalesce(p_topic_title, '')), ''), nullif(btrim(coalesce(p_session_label, '')), ''),
        v_sort, nullif(btrim(coalesce(p_notes, '')), ''),
        v_actor, v_actor
      ) returning * into v_row;
    else
      update public.activity_speakers set
        event_id = v_event,
        program_run_id = v_run,
        member_id = p_member_id,
        external_name = v_name,
        external_title = v_title,
        external_organization = v_org,
        speaker_role = v_role,
        topic_title = nullif(btrim(coalesce(p_topic_title, '')), ''),
        session_label = nullif(btrim(coalesce(p_session_label, '')), ''),
        sort_order = v_sort,
        notes = nullif(btrim(coalesce(p_notes, '')), ''),
        updated_by_profile_id = v_actor,
        updated_at = now()
      where id = p_speaker_id
      returning * into v_row;
    end if;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'This person is already listed as a speaker in that role here.';
  end;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => case when p_speaker_id is null then 'activity.speaker.added' else 'activity.speaker.updated' end,
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'activity_speaker',
    p_entity_id        => v_row.id,
    p_action           => case when p_speaker_id is null then 'create' else 'update' end,
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'event_id', v_row.event_id, 'program_run_id', v_row.program_run_id,
      'person_type', case when v_row.member_id is not null then 'member' else 'external' end,
      'speaker_role', v_row.speaker_role)
  );

  return jsonb_build_object('status', 'success', 'speaker', private.activity_speaker_json(v_row, true));
end;
$$;
revoke all on function public.save_activity_speaker(uuid, uuid, uuid, uuid, uuid, text, text, text, text, text, text, integer, text) from public, anon;
grant execute on function public.save_activity_speaker(uuid, uuid, uuid, uuid, uuid, text, text, text, text, text, text, integer, text) to authenticated;

create or replace function public.remove_activity_speaker(
  p_organization_id uuid,
  p_speaker_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_row public.activity_speakers%rowtype;
begin
  v_actor := private.assert_activity_caller(p_organization_id);
  select * into v_row from public.activity_speakers
  where id = p_speaker_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Speaker assignment not found.';
  end if;
  perform private.assert_activity_target(p_organization_id, v_row.event_id, v_row.program_run_id);

  delete from public.activity_speakers where id = v_row.id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'activity.speaker.removed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'activity_speaker',
    p_entity_id        => v_row.id,
    p_action           => 'delete',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'event_id', v_row.event_id, 'program_run_id', v_row.program_run_id,
      'member_id', v_row.member_id, 'speaker_role', v_row.speaker_role)
  );
  return jsonb_build_object('status', 'success', 'speaker_id', v_row.id);
end;
$$;
revoke all on function public.remove_activity_speaker(uuid, uuid) from public, anon;
grant execute on function public.remove_activity_speaker(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. Service-team write RPCs
-- -----------------------------------------------------------------------------
create or replace function public.save_activity_service_assignment(
  p_organization_id uuid,
  p_assignment_id uuid default null,
  p_event_id uuid default null,
  p_program_run_id uuid default null,
  p_member_id uuid default null,
  p_external_name text default null,
  p_role_code text default null,
  p_role_label text default null,
  p_team_group text default null,
  p_sort_order integer default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_existing public.activity_service_assignments%rowtype;
  v_row public.activity_service_assignments%rowtype;
  v_event uuid := p_event_id;
  v_run uuid := p_program_run_id;
  v_name text := nullif(btrim(coalesce(p_external_name, '')), '');
  v_role text := nullif(btrim(coalesce(p_role_code, '')), '');
  v_sort integer;
begin
  v_actor := private.assert_activity_caller(p_organization_id);

  if p_assignment_id is not null then
    select * into v_existing from public.activity_service_assignments
    where id = p_assignment_id and organization_id = p_organization_id
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'Service-team assignment not found.';
    end if;
    perform private.assert_activity_target(p_organization_id, v_existing.event_id, v_existing.program_run_id);
    if v_event is null and v_run is null then
      v_event := v_existing.event_id;
      v_run := v_existing.program_run_id;
    end if;
  end if;

  perform private.assert_activity_target(p_organization_id, v_event, v_run);

  if num_nonnulls(p_member_id, v_name) <> 1 then
    raise exception using errcode = '22023', message = 'Choose either a member or an external volunteer name (not both).';
  end if;
  if p_member_id is not null
     and (p_assignment_id is null or v_existing.member_id is distinct from p_member_id) then
    perform private.assert_activity_member(p_organization_id, p_member_id);
  end if;
  if v_role is null or not exists (select 1 from public.activity_service_roles r where r.code = v_role and r.is_active) then
    raise exception using errcode = '22023', message = 'Choose a valid service role.';
  end if;

  if p_sort_order is not null then
    v_sort := p_sort_order;
  elsif p_assignment_id is not null then
    v_sort := v_existing.sort_order;
  else
    select coalesce(max(sort_order) + 1, 0) into v_sort from public.activity_service_assignments
    where (v_event is not null and event_id = v_event) or (v_run is not null and program_run_id = v_run);
  end if;

  begin
    if p_assignment_id is null then
      insert into public.activity_service_assignments (
        organization_id, event_id, program_run_id, member_id, external_name,
        role_code, role_label, team_group, sort_order, notes,
        created_by_profile_id, updated_by_profile_id
      ) values (
        p_organization_id, v_event, v_run, p_member_id, v_name,
        v_role, nullif(btrim(coalesce(p_role_label, '')), ''), nullif(btrim(coalesce(p_team_group, '')), ''),
        v_sort, nullif(btrim(coalesce(p_notes, '')), ''),
        v_actor, v_actor
      ) returning * into v_row;
    else
      update public.activity_service_assignments set
        event_id = v_event,
        program_run_id = v_run,
        member_id = p_member_id,
        external_name = v_name,
        role_code = v_role,
        role_label = nullif(btrim(coalesce(p_role_label, '')), ''),
        team_group = nullif(btrim(coalesce(p_team_group, '')), ''),
        sort_order = v_sort,
        notes = nullif(btrim(coalesce(p_notes, '')), ''),
        updated_by_profile_id = v_actor,
        updated_at = now()
      where id = p_assignment_id
      returning * into v_row;
    end if;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'This person already has that service role here.';
  end;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => case when p_assignment_id is null then 'activity.service.added' else 'activity.service.updated' end,
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'activity_service_assignment',
    p_entity_id        => v_row.id,
    p_action           => case when p_assignment_id is null then 'create' else 'update' end,
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'event_id', v_row.event_id, 'program_run_id', v_row.program_run_id,
      'person_type', case when v_row.member_id is not null then 'member' else 'external' end,
      'role_code', v_row.role_code)
  );

  return jsonb_build_object('status', 'success', 'assignment', private.activity_service_json(v_row, true));
end;
$$;
revoke all on function public.save_activity_service_assignment(uuid, uuid, uuid, uuid, uuid, text, text, text, text, integer, text) from public, anon;
grant execute on function public.save_activity_service_assignment(uuid, uuid, uuid, uuid, uuid, text, text, text, text, integer, text) to authenticated;

create or replace function public.remove_activity_service_assignment(
  p_organization_id uuid,
  p_assignment_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_row public.activity_service_assignments%rowtype;
begin
  v_actor := private.assert_activity_caller(p_organization_id);
  select * into v_row from public.activity_service_assignments
  where id = p_assignment_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Service-team assignment not found.';
  end if;
  perform private.assert_activity_target(p_organization_id, v_row.event_id, v_row.program_run_id);

  delete from public.activity_service_assignments where id = v_row.id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'activity.service.removed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'activity_service_assignment',
    p_entity_id        => v_row.id,
    p_action           => 'delete',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'event_id', v_row.event_id, 'program_run_id', v_row.program_run_id,
      'member_id', v_row.member_id, 'role_code', v_row.role_code)
  );
  return jsonb_build_object('status', 'success', 'assignment_id', v_row.id);
end;
$$;
revoke all on function public.remove_activity_service_assignment(uuid, uuid) from public, anon;
grant execute on function public.remove_activity_service_assignment(uuid, uuid) to authenticated;

-- Pass 7.2C: Programs & Retreat — Youth Camp, Discovery Camp, Christian Life Seminar (written by Claude, 2026-10-14).
-- Ministry facts confirmed by Ron (2026-10-14) and from the project documents
-- ("Formation Courses in MFC", "Assuring a Good Foundation for New Members of MFC", rev Oct 2019):
--   * Youth Camp is for the Youth section; Discovery Camp is for the Campus section (MFC or FMC).
--     A camp is one event that may span several days, with one attendance.
--   * The Christian Life Seminar (CLS) is chapter-based (authority of the Chapter Servant), mounted by section
--     (Couples, Handmaids, Servants, Singles) or as a combined ("mega") CLS of several sections.
--     A CLS has 6 sessions (or the longer 9-session version); attendance is taken at every session.
--   * CLS participants are mostly NEW PEOPLE who are not yet members; members serve as the team.
--   * A CLS graduate is a participant who attended ALL sessions.
-- Design:
--   * program_runs: one run of a program (a CLS, a camp, or another program/retreat).
--   * Each session is an ordinary calendar event (type 'teaching' = "Programs & Retreat") linked to the run.
--   * program_participants: registered participants of a run — members or new people (name + contact).
--   * program_participant_attendance: participants present at a session. Members serving (the team) keep using
--     event_attendance. For a session, "expected" = registered participants.
--   * Managers: admins; for a CLS the Chapter Servant of that chapter; for camps the coordinator of that section
--     (same scope rules as Pass 7.2B, via the run's audience node). Greeters of a session may tick attendance.
--   * New people's contact details are returned only to the run's managers.

-- =============================================================================
-- 1. Tables
-- =============================================================================
create table if not exists public.program_runs (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  program_code           text not null check (program_code in ('youth_camp', 'discovery_camp', 'cls', 'other_program')),
  title                  text not null check (length(btrim(title)) between 3 and 200),
  description            text null check (description is null or length(description) <= 2000),
  chapter_node_id        uuid null references public.governance_nodes(id) on delete restrict,
  section_node_ids       uuid[] not null default '{}'::uuid[],
  audience_node_id       uuid null references public.governance_nodes(id) on delete restrict,
  session_count          integer not null check (session_count between 1 and 30),
  run_status             text not null default 'planned' check (run_status in ('planned', 'running', 'completed', 'cancelled')),
  cancel_reason          text null,
  created_by_profile_id  uuid not null references public.profiles(id) on delete restrict,
  created_at             timestamptz not null default now(),
  updated_by_profile_id  uuid null references public.profiles(id) on delete set null,
  updated_at             timestamptz not null default now(),
  constraint chk_program_runs_cancel_reason check (run_status <> 'cancelled' or cancel_reason is not null)
);
create index if not exists idx_program_runs_org on public.program_runs (organization_id, run_status);

alter table public.events add column if not exists program_run_id uuid null references public.program_runs(id) on delete restrict;
alter table public.events add column if not exists session_number integer null;
alter table public.events drop constraint if exists chk_events_program_session;
alter table public.events add constraint chk_events_program_session check (
  (program_run_id is null and session_number is null)
  or (program_run_id is not null and session_number is not null and session_number >= 1 and event_type = 'teaching')
);
create unique index if not exists uq_events_program_session_active
  on public.events (program_run_id, session_number) where program_run_id is not null and event_status <> 'cancelled';

create table if not exists public.program_participants (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  program_run_id         uuid not null references public.program_runs(id) on delete restrict,
  member_id              uuid null references public.members(id) on delete restrict,
  first_name             text null check (first_name is null or length(btrim(first_name)) between 1 and 100),
  last_name              text null check (last_name is null or length(btrim(last_name)) between 1 and 100),
  phone                  text null check (phone is null or length(phone) <= 40),
  email                  text null check (email is null or length(email) <= 200),
  invited_by_member_id   uuid null references public.members(id) on delete restrict,
  notes                  text null check (notes is null or length(notes) <= 1000),
  participant_status     text not null default 'registered' check (participant_status in ('registered', 'withdrawn')),
  created_by_profile_id  uuid not null references public.profiles(id) on delete restrict,
  created_at             timestamptz not null default now(),
  updated_by_profile_id  uuid null references public.profiles(id) on delete set null,
  updated_at             timestamptz not null default now(),
  constraint chk_program_participants_identity check (
    member_id is not null or (first_name is not null and last_name is not null)
  )
);
create unique index if not exists uq_program_participants_member
  on public.program_participants (program_run_id, member_id) where member_id is not null;
create index if not exists idx_program_participants_run on public.program_participants (program_run_id);

create table if not exists public.program_participant_attendance (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid not null references public.events(id) on delete restrict,
  participant_id         uuid not null references public.program_participants(id) on delete restrict,
  recorded_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  recorded_at            timestamptz not null default now(),
  removed_at             timestamptz null,
  removed_by_profile_id  uuid null references public.profiles(id) on delete set null
);
create unique index if not exists uq_program_participant_attendance_active
  on public.program_participant_attendance (event_id, participant_id) where removed_at is null;

alter table public.program_runs enable row level security;
alter table public.program_participants enable row level security;
alter table public.program_participant_attendance enable row level security;

-- =============================================================================
-- 2. Helpers
-- =============================================================================
create or replace function private.can_manage_program_run(p_organization_id uuid, p_run_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce((
    select private.caller_can_manage_audience(p_organization_id, r.audience_node_id)
    from public.program_runs r
    where r.id = p_run_id and r.organization_id = p_organization_id
  ), false)
$$;
revoke all on function private.can_manage_program_run(uuid, uuid) from public, anon, authenticated;

-- Display name of a participant (member display name, or "First Last" for a new person)
create or replace function private.program_participant_name(p public.program_participants)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce((select m.display_name from public.members m where m.id = p.member_id),
                  btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')))
$$;
revoke all on function private.program_participant_name(public.program_participants) from public, anon, authenticated;

-- Summary of a run as jsonb (no contact details)
create or replace function private.program_run_json(p_run public.program_runs)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with sessions as (
    select e.id from public.events e
    where e.program_run_id = p_run.id and e.event_status <> 'cancelled'
  ),
  parts as (
    select p.id from public.program_participants p
    where p.program_run_id = p_run.id and p.participant_status = 'registered'
  ),
  per_part as (
    select pp.id,
           (select count(*) from public.program_participant_attendance a
            where a.participant_id = pp.id and a.removed_at is null
              and a.event_id in (select id from sessions)) as attended
    from parts pp
  )
  select jsonb_build_object(
    'id', p_run.id,
    'program_code', p_run.program_code,
    'title', p_run.title,
    'description', p_run.description,
    'chapter_code', (select n.code from public.governance_nodes n where n.id = p_run.chapter_node_id),
    'chapter_name', (select n.name from public.governance_nodes n where n.id = p_run.chapter_node_id),
    'sections', coalesce((select jsonb_agg(jsonb_build_object('code', n.code, 'name', n.name,
                                                             'sub_area_name', sa.name) order by n.code)
                          from public.governance_nodes n
                          left join public.governance_nodes sa on sa.id = private.node_sub_area(n.id)
                          where n.id = any(p_run.section_node_ids)), '[]'::jsonb),
    'audience_name', coalesce((select n.name from public.governance_nodes n where n.id = p_run.audience_node_id), 'All members'),
    'session_count', p_run.session_count,
    'sessions_scheduled', (select count(*) from sessions),
    'run_status', p_run.run_status,
    'cancel_reason', p_run.cancel_reason,
    'participant_count', (select count(*) from parts),
    'graduate_count', case when (select count(*) from sessions) = p_run.session_count
                           then (select count(*) from per_part where attended = p_run.session_count)
                           else 0 end,
    'first_session_at', (select min(e.starts_at) from public.events e where e.program_run_id = p_run.id and e.event_status <> 'cancelled'),
    'last_session_at', (select max(coalesce(e.ends_at, e.starts_at)) from public.events e where e.program_run_id = p_run.id and e.event_status <> 'cancelled'),
    'can_manage', private.can_manage_program_run(p_run.organization_id, p_run.id)
  )
$$;
revoke all on function private.program_run_json(public.program_runs) from public, anon, authenticated;

-- Replaced: program sessions count registered participants as "expected"; members ticked are the team
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
    where p_event.program_run_id is null
      and m.organization_id = p_event.organization_id
      and m.record_status = 'active'
      and m.archived_at is null
      and private.member_in_event_audience(m.organization_id, m.id, p_event.audience_node_id)
  ),
  participants as (
    select p.id
    from public.program_participants p
    where p_event.program_run_id is not null
      and p.program_run_id = p_event.program_run_id
      and p.participant_status = 'registered'
  ),
  participants_present as (
    select a.participant_id
    from public.program_participant_attendance a
    where a.event_id = p_event.id and a.removed_at is null
      and a.participant_id in (select id from participants)
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
    'program_run_id', p_event.program_run_id,
    'program_code', (select r.program_code from public.program_runs r where r.id = p_event.program_run_id),
    'program_title', (select r.title from public.program_runs r where r.id = p_event.program_run_id),
    'session_number', p_event.session_number,
    'session_count', (select r.session_count from public.program_runs r where r.id = p_event.program_run_id),
    'is_program_session', p_event.program_run_id is not null,
    'expected_count', case when p_event.program_run_id is null then (select count(*) from expected)
                           else (select count(*) from participants) end,
    'present_count', case when p_event.program_run_id is null then (select count(*) from present)
                          else (select count(*) from participants_present) end,
    'present_expected_count', case when p_event.program_run_id is null
                                   then (select count(*) from present p where p.member_id in (select id from expected))
                                   else (select count(*) from participants_present) end,
    'guest_count', case when p_event.program_run_id is null
                        then (select count(*) from present p where p.member_id not in (select id from expected))
                        else 0 end,
    'team_count', case when p_event.program_run_id is null then 0 else (select count(*) from present) end,
    'is_greeter', private.is_event_greeter(p_event.organization_id, p_event.id),
    'can_record', private.can_record_event_attendance(p_event.organization_id, p_event.id),
    'can_manage', private.can_manage_event(p_event.organization_id, p_event.id)
  )
$$;
revoke all on function private.event_summary_json(public.events) from public, anon, authenticated;

-- =============================================================================
-- 3. Program run RPCs
-- =============================================================================

-- 5a. create_program_run
create or replace function public.create_program_run(
  p_organization_id uuid,
  p_program_code text,
  p_title text,
  p_session_count integer default null,
  p_chapter_code text default null,
  p_section_codes text[] default '{}'::text[],
  p_description text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_chapter uuid;
  v_sections uuid[] := '{}'::uuid[];
  v_kinds text[] := '{}'::text[];
  v_code text;
  v_node uuid;
  v_sessions integer;
  v_audience uuid;
  v_sub_areas uuid[];
  v_run public.program_runs%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if p_program_code is null or p_program_code not in ('youth_camp', 'discovery_camp', 'cls', 'other_program') then
    raise exception using errcode = '22023', message = 'Program must be youth_camp, discovery_camp, cls or other_program.';
  end if;
  if p_title is null or length(btrim(p_title)) < 3 then
    raise exception using errcode = '22023', message = 'Program title must be at least 3 characters.';
  end if;

  -- Chapter (optional except for CLS)
  if p_chapter_code is not null and btrim(p_chapter_code) <> '' then
    select n.id into v_chapter
    from public.governance_nodes n
    join public.governance_node_types t on t.id = n.governance_node_type_id and t.code = 'chapter'
    where n.organization_id = p_organization_id and n.code = btrim(p_chapter_code) and n.lifecycle_status = 'active';
    if v_chapter is null then
      raise exception using errcode = '22023', message = 'Chapter not found or not active.';
    end if;
  end if;

  -- Sections
  foreach v_code in array coalesce(p_section_codes, '{}'::text[]) loop
    select n.id into v_node
    from public.governance_nodes n
    join public.governance_node_types t on t.id = n.governance_node_type_id and t.code = 'section'
    where n.organization_id = p_organization_id and n.code = btrim(v_code) and n.lifecycle_status = 'active';
    if v_node is null then
      raise exception using errcode = '22023', message = format('Section %s not found or not active.', v_code);
    end if;
    if not (v_node = any(v_sections)) then
      v_sections := v_sections || v_node;
      v_kinds := v_kinds || regexp_replace(btrim(v_code), '^.*sec_', '');
    end if;
  end loop;

  if p_program_code = 'youth_camp' then
    if cardinality(v_sections) <> 1 or v_kinds[1] <> 'youth' then
      raise exception using errcode = '22023', message = 'A Youth Camp is for one Youth section.';
    end if;
    v_sessions := 1;
    v_audience := v_sections[1];
  elsif p_program_code = 'discovery_camp' then
    if cardinality(v_sections) <> 1 or v_kinds[1] <> 'campus' then
      raise exception using errcode = '22023', message = 'A Discovery Camp is for one Campus section.';
    end if;
    v_sessions := 1;
    v_audience := v_sections[1];
  elsif p_program_code = 'cls' then
    if v_chapter is null then
      raise exception using errcode = '22023', message = 'A Christian Life Seminar is chapter-based: choose the chapter.';
    end if;
    if cardinality(v_sections) < 1 then
      raise exception using errcode = '22023', message = 'Choose the section(s) mounting the CLS.';
    end if;
    if exists (select 1 from unnest(v_kinds) k where k not in ('couples', 'handmaids', 'servants', 'singles')) then
      raise exception using errcode = '22023', message = 'A CLS is mounted by the Couples, Handmaids, Servants or Singles section.';
    end if;
    if exists (select 1 from unnest(v_sections) s
               where private.node_sub_area(s) is distinct from private.node_sub_area(v_chapter)) then
      raise exception using errcode = '22023', message = 'The CLS sections must be in the same sub-area (MFC or FMC) as the chapter.';
    end if;
    v_sessions := coalesce(p_session_count, 6);
    if v_sessions not in (6, 9) then
      raise exception using errcode = '22023', message = 'A CLS has 6 sessions (or the longer 9-session version).';
    end if;
    v_audience := v_chapter;
  else
    v_sessions := coalesce(p_session_count, 1);
    if v_sessions < 1 or v_sessions > 30 then
      raise exception using errcode = '22023', message = 'Number of sessions must be between 1 and 30.';
    end if;
    if v_chapter is not null then
      v_audience := v_chapter;
    elsif cardinality(v_sections) = 1 then
      v_audience := v_sections[1];
    elsif cardinality(v_sections) > 1 then
      select array_agg(distinct private.node_sub_area(s)) into v_sub_areas from unnest(v_sections) s;
      v_audience := case when cardinality(v_sub_areas) = 1 then v_sub_areas[1] else null end;
    else
      v_audience := null;
    end if;
  end if;

  if not private.caller_can_manage_audience(p_organization_id, v_audience) then
    raise exception using errcode = '42501', message = 'You can only create programs for the area, chapter or section you serve.';
  end if;

  insert into public.program_runs (
    organization_id, program_code, title, description, chapter_node_id, section_node_ids,
    audience_node_id, session_count, run_status, created_by_profile_id, updated_by_profile_id
  ) values (
    p_organization_id, p_program_code, btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''), v_chapter, v_sections,
    v_audience, v_sessions, 'planned', v_actor, v_actor
  ) returning * into v_run;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'program.run.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'program_run',
    p_entity_id        => v_run.id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('program_code', v_run.program_code, 'session_count', v_run.session_count,
                                             'chapter_node_id', v_run.chapter_node_id, 'section_node_ids', to_jsonb(v_run.section_node_ids))
  );

  return jsonb_build_object('status', 'success', 'run', private.program_run_json(v_run));
end;
$$;
revoke all on function public.create_program_run(uuid, text, text, integer, text, text[], text) from public, anon;
grant execute on function public.create_program_run(uuid, text, text, integer, text, text[], text) to authenticated;

-- 5b. update_program_run: title and description only
create or replace function public.update_program_run(
  p_organization_id uuid,
  p_run_id uuid,
  p_title text,
  p_description text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_run public.program_runs%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_run from public.program_runs where id = p_run_id and organization_id = p_organization_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  if not private.can_manage_program_run(p_organization_id, p_run_id) then
    raise exception using errcode = '42501', message = 'You can only manage programs for the area, chapter or section you serve.';
  end if;
  if p_title is null or length(btrim(p_title)) < 3 then
    raise exception using errcode = '22023', message = 'Program title must be at least 3 characters.';
  end if;

  update public.program_runs
  set title = btrim(p_title), description = nullif(btrim(coalesce(p_description, '')), ''),
      updated_by_profile_id = v_actor, updated_at = now()
  where id = p_run_id
  returning * into v_run;

  -- Keep session titles in step with the program title
  update public.events
  set title = case when v_run.session_count = 1 then v_run.title else v_run.title || ' – Session ' || session_number end,
      updated_by_profile_id = v_actor, updated_at = now()
  where program_run_id = p_run_id;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'program.run.updated', p_event_category => 'governance',
    p_actor_profile_id => v_actor, p_entity_type => 'program_run', p_entity_id => p_run_id, p_action => 'update',
    p_outcome => 'success', p_access_reason => null, p_correlation_id => null, p_metadata => '{}'::jsonb);

  return jsonb_build_object('status', 'success', 'run', private.program_run_json(v_run));
end;
$$;
revoke all on function public.update_program_run(uuid, uuid, text, text) from public, anon;
grant execute on function public.update_program_run(uuid, uuid, text, text) to authenticated;

-- 5c. set_program_run_status: planned | running | completed | cancelled
--     Cancelling also cancels its sessions; refused while any session has attendance.
create or replace function public.set_program_run_status(
  p_organization_id uuid,
  p_run_id uuid,
  p_status text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_run public.program_runs%rowtype;
  v_old text;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_run from public.program_runs where id = p_run_id and organization_id = p_organization_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  if not private.can_manage_program_run(p_organization_id, p_run_id) then
    raise exception using errcode = '42501', message = 'You can only manage programs for the area, chapter or section you serve.';
  end if;
  if p_status is null or p_status not in ('planned', 'running', 'completed', 'cancelled') then
    raise exception using errcode = '22023', message = 'Status must be planned, running, completed or cancelled.';
  end if;
  v_old := v_run.run_status;
  if v_old = p_status then
    raise exception using errcode = '22023', message = 'The program already has status ' || p_status || '.';
  end if;

  if p_status = 'cancelled' then
    if p_reason is null or length(btrim(p_reason)) < 5 then
      raise exception using errcode = '22023', message = 'A reason of at least 5 characters is required to cancel a program.';
    end if;
    if exists (select 1 from public.events e
               join public.event_attendance a on a.event_id = e.id and a.removed_at is null
               where e.program_run_id = p_run_id)
       or exists (select 1 from public.events e
                  join public.program_participant_attendance a on a.event_id = e.id and a.removed_at is null
                  where e.program_run_id = p_run_id) then
      raise exception using errcode = '22023', message = 'Attendance was already taken for this program. Remove it before cancelling.';
    end if;
    update public.events
    set event_status = 'cancelled', cancel_reason = 'Program cancelled: ' || btrim(p_reason),
        updated_by_profile_id = v_actor, updated_at = now()
    where program_run_id = p_run_id and event_status <> 'cancelled';
  end if;

  update public.program_runs
  set run_status = p_status,
      cancel_reason = case when p_status = 'cancelled' then btrim(p_reason) else null end,
      updated_by_profile_id = v_actor, updated_at = now()
  where id = p_run_id
  returning * into v_run;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'program.run.status_changed', p_event_category => 'governance',
    p_actor_profile_id => v_actor, p_entity_type => 'program_run', p_entity_id => p_run_id, p_action => 'update',
    p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('previous_status', v_old, 'status', p_status, 'reason', nullif(btrim(coalesce(p_reason, '')), '')));

  return jsonb_build_object('status', 'success', 'run', private.program_run_json(v_run));
end;
$$;
revoke all on function public.set_program_run_status(uuid, uuid, text, text) from public, anon;
grant execute on function public.set_program_run_status(uuid, uuid, text, text) to authenticated;

-- 5d. add_program_session: schedule session N of a run as a calendar event
create or replace function public.add_program_session(
  p_organization_id uuid,
  p_run_id uuid,
  p_session_number integer,
  p_starts_at timestamptz,
  p_ends_at timestamptz default null,
  p_location_text text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_run public.program_runs%rowtype;
  v_event public.events%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_run from public.program_runs where id = p_run_id and organization_id = p_organization_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  if not private.can_manage_program_run(p_organization_id, p_run_id) then
    raise exception using errcode = '42501', message = 'You can only manage programs for the area, chapter or section you serve.';
  end if;
  if v_run.run_status in ('cancelled', 'completed') then
    raise exception using errcode = '22023', message = 'Sessions cannot be added to a cancelled or completed program.';
  end if;
  if p_session_number is null or p_session_number < 1 or p_session_number > v_run.session_count then
    raise exception using errcode = '22023', message = format('Session number must be between 1 and %s.', v_run.session_count);
  end if;
  if p_starts_at is null then
    raise exception using errcode = '22023', message = 'Session start date and time are required.';
  end if;
  if p_ends_at is not null and p_ends_at < p_starts_at then
    raise exception using errcode = '22023', message = 'Session end must be after its start.';
  end if;
  if exists (select 1 from public.events e
             where e.program_run_id = p_run_id and e.session_number = p_session_number and e.event_status <> 'cancelled') then
    raise exception using errcode = '23505', message = format('Session %s is already scheduled.', p_session_number);
  end if;

  insert into public.events (
    organization_id, event_type, title, starts_at, ends_at, location_text, audience_node_id,
    event_status, program_run_id, session_number, created_by_profile_id, updated_by_profile_id
  ) values (
    p_organization_id, 'teaching',
    case when v_run.session_count = 1 then v_run.title else v_run.title || ' – Session ' || p_session_number end,
    p_starts_at, p_ends_at, nullif(btrim(coalesce(p_location_text, '')), ''), v_run.audience_node_id,
    'scheduled', p_run_id, p_session_number, v_actor, v_actor
  ) returning * into v_event;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'program.session.added', p_event_category => 'governance',
    p_actor_profile_id => v_actor, p_entity_type => 'event', p_entity_id => v_event.id, p_action => 'create',
    p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('program_run_id', p_run_id, 'session_number', p_session_number, 'starts_at', p_starts_at));

  return jsonb_build_object('status', 'success', 'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.add_program_session(uuid, uuid, integer, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.add_program_session(uuid, uuid, integer, timestamptz, timestamptz, text) to authenticated;

-- 5e. update_program_session: date/time/location of a session
create or replace function public.update_program_session(
  p_organization_id uuid,
  p_event_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz default null,
  p_location_text text default null
) returns jsonb
language plpgsql
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
  where id = p_event_id and organization_id = p_organization_id and program_run_id is not null
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program session not found.';
  end if;
  if not private.can_manage_program_run(p_organization_id, v_event.program_run_id) then
    raise exception using errcode = '42501', message = 'You can only manage programs for the area, chapter or section you serve.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'A cancelled session cannot be edited.';
  end if;
  if p_starts_at is null then
    raise exception using errcode = '22023', message = 'Session start date and time are required.';
  end if;
  if p_ends_at is not null and p_ends_at < p_starts_at then
    raise exception using errcode = '22023', message = 'Session end must be after its start.';
  end if;

  update public.events
  set starts_at = p_starts_at, ends_at = p_ends_at,
      location_text = nullif(btrim(coalesce(p_location_text, '')), ''),
      updated_by_profile_id = v_actor, updated_at = now()
  where id = p_event_id
  returning * into v_event;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'program.session.updated', p_event_category => 'governance',
    p_actor_profile_id => v_actor, p_entity_type => 'event', p_entity_id => p_event_id, p_action => 'update',
    p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('starts_at', p_starts_at));

  return jsonb_build_object('status', 'success', 'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.update_program_session(uuid, uuid, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.update_program_session(uuid, uuid, timestamptz, timestamptz, text) to authenticated;

-- =============================================================================
-- 4. Participant RPCs
-- =============================================================================

-- 6a. add_program_participant: a member (p_member_id) or a new person (first + last name, optional contact)
create or replace function public.add_program_participant(
  p_organization_id uuid,
  p_run_id uuid,
  p_member_id uuid default null,
  p_first_name text default null,
  p_last_name text default null,
  p_phone text default null,
  p_email text default null,
  p_invited_by_member_id uuid default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_run public.program_runs%rowtype;
  v_part public.program_participants%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_run from public.program_runs where id = p_run_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  if not private.can_manage_program_run(p_organization_id, p_run_id) then
    raise exception using errcode = '42501', message = 'You can only manage programs for the area, chapter or section you serve.';
  end if;
  if v_run.run_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'Participants cannot be added to a cancelled program.';
  end if;

  if p_member_id is not null then
    if not exists (select 1 from public.members m
                   where m.id = p_member_id and m.organization_id = p_organization_id
                     and m.record_status = 'active' and m.archived_at is null) then
      raise exception using errcode = 'P0002', message = 'Member not found or not active.';
    end if;
    if exists (select 1 from public.program_participants p where p.program_run_id = p_run_id and p.member_id = p_member_id) then
      raise exception using errcode = '23505', message = 'This member is already registered in this program.';
    end if;
  else
    if p_first_name is null or length(btrim(p_first_name)) = 0 or p_last_name is null or length(btrim(p_last_name)) = 0 then
      raise exception using errcode = '22023', message = 'First name and last name are required for a new participant.';
    end if;
  end if;

  if p_invited_by_member_id is not null and not exists (
    select 1 from public.members m where m.id = p_invited_by_member_id and m.organization_id = p_organization_id
  ) then
    raise exception using errcode = 'P0002', message = 'Inviting member not found.';
  end if;

  insert into public.program_participants (
    organization_id, program_run_id, member_id, first_name, last_name, phone, email,
    invited_by_member_id, notes, participant_status, created_by_profile_id, updated_by_profile_id
  ) values (
    p_organization_id, p_run_id, p_member_id,
    case when p_member_id is null then btrim(p_first_name) end,
    case when p_member_id is null then btrim(p_last_name) end,
    case when p_member_id is null then nullif(btrim(coalesce(p_phone, '')), '') end,
    case when p_member_id is null then nullif(lower(btrim(coalesce(p_email, ''))), '') end,
    p_invited_by_member_id, nullif(btrim(coalesce(p_notes, '')), ''), 'registered', v_actor, v_actor
  ) returning * into v_part;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'program.participant.added', p_event_category => 'governance',
    p_actor_profile_id => v_actor, p_entity_type => 'program_participant', p_entity_id => v_part.id, p_action => 'create',
    p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('program_run_id', p_run_id, 'is_member', p_member_id is not null));

  return jsonb_build_object('status', 'success', 'participant_id', v_part.id,
                            'name', private.program_participant_name(v_part));
end;
$$;
revoke all on function public.add_program_participant(uuid, uuid, uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function public.add_program_participant(uuid, uuid, uuid, text, text, text, text, uuid, text) to authenticated;

-- 6b. update_program_participant: new person's name/contact; invited-by and notes for anyone
create or replace function public.update_program_participant(
  p_organization_id uuid,
  p_participant_id uuid,
  p_first_name text default null,
  p_last_name text default null,
  p_phone text default null,
  p_email text default null,
  p_invited_by_member_id uuid default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_part public.program_participants%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_part from public.program_participants
  where id = p_participant_id and organization_id = p_organization_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Participant not found.';
  end if;
  if not private.can_manage_program_run(p_organization_id, v_part.program_run_id) then
    raise exception using errcode = '42501', message = 'You can only manage programs for the area, chapter or section you serve.';
  end if;
  if v_part.member_id is null
     and (p_first_name is null or length(btrim(p_first_name)) = 0 or p_last_name is null or length(btrim(p_last_name)) = 0) then
    raise exception using errcode = '22023', message = 'First name and last name are required for a new participant.';
  end if;
  if p_invited_by_member_id is not null and not exists (
    select 1 from public.members m where m.id = p_invited_by_member_id and m.organization_id = p_organization_id
  ) then
    raise exception using errcode = 'P0002', message = 'Inviting member not found.';
  end if;

  update public.program_participants
  set first_name = case when member_id is null then btrim(p_first_name) else null end,
      last_name  = case when member_id is null then btrim(p_last_name) else null end,
      phone      = case when member_id is null then nullif(btrim(coalesce(p_phone, '')), '') else null end,
      email      = case when member_id is null then nullif(lower(btrim(coalesce(p_email, ''))), '') else null end,
      invited_by_member_id = p_invited_by_member_id,
      notes = nullif(btrim(coalesce(p_notes, '')), ''),
      updated_by_profile_id = v_actor, updated_at = now()
  where id = p_participant_id
  returning * into v_part;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'program.participant.updated', p_event_category => 'governance',
    p_actor_profile_id => v_actor, p_entity_type => 'program_participant', p_entity_id => p_participant_id, p_action => 'update',
    p_outcome => 'success', p_access_reason => null, p_correlation_id => null, p_metadata => '{}'::jsonb);

  return jsonb_build_object('status', 'success', 'participant_id', v_part.id, 'name', private.program_participant_name(v_part));
end;
$$;
revoke all on function public.update_program_participant(uuid, uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function public.update_program_participant(uuid, uuid, text, text, text, text, uuid, text) to authenticated;

-- 6c. set_program_participant_status: registered | withdrawn
create or replace function public.set_program_participant_status(
  p_organization_id uuid,
  p_participant_id uuid,
  p_status text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_part public.program_participants%rowtype;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_part from public.program_participants
  where id = p_participant_id and organization_id = p_organization_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Participant not found.';
  end if;
  if not private.can_manage_program_run(p_organization_id, v_part.program_run_id) then
    raise exception using errcode = '42501', message = 'You can only manage programs for the area, chapter or section you serve.';
  end if;
  if p_status is null or p_status not in ('registered', 'withdrawn') then
    raise exception using errcode = '22023', message = 'Status must be registered or withdrawn.';
  end if;
  if v_part.participant_status = p_status then
    raise exception using errcode = '22023', message = 'The participant already has status ' || p_status || '.';
  end if;

  update public.program_participants
  set participant_status = p_status, updated_by_profile_id = v_actor, updated_at = now()
  where id = p_participant_id;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'program.participant.status_changed', p_event_category => 'governance',
    p_actor_profile_id => v_actor, p_entity_type => 'program_participant', p_entity_id => p_participant_id, p_action => 'update',
    p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('previous_status', v_part.participant_status, 'status', p_status));

  return jsonb_build_object('status', 'success', 'participant_id', p_participant_id, 'participant_status', p_status);
end;
$$;
revoke all on function public.set_program_participant_status(uuid, uuid, text) from public, anon;
grant execute on function public.set_program_participant_status(uuid, uuid, text) to authenticated;

-- =============================================================================
-- 5. Read RPCs
-- =============================================================================

-- 7a. list_program_runs
create or replace function public.list_program_runs(
  p_organization_id uuid,
  p_include_closed boolean default false
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
  if not (private.has_permission('events.view', p_organization_id) or private.is_any_section_coordinator(p_organization_id)) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.view.';
  end if;

  return jsonb_build_object(
    'can_create', private.has_permission('events.manage', p_organization_id) or private.is_any_section_coordinator(p_organization_id),
    'runs', coalesce((
      select jsonb_agg(private.program_run_json(r) order by r.created_at desc)
      from public.program_runs r
      where r.organization_id = p_organization_id
        and (coalesce(p_include_closed, false) or r.run_status in ('planned', 'running'))
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.list_program_runs(uuid, boolean) from public, anon;
grant execute on function public.list_program_runs(uuid, boolean) to authenticated;

-- 7b. get_program_run: run + sessions + participants with per-session attendance and graduation.
--     Contact details (phone, email, notes) only for the run's managers.
create or replace function public.get_program_run(
  p_organization_id uuid,
  p_run_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_run public.program_runs%rowtype;
  v_manage boolean;
  v_scheduled integer;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  select * into v_run from public.program_runs where id = p_run_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  v_manage := private.can_manage_program_run(p_organization_id, p_run_id);
  if not (v_manage or private.has_permission('events.view', p_organization_id)
          or private.is_any_section_coordinator(p_organization_id)) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.view.';
  end if;

  select count(*) into v_scheduled from public.events e
  where e.program_run_id = p_run_id and e.event_status <> 'cancelled';

  return jsonb_build_object(
    'run', private.program_run_json(v_run),
    'sessions', coalesce((
      select jsonb_agg(private.event_summary_json(e) order by e.session_number, e.starts_at)
      from public.events e
      where e.program_run_id = p_run_id and e.event_status <> 'cancelled'
    ), '[]'::jsonb),
    'participants', coalesce((
      select jsonb_agg(x.j order by x.sort_key)
      from (
        select lower(private.program_participant_name(p)) as sort_key,
               jsonb_build_object(
                 'participant_id', p.id,
                 'name', private.program_participant_name(p),
                 'is_member', p.member_id is not null,
                 'member_id', p.member_id,
                 'member_number', (select m.member_number from public.members m where m.id = p.member_id),
                 'participant_status', p.participant_status,
                 'invited_by_name', (select m.display_name from public.members m where m.id = p.invited_by_member_id),
                 'invited_by_member_id', p.invited_by_member_id,
                 'phone', case when v_manage then p.phone end,
                 'email', case when v_manage then p.email end,
                 'notes', case when v_manage then p.notes end,
                 'first_name', case when v_manage then p.first_name end,
                 'last_name', case when v_manage then p.last_name end,
                 'attended_sessions', coalesce((
                   select jsonb_agg(e.session_number order by e.session_number)
                   from public.program_participant_attendance a
                   join public.events e on e.id = a.event_id and e.event_status <> 'cancelled'
                   where a.participant_id = p.id and a.removed_at is null
                 ), '[]'::jsonb),
                 'attended_count', (
                   select count(*)
                   from public.program_participant_attendance a
                   join public.events e on e.id = a.event_id and e.event_status <> 'cancelled'
                   where a.participant_id = p.id and a.removed_at is null
                 ),
                 'graduated', p.participant_status = 'registered'
                              and v_scheduled = v_run.session_count
                              and (select count(*)
                                   from public.program_participant_attendance a
                                   join public.events e on e.id = a.event_id and e.event_status <> 'cancelled'
                                   where a.participant_id = p.id and a.removed_at is null) = v_run.session_count
               ) as j
        from public.program_participants p
        where p.program_run_id = p_run_id
      ) x
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_program_run(uuid, uuid) from public, anon;
grant execute on function public.get_program_run(uuid, uuid) to authenticated;

-- 7c. get_program_session_roster: registered participants of a session (names only) with present flag
create or replace function public.get_program_session_roster(
  p_organization_id uuid,
  p_event_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event public.events%rowtype;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id and program_run_id is not null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program session not found.';
  end if;
  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'Access denied: you cannot record attendance for this session.';
  end if;

  return jsonb_build_object(
    'event', private.event_summary_json(v_event),
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
               'participant_id', p.id,
               'name', private.program_participant_name(p),
               'is_member', p.member_id is not null,
               'member_number', (select m.member_number from public.members m where m.id = p.member_id),
               'is_present', exists (select 1 from public.program_participant_attendance a
                                     where a.event_id = p_event_id and a.participant_id = p.id and a.removed_at is null))
             order by lower(private.program_participant_name(p)))
      from public.program_participants p
      where p.program_run_id = v_event.program_run_id and p.participant_status = 'registered'
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_program_session_roster(uuid, uuid) from public, anon;
grant execute on function public.get_program_session_roster(uuid, uuid) to authenticated;

-- 7d. set_program_participant_attendance: tick (p_present = true) or untick participants at a session
create or replace function public.set_program_participant_attendance(
  p_organization_id uuid,
  p_event_id uuid,
  p_participant_ids uuid[],
  p_present boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_event public.events%rowtype;
  v_ids uuid[];
  v_pid uuid;
  v_row uuid;
  v_changed int := 0;
  v_unchanged int := 0;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id and program_run_id is not null
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program session not found.';
  end if;
  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'Access denied: you cannot record attendance for this session.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'Attendance cannot be recorded for a cancelled session.';
  end if;
  if (v_event.starts_at at time zone 'America/New_York')::date > (now() at time zone 'America/New_York')::date then
    raise exception using errcode = '22023', message = 'Attendance can be recorded on or after the day of the session.';
  end if;

  select array_agg(distinct x) into v_ids from unnest(coalesce(p_participant_ids, '{}'::uuid[])) as x where x is not null;
  if v_ids is null or array_length(v_ids, 1) = 0 then
    raise exception using errcode = '22023', message = 'Select at least one participant.';
  end if;
  if array_length(v_ids, 1) > 500 then
    raise exception using errcode = '22023', message = 'At most 500 participants can be updated at once.';
  end if;
  if exists (select 1 from unnest(v_ids) x
             where not exists (select 1 from public.program_participants p
                               where p.id = x and p.program_run_id = v_event.program_run_id
                                 and p.participant_status = 'registered')) then
    raise exception using errcode = '22023', message = 'All selected people must be registered participants of this program.';
  end if;

  foreach v_pid in array v_ids loop
    select a.id into v_row from public.program_participant_attendance a
    where a.event_id = p_event_id and a.participant_id = v_pid and a.removed_at is null;
    if coalesce(p_present, true) then
      if v_row is null then
        insert into public.program_participant_attendance (organization_id, event_id, participant_id, recorded_by_profile_id)
        values (p_organization_id, p_event_id, v_pid, v_actor);
        v_changed := v_changed + 1;
      else
        v_unchanged := v_unchanged + 1;
      end if;
    else
      if v_row is not null then
        update public.program_participant_attendance set removed_at = now(), removed_by_profile_id = v_actor where id = v_row;
        v_changed := v_changed + 1;
      else
        v_unchanged := v_unchanged + 1;
      end if;
    end if;
  end loop;

  if v_changed > 0 then
    perform private.write_audit_event(
      p_organization_id => p_organization_id,
      p_event_code => case when coalesce(p_present, true) then 'program.attendance.recorded' else 'program.attendance.removed' end,
      p_event_category => 'governance', p_actor_profile_id => v_actor, p_entity_type => 'event', p_entity_id => p_event_id,
      p_action => case when coalesce(p_present, true) then 'record_attendance' else 'void' end,
      p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
      p_metadata => jsonb_build_object('changed_count', v_changed, 'unchanged_count', v_unchanged,
                                       'program_run_id', v_event.program_run_id, 'session_number', v_event.session_number));
  end if;

  return jsonb_build_object('status', 'success', 'changed_count', v_changed, 'unchanged_count', v_unchanged,
                            'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.set_program_participant_attendance(uuid, uuid, uuid[], boolean) from public, anon;
grant execute on function public.set_program_participant_attendance(uuid, uuid, uuid[], boolean) to authenticated;

-- =============================================================================
-- 6. Replaced event RPCs: program sessions are edited from the program page; participant attendance blocks cancel
-- =============================================================================

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
  if v_event.program_run_id is not null then
    raise exception using errcode = '22023', message = 'This is a program session. Change its date, time or place from the program page.';
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
  if p_status = 'cancelled' and (
    exists (select 1 from public.event_attendance a where a.event_id = v_event.id and a.removed_at is null)
    or exists (select 1 from public.program_participant_attendance a where a.event_id = v_event.id and a.removed_at is null)
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

-- Migration: 20261010123000_program_reporting_metadata.sql
-- Description: Add quarterly reporting metadata, read visibility masking, and reporting-readiness querying to Programs.

-- =============================================================================
-- 1. Table alterations: Add reporting metadata columns to public.program_runs
-- =============================================================================

alter table public.program_runs
  add column if not exists include_in_quarterly_report boolean not null default false,
  add column if not exists report_priority text not null default 'routine',
  add column if not exists report_highlight text null;

alter table public.program_runs drop constraint if exists chk_program_runs_report_priority;
alter table public.program_runs add constraint chk_program_runs_report_priority
  check (report_priority in ('routine', 'ministry_activity', 'major_highlight'));

alter table public.program_runs drop constraint if exists chk_program_runs_report_highlight;
alter table public.program_runs add constraint chk_program_runs_report_highlight
  check (report_highlight is null or length(btrim(report_highlight)) <= 2000);

-- =============================================================================
-- 2. Update private.program_run_json:
--    - Expose venue_location derived from constituent session events
--    - Expose audience_node_id
--    - Mask internal reporting metadata (include_in_quarterly_report, report_priority,
--      report_highlight) to NULL for non-managers (can_manage = false)
-- =============================================================================

create or replace function private.program_run_json(p_run public.program_runs)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with sessions as (
    select e.id, e.session_number, e.starts_at, e.ends_at, e.location_text
    from public.events e
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
  ),
  manage_check as (
    select private.can_manage_program_run(p_run.organization_id, p_run.id) as can_manage
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
    'audience_node_id', p_run.audience_node_id,
    'session_count', p_run.session_count,
    'sessions_scheduled', (select count(*) from sessions),
    'run_status', p_run.run_status,
    'cancel_reason', p_run.cancel_reason,
    'include_in_quarterly_report', case when (select can_manage from manage_check) then p_run.include_in_quarterly_report else null end,
    'report_priority', case when (select can_manage from manage_check) then p_run.report_priority else null end,
    'report_highlight', case when (select can_manage from manage_check) then p_run.report_highlight else null end,
    'participant_count', (select count(*) from parts),
    'graduate_count', case when (select count(*) from sessions) = p_run.session_count
                           then (select count(*) from per_part where attended = p_run.session_count)
                           else 0 end,
    'first_session_at', (select min(s.starts_at) from sessions s),
    'last_session_at', (select max(coalesce(s.ends_at, s.starts_at)) from sessions s),
    'venue_location', (select s.location_text from sessions s where s.location_text is not null and btrim(s.location_text) <> '' order by s.session_number limit 1),
    'can_manage', (select can_manage from manage_check)
  )
$$;
revoke all on function private.program_run_json(public.program_runs) from public, anon, authenticated;

-- =============================================================================
-- 3. Public RPC: create_program_run
--    Add reporting metadata parameters with defaults
-- =============================================================================

drop function if exists public.create_program_run(uuid, text, text, integer, text, text[], text);

create or replace function public.create_program_run(
  p_organization_id uuid,
  p_program_code text,
  p_title text,
  p_session_count integer default null,
  p_chapter_code text default null,
  p_section_codes text[] default '{}'::text[],
  p_description text default null,
  p_include_in_quarterly_report boolean default false,
  p_report_priority text default 'routine',
  p_report_highlight text default null
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

  if p_report_priority is not null and p_report_priority not in ('routine', 'ministry_activity', 'major_highlight') then
    raise exception using errcode = '22023', message = 'Report priority must be routine, ministry_activity, or major_highlight.';
  end if;
  if p_report_highlight is not null and length(btrim(p_report_highlight)) > 2000 then
    raise exception using errcode = '22023', message = 'Report highlight cannot exceed 2000 characters.';
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
    audience_node_id, session_count, run_status, created_by_profile_id, updated_by_profile_id,
    include_in_quarterly_report, report_priority, report_highlight
  ) values (
    p_organization_id, p_program_code, btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''), v_chapter, v_sections,
    v_audience, v_sessions, 'planned', v_actor, v_actor,
    coalesce(p_include_in_quarterly_report, false),
    coalesce(p_report_priority, 'routine'),
    nullif(btrim(coalesce(p_report_highlight, '')), '')
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
    p_metadata         => jsonb_build_object(
      'program_code', v_run.program_code,
      'session_count', v_run.session_count,
      'chapter_node_id', v_run.chapter_node_id,
      'section_node_ids', to_jsonb(v_run.section_node_ids),
      'include_in_quarterly_report', v_run.include_in_quarterly_report,
      'report_priority', v_run.report_priority
    )
  );

  return jsonb_build_object('status', 'success', 'run', private.program_run_json(v_run));
end;
$$;
revoke all on function public.create_program_run(uuid, text, text, integer, text, text[], text, boolean, text, text) from public, anon;
grant execute on function public.create_program_run(uuid, text, text, integer, text, text[], text, boolean, text, text) to authenticated;

-- =============================================================================
-- 4. Public RPC: update_program_run
--    Add reporting metadata parameters
-- =============================================================================

drop function if exists public.update_program_run(uuid, uuid, text, text);

create or replace function public.update_program_run(
  p_organization_id uuid,
  p_run_id uuid,
  p_title text,
  p_description text default null,
  p_include_in_quarterly_report boolean default null,
  p_report_priority text default null,
  p_report_highlight text default null
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

  if p_report_priority is not null and p_report_priority not in ('routine', 'ministry_activity', 'major_highlight') then
    raise exception using errcode = '22023', message = 'Report priority must be routine, ministry_activity, or major_highlight.';
  end if;
  if p_report_highlight is not null and length(btrim(p_report_highlight)) > 2000 then
    raise exception using errcode = '22023', message = 'Report highlight cannot exceed 2000 characters.';
  end if;

  update public.program_runs
  set title = btrim(p_title),
      description = nullif(btrim(coalesce(p_description, '')), ''),
      include_in_quarterly_report = coalesce(p_include_in_quarterly_report, include_in_quarterly_report),
      report_priority = coalesce(p_report_priority, report_priority),
      report_highlight = case when p_report_highlight is not null then nullif(btrim(p_report_highlight), '') else report_highlight end,
      updated_by_profile_id = v_actor,
      updated_at = now()
  where id = p_run_id
  returning * into v_run;

  -- Keep session titles in step with the program title
  update public.events
  set title = case when v_run.session_count = 1 then v_run.title else v_run.title || ' – Session ' || session_number end,
      updated_by_profile_id = v_actor,
      updated_at = now()
  where program_run_id = p_run_id;

  perform private.write_audit_event(
    p_organization_id => p_organization_id,
    p_event_code => 'program.run.updated',
    p_event_category => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type => 'program_run',
    p_entity_id => p_run_id,
    p_action => 'update',
    p_outcome => 'success',
    p_access_reason => null,
    p_correlation_id => null,
    p_metadata => jsonb_build_object(
      'include_in_quarterly_report', v_run.include_in_quarterly_report,
      'report_priority', v_run.report_priority
    )
  );

  return jsonb_build_object('status', 'success', 'run', private.program_run_json(v_run));
end;
$$;
revoke all on function public.update_program_run(uuid, uuid, text, text, boolean, text, text) from public, anon;
grant execute on function public.update_program_run(uuid, uuid, text, text, boolean, text, text) to authenticated;

-- =============================================================================
-- 5. Public RPC: list_program_runs
--    Add date range and quarterly reporting filtering
-- =============================================================================

drop function if exists public.list_program_runs(uuid, boolean);

create or replace function public.list_program_runs(
  p_organization_id uuid,
  p_include_closed boolean default false,
  p_from date default null,
  p_to date default null,
  p_quarterly_only boolean default false
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
      select jsonb_agg(private.program_run_json(r) order by coalesce(
        (select min(e.starts_at) from public.events e where e.program_run_id = r.id and e.event_status <> 'cancelled'),
        r.created_at
      ) desc)
      from public.program_runs r
      where r.organization_id = p_organization_id
        and (coalesce(p_include_closed, false) or r.run_status in ('planned', 'running'))
        and (not coalesce(p_quarterly_only, false) or r.include_in_quarterly_report = true)
        and (p_from is null or (coalesce(
          (select min(e.starts_at) from public.events e where e.program_run_id = r.id and e.event_status <> 'cancelled'),
          r.created_at
        ) at time zone 'America/New_York')::date >= p_from)
        and (p_to is null or (coalesce(
          (select min(e.starts_at) from public.events e where e.program_run_id = r.id and e.event_status <> 'cancelled'),
          r.created_at
        ) at time zone 'America/New_York')::date <= p_to)
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.list_program_runs(uuid, boolean, date, date, boolean) from public, anon;
grant execute on function public.list_program_runs(uuid, boolean, date, date, boolean) to authenticated;

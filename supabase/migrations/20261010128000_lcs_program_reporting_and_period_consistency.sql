-- =============================================================================
-- Migration: 20261010128000_lcs_program_reporting_and_period_consistency.sql
-- Pass 9.51 correction (forward-only; 126000 and 127000 untouched)
--
--   1. LCS (Life in Christ Seminar / LCSC parish mission) becomes a Program
--      type: program_runs.program_code = 'lcs'. It reuses sessions (Events),
--      program_participants (already supports external non-member people via
--      first_name/last_name), attendance, speakers, service team, photos and
--      reporting metadata. No LCS table; no parallel architecture.
--      Validation: generic Program branch -> 1..30 sessions, chapter optional,
--      sections optional (validated normally when supplied). CLS/Camp rules
--      unchanged.
--   2. list_quarterly_formation_reporting_items returns LCS rows
--      (source_kind = 'lcs') from the explicit program type.
--   3. list_report_activity_photos: Program-level and Program-session photos
--      qualify by the parent Program start date (first non-cancelled session,
--      fallback created_at) - the canonical Program reporting-period rule.
--      Standalone (incl. formation) Event photos continue to use Event date.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Allow program_code 'lcs'
-- -----------------------------------------------------------------------------
alter table public.program_runs drop constraint program_runs_program_code_check;
alter table public.program_runs add constraint program_runs_program_code_check
  check (program_code = any (array['youth_camp'::text, 'discovery_camp'::text, 'cls'::text, 'lcs'::text, 'other_program'::text]));

-- -----------------------------------------------------------------------------
-- 2. create_program_run: accept 'lcs' (generic branch; no CLS chapter/6-9 rule)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_program_run(p_organization_id uuid, p_program_code text, p_title text, p_session_count integer DEFAULT NULL::integer, p_chapter_code text DEFAULT NULL::text, p_section_codes text[] DEFAULT '{}'::text[], p_description text DEFAULT NULL::text, p_include_in_quarterly_report boolean DEFAULT false, p_report_priority text DEFAULT 'routine'::text, p_report_highlight text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
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
  if p_program_code is null or p_program_code not in ('youth_camp', 'discovery_camp', 'cls', 'lcs', 'other_program') then
    raise exception using errcode = '22023', message = 'Program must be youth_camp, discovery_camp, cls, lcs or other_program.';
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

  -- Chapter (optional except for CLS; LCS chapter is optional - parish missions may have none)
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
$function$;
revoke all on function public.create_program_run(uuid, text, text, integer, text, text[], text, boolean, text, text) from public, anon;
grant execute on function public.create_program_run(uuid, text, text, integer, text, text[], text, boolean, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Report-ready photos: Program photos follow the parent Program start date
-- -----------------------------------------------------------------------------
create or replace function public.list_report_activity_photos(
  p_organization_id uuid,
  p_from date,
  p_to date
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  perform private.assert_activity_caller(p_organization_id);
  if p_from is null or p_to is null or p_to < p_from then
    raise exception using errcode = '22023', message = 'Choose a valid reporting period.';
  end if;

  return coalesce((
    select jsonb_agg(x.j order by x.activity_date, x.activity_title, x.report_sort_order, x.sort_order)
    from (
      -- Standalone reportable events (incl. formation events): Event date
      select (private.activity_photo_json(p, true) || jsonb_build_object(
                'activity_kind', 'event', 'activity_id', e.id, 'activity_title', e.title,
                'activity_type', e.event_type, 'activity_date', e.starts_at)) as j,
             e.starts_at as activity_date, e.title as activity_title, p.report_sort_order, p.sort_order
      from public.activity_photos p
      join public.events e on e.id = p.event_id
      where p.organization_id = p_organization_id
        and p.include_in_quarterly_report
        and e.program_run_id is null
        and e.include_in_quarterly_report
        and e.event_status <> 'cancelled'
        and (e.starts_at at time zone 'America/New_York')::date between p_from and p_to
        and private.can_manage_activity_event(p_organization_id, e.id)
      union all
      -- Reportable programs (program-level + session photos): parent Program start date
      select (private.activity_photo_json(p, true) || jsonb_build_object(
                'activity_kind', 'program', 'activity_id', r.id, 'activity_title', r.title,
                'activity_type', r.program_code, 'activity_date', fs.start_at)) as j,
             fs.start_at, r.title, p.report_sort_order, p.sort_order
      from public.activity_photos p
      left join public.events se on se.id = p.event_id
      join public.program_runs r on r.id = coalesce(p.program_run_id, se.program_run_id)
      cross join lateral (
        select coalesce(min(e2.starts_at), r.created_at) as start_at from public.events e2
        where e2.program_run_id = r.id and e2.event_status <> 'cancelled'
      ) fs
      where p.organization_id = p_organization_id
        and p.include_in_quarterly_report
        and (se.id is null or se.event_status <> 'cancelled')
        and r.include_in_quarterly_report
        and r.run_status <> 'cancelled'
        and (fs.start_at at time zone 'America/New_York')::date between p_from and p_to
        and private.can_manage_program_run(p_organization_id, r.id)
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_report_activity_photos(uuid, date, date) from public, anon;
grant execute on function public.list_report_activity_photos(uuid, date, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Reporting-read RPC: CLS + LCS (program_runs) + formation (events)
-- -----------------------------------------------------------------------------
create or replace function public.list_quarterly_formation_reporting_items(
  p_organization_id uuid,
  p_period_start date,
  p_period_end date,
  p_included_only boolean default true
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_items jsonb;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if not private.has_permission('reports.census.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.census.view.';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then
    raise exception using errcode = '22023', message = 'Choose a valid reporting period.';
  end if;

  with cls_runs as (
    select r.*,
           coalesce((select min(e.starts_at) from public.events e
                     where e.program_run_id = r.id and e.event_status <> 'cancelled'),
                    r.created_at) as start_at,
           (select max(coalesce(e.ends_at, e.starts_at)) from public.events e
             where e.program_run_id = r.id and e.event_status <> 'cancelled') as end_at,
           coalesce((select array_agg(e.id) from public.events e
                     where e.program_run_id = r.id and e.event_status <> 'cancelled'), '{}'::uuid[]) as session_ids
    from public.program_runs r
    where r.organization_id = p_organization_id
      and r.program_code in ('cls', 'lcs')
      and r.run_status <> 'cancelled'
      and (not coalesce(p_included_only, true) or r.include_in_quarterly_report)
  ),
  cls_rows as (
    select c.start_at as sort_at, jsonb_build_object(
      'source_kind', c.program_code,
      'source_id', c.id,
      'source_table', 'program_runs',
      'organization_id', c.organization_id,
      'source_title', c.title,
      'program_code', c.program_code,
      'formation_program_code', null,
      'formation_program_title', null,
      'formation_talk_title', null,
      'activity_start_date', (c.start_at at time zone 'America/New_York')::date,
      'activity_end_date', (c.end_at at time zone 'America/New_York')::date,
      'run_status', c.run_status,
      'location', (select e.location_text from public.events e
                   where e.id = any(c.session_ids) and e.location_text is not null and btrim(e.location_text) <> ''
                   order by e.session_number limit 1),
      'meeting_type', (select case when count(distinct e.meeting_type) = 1 then min(e.meeting_type)
                                   when count(distinct e.meeting_type) > 1 then 'mixed' end
                       from public.events e where e.id = any(c.session_ids)),
      'branch_name', (select string_agg(distinct sa.name, ', ')
                      from public.governance_nodes n
                      join public.governance_nodes sa on sa.id = private.node_sub_area(n.id)
                      where n.id = any(c.section_node_ids)),
      'section_names', coalesce((select jsonb_agg(n.name order by n.code) from public.governance_nodes n
                                 where n.id = any(c.section_node_ids)), '[]'::jsonb),
      'chapter_name', (select n.name from public.governance_nodes n where n.id = c.chapter_node_id),
      'audience_name', (select n.name from public.governance_nodes n where n.id = c.audience_node_id),
      'participant_count', (select count(*) from public.program_participants p
                            where p.program_run_id = c.id and p.participant_status = 'registered'),
      'participant_count_is_authoritative', true,
      'attendance_summary', jsonb_build_object(
        'sessions_planned', c.session_count,
        'sessions_scheduled', cardinality(c.session_ids),
        'attendance_instances', (select count(*) from public.program_participant_attendance a
                                 join public.program_participants p on p.id = a.participant_id and p.participant_status = 'registered'
                                 where a.removed_at is null and a.event_id = any(c.session_ids)),
        'participants_with_attendance', (select count(distinct a.participant_id) from public.program_participant_attendance a
                                         join public.program_participants p on p.id = a.participant_id and p.participant_status = 'registered'
                                         where a.removed_at is null and a.event_id = any(c.session_ids))
      ),
      'attendance_count', (select count(distinct a.participant_id) from public.program_participant_attendance a
                           join public.program_participants p on p.id = a.participant_id and p.participant_status = 'registered'
                           where a.removed_at is null and a.event_id = any(c.session_ids)),
      'attendance_count_definition', 'registered participants with at least one recorded attendance in a non-cancelled session',
      'completion_count', null::integer,
      'completion_data_available', false,
      'include_in_quarterly_report', c.include_in_quarterly_report,
      'report_priority', c.report_priority,
      'report_highlight', c.report_highlight,
      'speakers', private.reporting_activity_speakers(c.session_ids, c.id),
      'service_team', private.reporting_activity_service_team(c.session_ids, c.id),
      'selected_photos', private.reporting_activity_selected_photos(c.session_ids, c.id)
    ) as j
    from cls_runs c
    where (c.start_at at time zone 'America/New_York')::date between p_period_start and p_period_end
  ),
  formation_rows as (
    select e.starts_at as sort_at, jsonb_build_object(
      'source_kind', 'formation',
      'source_id', e.id,
      'source_table', 'events',
      'organization_id', e.organization_id,
      'source_title', e.title,
      'program_code', null,
      'formation_program_code', fp.code,
      'formation_program_title', fp.title,
      'formation_talk_title', ft.title,
      'activity_start_date', (e.starts_at at time zone 'America/New_York')::date,
      'activity_end_date', (coalesce(e.ends_at, e.starts_at) at time zone 'America/New_York')::date,
      'run_status', e.event_status,
      'location', nullif(btrim(e.location_text), ''),
      'meeting_type', e.meeting_type,
      'branch_name', (select sa.name from public.governance_nodes sa where sa.id = private.node_sub_area(e.audience_node_id)),
      'section_names', coalesce((select jsonb_build_array(n.name) from public.governance_nodes n where n.id = e.audience_node_id), '[]'::jsonb),
      'chapter_name', null,
      'audience_name', coalesce((select n.name from public.governance_nodes n where n.id = e.audience_node_id), 'All members'),
      'participant_count', null::integer,
      'participant_count_is_authoritative', false,
      'attendance_summary', jsonb_build_object(
        'members_checked_in', (select count(distinct a.member_id) from public.event_attendance a
                               where a.event_id = e.id and a.removed_at is null)
      ),
      'attendance_count', (select count(distinct a.member_id) from public.event_attendance a
                           where a.event_id = e.id and a.removed_at is null),
      'attendance_count_definition', 'distinct members with an active Event attendance record',
      'completion_count', null::integer,
      'completion_data_available', false,
      'include_in_quarterly_report', e.include_in_quarterly_report,
      'report_priority', e.report_priority,
      'report_highlight', e.report_highlight,
      'speakers', private.reporting_activity_speakers(array[e.id], null),
      'service_team', private.reporting_activity_service_team(array[e.id], null),
      'selected_photos', private.reporting_activity_selected_photos(array[e.id], null)
    ) as j
    from public.events e
    left join public.formation_programs fp on fp.id = e.formation_program_id
    left join public.formation_talks ft on ft.id = e.formation_talk_id
    where e.organization_id = p_organization_id
      and e.event_type = 'formation_talk'
      and e.program_run_id is null
      and e.event_status <> 'cancelled'
      and (not coalesce(p_included_only, true) or e.include_in_quarterly_report)
      and (e.starts_at at time zone 'America/New_York')::date between p_period_start and p_period_end
  )
  select coalesce(jsonb_agg(x.j order by x.sort_at, x.j->>'source_title'), '[]'::jsonb)
    into v_items
  from (select * from cls_rows union all select * from formation_rows) x;

  return jsonb_build_object(
    'period_start', p_period_start,
    'period_end', p_period_end,
    'included_only', coalesce(p_included_only, true),
    'lcs_source_available', true,
    'items', v_items
  );
end;
$$;
revoke all on function public.list_quarterly_formation_reporting_items(uuid, date, date, boolean) from public, anon;
grant execute on function public.list_quarterly_formation_reporting_items(uuid, date, date, boolean) to authenticated;

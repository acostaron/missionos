-- =============================================================================
-- Migration: 20261010127000_cls_lcs_formation_reporting_integration.sql
-- Pass 9.51: CLS / LCS / Formation reporting integration (read-only layer)
--
-- Design:
--   * NO new tables / columns. Reporting metadata already exists on the
--     conducted-activity entities (program_runs, events).
--   * One reporting-read RPC normalizes three distinct domains without merging
--     their operational workflows:
--       cls        -> public.program_runs (program_code = 'cls')
--       formation  -> public.events (event_type = 'formation_talk', standalone)
--       lcs        -> NO authoritative structured source exists today; the
--                     source_kind is reserved and zero rows are returned.
--                     Titles are never parsed to infer LCS.
--   * Curriculum (formation_programs / formation_talks) is joined only as a
--     label for an actual conducted Event; it is never a row source.
--   * Member formation progress (member_formation_*_records) is never a row
--     source. Household topics are never a row source.
--   * Completion/graduation is never inferred from attendance:
--     completion_count = NULL, completion_data_available = false.
--   * Authorization: existing reporting permission reports.census.view.
--   * Period rule (New York local date):
--       cls       -> Program start = first non-cancelled session starts_at,
--                    falling back to created_at (Pass 9.48 rule).
--       formation -> Event starts_at.
--   * Cancelled Programs / Events are always excluded.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Private helpers: reporting-safe speakers / service team / selected photos
--    (reuse Pass 9.49 + 9.50 tables; no notes, no contact data, no audit fields)
-- -----------------------------------------------------------------------------
create or replace function private.reporting_activity_speakers(p_event_ids uuid[], p_run_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'speaker_id', s.id,
           'name', coalesce(m.display_name, s.external_name),
           'is_member', s.member_id is not null,
           'external_title', s.external_title,
           'external_organization', s.external_organization,
           'speaker_role', s.speaker_role,
           'topic_title', s.topic_title,
           'session_label', s.session_label,
           'event_id', s.event_id,
           'session_number', e.session_number
         ) order by e.session_number nulls first, s.sort_order, s.created_at), '[]'::jsonb)
  from public.activity_speakers s
  left join public.members m on m.id = s.member_id
  left join public.events e on e.id = s.event_id
  where (p_run_id is not null and s.program_run_id = p_run_id)
     or (s.event_id = any(coalesce(p_event_ids, '{}'::uuid[])))
$$;
revoke all on function private.reporting_activity_speakers(uuid[], uuid) from public, anon, authenticated;

create or replace function private.reporting_activity_service_team(p_event_ids uuid[], p_run_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'assignment_id', a.id,
           'name', coalesce(m.display_name, a.external_name),
           'is_member', a.member_id is not null,
           'role_code', a.role_code,
           'role_label', coalesce(a.role_label, r.label),
           'team_group', a.team_group,
           'event_id', a.event_id,
           'session_number', e.session_number
         ) order by e.session_number nulls first, a.sort_order, a.created_at), '[]'::jsonb)
  from public.activity_service_assignments a
  left join public.members m on m.id = a.member_id
  left join public.activity_service_roles r on r.code = a.role_code
  left join public.events e on e.id = a.event_id
  where (p_run_id is not null and a.program_run_id = p_run_id)
     or (a.event_id = any(coalesce(p_event_ids, '{}'::uuid[])))
$$;
revoke all on function private.reporting_activity_service_team(uuid[], uuid) from public, anon, authenticated;

create or replace function private.reporting_activity_selected_photos(p_event_ids uuid[], p_run_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'photo_id', p.id,
           'storage_bucket', p.storage_bucket,
           'storage_path', p.storage_path,
           'caption', p.caption,
           'alt_text', p.alt_text,
           'report_sort_order', p.report_sort_order,
           'event_id', p.event_id,
           'session_number', e.session_number
         ) order by p.report_sort_order nulls last, p.sort_order, p.uploaded_at), '[]'::jsonb)
  from public.activity_photos p
  left join public.events e on e.id = p.event_id
  where p.include_in_quarterly_report
    and ((p_run_id is not null and p.program_run_id = p_run_id)
         or (p.event_id = any(coalesce(p_event_ids, '{}'::uuid[]))))
$$;
revoke all on function private.reporting_activity_selected_photos(uuid[], uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Reporting-read RPC
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
      and r.program_code = 'cls'
      and r.run_status <> 'cancelled'
      and (not coalesce(p_included_only, true) or r.include_in_quarterly_report)
  ),
  cls_rows as (
    select c.start_at as sort_at, jsonb_build_object(
      'source_kind', 'cls',
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
    'lcs_source_available', false,
    'lcs_note', 'No authoritative structured LCS/LCSC source exists in MissionOS yet; no LCS rows are inferred.',
    'items', v_items
  );
end;
$$;
revoke all on function public.list_quarterly_formation_reporting_items(uuid, date, date, boolean) from public, anon;
grant execute on function public.list_quarterly_formation_reporting_items(uuid, date, date, boolean) to authenticated;

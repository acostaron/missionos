-- =============================================================================
-- Migration: 20261010129000_quarterly_national_report_generator.sql
-- Pass 9.52: Quarterly National Report generator
--
-- Design
--   * Reuses ministry_reporting_periods (quarter, dates) and the census snapshot
--     tables. The period's own status remains the CENSUS workflow.
--   * New table ministry_quarterly_reports (one per reporting period) carries the
--     REPORT workflow: draft -> review -> approved (review may return to draft).
--   * Report content is a versioned jsonb document (schema_version = 1) produced
--     by ONE builder: private.build_quarterly_report_document(period_id).
--       draft_document     : rebuilt on "Refresh Draft" (live sources)
--       approved_document  : builder output captured at approval; immutable
--   * Approval is blocked unless the period's census snapshot exists AND the
--     census period is approved (no live-membership fallback).
--   * Permissions: reports.quarterly.view / manage / approve (org admin only).
--   * No binaries stored; exports are generated client-side from the document.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Permissions
-- -----------------------------------------------------------------------------
insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
) values
  ('reports.quarterly.view', 'View quarterly national reports',
   'Allows viewing quarterly national report previews, approved snapshots, and exports.',
   'reports', 'view', 'organization', 'low', false, false, true),
  ('reports.quarterly.manage', 'Manage quarterly national reports',
   'Allows refreshing draft quarterly reports and submitting them for review.',
   'reports', 'manage', 'organization', 'standard', false, false, true),
  ('reports.quarterly.approve', 'Approve quarterly national reports',
   'Allows approving and freezing quarterly national reports as the historical record.',
   'reports', 'approve', 'organization', 'high', false, true, true)
on conflict (code) do nothing;

insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and r.is_system_role
  and p.code in ('reports.quarterly.view', 'reports.quarterly.manage', 'reports.quarterly.approve')
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

-- -----------------------------------------------------------------------------
-- 2. Report table
-- -----------------------------------------------------------------------------
create table public.ministry_quarterly_reports (
  id                        uuid primary key default gen_random_uuid(),
  organization_id           uuid not null references public.organizations(id) on delete restrict,
  reporting_period_id       uuid not null references public.ministry_reporting_periods(id) on delete restrict,
  status                    text not null default 'draft' check (status in ('draft', 'review', 'approved')),
  schema_version            integer not null default 1 check (schema_version >= 1),
  draft_document            jsonb,
  draft_built_at            timestamptz,
  draft_built_by_profile_id uuid references public.profiles(id) on delete set null,
  submitted_at              timestamptz,
  submitted_by_profile_id   uuid references public.profiles(id) on delete set null,
  approved_document         jsonb,
  approved_at               timestamptz,
  approved_by_profile_id    uuid references public.profiles(id) on delete set null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint uq_quarterly_report_period unique (reporting_period_id),
  constraint chk_quarterly_report_approval check (
    (status = 'approved' and approved_document is not null and approved_at is not null and approved_by_profile_id is not null)
    or (status in ('draft', 'review') and approved_document is null and approved_at is null)
  ),
  constraint chk_quarterly_report_review check (status <> 'review' or draft_document is not null)
);
create index idx_quarterly_reports_org on public.ministry_quarterly_reports (organization_id);

alter table public.ministry_quarterly_reports enable row level security;
revoke all on table public.ministry_quarterly_reports from public, anon, authenticated;

create or replace function private.guard_approved_quarterly_report()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if OLD.status = 'approved' then
    raise exception using errcode = '22023',
      message = 'Approved quarterly report is frozen and cannot be modified or deleted.';
  end if;
  return coalesce(NEW, OLD);
end;
$$;
revoke all on function private.guard_approved_quarterly_report() from public, anon, authenticated;

create trigger trg_guard_approved_quarterly_report
  before update or delete on public.ministry_quarterly_reports
  for each row execute function private.guard_approved_quarterly_report();

-- -----------------------------------------------------------------------------
-- 3. Pass 9.51 formation/CLS/LCS items: internal builder + unchanged public RPC
-- -----------------------------------------------------------------------------
create or replace function private.quarterly_formation_items(
  p_organization_id uuid,
  p_period_start date,
  p_period_end date,
  p_included_only boolean default true
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_items jsonb;
begin
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
  return v_items;
end;
$$;
revoke all on function private.quarterly_formation_items(uuid, date, date, boolean) from public, anon, authenticated;

-- Public Pass 9.51 RPC: same signature, same authorization, same output shape;
-- now delegates to the shared internal builder.
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

  return jsonb_build_object(
    'period_start', p_period_start,
    'period_end', p_period_end,
    'included_only', coalesce(p_included_only, true),
    'lcs_source_available', true,
    'items', private.quarterly_formation_items(p_organization_id, p_period_start, p_period_end, p_included_only)
  );
end;
$$;
revoke all on function public.list_quarterly_formation_reporting_items(uuid, date, date, boolean) from public, anon;
grant execute on function public.list_quarterly_formation_reporting_items(uuid, date, date, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Generic reportable activities (standalone non-formation Events and
--    non-CLS/LCS Programs). Program sessions never appear as Events; formation
--    Events and CLS/LCS Programs are reported only in the formation section.
-- -----------------------------------------------------------------------------
create or replace function private.quarterly_report_activity_items(
  p_organization_id uuid,
  p_period_start date,
  p_period_end date
) returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with ev as (
    select e.starts_at as sort_at, e.report_priority, jsonb_build_object(
      'activity_kind', 'event',
      'source_id', e.id,
      'activity_type', e.event_type,
      'title', e.title,
      'activity_start_date', (e.starts_at at time zone 'America/New_York')::date,
      'activity_end_date', (coalesce(e.ends_at, e.starts_at) at time zone 'America/New_York')::date,
      'starts_at', e.starts_at,
      'ends_at', e.ends_at,
      'meeting_type', e.meeting_type,
      'location', nullif(btrim(e.location_text), ''),
      'audience_name', coalesce((select n.name from public.governance_nodes n where n.id = e.audience_node_id), 'All members'),
      'branch_name', (select sa.name from public.governance_nodes sa where sa.id = private.node_sub_area(e.audience_node_id)),
      'section_names', '[]'::jsonb,
      'chapter_name', null,
      'participant_count', null,
      'sessions_scheduled', null,
      'report_priority', e.report_priority,
      'report_highlight', e.report_highlight,
      'speakers', private.reporting_activity_speakers(array[e.id], null),
      'service_team', private.reporting_activity_service_team(array[e.id], null),
      'selected_photos', private.reporting_activity_selected_photos(array[e.id], null)
    ) as j
    from public.events e
    where e.organization_id = p_organization_id
      and e.program_run_id is null
      and e.event_type <> 'formation_talk'
      and e.event_status <> 'cancelled'
      and e.include_in_quarterly_report
      and (e.starts_at at time zone 'America/New_York')::date between p_period_start and p_period_end
  ),
  runs as (
    select r.*,
           coalesce((select min(e.starts_at) from public.events e
                     where e.program_run_id = r.id and e.event_status <> 'cancelled'), r.created_at) as start_at,
           (select max(coalesce(e.ends_at, e.starts_at)) from public.events e
             where e.program_run_id = r.id and e.event_status <> 'cancelled') as end_at,
           coalesce((select array_agg(e.id) from public.events e
                     where e.program_run_id = r.id and e.event_status <> 'cancelled'), '{}'::uuid[]) as session_ids
    from public.program_runs r
    where r.organization_id = p_organization_id
      and r.program_code not in ('cls', 'lcs')
      and r.run_status <> 'cancelled'
      and r.include_in_quarterly_report
  ),
  pr as (
    select r.start_at as sort_at, r.report_priority, jsonb_build_object(
      'activity_kind', 'program',
      'source_id', r.id,
      'activity_type', r.program_code,
      'title', r.title,
      'activity_start_date', (r.start_at at time zone 'America/New_York')::date,
      'activity_end_date', (r.end_at at time zone 'America/New_York')::date,
      'starts_at', r.start_at,
      'ends_at', r.end_at,
      'meeting_type', (select case when count(distinct e.meeting_type) = 1 then min(e.meeting_type)
                                   when count(distinct e.meeting_type) > 1 then 'mixed' end
                       from public.events e where e.id = any(r.session_ids)),
      'location', (select e.location_text from public.events e
                   where e.id = any(r.session_ids) and e.location_text is not null and btrim(e.location_text) <> ''
                   order by e.session_number limit 1),
      'audience_name', (select n.name from public.governance_nodes n where n.id = r.audience_node_id),
      'branch_name', (select string_agg(distinct sa.name, ', ') from public.governance_nodes n
                      join public.governance_nodes sa on sa.id = private.node_sub_area(n.id)
                      where n.id = any(r.section_node_ids)),
      'section_names', coalesce((select jsonb_agg(n.name order by n.code) from public.governance_nodes n
                                 where n.id = any(r.section_node_ids)), '[]'::jsonb),
      'chapter_name', (select n.name from public.governance_nodes n where n.id = r.chapter_node_id),
      'participant_count', (select count(*) from public.program_participants p
                            where p.program_run_id = r.id and p.participant_status = 'registered'),
      'sessions_scheduled', cardinality(r.session_ids),
      'report_priority', r.report_priority,
      'report_highlight', r.report_highlight,
      'speakers', private.reporting_activity_speakers(r.session_ids, r.id),
      'service_team', private.reporting_activity_service_team(r.session_ids, r.id),
      'selected_photos', private.reporting_activity_selected_photos(r.session_ids, r.id)
    ) as j
    from runs r
    where (r.start_at at time zone 'America/New_York')::date between p_period_start and p_period_end
  )
  select coalesce(jsonb_agg(x.j order by
           case x.report_priority when 'major_highlight' then 1 when 'ministry_activity' then 2 else 3 end,
           x.sort_at, x.j->>'title'), '[]'::jsonb)
  from (select * from ev union all select * from pr) x
$$;
revoke all on function private.quarterly_report_activity_items(uuid, date, date) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5. The single report document builder (used by preview, draft, approval)
-- -----------------------------------------------------------------------------
create or replace function private.build_quarterly_report_document(p_reporting_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_period     public.ministry_reporting_periods%rowtype;
  v_snap       public.ministry_census_snapshots%rowtype;
  v_census     jsonb;
  v_activities jsonb;
  v_formation  jsonb;
  v_formation_sorted jsonb;
  v_all        jsonb;
  v_org_name   text;
begin
  select * into v_period from public.ministry_reporting_periods where id = p_reporting_period_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Reporting period not found.';
  end if;
  select name into v_org_name from public.organizations where id = v_period.organization_id;
  select * into v_snap from public.ministry_census_snapshots where reporting_period_id = v_period.id;

  if v_snap.id is null then
    v_census := jsonb_build_object('available', false, 'census_period_status', v_period.status);
  else
    v_census := jsonb_build_object(
      'available', true,
      'census_period_status', v_period.status,
      'census_approved', v_period.status = 'approved',
      'snapshot_id', v_snap.id,
      'snapshot_date', v_snap.snapshot_date,
      'captured_at', v_snap.captured_at,
      'total_active_members', v_snap.total_active_members,
      'uncategorized_active_members', v_snap.uncategorized_active_members,
      'branches', coalesce((
        select jsonb_agg(jsonb_build_object('branch_name', b.branch_name, 'active_member_count', b.total)
                         order by b.first_order)
        from (select coalesce(r.branch_name, 'Other') as branch_name, sum(r.active_member_count)::int as total,
                     min(r.display_order) as first_order
              from public.ministry_census_snapshot_rows r where r.snapshot_id = v_snap.id
              group by coalesce(r.branch_name, 'Other')) b), '[]'::jsonb),
      'sections', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'section_code', r.section_code, 'section_name', r.section_name,
                 'section_category', r.section_category, 'branch_name', r.branch_name,
                 'active_member_count', r.active_member_count) order by r.display_order)
        from public.ministry_census_snapshot_rows r where r.snapshot_id = v_snap.id), '[]'::jsonb)
    );
  end if;

  v_activities := private.quarterly_report_activity_items(v_period.organization_id, v_period.period_start, v_period.period_end);
  v_formation  := private.quarterly_formation_items(v_period.organization_id, v_period.period_start, v_period.period_end, true);
  select coalesce(jsonb_agg(f order by
           case f->>'report_priority' when 'major_highlight' then 1 when 'ministry_activity' then 2 else 3 end,
           f->>'activity_start_date', f->>'source_title'), '[]'::jsonb)
    into v_formation_sorted
  from jsonb_array_elements(v_formation) f;

  v_all := v_activities || v_formation_sorted;

  return jsonb_build_object(
    'schema_version', 1,
    'header', jsonb_build_object(
      'organization_name', 'Missionary Families of Christ',
      'organization_record_name', v_org_name,
      'area_name', 'MFC New York / New York Area',
      'report_title', format('Quarterly National Report - %s Q%s', v_period.period_year, v_period.period_quarter),
      'period_year', v_period.period_year,
      'period_quarter', v_period.period_quarter,
      'period_label', format('%s Q%s', v_period.period_year, v_period.period_quarter),
      'period_start', v_period.period_start,
      'period_end', v_period.period_end,
      'generated_at', now()
    ),
    'census', v_census,
    'major_highlights', coalesce((select jsonb_agg(a) from jsonb_array_elements(v_activities) a
                                  where a->>'report_priority' = 'major_highlight'), '[]'::jsonb),
    'other_activities', coalesce((select jsonb_agg(a) from jsonb_array_elements(v_activities) a
                                  where a->>'report_priority' <> 'major_highlight'), '[]'::jsonb),
    'formation_items', v_formation_sorted,
    'summary', jsonb_build_object(
      'total_active_members', case when v_snap.id is null then null else v_snap.total_active_members end,
      'branch_totals', coalesce(v_census->'branches', '[]'::jsonb),
      'reportable_events', (select count(*) from jsonb_array_elements(v_activities) a where a->>'activity_kind' = 'event'),
      'reportable_programs', (select count(*) from jsonb_array_elements(v_activities) a where a->>'activity_kind' = 'program'),
      'cls_count', (select count(*) from jsonb_array_elements(v_formation) f where f->>'source_kind' = 'cls'),
      'lcs_count', (select count(*) from jsonb_array_elements(v_formation) f where f->>'source_kind' = 'lcs'),
      'formation_count', (select count(*) from jsonb_array_elements(v_formation) f where f->>'source_kind' = 'formation'),
      'cls_registered_participants', (select coalesce(sum((f->>'participant_count')::int), 0) from jsonb_array_elements(v_formation) f where f->>'source_kind' = 'cls'),
      'lcs_registered_participants', (select coalesce(sum((f->>'participant_count')::int), 0) from jsonb_array_elements(v_formation) f where f->>'source_kind' = 'lcs'),
      'known_completions', (select sum((f->>'completion_count')::int) from jsonb_array_elements(v_formation) f
                            where (f->>'completion_data_available')::boolean),
      'completion_known_activities', (select count(*) from jsonb_array_elements(v_formation) f where (f->>'completion_data_available')::boolean),
      'completion_unavailable_activities', (select count(*) from jsonb_array_elements(v_formation) f where not (f->>'completion_data_available')::boolean),
      'selected_photos', (select coalesce(sum(jsonb_array_length(a->'selected_photos')), 0) from jsonb_array_elements(v_all) a),
      'speaker_assignments', (select coalesce(sum(jsonb_array_length(a->'speakers')), 0) from jsonb_array_elements(v_all) a),
      'service_team_assignments', (select coalesce(sum(jsonb_array_length(a->'service_team')), 0) from jsonb_array_elements(v_all) a)
    ),
    'readiness', jsonb_build_object(
      'blocking', jsonb_build_object(
        'census_snapshot_exists', v_snap.id is not null,
        'census_approved', v_period.status = 'approved'
      ),
      'warnings', jsonb_build_object(
        'missing_highlight', (select count(*) from jsonb_array_elements(v_all) a where coalesce(btrim(a->>'report_highlight'), '') = ''),
        'missing_photos', (select count(*) from jsonb_array_elements(v_all) a where jsonb_array_length(a->'selected_photos') = 0),
        'missing_speakers', (select count(*) from jsonb_array_elements(v_all) a where jsonb_array_length(a->'speakers') = 0),
        'missing_service_team', (select count(*) from jsonb_array_elements(v_all) a where jsonb_array_length(a->'service_team') = 0),
        'completion_unavailable', (select count(*) from jsonb_array_elements(v_formation) f where not (f->>'completion_data_available')::boolean)
      )
    )
  );
end;
$$;
revoke all on function private.build_quarterly_report_document(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 6. Helpers
-- -----------------------------------------------------------------------------
create or replace function private.quarterly_report_period_for(p_reporting_period_id uuid, p_permission text)
returns public.ministry_reporting_periods
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_period from public.ministry_reporting_periods where id = p_reporting_period_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Reporting period not found.';
  end if;
  if not private.has_organization_access(v_period.organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  if not private.has_permission(p_permission, v_period.organization_id) then
    raise exception using errcode = '42501', message = format('Access denied: missing required permission %s.', p_permission);
  end if;
  return v_period;
end;
$$;
revoke all on function private.quarterly_report_period_for(uuid, text) from public, anon, authenticated;

create or replace function private.quarterly_report_state_json(p_report public.ministry_quarterly_reports)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select case when p_report.id is null then jsonb_build_object('status', 'not_started')
  else jsonb_build_object(
    'id', p_report.id,
    'status', p_report.status,
    'schema_version', p_report.schema_version,
    'draft_built_at', p_report.draft_built_at,
    'draft_built_by_name', (select pr.display_name from public.profiles pr where pr.id = p_report.draft_built_by_profile_id),
    'submitted_at', p_report.submitted_at,
    'approved_at', p_report.approved_at,
    'approved_by_name', (select pr.display_name from public.profiles pr where pr.id = p_report.approved_by_profile_id)
  ) end
$$;
revoke all on function private.quarterly_report_state_json(public.ministry_quarterly_reports) from public, anon, authenticated;

create or replace function private.quarterly_report_audit(p_period public.ministry_reporting_periods, p_code text, p_action text, p_report_id uuid, p_extra jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  perform private.write_audit_event(
    p_organization_id  => p_period.organization_id,
    p_event_code       => p_code,
    p_event_category   => 'governance',
    p_actor_profile_id => private.current_profile_id(),
    p_entity_type      => 'ministry_quarterly_report',
    p_entity_id        => coalesce(p_report_id, p_period.id),
    p_action           => p_action,
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('reporting_period_id', p_period.id,
                            'period_year', p_period.period_year, 'period_quarter', p_period.period_quarter) || coalesce(p_extra, '{}'::jsonb)
  );
end;
$$;
revoke all on function private.quarterly_report_audit(public.ministry_reporting_periods, text, text, uuid, jsonb) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 7. Public RPCs
-- -----------------------------------------------------------------------------
create or replace function public.list_quarterly_reports(p_organization_id uuid)
returns jsonb
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
  if not private.has_permission('reports.quarterly.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.quarterly.view.';
  end if;
  return jsonb_build_object(
    'can_manage', private.has_permission('reports.quarterly.manage', p_organization_id),
    'can_approve', private.has_permission('reports.quarterly.approve', p_organization_id),
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reporting_period_id', p.id,
        'period_year', p.period_year,
        'period_quarter', p.period_quarter,
        'period_label', format('%s Q%s', p.period_year, p.period_quarter),
        'period_start', p.period_start,
        'period_end', p.period_end,
        'census_status', p.status,
        'census_snapshot_exists', exists (select 1 from public.ministry_census_snapshots s where s.reporting_period_id = p.id),
        'report', private.quarterly_report_state_json(q)
      ) order by p.period_year desc, p.period_quarter desc)
      from public.ministry_reporting_periods p
      left join public.ministry_quarterly_reports q on q.reporting_period_id = p.id
      where p.organization_id = p_organization_id and p.report_type = 'quarterly_national'
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.list_quarterly_reports(uuid) from public, anon;
grant execute on function public.list_quarterly_reports(uuid) to authenticated;

create or replace function public.get_quarterly_report_preview(p_reporting_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
  v_report public.ministry_quarterly_reports%rowtype;
  v_doc    jsonb;
  v_source text;
begin
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.view');
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id;

  if v_report.status = 'approved' then
    v_doc := v_report.approved_document; v_source := 'approved_snapshot';
  elsif v_report.status = 'review' then
    v_doc := v_report.draft_document; v_source := 'review_draft';
  elsif v_report.draft_document is not null then
    v_doc := v_report.draft_document; v_source := 'stored_draft';
  else
    v_doc := private.build_quarterly_report_document(v_period.id); v_source := 'live_preview';
  end if;

  return jsonb_build_object(
    'reporting_period_id', v_period.id,
    'document_source', v_source,
    'report', private.quarterly_report_state_json(v_report),
    'census_status', v_period.status,
    'can_manage', private.has_permission('reports.quarterly.manage', v_period.organization_id),
    'can_approve', private.has_permission('reports.quarterly.approve', v_period.organization_id),
    'document', v_doc
  );
end;
$$;
revoke all on function public.get_quarterly_report_preview(uuid) from public, anon;
grant execute on function public.get_quarterly_report_preview(uuid) to authenticated;

create or replace function public.refresh_quarterly_report_draft(p_reporting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
  v_report public.ministry_quarterly_reports%rowtype;
begin
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.manage');
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id for update;
  if v_report.id is not null and v_report.status <> 'draft' then
    raise exception using errcode = '22023', message = 'Only a draft quarterly report can be refreshed.';
  end if;

  insert into public.ministry_quarterly_reports (organization_id, reporting_period_id, status, draft_document,
    draft_built_at, draft_built_by_profile_id, updated_at)
  values (v_period.organization_id, v_period.id, 'draft', private.build_quarterly_report_document(v_period.id),
    now(), private.current_profile_id(), now())
  on conflict (reporting_period_id) do update set
    draft_document = excluded.draft_document,
    draft_built_at = excluded.draft_built_at,
    draft_built_by_profile_id = excluded.draft_built_by_profile_id,
    updated_at = now()
  returning * into v_report;

  perform private.quarterly_report_audit(v_period, 'quarterly_report.draft_refreshed', 'update', v_report.id);
  return public.get_quarterly_report_preview(v_period.id);
end;
$$;
revoke all on function public.refresh_quarterly_report_draft(uuid) from public, anon;
grant execute on function public.refresh_quarterly_report_draft(uuid) to authenticated;

create or replace function public.submit_quarterly_report_for_review(p_reporting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
  v_report public.ministry_quarterly_reports%rowtype;
begin
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.manage');
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id for update;
  if v_report.id is null or v_report.status <> 'draft' or v_report.draft_document is null then
    raise exception using errcode = '22023', message = 'Refresh the draft before submitting it for review.';
  end if;
  update public.ministry_quarterly_reports
     set status = 'review', submitted_at = now(), submitted_by_profile_id = private.current_profile_id(), updated_at = now()
   where id = v_report.id;
  perform private.quarterly_report_audit(v_period, 'quarterly_report.submitted_for_review', 'update', v_report.id);
  return public.get_quarterly_report_preview(v_period.id);
end;
$$;
revoke all on function public.submit_quarterly_report_for_review(uuid) from public, anon;
grant execute on function public.submit_quarterly_report_for_review(uuid) to authenticated;

create or replace function public.return_quarterly_report_to_draft(p_reporting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
  v_report public.ministry_quarterly_reports%rowtype;
begin
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.view');
  if not (private.has_permission('reports.quarterly.manage', v_period.organization_id)
          or private.has_permission('reports.quarterly.approve', v_period.organization_id)) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.quarterly.manage.';
  end if;
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id for update;
  if v_report.id is null or v_report.status <> 'review' then
    raise exception using errcode = '22023', message = 'Only a report in review can be returned to draft.';
  end if;
  update public.ministry_quarterly_reports
     set status = 'draft', submitted_at = null, submitted_by_profile_id = null, updated_at = now()
   where id = v_report.id;
  perform private.quarterly_report_audit(v_period, 'quarterly_report.returned_to_draft', 'update', v_report.id);
  return public.get_quarterly_report_preview(v_period.id);
end;
$$;
revoke all on function public.return_quarterly_report_to_draft(uuid) from public, anon;
grant execute on function public.return_quarterly_report_to_draft(uuid) to authenticated;

create or replace function public.approve_quarterly_report(p_reporting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
  v_report public.ministry_quarterly_reports%rowtype;
  v_doc    jsonb;
  v_actor  uuid := private.current_profile_id();
begin
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.approve');
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id for update;
  if v_report.id is null or v_report.status <> 'review' then
    raise exception using errcode = '22023', message = 'Only a quarterly report in review can be approved.';
  end if;
  if not exists (select 1 from public.ministry_census_snapshots s where s.reporting_period_id = v_period.id) then
    raise exception using errcode = '22023', message = 'Cannot approve: no census snapshot exists for this quarter.';
  end if;
  if v_period.status <> 'approved' then
    raise exception using errcode = '22023', message = 'Cannot approve: the quarterly census must be approved first.';
  end if;

  v_doc := private.build_quarterly_report_document(v_period.id);
  v_doc := v_doc || jsonb_build_object('approval', jsonb_build_object(
    'approved_at', now(),
    'approved_by_profile_id', v_actor,
    'approved_by_name', (select pr.display_name from public.profiles pr where pr.id = v_actor)
  ));

  update public.ministry_quarterly_reports
     set status = 'approved', approved_document = v_doc, approved_at = now(),
         approved_by_profile_id = v_actor, updated_at = now()
   where id = v_report.id;

  perform private.quarterly_report_audit(v_period, 'quarterly_report.approved', 'approve', v_report.id);
  return public.get_quarterly_report_preview(v_period.id);
end;
$$;
revoke all on function public.approve_quarterly_report(uuid) from public, anon;
grant execute on function public.approve_quarterly_report(uuid) to authenticated;

create or replace function public.get_quarterly_report_snapshot(p_reporting_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
  v_report public.ministry_quarterly_reports%rowtype;
begin
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.view');
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id;
  if v_report.status is distinct from 'approved' then
    raise exception using errcode = 'P0002', message = 'No approved quarterly report exists for this quarter.';
  end if;
  return jsonb_build_object('reporting_period_id', v_period.id, 'report', private.quarterly_report_state_json(v_report),
                            'document', v_report.approved_document);
end;
$$;
revoke all on function public.get_quarterly_report_snapshot(uuid) from public, anon;
grant execute on function public.get_quarterly_report_snapshot(uuid) to authenticated;

create or replace function public.record_quarterly_report_export(p_reporting_period_id uuid, p_format text)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
  v_report public.ministry_quarterly_reports%rowtype;
begin
  if p_format is null or p_format not in ('pdf', 'xlsx') then
    raise exception using errcode = '22023', message = 'Export format must be pdf or xlsx.';
  end if;
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.view');
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id;
  perform private.quarterly_report_audit(v_period,
    case when p_format = 'pdf' then 'quarterly_report.exported_pdf' else 'quarterly_report.exported_excel' end,
    'export', v_report.id,
    jsonb_build_object('official', coalesce(v_report.status = 'approved', false)));
end;
$$;
revoke all on function public.record_quarterly_report_export(uuid, text) from public, anon;
grant execute on function public.record_quarterly_report_export(uuid, text) to authenticated;

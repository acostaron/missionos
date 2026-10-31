-- =============================================================================
-- Migration: 20261010118000_quarterly_reporting_census_rpc_corrections.sql
-- Domain: Reporting (Pass 9.46V Migration Integrity Repair)
--
-- Formalizes post-push RPC function body corrections for:
--   1. public.list_reporting_periods(p_organization_id uuid)
--   2. public.get_reporting_period(p_reporting_period_id uuid)
--
-- Context:
--   In migration 20261010117000, creator/approver name resolution in these two RPCs
--   referenced `cp.email` / `ap.email` as fallback. In MissionOS, `public.profiles`
--   does not have an `email` column (auth emails are in `auth.users`).
--   This migration replaces both RPCs with the authoritative definitions that
--   resolve names via `profile_member_links` -> `members.display_name` with
--   safe fallback to `profiles.display_name` or 'User'.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. RPC: list_reporting_periods (corrected profile display name resolution)
-- -----------------------------------------------------------------------------
create or replace function public.list_reporting_periods(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor_profile_id uuid;
  v_periods_json     jsonb;
begin
  -- 1. Authentication
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required.';
  end if;

  -- 2. Organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('reports.census.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.census.view.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                      p.id,
        'organization_id',         p.organization_id,
        'report_type',             p.report_type,
        'period_year',             p.period_year,
        'period_quarter',          p.period_quarter,
        'period_start',            p.period_start,
        'period_end',              p.period_end,
        'status',                  p.status,
        'notes',                   p.notes,
        'created_at',              p.created_at,
        'created_by_profile_id',   p.created_by_profile_id,
        'created_by_name',         creator.display_name,
        'updated_at',              p.updated_at,
        'updated_by_profile_id',   p.updated_by_profile_id,
        'approved_at',             p.approved_at,
        'approved_by_profile_id',  p.approved_by_profile_id,
        'approved_by_name',        approver.display_name,
        'snapshot', case
          when s.id is not null then jsonb_build_object(
            'id',                            s.id,
            'snapshot_date',                 s.snapshot_date,
            'captured_at',                   s.captured_at,
            'total_active_members',          s.total_active_members,
            'uncategorized_active_members',  s.uncategorized_active_members
          )
          else null
        end
      )
      order by p.period_year desc, p.period_quarter desc, p.created_at desc
    ),
    '[]'::jsonb
  )
  into v_periods_json
  from public.ministry_reporting_periods p
  left join public.ministry_census_snapshots s on s.reporting_period_id = p.id
  left join public.profiles cp on cp.id = p.created_by_profile_id
  left join lateral (
    select coalesce(m.display_name, cp.display_name, 'User') as display_name
    from public.profile_member_links l
    join public.members m on m.id = l.member_id
    where l.profile_id = p.created_by_profile_id and l.is_primary and l.link_status = 'verified'
    limit 1
  ) creator on true
  left join public.profiles ap on ap.id = p.approved_by_profile_id
  left join lateral (
    select coalesce(m.display_name, ap.display_name, 'User') as display_name
    from public.profile_member_links l
    join public.members m on m.id = l.member_id
    where l.profile_id = p.approved_by_profile_id and l.is_primary and l.link_status = 'verified'
    limit 1
  ) approver on true
  where p.organization_id = p_organization_id;

  return v_periods_json;
end;
$$;

revoke all on function public.list_reporting_periods(uuid) from public, anon;
grant execute on function public.list_reporting_periods(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. RPC: get_reporting_period (corrected profile display name resolution)
-- -----------------------------------------------------------------------------
create or replace function public.get_reporting_period(
  p_reporting_period_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor_profile_id   uuid;
  v_period             public.ministry_reporting_periods%rowtype;
  v_snapshot           public.ministry_census_snapshots%rowtype;
  v_prev_year          integer;
  v_prev_quarter       integer;
  v_prev_snapshot_id   uuid := null;
  v_prev_total         integer := null;
  v_prev_captured_at   timestamptz := null;
  v_prev_status        text := null;
  v_sections_json      jsonb := '[]'::jsonb;
  v_creator_name       text := null;
  v_approver_name      text := null;
begin
  -- 1. Authentication
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required.';
  end if;

  -- 2. Load reporting period
  select * into v_period
  from public.ministry_reporting_periods
  where id = p_reporting_period_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Reporting period not found.';
  end if;

  -- 3. Organization access
  if not private.has_organization_access(v_period.organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- 4. Permission check
  if not private.has_permission('reports.census.view', v_period.organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.census.view.';
  end if;

  -- 5. Resolve creator / approver names
  if v_period.created_by_profile_id is not null then
    select coalesce(m.display_name, cp.display_name, 'User')
    into v_creator_name
    from public.profiles cp
    left join public.profile_member_links l on l.profile_id = cp.id and l.is_primary and l.link_status = 'verified'
    left join public.members m on m.id = l.member_id
    where cp.id = v_period.created_by_profile_id
    limit 1;
  end if;

  if v_period.approved_by_profile_id is not null then
    select coalesce(m.display_name, ap.display_name, 'User')
    into v_approver_name
    from public.profiles ap
    left join public.profile_member_links l on l.profile_id = ap.id and l.is_primary and l.link_status = 'verified'
    left join public.members m on m.id = l.member_id
    where ap.id = v_period.approved_by_profile_id
    limit 1;
  end if;

  -- 6. Load snapshot
  select * into v_snapshot
  from public.ministry_census_snapshots
  where reporting_period_id = v_period.id;

  -- 7. Calculate previous quarter and find previous approved period
  select p_prev_year, p_prev_quarter
  into v_prev_year, v_prev_quarter
  from private.get_previous_quarter(v_period.period_year, v_period.period_quarter);

  select s.id, s.total_active_members, s.captured_at, p.status
  into v_prev_snapshot_id, v_prev_total, v_prev_captured_at, v_prev_status
  from public.ministry_reporting_periods p
  join public.ministry_census_snapshots s on s.reporting_period_id = p.id
  where p.organization_id = v_period.organization_id
    and p.report_type = v_period.report_type
    and p.period_year = v_prev_year
    and p.period_quarter = v_prev_quarter
    and p.status = 'approved'
    and p.id <> v_period.id;

  -- 8. Load snapshot rows with comparison
  if v_snapshot.id is not null then
    with prev_rows as (
      select r.section_node_id, r.active_member_count as prev_count
      from public.ministry_census_snapshot_rows r
      where r.snapshot_id = v_prev_snapshot_id
    )
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'section_node_id',     sr.section_node_id,
          'section_code',        sr.section_code,
          'section_name',        sr.section_name,
          'section_category',    sr.section_category,
          'branch_name',         sr.branch_name,
          'display_order',       sr.display_order,
          'current_count',       sr.active_member_count,
          'previous_count',      pr.prev_count,
          'change_count',        case when pr.prev_count is not null then sr.active_member_count - pr.prev_count else null end,
          'change_percent',      case
                                   when pr.prev_count is not null and pr.prev_count > 0
                                   then round(((sr.active_member_count - pr.prev_count)::numeric / pr.prev_count::numeric) * 100.0, 1)
                                   else null
                                 end
        )
        order by sr.display_order, sr.section_name
      ),
      '[]'::jsonb
    )
    into v_sections_json
    from public.ministry_census_snapshot_rows sr
    left join prev_rows pr on pr.section_node_id = sr.section_node_id
    where sr.snapshot_id = v_snapshot.id;
  end if;

  return jsonb_build_object(
    'period', jsonb_build_object(
      'id',                      v_period.id,
      'organization_id',         v_period.organization_id,
      'report_type',             v_period.report_type,
      'period_year',             v_period.period_year,
      'period_quarter',          v_period.period_quarter,
      'period_start',            v_period.period_start,
      'period_end',              v_period.period_end,
      'status',                  v_period.status,
      'notes',                   v_period.notes,
      'created_at',              v_period.created_at,
      'created_by_profile_id',   v_period.created_by_profile_id,
      'created_by_name',         v_creator_name,
      'updated_at',              v_period.updated_at,
      'updated_by_profile_id',   v_period.updated_by_profile_id,
      'approved_at',             v_period.approved_at,
      'approved_by_profile_id',  v_period.approved_by_profile_id,
      'approved_by_name',        v_approver_name
    ),
    'snapshot', case
      when v_snapshot.id is not null then jsonb_build_object(
        'id',                            v_snapshot.id,
        'snapshot_date',                 v_snapshot.snapshot_date,
        'captured_at',                   v_snapshot.captured_at,
        'captured_by_profile_id',        v_snapshot.captured_by_profile_id,
        'total_active_members',          v_snapshot.total_active_members,
        'uncategorized_active_members',  v_snapshot.uncategorized_active_members,
        'notes',                         v_snapshot.notes
      )
      else null
    end,
    'sections', v_sections_json,
    'previous_quarter', case
      when v_prev_snapshot_id is not null then jsonb_build_object(
        'period_year',           v_prev_year,
        'period_quarter',        v_prev_quarter,
        'status',                v_prev_status,
        'total_active_members',  v_prev_total,
        'captured_at',           v_prev_captured_at
      )
      else null
    end,
    'comparison', case
      when v_snapshot.id is not null and v_prev_total is not null then jsonb_build_object(
        'current_total',         v_snapshot.total_active_members,
        'previous_total',        v_prev_total,
        'change_total',          v_snapshot.total_active_members - v_prev_total,
        'change_percent_total',  case
                                   when v_prev_total > 0
                                   then round(((v_snapshot.total_active_members - v_prev_total)::numeric / v_prev_total::numeric) * 100.0, 1)
                                   else null
                                 end
      )
      else null
    end,
    'reconciled', true
  );
end;
$$;

revoke all on function public.get_reporting_period(uuid) from public, anon;
grant execute on function public.get_reporting_period(uuid) to authenticated;

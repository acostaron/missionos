-- =============================================================================
-- Migration: 20261010117000_quarterly_reporting_census_foundation.sql
-- Phase:     Pass 9.46 — Quarterly Reporting Foundation + Membership Census Snapshot
--
-- Goals:
--   1. Ministry reporting period model (draft, review, approved).
--   2. Census snapshot storage (header + normalized section breakdown rows).
--   3. Authoritative active member census calculation & historical snapshotting.
--   4. Section breakdown preserving branch distinctions (MFC vs FMC).
--   5. Previous approved quarter comparison (counts, change, change %).
--   6. Uncategorized active members visibility & strict reconciliation invariant.
--   7. Approval workflow with snapshot freezing and immutability guards.
--   8. Narrow reports permissions & SECURITY DEFINER RPCs.
-- =============================================================================

begin;

-- =============================================================================
-- 1. Table Definitions
-- =============================================================================

create table if not exists public.ministry_reporting_periods (
  id                      uuid primary key default gen_random_uuid(),
  organization_id         uuid not null references public.organizations(id) on delete restrict,
  report_type             text not null default 'quarterly_national',
  period_year             integer not null check (period_year between 2000 and 2100),
  period_quarter          integer not null check (period_quarter between 1 and 4),
  period_start            date not null,
  period_end              date not null,
  status                  text not null default 'draft' check (status in ('draft', 'review', 'approved')),
  notes                   text,
  created_at              timestamptz not null default now(),
  created_by_profile_id   uuid references public.profiles(id) on delete set null,
  updated_at              timestamptz not null default now(),
  updated_by_profile_id   uuid references public.profiles(id) on delete set null,
  approved_at             timestamptz,
  approved_by_profile_id  uuid references public.profiles(id) on delete set null,

  constraint uq_reporting_period_org_type_yr_qtr
    unique (organization_id, report_type, period_year, period_quarter),
  constraint chk_period_dates
    check (period_start <= period_end),
  constraint chk_period_approval
    check (
      (status = 'approved' and approved_at is not null and approved_by_profile_id is not null)
      or (status in ('draft', 'review'))
    )
);

create table if not exists public.ministry_census_snapshots (
  id                           uuid primary key default gen_random_uuid(),
  reporting_period_id          uuid not null references public.ministry_reporting_periods(id) on delete cascade,
  organization_id              uuid not null references public.organizations(id) on delete restrict,
  snapshot_date                date not null default current_date,
  captured_at                  timestamptz not null default now(),
  captured_by_profile_id       uuid references public.profiles(id) on delete set null,
  total_active_members         integer not null check (total_active_members >= 0),
  uncategorized_active_members integer not null default 0 check (uncategorized_active_members >= 0),
  notes                        text,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),

  constraint uq_census_snapshot_period
    unique (reporting_period_id)
);

create table if not exists public.ministry_census_snapshot_rows (
  id                  uuid primary key default gen_random_uuid(),
  snapshot_id         uuid not null references public.ministry_census_snapshots(id) on delete cascade,
  organization_id     uuid not null references public.organizations(id) on delete restrict,
  section_node_id     uuid not null references public.governance_nodes(id) on delete restrict,
  section_code        text not null,
  section_name        text not null,
  section_category    text,
  branch_name         text,
  display_order       integer not null default 0,
  active_member_count integer not null check (active_member_count >= 0),
  created_at          timestamptz not null default now(),

  constraint uq_census_snapshot_row_section
    unique (snapshot_id, section_node_id)
);

create index if not exists idx_reporting_periods_org
  on public.ministry_reporting_periods (organization_id, period_year desc, period_quarter desc);

create index if not exists idx_census_snapshots_period
  on public.ministry_census_snapshots (reporting_period_id);

create index if not exists idx_census_snapshot_rows_snapshot
  on public.ministry_census_snapshot_rows (snapshot_id, display_order);

-- =============================================================================
-- 2. Row Level Security & Access Hardening
-- =============================================================================

alter table public.ministry_reporting_periods enable row level security;
alter table public.ministry_census_snapshots enable row level security;
alter table public.ministry_census_snapshot_rows enable row level security;

revoke all on table public.ministry_reporting_periods from public, anon, authenticated;
revoke all on table public.ministry_census_snapshots from public, anon, authenticated;
revoke all on table public.ministry_census_snapshot_rows from public, anon, authenticated;

-- =============================================================================
-- 3. Freeze & Immutability Trigger for Approved Periods
-- =============================================================================

create or replace function private.guard_approved_reporting_immutability()
returns trigger
language plpgsql
as $$
declare
  v_status text;
begin
  if TG_TABLE_NAME = 'ministry_reporting_periods' then
    if TG_OP = 'UPDATE' then
      if OLD.status = 'approved' and NEW.status <> 'approved' then
        raise exception using errcode = '22023',
          message = 'Approved reporting period is frozen and cannot be returned to another status.';
      end if;
      if OLD.status = 'approved' and (
        OLD.period_year <> NEW.period_year or
        OLD.period_quarter <> NEW.period_quarter or
        OLD.period_start <> NEW.period_start or
        OLD.period_end <> NEW.period_end or
        OLD.report_type <> NEW.report_type
      ) then
        raise exception using errcode = '22023',
          message = 'Approved reporting period dates and scope are frozen and cannot be modified.';
      end if;
    elsif TG_OP = 'DELETE' then
      if OLD.status = 'approved' then
        raise exception using errcode = '22023',
          message = 'Approved reporting period is frozen and cannot be deleted.';
      end if;
    end if;
    return coalesce(NEW, OLD);
  elsif TG_TABLE_NAME = 'ministry_census_snapshots' then
    if TG_OP in ('UPDATE', 'DELETE') then
      select status into v_status from public.ministry_reporting_periods where id = OLD.reporting_period_id;
      if v_status = 'approved' then
        raise exception using errcode = '22023',
          message = 'Census snapshot for approved reporting period is frozen and cannot be modified or deleted.';
      end if;
    end if;
    return coalesce(NEW, OLD);
  elsif TG_TABLE_NAME = 'ministry_census_snapshot_rows' then
    if TG_OP in ('UPDATE', 'DELETE') then
      select p.status into v_status
      from public.ministry_census_snapshots s
      join public.ministry_reporting_periods p on p.id = s.reporting_period_id
      where s.id = OLD.snapshot_id;
      if v_status = 'approved' then
        raise exception using errcode = '22023',
          message = 'Census snapshot rows for approved reporting period are frozen and cannot be modified or deleted.';
      end if;
    end if;
    return coalesce(NEW, OLD);
  end if;
  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists trg_guard_reporting_period_freeze on public.ministry_reporting_periods;
create trigger trg_guard_reporting_period_freeze
  before update or delete on public.ministry_reporting_periods
  for each row execute function private.guard_approved_reporting_immutability();

drop trigger if exists trg_guard_census_snapshot_freeze on public.ministry_census_snapshots;
create trigger trg_guard_census_snapshot_freeze
  before update or delete on public.ministry_census_snapshots
  for each row execute function private.guard_approved_reporting_immutability();

drop trigger if exists trg_guard_census_snapshot_rows_freeze on public.ministry_census_snapshot_rows;
create trigger trg_guard_census_snapshot_rows_freeze
  before update or delete on public.ministry_census_snapshot_rows
  for each row execute function private.guard_approved_reporting_immutability();

-- =============================================================================
-- 4. Permissions Setup
-- =============================================================================

insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
)
values
  (
    'reports.census.view',
    'View quarterly census reports',
    'Allows viewing quarterly reporting periods, live census preview, and historical census snapshots.',
    'reports',
    'view',
    'organization',
    'low',
    false,
    false,
    true
  ),
  (
    'reports.census.manage',
    'Manage quarterly census reports',
    'Allows creating draft quarterly reporting periods and capturing or refreshing draft census snapshots.',
    'reports',
    'manage',
    'organization',
    'standard',
    false,
    false,
    true
  ),
  (
    'reports.census.approve',
    'Approve quarterly census reports',
    'Allows transitioning reporting periods to review, returning to draft, and approving/freezing quarterly census reports.',
    'reports',
    'approve',
    'organization',
    'high',
    false,
    true,
    true
  )
on conflict (code) do nothing;

-- Role grants: Organization Administrator gets all 3 permissions
insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select
  r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and r.is_system_role
  and p.code in ('reports.census.view', 'reports.census.manage', 'reports.census.approve')
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

-- Role grants: Pastoral leaders get view only
insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select
  r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code in (
    'area_servant',
    'chapter_servant',
    'section_coordinator',
    'area_servant_leader_access',
    'chapter_servant_leader_access'
  )
  and r.is_system_role
  and p.code = 'reports.census.view'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

-- =============================================================================
-- 5. Helper Functions
-- =============================================================================

create or replace function private.get_quarter_dates(
  p_year integer,
  p_quarter integer,
  out p_start_date date,
  out p_end_date date
)
language plpgsql
immutable
as $$
begin
  if p_quarter = 1 then
    p_start_date := make_date(p_year, 1, 1);
    p_end_date   := make_date(p_year, 3, 31);
  elsif p_quarter = 2 then
    p_start_date := make_date(p_year, 4, 1);
    p_end_date   := make_date(p_year, 6, 30);
  elsif p_quarter = 3 then
    p_start_date := make_date(p_year, 7, 1);
    p_end_date   := make_date(p_year, 9, 30);
  elsif p_quarter = 4 then
    p_start_date := make_date(p_year, 10, 1);
    p_end_date   := make_date(p_year, 12, 31);
  else
    raise exception using errcode = '22023', message = 'Invalid quarter: must be between 1 and 4.';
  end if;
end;
$$;

create or replace function private.get_previous_quarter(
  p_year integer,
  p_quarter integer,
  out p_prev_year integer,
  out p_prev_quarter integer
)
language plpgsql
immutable
as $$
begin
  if p_quarter = 1 then
    p_prev_year    := p_year - 1;
    p_prev_quarter := 4;
  else
    p_prev_year    := p_year;
    p_prev_quarter := p_quarter - 1;
  end if;
end;
$$;

-- =============================================================================
-- 6. RPC: get_quarterly_census_preview
-- =============================================================================

create or replace function public.get_quarterly_census_preview(
  p_organization_id uuid,
  p_year integer,
  p_quarter integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor_profile_id       uuid;
  v_start_date             date;
  v_end_date               date;
  v_prev_year              integer;
  v_prev_quarter           integer;
  v_prev_period_id         uuid;
  v_prev_snapshot_id       uuid;
  v_prev_total             integer := null;
  v_prev_captured_at       timestamptz := null;
  v_prev_status            text := null;
  v_existing_period_id     uuid := null;
  v_existing_status        text := null;
  v_existing_snapshot_id   uuid := null;
  v_existing_captured_at   timestamptz := null;
  v_total_active           integer;
  v_uncategorized          integer;
  v_sum_sections           integer := 0;
  v_sections_json          jsonb;
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

  -- 4. Parameter validation
  if p_year is null or p_year < 2000 or p_year > 2100 then
    raise exception using errcode = '22023', message = 'Invalid year: must be between 2000 and 2100.';
  end if;
  if p_quarter is null or p_quarter < 1 or p_quarter > 4 then
    raise exception using errcode = '22023', message = 'Invalid quarter: must be between 1 and 4.';
  end if;

  -- 5. Dates calculation
  select p_start_date, p_end_date
  into v_start_date, v_end_date
  from private.get_quarter_dates(p_year, p_quarter);

  select p_prev_year, p_prev_quarter
  into v_prev_year, v_prev_quarter
  from private.get_previous_quarter(p_year, p_quarter);

  -- 6. Check existing period for this year/quarter
  select p.id, p.status, s.id, s.captured_at
  into v_existing_period_id, v_existing_status, v_existing_snapshot_id, v_existing_captured_at
  from public.ministry_reporting_periods p
  left join public.ministry_census_snapshots s on s.reporting_period_id = p.id
  where p.organization_id = p_organization_id
    and p.report_type = 'quarterly_national'
    and p.period_year = p_year
    and p.period_quarter = p_quarter;

  -- 7. Load previous approved quarterly snapshot for comparison
  select p.id, s.id, s.total_active_members, s.captured_at, p.status
  into v_prev_period_id, v_prev_snapshot_id, v_prev_total, v_prev_captured_at, v_prev_status
  from public.ministry_reporting_periods p
  join public.ministry_census_snapshots s on s.reporting_period_id = p.id
  where p.organization_id = p_organization_id
    and p.report_type = 'quarterly_national'
    and p.period_year = v_prev_year
    and p.period_quarter = v_prev_quarter
    and p.status = 'approved';

  -- 8. Compute live active members count
  select count(distinct m.id)
  into v_total_active
  from public.members m
  join public.member_statuses ms on ms.id = m.membership_status_id
  where m.organization_id = p_organization_id
    and m.record_status = 'active'
    and m.archived_at is null
    and not m.is_deceased
    and ms.is_active_membership = true;

  -- 9. Compute uncategorized active members count
  select count(distinct m.id)
  into v_uncategorized
  from public.members m
  join public.member_statuses ms on ms.id = m.membership_status_id
  where m.organization_id = p_organization_id
    and m.record_status = 'active'
    and m.archived_at is null
    and not m.is_deceased
    and ms.is_active_membership = true
    and (
      m.primary_section_node_id is null
      or not exists (
        select 1
        from public.governance_nodes gn
        join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id and gnt.code = 'section'
        where gn.id = m.primary_section_node_id
          and gn.organization_id = p_organization_id
          and gn.lifecycle_status = 'active'
      )
    );

  -- 10. Compute section breakdown with previous quarter comparison
  with prev_rows as (
    select
      r.section_node_id,
      r.active_member_count as prev_count
    from public.ministry_census_snapshot_rows r
    where r.snapshot_id = v_prev_snapshot_id
  ),
  current_sections as (
    select
      gn.id as section_node_id,
      gn.code as section_code,
      gn.name as section_name,
      s.section_category,
      coalesce(pgn.name, 'Other') as branch_name,
      coalesce(pgn.code, '') as branch_code,
      case
        when coalesce(pgn.code, '') = 'mfc_ny' then 1
        when coalesce(pgn.code, '') = 'fmc_ny' then 2
        else 3
      end as branch_rank,
      case s.section_category
        when 'couples' then 1
        when 'handmaids' then 2
        when 'servants' then 3
        when 'singles' then 4
        when 'campus' then 5
        when 'youth' then 6
        when 'kids' then 7
        else 8
      end as category_rank,
      count(m.id) as live_count
    from public.governance_nodes gn
    join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id and gnt.code = 'section'
    left join public.sections s on s.id = gn.id
    left join public.governance_node_relationships gnr
      on gnr.child_node_id = gn.id
     and gnr.relationship_type = 'primary_parent'
     and gnr.effective_to is null
    left join public.governance_nodes pgn on pgn.id = gnr.parent_node_id
    left join public.members m
      on m.primary_section_node_id = gn.id
     and m.organization_id = p_organization_id
     and m.record_status = 'active'
     and m.archived_at is null
     and not m.is_deceased
     and exists (
       select 1 from public.member_statuses ms
       where ms.id = m.membership_status_id and ms.is_active_membership = true
     )
    where gn.organization_id = p_organization_id
      and gn.lifecycle_status = 'active'
    group by gn.id, gn.code, gn.name, s.section_category, pgn.name, pgn.code
  )
  select
    coalesce(sum(live_count), 0),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'section_node_id',     cs.section_node_id,
          'section_code',        cs.section_code,
          'section_name',        cs.section_name,
          'section_category',    cs.section_category,
          'branch_name',         cs.branch_name,
          'branch_code',         cs.branch_code,
          'current_count',       cs.live_count,
          'previous_count',      pr.prev_count,
          'change_count',        case when pr.prev_count is not null then cs.live_count - pr.prev_count else null end,
          'change_percent',      case
                                   when pr.prev_count is not null and pr.prev_count > 0
                                   then round(((cs.live_count - pr.prev_count)::numeric / pr.prev_count::numeric) * 100.0, 1)
                                   else null
                                 end
        )
        order by cs.branch_rank, cs.category_rank, cs.section_name
      ),
      '[]'::jsonb
    )
  into v_sum_sections, v_sections_json
  from current_sections cs
  left join prev_rows pr on pr.section_node_id = cs.section_node_id;

  -- 11. Strict total reconciliation verification
  if (v_sum_sections + v_uncategorized) <> v_total_active then
    raise exception using errcode = 'P0001',
      message = format('Census reconciliation failed: sum of sections (%s) + uncategorized (%s) <> total active members (%s)',
                       v_sum_sections, v_uncategorized, v_total_active);
  end if;

  return jsonb_build_object(
    'organization_id',               p_organization_id,
    'period_year',                   p_year,
    'period_quarter',                p_quarter,
    'period_start',                  v_start_date,
    'period_end',                    v_end_date,
    'as_of_date',                    current_date,
    'total_active_members',          v_total_active,
    'uncategorized_active_members',  v_uncategorized,
    'reconciled',                    true,
    'sections',                      v_sections_json,
    'previous_quarter', case
      when v_prev_period_id is not null then jsonb_build_object(
        'period_year',           v_prev_year,
        'period_quarter',        v_prev_quarter,
        'status',                v_prev_status,
        'total_active_members',  v_prev_total,
        'captured_at',           v_prev_captured_at
      )
      else null
    end,
    'comparison', case
      when v_prev_total is not null then jsonb_build_object(
        'current_total',         v_total_active,
        'previous_total',        v_prev_total,
        'change_total',          v_total_active - v_prev_total,
        'change_percent_total',  case
                                   when v_prev_total > 0
                                   then round(((v_total_active - v_prev_total)::numeric / v_prev_total::numeric) * 100.0, 1)
                                   else null
                                 end
      )
      else null
    end,
    'existing_period', case
      when v_existing_period_id is not null then jsonb_build_object(
        'id',           v_existing_period_id,
        'status',       v_existing_status,
        'snapshot_id',  v_existing_snapshot_id,
        'captured_at',  v_existing_captured_at
      )
      else null
    end
  );
end;
$$;

revoke all on function public.get_quarterly_census_preview(uuid, integer, integer) from public, anon;
grant execute on function public.get_quarterly_census_preview(uuid, integer, integer) to authenticated;

-- =============================================================================
-- 7. RPC: list_reporting_periods
-- =============================================================================

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
    select coalesce(m.display_name, cp.display_name, cp.email, 'User') as display_name
    from public.profile_member_links l
    join public.members m on m.id = l.member_id
    where l.profile_id = p.created_by_profile_id and l.is_primary and l.link_status = 'verified'
    limit 1
  ) creator on true
  left join public.profiles ap on ap.id = p.approved_by_profile_id
  left join lateral (
    select coalesce(m.display_name, ap.display_name, ap.email, 'User') as display_name
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

-- =============================================================================
-- 8. RPC: get_reporting_period
-- =============================================================================

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
    select coalesce(m.display_name, cp.display_name, cp.email, 'User')
    into v_creator_name
    from public.profiles cp
    left join public.profile_member_links l on l.profile_id = cp.id and l.is_primary and l.link_status = 'verified'
    left join public.members m on m.id = l.member_id
    where cp.id = v_period.created_by_profile_id
    limit 1;
  end if;

  if v_period.approved_by_profile_id is not null then
    select coalesce(m.display_name, ap.display_name, ap.email, 'User')
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

-- =============================================================================
-- 9. RPC: capture_quarterly_census_snapshot (Internal worker + Public RPC)
-- =============================================================================

create or replace function private.execute_census_capture(
  p_reporting_period_id uuid,
  p_actor_profile_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_period             public.ministry_reporting_periods%rowtype;
  v_snapshot_id        uuid;
  v_total_active       integer;
  v_uncategorized      integer;
  v_sum_sections       integer := 0;
  r                    record;
  v_order              integer := 0;
begin
  select * into v_period
  from public.ministry_reporting_periods
  where id = p_reporting_period_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Reporting period not found.';
  end if;

  if v_period.status = 'approved' then
    raise exception using errcode = '22023',
      message = 'Approved reporting period is frozen and cannot be refreshed.';
  end if;

  if v_period.status = 'review' then
    raise exception using errcode = '22023',
      message = 'Reporting period is in review. Return period to draft status before refreshing census snapshot.';
  end if;

  -- 1. Compute total active members
  select count(distinct m.id)
  into v_total_active
  from public.members m
  join public.member_statuses ms on ms.id = m.membership_status_id
  where m.organization_id = v_period.organization_id
    and m.record_status = 'active'
    and m.archived_at is null
    and not m.is_deceased
    and ms.is_active_membership = true;

  -- 2. Compute uncategorized active members
  select count(distinct m.id)
  into v_uncategorized
  from public.members m
  join public.member_statuses ms on ms.id = m.membership_status_id
  where m.organization_id = v_period.organization_id
    and m.record_status = 'active'
    and m.archived_at is null
    and not m.is_deceased
    and ms.is_active_membership = true
    and (
      m.primary_section_node_id is null
      or not exists (
        select 1
        from public.governance_nodes gn
        join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id and gnt.code = 'section'
        where gn.id = m.primary_section_node_id
          and gn.organization_id = v_period.organization_id
          and gn.lifecycle_status = 'active'
      )
    );

  -- 3. Upsert snapshot header
  insert into public.ministry_census_snapshots (
    reporting_period_id,
    organization_id,
    snapshot_date,
    captured_at,
    captured_by_profile_id,
    total_active_members,
    uncategorized_active_members,
    updated_at
  )
  values (
    v_period.id,
    v_period.organization_id,
    current_date,
    now(),
    p_actor_profile_id,
    v_total_active,
    v_uncategorized,
    now()
  )
  on conflict (reporting_period_id) do update set
    snapshot_date                = current_date,
    captured_at                  = now(),
    captured_by_profile_id       = p_actor_profile_id,
    total_active_members         = v_total_active,
    uncategorized_active_members = v_uncategorized,
    updated_at                   = now()
  returning id into v_snapshot_id;

  -- 4. Delete existing rows for this snapshot
  delete from public.ministry_census_snapshot_rows
  where snapshot_id = v_snapshot_id;

  -- 5. Insert section rows preserving branches and category ordering
  for r in (
    select
      gn.id as section_node_id,
      gn.code as section_code,
      gn.name as section_name,
      s.section_category,
      coalesce(pgn.name, 'Other') as branch_name,
      case
        when coalesce(pgn.code, '') = 'mfc_ny' then 1
        when coalesce(pgn.code, '') = 'fmc_ny' then 2
        else 3
      end as branch_rank,
      case s.section_category
        when 'couples' then 1
        when 'handmaids' then 2
        when 'servants' then 3
        when 'singles' then 4
        when 'campus' then 5
        when 'youth' then 6
        when 'kids' then 7
        else 8
      end as category_rank,
      count(m.id) as active_member_count
    from public.governance_nodes gn
    join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id and gnt.code = 'section'
    left join public.sections s on s.id = gn.id
    left join public.governance_node_relationships gnr
      on gnr.child_node_id = gn.id
     and gnr.relationship_type = 'primary_parent'
     and gnr.effective_to is null
    left join public.governance_nodes pgn on pgn.id = gnr.parent_node_id
    left join public.members m
      on m.primary_section_node_id = gn.id
     and m.organization_id = v_period.organization_id
     and m.record_status = 'active'
     and m.archived_at is null
     and not m.is_deceased
     and exists (
       select 1 from public.member_statuses ms
       where ms.id = m.membership_status_id and ms.is_active_membership = true
     )
    where gn.organization_id = v_period.organization_id
      and gn.lifecycle_status = 'active'
    group by gn.id, gn.code, gn.name, s.section_category, pgn.name, pgn.code
    order by branch_rank, category_rank, gn.name
  ) loop
    v_order := v_order + 1;
    v_sum_sections := v_sum_sections + r.active_member_count;

    insert into public.ministry_census_snapshot_rows (
      snapshot_id,
      organization_id,
      section_node_id,
      section_code,
      section_name,
      section_category,
      branch_name,
      display_order,
      active_member_count
    )
    values (
      v_snapshot_id,
      v_period.organization_id,
      r.section_node_id,
      r.section_code,
      r.section_name,
      r.section_category,
      r.branch_name,
      v_order,
      r.active_member_count
    );
  end loop;

  -- 6. Total reconciliation assertion
  if (v_sum_sections + v_uncategorized) <> v_total_active then
    raise exception using errcode = 'P0001',
      message = format('Census reconciliation failed: sum of section rows (%s) + uncategorized (%s) <> total active members (%s)',
                       v_sum_sections, v_uncategorized, v_total_active);
  end if;

  -- 7. Update reporting period timestamp
  update public.ministry_reporting_periods
  set updated_at = now(),
      updated_by_profile_id = p_actor_profile_id
  where id = v_period.id;

  return v_snapshot_id;
end;
$$;

create or replace function public.capture_quarterly_census_snapshot(
  p_reporting_period_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor_profile_id uuid;
  v_org_id           uuid;
begin
  -- 1. Authentication
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required.';
  end if;

  -- 2. Resolve organization
  select organization_id into v_org_id
  from public.ministry_reporting_periods
  where id = p_reporting_period_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Reporting period not found.';
  end if;

  -- 3. Organization access
  if not private.has_organization_access(v_org_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- 4. Permission check
  if not private.has_permission('reports.census.manage', v_org_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.census.manage.';
  end if;

  -- 5. Execute capture
  perform private.execute_census_capture(p_reporting_period_id, v_actor_profile_id);

  return public.get_reporting_period(p_reporting_period_id);
end;
$$;

revoke all on function public.capture_quarterly_census_snapshot(uuid) from public, anon;
grant execute on function public.capture_quarterly_census_snapshot(uuid) to authenticated;

-- =============================================================================
-- 10. RPC: create_draft_reporting_period
-- =============================================================================

create or replace function public.create_draft_reporting_period(
  p_organization_id uuid,
  p_year integer,
  p_quarter integer,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor_profile_id    uuid;
  v_start_date          date;
  v_end_date            date;
  v_reporting_period_id uuid;
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
  if not private.has_permission('reports.census.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.census.manage.';
  end if;

  -- 4. Parameter validation
  if p_year is null or p_year < 2000 or p_year > 2100 then
    raise exception using errcode = '22023', message = 'Invalid year: must be between 2000 and 2100.';
  end if;
  if p_quarter is null or p_quarter < 1 or p_quarter > 4 then
    raise exception using errcode = '22023', message = 'Invalid quarter: must be between 1 and 4.';
  end if;

  -- 5. Calculate quarter boundaries
  select p_start_date, p_end_date
  into v_start_date, v_end_date
  from private.get_quarter_dates(p_year, p_quarter);

  -- 6. Check existing period
  if exists (
    select 1
    from public.ministry_reporting_periods
    where organization_id = p_organization_id
      and report_type = 'quarterly_national'
      and period_year = p_year
      and period_quarter = p_quarter
  ) then
    raise exception using errcode = '23505',
      message = format('A quarterly national reporting period already exists for %s Q%s.', p_year, p_quarter);
  end if;

  -- 7. Insert draft reporting period
  insert into public.ministry_reporting_periods (
    organization_id,
    report_type,
    period_year,
    period_quarter,
    period_start,
    period_end,
    status,
    notes,
    created_by_profile_id,
    updated_by_profile_id
  )
  values (
    p_organization_id,
    'quarterly_national',
    p_year,
    p_quarter,
    v_start_date,
    v_end_date,
    'draft',
    nullif(btrim(p_notes), ''),
    v_actor_profile_id,
    v_actor_profile_id
  )
  returning id into v_reporting_period_id;

  -- 8. Capture initial census snapshot immediately
  perform private.execute_census_capture(v_reporting_period_id, v_actor_profile_id);

  return public.get_reporting_period(v_reporting_period_id);
end;
$$;

revoke all on function public.create_draft_reporting_period(uuid, integer, integer, text) from public, anon;
grant execute on function public.create_draft_reporting_period(uuid, integer, integer, text) to authenticated;

-- =============================================================================
-- 11. RPC: set_reporting_period_status
-- =============================================================================

create or replace function public.set_reporting_period_status(
  p_reporting_period_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor_profile_id uuid;
  v_period           public.ministry_reporting_periods%rowtype;
begin
  -- 1. Authentication
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required.';
  end if;

  -- 2. Validate target status
  if p_status is null or p_status not in ('draft', 'review', 'approved') then
    raise exception using errcode = '22023',
      message = 'Invalid status: must be draft, review, or approved.';
  end if;

  -- 3. Load and lock reporting period
  select * into v_period
  from public.ministry_reporting_periods
  where id = p_reporting_period_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Reporting period not found.';
  end if;

  -- 4. Organization access
  if not private.has_organization_access(v_period.organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- 5. Frozen check: approved periods can NEVER be altered
  if v_period.status = 'approved' then
    raise exception using errcode = '22023',
      message = 'Approved reporting period is frozen and cannot be modified.';
  end if;

  -- 6. Transition rules & permissions
  if p_status = 'draft' then
    if not private.has_permission('reports.census.manage', v_period.organization_id) then
      raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.census.manage.';
    end if;

    update public.ministry_reporting_periods
    set status = 'draft',
        updated_at = now(),
        updated_by_profile_id = v_actor_profile_id
    where id = v_period.id;

  elsif p_status = 'review' then
    if not (
      private.has_permission('reports.census.manage', v_period.organization_id)
      or private.has_permission('reports.census.approve', v_period.organization_id)
    ) then
      raise exception using errcode = '42501', message = 'Access denied: missing required permission to move period to review.';
    end if;

    -- Must have a captured snapshot before review
    if not exists (select 1 from public.ministry_census_snapshots where reporting_period_id = v_period.id) then
      raise exception using errcode = '22023', message = 'Cannot move to review without a captured census snapshot.';
    end if;

    update public.ministry_reporting_periods
    set status = 'review',
        updated_at = now(),
        updated_by_profile_id = v_actor_profile_id
    where id = v_period.id;

  elsif p_status = 'approved' then
    if not private.has_permission('reports.census.approve', v_period.organization_id) then
      raise exception using errcode = '42501', message = 'Access denied: missing required permission reports.census.approve.';
    end if;

    -- Must have a captured snapshot before approval
    if not exists (select 1 from public.ministry_census_snapshots where reporting_period_id = v_period.id) then
      raise exception using errcode = '22023', message = 'Cannot approve reporting period without a captured census snapshot.';
    end if;

    update public.ministry_reporting_periods
    set status = 'approved',
        approved_at = now(),
        approved_by_profile_id = v_actor_profile_id,
        updated_at = now(),
        updated_by_profile_id = v_actor_profile_id
    where id = v_period.id;
  end if;

  return public.get_reporting_period(v_period.id);
end;
$$;

revoke all on function public.set_reporting_period_status(uuid, text) from public, anon;
grant execute on function public.set_reporting_period_status(uuid, text) to authenticated;

commit;

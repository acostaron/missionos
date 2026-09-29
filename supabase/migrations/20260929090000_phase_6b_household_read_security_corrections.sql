-- =============================================================================
-- Migration: 20260929090000_phase_6b_household_read_security_corrections.sql
-- Phase:     Phase 6B-1 — Household Read Security Corrections
--
-- Objectives:
--   1. Harden SECURITY DEFINER search_path across all household read functions
--      to the canonical format: SET search_path = pg_catalog, public, private, auth
--   2. Explicitly reaffirm that pastoral leadership appointments
--      (public.leadership_assignments) NEVER confer application authorization.
--      Application permissions and scopes are strictly derived from
--      profile_role_assignments and profile_scope_assignments.
--   3. Ensure public.get_member_households strictly enforces target member
--      governance scope via private.can_access_member('members.households.view', ...),
--      raising P0002 for out-of-scope members.
--   4. Standardize execute permissions (revoke public/anon, grant authenticated/service_role).
-- =============================================================================

-- =============================================================================
-- SECTION 1: private.can_access_household helper
-- =============================================================================

create or replace function private.can_access_household(
  p_permission_code text,
  p_organization_id uuid,
  p_household_id    uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id         uuid;
  v_is_valid_household boolean;
begin
  -- 1. Caller authentication
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    return false;
  end if;

  -- 2. Organization access
  if not private.has_organization_access(p_organization_id) then
    return false;
  end if;

  -- 3. Household validation:
  --    - Governance node exists
  --    - Node type is 'household'
  --    - public.households detail row exists
  --    - Organization boundary matches
  select exists (
    select 1
    from public.governance_nodes gn
    join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id
     and gnt.organization_id = gn.organization_id
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    where gn.id = p_household_id
      and gn.organization_id = p_organization_id
      and gnt.code = 'household'
  ) into v_is_valid_household;

  if not v_is_valid_household then
    return false;
  end if;

  -- 4. Delegate to governance scope check.
  --    IMPORTANT MISSIONOS ARCHITECTURAL INVARIANT:
  --    Pastoral leadership appointments (public.leadership_assignments) NEVER
  --    grant application authorization. Application permissions and governance
  --    scopes are strictly evaluated from profile_role_assignments and
  --    profile_scope_assignments via private.can_access_governance_node.
  --    Organization-wide software access is granted when caller holds an
  --    organization-level scope (scope_type = 'organization'), NOT by virtue
  --    of a pastoral appointment.
  return private.can_access_governance_node(
    p_permission_code,
    p_organization_id,
    p_household_id
  );
end;
$$;

comment on function private.can_access_household(text, uuid, uuid) is
  'Checks if the authenticated profile has permission and governance scope to access a household. Delegates strictly to private.can_access_governance_node for application authorization.';

revoke execute on function private.can_access_household(text, uuid, uuid) from public, anon;
grant execute on function private.can_access_household(text, uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 2: public.get_household_profile RPC
-- =============================================================================

create or replace function public.get_household_profile(
  p_organization_id uuid,
  p_household_id    uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_has_id_perm  boolean;
  v_profile_data jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('households.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household records.';
  end if;

  -- 4. Governance-scoped access check (indistinguishable P0002 to prevent existence leakage)
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Identifier permission for roster member numbers
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Build profile payload
  with household_identity as (
    select
      gn.id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      gn.effective_from,
      gn.effective_to,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      h.meeting_timezone_name,
      h.meeting_location_type,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.language_code,
      h.is_couple_household
    from public.governance_nodes gn
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    where gn.id = p_household_id
      and gn.organization_id = p_organization_id
  ),
  parent_gov as (
    select
      gnr.parent_node_id,
      pgn.name as parent_node_name,
      pgn.code as parent_node_code,
      pgnt.code as parent_node_type
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    join public.governance_node_types pgnt
      on pgnt.id = pgn.governance_node_type_id
     and pgnt.organization_id = pgn.organization_id
    where gnr.child_node_id = p_household_id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ),
  active_members as (
    select
      hm.id as household_membership_id,
      m.id as member_id,
      case when v_has_id_perm then m.member_number else null end as member_number,
      m.display_name,
      hm.membership_status,
      hm.membership_role,
      hm.is_primary,
      hm.effective_from,
      hm.effective_to
    from public.household_memberships hm
    join public.members m
      on m.id = hm.member_id
     and m.organization_id = hm.organization_id
    where hm.household_node_id = p_household_id
      and hm.organization_id = p_organization_id
      and hm.membership_status in ('active', 'temporary')
      and (hm.effective_to is null or hm.effective_to >= current_date)
    order by
      case when hm.membership_role in ('servant', 'leader') then 0 else 1 end,
      m.display_name asc
  ),
  formal_leaders as (
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from public.leadership_assignments la
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where la.governance_node_id = p_household_id
      and la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and (la.effective_to is null or la.effective_to >= current_date)
    order by coalesce(lrd.display_order, 999) asc, m.display_name asc
  )
  select jsonb_build_object(
    'household', (
      select jsonb_build_object(
        'id', hi.id,
        'name', hi.name,
        'code', hi.code,
        'lifecycle_status', hi.lifecycle_status,
        'household_category', hi.household_category,
        'effective_from', hi.effective_from,
        'effective_to', hi.effective_to,
        'meeting_frequency', hi.meeting_frequency,
        'meeting_day_of_week', hi.meeting_day_of_week,
        'meeting_start_time', hi.meeting_start_time,
        'meeting_timezone_name', hi.meeting_timezone_name,
        'meeting_location_type', hi.meeting_location_type,
        'target_member_count', hi.target_member_count,
        'maximum_member_count', hi.maximum_member_count,
        'accepts_new_members', hi.accepts_new_members,
        'language_code', hi.language_code,
        'is_couple_household', hi.is_couple_household
      )
      from household_identity hi
    ),
    'parent_governance', (
      select case
        when count(pg.*) = 0 then null
        else jsonb_build_object(
          'parent_node_id',   (array_agg(pg.parent_node_id))[1],
          'parent_node_name', (array_agg(pg.parent_node_name))[1],
          'parent_node_code', (array_agg(pg.parent_node_code))[1],
          'parent_node_type', (array_agg(pg.parent_node_type))[1]
        )
      end
      from parent_gov pg
    ),
    'counts', jsonb_build_object(
      'active_member_count',  (select count(*) from active_members),
      'target_member_count',  (select target_member_count from household_identity),
      'maximum_member_count', (select maximum_member_count from household_identity),
      'accepts_new_members',  (select accepts_new_members from household_identity)
    ),
    'leaders', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'leadership_assignment_id', fl.leadership_assignment_id,
            'member_id',                fl.member_id,
            'display_name',             fl.display_name,
            'leadership_role_code',     fl.leadership_role_code,
            'leadership_role_name',     fl.leadership_role_name,
            'assignment_status',        fl.assignment_status,
            'effective_from',           fl.effective_from,
            'effective_to',             fl.effective_to
          )
        )
        from formal_leaders fl
      ),
      '[]'::jsonb
    ),
    'members', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'household_membership_id', am.household_membership_id,
            'member_id',               am.member_id,
            'member_number',           am.member_number,
            'display_name',            am.display_name,
            'membership_status',       am.membership_status,
            'membership_role',         am.membership_role,
            'is_primary',              am.is_primary,
            'effective_from',          am.effective_from,
            'effective_to',            am.effective_to
          )
        )
        from active_members am
      ),
      '[]'::jsonb
    )
  ) into v_profile_data;

  return v_profile_data;
end;
$$;

comment on function public.get_household_profile(uuid, uuid) is
  'Returns browser-safe pastoral household profile details, parent governance node, formal leadership, and current active roster. Requires households.records.view and governance-scoped access.';

revoke execute on function public.get_household_profile(uuid, uuid) from public, anon;
grant execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: public.get_member_households RPC
-- =============================================================================

create or replace function public.get_member_households(
  p_organization_id uuid,
  p_member_id       uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_households jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('members.households.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view member household assignments.';
  end if;

  -- 4. Target Member Scope check (indistinguishable P0002)
  --    Ensures caller has governance-scoped access to the target member.
  --    Chapter/Unit/Household scoped callers cannot query household placement
  --    for out-of-scope members elsewhere in the organization.
  if not private.can_access_member('members.households.view', p_organization_id, p_member_id) then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  -- 5. Query member household assignments
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'household_membership_id', hm.id,
        'household_id',            gn.id,
        'household_name',          gn.name,
        'household_code',          gn.code,
        'household_status',        gn.lifecycle_status,
        'membership_status',       hm.membership_status,
        'membership_role',         hm.membership_role,
        'is_primary',              hm.is_primary,
        'effective_from',          hm.effective_from,
        'effective_to',            hm.effective_to,
        'parent_node_id',          p_gov.parent_node_id,
        'parent_node_name',        p_gov.parent_node_name,
        'parent_node_type',        p_gov.parent_node_type,
        'household_servant_name',  servant.display_name
      )
      order by hm.is_primary desc, hm.effective_from desc
    ),
    '[]'::jsonb
  ) into v_households
  from public.household_memberships hm
  join public.governance_nodes gn
    on gn.id = hm.household_node_id
   and gn.organization_id = hm.organization_id
  join public.households h
    on h.id = gn.id
   and h.organization_id = gn.organization_id
  left join lateral (
    select
      gnr.parent_node_id,
      pgn.name as parent_node_name,
      pgnt.code as parent_node_type
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    join public.governance_node_types pgnt
      on pgnt.id = pgn.governance_node_type_id
     and pgnt.organization_id = pgn.organization_id
    where gnr.child_node_id = gn.id
      and gnr.organization_id = gn.organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ) p_gov on true
  left join lateral (
    select m_lead.display_name
    from public.leadership_assignments la
    join public.members m_lead
      on m_lead.id = la.member_id
     and m_lead.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where la.governance_node_id = gn.id
      and la.organization_id = gn.organization_id
      and la.assignment_status = 'active'
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'household_servant'
    order by la.effective_from desc
    limit 1
  ) servant on true
  where hm.member_id = p_member_id
    and hm.organization_id = p_organization_id
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= current_date);

  return v_households;
end;
$$;

comment on function public.get_member_households(uuid, uuid) is
  'Returns the active pastoral household assignments for a member. Requires members.households.view and member governance scope access.';

revoke execute on function public.get_member_households(uuid, uuid) from public, anon;
grant execute on function public.get_member_households(uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 4: public.search_households RPC
-- =============================================================================

create or replace function public.search_households(
  p_organization_id           uuid,
  p_search                    text default null,
  p_parent_governance_node_id uuid default null,
  p_lifecycle_status          text default 'active',
  p_limit                     integer default 50,
  p_offset                    integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_total      integer;
  v_results    jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('households.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to search household records.';
  end if;

  -- 4. Count total accessible matching households
  select count(*)
  into v_total
  from public.governance_nodes gn
  join public.governance_node_types gnt
    on gnt.id = gn.governance_node_type_id
   and gnt.organization_id = gn.organization_id
  join public.households h
    on h.id = gn.id
   and h.organization_id = gn.organization_id
  left join lateral (
    select gnr.parent_node_id
    from public.governance_node_relationships gnr
    where gnr.child_node_id = gn.id
      and gnr.organization_id = gn.organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ) p_rel on true
  where gn.organization_id = p_organization_id
    and gnt.code = 'household'
    and (p_lifecycle_status is null or gn.lifecycle_status = p_lifecycle_status)
    and (p_parent_governance_node_id is null or p_rel.parent_node_id = p_parent_governance_node_id)
    and (
      p_search is null
      or p_search = ''
      or gn.name ilike '%' || p_search || '%'
      or gn.code ilike '%' || p_search || '%'
    )
    and private.can_access_household('households.records.view', p_organization_id, gn.id);

  -- 5. Query page of matching households
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'household_id',          gn.id,
        'name',                  gn.name,
        'code',                  gn.code,
        'lifecycle_status',      gn.lifecycle_status,
        'household_category',    h.household_category,
        'parent_node_id',        p_gov.parent_node_id,
        'parent_node_name',      p_gov.parent_node_name,
        'parent_node_type',      p_gov.parent_node_type,
        'active_member_count',   coalesce(m_cnt.cnt, 0),
        'target_member_count',   h.target_member_count,
        'maximum_member_count',  h.maximum_member_count,
        'accepts_new_members',   h.accepts_new_members,
        'meeting_frequency',     h.meeting_frequency
      )
      order by gn.name asc
    ),
    '[]'::jsonb
  ) into v_results
  from (
    select gn.id, gn.name, gn.code, gn.lifecycle_status, gn.organization_id
    from public.governance_nodes gn
    join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id
     and gnt.organization_id = gn.organization_id
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    left join lateral (
      select gnr.parent_node_id
      from public.governance_node_relationships gnr
      where gnr.child_node_id = gn.id
        and gnr.organization_id = gn.organization_id
        and gnr.relationship_type = 'primary_parent'
        and gnr.relationship_status = 'active'
        and (gnr.effective_to is null or gnr.effective_to >= current_date)
      order by gnr.effective_from desc
      limit 1
    ) p_rel on true
    where gn.organization_id = p_organization_id
      and gnt.code = 'household'
      and (p_lifecycle_status is null or gn.lifecycle_status = p_lifecycle_status)
      and (p_parent_governance_node_id is null or p_rel.parent_node_id = p_parent_governance_node_id)
      and (
        p_search is null
        or p_search = ''
        or gn.name ilike '%' || p_search || '%'
        or gn.code ilike '%' || p_search || '%'
      )
      and private.can_access_household('households.records.view', p_organization_id, gn.id)
    order by gn.name asc
    limit least(coalesce(p_limit, 50), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  ) gn_paged
  join public.governance_nodes gn
    on gn.id = gn_paged.id
  join public.households h
    on h.id = gn.id
  left join lateral (
    select
      gnr.parent_node_id,
      pgn.name as parent_node_name,
      pgnt.code as parent_node_type
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    join public.governance_node_types pgnt
      on pgnt.id = pgn.governance_node_type_id
     and pgnt.organization_id = pgn.organization_id
    where gnr.child_node_id = gn.id
      and gnr.organization_id = gn.organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ) p_gov on true
  left join lateral (
    select count(*) as cnt
    from public.household_memberships hm
    where hm.household_node_id = gn.id
      and hm.organization_id = gn.organization_id
      and hm.membership_status in ('active', 'temporary')
      and (hm.effective_to is null or hm.effective_to >= current_date)
  ) m_cnt on true;

  return jsonb_build_object(
    'households', v_results,
    'total_count', v_total
  );
end;
$$;

comment on function public.search_households(uuid, text, uuid, text, integer, integer) is
  'Searches pastoral households within the callers governance scope. Requires households.records.view.';

revoke execute on function public.search_households(uuid, text, uuid, text, integer, integer) from public, anon;
grant execute on function public.search_households(uuid, text, uuid, text, integer, integer) to authenticated, service_role;

-- =============================================================================
-- Migration: 20260929080000_phase_6b_household_read_foundation.sql
-- Phase:     Phase 6B-1 — Household Read Foundation
--
-- Summary:
--   1. Seed households.records.view permission in the permissions catalog.
--   2. Assign members.households.view to organization_administrator (retaining
--      existing servant role assignments).
--   3. Assign households.records.view to organization_administrator,
--      area_servant, chapter_servant, unit_servant, and household_servant.
--   4. Implement private.can_access_household(p_permission_code, p_organization_id, p_household_id)
--      validating node existence, node type = 'household', public.households
--      detail row, and delegating to private.can_access_governance_node.
--   5. Implement public.get_household_profile(p_organization_id, p_household_id)
--      returning safe household identity, immediate parent governance, formal
--      leaders, active member roster, and counts.
--   6. Implement public.get_member_households(p_organization_id, p_member_id)
--      returning member household placement array for the Member Profile card.
--   7. Implement public.search_households(p_organization_id, ...)
--      returning scoped household directory records.
--
-- Security:
--   All RPCs are SECURITY DEFINER with fixed search_path.
--   REVOKE EXECUTE from PUBLIC and anon.
--   GRANT EXECUTE to authenticated and service_role.
--   Direct table access remains blocked by RLS and lack of table grants.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Permissions catalog & role assignments
-- =============================================================================

insert into public.permissions (
  code,
  name,
  description,
  domain_code,
  action_code,
  scope_type,
  risk_level,
  requires_access_reason,
  requires_access_logging,
  is_active
)
values (
  'households.records.view',
  'View household records',
  'View household directory and household profile records.',
  'households',
  'view',
  'governance',
  'standard',
  false,
  false,
  true
)
on conflict (code) do update
set
  name                    = excluded.name,
  description             = excluded.description,
  domain_code             = excluded.domain_code,
  action_code             = excluded.action_code,
  scope_type              = excluded.scope_type,
  risk_level              = excluded.risk_level,
  requires_access_reason  = excluded.requires_access_reason,
  requires_access_logging = excluded.requires_access_logging,
  is_active               = excluded.is_active,
  updated_at              = now();

-- Assign members.households.view to organization_administrator
insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  approval_status,
  approved_at,
  approved_by_profile_id,
  created_by_profile_id
)
select
  null,
  ar.id,
  p.id,
  'allow',
  'approved',
  now(),
  null,
  null
from public.app_roles ar
cross join public.permissions p
where ar.code = 'organization_administrator'
  and p.code  = 'members.households.view'
on conflict do nothing;

-- Assign households.records.view to organization_administrator and servant roles
insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  approval_status,
  approved_at,
  approved_by_profile_id,
  created_by_profile_id
)
select
  null,
  ar.id,
  p.id,
  'allow',
  'approved',
  now(),
  null,
  null
from public.app_roles ar
cross join public.permissions p
where ar.code in (
  'organization_administrator',
  'area_servant',
  'chapter_servant',
  'unit_servant',
  'household_servant'
)
  and p.code = 'households.records.view'
on conflict do nothing;

-- =============================================================================
-- SECTION 2: private.can_access_household helper
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
set search_path = pg_catalog, public, auth, private
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
  --    - Public.households detail row exists
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

  -- 4. Delegate to governance scope check
  return private.can_access_governance_node(
    p_permission_code,
    p_organization_id,
    p_household_id
  );
end;
$$;

revoke execute on function private.can_access_household(text, uuid, uuid) from public, anon;
grant execute on function private.can_access_household(text, uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: public.get_household_profile(p_organization_id, p_household_id)
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
  v_profile_id          uuid;
  v_household_rec       record;
  v_can_see_identifiers boolean;
  v_parent_gov          jsonb;
  v_leaders_arr         jsonb;
  v_members_arr         jsonb;
  v_active_count        integer := 0;
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

  -- 4. Scope and validity check (indistinguishable P0002)
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Field-level permission flags
  v_can_see_identifiers := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Load household identity from governance_nodes + households
  select
    gn.id,
    gn.name,
    gn.code,
    gn.lifecycle_status,
    gn.effective_from,
    gn.effective_to,
    h.household_category,
    h.meeting_frequency,
    h.meeting_day_of_week,
    h.meeting_start_time,
    h.meeting_timezone_name,
    h.meeting_location_type,
    h.meeting_location_text,
    h.target_member_count,
    h.maximum_member_count,
    h.accepts_new_members,
    h.language_code,
    h.is_couple_household,
    h.created_at,
    h.updated_at
  into v_household_rec
  from public.governance_nodes gn
  join public.households h
    on h.id = gn.id
   and h.organization_id = gn.organization_id
  where gn.id = p_household_id
    and gn.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 7. Load parent governance node (immediate primary parent: Unit or Chapter)
  select jsonb_build_object(
    'parent_node_id',   gn_p.id,
    'parent_node_name', gn_p.name,
    'parent_node_code', gn_p.code,
    'parent_node_type', gnt_p.code
  )
  into v_parent_gov
  from public.governance_node_relationships r
  join public.governance_nodes gn_p
    on gn_p.id = r.parent_node_id
   and gn_p.organization_id = r.organization_id
  join public.governance_node_types gnt_p
    on gnt_p.id = gn_p.governance_node_type_id
   and gnt_p.organization_id = gn_p.organization_id
  where r.organization_id = p_organization_id
    and r.child_node_id = p_household_id
    and r.is_primary = true
    and r.relationship_status = 'active'
    and r.effective_from <= current_date
    and (r.effective_to is null or r.effective_to >= current_date)
  limit 1;

  -- 8. Load formal leaders from leadership_assignments
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', la.id,
        'member_id',                la.member_id,
        'display_name',             m.display_name,
        'leadership_role_code',     coalesce(lrd.code, 'household_servant'),
        'leadership_role_name',     coalesce(lrd.name, 'Household Servant'),
        'effective_from',           la.effective_from,
        'effective_to',             la.effective_to,
        'assignment_status',        la.assignment_status
      )
      order by la.effective_from asc, m.display_name asc
    ),
    '[]'::jsonb
  )
  into v_leaders_arr
  from public.leadership_assignments la
  join public.members m
    on m.id = la.member_id
   and m.organization_id = la.organization_id
  left join public.leadership_role_definitions lrd
    on lrd.id = la.leadership_role_definition_id
   and lrd.organization_id = la.organization_id
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_household_id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date);

  -- 9. Load active member roster (status IN ('active', 'temporary') and effective_to is null or future)
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'household_membership_id', hm.id,
          'member_id',               m.id,
          'member_number',           case when v_can_see_identifiers then m.member_number else null end,
          'display_name',            m.display_name,
          'membership_status',       hm.membership_status,
          'membership_role',         hm.membership_role,
          'is_primary',              hm.is_primary,
          'effective_from',          hm.effective_from,
          'effective_to',            hm.effective_to
        )
        order by
          case when hm.membership_role in ('servant', 'assistant_servant') then 0 else 1 end,
          hm.membership_role asc,
          m.display_name asc
      ),
      '[]'::jsonb
    ),
    count(hm.id)
  into v_members_arr, v_active_count
  from public.household_memberships hm
  join public.members m
    on m.id = hm.member_id
   and m.organization_id = hm.organization_id
  where hm.organization_id = p_organization_id
    and hm.household_node_id = p_household_id
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= current_date
    and (hm.effective_to is null or hm.effective_to >= current_date);

  return jsonb_build_object(
    'household', jsonb_build_object(
      'id',                    v_household_rec.id,
      'name',                  v_household_rec.name,
      'code',                  v_household_rec.code,
      'lifecycle_status',      v_household_rec.lifecycle_status,
      'household_category',    v_household_rec.household_category,
      'effective_from',        v_household_rec.effective_from,
      'effective_to',          v_household_rec.effective_to,
      'meeting_frequency',     v_household_rec.meeting_frequency,
      'meeting_day_of_week',   v_household_rec.meeting_day_of_week,
      'meeting_start_time',    v_household_rec.meeting_start_time,
      'meeting_timezone_name', v_household_rec.meeting_timezone_name,
      'meeting_location_type', v_household_rec.meeting_location_type,
      'meeting_location_text', v_household_rec.meeting_location_text,
      'target_member_count',   v_household_rec.target_member_count,
      'maximum_member_count',  v_household_rec.maximum_member_count,
      'accepts_new_members',   v_household_rec.accepts_new_members,
      'language_code',         v_household_rec.language_code,
      'is_couple_household',   v_household_rec.is_couple_household,
      'created_at',            v_household_rec.created_at,
      'updated_at',            v_household_rec.updated_at
    ),
    'parent_governance', v_parent_gov,
    'leaders',           coalesce(v_leaders_arr, '[]'::jsonb),
    'members',           coalesce(v_members_arr, '[]'::jsonb),
    'counts',            jsonb_build_object(
      'active_member_count',  v_active_count,
      'target_member_count',  v_household_rec.target_member_count,
      'maximum_member_count', v_household_rec.maximum_member_count,
      'accepts_new_members',  v_household_rec.accepts_new_members
    )
  );
end;
$$;

revoke execute on function public.get_household_profile(uuid, uuid) from public, anon;
grant execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 4: public.get_member_households(p_organization_id, p_member_id)
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

  -- 4. Member scope check (indistinguishable P0002)
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
        'household_servant_name',  lead.servant_name
      )
      order by
        hm.is_primary desc,
        (hm.effective_to is null) desc,
        hm.effective_from desc
    ),
    '[]'::jsonb
  )
  into v_households
  from public.household_memberships hm
  join public.governance_nodes gn
    on gn.id = hm.household_node_id
   and gn.organization_id = hm.organization_id
  -- Lateral join for immediate primary parent node
  left join lateral (
    select
      gn_p.id as parent_node_id,
      gn_p.name as parent_node_name,
      gnt_p.code as parent_node_type
    from public.governance_node_relationships r
    join public.governance_nodes gn_p
      on gn_p.id = r.parent_node_id
     and gn_p.organization_id = r.organization_id
    join public.governance_node_types gnt_p
      on gnt_p.id = gn_p.governance_node_type_id
     and gnt_p.organization_id = gn_p.organization_id
    where r.organization_id = p_organization_id
      and r.child_node_id = hm.household_node_id
      and r.is_primary = true
      and r.relationship_status = 'active'
      and r.effective_from <= current_date
      and (r.effective_to is null or r.effective_to >= current_date)
    limit 1
  ) p_gov on true
  -- Lateral join for current servant display name (from leadership_assignments or membership servant)
  left join lateral (
    select coalesce(
      (
        select m_l.display_name
        from public.leadership_assignments la
        join public.members m_l
          on m_l.id = la.member_id
         and m_l.organization_id = la.organization_id
        join public.leadership_role_definitions lrd
          on lrd.id = la.leadership_role_definition_id
         and lrd.organization_id = la.organization_id
        where la.organization_id = p_organization_id
          and la.governance_node_id = hm.household_node_id
          and la.assignment_status = 'active'
          and lrd.code in ('household_servant', 'H-SERV')
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
        limit 1
      ),
      (
        select m_s.display_name
        from public.household_memberships hm_s
        join public.members m_s
          on m_s.id = hm_s.member_id
         and m_s.organization_id = hm_s.organization_id
        where hm_s.organization_id = p_organization_id
          and hm_s.household_node_id = hm.household_node_id
          and hm_s.membership_role = 'servant'
          and hm_s.membership_status in ('active', 'temporary')
          and hm_s.effective_from <= current_date
          and (hm_s.effective_to is null or hm_s.effective_to >= current_date)
        limit 1
      )
    ) as servant_name
  ) lead on true
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id;

  return v_households;
end;
$$;

revoke execute on function public.get_member_households(uuid, uuid) from public, anon;
grant execute on function public.get_member_households(uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 5: public.search_households(...)
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
  v_profile_id  uuid;
  v_search_term text;
  v_limit       integer;
  v_offset      integer;
  v_households  jsonb;
  v_total_count integer := 0;
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

  -- 4. Sanitize parameters
  v_search_term := nullif(trim(p_search), '');
  v_limit := greatest(1, least(coalesce(p_limit, 50), 100));
  v_offset := greatest(0, coalesce(p_offset, 0));

  -- 5. Query matching scoped households
  with candidate_households as (
    select
      gn.id as household_id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      h.meeting_frequency,
      h.meeting_day_of_week,
      h.meeting_start_time,
      h.meeting_timezone_name,
      h.meeting_location_type,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      p_gov.parent_node_id,
      p_gov.parent_node_name,
      p_gov.parent_node_code,
      p_gov.parent_node_type,
      coalesce(m_cnt.cnt, 0) as active_member_count
    from public.governance_nodes gn
    join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id
     and gnt.organization_id = gn.organization_id
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    left join lateral (
      select
        gn_p.id as parent_node_id,
        gn_p.name as parent_node_name,
        gn_p.code as parent_node_code,
        gnt_p.code as parent_node_type
      from public.governance_node_relationships r
      join public.governance_nodes gn_p
        on gn_p.id = r.parent_node_id
       and gn_p.organization_id = r.organization_id
      join public.governance_node_types gnt_p
        on gnt_p.id = gn_p.governance_node_type_id
       and gnt_p.organization_id = gn_p.organization_id
      where r.organization_id = p_organization_id
        and r.child_node_id = gn.id
        and r.is_primary = true
        and r.relationship_status = 'active'
        and r.effective_from <= current_date
        and (r.effective_to is null or r.effective_to >= current_date)
      limit 1
    ) p_gov on true
    left join lateral (
      select count(*)::integer as cnt
      from public.household_memberships hm
      where hm.organization_id = p_organization_id
        and hm.household_node_id = gn.id
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
    ) m_cnt on true
    where gn.organization_id = p_organization_id
      and gnt.code = 'household'
      and (
        p_lifecycle_status is null
        or p_lifecycle_status = 'all'
        or gn.lifecycle_status = p_lifecycle_status
      )
      and (
        p_parent_governance_node_id is null
        or p_gov.parent_node_id = p_parent_governance_node_id
      )
      and (
        v_search_term is null
        or gn.name ilike '%' || v_search_term || '%'
        or gn.code ilike '%' || v_search_term || '%'
      )
      and private.can_access_household('households.records.view', p_organization_id, gn.id)
  ),
  total_c as (
    select count(*)::integer as total from candidate_households
  ),
  paginated as (
    select * from candidate_households
    order by name asc, code asc
    limit v_limit
    offset v_offset
  )
  select
    coalesce((select total from total_c), 0),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'household_id',          p.household_id,
          'name',                  p.name,
          'code',                  p.code,
          'lifecycle_status',      p.lifecycle_status,
          'household_category',    p.household_category,
          'parent_node_id',        p.parent_node_id,
          'parent_node_name',      p.parent_node_name,
          'parent_node_code',      p.parent_node_code,
          'parent_node_type',      p.parent_node_type,
          'active_member_count',   p.active_member_count,
          'target_member_count',   p.target_member_count,
          'maximum_member_count',  p.maximum_member_count,
          'accepts_new_members',   p.accepts_new_members,
          'meeting_frequency',     p.meeting_frequency,
          'meeting_day_of_week',   p.meeting_day_of_week,
          'meeting_start_time',    p.meeting_start_time,
          'meeting_timezone_name', p.meeting_timezone_name,
          'meeting_location_type', p.meeting_location_type
        )
      ),
      '[]'::jsonb
    )
  into v_total_count, v_households
  from paginated p;

  return jsonb_build_object(
    'households',  coalesce(v_households, '[]'::jsonb),
    'total_count', v_total_count,
    'limit',       v_limit,
    'offset',      v_offset
  );
end;
$$;

revoke execute on function public.search_households(uuid, text, uuid, text, integer, integer) from public, anon;
grant execute on function public.search_households(uuid, text, uuid, text, integer, integer) to authenticated, service_role;

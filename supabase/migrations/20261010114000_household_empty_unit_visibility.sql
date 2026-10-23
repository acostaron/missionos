-- =============================================================================
-- Migration: 20261010114000_household_empty_unit_visibility.sql
-- MissionOS Pass 9.42 — Authoritative Empty Unit Resolution + Scope-Aware Create
--
-- Fixes:
--   1. Server-derived empty unit detection independent of frontend pagination
--      (empty places determined by database household count = 0, not page slice).
--   2. Caller-specific can_create_household flag derived using backend authorization
--      (households.records.create AND private.can_access_governance_node).
--      Scoped leaders see "+ Household" only on units in their permitted subtree.
--
-- Read-only query; public.get_node_paths structural visibility is preserved unchanged.
-- =============================================================================

create or replace function public.get_household_place_slots(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile_id       uuid;
  v_can_create_perm  boolean;
  v_result           jsonb;
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

  -- 3. Check if caller has base households.records.create permission
  v_can_create_perm := private.has_permission('households.records.create', p_organization_id);

  -- 4. Aggregate place slots (active units and unit-less chapters)
  with active_units as (
    select
      gn.id as unit_id,
      gnt.code as place_type
    from public.governance_nodes gn
    join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id
     and gnt.organization_id = gn.organization_id
    where gn.organization_id = p_organization_id
      and gn.lifecycle_status = 'active'
      and (
        gnt.code = 'unit'
        or (
          gnt.code = 'chapter'
          and not exists (
            select 1
            from public.governance_node_relationships r_sub
            join public.governance_nodes un_sub
              on un_sub.id = r_sub.child_node_id
             and un_sub.organization_id = r_sub.organization_id
            join public.governance_node_types unt_sub
              on unt_sub.id = un_sub.governance_node_type_id
             and unt_sub.organization_id = un_sub.organization_id
            where r_sub.organization_id = p_organization_id
              and r_sub.parent_node_id = gn.id
              and r_sub.relationship_type = 'primary_parent'
              and r_sub.relationship_status = 'active'
              and r_sub.effective_from <= current_date
              and (r_sub.effective_to is null or r_sub.effective_to >= current_date)
              and unt_sub.code = 'unit'
              and un_sub.lifecycle_status = 'active'
          )
        )
      )
  ),
  unit_occupancy as (
    select
      u.unit_id,
      count(case when ht.code = 'household' and h.lifecycle_status = 'active' then 1 end)::int as household_count,
      case
        when v_can_create_perm then
          private.can_access_governance_node('households.records.create', p_organization_id, u.unit_id)
        else false
      end as can_create_household
    from active_units u
    left join public.governance_node_relationships r
      on r.organization_id = p_organization_id
     and r.parent_node_id = u.unit_id
     and r.relationship_type = 'primary_parent'
     and r.relationship_status = 'active'
     and r.effective_from <= current_date
     and (r.effective_to is null or r.effective_to >= current_date)
    left join public.governance_nodes h
      on h.id = r.child_node_id
     and h.organization_id = p_organization_id
    left join public.governance_node_types ht
      on ht.id = h.governance_node_type_id
     and ht.organization_id = h.organization_id
    group by u.unit_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'unit_id', o.unit_id,
        'household_count', o.household_count,
        'can_create_household', o.can_create_household
      ) order by o.unit_id
    ),
    '[]'::jsonb
  )
  into v_result
  from unit_occupancy o;

  return v_result;
end;
$$;

revoke all on function public.get_household_place_slots(uuid) from public, anon;
grant execute on function public.get_household_place_slots(uuid) to authenticated;

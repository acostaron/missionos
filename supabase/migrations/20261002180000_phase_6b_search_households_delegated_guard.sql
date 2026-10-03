-- =============================================================================
-- Migration: 20261002180000_phase_6b_search_households_delegated_guard.sql
-- Description: Refines search_households so the Phase 6B-9 double-lock guard
--              specifically targets delegated servant leaders (callers holding
--              delegated servant leader roles or grants), ensuring non-delegated
--              callers evaluate scope via can_access_household filtering.
-- =============================================================================

create or replace function public.search_households(
  p_organization_id           uuid,
  p_search                    text    default null,
  p_lifecycle_status          text    default 'active',
  p_parent_governance_node_id uuid    default null,
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
  v_profile_id   uuid;
  v_search_term  text;
  v_limit        integer;
  v_offset       integer;
  v_total_count  integer;
  v_households   jsonb;
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

  -- NON-ADMIN DELEGATED SERVANT LEADER DOUBLE-LOCK REQUIREMENT (Phase 6B-9)
  -- Applies to callers operating under delegated servant leader access roles or grants.
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if exists (
      select 1
      from public.profile_role_assignments pra
      join public.app_roles ar on ar.id = pra.app_role_id
      where pra.organization_id = p_organization_id
        and pra.profile_id = v_profile_id
        and pra.assignment_status = 'active'
        and ar.code in (
          'household_servant_leader_access',
          'unit_servant_leader_access',
          'chapter_servant_leader_access',
          'area_servant_leader_access'
        )
    ) or exists (
      select 1
      from public.servant_leader_access_grants g
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
    ) then
      if not exists (
        select 1
        from public.servant_leader_access_grants g
        join public.leadership_assignments la on la.id = g.leadership_assignment_id
        where g.organization_id = p_organization_id
          and g.profile_id = v_profile_id
          and g.access_status = 'active'
          and g.effective_from <= current_date
          and (g.effective_to is null or g.effective_to >= current_date)
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
      ) then
        raise exception using errcode = '42501',
          message = 'Active servant leader access grant and current leadership assignment are required.';
      end if;
    end if;
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
      h.pastoral_level,
      case h.pastoral_level
        when 'member'    then 'Member Household'
        when 'unit'      then 'Unit Household'
        when 'chapter'   then 'Chapter Household'
        when 'area'      then 'Area Household'
        when 'fraternal' then 'Fraternal Household'
        else initcap(h.pastoral_level) || ' Household'
      end as pastoral_level_label,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
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
        and r.relationship_type = 'primary_parent'
        and r.relationship_status = 'active'
        and r.effective_from <= current_date
        and (r.effective_to is null or r.effective_to >= current_date)
      order by r.created_at desc
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
        and hm.is_primary = true
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
          'pastoral_level',        p.pastoral_level,
          'pastoral_level_label',  p.pastoral_level_label,
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
    'total_count', v_total_count,
    'limit',       v_limit,
    'offset',      v_offset,
    'households',  v_households
  );
end;
$$;

revoke execute on function public.search_households(uuid, text, text, uuid, integer, integer) from public, anon;
grant execute on function public.search_households(uuid, text, text, uuid, integer, integer) to authenticated, service_role;

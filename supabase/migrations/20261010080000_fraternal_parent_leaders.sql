-- =============================================================================
-- Migration: 20261010080000_fraternal_parent_leaders.sql
-- MissionOS Pass 9.5 (written by Claude, 2026-10-15)
-- Ron: Fraternal households must be workable. Part 1 (this file): the servant leaders of the
-- Area/State a fraternal household sits under count as its responsible leaders (same
-- delegated-access double lock as other levels). This lets them assign/change topics and
-- manage meetings for the fraternal household. Members of the household come in Pass 9.6.
-- Guarded: replaces private.profile_has_direct_servant_leader_responsibility only if the live
-- body is still the 20261002070000 version.
-- =============================================================================
do $guard$
declare
  v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'profile_has_direct_servant_leader_responsibility';
  if v_md5 is distinct from 'fc0785ac8779e4ec1d59ddb552281ff6' then
    raise exception 'STOP: private.profile_has_direct_servant_leader_responsibility differs from 20261002070000 (md5 %).', v_md5;
  end if;
end;
$guard$;

create or replace function private.profile_has_direct_servant_leader_responsibility(
  p_profile_id         uuid,
  p_organization_id    uuid,
  p_household_node_id  uuid,
  p_required_role_code text default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member_id                uuid;
  v_pastoral_level           text;
  v_parent_node_id           uuid;
  v_expected_role            text;
  v_expected_gov_node        uuid;
  v_leadership_assignment_id uuid;
begin
  if p_profile_id is null or p_organization_id is null or p_household_node_id is null then
    return false;
  end if;

  -- 1. Authoritative profile-member link
  select pml.member_id
  into v_member_id
  from public.profile_member_links pml
  where pml.profile_id = p_profile_id
    and pml.organization_id = p_organization_id
    and pml.link_type = 'self'
    and pml.link_status = 'verified'
    and pml.is_primary = true
    and pml.ended_at is null;

  if v_member_id is null then
    return false;
  end if;

  -- 2. Household existence and pastoral level
  select h.pastoral_level, p_rel.parent_node_id
  into v_pastoral_level, v_parent_node_id
  from public.households h
  join public.governance_nodes gn
    on gn.id = h.id
   and gn.organization_id = h.organization_id
  left join lateral (
    select gnr.parent_node_id
    from public.governance_node_relationships gnr
    where gnr.organization_id = p_organization_id
      and gnr.child_node_id = h.id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and gnr.effective_from <= current_date
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.created_at desc
    limit 1
  ) p_rel on true
  where h.id = p_household_node_id
    and h.organization_id = p_organization_id
    and gn.lifecycle_status = 'active';

  if v_pastoral_level is null then
    return false;
  end if;

  -- 3. Fraternal households have no permanent servant leader. Pass 9.5 (Ron's decision):
  --    the servant leaders of the node the fraternal household sits under (its primary parent,
  --    an Area/State) carry responsibility for it, with the same delegated-access double lock.
  if v_pastoral_level = 'fraternal' then
    if v_parent_node_id is null then
      return false;
    end if;
    if p_required_role_code is not null
       and p_required_role_code not in ('area_servant_leader', 'chapter_servant_leader', 'unit_servant_leader') then
      return false;
    end if;
    return exists (
      select 1
      from public.leadership_assignments la
      join public.leadership_role_definitions lrd
        on lrd.id = la.leadership_role_definition_id
      join public.servant_leader_access_grants g
        on g.organization_id = p_organization_id
       and g.profile_id = p_profile_id
       and g.member_id = v_member_id
       and g.leadership_assignment_id = la.id
       and g.governance_node_id = v_parent_node_id
       and g.access_status = 'active'
       and g.effective_from <= current_date
       and (g.effective_to is null or g.effective_to >= current_date)
      where la.organization_id = p_organization_id
        and la.member_id = v_member_id
        and la.governance_node_id = v_parent_node_id
        and lrd.code in ('area_servant_leader', 'chapter_servant_leader', 'unit_servant_leader')
        and (p_required_role_code is null or lrd.code = p_required_role_code)
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date));
  end if;

  -- 4. Map expected role and target governance node
  case v_pastoral_level
    when 'member' then
      v_expected_role := 'household_servant_leader';
      v_expected_gov_node := p_household_node_id;
    when 'unit' then
      v_expected_role := 'unit_servant_leader';
      v_expected_gov_node := v_parent_node_id;
    when 'chapter' then
      v_expected_role := 'chapter_servant_leader';
      v_expected_gov_node := v_parent_node_id;
    when 'area' then
      v_expected_role := 'area_servant_leader';
      v_expected_gov_node := v_parent_node_id;
    else
      return false;
  end case;

  if v_expected_gov_node is null then
    return false;
  end if;

  if p_required_role_code is not null and p_required_role_code != v_expected_role then
    return false;
  end if;

  -- 5. Active leadership assignment check
  select la.id
  into v_leadership_assignment_id
  from public.leadership_assignments la
  join public.leadership_role_definitions lrd
    on lrd.id = la.leadership_role_definition_id
  where la.organization_id = p_organization_id
    and la.member_id = v_member_id
    and la.governance_node_id = v_expected_gov_node
    and lrd.code = v_expected_role
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date);

  if v_leadership_assignment_id is null then
    return false;
  end if;

  -- 6. Active delegated access grant check
  return exists (
    select 1
    from public.servant_leader_access_grants g
    where g.organization_id = p_organization_id
      and g.profile_id = p_profile_id
      and g.member_id = v_member_id
      and g.leadership_assignment_id = v_leadership_assignment_id
      and g.governance_node_id = v_expected_gov_node
      and g.access_status = 'active'
      and g.effective_from <= current_date
      and (g.effective_to is null or g.effective_to >= current_date)
  );
end;
$$;

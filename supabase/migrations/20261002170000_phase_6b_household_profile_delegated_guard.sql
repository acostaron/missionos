-- =============================================================================
-- Migration: 20261002170000_phase_6b_household_profile_delegated_guard.sql
-- Description: Refines get_household_profile so the Phase 6B-9 double-lock guard
--              specifically targets delegated servant leaders (callers holding
--              delegated servant leader roles or grants), ensuring non-delegated
--              callers evaluate scope via can_access_household (P0002 on out-of-scope).
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

  -- 4. Governance-scoped access check
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Identifier permission for roster member numbers
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Build profile payload with pastoral echelon derivation
  with household_identity as (
    select
      gn.id,
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
      case h.pastoral_level
        when 'member'    then 'household_servant_leader'
        when 'unit'      then 'unit_servant_leader'
        when 'chapter'   then 'chapter_servant_leader'
        when 'area'      then 'area_servant_leader'
        when 'fraternal' then 'rotating_facilitation'
      end as leadership_source,
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
    order by
      case when gnr.relationship_status = 'active' and gnr.effective_from <= current_date and (gnr.effective_to is null or gnr.effective_to >= current_date) then 0 else 1 end,
      gnr.effective_to desc nulls first,
      gnr.effective_from desc,
      gnr.created_at desc
    limit 1
  ),
  active_members as (
    select
      hm.id as household_membership_id,
      m.id as member_id,
      case
        when v_has_id_perm then m.member_number
        else null
      end as member_number,
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
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    order by
      case when hm.membership_role in ('servant', 'leader') then 0 else 1 end,
      m.display_name asc
  ),
  derived_leaders as (
    -- Member: from household node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    join public.leadership_assignments la
      on la.governance_node_id = hi.id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'member'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'household_servant_leader'

    union all

    -- Unit: from parent Unit node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'unit'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'unit_servant_leader'

    union all

    -- Chapter: from parent Chapter node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'chapter'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'chapter_servant_leader'

    union all

    -- Area: from parent Area node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'area'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'area_servant_leader'
  ),
  couple_leaders as (
    select
      lead.member_id as servant_member_id,
      lead.display_name as servant_display_name,
      lead.effective_from as servant_effective_from,
      spouse_mem.display_name as spouse_display_name,
      spouse_mem.id as spouse_member_id,
      case hi.pastoral_level
        when 'member'  then 'Household Leaders'
        when 'unit'    then 'Unit Leaders'
        when 'chapter' then 'Chapter Leaders'
        when 'area'    then 'Area Leaders'
      end as couple_title
    from derived_leaders lead
    join household_identity hi on hi.is_couple_household = true
    -- Spousal relationship check
    join public.family_relationships fr
      on fr.organization_id = p_organization_id
     and fr.relationship_status = 'active'
     and fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')
     and (fr.effective_from is null or fr.effective_from <= current_date)
     and (fr.effective_to is null or fr.effective_to >= current_date)
     and (fr.from_member_id = lead.member_id or fr.to_member_id = lead.member_id)
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
     and frt.code = 'spouse'
    cross join lateral (
      values (case when fr.from_member_id = lead.member_id then fr.to_member_id else fr.from_member_id end)
    ) as target_spouse(member_id)
    -- Spouse active member check
    join public.members spouse_mem
      on spouse_mem.id = target_spouse.member_id
     and spouse_mem.organization_id = p_organization_id
     and spouse_mem.record_status = 'active'
     and not spouse_mem.is_deceased
    -- For member households: spouse must also be a member of this household
    left join active_members am_spouse
      on am_spouse.member_id = target_spouse.member_id
    where (hi.pastoral_level != 'member' or am_spouse.member_id is not null)
      and hi.pastoral_level in ('member', 'unit', 'chapter', 'area')
    limit 1
  )
  select jsonb_build_object(
    'household', (
      select jsonb_build_object(
        'id',                    hi.id,
        'name',                  hi.name,
        'code',                  hi.code,
        'lifecycle_status',      hi.lifecycle_status,
        'household_category',    hi.household_category,
        'pastoral_level',        hi.pastoral_level,
        'pastoral_level_label',  hi.pastoral_level_label,
        'leadership_source',     hi.leadership_source,
        'effective_from',        hi.effective_from,
        'effective_to',          hi.effective_to,
        'meeting_frequency',     hi.meeting_frequency,
        'meeting_day_of_week',   hi.meeting_day_of_week,
        'meeting_start_time',    hi.meeting_start_time,
        'meeting_timezone_name', hi.meeting_timezone_name,
        'meeting_location_type', hi.meeting_location_type,
        'target_member_count',   hi.target_member_count,
        'maximum_member_count',  hi.maximum_member_count,
        'accepts_new_members',   hi.accepts_new_members,
        'language_code',         hi.language_code,
        'is_couple_household',   hi.is_couple_household
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
    'leaders', case
      when (select hi.pastoral_level from household_identity hi) = 'fraternal' then '[]'::jsonb
      else coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'leadership_assignment_id', dl.leadership_assignment_id,
              'member_id',                dl.member_id,
              'display_name',             dl.display_name,
              'leadership_role_code',     dl.leadership_role_code,
              'leadership_role_name',     dl.leadership_role_name,
              'assignment_status',        dl.assignment_status,
              'effective_from',           dl.effective_from,
              'effective_to',             dl.effective_to
            )
          )
          from derived_leaders dl
        ),
        '[]'::jsonb
      )
    end,
    'household_leaders', case
      when (select hi.pastoral_level from household_identity hi) = 'fraternal' then null
      else (
        select jsonb_build_object(
          'husband', jsonb_build_object(
            'member_id',    cl.servant_member_id,
            'display_name', cl.servant_display_name
          ),
          'wife', jsonb_build_object(
            'member_id',    cl.spouse_member_id,
            'display_name', cl.spouse_display_name
          ),
          'pastoral_label', cl.couple_title,
          'formatted_names', cl.servant_display_name || ' & ' || cl.spouse_display_name,
          'effective_from', cl.servant_effective_from
        )
        from couple_leaders cl
        limit 1
      )
    end,
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
    ),
    'counts', (
      select jsonb_build_object(
        'active_member_count',  (select count(*) from active_members),
        'target_member_count',  hi.target_member_count,
        'maximum_member_count', hi.maximum_member_count,
        'accepts_new_members',  hi.accepts_new_members
      )
      from household_identity hi
    ),
    -- Backwards-compatibility top-level keys
    'household_id',          (select hi.id from household_identity hi),
    'name',                  (select hi.name from household_identity hi),
    'code',                  (select hi.code from household_identity hi),
    'lifecycle_status',      (select hi.lifecycle_status from household_identity hi),
    'household_category',    (select hi.household_category from household_identity hi),
    'pastoral_level',        (select hi.pastoral_level from household_identity hi),
    'pastoral_level_label',  (select hi.pastoral_level_label from household_identity hi),
    'leadership_source',     (select hi.leadership_source from household_identity hi),
    'effective_from',        (select hi.effective_from from household_identity hi),
    'effective_to',          (select hi.effective_to from household_identity hi),
    'meeting_frequency',     (select hi.meeting_frequency from household_identity hi),
    'meeting_day_of_week',   (select hi.meeting_day_of_week from household_identity hi),
    'meeting_start_time',    (select hi.meeting_start_time from household_identity hi),
    'meeting_timezone_name', (select hi.meeting_timezone_name from household_identity hi),
    'meeting_location_type', (select hi.meeting_location_type from household_identity hi),
    'target_member_count',   (select hi.target_member_count from household_identity hi),
    'maximum_member_count',  (select hi.maximum_member_count from household_identity hi),
    'accepts_new_members',   (select hi.accepts_new_members from household_identity hi),
    'language_code',         (select hi.language_code from household_identity hi),
    'is_couple_household',   (select hi.is_couple_household from household_identity hi),
    'parent_node_id',        (select pg.parent_node_id from parent_gov pg),
    'parent_node_name',      (select pg.parent_node_name from parent_gov pg),
    'parent_node_code',      (select pg.parent_node_code from parent_gov pg),
    'parent_node_type',      (select pg.parent_node_type from parent_gov pg),
    'active_member_count',   (select count(*)::integer from active_members)
  ) into v_profile_data;

  return v_profile_data;
end;
$$;

revoke execute on function public.get_household_profile(uuid, uuid) from public, anon;
grant execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

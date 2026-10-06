-- =============================================================================
-- Migration: 20261002230000_phase_6b_formation_rpc_alignment.sql
-- Phase:     Phase 6B-10 — Household Formation Topics & Spiritual Progress
-- Purpose:   Restores canonical get_household_profile and get_pastoral_operations_dashboard
--            while enriching them with formation topic summaries.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Canonical get_household_profile with formation_summary
-- -----------------------------------------------------------------------------

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

  -- NON-ADMIN DOUBLE-LOCK REQUIREMENT (Phase 6B-9)
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
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
  ),
  formation_info as (
    select
      private.compute_household_formation_status(p_household_id) as formation_status,
      (
        select jsonb_build_object(
          'assignment_id',   a.id,
          'topic_id',        ft.id,
          'title',           ft.title,
          'planned_for_date', a.planned_for_date,
          'sequence_number', a.sequence_number
        )
        from public.household_topic_assignments a
        join public.formation_topics ft on ft.id = a.topic_id
        where a.household_node_id = p_household_id
          and a.assignment_status = 'planned'
        order by a.planned_for_date asc nulls last, a.sequence_number asc nulls last, a.created_at asc
        limit 1
      ) as next_topic,
      (
        select jsonb_build_object(
          'assignment_id', a.id,
          'topic_id',      ft.id,
          'title',         ft.title,
          'completed_at',  a.completed_at,
          'meeting_date',  m.meeting_date
        )
        from public.household_topic_assignments a
        join public.formation_topics ft on ft.id = a.topic_id
        left join public.household_meetings m on m.id = a.completed_household_meeting_id
        where a.household_node_id = p_household_id
          and a.assignment_status = 'completed'
        order by a.completed_at desc
        limit 1
      ) as last_completed_topic,
      (
        select count(*)::integer
        from public.household_topic_assignments
        where household_node_id = p_household_id
          and assignment_status = 'planned'
      ) as planned_topics_count,
      (
        select count(*)::integer
        from public.household_topic_assignments
        where household_node_id = p_household_id
          and assignment_status = 'completed'
      ) as completed_topics_count
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
    'formation_summary', (
      select jsonb_build_object(
        'formation_status',       fi.formation_status,
        'next_topic',             fi.next_topic,
        'last_completed_topic',   fi.last_completed_topic,
        'planned_topics_count',   fi.planned_topics_count,
        'completed_topics_count', fi.completed_topics_count
      )
      from formation_info fi
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

revoke all on function public.get_household_profile(uuid, uuid) from public, anon;
grant execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Canonical get_pastoral_operations_dashboard with formation_operations_summary
-- -----------------------------------------------------------------------------

create or replace function public.get_pastoral_operations_dashboard(
  p_organization_id    uuid,
  p_governance_node_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id             uuid;
  v_is_org_admin           boolean;
  v_caller_member_id       uuid;
  v_caller_display_name    text;
  v_can_review_placement   boolean;
  v_can_view_leadership    boolean;
  v_can_view_roster        boolean;
  v_target_scope_node_id   uuid;
  v_identity_json          jsonb;
  v_serving_assignments    jsonb := '[]'::jsonb;
  v_pastoral_membership    jsonb := null;
  v_care_responsibilities  jsonb := '[]'::jsonb;
  v_households_summary     jsonb := '[]'::jsonb;
  v_leadership_vacancies   jsonb := '[]'::jsonb;
  v_capacity_summary       jsonb;
  v_operational_summary    jsonb;
  v_placement_summary      jsonb;
  v_unassigned_count       integer := 0;
  v_meeting_ops_summary    jsonb;
  v_formation_ops_summary  jsonb;
  v_current_month_start    date;
  v_current_month_end      date;
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

  -- 3. Dedicated Dashboard Permission check
  if not private.has_permission('leadership.pastoral_dashboard.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view the pastoral operations dashboard.';
  end if;

  v_is_org_admin := private.is_organization_administrator(v_profile_id, p_organization_id);

  -- 4. NON-ADMIN DOUBLE-LOCK REQUIREMENT
  -- Delegated callers MUST hold an active servant leader access grant AND a current active leadership assignment.
  if not v_is_org_admin then
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

  -- 5. Scope verification if specific node supplied
  if p_governance_node_id is not null then
    if not private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, p_governance_node_id) then
      raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
    end if;
    v_target_scope_node_id := p_governance_node_id;
  end if;

  -- 6. Sub-domain permission checks for safe field filtering
  v_can_review_placement := private.has_permission('leadership.pastoral_placement.review', p_organization_id);
  v_can_view_leadership  := private.has_permission('governance.leadership.view', p_organization_id);
  v_can_view_roster      := private.has_permission('members.households.view', p_organization_id);

  -- 7. Resolve caller profile and member link (if exists)
  select pml.member_id, coalesce(m.display_name, p.display_name)
  into v_caller_member_id, v_caller_display_name
  from public.profiles p
  left join public.profile_member_links pml
    on pml.profile_id = p.id
   and pml.organization_id = p_organization_id
   and pml.is_primary = true
   and pml.link_type = 'self'
   and pml.link_status = 'verified'
   and pml.ended_at is null
  left join public.members m
    on m.id = pml.member_id
   and m.organization_id = p_organization_id
  where p.id = v_profile_id;

  if v_caller_display_name is null then
    select display_name into v_caller_display_name from public.profiles where id = v_profile_id;
  end if;

  -- 8. If linked to member, resolve Where I Serve (active formal servant roles)
  if v_caller_member_id is not null then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', la.id,
        'role_code',                lrd.code,
        'role_name',                lrd.name,
        'governance_node_id',       la.governance_node_id,
        'node_name',                gn.name,
        'node_type',                gnt.code,
        'effective_from',           la.effective_from
      )
    ), '[]'::jsonb)
    into v_serving_assignments
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join public.governance_nodes gn on gn.id = la.governance_node_id
    join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id
    where la.organization_id = p_organization_id
      and la.member_id = v_caller_member_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date);

    -- Resolve Where I Belong (primary household membership)
    select jsonb_build_object(
      'household_id',     hm.household_node_id,
      'household_name',   gn.name,
      'membership_role',  hm.membership_role,
      'membership_status', hm.membership_status,
      'effective_from',   hm.effective_from
    )
    into v_pastoral_membership
    from public.household_memberships hm
    join public.governance_nodes gn on gn.id = hm.household_node_id
    where hm.organization_id = p_organization_id
      and hm.member_id = v_caller_member_id
      and hm.is_primary = true
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    limit 1;
  end if;

  -- Build caller identity card
  v_identity_json := jsonb_build_object(
    'profile_id',            v_profile_id,
    'member_id',             v_caller_member_id,
    'display_name',          v_caller_display_name,
    'is_administrator',      v_is_org_admin,
    'scoped_governance_node', v_target_scope_node_id,
    'where_i_serve',         v_serving_assignments,
    'where_i_belong',        v_pastoral_membership
  );

  -- 9. Who I Care For (Pastoral Lineage / Care Hierarchy)
  with recursive care_nodes as (
    select
      gn.id as node_id,
      gn.name as node_name,
      gnt.code as node_type,
      1 as depth,
      gn.id as root_scope_id
    from public.governance_nodes gn
    join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id
    where gn.organization_id = p_organization_id
      and gn.lifecycle_status = 'active'
      and (
        (v_target_scope_node_id is not null and gn.id = v_target_scope_node_id)
        or (v_target_scope_node_id is null and v_is_org_admin and gnt.code in ('area', 'chapter', 'unit'))
        or (v_target_scope_node_id is null and not v_is_org_admin and exists (
          select 1 from public.leadership_assignments la_sub
          where la_sub.organization_id = p_organization_id
            and la_sub.member_id = v_caller_member_id
            and la_sub.governance_node_id = gn.id
            and la_sub.assignment_status = 'active'
            and la_sub.effective_from <= current_date
            and (la_sub.effective_to is null or la_sub.effective_to >= current_date)
        ))
      )

    union all

    select
      child_gn.id as node_id,
      child_gn.name as node_name,
      child_gnt.code as node_type,
      cn.depth + 1 as depth,
      cn.root_scope_id
    from care_nodes cn
    join public.governance_node_relationships gnr
      on gnr.parent_node_id = cn.node_id
     and gnr.organization_id = p_organization_id
     and gnr.relationship_status = 'active'
     and gnr.relationship_type = 'primary_parent'
     and gnr.effective_from <= current_date
     and (gnr.effective_to is null or gnr.effective_to >= current_date)
    join public.governance_nodes child_gn on child_gn.id = gnr.child_node_id
    join public.governance_node_types child_gnt on child_gnt.id = child_gn.governance_node_type_id
    where child_gn.lifecycle_status = 'active'
      and cn.depth < 5
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'governance_node_id',   cn.node_id,
      'node_name',            cn.node_name,
      'node_type',            cn.node_type,
      'depth',                cn.depth,
      'active_member_count',  (
        select count(distinct hm.member_id)
        from public.household_memberships hm
        where hm.household_node_id = cn.node_id
          and hm.organization_id = p_organization_id
          and hm.membership_status in ('active', 'temporary')
          and hm.effective_from <= current_date
          and (hm.effective_to is null or hm.effective_to >= current_date)
      ),
      'active_subordinate_households_count', (
        select count(distinct sub_gnr.child_node_id)
        from public.governance_node_relationships sub_gnr
        join public.governance_nodes sub_gn on sub_gn.id = sub_gnr.child_node_id
        join public.governance_node_types sub_gnt on sub_gnt.id = sub_gn.governance_node_type_id
        where sub_gnr.parent_node_id = cn.node_id
          and sub_gnr.organization_id = p_organization_id
          and sub_gnr.relationship_status = 'active'
          and sub_gnt.code = 'household'
          and sub_gn.lifecycle_status = 'active'
      )
    ) order by cn.depth asc, cn.node_name asc
  ), '[]'::jsonb)
  into v_care_responsibilities
  from care_nodes cn
  where private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, cn.node_id);

  -- 10. Households Summary in Scope
  with accessible_hh as (
    select
      gn.id as household_node_id,
      gn.name as household_name,
      gn.code as household_code,
      gn.lifecycle_status,
      h.pastoral_level,
      h.household_category,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.meeting_frequency,
      h.meeting_day_of_week,
      h.meeting_timezone_name
    from public.governance_nodes gn
    join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id
    join public.households h on h.id = gn.id and h.organization_id = gn.organization_id
    where gn.organization_id = p_organization_id
      and gnt.code = 'household'
      and gn.lifecycle_status = 'active'
      and (
        v_target_scope_node_id is null
        or gn.id = v_target_scope_node_id
        or exists (
          select 1
          from public.governance_node_relationships gnr
          where gnr.organization_id = p_organization_id
            and gnr.parent_node_id = v_target_scope_node_id
            and gnr.child_node_id = gn.id
            and gnr.relationship_status = 'active'
            and gnr.effective_from <= current_date
            and (gnr.effective_to is null or gnr.effective_to >= current_date)
        )
      )
      and private.can_access_household('households.records.view', p_organization_id, gn.id)
  ),
  household_members_agg as (
    select
      ah.household_node_id,
      count(hm.id) filter (where hm.membership_status in ('active', 'temporary')) as active_members,
      count(hm.id) filter (where hm.membership_status = 'trial') as trial_members
    from accessible_hh ah
    left join public.household_memberships hm
      on hm.household_node_id = ah.household_node_id
     and hm.organization_id = p_organization_id
     and hm.effective_from <= current_date
     and (hm.effective_to is null or hm.effective_to >= current_date)
    group by ah.household_node_id
  ),
  household_meetings_agg as (
    select
      ah.household_node_id,
      max(m.meeting_date) filter (where m.meeting_status = 'completed') as last_completed_meeting_date,
      min(m.meeting_date) filter (where m.meeting_status = 'scheduled' and m.meeting_date >= current_date) as next_scheduled_meeting_date
    from accessible_hh ah
    left join public.household_meetings m
      on m.household_node_id = ah.household_node_id
     and m.organization_id = p_organization_id
    group by ah.household_node_id
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'household_id',                ah.household_node_id,
      'name',                        ah.household_name,
      'code',                        ah.household_code,
      'pastoral_level',              ah.pastoral_level,
      'household_category',          ah.household_category,
      'active_member_count',         coalesce(hma.active_members, 0),
      'trial_member_count',          coalesce(hma.trial_members, 0),
      'target_member_count',         ah.target_member_count,
      'maximum_member_count',        ah.maximum_member_count,
      'accepts_new_members',         ah.accepts_new_members,
      'meeting_frequency',           ah.meeting_frequency,
      'last_completed_meeting_date', mtg.last_completed_meeting_date,
      'next_scheduled_meeting_date', mtg.next_scheduled_meeting_date,
      'meeting_operational_status',  case
        when mtg.last_completed_meeting_date is null then 'no_history'
        when mtg.last_completed_meeting_date < (current_date - 30) then 'overdue'
        else 'active'
      end
    ) order by ah.household_name asc
  ), '[]'::jsonb)
  into v_households_summary
  from accessible_hh ah
  left join household_members_agg hma on hma.household_node_id = ah.household_node_id
  left join household_meetings_agg mtg on mtg.household_node_id = ah.household_node_id;

  -- 11. Leadership Vacancies
  if v_can_view_leadership then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'governance_node_id',   gn.id,
        'governance_node_name', gn.name,
        'pastoral_level',       h.pastoral_level,
        'required_role_code',   case h.pastoral_level
          when 'member'  then 'household_servant_leader'
          when 'unit'    then 'unit_servant_leader'
          when 'chapter' then 'chapter_servant_leader'
          when 'area'    then 'area_servant_leader'
        end,
        'status', 'vacant'
      )
    ), '[]'::jsonb)
    into v_leadership_vacancies
    from public.households h
    join public.governance_nodes gn on gn.id = h.id and gn.organization_id = h.organization_id
    where h.organization_id = p_organization_id
      and gn.lifecycle_status = 'active'
      and h.pastoral_level in ('member', 'unit', 'chapter', 'area')
      and (
        v_target_scope_node_id is null
        or gn.id = v_target_scope_node_id
        or exists (
          select 1 from public.governance_node_relationships gnr
          where gnr.parent_node_id = v_target_scope_node_id
            and gnr.child_node_id = gn.id
            and gnr.organization_id = p_organization_id
            and gnr.relationship_status = 'active'
        )
      )
      and private.can_access_household('governance.leadership.view', p_organization_id, gn.id)
      and not exists (
        select 1
        from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.organization_id = p_organization_id
          and la.governance_node_id = (
            case
              when h.pastoral_level = 'member' then gn.id
              else (
                select parent_node_id
                from public.governance_node_relationships gnr2
                where gnr2.child_node_id = gn.id
                  and gnr2.relationship_type = 'primary_parent'
                  and gnr2.relationship_status = 'active'
                limit 1
              )
            end
          )
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = case h.pastoral_level
            when 'member'  then 'household_servant_leader'
            when 'unit'    then 'unit_servant_leader'
            when 'chapter' then 'chapter_servant_leader'
            when 'area'    then 'area_servant_leader'
          end
      );
  end if;

  -- 12. Capacity Summary
  with capacity_calc as (
    select
      sum(coalesce(item->>'active_member_count', '0')::integer) as total_active,
      sum(coalesce(item->>'maximum_member_count', '0')::integer) as total_max_capacity,
      sum(coalesce(item->>'target_member_count', '0')::integer) as total_target_capacity
    from jsonb_array_elements(v_households_summary) item
  )
  select jsonb_build_object(
    'total_active_members',   coalesce(total_active, 0),
    'total_max_capacity',     coalesce(total_max_capacity, 0),
    'total_target_capacity',  coalesce(total_target_capacity, 0),
    'capacity_utilization_rate', case
      when coalesce(total_max_capacity, 0) > 0
      then round((coalesce(total_active, 0)::numeric / total_max_capacity::numeric) * 100, 2)
      else 0.00
    end
  )
  into v_capacity_summary
  from capacity_calc;

  -- 13. Operational Summary
  select jsonb_build_object(
    'total_households_in_scope', jsonb_array_length(v_households_summary),
    'overdue_meetings_count', (
      select count(*)
      from jsonb_array_elements(v_households_summary) item
      where item->>'meeting_operational_status' = 'overdue'
    ),
    'vacant_households_count', jsonb_array_length(v_leadership_vacancies),
    'households_at_capacity_count', (
      select count(*)
      from jsonb_array_elements(v_households_summary) item
      where (item->>'maximum_member_count')::integer > 0
        and (item->>'active_member_count')::integer >= (item->>'maximum_member_count')::integer
    )
  )
  into v_operational_summary;

  -- 14. Placement Summary (if caller has placement review permission)
  if v_can_review_placement then
    begin
      select summary into v_placement_summary
      from public.get_placement_recommendations_summary(p_organization_id, v_target_scope_node_id);
    exception when others then
      v_placement_summary := jsonb_build_object(
        'missing_household', 0,
        'different_level', 0,
        'no_matching_household_available', 0,
        'manual_review_required', 0,
        'total', 0,
        'actionable_items', '[]'::jsonb
      );
    end;
  else
    v_placement_summary := jsonb_build_object(
      'missing_household', 0,
      'different_level', 0,
      'no_matching_household_available', 0,
      'manual_review_required', 0,
      'total', 0,
      'actionable_items', '[]'::jsonb
    );
  end if;

  -- 15. Unassigned Members Count
  select count(m.id)
  into v_unassigned_count
  from public.members m
  where m.organization_id = p_organization_id
    and m.record_status = 'active'
    and not exists (
      select 1
      from public.household_memberships hm
      where hm.member_id = m.id
        and hm.organization_id = p_organization_id
        and hm.is_primary = true
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
    )
    and (
      private.can_access_member('leadership.pastoral_dashboard.view', p_organization_id, m.id)
      or private.can_access_member('households.records.view', p_organization_id, m.id)
    );

  -- 16. Meeting Operations Summary
  with scoped_meetings as (
    select hm.*
    from public.household_meetings hm
    where hm.organization_id = p_organization_id
      and (
        v_target_scope_node_id is null
        or hm.household_node_id = v_target_scope_node_id
        or exists (
          select 1 from public.governance_node_relationships gnr
          where gnr.parent_node_id = v_target_scope_node_id
            and gnr.child_node_id = hm.household_node_id
            and gnr.organization_id = p_organization_id
            and gnr.relationship_status = 'active'
        )
      )
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, hm.household_node_id)
  )
  select jsonb_build_object(
    'upcoming_meetings', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'scheduled' and meeting_date >= current_date
    ), 0),
    'meetings_this_month', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'completed' and date_trunc('month', meeting_date) = date_trunc('month', current_date)
    ), 0),
    'attendance_pending', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'completed'
        and not (
          private.compute_attendance_summary(
            id,
            p_organization_id,
            meeting_date,
            household_node_id
          )->>'attendance_complete'
        )::boolean
    ), 0),
    'households_without_meeting_history', coalesce((
      select count(*) from jsonb_array_elements(v_households_summary) item
      where item->>'last_completed_meeting_date' is null
    ), 0),
    'households_overdue', coalesce((
      select count(*) from jsonb_array_elements(v_households_summary) item
      where item->>'meeting_operational_status' = 'overdue'
    ), 0),
    'member_follow_up_signals', coalesce((
      select count(distinct hm_fu.member_id)
      from public.household_memberships hm_fu
      join public.households h_fu on h_fu.id = hm_fu.household_node_id
      where hm_fu.organization_id   = p_organization_id
        and hm_fu.is_primary        = true
        and hm_fu.membership_status in ('active', 'temporary')
        and hm_fu.effective_from    <= current_date
        and (hm_fu.effective_to is null or hm_fu.effective_to >= current_date)
        and (
          v_target_scope_node_id is null
          or hm_fu.household_node_id = v_target_scope_node_id
          or exists (
            select 1 from public.governance_node_relationships gnr
            where gnr.parent_node_id = v_target_scope_node_id
              and gnr.child_node_id = hm_fu.household_node_id
              and gnr.organization_id = p_organization_id
              and gnr.relationship_status = 'active'
          )
        )
        and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, hm_fu.household_node_id)
        and (
          private.get_member_follow_up_signals(
            p_organization_id, hm_fu.member_id, hm_fu.household_node_id
          )->>'multiple_recent_absences'
        )::boolean = true
    ), 0)
  )
  into v_meeting_ops_summary;

  -- 17. Formation Operations Summary
  v_current_month_start := date_trunc('month', current_date)::date;
  v_current_month_end   := (date_trunc('month', current_date) + interval '1 month - 1 day')::date;

  with formation_stats as (
    select
      (item->>'household_id')::uuid as hh_id,
      private.compute_household_formation_status((item->>'household_id')::uuid) as formation_status,
      coalesce((
        select count(*)::integer
        from public.household_topic_assignments a
        where a.household_node_id = (item->>'household_id')::uuid
          and a.assignment_status = 'planned'
      ), 0) as planned_count,
      coalesce((
        select count(*)::integer
        from public.household_topic_assignments a
        where a.household_node_id = (item->>'household_id')::uuid
          and a.assignment_status = 'completed'
          and a.completed_at::date >= v_current_month_start
          and a.completed_at::date <= v_current_month_end
      ), 0) as completed_this_month_count
    from jsonb_array_elements(v_households_summary) item
  )
  select jsonb_build_object(
    'households_with_no_plan',     count(*) filter (where fs.formation_status = 'no_plan'),
    'topics_planned',              coalesce(sum(fs.planned_count), 0)::integer,
    'topics_completed_this_month', coalesce(sum(fs.completed_this_month_count), 0)::integer,
    'topics_due',                  count(*) filter (where fs.formation_status = 'topic_due'),
    'topics_overdue',              count(*) filter (where fs.formation_status = 'topic_overdue')
  ) into v_formation_ops_summary
  from formation_stats fs;

  -- 18. Return Unified Operational Dashboard Payload
  return jsonb_build_object(
    'organization_id',            p_organization_id,
    'identity',                   v_identity_json,
    'care_responsibilities',      v_care_responsibilities,
    'household_summary',          v_households_summary,
    'leadership_vacancies',       v_leadership_vacancies,
    'capacity_summary',           v_capacity_summary,
    'operational_summary',        v_operational_summary,
    'placement_review_summary',   v_placement_summary,
    'unassigned_members_count',   coalesce(v_unassigned_count, 0),
    'meeting_operations_summary', coalesce(v_meeting_ops_summary, jsonb_build_object(
      'upcoming_meetings',                  0,
      'meetings_this_month',                0,
      'attendance_pending',                 0,
      'households_without_meeting_history', 0,
      'households_overdue',                 0,
      'member_follow_up_signals',           0
    )),
    'formation_operations_summary', coalesce(v_formation_ops_summary, jsonb_build_object(
      'households_with_no_plan',     0,
      'topics_planned',              0,
      'topics_completed_this_month', 0,
      'topics_due',                  0,
      'topics_overdue',              0
    ))
  );
end;
$$;

comment on function public.get_pastoral_operations_dashboard(uuid, uuid) is
  'Unified operational pastoral leadership dashboard with delegated servant leader double-lock access enforcement, cadence, and formation operations.';

revoke all on function public.get_pastoral_operations_dashboard(uuid, uuid) from public, anon;
grant execute on function public.get_pastoral_operations_dashboard(uuid, uuid) to authenticated, service_role;

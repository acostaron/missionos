-- =============================================================================
-- Migration: 20261002250000_phase_6b_dashboard_payload_alignment.sql
-- Phase:     Phase 6B-10 — Dashboard Payload Alignment
-- Purpose:   Restores canonical identity and care responsibilities structures to
--            get_pastoral_operations_dashboard while retaining cadence and formation summaries.
-- =============================================================================

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

  -- 8. If caller is linked member: populate serving assignments and pastoral membership
  if v_caller_member_id is not null then
    -- Serving assignments: leadership roles held by caller in this org
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', la.id,
        'role_code',                lrd.code,
        'role_name',                lrd.name,
        'appointment_type',         la.appointment_type,
        'governance_node_id',       la.governance_node_id,
        'governance_node_name',     gn.name,
        'governance_node_type',     gnt.code,
        'effective_from',           la.effective_from,
        'effective_to',             la.effective_to
      ) order by la.effective_from desc
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

    -- Pastoral membership: where the caller is a member (primary household)
    select jsonb_build_object(
      'household_id',      h.id,
      'household_name',    gn.name,
      'pastoral_level',    h.pastoral_level,
      'membership_role',   hm.membership_role,
      'parent_node_id',    pn.id,
      'parent_node_name',  pn.name,
      'membership_status', hm.membership_status,
      'effective_from',    hm.effective_from
    )
    into v_pastoral_membership
    from public.household_memberships hm
    join public.households h on h.id = hm.household_node_id
    join public.governance_nodes gn on gn.id = h.id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn on pn.id = p_rel.parent_node_id
    where hm.organization_id = p_organization_id
      and hm.member_id = v_caller_member_id
      and hm.is_primary = true
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    limit 1;
  end if;

  -- 9. Build Identity Block
  v_identity_json := jsonb_build_object(
    'profile_id',                          v_profile_id,
    'member_id',                           v_caller_member_id,
    'display_name',                        v_caller_display_name,
    'has_linked_member',                   (v_caller_member_id is not null),
    'serving_assignments',                 v_serving_assignments,
    'pastoral_membership',                 v_pastoral_membership,
    'pastoral_household_placement_needed', (v_caller_member_id is not null and v_pastoral_membership is null and jsonb_array_length(v_serving_assignments) > 0),
    'is_administrator',                    v_is_org_admin,
    'scoped_governance_node',              v_target_scope_node_id,
    'where_i_serve',                       v_serving_assignments,
    'where_i_belong',                      v_pastoral_membership
  );

  -- 10. Care Responsibilities
  if v_caller_member_id is not null and jsonb_array_length(v_serving_assignments) > 0 then
    with caller_roles as (
      select
        (item->>'leadership_assignment_id')::uuid as assignment_id,
        item->>'role_code' as role_code,
        (item->>'governance_node_id')::uuid as node_id,
        item->>'governance_node_name' as node_name
      from jsonb_array_elements(v_serving_assignments) item
    ),
    hsl_care as (
      select
        cr.assignment_id,
        'household'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'household_members',
          'household_id', cr.node_id,
          'household_name', cr.node_name,
          'member_count', count(hm.id),
          'members', case when v_can_view_roster then coalesce(jsonb_agg(
            jsonb_build_object(
              'member_id', m.id,
              'display_name', m.display_name,
              'member_number', m.member_number,
              'membership_role', hm.membership_role,
              'effective_from', hm.effective_from
            ) order by m.display_name
          ), '[]'::jsonb) else '[]'::jsonb end
        ) as care_payload
      from caller_roles cr
      join public.households h on h.id = cr.node_id and h.pastoral_level = 'member'
      left join public.household_memberships hm
        on hm.household_node_id = cr.node_id
       and hm.organization_id = p_organization_id
       and hm.membership_status in ('active', 'temporary')
       and hm.effective_from <= current_date
       and (hm.effective_to is null or hm.effective_to >= current_date)
      left join public.members m on m.id = hm.member_id
      where cr.role_code = 'household_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    usl_care as (
      select
        cr.assignment_id,
        'unit'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'unit_household_leaders',
          'unit_id', cr.node_id,
          'unit_name', cr.node_name,
          'household_count', count(distinct rel.child_node_id),
          'households', case when v_can_view_leadership then coalesce(jsonb_agg(distinct
            jsonb_build_object(
              'household_id', h.id,
              'household_name', hh_node.name,
              'servant_leader', case when lm.id is not null then jsonb_build_object(
                'member_id', lm.id,
                'display_name', lm.display_name,
                'effective_from', la.effective_from
              ) else null end,
              'derived_spouse', case when sp.id is not null then jsonb_build_object(
                'member_id', sp.id,
                'display_name', sp.display_name
              ) else null end
            )
          ), '[]'::jsonb) else '[]'::jsonb end
        ) as care_payload
      from caller_roles cr
      join public.governance_nodes u_node on u_node.id = cr.node_id
      join public.governance_node_types unt on unt.id = u_node.governance_node_type_id and unt.code = 'unit'
      left join public.governance_node_relationships rel
        on rel.parent_node_id = cr.node_id
       and rel.organization_id = p_organization_id
       and rel.relationship_type = 'primary_parent'
       and rel.relationship_status = 'active'
       and (rel.effective_to is null or rel.effective_to >= current_date)
      left join public.households h on h.id = rel.child_node_id and h.pastoral_level = 'member'
      left join public.governance_nodes hh_node on hh_node.id = h.id
      left join public.leadership_assignments la
        on la.governance_node_id = h.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.members lm on lm.id = la.member_id
      left join public.family_relationships fr
        on fr.organization_id = p_organization_id
       and fr.relationship_status = 'active'
       and (fr.effective_from is null or fr.effective_from <= current_date)
       and (fr.effective_to is null or fr.effective_to >= current_date)
       and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
      left join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      left join public.members sp on sp.id = (case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end) and sp.record_status = 'active' and not sp.is_deceased
      where cr.role_code = 'unit_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    csl_care as (
      select
        cr.assignment_id,
        'chapter'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'chapter_unit_leaders',
          'chapter_id', cr.node_id,
          'chapter_name', cr.node_name,
          'unit_count', count(distinct rel.child_node_id),
          'units', case when v_can_view_leadership then coalesce(jsonb_agg(distinct
            jsonb_build_object(
              'unit_id', u_node.id,
              'unit_name', u_node.name,
              'unit_leader', case when lm.id is not null then jsonb_build_object(
                'member_id', lm.id,
                'display_name', lm.display_name,
                'effective_from', la.effective_from
              ) else null end,
              'derived_spouse', case when sp.id is not null then jsonb_build_object(
                'member_id', sp.id,
                'display_name', sp.display_name
              ) else null end
            )
          ), '[]'::jsonb) else '[]'::jsonb end
        ) as care_payload
      from caller_roles cr
      join public.governance_nodes c_node on c_node.id = cr.node_id
      join public.governance_node_types cnt on cnt.id = c_node.governance_node_type_id and cnt.code = 'chapter'
      left join public.governance_node_relationships rel
        on rel.parent_node_id = cr.node_id
       and rel.organization_id = p_organization_id
       and rel.relationship_type = 'primary_parent'
       and rel.relationship_status = 'active'
       and (rel.effective_to is null or rel.effective_to >= current_date)
      left join public.governance_nodes u_node on u_node.id = rel.child_node_id
      left join public.governance_node_types unt on unt.id = u_node.governance_node_type_id and unt.code = 'unit'
      left join public.leadership_assignments la
        on la.governance_node_id = u_node.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.members lm on lm.id = la.member_id
      left join public.family_relationships fr
        on fr.organization_id = p_organization_id
       and fr.relationship_status = 'active'
       and (fr.effective_from is null or fr.effective_from <= current_date)
       and (fr.effective_to is null or fr.effective_to >= current_date)
       and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
      left join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      left join public.members sp on sp.id = (case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end) and sp.record_status = 'active' and not sp.is_deceased
      where cr.role_code = 'chapter_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    asl_care as (
      select
        cr.assignment_id,
        'area'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'area_chapter_leaders',
          'area_id', cr.node_id,
          'area_name', cr.node_name,
          'chapter_count', count(distinct rel.child_node_id),
          'chapters', case when v_can_view_leadership then coalesce(jsonb_agg(distinct
            jsonb_build_object(
              'chapter_id', c_node.id,
              'chapter_name', c_node.name,
              'chapter_leader', case when lm.id is not null then jsonb_build_object(
                'member_id', lm.id,
                'display_name', lm.display_name,
                'effective_from', la.effective_from
              ) else null end,
              'derived_spouse', case when sp.id is not null then jsonb_build_object(
                'member_id', sp.id,
                'display_name', sp.display_name
              ) else null end
            )
          ), '[]'::jsonb) else '[]'::jsonb end
        ) as care_payload
      from caller_roles cr
      join public.governance_nodes a_node on a_node.id = cr.node_id
      join public.governance_node_types ant on ant.id = a_node.governance_node_type_id and ant.code in ('area', 'area_state')
      left join public.governance_node_relationships rel
        on rel.parent_node_id = cr.node_id
       and rel.organization_id = p_organization_id
       and rel.relationship_type = 'primary_parent'
       and rel.relationship_status = 'active'
       and (rel.effective_to is null or rel.effective_to >= current_date)
      left join public.governance_nodes c_node on c_node.id = rel.child_node_id
      left join public.governance_node_types cnt on cnt.id = c_node.governance_node_type_id and cnt.code = 'chapter'
      left join public.leadership_assignments la
        on la.governance_node_id = c_node.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.members lm on lm.id = la.member_id
      left join public.family_relationships fr
        on fr.organization_id = p_organization_id
       and fr.relationship_status = 'active'
       and (fr.effective_from is null or fr.effective_from <= current_date)
       and (fr.effective_to is null or fr.effective_to >= current_date)
       and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
      left join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      left join public.members sp on sp.id = (case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end) and sp.record_status = 'active' and not sp.is_deceased
      where cr.role_code = 'area_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    all_care as (
      select * from hsl_care
      union all
      select * from usl_care
      union all
      select * from csl_care
      union all
      select * from asl_care
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', ac.assignment_id,
        'responsibility_level',     ac.responsibility_level,
        'scope_id',                 ac.scope_id,
        'scope_name',               ac.scope_name,
        'care_details',             ac.care_payload
      )
    ), '[]'::jsonb)
    into v_care_responsibilities
    from all_care ac;
  end if;

  -- 11. Household Summaries within Caller Scope
  with scoped_households as (
    select
      h.id as household_id,
      gn.name as household_name,
      h.pastoral_level,
      h.household_category,
      gn.lifecycle_status,
      h.is_couple_household,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      p_node.id as scope_node_id,
      p_node.name as scope_node_name
    from public.households h
    join public.governance_nodes gn on gn.id = h.id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes p_node on p_node.id = p_rel.parent_node_id
    where gn.organization_id = p_organization_id
      and gn.lifecycle_status in ('active', 'forming')
      and (
        v_is_org_admin
        or (v_target_scope_node_id is not null and (gn.id = v_target_scope_node_id or p_node.id = v_target_scope_node_id))
        or (v_target_scope_node_id is null and exists (
          select 1 from public.leadership_assignments la_sub
          where la_sub.organization_id = p_organization_id
            and la_sub.member_id = v_caller_member_id
            and (la_sub.governance_node_id = gn.id or la_sub.governance_node_id = p_node.id)
            and la_sub.assignment_status = 'active'
            and la_sub.effective_from <= current_date
            and (la_sub.effective_to is null or la_sub.effective_to >= current_date)
        ))
      )
  ),
  household_leaders as (
    select
      sh.household_id,
      sh.pastoral_level,
      sh.is_couple_household,
      sh.household_name,
      sh.household_category,
      sh.lifecycle_status,
      sh.scope_node_id,
      sh.scope_node_name,
      sh.meeting_frequency,
      sh.meeting_day_of_week,
      sh.meeting_start_time,
      sh.target_member_count,
      sh.maximum_member_count,
      sh.accepts_new_members,
      case
        when sh.pastoral_level = 'member' then la_hh.id
        when sh.pastoral_level in ('unit', 'chapter', 'area') then la_scope.id
        else null
      end as leadership_assignment_id,
      case
        when sh.pastoral_level = 'member' then lm_hh.id
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lm_scope.id
        else null
      end as leader_member_id,
      case
        when sh.pastoral_level = 'member' then lm_hh.display_name
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lm_scope.display_name
        else null
      end as leader_name,
      case
        when sh.pastoral_level = 'member' then lrd_hh.code
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lrd_scope.code
        else null
      end as role_code,
      case
        when sh.pastoral_level = 'member' then lrd_hh.name
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lrd_scope.name
        else null
      end as role_name,
      case
        when sh.pastoral_level = 'fraternal' then null
        when sh.is_couple_household and sh.pastoral_level = 'member' and sp_hh.id is not null then sp_hh.display_name
        when sh.is_couple_household and sh.pastoral_level in ('unit', 'chapter', 'area') and sp_scope.id is not null then sp_scope.display_name
        else null
      end as derived_spouse_name
    from scoped_households sh
    left join public.leadership_assignments la_hh
      on la_hh.governance_node_id = sh.household_id
     and la_hh.organization_id = p_organization_id
     and la_hh.assignment_status = 'active'
     and la_hh.effective_from <= current_date
     and (la_hh.effective_to is null or la_hh.effective_to >= current_date)
    left join public.leadership_role_definitions lrd_hh on lrd_hh.id = la_hh.leadership_role_definition_id and lrd_hh.code = 'household_servant_leader'
    left join public.members lm_hh on lm_hh.id = la_hh.member_id and lrd_hh.id is not null
    left join public.family_relationships fr_hh
      on fr_hh.organization_id = p_organization_id
     and fr_hh.relationship_status = 'active'
     and (fr_hh.effective_from is null or fr_hh.effective_from <= current_date)
     and (fr_hh.effective_to is null or fr_hh.effective_to >= current_date)
     and (fr_hh.from_member_id = lm_hh.id or fr_hh.to_member_id = lm_hh.id)
    left join public.family_relationship_types frt_hh on frt_hh.id = fr_hh.relationship_type_id and frt_hh.code = 'spouse'
    left join public.members sp_hh on sp_hh.id = (case when fr_hh.from_member_id = lm_hh.id then fr_hh.to_member_id else fr_hh.from_member_id end) and sp_hh.record_status = 'active' and not sp_hh.is_deceased
    left join public.leadership_assignments la_scope
      on la_scope.governance_node_id = sh.scope_node_id
     and la_scope.organization_id = p_organization_id
     and la_scope.assignment_status = 'active'
     and la_scope.effective_from <= current_date
     and (la_scope.effective_to is null or la_scope.effective_to >= current_date)
    left join public.leadership_role_definitions lrd_scope
      on lrd_scope.id = la_scope.leadership_role_definition_id
     and (
       (sh.pastoral_level = 'unit' and lrd_scope.code = 'unit_servant_leader') or
       (sh.pastoral_level = 'chapter' and lrd_scope.code = 'chapter_servant_leader') or
       (sh.pastoral_level = 'area' and lrd_scope.code = 'area_servant_leader')
     )
    left join public.members lm_scope on lm_scope.id = la_scope.member_id and lrd_scope.id is not null
    left join public.family_relationships fr_scope
      on fr_scope.organization_id = p_organization_id
     and fr_scope.relationship_status = 'active'
     and (fr_scope.effective_from is null or fr_scope.effective_from <= current_date)
     and (fr_scope.effective_to is null or fr_scope.effective_to >= current_date)
     and (fr_scope.from_member_id = lm_scope.id or fr_scope.to_member_id = lm_scope.id)
    left join public.family_relationship_types frt_scope on frt_scope.id = fr_scope.relationship_type_id and frt_scope.code = 'spouse'
    left join public.members sp_scope on sp_scope.id = (case when fr_scope.from_member_id = lm_scope.id then fr_scope.to_member_id else fr_scope.from_member_id end) and sp_scope.record_status = 'active' and not sp_scope.is_deceased
  ),
  household_members_count as (
    select
      hm.household_node_id as household_id,
      count(hm.id) filter (where hm.membership_status in ('active', 'temporary')) as member_count
    from public.household_memberships hm
    where hm.organization_id = p_organization_id
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    group by hm.household_node_id
  ),
  classified_households as (
    select
      hl.*,
      coalesce(hmc.member_count, 0) as member_count,
      case
        when hl.pastoral_level = 'fraternal' then 'Rotating Facilitator'
        when hl.leader_name is not null and hl.derived_spouse_name is not null then hl.leader_name || ' & ' || hl.derived_spouse_name || ' (' || coalesce(hl.role_name, 'Leader') || ')'
        when hl.leader_name is not null then hl.leader_name || ' (' || coalesce(hl.role_name, 'Leader') || ')'
        else 'Unassigned'
      end as leader_display_label,
      case
        when hl.pastoral_level = 'fraternal' then 'rotating_facilitation'
        when hl.leader_member_id is not null then 'assigned'
        else 'vacant'
      end as leadership_status,
      case
        when coalesce(hmc.member_count, 0) = 0 then 'empty'
        when hl.maximum_member_count is not null and coalesce(hmc.member_count, 0) >= hl.maximum_member_count then 'full'
        when hl.target_member_count is not null and coalesce(hmc.member_count, 0) >= hl.target_member_count then 'optimal'
        else 'under_target'
      end as capacity_status
    from household_leaders hl
    left join household_members_count hmc on hmc.household_id = hl.household_id
  ),
  with_operational_status as (
    select
      ch.*,
      case
        when ch.pastoral_level != 'fraternal' and ch.leadership_status = 'vacant' then 'needs_leader'
        when ch.capacity_status = 'empty' then 'needs_members'
        when ch.capacity_status = 'full' then 'at_capacity'
        when ch.accepts_new_members and ch.target_member_count is not null and ch.member_count < ch.target_member_count then 'needs_members'
        else 'ready'
      end as operational_status
    from classified_households ch
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'household_id',            wos.household_id,
      'household_name',          wos.household_name,
      'pastoral_level',          wos.pastoral_level,
      'household_category',      wos.household_category,
      'lifecycle_status',        wos.lifecycle_status,
      'is_couple_household',     wos.is_couple_household,
      'scope_node_id',           wos.scope_node_id,
      'scope_node_name',         wos.scope_node_name,
      'formal_leader', case when wos.leader_member_id is not null then jsonb_build_object(
        'leadership_assignment_id', wos.leadership_assignment_id,
        'member_id',                wos.leader_member_id,
        'display_name',             wos.leader_name,
        'role_code',                wos.role_code,
        'role_name',                wos.role_name
      ) else null end,
      'derived_leader_spouse',   wos.derived_spouse_name,
      'leader_display_label',    wos.leader_display_label,
      'member_count',            wos.member_count,
      'target_member_count',     wos.target_member_count,
      'maximum_member_count',    wos.maximum_member_count,
      'accepts_new_members',     wos.accepts_new_members,
      'capacity_status',         wos.capacity_status,
      'leadership_status',       wos.leadership_status,
      'operational_status',      wos.operational_status,
      'meeting_frequency',       wos.meeting_frequency,
      'meeting_day_of_week',     wos.meeting_day_of_week,
      'meeting_start_time',      wos.meeting_start_time
    ) order by
      case wos.pastoral_level
        when 'fraternal' then 1
        when 'area' then 2
        when 'chapter' then 3
        when 'unit' then 4
        when 'member' then 5
        else 6
      end,
      wos.household_name asc
  ), '[]'::jsonb)
  into v_households_summary
  from with_operational_status wos;

  -- 12. Leadership Vacancies
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'household_id',       item->>'household_id',
      'household_name',     item->>'household_name',
      'pastoral_level',     item->>'pastoral_level',
      'scope_node_id',      item->>'scope_node_id',
      'scope_node_name',    item->>'scope_node_name',
      'required_role_code', case (item->>'pastoral_level')
        when 'member'  then 'household_servant_leader'
        when 'unit'    then 'unit_servant_leader'
        when 'chapter' then 'chapter_servant_leader'
        when 'area'    then 'area_servant_leader'
        else null
      end,
      'member_count',       (item->>'member_count')::integer
    )
  ), '[]'::jsonb)
  into v_leadership_vacancies
  from jsonb_array_elements(v_households_summary) item
  where (item->>'leadership_status') = 'vacant';

  -- 13. Capacity & Operational Status Aggregations
  with items as (
    select
      item->>'capacity_status' as cap_status,
      item->>'operational_status' as op_status,
      (item->>'member_count')::integer as m_count,
      (item->>'target_member_count')::integer as t_count,
      (item->>'maximum_member_count')::integer as max_count
    from jsonb_array_elements(v_households_summary) item
  )
  select
    jsonb_build_object(
      'total_households',     count(*),
      'empty_households',     count(*) filter (where cap_status = 'empty'),
      'under_target',         count(*) filter (where cap_status = 'under_target'),
      'optimal',              count(*) filter (where cap_status = 'optimal'),
      'full',                 count(*) filter (where cap_status = 'full'),
      'total_assigned_members', coalesce(sum(m_count), 0),
      'total_target_capacity',  coalesce(sum(t_count), 0),
      'total_maximum_capacity', coalesce(sum(max_count), 0)
    ),
    jsonb_build_object(
      'ready',          count(*) filter (where op_status = 'ready'),
      'needs_leader',   count(*) filter (where op_status = 'needs_leader'),
      'needs_members',  count(*) filter (where op_status = 'needs_members'),
      'at_capacity',    count(*) filter (where op_status = 'at_capacity')
    )
  into v_capacity_summary, v_operational_summary
  from items;

  -- 14. Placement Review Summary
  if v_can_review_placement then
    with candidates as (
      select
        rc.id as candidate_id,
        rc.review_reason,
        rc.member_id,
        m.display_name as member_name,
        rc.current_household_node_id,
        rc.suggested_household_node_id,
        rc.suggested_pastoral_level
      from public.pastoral_placement_review_candidates rc
      join public.members m on m.id = rc.member_id
      where rc.organization_id = p_organization_id
        and rc.status = 'pending'
    )
    select jsonb_build_object(
      'missing_household', count(*) filter (where review_reason = 'missing_household'),
      'different_level', count(*) filter (where review_reason = 'different_level'),
      'no_matching_household_available', count(*) filter (where review_reason = 'no_matching_household_available'),
      'manual_review_required', count(*) filter (where review_reason = 'manual_review_required'),
      'total', count(*),
      'actionable_items', coalesce(jsonb_agg(
        jsonb_build_object(
          'candidate_id', candidate_id,
          'review_reason', review_reason,
          'member_id', member_id,
          'member_name', member_name,
          'suggested_pastoral_level', suggested_pastoral_level
        ) order by candidate_id
      ), '[]'::jsonb)
    )
    into v_placement_summary
    from candidates;
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
  v_current_month_start := date_trunc('month', current_date)::date;
  v_current_month_end   := (date_trunc('month', current_date) + interval '1 month - 1 day')::date;

  with meeting_stats as (
    select
      (item->>'household_id')::uuid as hh_id,
      coalesce((
        select count(*)::integer
        from public.household_meetings hm
        where hm.household_node_id = (item->>'household_id')::uuid
          and hm.meeting_date >= current_date
          and hm.meeting_status in ('scheduled', 'in_progress')
      ), 0) as upcoming_count,
      coalesce((
        select count(*)::integer
        from public.household_meetings hm
        where hm.household_node_id = (item->>'household_id')::uuid
          and hm.meeting_date >= v_current_month_start
          and hm.meeting_date <= v_current_month_end
          and hm.meeting_status = 'completed'
      ), 0) as completed_this_month_count,
      coalesce((
        select count(*)::integer
        from public.household_meetings hm
        where hm.household_node_id = (item->>'household_id')::uuid
          and hm.meeting_date <= current_date
          and hm.meeting_status in ('scheduled', 'in_progress')
      ), 0) as attendance_pending_count,
      (
        select count(*)::integer
        from public.household_meetings hm
        where hm.household_node_id = (item->>'household_id')::uuid
      ) as total_meetings_count,
      (
        select max(hm.meeting_date)
        from public.household_meetings hm
        where hm.household_node_id = (item->>'household_id')::uuid
          and hm.meeting_status = 'completed'
      ) as last_completed_meeting_date,
      item->>'meeting_frequency' as frequency
    from jsonb_array_elements(v_households_summary) item
  )
  select jsonb_build_object(
    'upcoming_meetings', coalesce(sum(ms.upcoming_count), 0)::integer,
    'meetings_this_month', coalesce(sum(ms.completed_this_month_count), 0)::integer,
    'attendance_pending', coalesce(sum(ms.attendance_pending_count), 0)::integer,
    'households_without_meeting_history', count(*) filter (where ms.total_meetings_count = 0),
    'households_overdue', count(*) filter (
      where (
        (ms.frequency = 'weekly' and (ms.last_completed_meeting_date is null or ms.last_completed_meeting_date < current_date - interval '14 days')) or
        (ms.frequency = 'biweekly' and (ms.last_completed_meeting_date is null or ms.last_completed_meeting_date < current_date - interval '28 days')) or
        (ms.frequency = 'monthly' and (ms.last_completed_meeting_date is null or ms.last_completed_meeting_date < current_date - interval '45 days'))
      ) and ms.total_meetings_count > 0
    ),
    'member_follow_up_signals', coalesce((
      select count(distinct a.member_id)::integer
      from public.household_meeting_attendance a
      join public.household_meetings m on m.id = a.household_meeting_id
      where m.household_node_id in (select (item->>'household_id')::uuid from jsonb_array_elements(v_households_summary) item)
        and a.attendance_status in ('absent', 'excused')
        and m.meeting_date >= current_date - interval '60 days'
    ), 0)::integer
  ) into v_meeting_ops_summary
  from meeting_stats ms;

  -- 17. Formation Operations Summary
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

revoke all on function public.get_pastoral_operations_dashboard(uuid, uuid) from public, anon;
grant execute on function public.get_pastoral_operations_dashboard(uuid, uuid) to authenticated, service_role;

comment on function public.get_pastoral_operations_dashboard(uuid, uuid) is
  'Unified operational pastoral leadership dashboard with delegated servant leader double-lock access enforcement, cadence, and formation operations.';

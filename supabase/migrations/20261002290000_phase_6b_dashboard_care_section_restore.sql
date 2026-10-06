-- =============================================================================
-- Migration: 20261002290000_phase_6b_dashboard_care_section_restore.sql
-- Phase:     Phase 6B-10B correction
-- Purpose:   Migration 250000 rewrote the care_responsibilities section of
--            get_pastoral_operations_dashboard with non-canonical type values
--            and keys (unit_household_leaders, chapter_unit_leaders, ...),
--            breaking the established dashboard contract. Restores the
--            canonical care section from migration 110000 verbatim.
--            Rewrites only that block of the live function; all other logic
--            (formation/meeting summaries, ACLs) is untouched.
-- =============================================================================

do $mig$
declare
  v_def   text;
  v_start integer;
  v_end   integer;
  v_endtok text := E'    from all_care ac;';
  v_canon text := $care$
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
          'type', 'household_leaders',
          'unit_id', cr.node_id,
          'unit_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'household_id', h.id,
              'household_name', gn.name,
              'is_couple_household', h.is_couple_household,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'has_derived_spouse', (h.is_couple_household and sp.id is not null),
              'derived_spouse_name', case when h.is_couple_household then sp.display_name else null end,
              'derived_pastoral_title', case when h.is_couple_household and sp.id is not null then 'Household Leaders' else 'Household Servant Leader' end
            ) order by gn.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.households h on h.id = gnr.child_node_id and h.pastoral_level = 'member'
      join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = h.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'household_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
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
          'type', 'unit_leaders',
          'chapter_id', cr.node_id,
          'chapter_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'unit_id', un.id,
              'unit_name', un.name,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'couples_context_status', g_guidance.couples_status,
              'has_derived_spouse', (g_guidance.couples_status = 'couples' and sp.id is not null),
              'derived_spouse_name', case when g_guidance.couples_status = 'couples' then sp.display_name else null end,
              'derived_pastoral_title', case when g_guidance.couples_status = 'couples' and sp.id is not null then 'Unit Leaders' else 'Unit Servant Leader' end
            ) order by un.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.governance_nodes un on un.id = gnr.child_node_id and un.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = un.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'unit_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select
          case
            when exists (
              select 1 from public.governance_nodes sn
              join public.governance_node_types snt on snt.id = sn.governance_node_type_id
              where sn.id = lm.primary_section_node_id and (snt.code = 'couples' or sn.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when lm.primary_section_node_id is not null then 'non_couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and (gnt_mga.code = 'couples' or gn_mga.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and gnt_mga.code in ('singles', 'youth', 'handmaids', 'servants', 'men', 'women')
            ) then 'non_couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = true
            ) then 'couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = false
            ) then 'non_couples'
            when not exists (
              select 1 from public.family_relationships fr_chk
              where (fr_chk.from_member_id = lm.id or fr_chk.to_member_id = lm.id)
                and fr_chk.organization_id = p_organization_id and fr_chk.relationship_status = 'active'
            ) then 'non_couples'
            else 'ambiguous'
          end as couples_status
      ) g_guidance on true
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
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
          'type', 'chapter_leaders',
          'area_id', cr.node_id,
          'area_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'chapter_id', chn.id,
              'chapter_name', chn.name,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'couples_context_status', g_guidance.couples_status,
              'has_derived_spouse', (g_guidance.couples_status = 'couples' and sp.id is not null),
              'derived_spouse_name', case when g_guidance.couples_status = 'couples' then sp.display_name else null end,
              'derived_pastoral_title', case when g_guidance.couples_status = 'couples' and sp.id is not null then 'Chapter Leaders' else 'Chapter Servant Leader' end
            ) order by chn.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.governance_nodes chn on chn.id = gnr.child_node_id and chn.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = chn.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'chapter_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select
          case
            when exists (
              select 1 from public.governance_nodes sn
              join public.governance_node_types snt on snt.id = sn.governance_node_type_id
              where sn.id = lm.primary_section_node_id and (snt.code = 'couples' or sn.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when lm.primary_section_node_id is not null then 'non_couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and (gnt_mga.code = 'couples' or gn_mga.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and gnt_mga.code in ('singles', 'youth', 'handmaids', 'servants', 'men', 'women')
            ) then 'non_couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = true
            ) then 'couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = false
            ) then 'non_couples'
            when not exists (
              select 1 from public.family_relationships fr_chk
              where (fr_chk.from_member_id = lm.id or fr_chk.to_member_id = lm.id)
                and fr_chk.organization_id = p_organization_id and fr_chk.relationship_status = 'active'
            ) then 'non_couples'
            else 'ambiguous'
          end as couples_status
      ) g_guidance on true
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
      where cr.role_code = 'area_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', assignment_id,
        'responsibility_level',     responsibility_level,
        'scope_id',                 scope_id,
        'scope_name',               scope_name,
        'details',                  care_payload
      )
    ), '[]'::jsonb)
    into v_care_responsibilities
    from (
      select * from hsl_care
      union all
      select * from usl_care
      union all
      select * from csl_care
      union all
      select * from asl_care
    ) u;
$care$;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_pastoral_operations_dashboard'
    and pg_get_function_identity_arguments(p.oid) = 'p_organization_id uuid, p_governance_node_id uuid';

  if v_def is null then
    raise exception 'get_pastoral_operations_dashboard not found';
  end if;

  v_start := position(E'    with caller_roles as (' in v_def);
  v_end   := position(v_endtok in v_def);
  if v_start = 0 or v_end = 0 or v_end < v_start then
    raise exception 'care section markers not found';
  end if;

  v_def := substr(v_def, 1, v_start - 1)
        || btrim(v_canon, E'\n')
        || substr(v_def, v_end + length(v_endtok));

  execute v_def;
end;
$mig$;
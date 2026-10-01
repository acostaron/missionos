-- =============================================================================
-- Migration: 20261001010000_phase_6b_pastoral_operations_dashboard.sql
-- Phase:     Phase 6B-7 — Pastoral Household Operations & Leader Care Dashboard
--
-- Authoritative Architecture:
--   1. Register narrow permission:
--      - leadership.pastoral_dashboard.view
--      Assigned initially strictly to organization_administrator.
--      Do NOT grant to servant roles automatically.
--
--   2. Implement public.get_pastoral_operations_dashboard:
--      Read-only, set-based, SECURITY DEFINER RPC.
--      Requires leadership.pastoral_dashboard.view.
--      Derives:
--        - Identity & Personalized Leader Context (Where I Serve, Where I Receive Pastoral Care)
--          gracefully handles admin without linked member.
--        - Echelon Care Responsibilities:
--            HSL -> members of their Member Household
--            USL -> Household Leaders of Member Households under their Unit
--            CSL -> Unit Leaders of Units under their Chapter
--            ASL -> Chapter Leaders of Chapters under their Area
--        - Household Summaries within caller's authorized scope (with operational status,
--          capacity status, leadership status).
--        - Leadership Vacancies (Member HH without HSL, Unit without USL, Chapter without CSL, Area without ASL; Fraternal is not_applicable).
--        - Capacity Summary (available, at_target, full, not_accepting).
--        - Placement Review Summary (reuses canonical Phase 6B-6 statuses).
--        - Unassigned Members count (active members with no current primary household).
--
--   3. Implement public.get_pastoral_household_roster:
--      Read-only, privacy-minimized roster for a specific household.
--      Requires leadership.pastoral_dashboard.view and members.households.view.
--      Returns member_id, member_number, display_name, membership_id, membership_role,
--      membership_status, effective_from, is_primary.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Register Permission & Initial Role Grants
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
  'leadership.pastoral_dashboard.view',
  'View pastoral operations dashboard',
  'Authorizes reading the pastoral operations dashboard, operational summaries, and leader care overview.',
  'leadership',
  'view',
  'governance',
  'low',
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
  is_active               = excluded.is_active;

-- Map permission initially ONLY to organization_administrator
insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  effective_from_at,
  effective_to_at,
  approval_status,
  approved_at,
  created_at,
  updated_at
)
select
  r.organization_id,
  r.id as app_role_id,
  p.id as permission_id,
  'allow',
  now(),
  null,
  'approved',
  now(),
  now(),
  now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and p.code = 'leadership.pastoral_dashboard.view'
  and not exists (
    select 1
    from public.role_permissions rp
    where rp.organization_id = r.organization_id
      and rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.approval_status = 'approved'
  );

-- =============================================================================
-- SECTION 2: Public RPC public.get_pastoral_operations_dashboard
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

  -- 4. Scope verification if specific node supplied
  if p_governance_node_id is not null then
    if not private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, p_governance_node_id) then
      raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
    end if;
    v_target_scope_node_id := p_governance_node_id;
  end if;

  -- 5. Sub-domain permission checks for safe field filtering
  v_can_review_placement := private.has_permission('leadership.pastoral_placement.review', p_organization_id);
  v_can_view_leadership  := private.has_permission('governance.leadership.view', p_organization_id);
  v_can_view_roster      := private.has_permission('members.households.view', p_organization_id);

  -- 6. Resolve caller profile and member link (if exists)
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

  -- 7. If linked to member, resolve Where I Serve (active formal servant roles)
  if v_caller_member_id is not null then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', la.id,
        'role_code',                lrd.code,
        'role_name',                lrd.name,
        'governance_node_id',       la.governance_node_id,
        'governance_node_name',     gn.name,
        'pastoral_level',           h.pastoral_level,
        'effective_from',           la.effective_from,
        'effective_to',             la.effective_to
      ) order by la.effective_from desc
    ), '[]'::jsonb)
    into v_serving_assignments
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join public.governance_nodes gn on gn.id = la.governance_node_id
    left join public.households h on h.id = la.governance_node_id
    where la.organization_id = p_organization_id
      and la.member_id = v_caller_member_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader');

    -- Where I Receive Pastoral Care (current primary household)
    select jsonb_build_object(
      'household_id',            h.id,
      'household_name',          gn.name,
      'pastoral_level',          h.pastoral_level,
      'scope_node_id',           p_rel.parent_node_id,
      'scope_node_name',         pn.name,
      'membership_role',         hm.membership_role,
      'effective_from',          hm.effective_from,
      'meeting_frequency',       h.meeting_frequency,
      'meeting_day_of_week',     h.meeting_day_of_week,
      'meeting_start_time',      to_char(h.meeting_start_time, 'HH24:MI:SS'),
      'meeting_timezone_name',   h.meeting_timezone_name,
      'is_fraternal',            (h.pastoral_level = 'fraternal')
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

  -- 8. Build Identity Block
  v_identity_json := jsonb_build_object(
    'profile_id',                          v_profile_id,
    'member_id',                           v_caller_member_id,
    'display_name',                        v_caller_display_name,
    'has_linked_member',                   (v_caller_member_id is not null),
    'serving_assignments',                 v_serving_assignments,
    'pastoral_membership',                 v_pastoral_membership,
    'pastoral_household_placement_needed', (v_caller_member_id is not null and v_pastoral_membership is null and jsonb_array_length(v_serving_assignments) > 0)
  );

  -- 9. Care Responsibilities (Where I am Pastorally Responsible)
  -- Echelon model:
  --   HSL -> members of Member Household they lead
  --   USL -> Household Leaders of Member Households under their Unit
  --   CSL -> Unit Leaders of Units under their Chapter
  --   ASL -> Chapter Leaders of Chapters under their Area
  if v_caller_member_id is not null and jsonb_array_length(v_serving_assignments) > 0 then
    with caller_roles as (
      select
        (item->>'leadership_assignment_id')::uuid as assignment_id,
        item->>'role_code' as role_code,
        (item->>'governance_node_id')::uuid as node_id,
        item->>'governance_node_name' as node_name
      from jsonb_array_elements(v_serving_assignments) item
    ),
    -- Branch A: HSL cares for members of the Member Household
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
    -- Branch B: USL cares for Household Leaders of Member Households under their Unit
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
    -- Branch C: CSL cares for Unit Leaders of Units under their Chapter
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
    -- Branch D: ASL cares for Chapter Leaders of Chapters under their Area
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
  end if;

  -- 10. Households Summary & Operational Calculation
  -- Build set-based household records filtered to caller governance scope
  with scoped_households as (
    select
      h.id as household_id,
      gn.name as household_name,
      h.pastoral_level,
      h.household_category,
      gn.lifecycle_status,
      h.is_couple_household,
      p_rel.parent_node_id as scope_node_id,
      pn.name as scope_node_name,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      count(hm.id) filter (
        where hm.membership_status in ('active', 'temporary')
          and hm.effective_from <= current_date
          and (hm.effective_to is null or hm.effective_to >= current_date)
      ) as member_count
    from public.households h
    join public.governance_nodes gn on gn.id = h.id and gn.organization_id = p_organization_id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn on pn.id = p_rel.parent_node_id
    left join public.household_memberships hm
      on hm.household_node_id = h.id
     and hm.organization_id = p_organization_id
    where h.organization_id = p_organization_id
      -- Filter to specific governance node if passed, or enforce caller scope
      and (
        v_target_scope_node_id is null
        or h.id = v_target_scope_node_id
        or p_rel.parent_node_id = v_target_scope_node_id
        or exists (
          select 1 from public.governance_node_relationships anc
          where anc.parent_node_id = v_target_scope_node_id
            and anc.child_node_id = p_rel.parent_node_id
            and anc.organization_id = p_organization_id
            and anc.relationship_status = 'active'
        )
      )
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h.id)
    group by
      h.id, gn.name, h.pastoral_level, h.household_category, gn.lifecycle_status,
      h.is_couple_household, p_rel.parent_node_id, pn.name, h.target_member_count,
      h.maximum_member_count, h.accepts_new_members, h.meeting_frequency,
      h.meeting_day_of_week, h.meeting_start_time
  ),
  household_leaders as (
    select
      sh.household_id,
      case
        -- Member Household: formal office on household node itself
        when sh.pastoral_level = 'member' then la_hh.id
        -- Higher level: formal office on the parent scope governance node
        when sh.pastoral_level = 'unit' then la_scope.id
        when sh.pastoral_level = 'chapter' then la_scope.id
        when sh.pastoral_level = 'area' then la_scope.id
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
      -- Derived spouse
      case
        when sh.pastoral_level = 'fraternal' then null
        when sh.is_couple_household and sh.pastoral_level = 'member' and sp_hh.id is not null then sp_hh.display_name
        when sh.is_couple_household and sh.pastoral_level in ('unit', 'chapter', 'area') and sp_scope.id is not null then sp_scope.display_name
        else null
      end as derived_spouse_name
    from scoped_households sh
    -- Household formal leader (for member households)
    left join public.leadership_assignments la_hh
      on la_hh.governance_node_id = sh.household_id
     and la_hh.organization_id = p_organization_id
     and la_hh.assignment_status = 'active'
     and la_hh.effective_from <= current_date
     and (la_hh.effective_to is null or la_hh.effective_to >= current_date)
    left join public.leadership_role_definitions lrd_hh
      on lrd_hh.id = la_hh.leadership_role_definition_id
     and lrd_hh.code = 'household_servant_leader'
    left join public.members lm_hh on lm_hh.id = la_hh.member_id
    left join lateral (
      select m_sp.id, m_sp.display_name
      from public.family_relationships fr
      join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      join public.members m_sp on m_sp.id = case when fr.from_member_id = lm_hh.id then fr.to_member_id else fr.from_member_id end
      where fr.organization_id = p_organization_id
        and (fr.from_member_id = lm_hh.id or fr.to_member_id = lm_hh.id)
        and fr.relationship_status = 'active'
        and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
        and (fr.effective_to is null or fr.effective_to >= current_date)
      limit 1
    ) sp_hh on true
    -- Scope formal leader (for Unit, Chapter, Area households)
    left join public.leadership_assignments la_scope
      on la_scope.governance_node_id = sh.scope_node_id
     and la_scope.organization_id = p_organization_id
     and la_scope.assignment_status = 'active'
     and la_scope.effective_from <= current_date
     and (la_scope.effective_to is null or la_scope.effective_to >= current_date)
    left join public.leadership_role_definitions lrd_scope
      on lrd_scope.id = la_scope.leadership_role_definition_id
     and lrd_scope.code in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    left join public.members lm_scope on lm_scope.id = la_scope.member_id
    left join lateral (
      select m_sp.id, m_sp.display_name
      from public.family_relationships fr
      join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      join public.members m_sp on m_sp.id = case when fr.from_member_id = lm_scope.id then fr.to_member_id else fr.from_member_id end
      where fr.organization_id = p_organization_id
        and (fr.from_member_id = lm_scope.id or fr.to_member_id = lm_scope.id)
        and fr.relationship_status = 'active'
        and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
        and (fr.effective_to is null or fr.effective_to >= current_date)
      limit 1
    ) sp_scope on true
  ),
  classified_households as (
    select
      sh.*,
      hl.leadership_assignment_id,
      hl.leader_member_id,
      hl.leader_name,
      hl.role_code as leader_role_code,
      hl.role_name as leader_role_name,
      hl.derived_spouse_name,
      -- Leadership Status
      case
        when sh.pastoral_level = 'fraternal' then 'not_applicable'
        when hl.leader_member_id is not null then 'assigned'
        else 'vacant'
      end as leadership_status,
      -- Capacity Status (canonical Phase 6B-6 semantics)
      case
        when not sh.accepts_new_members then 'not_accepting'
        when sh.maximum_member_count is not null and sh.member_count >= sh.maximum_member_count then 'full'
        when sh.target_member_count is not null and sh.member_count >= sh.target_member_count then 'at_target'
        else 'available'
      end as capacity_status,
      -- Display title for couple
      case
        when sh.pastoral_level = 'fraternal' then 'Rotating facilitation — no permanent formal servant leader'
        when hl.derived_spouse_name is not null then
          case sh.pastoral_level
            when 'member' then 'Household Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'unit' then 'Unit Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'chapter' then 'Chapter Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'area' then 'Area Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            else hl.leader_name || ' & ' || hl.derived_spouse_name
          end
        when hl.leader_name is not null then hl.leader_name || ' (' || coalesce(hl.leader_role_name, 'Leader') || ')'
        else 'Vacant'
      end as leader_display_label
    from scoped_households sh
    join household_leaders hl on hl.household_id = sh.household_id
  ),
  with_operational_status as (
    select
      ch.*,
      -- Operational Status Precedence:
      -- 1. inactive
      -- 2. placement_review_required
      -- 3. needs_leader
      -- 4. at_capacity
      -- 5. not_accepting
      -- 6. needs_members
      -- 7. ready
      case
        when ch.lifecycle_status != 'active' then 'inactive'
        when ch.pastoral_level != 'fraternal' and ch.leadership_status = 'vacant' then 'needs_leader'
        when ch.capacity_status = 'full' then 'at_capacity'
        when ch.capacity_status = 'not_accepting' then 'not_accepting'
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
        'role_code',                wos.leader_role_code,
        'role_name',                wos.leader_role_name
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
      end,
      wos.household_name
  ), '[]'::jsonb)
  into v_households_summary
  from with_operational_status wos;

  -- 11. Capacity & Operational Aggregates
  select jsonb_build_object(
    'available',     count(*) filter (where item->>'capacity_status' = 'available'),
    'at_target',     count(*) filter (where item->>'capacity_status' = 'at_target'),
    'full',          count(*) filter (where item->>'capacity_status' = 'full'),
    'not_accepting', count(*) filter (where item->>'capacity_status' = 'not_accepting'),
    'total',         count(*)
  )
  into v_capacity_summary
  from jsonb_array_elements(v_households_summary) item;

  select jsonb_build_object(
    'ready',                     count(*) filter (where item->>'operational_status' = 'ready'),
    'needs_leader',              count(*) filter (where item->>'operational_status' = 'needs_leader'),
    'needs_members',             count(*) filter (where item->>'operational_status' = 'needs_members'),
    'at_capacity',               count(*) filter (where item->>'operational_status' = 'at_capacity'),
    'not_accepting',             count(*) filter (where item->>'operational_status' = 'not_accepting'),
    'placement_review_required', count(*) filter (where item->>'operational_status' = 'placement_review_required'),
    'inactive',                  count(*) filter (where item->>'operational_status' = 'inactive'),
    'total',                     count(*)
  )
  into v_operational_summary
  from jsonb_array_elements(v_households_summary) item;

  -- 12. Leadership Vacancies
  -- Gathers:
  --   A. Member Households without HSL
  --   B. Units without USL
  --   C. Chapters without CSL
  --   D. Areas without ASL
  -- (Fraternal is explicitly NOT vacant)
  with vacant_nodes as (
    -- Member Households
    select
      h.id as governance_node_id,
      gn.name as governance_node_name,
      'household_servant_leader'::text as role_code,
      'Household Servant Leader'::text as role_name,
      h.pastoral_level
    from public.households h
    join public.governance_nodes gn on gn.id = h.id and gn.organization_id = p_organization_id
    where h.organization_id = p_organization_id
      and gn.lifecycle_status = 'active'
      and h.pastoral_level = 'member'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = h.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'household_servant_leader'
      )
    union all
    -- Units without USL
    select
      un.id as governance_node_id,
      un.name as governance_node_name,
      'unit_servant_leader'::text as role_code,
      'Unit Servant Leader'::text as role_name,
      'unit'::text as pastoral_level
    from public.governance_nodes un
    join public.governance_node_types unt on unt.id = un.governance_node_type_id and unt.code = 'unit'
    where un.organization_id = p_organization_id
      and un.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, un.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = un.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'unit_servant_leader'
      )
    union all
    -- Chapters without CSL
    select
      chn.id as governance_node_id,
      chn.name as governance_node_name,
      'chapter_servant_leader'::text as role_code,
      'Chapter Servant Leader'::text as role_name,
      'chapter'::text as pastoral_level
    from public.governance_nodes chn
    join public.governance_node_types chnt on chnt.id = chn.governance_node_type_id and chnt.code = 'chapter'
    where chn.organization_id = p_organization_id
      and chn.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, chn.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = chn.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'chapter_servant_leader'
      )
    union all
    -- Areas without ASL
    select
      arn.id as governance_node_id,
      arn.name as governance_node_name,
      'area_servant_leader'::text as role_code,
      'Area Servant Leader'::text as role_name,
      'area'::text as pastoral_level
    from public.governance_nodes arn
    join public.governance_node_types arnt on arnt.id = arn.governance_node_type_id and arnt.code = 'area_state'
    where arn.organization_id = p_organization_id
      and arn.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, arn.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = arn.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'area_servant_leader'
      )
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'governance_node_id',   vn.governance_node_id,
      'governance_node_name', vn.governance_node_name,
      'role_code',            vn.role_code,
      'role_name',            vn.role_name,
      'pastoral_level',       vn.pastoral_level,
      'vacancy_status',       'vacant'
    ) order by vn.governance_node_name
  ), '[]'::jsonb)
  into v_leadership_vacancies
  from vacant_nodes vn;

  -- 13. Placement Review Summary Integration
  -- Reuses Phase 6B-6 canonical logic; if caller has leadership.pastoral_placement.review, returns items
  if v_can_review_placement then
    declare
      v_search_res jsonb;
    begin
      v_search_res := public.search_servant_leaders_needing_pastoral_placement(
        p_organization_id    => p_organization_id,
        p_include_correct    => false,
        p_limit              => 100,
        p_offset             => 0
      );

      select jsonb_build_object(
        'missing_household',               count(*) filter (where item->>'placement_status' = 'missing_household'),
        'different_level',                 count(*) filter (where item->>'placement_status' = 'different_level'),
        'no_matching_household_available', count(*) filter (where item->>'placement_status' = 'no_matching_household_available'),
        'manual_review_required',          count(*) filter (where item->>'placement_status' = 'manual_review_required'),
        'total',                           coalesce(v_search_res->>'total_count', '0')::integer,
        'actionable_items',                v_search_res->'items'
      )
      into v_placement_summary
      from jsonb_array_elements(coalesce(v_search_res->'items', '[]'::jsonb)) item;

      if v_placement_summary is null then
        v_placement_summary := jsonb_build_object(
          'missing_household', 0,
          'different_level', 0,
          'no_matching_household_available', 0,
          'manual_review_required', 0,
          'total', 0,
          'actionable_items', '[]'::jsonb
        );
      end if;
    end;
  else
    -- Without placement review permission, provide empty or safe count (total: 0, items: empty)
    v_placement_summary := jsonb_build_object(
      'missing_household', 0,
      'different_level', 0,
      'no_matching_household_available', 0,
      'manual_review_required', 0,
      'total', 0,
      'actionable_items', '[]'::jsonb
    );
  end if;

  -- 14. Unassigned Members Count (Members Without a Household)
  -- Active members in scope without current primary household
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

  -- 15. Return Unified Operational Dashboard Payload
  return jsonb_build_object(
    'organization_id',          p_organization_id,
    'identity',                 v_identity_json,
    'care_responsibilities',    v_care_responsibilities,
    'household_summary',        v_households_summary,
    'leadership_vacancies',     v_leadership_vacancies,
    'capacity_summary',         v_capacity_summary,
    'operational_summary',      v_operational_summary,
    'placement_review_summary', v_placement_summary,
    'unassigned_members_count', coalesce(v_unassigned_count, 0)
  );
end;
$$;

revoke all on function public.get_pastoral_operations_dashboard(uuid, uuid) from public, anon;
grant execute on function public.get_pastoral_operations_dashboard(uuid, uuid) to authenticated, service_role;

comment on function public.get_pastoral_operations_dashboard(uuid, uuid) is
  'Read-only operational dashboard returning identity, care responsibilities, household summaries, vacancies, capacity, placement review counts, and unassigned member counts.';

-- =============================================================================
-- SECTION 3: Public RPC public.get_pastoral_household_roster
-- =============================================================================

create or replace function public.get_pastoral_household_roster(
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
  v_profile_id             uuid;
  v_household              public.households%rowtype;
  v_household_node         public.governance_nodes%rowtype;
  v_parent_node            public.governance_nodes%rowtype;
  v_parent_rel             public.governance_node_relationships%rowtype;
  v_formal_leader          jsonb := null;
  v_derived_spouse_name    text := null;
  v_members_roster         jsonb := '[]'::jsonb;
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
    raise exception using errcode = '42501', message = 'You do not have permission to view the pastoral dashboard.';
  end if;

  -- 4. Roster Permission check
  if not private.has_permission('members.households.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household member rosters.';
  end if;

  -- 5. Scope check on target household (indistinguishable P0002)
  if not private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 6. Load household and governance node
  select * into v_household from public.households where id = p_household_id and organization_id = p_organization_id;
  select * into v_household_node from public.governance_nodes where id = p_household_id and organization_id = p_organization_id;

  if v_household.id is null or v_household_node.id is null then
    raise exception using errcode = 'P0002', message = 'Household record not found.';
  end if;

  -- Load parent scope
  select * into v_parent_rel
  from public.governance_node_relationships
  where child_node_id = p_household_id
    and organization_id = p_organization_id
    and relationship_type = 'primary_parent'
    and relationship_status = 'active'
    and (effective_to is null or effective_to >= current_date)
  limit 1;

  if v_parent_rel.parent_node_id is not null then
    select * into v_parent_node from public.governance_nodes where id = v_parent_rel.parent_node_id;
  end if;

  -- 7. Load leadership context
  if v_household.pastoral_level = 'member' then
    select jsonb_build_object(
      'leadership_assignment_id', la.id,
      'member_id',                m.id,
      'display_name',             m.display_name,
      'role_code',                lrd.code,
      'role_name',                lrd.name,
      'effective_from',           la.effective_from
    )
    into v_formal_leader
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'household_servant_leader'
    join public.members m on m.id = la.member_id
    where la.governance_node_id = p_household_id
      and la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
    limit 1;
  elsif v_household.pastoral_level in ('unit', 'chapter', 'area') and v_parent_rel.parent_node_id is not null then
    select jsonb_build_object(
      'leadership_assignment_id', la.id,
      'member_id',                m.id,
      'display_name',             m.display_name,
      'role_code',                lrd.code,
      'role_name',                lrd.name,
      'effective_from',           la.effective_from
    )
    into v_formal_leader
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
      and lrd.code in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    join public.members m on m.id = la.member_id
    where la.governance_node_id = v_parent_rel.parent_node_id
      and la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
    limit 1;
  end if;

  -- Derived spouse if Couples context
  if v_household.is_couple_household and v_formal_leader is not null and v_household.pastoral_level != 'fraternal' then
    select m_sp.display_name
    into v_derived_spouse_name
    from public.family_relationships fr
    join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
    join public.members m_sp on m_sp.id = case when fr.from_member_id = (v_formal_leader->>'member_id')::uuid then fr.to_member_id else fr.from_member_id end
    where fr.organization_id = p_organization_id
      and (fr.from_member_id = (v_formal_leader->>'member_id')::uuid or fr.to_member_id = (v_formal_leader->>'member_id')::uuid)
      and fr.relationship_status = 'active'
      and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
      and (fr.effective_to is null or fr.effective_to >= current_date)
    limit 1;
  end if;

  -- 8. Build privacy-minimized members roster
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'member_id',         m.id,
      'member_number',     m.member_number,
      'display_name',      m.display_name,
      'membership_id',     hm.id,
      'membership_role',   hm.membership_role,
      'membership_status', hm.membership_status,
      'effective_from',    hm.effective_from,
      'is_primary',        hm.is_primary
    ) order by
      case hm.membership_role
        when 'servant' then 1
        when 'assistant_servant' then 2
        else 3
      end,
      m.display_name
  ), '[]'::jsonb)
  into v_members_roster
  from public.household_memberships hm
  join public.members m on m.id = hm.member_id and m.organization_id = p_organization_id
  where hm.household_node_id = p_household_id
    and hm.organization_id = p_organization_id
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= current_date
    and (hm.effective_to is null or hm.effective_to >= current_date)
    and private.can_access_member('members.households.view', p_organization_id, m.id);

  -- 9. Return Roster Payload
  return jsonb_build_object(
    'household_id',            v_household.id,
    'household_name',          v_household_node.name,
    'household_category',      v_household.household_category,
    'pastoral_level',          v_household.pastoral_level,
    'lifecycle_status',        v_household_node.lifecycle_status,
    'is_couple_household',     v_household.is_couple_household,
    'scope_node_id',           v_parent_rel.parent_node_id,
    'scope_node_name',         v_parent_node.name,
    'target_member_count',     v_household.target_member_count,
    'maximum_member_count',    v_household.maximum_member_count,
    'accepts_new_members',     v_household.accepts_new_members,
    'meeting_frequency',       v_household.meeting_frequency,
    'meeting_day_of_week',     v_household.meeting_day_of_week,
    'meeting_start_time',      to_char(v_household.meeting_start_time, 'HH24:MI:SS'),
    'meeting_timezone_name',   v_household.meeting_timezone_name,
    'formal_leader',           v_formal_leader,
    'derived_leader_spouse',   v_derived_spouse_name,
    'is_fraternal',            (v_household.pastoral_level = 'fraternal'),
    'members_count',           jsonb_array_length(v_members_roster),
    'members',                 v_members_roster
  );
end;
$$;

revoke all on function public.get_pastoral_household_roster(uuid, uuid) from public, anon;
grant execute on function public.get_pastoral_household_roster(uuid, uuid) to authenticated, service_role;

comment on function public.get_pastoral_household_roster(uuid, uuid) is
  'Read-only, privacy-minimized household roster returning member identity, role, and placement status with zero sensitive contact or financial fields.';

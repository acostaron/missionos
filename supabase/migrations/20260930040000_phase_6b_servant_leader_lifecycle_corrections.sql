-- =============================================================================
-- Migration: 20260930040000_phase_6b_servant_leader_lifecycle_corrections.sql
-- Phase:     Phase 6B-5 — Servant Leader Appointment Lifecycle & Pastoral Placement Corrections
--
-- Authoritative Scope:
--   1. Ensure idempotent mapping of servant leader lifecycle permissions to
--      organization_administrator handling nullable organization_id.
--   2. Redefine public.appoint_servant_leader:
--      - Enforces that the target governance node must have lifecycle_status = 'active'.
--      - Planned or non-active nodes are rejected with 22023:
--        'Servant leaders may only be appointed to active governance nodes.'
--      - Preserves administrative fast-path timestamps (proposed, approved, accepted, activated).
--      - Preserves node and candidate member scope security checks.
--   3. Redefine public.get_servant_leader_pastoral_placement_guidance:
--      - Uses canonical spouse verification statuses:
--        ('member_confirmed', 'administrator_verified', 'document_verified').
--        Eliminates non-existent 'pastoral_verified'.
--      - Gating for Couples context:
--        Explicitly evaluates whether the leadership context is Couples (via household.is_couple_household = true
--        for household_servant_leader, or section context). If spouse is required in Couples context but
--        unresolved or unverified, sets placement_status = 'manual_review_required'.
--      - Placement status precedence:
--        1) Required Couples context with unresolved/unverified spouse -> 'manual_review_required'
--        2) No matching higher-level household in required scope -> 'no_matching_household_available'
--        3) Matching household exists but member has no current primary household -> 'missing_household'
--        4) Current primary household has wrong level OR wrong governance scope -> 'different_level'
--        5) Current primary household matches expected level AND scope node -> 'correct'
--      - Enforces both expected pastoral_level AND parent governance scope for 'correct':
--        The leader's current household must have parent_node_id = v_recommended_node_id.
--      - Scopes candidate member reads using members.households.view OR members.records.view.
--      - ZERO mutations.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Idempotent role_permissions mapping for organization_administrator
-- =============================================================================

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
  and p.code in (
    'leadership.servant_leaders.appoint',
    'leadership.servant_leaders.conclude',
    'leadership.servant_leaders.replace'
  )
  and not exists (
    select 1
    from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and coalesce(rp.organization_id, '00000000-0000-0000-0000-000000000000'::uuid) =
          coalesce(r.organization_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

-- =============================================================================
-- SECTION 2: Redefine public.appoint_servant_leader
-- =============================================================================

create or replace function public.appoint_servant_leader(
  p_organization_id    uuid,
  p_role_code          text,
  p_governance_node_id uuid,
  p_member_id          uuid,
  p_effective_from     date default current_date,
  p_reason             text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id         uuid;
  v_role_code          text;
  v_effective_from     date;
  v_node               public.governance_nodes%rowtype;
  v_node_type          public.governance_node_types%rowtype;
  v_role_def           public.leadership_role_definitions%rowtype;
  v_hh_level           text;
  v_member             public.members%rowtype;
  v_existing_active_id uuid;
  v_existing_holder_id uuid;
  v_new_assignment_id  uuid := gen_random_uuid();
  v_now                timestamptz := now();
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
  if not private.has_permission('leadership.servant_leaders.appoint', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to appoint servant leaders.';
  end if;

  -- 4. Canonical Role Code validation
  v_role_code := lower(trim(coalesce(p_role_code, '')));
  if v_role_code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    raise exception using errcode = '22023',
      message = 'Invalid servant leader role code: "' || v_role_code || '". Allowed canonical codes: household_servant_leader, unit_servant_leader, chapter_servant_leader, area_servant_leader.';
  end if;

  -- 5. Temporal MVP Policy: Future-effective appointments unsupported
  v_effective_from := coalesce(p_effective_from, current_date);
  if v_effective_from > current_date then
    raise exception using errcode = '22023', message = 'Future servant-leader changes are not supported yet.';
  end if;

  -- 6. Lock target governance node FOR UPDATE to prevent race conditions
  select *
  into v_node
  from public.governance_nodes gn
  where gn.id = p_governance_node_id
    and gn.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  -- Enforce active node lifecycle policy
  if v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Servant leaders may only be appointed to active governance nodes.';
  end if;

  -- 7. Governance scope check on target node
  if not private.can_access_governance_node('leadership.servant_leaders.appoint', p_organization_id, p_governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  -- 8. Resolve and validate node type
  select *
  into v_node_type
  from public.governance_node_types gnt
  where gnt.id = v_node.governance_node_type_id
    and gnt.organization_id = p_organization_id;

  -- 9. Resolve canonical role definition
  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.organization_id = p_organization_id
    and lrd.code = v_role_code
    and lrd.is_active = true;

  if not found then
    raise exception using errcode = '22023', message = 'Canonical leadership role "' || v_role_code || '" is not configured or active.';
  end if;

  -- 10. Role and Node Type Compatibility
  if v_role_code = 'household_servant_leader' then
    if v_node_type.code != 'household' then
      raise exception using errcode = '22023', message = 'Household Servant Leader must be appointed to a Household node.';
    end if;

    -- Phase 6B-4 Guard: only member households can have a formal Household Servant Leader
    select h.pastoral_level
    into v_hh_level
    from public.households h
    where h.id = v_node.id
      and h.organization_id = p_organization_id;

    if v_hh_level is distinct from 'member' then
      raise exception using errcode = '23514',
        message = 'Household Servant Leader appointment is only permitted on Member Households. This household has pastoral level: "' || coalesce(v_hh_level, 'unknown') || '".';
    end if;

  elsif v_role_code = 'unit_servant_leader' then
    if v_node_type.code != 'unit' then
      raise exception using errcode = '22023', message = 'Unit Servant Leader must be appointed to a Unit node.';
    end if;

  elsif v_role_code = 'chapter_servant_leader' then
    if v_node_type.code != 'chapter' then
      raise exception using errcode = '22023', message = 'Chapter Servant Leader must be appointed to a Chapter node.';
    end if;

  elsif v_role_code = 'area_servant_leader' then
    if v_node_type.code != 'area_state' then
      raise exception using errcode = '22023', message = 'Area Servant Leader must be appointed to an Area/State node.';
    end if;
  end if;

  -- 11. Candidate Member Validation & Scope
  select *
  into v_member
  from public.members m
  where m.id = p_member_id
    and m.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidate member not found or not accessible.';
  end if;

  if not private.can_access_member('leadership.servant_leaders.appoint', p_organization_id, p_member_id) then
    raise exception using errcode = 'P0002', message = 'Candidate member not found or not accessible.';
  end if;

  if v_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Candidate member record is not active.';
  end if;

  if v_member.is_deceased then
    raise exception using errcode = '22023', message = 'Cannot appoint a deceased member as servant leader.';
  end if;

  -- 12. Check for duplicate active assignment for same member, role, and node
  select la.id
  into v_existing_active_id
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.member_id = p_member_id
    and la.governance_node_id = p_governance_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date)
  limit 1;

  if v_existing_active_id is not null then
    raise exception using errcode = '22023', message = 'This member already holds an active appointment for this role on this node.';
  end if;

  -- 13. Single office holder check on target node
  select la.id
  into v_existing_holder_id
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_governance_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date)
  limit 1;

  if v_existing_holder_id is not null then
    raise exception using errcode = '22023',
      message = 'An active servant leader already holds this role on this node. Use the Replace workflow instead of Appoint.';
  end if;

  -- 14. Administrative Fast-Path Insert into public.leadership_assignments
  insert into public.leadership_assignments (
    id,
    organization_id,
    member_id,
    governance_node_id,
    leadership_role_definition_id,
    paired_assignment_id,
    assignment_status,
    appointment_type,
    effective_from,
    effective_to,
    proposed_at,
    proposed_by_profile_id,
    approved_at,
    approved_by_profile_id,
    accepted_at,
    activated_at,
    appointment_summary,
    metadata,
    created_at,
    created_by_profile_id,
    updated_at,
    updated_by_profile_id
  ) values (
    v_new_assignment_id,
    p_organization_id,
    p_member_id,
    p_governance_node_id,
    v_role_def.id,
    null,
    'active',
    'regular',
    v_effective_from,
    null,
    v_now,
    v_profile_id,
    v_now,
    v_profile_id,
    v_now,
    v_now,
    trim(coalesce(p_reason, '')),
    jsonb_build_object(
      'role_code',            v_role_code,
      'appointed_by_profile', v_profile_id,
      'fast_path',            true
    ),
    v_now,
    v_profile_id,
    v_now,
    v_profile_id
  );

  -- 15. Record Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader.appointed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => v_new_assignment_id,
    p_action           => 'appoint',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'role_code',                v_role_code,
      'governance_node_id',       p_governance_node_id,
      'governance_node_name',     v_node.name,
      'member_id',                p_member_id,
      'effective_from',           v_effective_from,
      'reason',                   p_reason
    )
  );

  return jsonb_build_object(
    'status',                   'appointed',
    'organization_id',          p_organization_id,
    'leadership_assignment_id', v_new_assignment_id,
    'governance_node_id',       p_governance_node_id,
    'governance_node_name',     v_node.name,
    'member_id',                p_member_id,
    'member_name',              v_member.display_name,
    'role_code',                v_role_code,
    'role_name',                v_role_def.name,
    'effective_from',           v_effective_from
  );
end;
$$;

comment on function public.appoint_servant_leader(uuid, text, uuid, uuid, date, text) is
  'Appoints a candidate member to a canonical servant-leader role. Enforces role-to-node validation, active node status, Phase 6B-4 formal household rules, single active cardinality, and temporal constraints.';

revoke execute on function public.appoint_servant_leader(uuid, text, uuid, uuid, date, text) from public, anon;
grant  execute on function public.appoint_servant_leader(uuid, text, uuid, uuid, date, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: Redefine public.get_servant_leader_pastoral_placement_guidance
-- =============================================================================

create or replace function public.get_servant_leader_pastoral_placement_guidance(
  p_organization_id           uuid,
  p_member_id                 uuid,
  p_leadership_assignment_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id             uuid;
  v_member                 public.members%rowtype;
  v_assignment             public.leadership_assignments%rowtype;
  v_role_def               public.leadership_role_definitions%rowtype;
  v_gov_node               public.governance_nodes%rowtype;
  v_gov_node_type          public.governance_node_types%rowtype;
  v_current_hh_id          uuid;
  v_current_hh_name        text;
  v_current_hh_parent_id   uuid;
  v_current_pastoral_level text;
  v_recommended_level      text;
  v_recommended_node_id    uuid;
  v_recommended_node_name  text;
  v_matching_hh_count      integer := 0;
  v_placement_status       text;
  v_is_couple_context      boolean := false;
  v_spouse_id              uuid;
  v_spouse_name            text;
  v_spouse_verified        boolean := false;
  v_has_any_spouse         boolean := false;
  v_parent_rel             public.governance_node_relationships%rowtype;
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

  -- 3. Scope check on member using members.households.view or members.records.view
  if not (
    private.can_access_member('members.households.view', p_organization_id, p_member_id)
    or private.can_access_member('members.records.view', p_organization_id, p_member_id)
  ) then
    raise exception using errcode = 'P0002', message = 'Member record not found or not accessible.';
  end if;

  select * into v_member from public.members where id = p_member_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Member record not found.';
  end if;

  -- 4. Resolve leadership assignment
  if p_leadership_assignment_id is not null then
    select *
    into v_assignment
    from public.leadership_assignments la
    where la.id = p_leadership_assignment_id
      and la.organization_id = p_organization_id
      and la.member_id = p_member_id;
  else
    -- Resolve most recent active canonical pastoral assignment
    select la.*
    into v_assignment
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    where la.organization_id = p_organization_id
      and la.member_id = p_member_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    order by la.effective_from desc
    limit 1;
  end if;

  if v_assignment.id is null then
    return jsonb_build_object(
      'has_formal_role', false,
      'member_id',       p_member_id,
      'message',         'No active canonical servant leader assignment found for this member.'
    );
  end if;

  -- Resolve role definition
  select * into v_role_def from public.leadership_role_definitions where id = v_assignment.leadership_role_definition_id;

  -- Resolve governance node where leader serves
  select * into v_gov_node from public.governance_nodes where id = v_assignment.governance_node_id;
  select * into v_gov_node_type from public.governance_node_types where id = v_gov_node.governance_node_type_id;

  -- 5. Determine recommended pastoral level and parent scope node
  -- - household_servant_leader (leads member hh)         -> receives care in Unit Household (parent Unit of Household)
  -- - unit_servant_leader (leads unit)                  -> receives care in Chapter Household (parent Chapter of Unit)
  -- - chapter_servant_leader (leads chapter)            -> receives care in Area Household (parent Area of Chapter)
  -- - area_servant_leader (leads area)                  -> receives care in Fraternal Household (at Area node)
  if v_role_def.code = 'household_servant_leader' then
    v_recommended_level := 'unit';
    -- Scope node is the parent Unit of this household
    select gnr.* into v_parent_rel
    from public.governance_node_relationships gnr
    where gnr.child_node_id = v_gov_node.id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and gnr.effective_from <= current_date
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    limit 1;

    v_recommended_node_id := v_parent_rel.parent_node_id;

    -- Check if target household is a Couples household
    select coalesce(h.is_couple_household, false)
    into v_is_couple_context
    from public.households h
    where h.id = v_gov_node.id
      and h.organization_id = p_organization_id;

  elsif v_role_def.code = 'unit_servant_leader' then
    v_recommended_level := 'chapter';
    -- Scope node is the parent Chapter of this unit
    select gnr.* into v_parent_rel
    from public.governance_node_relationships gnr
    where gnr.child_node_id = v_gov_node.id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and gnr.effective_from <= current_date
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    limit 1;

    v_recommended_node_id := v_parent_rel.parent_node_id;

  elsif v_role_def.code = 'chapter_servant_leader' then
    v_recommended_level := 'area';
    -- Scope node is the parent Area/State of this chapter
    select gnr.* into v_parent_rel
    from public.governance_node_relationships gnr
    where gnr.child_node_id = v_gov_node.id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and gnr.effective_from <= current_date
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    limit 1;

    v_recommended_node_id := v_parent_rel.parent_node_id;

  elsif v_role_def.code = 'area_servant_leader' then
    v_recommended_level := 'fraternal';
    -- Scope node is the Area/State node itself
    v_recommended_node_id := v_gov_node.id;
  end if;

  if v_recommended_node_id is not null then
    select name into v_recommended_node_name from public.governance_nodes where id = v_recommended_node_id;
  end if;

  -- 6. Check Current Primary Household of Member and its parent governance node
  select
    hm.household_node_id,
    gn.name,
    h.pastoral_level,
    gnr.parent_node_id
  into
    v_current_hh_id,
    v_current_hh_name,
    v_current_pastoral_level,
    v_current_hh_parent_id
  from public.household_memberships hm
  join public.governance_nodes gn on gn.id = hm.household_node_id
  join public.households h on h.id = hm.household_node_id
  left join public.governance_node_relationships gnr
    on gnr.child_node_id = gn.id
   and gnr.organization_id = p_organization_id
   and gnr.relationship_type = 'primary_parent'
   and gnr.relationship_status = 'active'
   and gnr.effective_from <= current_date
   and (gnr.effective_to is null or gnr.effective_to >= current_date)
  where hm.member_id = p_member_id
    and hm.organization_id = p_organization_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= current_date
    and (hm.effective_to is null or hm.effective_to >= current_date)
  limit 1;

  -- 7. Count matching active households available at the recommended level and scope
  if v_recommended_node_id is not null then
    select count(*)
    into v_matching_hh_count
    from public.households h
    join public.governance_nodes gn on gn.id = h.id
    join public.governance_node_relationships gnr
      on gnr.child_node_id = h.id
     and gnr.organization_id = h.organization_id
     and gnr.relationship_type = 'primary_parent'
     and gnr.relationship_status = 'active'
     and gnr.effective_from <= current_date
     and (gnr.effective_to is null or gnr.effective_to >= current_date)
    where h.organization_id = p_organization_id
      and h.pastoral_level = v_recommended_level
      and gn.lifecycle_status = 'active'
      and gnr.parent_node_id = v_recommended_node_id;
  else
    v_matching_hh_count := 0;
  end if;

  -- 8. Evaluate Spouse Relationship Context
  -- Check if member has any spouse relationship
  select
    target_spouse.member_id,
    sm.display_name,
    (fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified'))
  into
    v_spouse_id,
    v_spouse_name,
    v_spouse_verified
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
  cross join lateral (
    values (case when fr.from_member_id = p_member_id then fr.to_member_id else fr.from_member_id end)
  ) as target_spouse(member_id)
  join public.members sm on sm.id = target_spouse.member_id and sm.organization_id = p_organization_id
  where fr.organization_id = p_organization_id
    and fr.relationship_status = 'active'
    and (fr.effective_from is null or fr.effective_from <= current_date)
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id)
  order by
    case when fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified') then 0 else 1 end,
    fr.created_at desc
  limit 1;

  if v_spouse_id is not null then
    v_has_any_spouse := true;
  end if;

  -- 9. Determine Placement Status with Strict Precedence
  -- Precedence:
  --   1. Required Couples context but spouse unresolved or unverified -> 'manual_review_required'
  --   2. No matching higher-level household in required scope -> 'no_matching_household_available'
  --   3. Matching household exists but member has no current primary household -> 'missing_household'
  --   4. Current primary household exists but pastoral level OR governance scope is wrong -> 'different_level'
  --   5. Current primary household has expected pastoral level AND expected governance scope -> 'correct'
  if v_is_couple_context and (not v_has_any_spouse or not v_spouse_verified) then
    v_placement_status := 'manual_review_required';
  elsif v_matching_hh_count = 0 then
    v_placement_status := 'no_matching_household_available';
  elsif v_current_hh_id is null then
    v_placement_status := 'missing_household';
  elsif v_current_pastoral_level = v_recommended_level and v_current_hh_parent_id = v_recommended_node_id then
    v_placement_status := 'correct';
  else
    v_placement_status := 'different_level';
  end if;

  -- Return comprehensive read-only guidance
  return jsonb_build_object(
    'member_id',                     p_member_id,
    'member_name',                   v_member.display_name,
    'has_formal_role',               true,
    'leadership_assignment_id',      v_assignment.id,
    'role_code',                     v_role_def.code,
    'role_name',                     v_role_def.name,
    'governance_node_id',            v_gov_node.id,
    'governance_node_name',          v_gov_node.name,
    'current_primary_household_id',  v_current_hh_id,
    'current_primary_household_name',v_current_hh_name,
    'current_pastoral_level',        v_current_pastoral_level,
    'current_household_parent_id',   v_current_hh_parent_id,
    'recommended_pastoral_level',    v_recommended_level,
    'recommended_scope_node_id',     v_recommended_node_id,
    'recommended_scope_node_name',   v_recommended_node_name,
    'matching_echelon_households_count', v_matching_hh_count,
    'placement_status',              v_placement_status,
    'is_couple_context',             v_is_couple_context,
    'spouse_context', jsonb_build_object(
      'has_spouse',                  v_has_any_spouse,
      'has_verified_spouse',         v_spouse_verified,
      'spouse_member_id',            v_spouse_id,
      'spouse_name',                 v_spouse_name,
      'evaluation_rule',             'In Couples section, formal servant leader husband and verified wife receive pastoral nourishment together in higher echelon household'
    )
  );
end;
$$;

comment on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) is
  'Read-only RPC returning authoritative pastoral placement recommendation based on formal leadership office. Zero mutations.';

revoke execute on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) from public, anon;
grant  execute on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) to authenticated, service_role;

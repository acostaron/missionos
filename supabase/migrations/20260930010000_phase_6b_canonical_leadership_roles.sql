-- =============================================================================
-- Migration: 20260930010000_phase_6b_canonical_leadership_roles.sql
-- Phase:     Phase 6B-3 — MFC Canonical Pastoral Leadership Offices & Seed
--
-- Authoritative Canonical Roles Defined:
--   1. Household Servant Leader (household_servant_leader) -> scope: household (rank 70)
--   2. Unit Servant Leader      (unit_servant_leader)      -> scope: unit      (rank 60)
--   3. Chapter Servant Leader   (chapter_servant_leader)   -> scope: chapter   (rank 50)
--   4. Area Servant Leader      (area_servant_leader)      -> scope: area_state (rank 30)
--
-- Domain Rules Enforced:
--   - leadership_category = 'pastoral' (intentional MissionOS domain convention)
--   - appointment_scope_type = 'governance_node'
--   - cardinality_type = 'single', minimum_assignees = 0, maximum_assignees = 1 (vacancy allowed)
--   - default_term_months = NULL, maximum_term_months = NULL (no invented term limits)
--   - allows_interim_assignment = true (column default preserved)
--   - requires_approval = true
--   - requires_couple_pair = false (husband holds formal office; pastoral couple is derived)
--   - creates_application_access_review = false (zero application authorization created)
--   - Exactly one organization resolved dynamically; aborts if zero or multiple.
--   - Safe, explicit INSERT with existence validation (fails if codes already exist).
--   - Corrective RPC definitions replacing legacy 'household_servant' references.
--   - Software app_roles remain untouched.
-- =============================================================================

do $$
declare
  v_org_id                           uuid;
  v_org_count                        integer;
  v_existing_roles_count             integer;

  -- Governance Node Types
  v_type_household_id                uuid;
  v_type_unit_id                     uuid;
  v_type_chapter_id                  uuid;
  v_type_area_state_id               uuid;

  -- Role Definition IDs
  v_role_household_servant_leader_id uuid;
  v_role_unit_servant_leader_id      uuid;
  v_role_chapter_servant_leader_id   uuid;
  v_role_area_servant_leader_id      uuid;
begin
  -- ---------------------------------------------------------------------------
  -- 1. Deterministic Organization Resolution
  -- ---------------------------------------------------------------------------
  select count(*) into v_org_count from public.organizations;
  if v_org_count <> 1 then
    raise exception using
      errcode = 'P0002',
      message = 'Deterministic organization resolution failed: expected exactly 1 organization, found ' || v_org_count;
  end if;

  select id into strict v_org_id from public.organizations limit 1;

  -- ---------------------------------------------------------------------------
  -- 2. Resolve Governance Node Type IDs
  -- ---------------------------------------------------------------------------
  select id into strict v_type_household_id
  from public.governance_node_types
  where organization_id = v_org_id and code = 'household';

  select id into strict v_type_unit_id
  from public.governance_node_types
  where organization_id = v_org_id and code = 'unit';

  select id into strict v_type_chapter_id
  from public.governance_node_types
  where organization_id = v_org_id and code = 'chapter';

  select id into strict v_type_area_state_id
  from public.governance_node_types
  where organization_id = v_org_id and code = 'area_state';

  -- ---------------------------------------------------------------------------
  -- 3. Idempotency & Safety: Verify Canonical Codes Do Not Already Exist
  -- ---------------------------------------------------------------------------
  select count(*) into v_existing_roles_count
  from public.leadership_role_definitions
  where organization_id = v_org_id
    and code in (
      'household_servant_leader',
      'unit_servant_leader',
      'chapter_servant_leader',
      'area_servant_leader'
    );

  if v_existing_roles_count > 0 then
    raise exception using
      errcode = '23505',
      message = 'One or more canonical leadership role codes already exist for organization ' || v_org_id;
  end if;

  -- ---------------------------------------------------------------------------
  -- 4. Seed Exactly Four Canonical Pastoral Role Definitions
  -- ---------------------------------------------------------------------------
  v_role_household_servant_leader_id := gen_random_uuid();
  insert into public.leadership_role_definitions (
    id,
    organization_id,
    code,
    name,
    description,
    leadership_category,
    appointment_scope_type,
    cardinality_type,
    minimum_assignees,
    maximum_assignees,
    requires_approval,
    requires_couple_pair,
    creates_application_access_review,
    default_term_months,
    maximum_term_months,
    allows_interim_assignment,
    is_active,
    display_order
  ) values (
    v_role_household_servant_leader_id,
    v_org_id,
    'household_servant_leader',
    'Household Servant Leader',
    'Formal pastoral leader appointed to shepherd a household.',
    'pastoral',
    'governance_node',
    'single',
    0,
    1,
    true,
    false,
    false,
    null,
    null,
    true,
    true,
    10
  );

  v_role_unit_servant_leader_id := gen_random_uuid();
  insert into public.leadership_role_definitions (
    id,
    organization_id,
    code,
    name,
    description,
    leadership_category,
    appointment_scope_type,
    cardinality_type,
    minimum_assignees,
    maximum_assignees,
    requires_approval,
    requires_couple_pair,
    creates_application_access_review,
    default_term_months,
    maximum_term_months,
    allows_interim_assignment,
    is_active,
    display_order
  ) values (
    v_role_unit_servant_leader_id,
    v_org_id,
    'unit_servant_leader',
    'Unit Servant Leader',
    'Pastoral and governance servant leader of a Unit.',
    'pastoral',
    'governance_node',
    'single',
    0,
    1,
    true,
    false,
    false,
    null,
    null,
    true,
    true,
    20
  );

  v_role_chapter_servant_leader_id := gen_random_uuid();
  insert into public.leadership_role_definitions (
    id,
    organization_id,
    code,
    name,
    description,
    leadership_category,
    appointment_scope_type,
    cardinality_type,
    minimum_assignees,
    maximum_assignees,
    requires_approval,
    requires_couple_pair,
    creates_application_access_review,
    default_term_months,
    maximum_term_months,
    allows_interim_assignment,
    is_active,
    display_order
  ) values (
    v_role_chapter_servant_leader_id,
    v_org_id,
    'chapter_servant_leader',
    'Chapter Servant Leader',
    'Pastoral and governance servant leader of a Chapter.',
    'pastoral',
    'governance_node',
    'single',
    0,
    1,
    true,
    false,
    false,
    null,
    null,
    true,
    true,
    30
  );

  v_role_area_servant_leader_id := gen_random_uuid();
  insert into public.leadership_role_definitions (
    id,
    organization_id,
    code,
    name,
    description,
    leadership_category,
    appointment_scope_type,
    cardinality_type,
    minimum_assignees,
    maximum_assignees,
    requires_approval,
    requires_couple_pair,
    creates_application_access_review,
    default_term_months,
    maximum_term_months,
    allows_interim_assignment,
    is_active,
    display_order
  ) values (
    v_role_area_servant_leader_id,
    v_org_id,
    'area_servant_leader',
    'Area Servant Leader',
    'Pastoral and governance servant leader of an Area.',
    'pastoral',
    'governance_node',
    'single',
    0,
    1,
    true,
    false,
    false,
    null,
    null,
    true,
    true,
    40
  );

  -- ---------------------------------------------------------------------------
  -- 5. Seed Exactly Four Primary Node-Type Mappings
  -- ---------------------------------------------------------------------------
  -- Household Servant Leader -> Household (rank 70)
  insert into public.leadership_role_node_types (
    id,
    organization_id,
    leadership_role_definition_id,
    governance_node_type_id,
    is_primary_mapping,
    minimum_node_rank,
    maximum_node_rank,
    is_active
  ) values (
    gen_random_uuid(),
    v_org_id,
    v_role_household_servant_leader_id,
    v_type_household_id,
    true,
    70,
    70,
    true
  );

  -- Unit Servant Leader -> Unit (rank 60)
  insert into public.leadership_role_node_types (
    id,
    organization_id,
    leadership_role_definition_id,
    governance_node_type_id,
    is_primary_mapping,
    minimum_node_rank,
    maximum_node_rank,
    is_active
  ) values (
    gen_random_uuid(),
    v_org_id,
    v_role_unit_servant_leader_id,
    v_type_unit_id,
    true,
    60,
    60,
    true
  );

  -- Chapter Servant Leader -> Chapter (rank 50)
  insert into public.leadership_role_node_types (
    id,
    organization_id,
    leadership_role_definition_id,
    governance_node_type_id,
    is_primary_mapping,
    minimum_node_rank,
    maximum_node_rank,
    is_active
  ) values (
    gen_random_uuid(),
    v_org_id,
    v_role_chapter_servant_leader_id,
    v_type_chapter_id,
    true,
    50,
    50,
    true
  );

  -- Area Servant Leader -> Area or State (rank 30)
  insert into public.leadership_role_node_types (
    id,
    organization_id,
    leadership_role_definition_id,
    governance_node_type_id,
    is_primary_mapping,
    minimum_node_rank,
    maximum_node_rank,
    is_active
  ) values (
    gen_random_uuid(),
    v_org_id,
    v_role_area_servant_leader_id,
    v_type_area_state_id,
    true,
    30,
    30,
    true
  );

  -- ---------------------------------------------------------------------------
  -- 6. Safety Assertions: Validate Post-Seed Invariants
  -- ---------------------------------------------------------------------------
  assert (
    select count(*)
    from public.leadership_role_definitions
    where organization_id = v_org_id
      and is_active
      and code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
  ) = 4, 'Safety Assertion Failed: expected exactly 4 active canonical leadership roles';

  assert (
    select count(*)
    from public.leadership_role_node_types lrnt
    join public.leadership_role_definitions lrd on lrd.id = lrnt.leadership_role_definition_id
    where lrnt.organization_id = v_org_id
      and lrnt.is_active
      and lrnt.is_primary_mapping
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
  ) = 4, 'Safety Assertion Failed: expected exactly 4 active primary leadership role node mappings';
end $$;

-- =============================================================================
-- 7. Corrective RPC Definitions: Update Live RPCs to Canonical Code
-- =============================================================================

-- 7A. Update public.get_household_profile: uses canonical 'household_servant_leader'
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

  -- 4. Governance-scoped access check
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Identifier permission for roster member numbers
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Build profile payload
  with household_identity as (
    select
      gn.id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
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
  formal_leaders as (
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from public.leadership_assignments la
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where la.governance_node_id = p_household_id
      and la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
    order by coalesce(lrd.display_order, 999) asc, m.display_name asc
  ),
  couple_leaders as (
    select
      servant.member_id as servant_member_id,
      servant.display_name as servant_display_name,
      servant.effective_from as servant_effective_from,
      spouse_mem.member_id as spouse_member_id,
      spouse_mem.display_name as spouse_display_name
    from formal_leaders servant
    join household_identity hi on hi.is_couple_household = true
    -- Look up canonical spouse relationship in family_relationships
    join public.family_relationships fr
      on fr.organization_id = p_organization_id
     and fr.relationship_status = 'active'
     and fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')
     and (fr.effective_from is null or fr.effective_from <= current_date)
     and (fr.effective_to is null or fr.effective_to >= current_date)
     and (fr.from_member_id = servant.member_id or fr.to_member_id = servant.member_id)
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
     and frt.code = 'spouse'
    cross join lateral (
      values (case when fr.from_member_id = servant.member_id then fr.to_member_id else fr.from_member_id end)
    ) as target_spouse(member_id)
    -- Spouse MUST also be an active member of this same household
    join active_members spouse_mem
      on spouse_mem.member_id = target_spouse.member_id
    where servant.leadership_role_code = 'household_servant_leader'
    limit 1
  )
  select jsonb_build_object(
    'household', (
      select jsonb_build_object(
        'id', hi.id,
        'name', hi.name,
        'code', hi.code,
        'lifecycle_status', hi.lifecycle_status,
        'household_category', hi.household_category,
        'effective_from', hi.effective_from,
        'effective_to', hi.effective_to,
        'meeting_frequency', hi.meeting_frequency,
        'meeting_day_of_week', hi.meeting_day_of_week,
        'meeting_start_time', hi.meeting_start_time,
        'meeting_timezone_name', hi.meeting_timezone_name,
        'meeting_location_type', hi.meeting_location_type,
        'target_member_count', hi.target_member_count,
        'maximum_member_count', hi.maximum_member_count,
        'accepts_new_members', hi.accepts_new_members,
        'language_code', hi.language_code,
        'is_couple_household', hi.is_couple_household
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
    'leaders', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'leadership_assignment_id', fl.leadership_assignment_id,
            'member_id',                fl.member_id,
            'display_name',             fl.display_name,
            'leadership_role_code',     fl.leadership_role_code,
            'leadership_role_name',     fl.leadership_role_name,
            'assignment_status',        fl.assignment_status,
            'effective_from',           fl.effective_from,
            'effective_to',             fl.effective_to
          )
        )
        from formal_leaders fl
      ),
      '[]'::jsonb
    ),
    'household_leaders', (
      select jsonb_build_object(
        'husband', jsonb_build_object(
          'member_id',    cl.servant_member_id,
          'display_name', cl.servant_display_name
        ),
        'wife', jsonb_build_object(
          'member_id',    cl.spouse_member_id,
          'display_name', cl.spouse_display_name
        ),
        'pastoral_label', 'Household Leaders',
        'formatted_names', cl.servant_display_name || ' & ' || cl.spouse_display_name,
        'effective_from', cl.servant_effective_from
      )
      from couple_leaders cl
      limit 1
    ),
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
    )
  ) into v_profile_data;

  return v_profile_data;
end;
$$;

comment on function public.get_household_profile(uuid, uuid) is
  'Returns the complete pastoral household profile using canonical household_servant_leader role definition.';

-- 7B. Update public.get_member_households: uses canonical 'household_servant_leader'
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

  -- 4. Governance-scoped access check for the member
  if not private.can_access_member('members.households.view', p_organization_id, p_member_id) then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  -- 5. Query member household assignments with canonical leader join
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
        'household_servant_name',  servant.display_name
      )
      order by hm.is_primary desc, hm.effective_from desc
    ),
    '[]'::jsonb
  ) into v_households
  from public.household_memberships hm
  join public.governance_nodes gn
    on gn.id = hm.household_node_id
   and gn.organization_id = hm.organization_id
  join public.households h
    on h.id = gn.id
   and h.organization_id = gn.organization_id
  left join lateral (
    select
      gnr.parent_node_id,
      pgn.name as parent_node_name,
      pgnt.code as parent_node_type
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    join public.governance_node_types pgnt
      on pgnt.id = pgn.governance_node_type_id
     and pgnt.organization_id = pgn.organization_id
    where gnr.child_node_id = gn.id
      and gnr.organization_id = gn.organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ) p_gov on true
  left join lateral (
    select m_lead.display_name
    from public.leadership_assignments la
    join public.members m_lead
      on m_lead.id = la.member_id
     and m_lead.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where la.governance_node_id = gn.id
      and la.organization_id = gn.organization_id
      and la.assignment_status = 'active'
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'household_servant_leader'
    order by la.effective_from desc
    limit 1
  ) servant on true
  where hm.member_id = p_member_id
    and hm.organization_id = p_organization_id
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= current_date);

  return v_households;
end;
$$;

comment on function public.get_member_households(uuid, uuid) is
  'Returns active household assignments for a member using canonical household_servant_leader role.';

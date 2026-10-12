-- =============================================================================
-- Migration 108: area_section_coordinators_foundation
--
-- Description:
--   1. Inserts canonical role definitions:
--      - area_section_coordinator ("Area Section Coordinator")
--      - fmc_coordinator ("FMC Coordinator")
--   2. Inserts leadership_role_node_types mappings:
--      - area_section_coordinator -> section
--      - fmc_coordinator -> area_state
--   3. Implements private.section_coordinator_eligibility(p_org, p_member, p_section_node)
--   4. Implements private.appoint_area_coordinator_core(...)
--   5. Implements public.appoint_area_coordinator(...)
--   6. Implements public.end_area_coordinator(...)
--   7. Creates staging.coordinator_import table for batch import
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Role Definitions
-- -----------------------------------------------------------------------------

insert into public.leadership_role_definitions (
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
  is_active,
  display_order
)
select
  o.id,
  'area_section_coordinator',
  'Area Section Coordinator',
  'Area Section Coordinator for an MFC section',
  'section',
  'section',
  'single',
  0,
  1,
  true,
  false,
  true,
  true,
  50
from public.organizations o
on conflict (organization_id, code) do update
set name = excluded.name,
    description = excluded.description,
    leadership_category = excluded.leadership_category,
    appointment_scope_type = excluded.appointment_scope_type,
    cardinality_type = excluded.cardinality_type,
    minimum_assignees = excluded.minimum_assignees,
    maximum_assignees = excluded.maximum_assignees,
    requires_approval = excluded.requires_approval,
    requires_couple_pair = excluded.requires_couple_pair,
    creates_application_access_review = excluded.creates_application_access_review,
    is_active = excluded.is_active;

insert into public.leadership_role_definitions (
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
  is_active,
  display_order
)
select
  o.id,
  'fmc_coordinator',
  'FMC Coordinator',
  'FMC Coordinator for Area',
  'section',
  'governance_node',
  'single',
  0,
  1,
  true,
  false,
  true,
  true,
  55
from public.organizations o
on conflict (organization_id, code) do update
set name = excluded.name,
    description = excluded.description,
    leadership_category = excluded.leadership_category,
    appointment_scope_type = excluded.appointment_scope_type,
    cardinality_type = excluded.cardinality_type,
    minimum_assignees = excluded.minimum_assignees,
    maximum_assignees = excluded.maximum_assignees,
    requires_approval = excluded.requires_approval,
    requires_couple_pair = excluded.requires_couple_pair,
    creates_application_access_review = excluded.creates_application_access_review,
    is_active = excluded.is_active;

-- -----------------------------------------------------------------------------
-- 2. Role Node Types
-- -----------------------------------------------------------------------------

insert into public.leadership_role_node_types (
  organization_id,
  leadership_role_definition_id,
  governance_node_type_id,
  is_primary_mapping,
  is_active
)
select
  lrd.organization_id,
  lrd.id,
  gnt.id,
  true,
  true
from public.leadership_role_definitions lrd
join public.governance_node_types gnt on gnt.organization_id = lrd.organization_id and gnt.code = 'section'
where lrd.code = 'area_section_coordinator'
on conflict (organization_id, leadership_role_definition_id, governance_node_type_id) do update
set is_primary_mapping = excluded.is_primary_mapping,
    is_active = excluded.is_active;

insert into public.leadership_role_node_types (
  organization_id,
  leadership_role_definition_id,
  governance_node_type_id,
  is_primary_mapping,
  is_active
)
select
  lrd.organization_id,
  lrd.id,
  gnt.id,
  true,
  true
from public.leadership_role_definitions lrd
join public.governance_node_types gnt on gnt.organization_id = lrd.organization_id and gnt.code = 'area_state'
where lrd.code = 'fmc_coordinator'
on conflict (organization_id, leadership_role_definition_id, governance_node_type_id) do update
set is_primary_mapping = excluded.is_primary_mapping,
    is_active = excluded.is_active;

-- -----------------------------------------------------------------------------
-- 3. Staging Import Table
-- -----------------------------------------------------------------------------

create schema if not exists staging;

create table if not exists staging.coordinator_import (
  id uuid primary key default gen_random_uuid(),
  import_batch_code text not null,
  action text not null check (action in ('set_sex', 'spouse', 'parent', 'appoint', 'appoint_exception')),
  member_number text not null,
  value text,
  related_member_number text,
  note text,
  applied_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);

revoke all on staging.coordinator_import from public, anon, authenticated;
grant all on staging.coordinator_import to service_role;

-- -----------------------------------------------------------------------------
-- 4. Eligibility Function
-- -----------------------------------------------------------------------------

create or replace function private.section_coordinator_eligibility(
  p_org uuid,
  p_member uuid,
  p_section_node uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member public.members%rowtype;
  v_section_node public.governance_nodes%rowtype;
  v_member_section_code text;
  v_spouse_member_id uuid;
  v_has_active_verified_spouse boolean := false;
begin
  -- 1. Candidate member check
  select *
  into v_member
  from public.members m
  where m.id = p_member
    and m.organization_id = p_org;

  if not found or v_member.record_status != 'active' then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'member_inactive',
      'message', 'Candidate member record is not active.'
    );
  end if;

  if v_member.is_deceased then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'member_deceased',
      'message', 'Cannot appoint a deceased member as coordinator.'
    );
  end if;

  -- 2. Sex check
  if v_member.sex is null then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'sex_null',
      'message', 'Record the member''s sex first.'
    );
  end if;

  -- 3. Target section node check
  select *
  into v_section_node
  from public.governance_nodes gn
  where gn.id = p_section_node
    and gn.organization_id = p_org;

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'section_not_found',
      'message', 'Section node not found.'
    );
  end if;

  -- sec_couples has no coordinator ever
  if v_section_node.code = 'sec_couples' then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'sec_couples_no_coordinator',
      'message', 'Couples section does not have an area coordinator.'
    );
  end if;

  -- 4. Member primary section placement
  select gn.code
  into v_member_section_code
  from public.section_memberships sm
  join public.governance_nodes gn on gn.id = sm.section_node_id
  where sm.organization_id = p_org
    and sm.member_id = p_member
    and sm.membership_status = 'active'
    and sm.is_primary = true
  limit 1;

  -- 5. Active verified spouse check
  select (case when fr.from_member_id = p_member then fr.to_member_id else fr.from_member_id end)
  into v_spouse_member_id
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id
  where fr.organization_id = p_org
    and frt.code = 'spouse'
    and fr.relationship_status = 'active'
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and fr.verification_status in ('administrator_verified', 'document_verified')
    and (fr.from_member_id = p_member or fr.to_member_id = p_member)
  limit 1;

  if v_spouse_member_id is not null then
    select exists (
      select 1
      from public.members sp
      where sp.id = v_spouse_member_id
        and sp.organization_id = p_org
        and sp.record_status = 'active'
        and not sp.is_deceased
    ) into v_has_active_verified_spouse;
  end if;

  -- 6. Evaluate section-specific rules
  case v_section_node.code
    when 'sec_handmaids' then
      if v_member.sex != 'female' then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'handmaids_female_only',
          'message', 'Handmaids section coordinator must be female.'
        );
      end if;

      if not (v_member_section_code = 'sec_handmaids' or (v_member_section_code = 'sec_couples' and v_has_active_verified_spouse)) then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'handmaids_section_or_couples_spouse',
          'message', 'Handmaids coordinator must be in Handmaids section or in Couples with an active verified spouse.'
        );
      end if;

    when 'sec_servants' then
      if v_member.sex != 'male' then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'servants_male_only',
          'message', 'Servants section coordinator must be male.'
        );
      end if;

      if not (v_member_section_code = 'sec_servants' or (v_member_section_code = 'sec_couples' and v_has_active_verified_spouse)) then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'servants_section_or_couples_spouse',
          'message', 'Servants coordinator must be in Servants section or in Couples with an active verified spouse.'
        );
      end if;

    when 'sec_kids', 'sec_youth', 'sec_singles', 'sec_campus' then
      -- Rule: a couple (male holder in Couples with an active verified spouse) OR a male member
      if (v_member.sex = 'male' and v_member_section_code = 'sec_couples' and v_has_active_verified_spouse)
         or (v_member.sex = 'male') then
        null;
      else
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'family_section_couple_or_male',
          'message', 'Section coordinator for ' || coalesce(v_section_node.name, v_section_node.code) || ' must be a couple (husband in Couples with active verified spouse) or a male member.'
        );
      end if;

    else
      return jsonb_build_object(
        'eligible', false,
        'rule_failed', 'unsupported_section',
        'message', 'Unsupported section code for section coordinator: ' || v_section_node.code
      );
  end case;

  return jsonb_build_object(
    'eligible', true,
    'rule_failed', null,
    'message', 'Candidate member is eligible.'
  );
end;
$$;

revoke all on function private.section_coordinator_eligibility(uuid, uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5. Core Appointment Logic (Shared between public RPC and batch migration)
-- -----------------------------------------------------------------------------

create or replace function private.appoint_area_coordinator_core(
  p_organization_id uuid,
  p_role_code text,
  p_node_id uuid,
  p_member_id uuid,
  p_effective_from date default current_date,
  p_exception_reason text default null,
  p_actor_profile_id uuid default null,
  p_source text default 'appoint_area_coordinator'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_role_code text;
  v_effective_from date;
  v_node public.governance_nodes%rowtype;
  v_node_type public.governance_node_types%rowtype;
  v_role_def public.leadership_role_definitions%rowtype;
  v_member public.members%rowtype;
  v_eligibility jsonb;
  v_is_exception boolean := false;
  v_exception_reason text := null;
  v_rule_failed text := null;
  v_existing_active_id uuid;
  v_partner_member_id uuid;
  v_couple_partner_id uuid := null;
  v_new_assignment_id uuid := gen_random_uuid();
  v_now timestamptz := clock_timestamp();
  v_metadata jsonb;
begin
  -- 1. Canonical Role Code validation
  v_role_code := lower(trim(coalesce(p_role_code, '')));
  if v_role_code not in ('area_section_coordinator', 'fmc_coordinator') then
    raise exception using errcode = '22023',
      message = 'Invalid coordinator role code: "' || v_role_code || '". Allowed canonical codes: area_section_coordinator, fmc_coordinator.';
  end if;

  v_effective_from := coalesce(p_effective_from, current_date);

  -- 2. Lock target governance node FOR UPDATE
  select *
  into v_node
  from public.governance_nodes gn
  where gn.id = p_node_id
    and gn.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  if v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Coordinators may only be appointed to active governance nodes.';
  end if;

  -- Reject sec_couples
  if v_node.code = 'sec_couples' then
    raise exception using errcode = '22023', message = 'Couples section does not have an area coordinator.';
  end if;

  -- 3. Resolve role definition
  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.organization_id = p_organization_id
    and lrd.code = v_role_code
    and lrd.is_active = true;

  if not found then
    raise exception using errcode = '22023', message = 'Leadership role "' || v_role_code || '" is not configured or active.';
  end if;

  -- 4. Validate node type matches leadership_role_node_types
  select gnt.*
  into v_node_type
  from public.governance_node_types gnt
  join public.leadership_role_node_types lrnt on lrnt.governance_node_type_id = gnt.id
  where lrnt.organization_id = p_organization_id
    and lrnt.leadership_role_definition_id = v_role_def.id
    and lrnt.is_active = true
    and gnt.id = v_node.governance_node_type_id;

  if not found then
    raise exception using errcode = '22023',
      message = 'Governance node type is not compatible with leadership role "' || v_role_code || '".';
  end if;

  -- 5. Candidate Member Validation
  select *
  into v_member
  from public.members m
  where m.id = p_member_id
    and m.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidate member not found.';
  end if;

  if v_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Candidate member record is not active.';
  end if;

  if v_member.is_deceased then
    raise exception using errcode = '22023', message = 'Cannot appoint a deceased member as coordinator.';
  end if;

  -- 6. Eligibility check (for area_section_coordinator)
  if v_role_code = 'area_section_coordinator' then
    v_eligibility := private.section_coordinator_eligibility(p_organization_id, p_member_id, p_node_id);
    if not (v_eligibility->>'eligible')::boolean then
      if p_exception_reason is null or trim(p_exception_reason) = '' then
        raise exception using errcode = '22023',
          message = coalesce(v_eligibility->>'message', 'Candidate member is not eligible for this section coordinator role.');
      else
        v_is_exception := true;
        v_exception_reason := trim(p_exception_reason);
        v_rule_failed := v_eligibility->>'rule_failed';
      end if;
    end if;
  end if;

  -- 7. At most ONE active assignment per (role, node)
  select la.id
  into v_existing_active_id
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date)
  limit 1;

  if v_existing_active_id is not null then
    raise exception using errcode = '23505',
      message = 'This section already has an active coordinator.';
  end if;

  -- 8. Couple partner detection
  select (case when fr.from_member_id = p_member_id then fr.to_member_id else fr.from_member_id end)
  into v_partner_member_id
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id
  where fr.organization_id = p_organization_id
    and frt.code = 'spouse'
    and fr.relationship_status = 'active'
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and fr.verification_status in ('administrator_verified', 'document_verified')
    and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id)
  limit 1;

  -- Handmaids exception: the woman holds office herself; Servants: brother holds office.
  -- Family sections (Campus, Youth, Kids, Singles) recognize couple partner when spouse is active and verified.
  if v_node.code in ('sec_campus', 'sec_youth', 'sec_singles', 'sec_kids') and v_partner_member_id is not null then
    v_couple_partner_id := v_partner_member_id;
  end if;

  -- 9. Build metadata
  v_metadata := jsonb_build_object(
    'role_code', v_role_code,
    'source', p_source
  );

  if p_actor_profile_id is not null then
    v_metadata := v_metadata || jsonb_build_object('appointed_by_profile', p_actor_profile_id);
  end if;

  if v_couple_partner_id is not null then
    v_metadata := v_metadata || jsonb_build_object('couple_partner_member_id', v_couple_partner_id);
  end if;

  if v_is_exception then
    v_metadata := v_metadata || jsonb_build_object(
      'eligibility_exception', true,
      'exception_reason', v_exception_reason,
      'rule_failed', v_rule_failed
    );
  end if;

  -- 10. Insert active leadership_assignment
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
    p_node_id,
    v_role_def.id,
    null,
    'active',
    'regular',
    v_effective_from,
    null,
    v_now,
    p_actor_profile_id,
    v_now,
    p_actor_profile_id,
    v_now,
    v_now,
    case when v_is_exception then v_exception_reason else 'Appointed ' || v_role_def.name end,
    v_metadata,
    v_now,
    p_actor_profile_id,
    v_now,
    p_actor_profile_id
  );

  -- 11. History row
  insert into public.leadership_assignment_history (
    organization_id,
    leadership_assignment_id,
    previous_status,
    new_status,
    change_type,
    previous_state,
    new_state,
    change_summary,
    effective_at,
    actor_profile_id,
    source
  ) values (
    p_organization_id,
    v_new_assignment_id,
    null,
    'active',
    'activated',
    null,
    jsonb_build_object(
      'member_id', p_member_id,
      'governance_node_id', p_node_id,
      'role_code', v_role_code,
      'effective_from', v_effective_from,
      'eligibility_exception', v_is_exception
    ),
    case when v_is_exception then v_exception_reason else 'Coordinator appointed.' end,
    v_now,
    p_actor_profile_id,
    case
      when p_source in ('application', 'database_function', 'import', 'migration', 'administrator') then p_source
      else 'database_function'
    end
  );

  -- 12. Audit event (NO PII)
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'area_coordinator.appointed',
    p_event_category   => 'governance',
    p_actor_profile_id => p_actor_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => v_new_assignment_id,
    p_action           => 'appoint',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'role_code',            v_role_code,
      'governance_node_id',   p_node_id,
      'governance_node_code', v_node.code,
      'member_id',            p_member_id,
      'couple_partner_id',    v_couple_partner_id,
      'is_exception',         v_is_exception,
      'effective_from',       v_effective_from
    )
  );

  return jsonb_build_object(
    'assignment_id',            v_new_assignment_id,
    'role',                     v_role_code,
    'node_code',                v_node.code,
    'member_id',                p_member_id,
    'couple_partner_member_id', v_couple_partner_id,
    'exception_flag',           v_is_exception
  );
end;
$$;

revoke all on function private.appoint_area_coordinator_core(uuid, text, uuid, uuid, date, text, uuid, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 6. Public Appointment RPC
-- -----------------------------------------------------------------------------

create or replace function public.appoint_area_coordinator(
  p_organization_id uuid,
  p_role_code text,
  p_node_id uuid,
  p_member_id uuid,
  p_effective_from date default current_date,
  p_exception_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
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

  -- 3. Permission check (matching leadership.servant_leaders.appoint)
  if not private.has_permission('leadership.servant_leaders.appoint', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to appoint coordinators.';
  end if;

  -- 4. Delegate to core implementation
  return private.appoint_area_coordinator_core(
    p_organization_id  => p_organization_id,
    p_role_code        => p_role_code,
    p_node_id          => p_node_id,
    p_member_id        => p_member_id,
    p_effective_from   => p_effective_from,
    p_exception_reason => p_exception_reason,
    p_actor_profile_id => v_profile_id,
    p_source           => 'appoint_area_coordinator'
  );
end;
$$;

revoke all on function public.appoint_area_coordinator(uuid, text, uuid, uuid, date, text) from public, anon;
grant execute on function public.appoint_area_coordinator(uuid, text, uuid, uuid, date, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Public End Appointment RPC
-- -----------------------------------------------------------------------------

create or replace function public.end_area_coordinator(
  p_organization_id uuid,
  p_assignment_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_assignment public.leadership_assignments%rowtype;
  v_role_code text;
  v_node_code text;
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
    raise exception using errcode = '42501', message = 'You do not have permission to manage coordinators.';
  end if;

  -- 4. Lock assignment FOR UPDATE
  select la.*
  into v_assignment
  from public.leadership_assignments la
  where la.id = p_assignment_id
    and la.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership assignment not found.';
  end if;

  if v_assignment.assignment_status != 'active' then
    raise exception using errcode = '22023', message = 'Leadership assignment is not active.';
  end if;

  select lrd.code into v_role_code
  from public.leadership_role_definitions lrd
  where lrd.id = v_assignment.leadership_role_definition_id;

  if v_role_code not in ('area_section_coordinator', 'fmc_coordinator') then
    raise exception using errcode = '22023', message = 'Assignment is not an area coordinator role.';
  end if;

  select gn.code into v_node_code
  from public.governance_nodes gn
  where gn.id = v_assignment.governance_node_id;

  -- 5. End assignment
  update public.leadership_assignments
  set assignment_status = 'completed',
      effective_to = coalesce(effective_to, current_date),
      ended_at = clock_timestamp(),
      ended_by_profile_id = v_profile_id,
      ending_reason = trim(coalesce(p_reason, '')),
      updated_at = clock_timestamp(),
      updated_by_profile_id = v_profile_id
  where id = p_assignment_id;

  -- 6. History row
  insert into public.leadership_assignment_history (
    organization_id,
    leadership_assignment_id,
    previous_status,
    new_status,
    change_type,
    change_summary,
    effective_at,
    actor_profile_id,
    source
  ) values (
    p_organization_id,
    p_assignment_id,
    'active',
    'completed',
    'completed',
    p_reason,
    clock_timestamp(),
    v_profile_id,
    'database_function'
  );

  -- 7. Audit event (NO PII)
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'area_coordinator.ended',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => p_assignment_id,
    p_action           => 'end',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'role_code',            v_role_code,
      'governance_node_code', v_node_code,
      'reason',               p_reason
    )
  );

  return jsonb_build_object(
    'status', 'completed',
    'leadership_assignment_id', p_assignment_id
  );
end;
$$;

revoke all on function public.end_area_coordinator(uuid, uuid, text) from public, anon;
grant execute on function public.end_area_coordinator(uuid, uuid, text) to authenticated;

-- =============================================================================
-- Migration: 20260930030000_phase_6b_servant_leader_lifecycle.sql
-- Phase:     Phase 6B-5 ΓÇö Servant Leader Appointment Lifecycle & Pastoral Placement
--
-- Authoritative Scope:
--   1. Seed narrow permissions:
--      - leadership.servant_leaders.appoint
--      - leadership.servant_leaders.conclude
--      - leadership.servant_leaders.replace
--      Assigned initially ONLY to organization_administrator.
--
--   2. Implement public.appoint_servant_leader:
--      Appoints a candidate member to one of the 4 canonical servant-leader roles:
--      household_servant_leader, unit_servant_leader, chapter_servant_leader, area_servant_leader.
--      Validates authentication, organization access, caller governance scope, member status,
--      node type mapping, and Phase 6B-4 formal household guard (pastoral_level = 'member').
--      Enforces temporal policy: effective_from <= current_date.
--      Preserves application authorization boundary: zero app_role / profile assignment changes.
--
--   3. Implement public.conclude_servant_leader:
--      Concludes an active servant-leader assignment with historical preservation.
--      Validates caller scope, assignment ownership, and reason requirement.
--      Enforces temporal policy: effective_to <= current_date and effective_to >= effective_from.
--      Sets assignment_status = 'completed' (or 'ended_early'), ended_at = now(), ending_reason.
--
--   4. Implement public.replace_servant_leader:
--      Atomic replacement workflow locking target node and active assignment.
--      Rejects if no current role holder (returns no_current_role_holder blocker).
--      Rejects same-member replacement.
--      Concludes outgoing assignment and activates incoming assignment same-day.
--
--   5. Implement public.get_servant_leader_pastoral_placement_guidance:
--      Read-only RPC returning recommended pastoral nourishment echelon:
--      - household_servant_leader -> Unit Household (nourishment for household leaders)
--      - unit_servant_leader      -> Chapter Household (nourishment for unit leaders)
--      - chapter_servant_leader   -> Area Household (nourishment for chapter leaders)
--      - area_servant_leader      -> Fraternal Household (nourishment for area leader & seniors)
--      Evaluates verified spouse relationship context for Couples.
--      ZERO mutations performed.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Seed Servant Leader Lifecycle Permissions
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
values
  (
    'leadership.servant_leaders.appoint',
    'Appoint servant leaders',
    'Authorizes formal appointment of Household, Unit, Chapter, and Area Servant Leaders.',
    'leadership',
    'appoint',
    'governance',
    'high',
    false,
    true,
    true
  ),
  (
    'leadership.servant_leaders.conclude',
    'Conclude servant leaders',
    'Authorizes concluding an active servant-leader appointment while preserving history.',
    'leadership',
    'conclude',
    'governance',
    'high',
    false,
    true,
    true
  ),
  (
    'leadership.servant_leaders.replace',
    'Replace servant leaders',
    'Authorizes atomic replacement of an active servant leader with an incoming leader.',
    'leadership',
    'replace',
    'governance',
    'high',
    false,
    true,
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

-- Map permissions initially ONLY to organization_administrator
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
      and rp.organization_id = r.organization_id
  );

-- =============================================================================
-- SECTION 2: Implement public.appoint_servant_leader
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
  v_profile_id          uuid;
  v_role_code           text;
  v_effective_from      date;
  v_role_def            public.leadership_role_definitions%rowtype;
  v_node                public.governance_nodes%rowtype;
  v_node_type           public.governance_node_types%rowtype;
  v_member              public.members%rowtype;
  v_hh_level            text;
  v_existing_active_id  uuid;
  v_existing_member_id  uuid;
  v_new_assignment_id   uuid;
  v_now                 timestamptz := now();
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

  if v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Cannot appoint a servant leader to a governance node that is not active.';
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

  -- 12. Check existing active office holder on this role & node
  select la.id, la.member_id
  into v_existing_active_id, v_existing_member_id
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_governance_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date)
  for update;

  if v_existing_active_id is not null then
    if v_existing_member_id = p_member_id then
      raise exception using errcode = '22023', message = 'Candidate is already the active servant leader for this role and node.';
    else
      raise exception using errcode = '22023',
        message = 'An active servant leader is already assigned to this role and node. Use the Replace workflow to replace an existing leader.';
    end if;
  end if;

  -- 13. Insert formal leadership assignment
  v_new_assignment_id := gen_random_uuid();

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
    nullif(trim(coalesce(p_reason, '')), ''),
    jsonb_build_object(
      'role_code', v_role_code,
      'appointed_via', 'appoint_servant_leader'
    ),
    v_now,
    v_profile_id,
    v_now,
    v_profile_id
  );

  -- 14. Record Audit Event
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
      'leadership_assignment_id', v_new_assignment_id,
      'member_id',                p_member_id,
      'governance_node_id',       p_governance_node_id,
      'role_code',                v_role_code,
      'effective_from',           v_effective_from,
      'reason',                   p_reason
    )
  );

  -- 15. Return structured result
  return jsonb_build_object(
    'status',                   'appointed',
    'leadership_assignment_id', v_new_assignment_id,
    'role_code',                v_role_code,
    'role_name',                v_role_def.name,
    'governance_node_id',       p_governance_node_id,
    'governance_node_name',     v_node.name,
    'member_id',                p_member_id,
    'member_name',              v_member.display_name,
    'effective_from',           v_effective_from
  );
end;
$$;

comment on function public.appoint_servant_leader(uuid, text, uuid, uuid, date, text) is
  'Appoints a candidate member to a canonical servant-leader role. Enforces role-to-node validation, Phase 6B-4 formal household rules, single active cardinality, and temporal constraints.';

revoke execute on function public.appoint_servant_leader(uuid, text, uuid, uuid, date, text) from public, anon;

grant  execute on function public.appoint_servant_leader(uuid, text, uuid, uuid, date, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: Implement public.conclude_servant_leader
-- =============================================================================

create or replace function public.conclude_servant_leader(
  p_organization_id           uuid,
  p_leadership_assignment_id uuid,
  p_effective_to              date default current_date,
  p_reason                    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id    uuid;
  v_effective_to  date;
  v_reason        text;
  v_assignment    public.leadership_assignments%rowtype;
  v_role_def      public.leadership_role_definitions%rowtype;
  v_node          public.governance_nodes%rowtype;
  v_member        public.members%rowtype;
  v_now           timestamptz := now();
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
  if not private.has_permission('leadership.servant_leaders.conclude', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to conclude servant leaders.';
  end if;

  -- 4. Reason validation
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = '23502', message = 'A reason is required to conclude a servant leader appointment.';
  end if;

  -- 5. Temporal MVP Policy: Future-effective conclusion unsupported
  v_effective_to := coalesce(p_effective_to, current_date);
  if v_effective_to > current_date then
    raise exception using errcode = '22023', message = 'Future servant-leader changes are not supported yet.';
  end if;

  -- 6. Lock assignment row FOR UPDATE
  select *
  into v_assignment
  from public.leadership_assignments la
  where la.id = p_leadership_assignment_id
    and la.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership assignment not found or not accessible.';
  end if;

  -- 7. Validate role is canonical servant-leader role
  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.id = v_assignment.leadership_role_definition_id
    and lrd.organization_id = p_organization_id;

  if v_role_def.code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    raise exception using errcode = '22023',
      message = 'This RPC only concludes canonical servant-leader appointments.';
  end if;

  -- 8. Validate assignment is currently active
  if v_assignment.assignment_status != 'active' or (v_assignment.effective_to is not null and v_assignment.effective_to < current_date) then
    raise exception using errcode = '22023', message = 'Leadership assignment is not currently active.';
  end if;

  -- 9. Validate effective_to >= effective_from
  if v_assignment.effective_from is not null and v_effective_to < v_assignment.effective_from then
    raise exception using errcode = '22023', message = 'Conclusion date cannot be earlier than the assignment effective start date.';
  end if;

  -- 10. Scope checks on governance node and member
  if not private.can_access_governance_node('leadership.servant_leaders.conclude', p_organization_id, v_assignment.governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  if not private.can_access_member('leadership.servant_leaders.conclude', p_organization_id, v_assignment.member_id) then
    raise exception using errcode = 'P0002', message = 'Member record not found or not accessible.';
  end if;

  select * into v_node from public.governance_nodes where id = v_assignment.governance_node_id;
  select * into v_member from public.members where id = v_assignment.member_id;

  -- 11. Update assignment to terminal status 'completed'
  update public.leadership_assignments
  set
    assignment_status     = 'completed',
    effective_to          = v_effective_to,
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where id = p_leadership_assignment_id;

  -- 12. Record Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader.concluded',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => p_leadership_assignment_id,
    p_action           => 'conclude',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'leadership_assignment_id', p_leadership_assignment_id,
      'member_id',                v_assignment.member_id,
      'governance_node_id',       v_assignment.governance_node_id,
      'role_code',                v_role_def.code,
      'effective_to',             v_effective_to,
      'ending_reason',            v_reason
    )
  );

  -- 13. Return structured result
  return jsonb_build_object(
    'status',                   'concluded',
    'leadership_assignment_id', p_leadership_assignment_id,
    'role_code',                v_role_def.code,
    'role_name',                v_role_def.name,
    'governance_node_id',       v_assignment.governance_node_id,
    'governance_node_name',     v_node.name,
    'member_id',                v_assignment.member_id,
    'member_name',              v_member.display_name,
    'effective_to',             v_effective_to
  );
end;
$$;

comment on function public.conclude_servant_leader(uuid, uuid, date, text) is
  'Concludes an active servant-leader appointment with full historical preservation. Enforces reason, scope, and temporal checks.';

revoke execute on function public.conclude_servant_leader(uuid, uuid, date, text) from public, anon;

grant  execute on function public.conclude_servant_leader(uuid, uuid, date, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 4: Implement public.replace_servant_leader
-- =============================================================================

create or replace function public.replace_servant_leader(
  p_organization_id    uuid,
  p_role_code          text,
  p_governance_node_id uuid,
  p_new_member_id      uuid,
  p_effective_date     date default current_date,
  p_reason             text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id          uuid;
  v_role_code           text;
  v_effective_date      date;
  v_reason              text;
  v_role_def            public.leadership_role_definitions%rowtype;
  v_node                public.governance_nodes%rowtype;
  v_node_type           public.governance_node_types%rowtype;
  v_outgoing_assignment public.leadership_assignments%rowtype;
  v_outgoing_member     public.members%rowtype;
  v_incoming_member     public.members%rowtype;
  v_hh_level            text;
  v_new_assignment_id   uuid;
  v_now                 timestamptz := now();
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
  if not private.has_permission('leadership.servant_leaders.replace', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to replace servant leaders.';
  end if;

  -- 4. Reason validation
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = '23502', message = 'A reason is required to replace a servant leader.';
  end if;

  -- 5. Canonical Role Code validation
  v_role_code := lower(trim(coalesce(p_role_code, '')));
  if v_role_code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    raise exception using errcode = '22023',
      message = 'Invalid servant leader role code: "' || v_role_code || '". Allowed canonical codes: household_servant_leader, unit_servant_leader, chapter_servant_leader, area_servant_leader.';
  end if;

  -- 6. Temporal MVP Policy: Future-effective replacement unsupported
  v_effective_date := coalesce(p_effective_date, current_date);
  if v_effective_date > current_date then
    raise exception using errcode = '22023', message = 'Future servant-leader changes are not supported yet.';
  end if;

  -- 7. Lock target governance node FOR UPDATE
  select *
  into v_node
  from public.governance_nodes gn
  where gn.id = p_governance_node_id
    and gn.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  if v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Cannot replace a servant leader on a governance node that is not active.';
  end if;

  -- 8. Governance scope check on target node
  if not private.can_access_governance_node('leadership.servant_leaders.replace', p_organization_id, p_governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

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
  select *
  into v_node_type
  from public.governance_node_types gnt
  where gnt.id = v_node.governance_node_type_id
    and gnt.organization_id = p_organization_id;

  if v_role_code = 'household_servant_leader' then
    if v_node_type.code != 'household' then
      raise exception using errcode = '22023', message = 'Household Servant Leader must be appointed to a Household node.';
    end if;

    select h.pastoral_level
    into v_hh_level
    from public.households h
    where h.id = v_node.id
      and h.organization_id = p_organization_id;

    if v_hh_level is distinct from 'member' then
      raise exception using errcode = '23514',
        message = 'Household Servant Leader replacement is only permitted on Member Households. This household has pastoral level: "' || coalesce(v_hh_level, 'unknown') || '".';
    end if;
  elsif v_role_code = 'unit_servant_leader' and v_node_type.code != 'unit' then
    raise exception using errcode = '22023', message = 'Unit Servant Leader must be appointed to a Unit node.';
  elsif v_role_code = 'chapter_servant_leader' and v_node_type.code != 'chapter' then
    raise exception using errcode = '22023', message = 'Chapter Servant Leader must be appointed to a Chapter node.';
  elsif v_role_code = 'area_servant_leader' and v_node_type.code != 'area_state' then
    raise exception using errcode = '22023', message = 'Area Servant Leader must be appointed to an Area/State node.';
  end if;

  -- 11. Lock current active office holder FOR UPDATE
  select *
  into v_outgoing_assignment
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_governance_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date)
  for update;

  if not found then
    return jsonb_build_object(
      'status',               'blocked',
      'blocker_type',         'no_current_role_holder',
      'role_code',            v_role_code,
      'governance_node_id',   p_governance_node_id,
      'governance_node_name', v_node.name,
      'message',              'No active servant leader currently holds this office. Use the Appoint action instead.'
    );
  end if;

  -- 12. Reject same-member replacement
  if v_outgoing_assignment.member_id = p_new_member_id then
    raise exception using errcode = '22023', message = 'The replacement member is already the active servant leader for this role.';
  end if;

  -- 13. Validate incoming member
  select *
  into v_incoming_member
  from public.members m
  where m.id = p_new_member_id
    and m.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Incoming member not found or not accessible.';
  end if;

  if not private.can_access_member('leadership.servant_leaders.replace', p_organization_id, p_new_member_id) then
    raise exception using errcode = 'P0002', message = 'Incoming member not found or not accessible.';
  end if;

  if v_incoming_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Incoming member record is not active.';
  end if;

  if v_incoming_member.is_deceased then
    raise exception using errcode = '22023', message = 'Cannot appoint a deceased member as servant leader.';
  end if;

  -- Also check scope over outgoing member
  if not private.can_access_member('leadership.servant_leaders.replace', p_organization_id, v_outgoing_assignment.member_id) then
    raise exception using errcode = 'P0002', message = 'Outgoing leader record not accessible.';
  end if;

  select * into v_outgoing_member from public.members where id = v_outgoing_assignment.member_id;

  -- 14. Step A: Conclude outgoing assignment
  update public.leadership_assignments
  set
    assignment_status     = 'completed',
    effective_to          = v_effective_date,
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = 'Replaced: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where id = v_outgoing_assignment.id;

  -- 15. Step B: Insert incoming assignment (same-day transition)
  v_new_assignment_id := gen_random_uuid();

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
    p_new_member_id,
    p_governance_node_id,
    v_role_def.id,
    null,
    'active',
    'regular',
    v_effective_date,
    null,
    v_now,
    v_profile_id,
    v_now,
    v_profile_id,
    v_now,
    v_now,
    v_reason,
    jsonb_build_object(
      'role_code',                v_role_code,
      'replaced_assignment_id',   v_outgoing_assignment.id,
      'replaced_member_id',       v_outgoing_assignment.member_id
    ),
    v_now,
    v_profile_id,
    v_now,
    v_profile_id
  );

  -- 16. Record Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader.replaced',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => v_new_assignment_id,
    p_action           => 'replace',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'outgoing_assignment_id', v_outgoing_assignment.id,
      'outgoing_member_id',     v_outgoing_assignment.member_id,
      'incoming_assignment_id', v_new_assignment_id,
      'incoming_member_id',     p_new_member_id,
      'governance_node_id',     p_governance_node_id,
      'role_code',              v_role_code,
      'effective_date',         v_effective_date,
      'reason',                 v_reason
    )
  );

  -- 17. Return structured result
  return jsonb_build_object(
    'status',                   'replaced',
    'role_code',                v_role_code,
    'role_name',                v_role_def.name,
    'governance_node_id',       p_governance_node_id,
    'governance_node_name',     v_node.name,
    'effective_date',           v_effective_date,
    'outgoing_assignment_id',   v_outgoing_assignment.id,
    'outgoing_member_id',       v_outgoing_assignment.member_id,
    'outgoing_member_name',     v_outgoing_member.display_name,
    'incoming_assignment_id',   v_new_assignment_id,
    'incoming_member_id',       p_new_member_id,
    'incoming_member_name',     v_incoming_member.display_name
  );
end;
$$;

comment on function public.replace_servant_leader(uuid, text, uuid, uuid, date, text) is
  'Atomically replaces an active servant leader with an incoming leader on the same day. Concludes outgoing row and activates incoming row under single-transaction lock.';

revoke execute on function public.replace_servant_leader(uuid, text, uuid, uuid, date, text) from public, anon;

grant  execute on function public.replace_servant_leader(uuid, text, uuid, uuid, date, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 5: Implement public.get_servant_leader_pastoral_placement_guidance
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
  v_current_pastoral_level text;
  v_recommended_level      text;
  v_recommended_node_id    uuid;
  v_recommended_node_name  text;
  v_matching_hh_count      integer;
  v_placement_status       text;
  v_spouse_id              uuid;
  v_spouse_name            text;
  v_spouse_verified        boolean := false;
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

  -- 3. Scope check on member
  if not private.can_access_member('governance.leadership.view', p_organization_id, p_member_id) then
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
      'member_id',        p_member_id,
      'member_name',      v_member.display_name,
      'has_formal_role',  false,
      'placement_status', 'no_active_servant_role'
    );
  end if;

  -- Resolve role definition and governance node
  select * into v_role_def from public.leadership_role_definitions where id = v_assignment.leadership_role_definition_id;
  select * into v_gov_node from public.governance_nodes where id = v_assignment.governance_node_id;
  select * into v_gov_node_type from public.governance_node_types where id = v_gov_node.governance_node_type_id;

  -- 5. Determine Recommended Pastoral Level & Scope Node based on authoritative ladder:
  -- - household_servant_leader (leads member household) -> receives care in Unit Household (parent Unit of member household)
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

  -- 6. Check Current Primary Household of Member
  select
    hm.household_node_id,
    gn.name,
    h.pastoral_level
  into
    v_current_hh_id,
    v_current_hh_name,
    v_current_pastoral_level
  from public.household_memberships hm
  join public.governance_nodes gn on gn.id = hm.household_node_id
  join public.households h on h.id = hm.household_node_id
  where hm.member_id = p_member_id
    and hm.organization_id = p_organization_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= current_date
    and (hm.effective_to is null or hm.effective_to >= current_date)
  limit 1;

  -- 7. Count matching active households available at the recommended level and scope
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

  -- 8. Evaluate Verified Spouse Context for Couples
  select
    target_spouse.member_id,
    sm.display_name,
    true
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
    and fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')
    and (fr.effective_from is null or fr.effective_from <= current_date)
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id)
  limit 1;

  -- 9. Determine Placement Status
  if v_current_hh_id is null then
    v_placement_status := 'missing_household';
  elsif v_current_pastoral_level = v_recommended_level then
    v_placement_status := 'correct';
  elsif v_matching_hh_count = 0 then
    v_placement_status := 'no_matching_household_available';
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
    'recommended_pastoral_level',    v_recommended_level,
    'recommended_scope_node_id',     v_recommended_node_id,
    'recommended_scope_node_name',   v_recommended_node_name,
    'matching_households_available', v_matching_hh_count,
    'placement_status',              v_placement_status,
    'spouse_context', jsonb_build_object(
      'has_verified_spouse', coalesce(v_spouse_verified, false),
      'spouse_member_id',    v_spouse_id,
      'spouse_name',         v_spouse_name
    )
  );
end;
$$;

comment on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) is
  'Read-only RPC returning authoritative pastoral placement recommendation based on formal leadership office. Zero mutations.';

revoke execute on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) from public, anon;

grant  execute on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) to authenticated, service_role;


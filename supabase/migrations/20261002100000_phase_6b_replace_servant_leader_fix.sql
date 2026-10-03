-- Migration: 20261002100000_phase_6b_replace_servant_leader_fix.sql
-- Description: Fix appointment_type to 'regular' in replace_servant_leader

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

  -- Atomically Revoke Outgoing Leader Access Grant & Associated Roles/Scopes
  update public.servant_leader_access_grants
  set
    access_status         = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Servant leader replaced: ' || v_reason,
    updated_at            = v_now
  where leadership_assignment_id = v_outgoing_assignment.id
    and organization_id = p_organization_id
    and access_status = 'active';

  update public.profile_role_assignments
  set
    assignment_status     = 'ended',
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = 'Servant leader replaced: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where leadership_assignment_id = v_outgoing_assignment.id
    and organization_id = p_organization_id
    and assignment_status = 'active';

  update public.profile_scope_assignments psa
  set
    assignment_status     = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Servant leader replaced: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where psa.organization_id = p_organization_id
    and psa.assignment_status = 'active'
    and exists (
      select 1 from public.profile_role_assignments pra
      where pra.id = psa.profile_role_assignment_id
        and pra.leadership_assignment_id = v_outgoing_assignment.id
        and pra.organization_id = p_organization_id
    );

  -- 15. Step B: Insert incoming assignment (same-day transition)
  -- Note: incoming leader does NOT receive software access automatically!
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
  )
  values (
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
    'Replaced outgoing servant leader: ' || v_outgoing_member.display_name || '. Reason: ' || v_reason,
    jsonb_build_object(
      'superseded_assignment_id', v_outgoing_assignment.id,
      'superseded_member_id',     v_outgoing_assignment.member_id,
      'superseded_member_name',   v_outgoing_member.display_name,
      'replacement_reason',       v_reason
    ),
    v_now,
    v_profile_id,
    v_now,
    v_profile_id
  );

  -- 16. Record Audit Events
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
      'role_code',              v_role_def.code,
      'effective_date',         v_effective_date,
      'transition_reason',      v_reason
    )
  );

  return jsonb_build_object(
    'status',                 'replaced',
    'concluded_assignment_id', v_outgoing_assignment.id,
    'new_assignment_id',       v_new_assignment_id,
    'role_code',               v_role_def.code,
    'outgoing_member_id',      v_outgoing_assignment.member_id,
    'incoming_member_id',      p_new_member_id,
    'governance_node_id',      p_governance_node_id,
    'effective_date',          v_effective_date
  );
end;
$$;

-- =============================================================================
-- Migration: 20261002210000_phase_6b_replace_servant_leader_scope_revocation_fix.sql
-- Phase:     Phase 6B-9 — Delegated Servant Leader Access & Scope-Based Operations
-- Purpose:   Fix profile_scope_assignments revocation in replace_servant_leader
--            by setting assignment_status = 'revoked' without mutating effective_to_at
--            to prevent violating ck_profile_scope_assignments__period.
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
  v_role_def            public.leadership_role_definitions%rowtype;
  v_node                public.governance_nodes%rowtype;
  v_node_type           public.governance_node_types%rowtype;
  v_outgoing_assignment public.leadership_assignments%rowtype;
  v_outgoing_member     public.members%rowtype;
  v_incoming_member     public.members%rowtype;
  v_new_assignment_id   uuid;
  v_effective_date      date;
  v_reason              text;
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

  -- 3. Dedicated permission check
  if not private.has_permission('leadership.servant_leaders.replace', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to replace servant leaders.';
  end if;

  -- 4. Validate role code
  if p_role_code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    raise exception using errcode = '22023',
      message = 'Only canonical servant leader appointments may be replaced with this function.';
  end if;

  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.code = p_role_code
    and lrd.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership role definition "' || p_role_code || '" not found.';
  end if;

  -- 5. Scope check for replace on governance node
  if not private.can_access_governance_node('leadership.servant_leaders.replace', p_organization_id, p_governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Governance node not accessible for servant leader replacement.';
  end if;

  -- 6. Validate governance node
  select gn.*
  into v_node
  from public.governance_nodes gn
  where gn.id = p_governance_node_id
    and gn.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  if v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Target governance node is not active.';
  end if;

  select gnt.*
  into v_node_type
  from public.governance_node_types gnt
  where gnt.id = v_node.governance_node_type_id
    and gnt.organization_id = p_organization_id;

  -- 7. Validate node compatibility
  case p_role_code
    when 'household_servant_leader' then
      if v_node_type.code != 'household' then
        raise exception using errcode = '22023', message = 'Household Servant Leader must target a Household node.';
      end if;
      if exists (select 1 from public.households h where h.id = p_governance_node_id and h.pastoral_level = 'fraternal') then
        raise exception using errcode = '22023', message = 'Fraternal households do not support formal Servant Leader appointments.';
      end if;
    when 'unit_servant_leader' then
      if v_node_type.code != 'unit' then
        raise exception using errcode = '22023', message = 'Unit Servant Leader must target a Unit node.';
      end if;
    when 'chapter_servant_leader' then
      if v_node_type.code != 'chapter' then
        raise exception using errcode = '22023', message = 'Chapter Servant Leader must target a Chapter node.';
      end if;
    when 'area_servant_leader' then
      if v_node_type.code != 'area_state' then
        raise exception using errcode = '22023', message = 'Area Servant Leader must target an Area node.';
      end if;
  end case;

  -- 8. Effective date default & boundary validations
  v_effective_date := coalesce(p_effective_date, current_date);
  if v_effective_date > current_date then
    raise exception using errcode = '22023', message = 'Servant leader replacement cannot be future-dated.';
  end if;

  -- 9. Mandatory reason
  v_reason := nullif(trim(p_reason), '');
  if v_reason is null then
    raise exception using errcode = '23502', message = 'Replacement reason is mandatory and cannot be blank.';
  end if;

  -- 10. Find active predecessor
  select *
  into v_outgoing_assignment
  from public.leadership_assignments la
  where la.governance_node_id = p_governance_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.organization_id = p_organization_id
    and la.assignment_status = 'active'
    and la.effective_from <= v_effective_date
    and (la.effective_to is null or la.effective_to >= v_effective_date)
  for update;

  if not found then
    return jsonb_build_object(
      'status',               'blocked',
      'blocker_type',         'no_current_role_holder',
      'role_code',            p_role_code,
      'governance_node_id',   p_governance_node_id,
      'governance_node_name', v_node.name,
      'message',              'No active servant leader currently holds this office. Use the Appoint action instead.'
    );
  end if;

  -- Cannot replace with the same member
  if v_outgoing_assignment.member_id = p_new_member_id then
    raise exception using errcode = '22023',
      message = 'Incoming servant leader cannot be the same as outgoing servant leader.';
  end if;

  -- 11. Validate incoming member
  select *
  into v_incoming_member
  from public.members m
  where m.id = p_new_member_id
    and m.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Incoming member not found in organization.';
  end if;

  if v_incoming_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Incoming servant leader must be an active member.';
  end if;

  if v_incoming_member.is_deceased then
    raise exception using errcode = '22023', message = 'Cannot appoint a deceased member as servant leader.';
  end if;

  -- Resolve outgoing member for audit
  select *
  into v_outgoing_member
  from public.members m
  where m.id = v_outgoing_assignment.member_id;

  -- 12. Atomically conclude predecessor assignment
  update public.leadership_assignments
  set
    assignment_status     = 'completed',
    effective_to          = v_effective_date,
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = 'Replaced by ' || v_incoming_member.display_name || ': ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where id = v_outgoing_assignment.id;

  -- 13. Conclude / revoke any existing software access grants for the outgoing assignment
  update public.servant_leader_access_grants
  set
    access_status         = 'revoked',
    effective_to          = v_effective_date,
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Predecessor appointment replaced'
  where leadership_assignment_id = v_outgoing_assignment.id
    and access_status = 'active';

  -- 14. Revoke profile scope assignments for outgoing grants without invalidating period
  update public.profile_scope_assignments psa
  set
    assignment_status     = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Predecessor appointment replaced',
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where psa.id in (
    select g.profile_scope_assignment_id
    from public.servant_leader_access_grants g
    where g.leadership_assignment_id = v_outgoing_assignment.id
      and g.profile_scope_assignment_id is not null
  );

  -- 15. Create incoming active pastoral appointment
  v_new_assignment_id := gen_random_uuid();
  insert into public.leadership_assignments (
    id,
    organization_id,
    member_id,
    governance_node_id,
    leadership_role_definition_id,
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
    'Replaced predecessor (' || v_outgoing_member.display_name || '): ' || v_reason,
    jsonb_build_object(
      'role_code',              p_role_code,
      'appointed_by_profile',   v_profile_id,
      'replaced_assignment_id', v_outgoing_assignment.id
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
      'outgoing_leadership_assignment_id', v_outgoing_assignment.id,
      'outgoing_member_id',                v_outgoing_assignment.member_id,
      'incoming_leadership_assignment_id', v_new_assignment_id,
      'incoming_member_id',                p_new_member_id,
      'governance_node_id',                p_governance_node_id,
      'role_code',                         p_role_code,
      'effective_date',                    v_effective_date,
      'reason',                            v_reason
    )
  );

  return jsonb_build_object(
    'status',                            'replaced',
    'governance_node_id',                p_governance_node_id,
    'role_code',                         p_role_code,
    'outgoing_assignment_id',            v_outgoing_assignment.id,
    'outgoing_leadership_assignment_id', v_outgoing_assignment.id,
    'outgoing_member_id',                v_outgoing_assignment.member_id,
    'outgoing_member_name',              v_outgoing_member.display_name,
    'incoming_assignment_id',            v_new_assignment_id,
    'incoming_leadership_assignment_id', v_new_assignment_id,
    'new_assignment_id',                 v_new_assignment_id,
    'incoming_member_id',                p_new_member_id,
    'incoming_member_name',              v_incoming_member.display_name,
    'effective_date',                    v_effective_date,
    'transition_at',                     v_now
  );
end;
$$;

comment on function public.replace_servant_leader(uuid, text, uuid, uuid, date, text) is
  'Same-day replacement of an active servant leader, atomically concluding predecessor, revoking software grants, and appointing successor with regular appointment_type.';

revoke execute on function public.replace_servant_leader(uuid, text, uuid, uuid, date, text) from public, anon;
grant  execute on function public.replace_servant_leader(uuid, text, uuid, uuid, date, text) to authenticated, service_role;

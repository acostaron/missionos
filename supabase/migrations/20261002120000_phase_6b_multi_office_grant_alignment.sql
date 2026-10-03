-- =============================================================================
-- Migration: 20261002120000_phase_6b_multi_office_grant_alignment.sql
-- Phase:     Phase 6B-9 — Delegated Servant Leader Access & Scope-Based Operations
-- Purpose:   Supports multi-office delegated servant leaders by reusing existing
--            active profile_role_assignments for the same app_role_id and only
--            ending the role assignment upon revocation/conclusion if no other
--            active servant leader access grants remain.
-- =============================================================================

-- 1. grant_servant_leader_access
create or replace function public.grant_servant_leader_access(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid,
  p_profile_id               uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_admin_profile_id   uuid;
  v_assignment         public.leadership_assignments%rowtype;
  v_role_def           public.leadership_role_definitions%rowtype;
  v_node               public.governance_nodes%rowtype;
  v_node_type          public.governance_node_types%rowtype;
  v_member             public.members%rowtype;
  v_target_profile_id  uuid;
  v_app_role_code      text;
  v_app_role           public.app_roles%rowtype;
  v_includes_desc      boolean;
  v_pra_id             uuid;
  v_psa_id             uuid;
  v_grant_id           uuid;
  v_effective_to_at    timestamptz;
  v_now                timestamptz := now();
begin
  -- 1. Authentication check
  v_admin_profile_id := private.current_profile_id();
  if v_admin_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Dedicated permission check
  if not private.has_permission('leadership.delegated_access.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage delegated servant leader access.';
  end if;

  -- 4. Lock leadership assignment FOR UPDATE
  select *
  into v_assignment
  from public.leadership_assignments la
  where la.id = p_leadership_assignment_id
    and la.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership assignment not found or not accessible.';
  end if;

  -- 5. Canonical servant leader role check
  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.id = v_assignment.leadership_role_definition_id
    and lrd.organization_id = p_organization_id;

  if v_role_def.code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    raise exception using errcode = '22023',
      message = 'Delegated access can only be granted to canonical servant leader roles.';
  end if;

  -- 6. Active and current leadership assignment requirement
  if v_assignment.assignment_status != 'active' or (v_assignment.effective_to is not null and v_assignment.effective_to < current_date) then
    raise exception using errcode = '22023', message = 'Leadership assignment is not currently active.';
  end if;

  if v_assignment.effective_from > current_date then
    raise exception using errcode = '22023', message = 'Future servant-leader appointments cannot receive delegated access yet.';
  end if;

  -- 7. Validate governance node
  select gn.*
  into v_node
  from public.governance_nodes gn
  where gn.id = v_assignment.governance_node_id
    and gn.organization_id = p_organization_id;

  if not found or v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Target governance node is not active.';
  end if;

  select gnt.*
  into v_node_type
  from public.governance_node_types gnt
  where gnt.id = v_node.governance_node_type_id
    and gnt.organization_id = p_organization_id;

  -- Node type compatibility check
  case v_role_def.code
    when 'household_servant_leader' then
      if v_node_type.code != 'household' then
        raise exception using errcode = '22023', message = 'Household Servant Leader must target a Household node.';
      end if;
      v_app_role_code := 'household_servant_leader_access';
      v_includes_desc := false;
    when 'unit_servant_leader' then
      if v_node_type.code != 'unit' then
        raise exception using errcode = '22023', message = 'Unit Servant Leader must target a Unit node.';
      end if;
      v_app_role_code := 'unit_servant_leader_access';
      v_includes_desc := true;
    when 'chapter_servant_leader' then
      if v_node_type.code != 'chapter' then
        raise exception using errcode = '22023', message = 'Chapter Servant Leader must target a Chapter node.';
      end if;
      v_app_role_code := 'chapter_servant_leader_access';
      v_includes_desc := true;
    when 'area_servant_leader' then
      if v_node_type.code != 'area_state' then
        raise exception using errcode = '22023', message = 'Area Servant Leader must target an Area/State node.';
      end if;
      v_app_role_code := 'area_servant_leader_access';
      v_includes_desc := true;
  end case;

  -- 8. Resolve leader member
  select *
  into v_member
  from public.members m
  where m.id = v_assignment.member_id
    and m.organization_id = p_organization_id;

  if not found or v_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Servant leader member record is not active.';
  end if;

  -- 9. Resolve verified linked application profile
  if p_profile_id is not null then
    select pml.profile_id
    into v_target_profile_id
    from public.profile_member_links pml
    where pml.organization_id = p_organization_id
      and pml.member_id = v_assignment.member_id
      and pml.profile_id = p_profile_id
      and pml.link_type = 'self'
      and pml.link_status = 'verified'
      and pml.is_primary = true
      and pml.ended_at is null;

    if not found then
      raise exception using errcode = '22023',
        message = 'Requested profile does not hold a verified primary link to this servant leader.';
    end if;
  else
    select pml.profile_id
    into v_target_profile_id
    from public.profile_member_links pml
    where pml.organization_id = p_organization_id
      and pml.member_id = v_assignment.member_id
      and pml.link_type = 'self'
      and pml.link_status = 'verified'
      and pml.is_primary = true
      and pml.ended_at is null
    order by pml.verified_at desc
    limit 1;

    if not found then
      raise exception using errcode = '22023',
        message = 'No verified application profile is linked to this servant leader.';
    end if;
  end if;

  -- Profile must be active
  if not exists (
    select 1 from public.profiles
    where id = v_target_profile_id and account_status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'The linked application profile is not active.';
  end if;

  -- 10. Check if active grant already exists for this leadership assignment
  if exists (
    select 1
    from public.servant_leader_access_grants g
    where g.organization_id = p_organization_id
      and g.leadership_assignment_id = p_leadership_assignment_id
      and g.access_status = 'active'
  ) then
    raise exception using errcode = '22023',
      message = 'An active servant leader access grant already exists for this leadership assignment.';
  end if;

  -- 11. Resolve target app role
  select *
  into v_app_role
  from public.app_roles ar
  where ar.code = v_app_role_code
    and ar.is_active = true
    and (ar.organization_id is null or ar.organization_id = p_organization_id)
  limit 1;

  if not found then
    raise exception using errcode = 'P0002', message = 'Delegated application role "' || v_app_role_code || '" not found.';
  end if;

  if v_assignment.effective_to is not null then
    v_effective_to_at := (v_assignment.effective_to::text || ' 23:59:59.999Z')::timestamptz;
  else
    v_effective_to_at := null;
  end if;

  -- 12. Resolve or create profile_role_assignment (source_type = 'leadership_assignment')
  -- Handles multi-office leader holding multiple assignments with the same role
  select id into v_pra_id
  from public.profile_role_assignments
  where profile_id = v_target_profile_id
    and app_role_id = v_app_role.id
    and coalesce(organization_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_organization_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and assignment_status = 'active'
  limit 1;

  if v_pra_id is null then
    v_pra_id := gen_random_uuid();
    insert into public.profile_role_assignments (
      id,
      organization_id,
      profile_id,
      app_role_id,
      source_type,
      leadership_assignment_id,
      assignment_status,
      effective_from_at,
      effective_to_at,
      proposed_at,
      proposed_by_profile_id,
      approved_at,
      approved_by_profile_id,
      activated_at,
      assignment_summary,
      created_at,
      updated_at,
      updated_by_profile_id
    )
    values (
      v_pra_id,
      p_organization_id,
      v_target_profile_id,
      v_app_role.id,
      'leadership_assignment',
      v_assignment.id,
      'active',
      v_now,
      v_effective_to_at,
      v_now,
      v_admin_profile_id,
      v_now,
      v_admin_profile_id,
      v_now,
      'Delegated servant leader access grant for ' || v_role_def.name,
      v_now,
      v_now,
      v_admin_profile_id
    );
  end if;

  -- 13. Create profile_scope_assignment
  v_psa_id := gen_random_uuid();
  insert into public.profile_scope_assignments (
    id,
    organization_id,
    profile_role_assignment_id,
    scope_type,
    governance_node_id,
    scope_effect,
    includes_descendants,
    assignment_status,
    effective_from_at,
    effective_to_at,
    assigned_at,
    assigned_by_profile_id,
    assignment_summary,
    created_at,
    updated_at,
    updated_by_profile_id
  )
  values (
    v_psa_id,
    p_organization_id,
    v_pra_id,
    'governance_node',
    v_assignment.governance_node_id,
    'include',
    v_includes_desc,
    'active',
    v_now,
    v_effective_to_at,
    v_now,
    v_admin_profile_id,
    'Delegated scope for ' || v_role_def.name,
    v_now,
    v_now,
    v_admin_profile_id
  );

  -- 14. Create servant_leader_access_grants record
  v_grant_id := gen_random_uuid();
  insert into public.servant_leader_access_grants (
    id,
    organization_id,
    profile_id,
    member_id,
    leadership_assignment_id,
    app_role_id,
    profile_role_assignment_id,
    profile_scope_assignment_id,
    governance_node_id,
    access_status,
    granted_at,
    granted_by_profile_id,
    effective_from,
    effective_to,
    created_at,
    updated_at
  )
  values (
    v_grant_id,
    p_organization_id,
    v_target_profile_id,
    v_assignment.member_id,
    v_assignment.id,
    v_app_role.id,
    v_pra_id,
    v_psa_id,
    v_assignment.governance_node_id,
    'active',
    v_now,
    v_admin_profile_id,
    current_date,
    v_assignment.effective_to,
    v_now,
    v_now
  );

  -- 15. Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader_access.granted',
    p_event_category   => 'governance',
    p_actor_profile_id => v_admin_profile_id,
    p_entity_type      => 'servant_leader_access_grant',
    p_entity_id        => v_grant_id,
    p_action           => 'grant',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'grant_id',                 v_grant_id,
      'leadership_assignment_id', v_assignment.id,
      'profile_id',               v_target_profile_id,
      'member_id',                v_assignment.member_id,
      'role_code',                v_role_def.code,
      'app_role_code',            v_app_role_code,
      'governance_node_id',       v_assignment.governance_node_id,
      'governance_node_name',     v_node.name
    )
  );

  return jsonb_build_object(
    'grant_id',                 v_grant_id,
    'leadership_assignment_id', v_assignment.id,
    'profile_id',               v_target_profile_id,
    'member_id',                v_assignment.member_id,
    'member_name',              v_member.display_name,
    'role_code',                v_role_def.code,
    'app_role_code',            v_app_role_code,
    'governance_node_id',       v_assignment.governance_node_id,
    'governance_node_name',     v_node.name,
    'access_status',            'active',
    'granted_at',               v_now
  );
end;
$$;

comment on function public.grant_servant_leader_access(uuid, uuid, uuid) is
  'Grants explicit delegated application access for an active servant leader appointment. Reuses active profile_role_assignment when holder has multiple offices.';

revoke execute on function public.grant_servant_leader_access(uuid, uuid, uuid) from public, anon;

grant  execute on function public.grant_servant_leader_access(uuid, uuid, uuid) to authenticated, service_role;

-- 2. revoke_servant_leader_access
create or replace function public.revoke_servant_leader_access(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid default null,
  p_grant_id                 uuid default null,
  p_reason                   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_admin_profile_id  uuid;
  v_grant             public.servant_leader_access_grants%rowtype;
  v_reason            text;
  v_now               timestamptz := now();
begin
  -- 1. Authentication check
  v_admin_profile_id := private.current_profile_id();
  if v_admin_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Dedicated permission check
  if not private.has_permission('leadership.delegated_access.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to revoke delegated servant leader access.';
  end if;

  v_reason := trim(coalesce(p_reason, 'Delegated access revoked by administrator'));

  -- 4. Locate active grant
  if p_grant_id is not null then
    select *
    into v_grant
    from public.servant_leader_access_grants g
    where g.id = p_grant_id
      and g.organization_id = p_organization_id
    for update;
  elsif p_leadership_assignment_id is not null then
    select *
    into v_grant
    from public.servant_leader_access_grants g
    where g.leadership_assignment_id = p_leadership_assignment_id
      and g.organization_id = p_organization_id
      and g.access_status = 'active'
    for update;
  else
    raise exception using errcode = '22023',
      message = 'Either p_grant_id or p_leadership_assignment_id must be provided.';
  end if;

  if not found then
    raise exception using errcode = 'P0002', message = 'Active servant leader access grant not found.';
  end if;

  if v_grant.access_status != 'active' then
    raise exception using errcode = '22023', message = 'This access grant is already ' || v_grant.access_status || '.';
  end if;

  -- 5. Revoke grant record
  update public.servant_leader_access_grants
  set
    access_status         = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_admin_profile_id,
    revocation_reason     = v_reason,
    updated_at            = v_now
  where id = v_grant.id;

  -- 6. End associated profile role assignment ONLY IF no other active grant references it
  if v_grant.profile_role_assignment_id is not null then
    if not exists (
      select 1
      from public.servant_leader_access_grants other_g
      where other_g.profile_role_assignment_id = v_grant.profile_role_assignment_id
        and other_g.id != v_grant.id
        and other_g.access_status = 'active'
    ) then
      update public.profile_role_assignments
      set
        assignment_status     = 'ended',
        ended_at              = v_now,
        ended_by_profile_id   = v_admin_profile_id,
        ending_reason         = v_reason,
        updated_at            = v_now,
        updated_by_profile_id = v_admin_profile_id
      where id = v_grant.profile_role_assignment_id
        and organization_id = p_organization_id
        and assignment_status = 'active';
    end if;
  end if;

  -- 7. Revoke associated profile scope assignment
  if v_grant.profile_scope_assignment_id is not null then
    update public.profile_scope_assignments
    set
      assignment_status     = 'revoked',
      revoked_at            = v_now,
      revoked_by_profile_id = v_admin_profile_id,
      revocation_reason     = v_reason,
      updated_at            = v_now,
      updated_by_profile_id = v_admin_profile_id
    where id = v_grant.profile_scope_assignment_id
      and organization_id = p_organization_id
      and assignment_status = 'active';
  end if;

  -- 8. Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader_access.revoked',
    p_event_category   => 'governance',
    p_actor_profile_id => v_admin_profile_id,
    p_entity_type      => 'servant_leader_access_grant',
    p_entity_id        => v_grant.id,
    p_action           => 'revoke',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'grant_id',                 v_grant.id,
      'leadership_assignment_id', v_grant.leadership_assignment_id,
      'profile_id',               v_grant.profile_id,
      'member_id',                v_grant.member_id,
      'reason',                   v_reason
    )
  );

  return jsonb_build_object(
    'grant_id',                 v_grant.id,
    'leadership_assignment_id', v_grant.leadership_assignment_id,
    'profile_id',               v_grant.profile_id,
    'member_id',                v_grant.member_id,
    'access_status',            'revoked',
    'revoked_at',               v_now,
    'reason',                   v_reason
  );
end;
$$;

comment on function public.revoke_servant_leader_access(uuid, uuid, uuid, text) is
  'Revokes delegated servant leader access. Role assignment is ended only if no other active grants share it.';

revoke execute on function public.revoke_servant_leader_access(uuid, uuid, uuid, text) from public, anon;

grant  execute on function public.revoke_servant_leader_access(uuid, uuid, uuid, text) to authenticated, service_role;

-- 3. conclude_servant_leader
create or replace function public.conclude_servant_leader(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid,
  p_effective_to             date default current_date,
  p_reason                   text default null
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

  -- 10. Scope verification for governance node & member
  if not private.can_access_governance_node('leadership.servant_leaders.conclude', p_organization_id, v_assignment.governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Governance node not accessible.';
  end if;

  if not private.can_access_member('leadership.servant_leaders.conclude', p_organization_id, v_assignment.member_id) then
    raise exception using errcode = 'P0002', message = 'Member record not accessible.';
  end if;

  -- 11. Conclude assignment
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

  -- 12. Atomically Revoke Delegated Access Grants & Associated Roles/Scopes
  update public.servant_leader_access_grants
  set
    access_status         = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Leadership concluded: ' || v_reason,
    updated_at            = v_now
  where leadership_assignment_id = p_leadership_assignment_id
    and organization_id = p_organization_id
    and access_status = 'active';

  update public.profile_role_assignments pra
  set
    assignment_status     = 'ended',
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = 'Leadership concluded: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where pra.id in (
      select g.profile_role_assignment_id
      from public.servant_leader_access_grants g
      where g.leadership_assignment_id = p_leadership_assignment_id
        and g.organization_id = p_organization_id
    )
    and pra.organization_id = p_organization_id
    and pra.assignment_status = 'active'
    and not exists (
      select 1 from public.servant_leader_access_grants other_g
      where other_g.profile_role_assignment_id = pra.id
        and other_g.leadership_assignment_id != p_leadership_assignment_id
        and other_g.access_status = 'active'
    );

  update public.profile_scope_assignments psa
  set
    assignment_status     = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Leadership concluded: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where psa.id in (
      select g.profile_scope_assignment_id
      from public.servant_leader_access_grants g
      where g.leadership_assignment_id = p_leadership_assignment_id
        and g.organization_id = p_organization_id
    )
    and psa.organization_id = p_organization_id
    and psa.assignment_status = 'active';

  -- 13. Record Audit Event
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

  return jsonb_build_object(
    'status',                   'concluded',
    'leadership_assignment_id', p_leadership_assignment_id,
    'role_code',                v_role_def.code,
    'member_id',                v_assignment.member_id,
    'governance_node_id',       v_assignment.governance_node_id,
    'effective_to',             v_effective_to,
    'ended_at',                 v_now
  );
end;
$$;

comment on function public.conclude_servant_leader(uuid, uuid, date, text) is
  'Concludes a servant leader appointment and revokes any associated software access grants and scopes, preserving shared role assignments if other grants exist.';

revoke execute on function public.conclude_servant_leader(uuid, uuid, date, text) from public, anon;

grant  execute on function public.conclude_servant_leader(uuid, uuid, date, text) to authenticated, service_role;

-- 4. replace_servant_leader
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
        raise exception using errcode = '22023', message = 'Area Servant Leader must target an Area/State node.';
      end if;
  end case;

  -- 8. Effective date
  v_effective_date := coalesce(p_effective_date, current_date);

  -- 9. Validate reason
  v_reason := trim(coalesce(p_reason, 'Servant leader replacement transition'));
  if length(v_reason) < 3 then
    raise exception using errcode = '22023', message = 'A meaningful replacement reason is required.';
  end if;

  -- 10. Validate incoming member
  if not private.can_access_member('leadership.servant_leaders.replace', p_organization_id, p_new_member_id) then
    raise exception using errcode = 'P0002', message = 'Incoming member record not accessible for servant leader replacement.';
  end if;

  select * into v_incoming_member
  from public.members
  where id = p_new_member_id and organization_id = p_organization_id;

  if not found or v_incoming_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Incoming member is not active.';
  end if;

  -- 11. Find currently active outgoing leader
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
    raise exception using errcode = 'P0002',
      message = 'No active servant leader found to replace for role ' || p_role_code || ' on this node.';
  end if;

  -- 12. Incoming member cannot be the same as outgoing member
  if v_outgoing_assignment.member_id = p_new_member_id then
    raise exception using errcode = '22023', message = 'Incoming member is already the active leader for this assignment.';
  end if;

  -- 13. Scope check for outgoing member
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

  update public.profile_role_assignments pra
  set
    assignment_status     = 'ended',
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = 'Servant leader replaced: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where pra.id in (
      select g.profile_role_assignment_id
      from public.servant_leader_access_grants g
      where g.leadership_assignment_id = v_outgoing_assignment.id
        and g.organization_id = p_organization_id
    )
    and pra.organization_id = p_organization_id
    and pra.assignment_status = 'active'
    and not exists (
      select 1 from public.servant_leader_access_grants other_g
      where other_g.profile_role_assignment_id = pra.id
        and other_g.leadership_assignment_id != v_outgoing_assignment.id
        and other_g.access_status = 'active'
    );

  update public.profile_scope_assignments psa
  set
    assignment_status     = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Servant leader replaced: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where psa.id in (
      select g.profile_scope_assignment_id
      from public.servant_leader_access_grants g
      where g.leadership_assignment_id = v_outgoing_assignment.id
        and g.organization_id = p_organization_id
    )
    and psa.organization_id = p_organization_id
    and psa.assignment_status = 'active';

  -- 15. Step B: Insert incoming assignment (same-day transition)
  v_new_assignment_id := gen_random_uuid();
  insert into public.leadership_assignments (
    id,
    organization_id,
    member_id,
    governance_node_id,
    leadership_role_definition_id,
    appointment_type,
    assignment_status,
    effective_from,
    effective_to,
    appointed_at,
    appointed_by_profile_id,
    assignment_notes,
    created_at,
    updated_at,
    updated_by_profile_id
  )
  values (
    v_new_assignment_id,
    p_organization_id,
    p_new_member_id,
    p_governance_node_id,
    v_role_def.id,
    'regular',
    'active',
    v_effective_date,
    null,
    v_now,
    v_profile_id,
    'Replaced predecessor (' || v_outgoing_member.display_name || '): ' || v_reason,
    v_now,
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
    'outgoing_leadership_assignment_id', v_outgoing_assignment.id,
    'outgoing_member_id',                v_outgoing_assignment.member_id,
    'outgoing_member_name',              v_outgoing_member.display_name,
    'incoming_leadership_assignment_id', v_new_assignment_id,
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

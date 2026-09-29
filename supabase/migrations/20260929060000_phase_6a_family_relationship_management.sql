-- =============================================================================
-- Migration: 20260929060000_phase_6a_family_relationship_management.sql
-- Description: Phase 6A-5 Family Relationship Management
--
-- Adds:
-- 1. Permissions:
--    - families.relationships.add
--    - families.relationships.end
--    Assigned initially to organization_administrator.
--
-- 2. Stored Procedures:
--    - public.add_family_relationship
--    - public.end_family_relationship
--
-- 3. Security & Invariant Posture:
--    - Enforces canonical ordering for symmetric relationships (spouse).
--    - Enforces reciprocal creation and ending for asymmetric relationships (parent_of / child_of).
--    - Restricts relationship writes to active family members within operational families.
--    - Prevents impossible, conflicting, or duplicate active relationships.
--    - Non-destructive lifecycle: sets status to 'ended' and records effective_to; zero hard deletes.
--    - Emits structured audit events.
--    - Direct table writes revoked from anon and authenticated.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Permissions catalog & role assignments
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
    'families.relationships.add',
    'Add family relationships',
    'Record interpersonal relationships between active family members.',
    'families',
    'create',
    'organization',
    'standard',
    false,
    false,
    true
  ),
  (
    'families.relationships.end',
    'End family relationships',
    'Conclude interpersonal relationships within a family unit.',
    'families',
    'archive',
    'organization',
    'standard',
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
  is_active               = excluded.is_active,
  updated_at              = now();

insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  approval_status,
  approved_at,
  approved_by_profile_id,
  created_by_profile_id
)
select
  null,
  ar.id,
  p.id,
  'allow',
  'approved',
  now(),
  null,
  null
from public.app_roles ar
cross join public.permissions p
where ar.code = 'organization_administrator'
  and p.code in (
    'families.relationships.add',
    'families.relationships.end'
  )
on conflict do nothing;

-- =============================================================================
-- SECTION 2: Direct Table Write Posture (Defense in Depth)
-- =============================================================================

revoke insert, update, delete on public.family_relationships from public;
revoke insert, update, delete on public.family_relationships from anon;
revoke insert, update, delete on public.family_relationships from authenticated;

-- =============================================================================
-- SECTION 3: Function public.add_family_relationship
-- =============================================================================

create or replace function public.add_family_relationship(
  p_organization_id        uuid,
  p_family_id              uuid,
  p_from_member_id         uuid,
  p_to_member_id           uuid,
  p_relationship_type_code text,
  p_effective_from         date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id           uuid;
  v_family               public.families%rowtype;
  v_from_member          public.members%rowtype;
  v_to_member            public.members%rowtype;
  v_type                 public.family_relationship_types%rowtype;
  v_inverse_type         public.family_relationship_types%rowtype;
  v_effective_from       date;
  v_from_active_fm       integer;
  v_to_active_fm         integer;
  v_canon_from           uuid;
  v_canon_to             uuid;
  v_existing_id          uuid;
  v_existing_spouse_id   uuid;
  v_conflict_id          uuid;
  v_rel_id               uuid;
  v_reciprocal_rel_id    uuid;
begin
  -- Step 1: Authentication guard
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: Permission check
  if not private.has_permission('families.relationships.add', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to add family relationships.';
  end if;

  -- Step 4: Self-relationship rejection
  if p_from_member_id = p_to_member_id then
    raise exception
      using errcode = '22023',
            message = 'A member cannot have a relationship with themselves.';
  end if;

  -- Step 5: Scope check for target family
  if not private.can_access_family('families.relationships.add', p_organization_id, p_family_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  select * into v_family
  from public.families
  where id              = p_family_id
    and organization_id = p_organization_id;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 6: Family lifecycle operational gating
  if v_family.family_status in ('archived', 'ended', 'merged') then
    raise exception
      using errcode = '22023',
            message = 'Relationship changes are not allowed for this family in its current status.';
  end if;

  -- Step 7: Scope check for both target members
  if not private.can_access_member('families.relationships.add', p_organization_id, p_from_member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  if not private.can_access_member('families.relationships.add', p_organization_id, p_to_member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- Step 8: Member existence and lifecycle validation
  select * into v_from_member
  from public.members
  where id              = p_from_member_id
    and organization_id = p_organization_id;

  select * into v_to_member
  from public.members
  where id              = p_to_member_id
    and organization_id = p_organization_id;

  if v_from_member.id is null or v_to_member.id is null then
    raise exception
      using errcode = 'P0002',
            message = 'One or both members were not found in this organization.';
  end if;

  if v_from_member.record_status = 'archived' or v_to_member.record_status = 'archived' then
    raise exception
      using errcode = '22023',
            message = 'Cannot create a family relationship involving an archived member record.';
  end if;

  if v_from_member.is_deceased = true or v_to_member.is_deceased = true then
    raise exception
      using errcode = '22023',
            message = 'Cannot create a new active family relationship involving a deceased member.';
  end if;

  -- Step 9: Verify both members are active members of this family
  select count(*) into v_from_active_fm
  from public.family_members
  where organization_id   = p_organization_id
    and family_id         = p_family_id
    and member_id         = p_from_member_id
    and membership_status = 'active'
    and (effective_to is null or effective_to > current_date);

  select count(*) into v_to_active_fm
  from public.family_members
  where organization_id   = p_organization_id
    and family_id         = p_family_id
    and member_id         = p_to_member_id
    and membership_status = 'active'
    and (effective_to is null or effective_to > current_date);

  if v_from_active_fm = 0 or v_to_active_fm = 0 then
    raise exception
      using errcode = '22023',
            message = 'Both members must currently belong to this family.';
  end if;

  -- Step 10: Relationship type lookup
  select * into v_type
  from public.family_relationship_types
  where code = trim(p_relationship_type_code)
    and is_active = true
    and (organization_id is null or organization_id = p_organization_id);

  if not found then
    raise exception
      using errcode = '22023',
            message = 'Invalid or inactive relationship type.';
  end if;

  -- Step 11: Date validation
  v_effective_from := coalesce(p_effective_from, current_date);
  if v_effective_from > current_date then
    raise exception
      using errcode = '22023',
            message = 'Effective from date cannot be in the future.';
  end if;

  -- Step 12: Invariants and insertion
  if v_type.is_symmetric then
    -- Symmetric (e.g. spouse): canonical pair ordering
    v_canon_from := least(p_from_member_id, p_to_member_id);
    v_canon_to   := greatest(p_from_member_id, p_to_member_id);

    -- Check for duplicate active spouse pair
    select id into v_existing_id
    from public.family_relationships
    where organization_id     = p_organization_id
      and family_id           = p_family_id
      and relationship_type_id = v_type.id
      and from_member_id      = v_canon_from
      and to_member_id        = v_canon_to
      and relationship_status = 'active'
      and (effective_to is null or effective_to > current_date);

    if found then
      raise exception
        using errcode = '22023',
              message = 'This relationship is already recorded.';
    end if;

    -- Check single active spouse policy (allows_multiple_current = false)
    if not v_type.allows_multiple_current then
      select id into v_existing_spouse_id
      from public.family_relationships
      where organization_id     = p_organization_id
        and family_id           = p_family_id
        and relationship_type_id = v_type.id
        and relationship_status = 'active'
        and (effective_to is null or effective_to > current_date)
        and (
          from_member_id in (p_from_member_id, p_to_member_id)
          or to_member_id in (p_from_member_id, p_to_member_id)
        )
      limit 1;

      if found then
        raise exception
          using errcode = '22023',
                message = 'A member cannot have multiple active spouses in the same family.';
      end if;
    end if;

    -- Insert single canonical symmetric row
    insert into public.family_relationships (
      organization_id,
      family_id,
      from_member_id,
      to_member_id,
      relationship_type_id,
      effective_from,
      relationship_status,
      source,
      created_by_profile_id
    ) values (
      p_organization_id,
      p_family_id,
      v_canon_from,
      v_canon_to,
      v_type.id,
      v_effective_from,
      'active',
      'member_provided',
      v_profile_id
    ) returning id into v_rel_id;

    -- Audit event
    perform private.write_audit_event(
      p_organization_id  => p_organization_id,
      p_event_code       => 'family.relationship.added',
      p_event_category   => 'member',
      p_actor_profile_id => v_profile_id,
      p_entity_type      => 'family_relationship',
      p_entity_id        => v_rel_id,
      p_action           => 'create',
      p_outcome          => 'success',
      p_access_reason    => null,
      p_correlation_id   => null,
      p_metadata         => jsonb_build_object(
        'family_id',          p_family_id,
        'from_member_id',     v_canon_from,
        'to_member_id',       v_canon_to,
        'relationship_type',  v_type.code,
        'is_symmetric',       true,
        'effective_from',     v_effective_from
      )
    );

    return jsonb_build_object(
      'status',            'created',
      'relationship_id',   v_rel_id,
      'family_id',         p_family_id,
      'from_member_id',    v_canon_from,
      'to_member_id',      v_canon_to,
      'relationship_code', v_type.code,
      'effective_from',    v_effective_from
    );

  else
    -- Asymmetric (parent_of / child_of)
    select * into v_inverse_type
    from public.family_relationship_types
    where code = v_type.inverse_code
      and is_active = true
      and (organization_id is null or organization_id = p_organization_id);

    if not found then
      raise exception
        using errcode = '22023',
              message = 'Inverse relationship type not configured.';
    end if;

    -- Check for existing exact directed relationship
    select id into v_existing_id
    from public.family_relationships
    where organization_id     = p_organization_id
      and family_id           = p_family_id
      and relationship_type_id = v_type.id
      and from_member_id      = p_from_member_id
      and to_member_id        = p_to_member_id
      and relationship_status = 'active'
      and (effective_to is null or effective_to > current_date);

    if found then
      raise exception
        using errcode = '22023',
              message = 'This relationship is already recorded.';
    end if;

    -- Check for existing reciprocal row (logical duplicate)
    select id into v_existing_id
    from public.family_relationships
    where organization_id     = p_organization_id
      and family_id           = p_family_id
      and relationship_type_id = v_inverse_type.id
      and from_member_id      = p_to_member_id
      and to_member_id        = p_from_member_id
      and relationship_status = 'active'
      and (effective_to is null or effective_to > current_date);

    if found then
      raise exception
        using errcode = '22023',
              message = 'This relationship is already recorded.';
    end if;

    -- Check for conflicting relationship in contradictory direction
    select id into v_conflict_id
    from public.family_relationships
    where organization_id     = p_organization_id
      and family_id           = p_family_id
      and relationship_status = 'active'
      and (effective_to is null or effective_to > current_date)
      and (
        (relationship_type_id = v_type.id and from_member_id = p_to_member_id and to_member_id = p_from_member_id)
        or
        (relationship_type_id = v_inverse_type.id and from_member_id = p_from_member_id and to_member_id = p_to_member_id)
      )
      limit 1;

    if found then
      raise exception
        using errcode = '22023',
              message = 'Conflicting active relationship already exists between these members.';
    end if;

    -- Atomically insert primary row
    insert into public.family_relationships (
      organization_id,
      family_id,
      from_member_id,
      to_member_id,
      relationship_type_id,
      effective_from,
      relationship_status,
      source,
      created_by_profile_id
    ) values (
      p_organization_id,
      p_family_id,
      p_from_member_id,
      p_to_member_id,
      v_type.id,
      v_effective_from,
      'active',
      'member_provided',
      v_profile_id
    ) returning id into v_rel_id;

    -- Atomically insert reciprocal row
    insert into public.family_relationships (
      organization_id,
      family_id,
      from_member_id,
      to_member_id,
      relationship_type_id,
      effective_from,
      relationship_status,
      source,
      created_by_profile_id
    ) values (
      p_organization_id,
      p_family_id,
      p_to_member_id,
      p_from_member_id,
      v_inverse_type.id,
      v_effective_from,
      'active',
      'member_provided',
      v_profile_id
    ) returning id into v_reciprocal_rel_id;

    -- Audit event
    perform private.write_audit_event(
      p_organization_id  => p_organization_id,
      p_event_code       => 'family.relationship.added',
      p_event_category   => 'member',
      p_actor_profile_id => v_profile_id,
      p_entity_type      => 'family_relationship',
      p_entity_id        => v_rel_id,
      p_action           => 'create',
      p_outcome          => 'success',
      p_access_reason    => null,
      p_correlation_id   => null,
      p_metadata         => jsonb_build_object(
        'family_id',                  p_family_id,
        'from_member_id',             p_from_member_id,
        'to_member_id',               p_to_member_id,
        'relationship_type',          v_type.code,
        'is_symmetric',               false,
        'reciprocal_relationship_id', v_reciprocal_rel_id,
        'effective_from',             v_effective_from
      )
    );

    return jsonb_build_object(
      'status',                     'created',
      'relationship_id',            v_rel_id,
      'reciprocal_relationship_id', v_reciprocal_rel_id,
      'family_id',                  p_family_id,
      'from_member_id',             p_from_member_id,
      'to_member_id',               p_to_member_id,
      'relationship_code',          v_type.code,
      'effective_from',             v_effective_from
    );
  end if;
end;
$$;

revoke execute on function public.add_family_relationship(uuid, uuid, uuid, uuid, text, date) from public;
revoke execute on function public.add_family_relationship(uuid, uuid, uuid, uuid, text, date) from anon;
grant  execute on function public.add_family_relationship(uuid, uuid, uuid, uuid, text, date) to authenticated;
grant  execute on function public.add_family_relationship(uuid, uuid, uuid, uuid, text, date) to service_role;

-- =============================================================================
-- SECTION 4: Function public.end_family_relationship
-- =============================================================================

create or replace function public.end_family_relationship(
  p_organization_id  uuid,
  p_relationship_id  uuid,
  p_effective_to     date default current_date,
  p_reason           text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id         uuid;
  v_rel                public.family_relationships%rowtype;
  v_family             public.families%rowtype;
  v_type               public.family_relationship_types%rowtype;
  v_inverse_type_id    uuid;
  v_effective_to       date;
  v_reason             text;
begin
  -- Step 1: Authentication guard
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: Permission check
  if not private.has_permission('families.relationships.end', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to end family relationships.';
  end if;

  -- Step 4: Validate reason
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception
      using errcode = '22023',
            message = 'A reason is required to end a family relationship.';
  end if;

  -- Step 5: Load target relationship
  select * into v_rel
  from public.family_relationships
  where id              = p_relationship_id
    and organization_id = p_organization_id;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Relationship not found or not accessible.';
  end if;

  -- Step 6: Verify relationship is currently active
  if v_rel.relationship_status <> 'active' or (v_rel.effective_to is not null and v_rel.effective_to <= current_date) then
    raise exception
      using errcode = '22023',
            message = 'Relationship is not currently active.';
  end if;

  -- Step 7: Date validation
  v_effective_to := coalesce(p_effective_to, current_date);
  if v_effective_to > current_date then
    raise exception
      using errcode = '22023',
            message = 'Effective to date cannot be in the future.';
  end if;

  if v_rel.effective_from is not null and v_effective_to < v_rel.effective_from then
    raise exception
      using errcode = '22023',
            message = 'Effective to date cannot be before effective from date.';
  end if;

  -- Step 8: Scope check for target family
  if not private.can_access_family('families.relationships.end', p_organization_id, v_rel.family_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  select * into v_family
  from public.families
  where id              = v_rel.family_id
    and organization_id = p_organization_id;

  if v_family.family_status in ('archived', 'ended', 'merged') then
    raise exception
      using errcode = '22023',
            message = 'Relationship changes are not allowed for this family in its current status.';
  end if;

  -- Step 9: Scope check for both member endpoints
  if not private.can_access_member('families.relationships.end', p_organization_id, v_rel.from_member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  if not private.can_access_member('families.relationships.end', p_organization_id, v_rel.to_member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- Step 10: Mark primary relationship row as ended
  update public.family_relationships
  set relationship_status   = 'ended',
      effective_to          = v_effective_to,
      updated_by_profile_id = v_profile_id
  where id = p_relationship_id;

  -- Step 11: If asymmetric, atomically end the reciprocal row if it exists
  select * into v_type
  from public.family_relationship_types
  where id = v_rel.relationship_type_id;

  if not v_type.is_symmetric and v_type.inverse_code is not null then
    select id into v_inverse_type_id
    from public.family_relationship_types
    where code = v_type.inverse_code
      and (organization_id is null or organization_id = p_organization_id);

    if v_inverse_type_id is not null then
      update public.family_relationships
      set relationship_status   = 'ended',
          effective_to          = v_effective_to,
          updated_by_profile_id = v_profile_id
      where organization_id     = p_organization_id
        and family_id           = v_rel.family_id
        and from_member_id      = v_rel.to_member_id
        and to_member_id        = v_rel.from_member_id
        and relationship_type_id = v_inverse_type_id
        and relationship_status = 'active'
        and (effective_to is null or effective_to > current_date);
    end if;
  end if;

  -- Step 12: Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'family.relationship.ended',
    p_event_category   => 'member',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'family_relationship',
    p_entity_id        => p_relationship_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => v_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'family_id',          v_rel.family_id,
      'from_member_id',     v_rel.from_member_id,
      'to_member_id',       v_rel.to_member_id,
      'end_reason',         v_reason,
      'effective_to',       v_effective_to,
      'previous_status',    v_rel.relationship_status
    )
  );

  -- Step 13: Success response
  return jsonb_build_object(
    'status',              'success',
    'relationship_id',     p_relationship_id,
    'family_id',           v_rel.family_id,
    'relationship_status', 'ended',
    'effective_to',        v_effective_to
  );
end;
$$;

revoke execute on function public.end_family_relationship(uuid, uuid, date, text) from public;
revoke execute on function public.end_family_relationship(uuid, uuid, date, text) from anon;
grant  execute on function public.end_family_relationship(uuid, uuid, date, text) to authenticated;
grant  execute on function public.end_family_relationship(uuid, uuid, date, text) to service_role;

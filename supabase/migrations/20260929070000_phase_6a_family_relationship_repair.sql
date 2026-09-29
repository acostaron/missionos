-- =============================================================================
-- Migration: 20260929070000_phase_6a_family_relationship_repair.sql
-- Description: Phase 6A-5 Family Relationship Reciprocal Repair
--
-- Adds:
-- 1. Permission:
--    - families.relationships.correct
--    Assigned initially ONLY to organization_administrator.
--
-- 2. Stored Procedure:
--    - public.repair_family_relationship_reciprocal
--
-- Security & Invariant Posture:
--    - Explicit administrator correction operation.
--    - Repairs ONLY asymmetric parental relationships (parent_of <-> child_of)
--      that are missing their inverse reciprocal row.
--    - Symmetric relationships (spouse) are strictly rejected with SQLSTATE 22023.
--    - Existing relationship row is never mutated or deleted.
--    - Preserves all invariants for active families and members.
--    - Emits structured audit event 'family.relationship.reciprocal_repaired'.
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
values (
  'families.relationships.correct',
  'Repair family relationships',
  'Repair missing reciprocal links for historical asymmetric family relationships.',
  'families',
  'update',
  'organization',
  'high',
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
  and p.code = 'families.relationships.correct'
on conflict do nothing;

-- =============================================================================
-- SECTION 2: Stored Procedure public.repair_family_relationship_reciprocal
-- =============================================================================

create or replace function public.repair_family_relationship_reciprocal(
  p_organization_id uuid,
  p_relationship_id uuid,
  p_reason          text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id                 uuid;
  v_rel                        public.family_relationships%rowtype;
  v_family                     public.families%rowtype;
  v_from_member                public.members%rowtype;
  v_to_member                  public.members%rowtype;
  v_type                       public.family_relationship_types%rowtype;
  v_inverse_type               public.family_relationship_types%rowtype;
  v_from_active_fm             integer;
  v_to_active_fm               integer;
  v_existing_reciprocal_id     uuid;
  v_conflict_id                uuid;
  v_reciprocal_rel_id          uuid;
  v_reason                     text;
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
  if not private.has_permission('families.relationships.correct', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to repair family relationships.';
  end if;

  -- Step 4: Validate reason
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception
      using errcode = '22023',
            message = 'A reason is required to repair a family relationship.';
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

  -- Step 6: Verify target relationship is currently active
  if v_rel.relationship_status <> 'active' or (v_rel.effective_to is not null and v_rel.effective_to <= current_date) then
    raise exception
      using errcode = '22023',
            message = 'Target relationship is not currently active.';
  end if;

  -- Step 7: Scope check for target family
  if not private.can_access_family('families.relationships.correct', p_organization_id, v_rel.family_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  select * into v_family
  from public.families
  where id              = v_rel.family_id
    and organization_id = p_organization_id;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 8: Family lifecycle operational gating
  if v_family.family_status in ('archived', 'ended', 'merged') then
    raise exception
      using errcode = '22023',
            message = 'Relationship changes are not allowed for this family in its current status.';
  end if;

  -- Step 9: Scope check for both target members
  if not private.can_access_member('families.relationships.correct', p_organization_id, v_rel.from_member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  if not private.can_access_member('families.relationships.correct', p_organization_id, v_rel.to_member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- Step 10: Member existence and lifecycle validation
  select * into v_from_member
  from public.members
  where id              = v_rel.from_member_id
    and organization_id = p_organization_id;

  select * into v_to_member
  from public.members
  where id              = v_rel.to_member_id
    and organization_id = p_organization_id;

  if v_from_member.id is null or v_to_member.id is null then
    raise exception
      using errcode = 'P0002',
            message = 'One or both members were not found in this organization.';
  end if;

  if v_from_member.record_status = 'archived' or v_to_member.record_status = 'archived' then
    raise exception
      using errcode = '22023',
            message = 'Cannot repair a relationship involving an archived member record.';
  end if;

  if v_from_member.is_deceased = true or v_to_member.is_deceased = true then
    raise exception
      using errcode = '22023',
            message = 'Cannot repair an active family relationship involving a deceased member.';
  end if;

  -- Step 11: Verify both members remain active members of this family
  select count(*) into v_from_active_fm
  from public.family_members
  where organization_id   = p_organization_id
    and family_id         = v_rel.family_id
    and member_id         = v_rel.from_member_id
    and membership_status = 'active'
    and (effective_to is null or effective_to > current_date);

  select count(*) into v_to_active_fm
  from public.family_members
  where organization_id   = p_organization_id
    and family_id         = v_rel.family_id
    and member_id         = v_rel.to_member_id
    and membership_status = 'active'
    and (effective_to is null or effective_to > current_date);

  if v_from_active_fm = 0 or v_to_active_fm = 0 then
    raise exception
      using errcode = '22023',
            message = 'Both members must currently belong to this family.';
  end if;

  -- Step 12: Relationship type check (must be asymmetric with inverse)
  select * into v_type
  from public.family_relationship_types
  where id = v_rel.relationship_type_id;

  if not found or not v_type.is_active then
    raise exception
      using errcode = '22023',
            message = 'Invalid or inactive relationship type.';
  end if;

  if v_type.is_symmetric then
    raise exception
      using errcode = '22023',
            message = 'Cannot repair reciprocal relationship for symmetric relationship type.';
  end if;

  if v_type.inverse_code is null or trim(v_type.inverse_code) = '' then
    raise exception
      using errcode = '22023',
            message = 'Target relationship does not have a defined inverse type.';
  end if;

  select * into v_inverse_type
  from public.family_relationship_types
  where code = v_type.inverse_code
    and is_active = true
    and (organization_id is null or organization_id = p_organization_id);

  if not found then
    raise exception
      using errcode = '22023',
            message = 'Inverse relationship type not configured or inactive.';
  end if;

  -- Step 13: Verify reciprocal relationship does NOT already exist
  select id into v_existing_reciprocal_id
  from public.family_relationships
  where organization_id      = p_organization_id
    and family_id            = v_rel.family_id
    and relationship_type_id = v_inverse_type.id
    and from_member_id       = v_rel.to_member_id
    and to_member_id         = v_rel.from_member_id
    and relationship_status  = 'active'
    and (effective_to is null or effective_to > current_date);

  if v_existing_reciprocal_id is not null then
    raise exception
      using errcode = '22023',
            message = 'Reciprocal relationship already exists.';
  end if;

  -- Step 14: Verify no contradictory conflicting active relationship
  select id into v_conflict_id
  from public.family_relationships
  where organization_id     = p_organization_id
    and family_id           = v_rel.family_id
    and relationship_status = 'active'
    and (effective_to is null or effective_to > current_date)
    and (
      (relationship_type_id = v_type.id and from_member_id = v_rel.to_member_id and to_member_id = v_rel.from_member_id)
      or
      (relationship_type_id = v_inverse_type.id and from_member_id = v_rel.from_member_id and to_member_id = v_rel.to_member_id)
    )
  limit 1;

  if v_conflict_id is not null then
    raise exception
      using errcode = '22023',
            message = 'Conflicting active relationship already exists between these members.';
  end if;

  -- Step 15: Insert missing reciprocal relationship row
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
    v_rel.family_id,
    v_rel.to_member_id,
    v_rel.from_member_id,
    v_inverse_type.id,
    coalesce(v_rel.effective_from, current_date),
    'active',
    'administrator',
    v_profile_id
  ) returning id into v_reciprocal_rel_id;

  -- Step 16: Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'family.relationship.reciprocal_repaired',
    p_event_category   => 'member',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'family_relationship',
    p_entity_id        => v_reciprocal_rel_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => v_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'family_id',                          v_rel.family_id,
      'existing_relationship_id',           p_relationship_id,
      'created_reciprocal_relationship_id', v_reciprocal_rel_id,
      'existing_relationship_type',         v_type.code,
      'created_inverse_type',               v_inverse_type.code,
      'from_member_id',                     v_rel.to_member_id,
      'to_member_id',                       v_rel.from_member_id,
      'reason',                             v_reason
    )
  );

  -- Step 17: Return status payload
  return jsonb_build_object(
    'status',                       'repaired',
    'existing_relationship_id',     p_relationship_id,
    'reciprocal_relationship_id',   v_reciprocal_rel_id,
    'existing_relationship_code',   v_type.code,
    'reciprocal_relationship_code', v_inverse_type.code
  );
end;
$$;

revoke execute on function public.repair_family_relationship_reciprocal(uuid, uuid, text) from public;
revoke execute on function public.repair_family_relationship_reciprocal(uuid, uuid, text) from anon;
grant  execute on function public.repair_family_relationship_reciprocal(uuid, uuid, text) to authenticated;
grant  execute on function public.repair_family_relationship_reciprocal(uuid, uuid, text) to service_role;

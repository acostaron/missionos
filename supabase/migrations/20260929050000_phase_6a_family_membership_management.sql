-- =============================================================================
-- Migration: 20260929050000_phase_6a_family_membership_management.sql
-- Phase:     Phase 6A-4 — Family Membership Management
--
-- Summary:
--   1. Seed permissions:
--      - families.members.add
--      - families.members.update
--      - families.members.end
--      Strictly assigned to organization_administrator.
--
--   2. Implement RPCs:
--      - public.add_family_member(...)
--      - public.update_family_member(...)
--      - public.end_family_membership(...)
--
--   Maintains separation of family membership from family relationship.
--   Enforces same-family active uniqueness, multi-family warnings, and
--   non-destructive membership ending.
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
    'families.members.add',
    'Add family members',
    'Add members to relational family units.',
    'families',
    'create',
    'organization',
    'standard',
    false,
    false,
    true
  ),
  (
    'families.members.update',
    'Update family members',
    'Update membership roles and flags in relational family units.',
    'families',
    'update',
    'organization',
    'standard',
    false,
    false,
    true
  ),
  (
    'families.members.end',
    'End family membership',
    'Conclude member participation in relational family units.',
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
    'families.members.add',
    'families.members.update',
    'families.members.end'
  )
on conflict do nothing;

-- =============================================================================
-- SECTION 2: public.add_family_member
-- =============================================================================

create or replace function public.add_family_member(
  p_organization_id                uuid,
  p_family_id                      uuid,
  p_member_id                      uuid,
  p_family_role                    text    default null,
  p_is_primary_contact             boolean default false,
  p_is_dependent                   boolean default false,
  p_effective_from                 date    default current_date,
  p_confirm_multiple_active_family boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id               uuid;
  v_family                   public.families%rowtype;
  v_member                   public.members%rowtype;
  v_family_role              text;
  v_effective_from           date;
  v_existing_active_families jsonb;
  v_new_member_id            uuid;
begin
  -- Step 1: Resolve authenticated caller
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Guard: active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: Guard: required permission families.members.add
  if not private.has_permission('families.members.add', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to add family members.';
  end if;

  -- Step 4: Guard: scope checks (family and member both required)
  if not private.can_access_family('families.members.add', p_organization_id, p_family_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  if not private.can_access_member('families.members.add', p_organization_id, p_member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- Step 5: Lock family and verify operational lifecycle state
  select * into v_family
  from public.families
  where id              = p_family_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  if v_family.family_status in ('archived', 'ended', 'merged') then
    raise exception
      using errcode = '22023',
            message = 'Cannot add members to a family in ' || v_family.family_status || ' status.';
  end if;

  -- Step 6: Lock member and verify operational status (block deceased and archived)
  select * into v_member
  from public.members
  where id              = p_member_id
    and organization_id = p_organization_id;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  if v_member.is_deceased then
    raise exception
      using errcode = '22023',
            message = 'Deceased members cannot be added to a new active family membership.';
  end if;

  if v_member.record_status = 'archived' then
    raise exception
      using errcode = '22023',
            message = 'Archived member records cannot be added to a new active family membership.';
  end if;

  -- Step 7: Validate effective_from date (cannot be in future)
  v_effective_from := coalesce(p_effective_from, current_date);
  if v_effective_from > current_date then
    raise exception
      using errcode = '22023',
            message = 'Effective from date cannot be in the future.';
  end if;

  -- Step 8: Validate family_role against schema constraint
  if p_family_role is not null and trim(p_family_role) <> '' then
    v_family_role := trim(p_family_role);
    if v_family_role not in (
      'spouse', 'parent', 'child', 'guardian', 'dependent', 'relative', 'family_contact', 'other'
    ) then
      raise exception
        using errcode = '22023',
              message = 'Invalid family role. Allowed values: spouse, parent, child, guardian, dependent, relative, family_contact, other.';
    end if;
  else
    v_family_role := null;
  end if;

  -- Step 9: Same-family duplicate active membership check (strict hard error)
  if exists (
    select 1
    from public.family_members fm
    where fm.organization_id   = p_organization_id
      and fm.family_id         = p_family_id
      and fm.member_id         = p_member_id
      and fm.membership_status = 'active'
      and (
        fm.effective_to is null
        or fm.effective_to > current_date
      )
  ) then
    raise exception
      using errcode = '22023',
            message = 'This member already has an active membership in this family.';
  end if;

  -- Step 10: Multiple active family memberships in OTHER families check (warning with confirmation)
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'family_id',     f.id,
        'family_name',   f.family_name,
        'display_name',  f.display_name,
        'family_status', f.family_status,
        'family_role',   fm.family_role
      )
    ),
    '[]'::jsonb
  )
  into v_existing_active_families
  from public.family_members fm
  join public.families f
    on  f.id              = fm.family_id
    and f.organization_id = fm.organization_id
  where fm.organization_id   = p_organization_id
    and fm.member_id         = p_member_id
    and fm.family_id        <> p_family_id
    and fm.membership_status = 'active'
    and (
      fm.effective_to is null
      or fm.effective_to > current_date
    )
    and f.family_status not in ('archived', 'ended', 'merged');

  if jsonb_array_length(v_existing_active_families) > 0 and not coalesce(p_confirm_multiple_active_family, false) then
    return jsonb_build_object(
      'status',            'warning',
      'warning_type',      'multiple_active_family_memberships',
      'warning_count',     jsonb_array_length(v_existing_active_families),
      'existing_families', v_existing_active_families
    );
  end if;

  -- Step 11: Insert family_members row
  v_new_member_id := gen_random_uuid();
  insert into public.family_members (
    id,
    organization_id,
    family_id,
    member_id,
    family_role,
    is_primary_contact,
    is_dependent,
    effective_from,
    effective_to,
    membership_status,
    created_by_profile_id,
    updated_by_profile_id
  ) values (
    v_new_member_id,
    p_organization_id,
    p_family_id,
    p_member_id,
    v_family_role,
    coalesce(p_is_primary_contact, false),
    coalesce(p_is_dependent, false),
    v_effective_from,
    null,
    'active',
    v_profile_id,
    v_profile_id
  );

  -- Step 12: Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'family.member.added',
    p_event_category   => 'member',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'family_member',
    p_entity_id        => v_new_member_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'family_id',          p_family_id,
      'member_id',          p_member_id,
      'family_role',        v_family_role,
      'is_primary_contact', coalesce(p_is_primary_contact, false),
      'is_dependent',       coalesce(p_is_dependent, false),
      'effective_from',     v_effective_from,
      'multi_family_count', jsonb_array_length(v_existing_active_families)
    )
  );

  -- Step 13: Return success response
  return jsonb_build_object(
    'status',           'created',
    'family_member_id', v_new_member_id,
    'family_id',        p_family_id,
    'member_id',        p_member_id,
    'family_role',      v_family_role,
    'effective_from',   v_effective_from,
    'warning_count',    jsonb_array_length(v_existing_active_families)
  );
end;
$$;

revoke execute on function public.add_family_member(uuid, uuid, uuid, text, boolean, boolean, date, boolean) from public;
revoke execute on function public.add_family_member(uuid, uuid, uuid, text, boolean, boolean, date, boolean) from anon;
grant  execute on function public.add_family_member(uuid, uuid, uuid, text, boolean, boolean, date, boolean) to authenticated;
grant  execute on function public.add_family_member(uuid, uuid, uuid, text, boolean, boolean, date, boolean) to service_role;

-- =============================================================================
-- SECTION 3: public.update_family_member
-- =============================================================================

create or replace function public.update_family_member(
  p_organization_id    uuid,
  p_family_member_id   uuid,
  p_family_role        text,
  p_is_primary_contact boolean,
  p_is_dependent       boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_fm          public.family_members%rowtype;
  v_family      public.families%rowtype;
  v_family_role text;
begin
  -- Step 1: Resolve authenticated caller
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Guard: active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: Guard: required permission families.members.update
  if not private.has_permission('families.members.update', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to update family members.';
  end if;

  -- Step 4: Lock family_members row
  select * into v_fm
  from public.family_members
  where id              = p_family_member_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Family membership not found or not accessible.';
  end if;

  -- Step 5: Scope check (family and member access)
  if not private.can_access_family('families.members.update', p_organization_id, v_fm.family_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  if not private.can_access_member('families.members.update', p_organization_id, v_fm.member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- Step 6: Verify family lifecycle is operational
  select * into v_family
  from public.families
  where id              = v_fm.family_id
    and organization_id = p_organization_id;

  if v_family.family_status in ('archived', 'ended', 'merged') then
    raise exception
      using errcode = '22023',
            message = 'Cannot update membership in a family in ' || v_family.family_status || ' status.';
  end if;

  -- Step 7: Verify membership is currently active
  if v_fm.membership_status <> 'active' or (v_fm.effective_to is not null and v_fm.effective_to <= current_date) then
    raise exception
      using errcode = '22023',
            message = 'Only active family memberships can be edited.';
  end if;

  -- Step 8: Validate family_role against schema constraint
  if p_family_role is not null and trim(p_family_role) <> '' then
    v_family_role := trim(p_family_role);
    if v_family_role not in (
      'spouse', 'parent', 'child', 'guardian', 'dependent', 'relative', 'family_contact', 'other'
    ) then
      raise exception
        using errcode = '22023',
              message = 'Invalid family role. Allowed values: spouse, parent, child, guardian, dependent, relative, family_contact, other.';
    end if;
  else
    v_family_role := null;
  end if;

  -- Step 9: Update metadata fields only
  update public.family_members
  set
    family_role           = v_family_role,
    is_primary_contact    = coalesce(p_is_primary_contact, false),
    is_dependent          = coalesce(p_is_dependent, false),
    updated_by_profile_id = v_profile_id,
    updated_at            = now()
  where id              = p_family_member_id
    and organization_id = p_organization_id;

  -- Step 10: Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'family.member.updated',
    p_event_category   => 'member',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'family_member',
    p_entity_id        => p_family_member_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'family_id',               v_fm.family_id,
      'member_id',               v_fm.member_id,
      'old_family_role',         v_fm.family_role,
      'new_family_role',         v_family_role,
      'old_is_primary_contact',  v_fm.is_primary_contact,
      'new_is_primary_contact',  coalesce(p_is_primary_contact, false),
      'old_is_dependent',        v_fm.is_dependent,
      'new_is_dependent',        coalesce(p_is_dependent, false)
    )
  );

  -- Step 11: Return updated metadata summary
  return jsonb_build_object(
    'status',             'success',
    'family_member_id',   p_family_member_id,
    'family_id',          v_fm.family_id,
    'member_id',          v_fm.member_id,
    'family_role',        v_family_role,
    'is_primary_contact', coalesce(p_is_primary_contact, false),
    'is_dependent',       coalesce(p_is_dependent, false)
  );
end;
$$;

revoke execute on function public.update_family_member(uuid, uuid, text, boolean, boolean) from public;
revoke execute on function public.update_family_member(uuid, uuid, text, boolean, boolean) from anon;
grant  execute on function public.update_family_member(uuid, uuid, text, boolean, boolean) to authenticated;
grant  execute on function public.update_family_member(uuid, uuid, text, boolean, boolean) to service_role;

-- =============================================================================
-- SECTION 4: public.end_family_membership
-- =============================================================================

create or replace function public.end_family_membership(
  p_organization_id  uuid,
  p_family_member_id uuid,
  p_effective_to     date default current_date,
  p_reason           text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_fm           public.family_members%rowtype;
  v_family       public.families%rowtype;
  v_effective_to date;
  v_reason       text;
begin
  -- Step 1: Resolve authenticated caller
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Guard: active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: Guard: required permission families.members.end
  if not private.has_permission('families.members.end', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to end family memberships.';
  end if;

  -- Step 4: Validate reason
  v_reason := trim(p_reason);
  if nullif(v_reason, '') is null then
    raise exception
      using errcode = '23502',
            message = 'An end membership reason is required.';
  end if;

  -- Step 5: Lock family_members row
  select * into v_fm
  from public.family_members
  where id              = p_family_member_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Family membership not found or not accessible.';
  end if;

  -- Step 6: Scope check (family and member access)
  if not private.can_access_family('families.members.end', p_organization_id, v_fm.family_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  if not private.can_access_member('families.members.end', p_organization_id, v_fm.member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- Step 7: Verify family lifecycle is operational
  select * into v_family
  from public.families
  where id              = v_fm.family_id
    and organization_id = p_organization_id;

  if v_family.family_status in ('archived', 'ended', 'merged') then
    raise exception
      using errcode = '22023',
            message = 'Cannot end membership in a family in ' || v_family.family_status || ' status.';
  end if;

  -- Step 8: Verify membership is currently active (reject second end attempt)
  if v_fm.membership_status in ('ended', 'historical') or (v_fm.effective_to is not null and v_fm.effective_to <= current_date) then
    raise exception
      using errcode = '22023',
            message = 'Family membership is already ended.';
  end if;

  -- Step 9: Validate effective_to date
  v_effective_to := coalesce(p_effective_to, current_date);
  if v_effective_to > current_date then
    raise exception
      using errcode = '22023',
            message = 'Effective end date cannot be in the future.';
  end if;

  if v_fm.effective_from is not null and v_effective_to < v_fm.effective_from then
    raise exception
      using errcode = '22023',
            message = 'Effective end date cannot be earlier than effective from date.';
  end if;

  -- Step 10: Non-destructive update: set status = 'ended', record effective_to
  -- Preserves row, preserves member, preserves family, preserves relationships!
  update public.family_members
  set
    membership_status     = 'ended',
    effective_to          = v_effective_to,
    updated_by_profile_id = v_profile_id,
    updated_at            = now()
  where id              = p_family_member_id
    and organization_id = p_organization_id;

  -- Step 11: Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'family.member.ended',
    p_event_category   => 'member',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'family_member',
    p_entity_id        => p_family_member_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => v_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'family_id',       v_fm.family_id,
      'member_id',       v_fm.member_id,
      'end_reason',      v_reason,
      'effective_to',    v_effective_to,
      'previous_status', v_fm.membership_status
    )
  );

  -- Step 12: Return success response
  return jsonb_build_object(
    'status',            'success',
    'family_member_id',  p_family_member_id,
    'family_id',         v_fm.family_id,
    'member_id',         v_fm.member_id,
    'membership_status', 'ended',
    'effective_to',      v_effective_to
  );
end;
$$;

revoke execute on function public.end_family_membership(uuid, uuid, date, text) from public;
revoke execute on function public.end_family_membership(uuid, uuid, date, text) from anon;
grant  execute on function public.end_family_membership(uuid, uuid, date, text) to authenticated;
grant  execute on function public.end_family_membership(uuid, uuid, date, text) to service_role;

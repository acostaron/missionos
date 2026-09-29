-- =============================================================================
-- Migration: 20260929020000_phase_6a_family_identity_writes.sql
-- Phase:     Phase 6A-3A — Family Identity Write Backend
--
-- Summary:
--   1. Seed family write permissions:
--      - families.records.create (high risk, governance scope)
--      - families.records.update (high risk, governance scope)
--      - families.records.archive (critical risk, governance scope)
--      Assign all three initially ONLY to organization_administrator.
--
--   2. Update private.can_access_family:
--      Support organization-wide scope callers (e.g. organization_administrator)
--      for zero-member and all-ended-member relational family units while
--      preserving union-access for node-scoped callers.
--
--   3. Implement public.create_family:
--      Creates family entity only.
--      Validates organization access, permission, non-empty trimmed names,
--      valid family_type, past/present formed_on.
--      Detects potential duplicates with p_confirm_duplicate guard.
--      Writes family.created audit event.
--
--   4. Implement public.update_family_identity:
--      Updates safe identity fields only (display_name, family_name, family_type, formed_on).
--      Locks row FOR UPDATE.
--      Prohibits updating archived or ended families.
--      Writes family.identity_updated audit event.
--
--   5. Implement public.archive_family_record:
--      Archives family entity only (sets family_status = 'archived', ended_on).
--      Does NOT delete or mutate family_members, family_relationships, or member records.
--      Requires non-empty p_reason.
--      Warns if active members exist unless confirmed with p_confirm_with_active_members.
--      Writes family.archived audit event with reason and member counts.
--
-- Security:
--   All write RPCs: SECURITY DEFINER, fixed search_path.
--   REVOKE EXECUTE from PUBLIC and anon.
--   GRANT EXECUTE to authenticated and service_role.
--   Zero direct table write grants.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Permissions catalog & role assignment
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
    'families.records.create',
    'Create family records',
    'Create new relational family unit records.',
    'families',
    'create',
    'governance',
    'high',
    false,
    false,
    true
  ),
  (
    'families.records.update',
    'Update family records',
    'Update identity information for relational family unit records.',
    'families',
    'update',
    'governance',
    'high',
    false,
    false,
    true
  ),
  (
    'families.records.archive',
    'Archive family records',
    'Archive relational family unit records.',
    'families',
    'archive',
    'governance',
    'critical',
    true,
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
  is_active               = excluded.is_active,
  updated_at              = now();

-- Assign newly created permissions strictly to organization_administrator
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
    'families.records.create',
    'families.records.update',
    'families.records.archive'
  )
on conflict do nothing;

-- =============================================================================
-- SECTION 2: private.can_access_family with org-wide scope support
-- =============================================================================

create or replace function private.can_access_family(
  p_permission_code text,
  p_organization_id uuid,
  p_family_id       uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
begin
  -- Step 1: Canonical caller identity resolution
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    return false;
  end if;

  -- Step 2: Guard: active organization access
  if not private.has_organization_access(p_organization_id) then
    return false;
  end if;

  -- Step 3: Guard: required permission
  if not private.has_permission(p_permission_code, p_organization_id) then
    return false;
  end if;

  -- Step 4: Guard: family exists in this organization (no leak -- returns false)
  if not exists (
    select 1
    from public.families f
    where f.id              = p_family_id
      and f.organization_id = p_organization_id
  ) then
    return false;
  end if;

  -- Step 5: Scope check:
  -- Branch 1: Organization-wide scope (covers zero-member families, ended families, and org admins)
  if exists (
    select 1
    from public.profile_role_assignments pra
    join public.profile_scope_assignments psa
      on psa.profile_role_assignment_id = pra.id
     and psa.organization_id            = pra.organization_id
    where pra.profile_id        = v_profile_id
      and pra.organization_id   = p_organization_id
      and pra.assignment_status = 'active'
      and pra.effective_from_at <= now()
      and (pra.effective_to_at is null or pra.effective_to_at > now())
      and psa.scope_type        = 'organization'
      and psa.scope_effect      = 'include'
      and psa.assignment_status = 'active'
      and psa.effective_from_at <= now()
      and (psa.effective_to_at is null or psa.effective_to_at > now())
  ) and not exists (
    select 1
    from public.profile_role_assignments pra
    join public.profile_scope_assignments psa
      on psa.profile_role_assignment_id = pra.id
     and psa.organization_id            = pra.organization_id
    where pra.profile_id        = v_profile_id
      and pra.organization_id   = p_organization_id
      and pra.assignment_status = 'active'
      and pra.effective_from_at <= now()
      and (pra.effective_to_at is null or pra.effective_to_at > now())
      and psa.scope_type        = 'organization'
      and psa.scope_effect      = 'exclude'
      and psa.assignment_status = 'active'
      and psa.effective_from_at <= now()
      and (psa.effective_to_at is null or psa.effective_to_at > now())
  ) then
    return true;
  end if;

  -- Branch 2: Union-access: at least one active member in the relational family
  -- unit is accessible to caller via private.can_access_member.
  return exists (
    select 1
    from public.family_members fm
    where fm.organization_id   = p_organization_id
      and fm.family_id         = p_family_id
      and fm.membership_status = 'active'
      and (
        fm.effective_to is null
        or fm.effective_to > current_date
      )
      and private.can_access_member(
            p_permission_code,
            p_organization_id,
            fm.member_id
          )
  );
end;
$$;

-- =============================================================================
-- SECTION 3: public.create_family
-- =============================================================================

create or replace function public.create_family(
  p_organization_id   uuid,
  p_display_name      text,
  p_family_name       text,
  p_family_type       text default 'household_family',
  p_formed_on         date default null,
  p_confirm_duplicate boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id          uuid;
  v_display_name        text;
  v_family_name         text;
  v_family_type         text;
  v_new_family_id       uuid;
  v_duplicate_matches   jsonb;
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

  -- Step 3: Guard: required permission families.records.create
  if not private.has_permission('families.records.create', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to create family records.';
  end if;

  -- Step 4: String trimming and required value validation
  v_display_name := trim(p_display_name);
  v_family_name  := trim(p_family_name);

  if nullif(v_display_name, '') is null then
    raise exception
      using errcode = '23502',
            message = 'Display name cannot be empty.';
  end if;

  if nullif(v_family_name, '') is null then
    raise exception
      using errcode = '23502',
            message = 'Family name cannot be empty.';
  end if;

  -- Step 5: Validate family_type against schema catalog
  v_family_type := coalesce(nullif(trim(p_family_type), ''), 'household_family');
  if v_family_type not in (
    'household_family', 'married_couple', 'single_parent_family',
    'guardian_family', 'extended_family', 'other'
  ) then
    raise exception
      using errcode = '22023',
            message = 'Invalid family type. Allowed values: household_family, married_couple, single_parent_family, guardian_family, extended_family, other.';
  end if;

  -- Step 6: Validate formed_on cannot be in future
  if p_formed_on is not null and p_formed_on > current_date then
    raise exception
      using errcode = '22023',
            message = 'Formed on date cannot be in the future.';
  end if;

  -- Step 7: Duplicate detection
  -- Check for existing active families with same or highly similar display name
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'family_id',     f.id,
        'family_name',   f.family_name,
        'display_name',  f.display_name,
        'family_status', f.family_status,
        'formed_on',     f.formed_on
      )
    ),
    '[]'::jsonb
  )
  into v_duplicate_matches
  from public.families f
  where f.organization_id = p_organization_id
    and f.family_status   = 'active'
    and (
      lower(f.display_name) = lower(v_display_name)
      or similarity(f.display_name, v_display_name) >= 0.85
      or (
        lower(f.family_name) = lower(v_family_name)
        and similarity(f.display_name, v_display_name) >= 0.70
      )
    );

  if jsonb_array_length(v_duplicate_matches) > 0 and not coalesce(p_confirm_duplicate, false) then
    return jsonb_build_object(
      'status',        'warning',
      'warning_type',  'duplicate_family_detected',
      'warning_count', jsonb_array_length(v_duplicate_matches),
      'warnings',      v_duplicate_matches
    );
  end if;

  -- Step 8: Insert family entity only (zero members, zero relationships, default directory_visibility)
  v_new_family_id := gen_random_uuid();
  insert into public.families (
    id,
    organization_id,
    family_name,
    display_name,
    family_type,
    family_status,
    formed_on,
    ended_on,
    directory_visibility,
    primary_address_id,
    primary_parish_id,
    administrative_notes,
    created_by_profile_id,
    updated_by_profile_id
  ) values (
    v_new_family_id,
    p_organization_id,
    v_family_name,
    v_display_name,
    v_family_type,
    'active',
    p_formed_on,
    null,
    'leaders_only',
    null,
    null,
    null,
    v_profile_id,
    v_profile_id
  );

  -- Step 9: Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'family.created',
    p_event_category   => 'member',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'family',
    p_entity_id        => v_new_family_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'family_type',         v_family_type,
      'formed_on',           p_formed_on,
      'duplicate_confirmed', (coalesce(p_confirm_duplicate, false) and jsonb_array_length(v_duplicate_matches) > 0),
      'warning_count',       jsonb_array_length(v_duplicate_matches)
    )
  );

  -- Step 10: Return clean created contract
  return jsonb_build_object(
    'status',        'created',
    'family_id',     v_new_family_id,
    'display_name',  v_display_name,
    'family_name',   v_family_name,
    'family_status', 'active',
    'warning_count', jsonb_array_length(v_duplicate_matches)
  );
end;
$$;

revoke execute on function public.create_family(uuid, text, text, text, date, boolean) from public;
revoke execute on function public.create_family(uuid, text, text, text, date, boolean) from anon;
grant  execute on function public.create_family(uuid, text, text, text, date, boolean) to authenticated;
grant  execute on function public.create_family(uuid, text, text, text, date, boolean) to service_role;

-- =============================================================================
-- SECTION 4: public.update_family_identity
-- =============================================================================

create or replace function public.update_family_identity(
  p_organization_id uuid,
  p_family_id       uuid,
  p_display_name    text,
  p_family_name     text,
  p_family_type     text default null,
  p_formed_on       date default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_family       public.families%rowtype;
  v_display_name text;
  v_family_name  text;
  v_family_type  text;
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

  -- Step 3: Guard: required permission families.records.update
  if not private.has_permission('families.records.update', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to update family records.';
  end if;

  -- Step 4: Guard: scope check (indistinguishable P0002)
  if not private.can_access_family('families.records.update', p_organization_id, p_family_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 5: Lock family row before update
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

  -- Step 6: Guard: editable lifecycle state
  if v_family.family_status in ('archived', 'ended') then
    raise exception
      using errcode = '22023',
            message = 'Cannot update family in ' || v_family.family_status || ' status.';
  end if;

  -- Step 7: String trimming and required value validation
  v_display_name := trim(p_display_name);
  v_family_name  := trim(p_family_name);

  if nullif(v_display_name, '') is null then
    raise exception
      using errcode = '23502',
            message = 'Display name cannot be empty.';
  end if;

  if nullif(v_family_name, '') is null then
    raise exception
      using errcode = '23502',
            message = 'Family name cannot be empty.';
  end if;

  -- Step 8: Validate family_type
  if p_family_type is not null then
    v_family_type := trim(p_family_type);
    if v_family_type not in (
      'household_family', 'married_couple', 'single_parent_family',
      'guardian_family', 'extended_family', 'other'
    ) then
      raise exception
        using errcode = '22023',
              message = 'Invalid family type. Allowed values: household_family, married_couple, single_parent_family, guardian_family, extended_family, other.';
    end if;
  else
    v_family_type := v_family.family_type;
  end if;

  -- Step 9: Validate formed_on
  if p_formed_on is not null and p_formed_on > current_date then
    raise exception
      using errcode = '22023',
            message = 'Formed on date cannot be in the future.';
  end if;

  if v_family.ended_on is not null and p_formed_on is not null and p_formed_on > v_family.ended_on then
    raise exception
      using errcode = '22023',
            message = 'Formed on date cannot be after ended on date.';
  end if;

  -- Step 10: Update identity fields only (touch no deferred/out-of-scope fields)
  update public.families
  set
    display_name          = v_display_name,
    family_name           = v_family_name,
    family_type           = v_family_type,
    formed_on             = p_formed_on,
    updated_by_profile_id = v_profile_id
  where id              = p_family_id
    and organization_id = p_organization_id;

  -- Step 11: Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'family.identity_updated',
    p_event_category   => 'member',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'family',
    p_entity_id        => p_family_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'old_display_name', v_family.display_name,
      'new_display_name', v_display_name,
      'old_family_name',  v_family.family_name,
      'new_family_name',  v_family_name,
      'old_family_type',  v_family.family_type,
      'new_family_type',  v_family_type,
      'old_formed_on',    v_family.formed_on,
      'new_formed_on',    p_formed_on
    )
  );

  -- Step 12: Return updated identity summary
  return jsonb_build_object(
    'status',       'success',
    'family_id',    p_family_id,
    'display_name', v_display_name,
    'family_name',  v_family_name,
    'family_type',  v_family_type,
    'formed_on',    p_formed_on
  );
end;
$$;

revoke execute on function public.update_family_identity(uuid, uuid, text, text, text, date) from public;
revoke execute on function public.update_family_identity(uuid, uuid, text, text, text, date) from anon;
grant  execute on function public.update_family_identity(uuid, uuid, text, text, text, date) to authenticated;
grant  execute on function public.update_family_identity(uuid, uuid, text, text, text, date) to service_role;

-- =============================================================================
-- SECTION 5: public.archive_family_record
-- =============================================================================

create or replace function public.archive_family_record(
  p_organization_id             uuid,
  p_family_id                   uuid,
  p_reason                      text,
  p_confirm_with_active_members boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id               uuid;
  v_family                   public.families%rowtype;
  v_reason                   text;
  v_active_member_count       bigint;
  v_active_relationship_count bigint;
  v_ended_on                 date;
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

  -- Step 3: Guard: required permission families.records.archive
  if not private.has_permission('families.records.archive', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to archive family records.';
  end if;

  -- Step 4: Guard: scope check (indistinguishable P0002)
  if not private.can_access_family('families.records.archive', p_organization_id, p_family_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 5: Lock family row before update
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

  -- Step 6: Validate reason
  v_reason := trim(p_reason);
  if nullif(v_reason, '') is null then
    raise exception
      using errcode = '23502',
            message = 'Archive reason is required.';
  end if;

  -- Step 7: Validate lifecycle - reject duplicate archive
  if v_family.family_status = 'archived' then
    raise exception
      using errcode = '22023',
            message = 'Family is already archived.';
  end if;

  -- Step 8: Active members & relationships check
  select
    count(*) filter (where fm.membership_status = 'active' and (fm.effective_to is null or fm.effective_to > current_date)),
    (
      select count(*)
      from public.family_relationships fr
      where fr.organization_id     = p_organization_id
        and fr.family_id           = p_family_id
        and fr.relationship_status = 'active'
        and (fr.effective_to is null or fr.effective_to > current_date)
    )
  into v_active_member_count, v_active_relationship_count
  from public.family_members fm
  where fm.organization_id = p_organization_id
    and fm.family_id       = p_family_id;

  if v_active_member_count > 0 and not coalesce(p_confirm_with_active_members, false) then
    return jsonb_build_object(
      'status',                     'warning',
      'warning_type',               'active_members_present',
      'active_member_count',        v_active_member_count,
      'active_relationship_count',  v_active_relationship_count,
      'message',                    'Family has active members. Confirm archive with active members to proceed.'
    );
  end if;

  -- Step 9: Resolve ended_on (satisfying ended_on >= formed_on)
  v_ended_on := coalesce(v_family.ended_on, current_date);
  if v_family.formed_on is not null and v_ended_on < v_family.formed_on then
    v_ended_on := v_family.formed_on;
  end if;

  -- Step 10: Update family entity lifecycle ONLY
  -- Historical relational data (family_members, family_relationships) remains untouched.
  update public.families
  set
    family_status         = 'archived',
    ended_on              = v_ended_on,
    updated_by_profile_id = v_profile_id
  where id              = p_family_id
    and organization_id = p_organization_id;

  -- Step 11: Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'family.archived',
    p_event_category   => 'member',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'family',
    p_entity_id        => p_family_id,
    p_action           => 'archive',
    p_outcome          => 'success',
    p_access_reason    => v_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'archive_reason',              v_reason,
      'active_member_count',         v_active_member_count,
      'active_relationship_count',   v_active_relationship_count,
      'confirmed_with_active_members', (v_active_member_count > 0 and coalesce(p_confirm_with_active_members, false)),
      'ended_on',                    v_ended_on
    )
  );

  -- Step 12: Return clean archived response
  return jsonb_build_object(
    'status',                    'success',
    'family_id',                 p_family_id,
    'family_status',             'archived',
    'ended_on',                  v_ended_on,
    'active_member_count',       v_active_member_count,
    'active_relationship_count', v_active_relationship_count
  );
end;
$$;

revoke execute on function public.archive_family_record(uuid, uuid, text, boolean) from public;
revoke execute on function public.archive_family_record(uuid, uuid, text, boolean) from anon;
grant  execute on function public.archive_family_record(uuid, uuid, text, boolean) to authenticated;
grant  execute on function public.archive_family_record(uuid, uuid, text, boolean) to service_role;

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================

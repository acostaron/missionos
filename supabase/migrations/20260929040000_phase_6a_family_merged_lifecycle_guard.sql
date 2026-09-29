-- =============================================================================
-- Migration: 20260929040000_phase_6a_family_merged_lifecycle_guard.sql
-- Phase:     Phase 6A-3A/3B — Family Lifecycle Guard Corrections
--
-- Summary:
--   Updates public.update_family_identity and public.archive_family_record to
--   strictly protect historical/superseded/concluded family entities:
--     - update_family_identity: rejects 'archived', 'ended', and 'merged' (22023)
--     - archive_family_record:  rejects 'archived', 'ended', and 'merged' (22023)
--
--   Maintains 'active' and 'changed' as operational statuses permitted for
--   identity updates and archive operations.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. public.update_family_identity
-- -----------------------------------------------------------------------------
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

  -- Step 6: Guard: editable lifecycle state (reject archived, ended, merged)
  if v_family.family_status in ('archived', 'ended', 'merged') then
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

-- -----------------------------------------------------------------------------
-- 2. public.archive_family_record
-- -----------------------------------------------------------------------------
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

  -- Step 7: Validate lifecycle - reject duplicate archive, ended, or merged
  if v_family.family_status in ('archived', 'ended', 'merged') then
    raise exception
      using errcode = '22023',
            message = 'Cannot archive family in ' || v_family.family_status || ' status.';
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

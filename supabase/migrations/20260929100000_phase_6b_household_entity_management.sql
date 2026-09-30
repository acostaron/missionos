-- =============================================================================
-- Migration: 20260929100000_phase_6b_household_entity_management.sql
-- Phase:     Phase 6B-2 — Household Entity Lifecycle Management
--
-- Summary:
--   1. Seed household entity write permissions:
--      - households.records.create  (high risk, governance scope)
--      - households.records.update  (high risk, governance scope)
--      - households.records.archive (critical risk, governance scope)
--      Assign all three initially ONLY to organization_administrator.
--
--   2. Implement public.create_household:
--      Creates governance_nodes row (rank 70 household), public.households detail row,
--      and public.governance_node_relationships row (primary_parent under active Unit or Chapter).
--      Validates organization access, permission, governance scope, code formatting,
--      code uniqueness, name, category, meeting schedule, and capacity bounds.
--      Writes 'governance' / 'household.created' audit event.
--
--   3. Implement public.update_household:
--      Updates mutable operational configuration: name, code, household_category,
--      meeting_frequency, meeting_day_of_week, meeting_start_time, meeting_timezone_name,
--      meeting_location_type, meeting_location_text, target_member_count,
--      maximum_member_count, accepts_new_members, language_code, is_couple_household.
--      Guards against updating archived/closed/merged households (22023).
--      Locks rows FOR UPDATE. Parent governance placement is immutable in this RPC.
--      Writes 'governance' / 'household.updated' audit event.
--
--   4. Implement public.archive_household:
--      Safely transitions a household to archived status.
--      BLOCKS archive if active/temporary household memberships exist (blocker_type: active_household_memberships).
--      BLOCKS archive if active formal leadership assignments exist (blocker_type: active_leadership_assignments).
--      Updates governance_nodes.lifecycle_status = 'archived', archived_at, archived_by, archive_reason, effective_to.
--      Preserves all historical nodes, details, relationships, memberships, and leadership rows.
--      Writes 'governance' / 'household.archived' audit event.
--
-- Security:
--   All write RPCs: SECURITY DEFINER, SET search_path = pg_catalog, public, private, auth.
--   REVOKE EXECUTE from PUBLIC and anon.
--   GRANT EXECUTE to authenticated and service_role.
--   No direct browser write grants on tables.
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
    'households.records.create',
    'Create household records',
    'Create new pastoral household entities and attach them to governance hierarchy.',
    'households',
    'create',
    'governance',
    'high',
    false,
    false,
    true
  ),
  (
    'households.records.update',
    'Update household records',
    'Update identity and pastoral configuration for household records.',
    'households',
    'update',
    'governance',
    'high',
    false,
    false,
    true
  ),
  (
    'households.records.archive',
    'Archive household records',
    'Archive pastoral household records when no active members or leaders remain.',
    'households',
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
    'households.records.create',
    'households.records.update',
    'households.records.archive'
  )
on conflict do nothing;

-- =============================================================================
-- SECTION 2: public.create_household RPC
-- =============================================================================

create or replace function public.create_household(
  p_organization_id           uuid,
  p_name                      text,
  p_code                      text,
  p_parent_governance_node_id uuid,
  p_household_category        text     default 'pastoral',
  p_effective_from            date     default current_date,
  p_meeting_frequency         text     default 'weekly',
  p_meeting_day_of_week       smallint default null,
  p_meeting_start_time        time     default null,
  p_meeting_timezone_name     text     default 'America/New_York',
  p_meeting_location_type     text     default 'residence',
  p_meeting_location_text     text     default null,
  p_target_member_count       integer  default null,
  p_maximum_member_count      integer  default null,
  p_accepts_new_members       boolean  default true,
  p_language_code             text     default 'en',
  p_is_couple_household       boolean  default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id              uuid;
  v_name                    text;
  v_code                    text;
  v_household_category      text;
  v_meeting_frequency       text;
  v_meeting_location_type   text;
  v_meeting_timezone_name   text;
  v_language_code           text;
  v_effective_from          date;
  v_hh_type_id              uuid;
  v_parent_node             public.governance_nodes%rowtype;
  v_parent_type             public.governance_node_types%rowtype;
  v_new_household_id        uuid;
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
  if not private.has_permission('households.records.create', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to create household records.';
  end if;

  -- 4. Scope-safe check: Caller must have scope over parent governance node
  if not private.can_access_governance_node('households.records.create', p_organization_id, p_parent_governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Parent governance node not found or not accessible.';
  end if;

  -- 5. Resolve household governance_node_type
  select gnt.id
  into v_hh_type_id
  from public.governance_node_types gnt
  where gnt.organization_id = p_organization_id
    and gnt.code = 'household'
    and gnt.is_household_type = true
    and gnt.requires_detail_record = true;

  if v_hh_type_id is null then
    raise exception using errcode = '22023', message = 'Household governance node type is not configured for this organization.';
  end if;

  -- 6. Validate Parent Governance Node
  select *
  into v_parent_node
  from public.governance_nodes gn
  where gn.id = p_parent_governance_node_id
    and gn.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Parent governance node not found.';
  end if;

  select *
  into v_parent_type
  from public.governance_node_types gnt
  where gnt.id = v_parent_node.governance_node_type_id
    and gnt.organization_id = p_organization_id;

  -- Allowed parent types: Unit or Chapter
  if v_parent_type.code not in ('unit', 'chapter') then
    raise exception using errcode = '22023', message = 'Households can only be placed under a Unit or Chapter.';
  end if;

  -- Parent lifecycle check: must be active (or planned)
  if v_parent_node.lifecycle_status in ('closed', 'merged', 'archived') then
    raise exception using errcode = '22023', message = 'Cannot attach a household to a closed, merged, or archived parent node.';
  end if;

  -- 7. Validate Name
  v_name := trim(coalesce(p_name, ''));
  if v_name = '' then
    raise exception using errcode = '23502', message = 'Household name is required.';
  end if;
  if length(v_name) > 200 then
    raise exception using errcode = '22023', message = 'Household name must not exceed 200 characters.';
  end if;

  -- 8. Validate and normalize Code
  v_code := lower(trim(coalesce(p_code, '')));
  if v_code = '' then
    raise exception using errcode = '23502', message = 'Household code is required.';
  end if;
  if not (v_code ~ '^[a-z][a-z0-9_]*$') then
    raise exception using errcode = '22023', message = 'Household code must begin with a letter and contain only lowercase letters, digits, and underscores.';
  end if;
  if length(v_code) > 50 then
    raise exception using errcode = '22023', message = 'Household code must not exceed 50 characters.';
  end if;

  -- Duplicate code check within organization
  if exists (
    select 1
    from public.governance_nodes gn
    where gn.organization_id = p_organization_id
      and gn.code = v_code
  ) then
    raise exception using errcode = '23505', message = 'A governance node with code "' || v_code || '" already exists in this organization.';
  end if;

  -- 9. Validate Configuration Fields
  v_household_category := trim(coalesce(p_household_category, 'pastoral'));
  if v_household_category not in ('pastoral', 'formation', 'mission', 'temporary', 'welcoming', 'other') then
    raise exception using errcode = '22023', message = 'Invalid household category. Allowed values: pastoral, formation, mission, temporary, welcoming, other.';
  end if;

  v_meeting_frequency := trim(coalesce(p_meeting_frequency, 'weekly'));
  if v_meeting_frequency not in ('weekly', 'biweekly', 'monthly', 'quarterly', 'seasonal', 'variable') then
    raise exception using errcode = '22023', message = 'Invalid meeting frequency. Allowed values: weekly, biweekly, monthly, quarterly, seasonal, variable.';
  end if;

  if p_meeting_day_of_week is not null and (p_meeting_day_of_week < 0 or p_meeting_day_of_week > 6) then
    raise exception using errcode = '22023', message = 'Meeting day of week must be between 0 (Sunday) and 6 (Saturday).';
  end if;

  v_meeting_location_type := trim(coalesce(p_meeting_location_type, 'residence'));
  if v_meeting_location_type not in ('residence', 'church', 'parish_hall', 'online', 'hybrid', 'variable', 'other') then
    raise exception using errcode = '22023', message = 'Invalid meeting location type. Allowed values: residence, church, parish_hall, online, hybrid, variable, other.';
  end if;

  v_meeting_timezone_name := trim(coalesce(p_meeting_timezone_name, 'America/New_York'));
  if not exists (select 1 from public.timezones tz where tz.name = v_meeting_timezone_name) then
    raise exception using errcode = '22023', message = 'Invalid meeting timezone name.';
  end if;

  v_language_code := lower(trim(coalesce(p_language_code, 'en')));
  if not exists (select 1 from public.languages l where l.code = v_language_code) then
    raise exception using errcode = '22023', message = 'Invalid language code.';
  end if;

  if p_target_member_count is not null and p_target_member_count <= 0 then
    raise exception using errcode = '22023', message = 'Target member count must be greater than zero.';
  end if;

  if p_maximum_member_count is not null and p_maximum_member_count <= 0 then
    raise exception using errcode = '22023', message = 'Maximum member count must be greater than zero.';
  end if;

  if p_target_member_count is not null and p_maximum_member_count is not null and p_maximum_member_count < p_target_member_count then
    raise exception using errcode = '22023', message = 'Maximum member count cannot be less than target member count.';
  end if;

  v_effective_from := coalesce(p_effective_from, current_date);

  -- 10. Atomic Multi-Table Creation: Step A: governance_nodes
  v_new_household_id := gen_random_uuid();

  insert into public.governance_nodes (
    id,
    organization_id,
    governance_node_type_id,
    code,
    name,
    lifecycle_status,
    effective_from,
    created_by,
    updated_by
  ) values (
    v_new_household_id,
    p_organization_id,
    v_hh_type_id,
    v_code,
    v_name,
    'active',
    v_effective_from,
    v_profile_id,
    v_profile_id
  );

  -- Step B: specialized public.households row
  insert into public.households (
    id,
    organization_id,
    household_category,
    meeting_frequency,
    meeting_day_of_week,
    meeting_start_time,
    meeting_timezone_name,
    meeting_location_type,
    meeting_location_text,
    target_member_count,
    maximum_member_count,
    accepts_new_members,
    language_code,
    is_couple_household,
    created_by,
    updated_by
  ) values (
    v_new_household_id,
    p_organization_id,
    v_household_category,
    v_meeting_frequency,
    p_meeting_day_of_week,
    p_meeting_start_time,
    v_meeting_timezone_name,
    v_meeting_location_type,
    nullif(trim(coalesce(p_meeting_location_text, '')), ''),
    p_target_member_count,
    p_maximum_member_count,
    coalesce(p_accepts_new_members, true),
    v_language_code,
    coalesce(p_is_couple_household, false),
    v_profile_id,
    v_profile_id
  );

  -- Step C: parent governance relationship
  insert into public.governance_node_relationships (
    organization_id,
    parent_node_id,
    child_node_id,
    relationship_type,
    relationship_status,
    is_primary,
    effective_from,
    created_by,
    updated_by
  ) values (
    p_organization_id,
    p_parent_governance_node_id,
    v_new_household_id,
    'primary_parent',
    'active',
    true,
    v_effective_from,
    v_profile_id,
    v_profile_id
  );

  -- Step D: Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household',
    p_entity_id        => v_new_household_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_id',              v_new_household_id,
      'name',                      v_name,
      'code',                      v_code,
      'parent_governance_node_id', p_parent_governance_node_id,
      'parent_node_name',          v_parent_node.name,
      'parent_node_type',          v_parent_type.code,
      'household_category',        v_household_category,
      'is_couple_household',       coalesce(p_is_couple_household, false)
    )
  );

  -- 11. Return created contract
  return jsonb_build_object(
    'status',                    'created',
    'household_id',              v_new_household_id,
    'name',                      v_name,
    'code',                      v_code,
    'lifecycle_status',          'active',
    'parent_governance_node_id', p_parent_governance_node_id
  );
end;
$$;

comment on function public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) is
  'Creates a pastoral household entity, specialized detail row, and primary parent relationship. Atomic transaction with full governance validation.';

revoke execute on function public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) from public, anon;
grant  execute on function public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: public.update_household RPC
-- =============================================================================

create or replace function public.update_household(
  p_organization_id           uuid,
  p_household_id              uuid,
  p_name                      text,
  p_code                      text,
  p_household_category        text     default 'pastoral',
  p_meeting_frequency         text     default 'weekly',
  p_meeting_day_of_week       smallint default null,
  p_meeting_start_time        time     default null,
  p_meeting_timezone_name     text     default 'America/New_York',
  p_meeting_location_type     text     default 'residence',
  p_meeting_location_text     text     default null,
  p_target_member_count       integer  default null,
  p_maximum_member_count      integer  default null,
  p_accepts_new_members       boolean  default true,
  p_language_code             text     default 'en',
  p_is_couple_household       boolean  default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id            uuid;
  v_node                  public.governance_nodes%rowtype;
  v_household             public.households%rowtype;
  v_name                  text;
  v_code                  text;
  v_household_category    text;
  v_meeting_frequency     text;
  v_meeting_location_type text;
  v_meeting_timezone_name text;
  v_language_code         text;
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
  if not private.has_permission('households.records.update', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to update household records.';
  end if;

  -- 4. Scope check (indistinguishable P0002)
  if not private.can_access_household('households.records.update', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Lock rows FOR UPDATE
  select *
  into v_node
  from public.governance_nodes gn
  where gn.id = p_household_id
    and gn.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  select *
  into v_household
  from public.households h
  where h.id = p_household_id
    and h.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household detail record not found.';
  end if;

  -- 6. Lifecycle check: reject updates on closed, merged, or archived households
  if v_node.lifecycle_status in ('closed', 'merged', 'archived') then
    raise exception using errcode = '22023', message = 'Cannot update a household in ' || v_node.lifecycle_status || ' status.';
  end if;

  -- 7. Validate Name
  v_name := trim(coalesce(p_name, ''));
  if v_name = '' then
    raise exception using errcode = '23502', message = 'Household name is required.';
  end if;
  if length(v_name) > 200 then
    raise exception using errcode = '22023', message = 'Household name must not exceed 200 characters.';
  end if;

  -- 8. Validate and normalize Code
  v_code := lower(trim(coalesce(p_code, '')));
  if v_code = '' then
    raise exception using errcode = '23502', message = 'Household code is required.';
  end if;
  if not (v_code ~ '^[a-z][a-z0-9_]*$') then
    raise exception using errcode = '22023', message = 'Household code must begin with a letter and contain only lowercase letters, digits, and underscores.';
  end if;
  if length(v_code) > 50 then
    raise exception using errcode = '22023', message = 'Household code must not exceed 50 characters.';
  end if;

  -- Duplicate code check within organization (excluding this household)
  if exists (
    select 1
    from public.governance_nodes gn
    where gn.organization_id = p_organization_id
      and gn.code = v_code
      and gn.id <> p_household_id
  ) then
    raise exception using errcode = '23505', message = 'A governance node with code "' || v_code || '" already exists in this organization.';
  end if;

  -- 9. Validate Configuration Fields
  v_household_category := trim(coalesce(p_household_category, 'pastoral'));
  if v_household_category not in ('pastoral', 'formation', 'mission', 'temporary', 'welcoming', 'other') then
    raise exception using errcode = '22023', message = 'Invalid household category. Allowed values: pastoral, formation, mission, temporary, welcoming, other.';
  end if;

  v_meeting_frequency := trim(coalesce(p_meeting_frequency, 'weekly'));
  if v_meeting_frequency not in ('weekly', 'biweekly', 'monthly', 'quarterly', 'seasonal', 'variable') then
    raise exception using errcode = '22023', message = 'Invalid meeting frequency. Allowed values: weekly, biweekly, monthly, quarterly, seasonal, variable.';
  end if;

  if p_meeting_day_of_week is not null and (p_meeting_day_of_week < 0 or p_meeting_day_of_week > 6) then
    raise exception using errcode = '22023', message = 'Meeting day of week must be between 0 (Sunday) and 6 (Saturday).';
  end if;

  v_meeting_location_type := trim(coalesce(p_meeting_location_type, 'residence'));
  if v_meeting_location_type not in ('residence', 'church', 'parish_hall', 'online', 'hybrid', 'variable', 'other') then
    raise exception using errcode = '22023', message = 'Invalid meeting location type. Allowed values: residence, church, parish_hall, online, hybrid, variable, other.';
  end if;

  v_meeting_timezone_name := trim(coalesce(p_meeting_timezone_name, 'America/New_York'));
  if not exists (select 1 from public.timezones tz where tz.name = v_meeting_timezone_name) then
    raise exception using errcode = '22023', message = 'Invalid meeting timezone name.';
  end if;

  v_language_code := lower(trim(coalesce(p_language_code, 'en')));
  if not exists (select 1 from public.languages l where l.code = v_language_code) then
    raise exception using errcode = '22023', message = 'Invalid language code.';
  end if;

  if p_target_member_count is not null and p_target_member_count <= 0 then
    raise exception using errcode = '22023', message = 'Target member count must be greater than zero.';
  end if;

  if p_maximum_member_count is not null and p_maximum_member_count <= 0 then
    raise exception using errcode = '22023', message = 'Maximum member count must be greater than zero.';
  end if;

  if p_target_member_count is not null and p_maximum_member_count is not null and p_maximum_member_count < p_target_member_count then
    raise exception using errcode = '22023', message = 'Maximum member count cannot be less than target member count.';
  end if;

  -- 10. Apply updates to governance_nodes (name, code, updated_by)
  update public.governance_nodes
  set
    name       = v_name,
    code       = v_code,
    updated_by = v_profile_id
  where id = p_household_id
    and organization_id = p_organization_id;

  -- Step B: Apply updates to public.households
  update public.households
  set
    household_category    = v_household_category,
    meeting_frequency     = v_meeting_frequency,
    meeting_day_of_week   = p_meeting_day_of_week,
    meeting_start_time    = p_meeting_start_time,
    meeting_timezone_name = v_meeting_timezone_name,
    meeting_location_type = v_meeting_location_type,
    meeting_location_text = nullif(trim(coalesce(p_meeting_location_text, '')), ''),
    target_member_count   = p_target_member_count,
    maximum_member_count  = p_maximum_member_count,
    accepts_new_members   = coalesce(p_accepts_new_members, true),
    language_code         = v_language_code,
    is_couple_household   = coalesce(p_is_couple_household, false),
    updated_by            = v_profile_id
  where id = p_household_id
    and organization_id = p_organization_id;

  -- Step C: Record Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household.updated',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household',
    p_entity_id        => p_household_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_id',        p_household_id,
      'old_name',            v_node.name,
      'new_name',            v_name,
      'old_code',            v_node.code,
      'new_code',            v_code,
      'household_category',  v_household_category,
      'is_couple_household', coalesce(p_is_couple_household, false),
      'accepts_new_members', coalesce(p_accepts_new_members, true)
    )
  );

  return jsonb_build_object(
    'status',           'success',
    'household_id',     p_household_id,
    'name',             v_name,
    'code',             v_code,
    'lifecycle_status', v_node.lifecycle_status
  );
end;
$$;

comment on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) is
  'Updates operational identity and pastoral configuration for a household. Governance parent placement is immutable in this RPC.';

revoke execute on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) from public, anon;
grant  execute on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 4: public.archive_household RPC
-- =============================================================================

create or replace function public.archive_household(
  p_organization_id uuid,
  p_household_id    uuid,
  p_reason          text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id           uuid;
  v_node                 public.governance_nodes%rowtype;
  v_reason               text;
  v_active_member_count  bigint;
  v_active_leader_count  bigint;
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
  if not private.has_permission('households.records.archive', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to archive household records.';
  end if;

  -- 4. Scope check (indistinguishable P0002)
  if not private.can_access_household('households.records.archive', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Lock governance node row FOR UPDATE
  select *
  into v_node
  from public.governance_nodes gn
  where gn.id = p_household_id
    and gn.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 6. Validate Reason
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = '23502', message = 'Archive reason is required.';
  end if;

  -- 7. Reject duplicate archive
  if v_node.lifecycle_status = 'archived' then
    raise exception using errcode = '22023', message = 'Household is already archived.';
  end if;

  -- 8. Archive Safety Guard 1: Active Household Memberships
  select count(*)
  into v_active_member_count
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.household_node_id = p_household_id
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= current_date);

  if v_active_member_count > 0 then
    return jsonb_build_object(
      'status',              'blocked',
      'blocker_type',        'active_household_memberships',
      'active_member_count', v_active_member_count,
      'message',             'Cannot archive household with active member assignments. Transfer or conclude active household memberships before archiving.'
    );
  end if;

  -- 9. Archive Safety Guard 2: Active Household Leadership Assignments
  select count(*)
  into v_active_leader_count
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_household_id
    and la.assignment_status = 'active'
    and (la.effective_to is null or la.effective_to >= current_date);

  if v_active_leader_count > 0 then
    return jsonb_build_object(
      'status',                  'blocked',
      'blocker_type',            'active_leadership_assignments',
      'active_leadership_count', v_active_leader_count,
      'message',                 'Cannot archive household with active leadership appointments. Conclude all formal leadership assignments before archiving.'
    );
  end if;

  -- 10. End active primary_parent relationship first (with relationship_status = 'ended')
  -- This satisfies validate_governance_relationship() which prohibits active relationships on archived nodes.
  update public.governance_node_relationships
  set
    relationship_status = 'ended',
    effective_to        = coalesce(effective_to, current_date),
    ended_at            = now(),
    ended_by            = v_profile_id,
    ending_reason       = 'Household archived: ' || v_reason,
    updated_by          = v_profile_id
  where child_node_id = p_household_id
    and organization_id = p_organization_id
    and relationship_type = 'primary_parent'
    and relationship_status = 'active';

  -- Step B: Update governance node to archived lifecycle
  update public.governance_nodes
  set
    lifecycle_status = 'archived',
    archived_at      = now(),
    archived_by      = v_profile_id,
    archive_reason   = v_reason,
    effective_to     = coalesce(effective_to, current_date),
    updated_by       = v_profile_id
  where id = p_household_id
    and organization_id = p_organization_id;

  -- 11. Record Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household.archived',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household',
    p_entity_id        => p_household_id,
    p_action           => 'archive',
    p_outcome          => 'success',
    p_access_reason    => v_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_id',          p_household_id,
      'archive_reason',        v_reason,
      'previous_status',       v_node.lifecycle_status,
      'effective_to',          coalesce(v_node.effective_to, current_date)
    )
  );

  return jsonb_build_object(
    'status',           'success',
    'household_id',     p_household_id,
    'lifecycle_status', 'archived',
    'archive_reason',   v_reason
  );
end;
$$;

comment on function public.archive_household(uuid, uuid, text) is
  'Safely archives a pastoral household entity when no active members or leaders remain. Fully preserves historical data.';

revoke execute on function public.archive_household(uuid, uuid, text) from public, anon;
grant  execute on function public.archive_household(uuid, uuid, text) to authenticated, service_role;

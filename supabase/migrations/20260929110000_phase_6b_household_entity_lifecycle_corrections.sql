-- =============================================================================
-- Migration: 20260929110000_phase_6b_household_entity_lifecycle_corrections.sql
-- Description: Phase 6B-2 Lifecycle corrections:
--   1. Fix create_household parent lifecycle validation (strictly require parent.lifecycle_status = 'active')
--   2. Fix update_household lifecycle check (reject 'dissolved' and 'archived'; allow 'draft', 'planned', 'active', 'temporarily_inactive', 'suspended')
--   3. Fix get_household_profile to preserve historical parent governance context for archived/dissolved households
-- =============================================================================

-- =============================================================================
-- SECTION 1: Fix create_household parent lifecycle validation
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
  v_profile_id             uuid;
  v_hh_type_id             uuid;
  v_parent_node            public.governance_nodes%rowtype;
  v_parent_type            public.governance_node_types%rowtype;
  v_new_household_id       uuid;
  v_name                   text;
  v_code                   text;
  v_household_category     text;
  v_meeting_frequency      text;
  v_meeting_location_type  text;
  v_meeting_timezone_name  text;
  v_language_code          text;
  v_effective_from         date;
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
    raise exception using errcode = 'P0002', message = 'Parent governance node not found or not accessible.';
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

  -- Parent lifecycle check: Parent must be active
  if v_parent_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Cannot attach a household to a parent node that is not active.';
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
  'Creates a pastoral household entity, specialized detail row, and primary parent relationship. Atomic transaction with full governance validation. Parent must be in active status.';

revoke execute on function public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) from public, anon;
grant  execute on function public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 2: Fix update_household lifecycle check
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

  -- 6. Lifecycle check: reject updates on dissolved or archived households
  if v_node.lifecycle_status in ('dissolved', 'archived') then
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

  -- Check duplicate code within organization if code changed
  if v_code != v_node.code and exists (
    select 1
    from public.governance_nodes gn
    where gn.organization_id = p_organization_id
      and gn.code = v_code
      and gn.id != p_household_id
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

  -- 10. Update governance_nodes
  update public.governance_nodes
  set
    name       = v_name,
    code       = v_code,
    updated_by = v_profile_id
  where id = p_household_id
    and organization_id = p_organization_id;

  -- Step B: Update specialized public.households
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
      'name',                v_name,
      'code',                v_code,
      'household_category',  v_household_category,
      'is_couple_household', coalesce(p_is_couple_household, false)
    )
  );

  return jsonb_build_object(
    'status',           'updated',
    'household_id',     p_household_id,
    'name',             v_name,
    'code',             v_code,
    'lifecycle_status', v_node.lifecycle_status
  );
end;
$$;

comment on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) is
  'Updates operational identity and pastoral configuration for a household. Governance parent placement is immutable in this RPC. Rejects updates to dissolved or archived households.';

revoke execute on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) from public, anon;
grant  execute on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: Fix get_household_profile historical parent relationship resolution
-- =============================================================================

create or replace function public.get_household_profile(
  p_organization_id uuid,
  p_household_id    uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_has_id_perm  boolean;
  v_profile_data jsonb;
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
  if not private.has_permission('households.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household records.';
  end if;

  -- 4. Governance-scoped access check (indistinguishable P0002 to prevent existence leakage)
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Identifier permission for roster member numbers
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Build profile payload
  with household_identity as (
    select
      gn.id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      gn.effective_from,
      gn.effective_to,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      h.meeting_timezone_name,
      h.meeting_location_type,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.language_code,
      h.is_couple_household
    from public.governance_nodes gn
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    where gn.id = p_household_id
      and gn.organization_id = p_organization_id
  ),
  parent_gov as (
    select
      gnr.parent_node_id,
      pgn.name as parent_node_name,
      pgn.code as parent_node_code,
      pgnt.code as parent_node_type
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    join public.governance_node_types pgnt
      on pgnt.id = pgn.governance_node_type_id
     and pgnt.organization_id = pgn.organization_id
    where gnr.child_node_id = p_household_id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
    order by
      case when gnr.relationship_status = 'active' and (gnr.effective_to is null or gnr.effective_to >= current_date) then 0 else 1 end,
      gnr.effective_to desc nulls first,
      gnr.effective_from desc,
      gnr.created_at desc
    limit 1
  ),
  active_members as (
    select
      hm.id as household_membership_id,
      m.id as member_id,
      case when v_has_id_perm then m.member_number else null end as member_number,
      m.display_name,
      hm.membership_status,
      hm.membership_role,
      hm.is_primary,
      hm.effective_from,
      hm.effective_to
    from public.household_memberships hm
    join public.members m
      on m.id = hm.member_id
     and m.organization_id = hm.organization_id
    where hm.household_node_id = p_household_id
      and hm.organization_id = p_organization_id
      and hm.membership_status in ('active', 'temporary')
      and (hm.effective_to is null or hm.effective_to >= current_date)
    order by
      case when hm.membership_role in ('servant', 'leader') then 0 else 1 end,
      m.display_name asc
  ),
  formal_leaders as (
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from public.leadership_assignments la
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where la.governance_node_id = p_household_id
      and la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and (la.effective_to is null or la.effective_to >= current_date)
    order by coalesce(lrd.display_order, 999) asc, m.display_name asc
  )
  select jsonb_build_object(
    'household', (
      select jsonb_build_object(
        'id', hi.id,
        'name', hi.name,
        'code', hi.code,
        'lifecycle_status', hi.lifecycle_status,
        'household_category', hi.household_category,
        'effective_from', hi.effective_from,
        'effective_to', hi.effective_to,
        'meeting_frequency', hi.meeting_frequency,
        'meeting_day_of_week', hi.meeting_day_of_week,
        'meeting_start_time', hi.meeting_start_time,
        'meeting_timezone_name', hi.meeting_timezone_name,
        'meeting_location_type', hi.meeting_location_type,
        'target_member_count', hi.target_member_count,
        'maximum_member_count', hi.maximum_member_count,
        'accepts_new_members', hi.accepts_new_members,
        'language_code', hi.language_code,
        'is_couple_household', hi.is_couple_household
      )
      from household_identity hi
    ),
    'parent_governance', (
      select case
        when count(pg.*) = 0 then null
        else jsonb_build_object(
          'parent_node_id',   (array_agg(pg.parent_node_id))[1],
          'parent_node_name', (array_agg(pg.parent_node_name))[1],
          'parent_node_code', (array_agg(pg.parent_node_code))[1],
          'parent_node_type', (array_agg(pg.parent_node_type))[1]
        )
      end
      from parent_gov pg
    ),
    'leaders', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'leadership_assignment_id', fl.leadership_assignment_id,
            'member_id',                fl.member_id,
            'display_name',             fl.display_name,
            'leadership_role_code',     fl.leadership_role_code,
            'leadership_role_name',     fl.leadership_role_name,
            'assignment_status',        fl.assignment_status,
            'effective_from',           fl.effective_from,
            'effective_to',             fl.effective_to
          )
        )
        from formal_leaders fl
      ),
      '[]'::jsonb
    ),
    'members', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'household_membership_id', am.household_membership_id,
            'member_id',               am.member_id,
            'member_number',           am.member_number,
            'display_name',            am.display_name,
            'membership_status',       am.membership_status,
            'membership_role',         am.membership_role,
            'is_primary',              am.is_primary,
            'effective_from',          am.effective_from,
            'effective_to',            am.effective_to
          )
        )
        from active_members am
      ),
      '[]'::jsonb
    ),
    'counts', (
      select jsonb_build_object(
        'active_member_count',  (select count(*) from active_members),
        'target_member_count',  hi.target_member_count,
        'maximum_member_count', hi.maximum_member_count,
        'accepts_new_members',  hi.accepts_new_members
      )
      from household_identity hi
    )
  )
  into v_profile_data;

  return v_profile_data;
end;
$$;

comment on function public.get_household_profile(uuid, uuid) is
  'Returns complete household pastoral profile, former or current parent governance context, active members roster, and formal leaders.';

revoke execute on function public.get_household_profile(uuid, uuid) from public, anon;
grant  execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

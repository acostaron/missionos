-- =============================================================================
-- Migration: 20260930020000_phase_6b_pastoral_household_levels.sql
-- Phase:     Phase 6B-4 — Pastoral Household Levels & Leader Nourishment Structure
--
-- Authoritative Pastoral Household Ladder:
--   1. Member Household   (member)   -> Pastoral care for regular members. Formal office: Household Servant Leader.
--   2. Unit Household     (unit)     -> Pastoral nourishment for Household Leaders. Leader derived from Unit Servant Leader.
--   3. Chapter Household  (chapter)  -> Pastoral nourishment for Unit Leaders. Leader derived from Chapter Servant Leader.
--   4. Area Household     (area)     -> Pastoral nourishment for Chapter Leaders. Leader derived from Area Servant Leader.
--   5. Fraternal Household (fraternal)-> Pastoral nourishment for Area Servant Leader & senior unplaced members.
--                                       Peer-facilitated prayer meetings; NO permanent servant-leader office.
--
-- Domain Model Rules Enforced:
--   - public.households.pastoral_level text NOT NULL DEFAULT 'member'
--     CHECK (pastoral_level IN ('member', 'unit', 'chapter', 'area', 'fraternal'))
--   - household_category remains separate (pastoral, formation, mission, temporary, welcoming, other).
--   - leadership_model is derived dynamically, NOT stored as a writable column.
--   - Parent governance placement node validation:
--       * member:    Unit only (Chapter allowed only when no Unit exists under Chapter).
--       * unit:      Unit only.
--       * chapter:   Chapter only.
--       * area:      Area/State only.
--       * fraternal: Area/State only.
--   - Formal leadership guard: household_servant_leader appointment permitted only on member households.
--   - Fraternal household membership guard: membership_role must be 'member' (no servant/assistant).
--   - Update guard: pastoral_level change blocked if household has active memberships or active leadership.
--   - get_placement_nodes updated to include 'area_state' alongside 'chapter' and 'unit'.
--   - get_household_profile updated to project pastoral_level, pastoral_level_label, leadership_source,
--     and derive formal_leaders / pastoral couple from parent governance nodes for higher levels.
--   - search_households updated to project pastoral_level and pastoral_level_label.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Schema Extension — Add pastoral_level to public.households
-- =============================================================================

alter table public.households
  add column if not exists pastoral_level text not null default 'member';

-- Add check constraint safely
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ck_households__pastoral_level'
      and conrelid = 'public.households'::regclass
  ) then
    alter table public.households
      add constraint ck_households__pastoral_level
      check (pastoral_level in ('member', 'unit', 'chapter', 'area', 'fraternal'));
  end if;
end;
$$;

comment on column public.households.pastoral_level is
  'Authoritative pastoral household level: member, unit, chapter, area, or fraternal. Determines pastoral nourishment echelon and derived leadership model.';

-- =============================================================================
-- SECTION 2: Update public.get_placement_nodes
-- Include 'area_state' so Area and Fraternal households can be placed under Area/State.
-- =============================================================================

create or replace function public.get_placement_nodes(
  p_organization_id uuid
)
returns table (
  governance_node_id        uuid,
  node_code                 text,
  node_name                 text,
  node_type_code            text,
  parent_governance_node_id uuid,
  parent_node_name          text,
  hierarchy_rank            integer
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor_profile_id uuid;
begin
  -- 1. Resolve and verify authenticated caller profile
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  -- 2. Verify active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not belong to active organization.';
  end if;

  -- 3. Verify governance structure view permission
  if not private.has_permission('governance.structure.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission governance.structure.view.';
  end if;

  -- 4. Return selectable active Area/State, Chapter, and Unit nodes filtered to caller governance scope
  return query
  select
    n.id as governance_node_id,
    n.code as node_code,
    n.name as node_name,
    nt.code as node_type_code,
    case
      -- For unit, parent_governance_node_id is its primary parent chapter
      when nt.code = 'unit' then p_rel.parent_node_id
      -- For chapter, parent is its primary parent area_state
      when nt.code = 'chapter' then p_rel.parent_node_id
      else null
    end as parent_governance_node_id,
    case
      when nt.code in ('unit', 'chapter') then pn.name
      else null
    end as parent_node_name,
    nt.hierarchy_rank::integer as hierarchy_rank
  from public.governance_nodes n
  join public.governance_node_types nt
    on nt.id = n.governance_node_type_id
   and nt.organization_id = n.organization_id
  -- Join parent relationship for units and chapters
  left join public.governance_node_relationships p_rel
    on p_rel.child_node_id = n.id
   and p_rel.organization_id = n.organization_id
   and p_rel.is_primary = true
   and p_rel.relationship_status = 'active'
   and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
  left join public.governance_nodes pn
    on pn.id = p_rel.parent_node_id
   and pn.organization_id = n.organization_id
  where n.organization_id = p_organization_id
    and n.lifecycle_status = 'active'
    and (n.effective_to is null or n.effective_to >= current_date)
    and nt.code in ('area_state', 'chapter', 'unit')
    -- Enforce caller governance scope
    and private.profile_has_governance_scope(v_actor_profile_id, p_organization_id, n.id, now())
  order by
    nt.hierarchy_rank asc,
    coalesce(pn.name, n.name) asc,
    n.name asc;
end;
$$;

comment on function public.get_placement_nodes(uuid) is
  'Browser-safe RPC providing active Area/State, Chapter, and Unit nodes for governance placement selection, scoped to caller authorization.';

revoke all on function public.get_placement_nodes(uuid) from public, anon;
grant execute on function public.get_placement_nodes(uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: Update public.create_household Contract & Validations
-- =============================================================================

-- Drop legacy overload to ensure exact function replacement without multiple signatures
drop function if exists public.create_household(uuid, text, text, uuid, text, date, text, smallint, time without time zone, text, text, text, integer, integer, boolean, text, boolean);
drop function if exists public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean);

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
  p_is_couple_household       boolean  default false,
  p_pastoral_level            text     default 'member'
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
  v_pastoral_level         text;
  v_meeting_frequency      text;
  v_meeting_location_type  text;
  v_meeting_timezone_name  text;
  v_language_code          text;
  v_effective_from         date;
  v_unit_count_under_chap  integer;
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

  -- 6. Validate Pastoral Level
  v_pastoral_level := lower(trim(coalesce(p_pastoral_level, 'member')));
  if v_pastoral_level not in ('member', 'unit', 'chapter', 'area', 'fraternal') then
    raise exception using errcode = '22023',
      message = 'Invalid pastoral level: "' || v_pastoral_level || '". Allowed values: member, unit, chapter, area, fraternal.';
  end if;

  -- 7. Validate Parent Governance Node
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

  -- Parent lifecycle check: Parent must be active
  if v_parent_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Cannot attach a household to a parent node that is not active.';
  end if;

  -- Authoritative parent type validation based on pastoral_level
  if v_pastoral_level = 'member' then
    if v_parent_type.code = 'unit' then
      -- Standard placement under Unit
      null;
    elsif v_parent_type.code = 'chapter' then
      -- Chapter allowed ONLY when there are no active Unit nodes under this Chapter
      select count(*)
      into v_unit_count_under_chap
      from public.governance_node_relationships gnr
      join public.governance_nodes un
        on un.id = gnr.child_node_id
       and un.organization_id = gnr.organization_id
      join public.governance_node_types unt
        on unt.id = un.governance_node_type_id
       and unt.organization_id = un.organization_id
      where gnr.organization_id = p_organization_id
        and gnr.parent_node_id = v_parent_node.id
        and gnr.relationship_type = 'primary_parent'
        and gnr.relationship_status = 'active'
        and (gnr.effective_to is null or gnr.effective_to >= current_date)
        and unt.code = 'unit'
        and un.lifecycle_status = 'active';

      if v_unit_count_under_chap > 0 then
        raise exception using errcode = '22023',
          message = 'Member Household cannot be attached directly to Chapter "' || v_parent_node.name || '" because active Unit structures exist. Member households must be attached to a Unit.';
      end if;
    else
      raise exception using errcode = '22023',
        message = 'Member Household must be placed under a Unit (or Chapter if no Units exist). Parent was "' || v_parent_type.code || '".';
    end if;

  elsif v_pastoral_level = 'unit' then
    if v_parent_type.code != 'unit' then
      raise exception using errcode = '22023',
        message = 'Unit Household must be placed under a Unit. Parent was "' || v_parent_type.code || '".';
    end if;

  elsif v_pastoral_level = 'chapter' then
    if v_parent_type.code != 'chapter' then
      raise exception using errcode = '22023',
        message = 'Chapter Household must be placed under a Chapter. Parent was "' || v_parent_type.code || '".';
    end if;

  elsif v_pastoral_level in ('area', 'fraternal') then
    if v_parent_type.code != 'area_state' then
      raise exception using errcode = '22023',
        message = initcap(v_pastoral_level) || ' Household must be placed under an Area/State governance node. Parent was "' || v_parent_type.code || '".';
    end if;
  end if;

  -- 8. Validate Name
  v_name := trim(coalesce(p_name, ''));
  if v_name = '' then
    raise exception using errcode = '23502', message = 'Household name is required.';
  end if;
  if length(v_name) > 200 then
    raise exception using errcode = '22023', message = 'Household name must not exceed 200 characters.';
  end if;

  -- 9. Validate and normalize Code
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

  -- 10. Validate Configuration Fields
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

  -- 11. Atomic Multi-Table Creation: Step A: governance_nodes
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
    pastoral_level,
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
    v_pastoral_level,
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
      'pastoral_level',            v_pastoral_level,
      'is_couple_household',       coalesce(p_is_couple_household, false)
    )
  );

  -- 12. Return created contract
  return jsonb_build_object(
    'status',                    'created',
    'household_id',              v_new_household_id,
    'name',                      v_name,
    'code',                      v_code,
    'lifecycle_status',          'active',
    'pastoral_level',            v_pastoral_level,
    'parent_governance_node_id', p_parent_governance_node_id
  );
end;
$$;

comment on function public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean, text) is
  'Creates a pastoral household entity with authoritative pastoral level and parent node validation. Atomic transaction with full governance validation. Parent must be in active status.';

revoke execute on function public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean, text) from public, anon;
grant  execute on function public.create_household(uuid, text, text, uuid, text, date, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 4: Update public.update_household Contract & Validations
-- Guard: pastoral_level change blocked if household has active memberships or active leadership.
-- =============================================================================

-- Drop legacy overload to ensure exact function replacement without multiple signatures
drop function if exists public.update_household(uuid, uuid, text, text, text, text, smallint, time without time zone, text, text, text, integer, integer, boolean, text, boolean);
drop function if exists public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean);

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
  p_is_couple_household       boolean  default false,
  p_pastoral_level            text     default null
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
  v_pastoral_level        text;
  v_meeting_frequency     text;
  v_meeting_location_type text;
  v_meeting_timezone_name text;
  v_language_code         text;
  v_active_mem_count      integer;
  v_active_lead_count     integer;
  v_parent_node           public.governance_nodes%rowtype;
  v_parent_type           public.governance_node_types%rowtype;
  v_unit_count_under_chap integer;
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

  -- 6. Canonical lifecycle check: reject updates on closed, merged, or archived households
  -- Config edits are permitted only for 'planned', 'active', 'temporarily_inactive'
  if v_node.lifecycle_status in ('closed', 'merged', 'archived') then
    raise exception using errcode = '22023',
      message = 'Cannot update a household in ' || v_node.lifecycle_status || ' status.';
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

  -- 9. Pastoral Level Validation & Guard
  v_pastoral_level := coalesce(p_pastoral_level, v_household.pastoral_level);
  v_pastoral_level := lower(trim(v_pastoral_level));

  if v_pastoral_level not in ('member', 'unit', 'chapter', 'area', 'fraternal') then
    raise exception using errcode = '22023',
      message = 'Invalid pastoral level: "' || v_pastoral_level || '". Allowed values: member, unit, chapter, area, fraternal.';
  end if;

  if v_pastoral_level != v_household.pastoral_level then
    -- Check for active memberships
    select count(*)
    into v_active_mem_count
    from public.household_memberships hm
    where hm.organization_id = p_organization_id
      and hm.household_node_id = p_household_id
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date);

    if v_active_mem_count > 0 then
      raise exception using errcode = '22023',
        message = 'Cannot change pastoral level: household currently has ' || v_active_mem_count || ' active membership(s). Household must be empty to change pastoral level.';
    end if;

    -- Check for active formal leadership assignments
    select count(*)
    into v_active_lead_count
    from public.leadership_assignments la
    where la.organization_id = p_organization_id
      and la.governance_node_id = p_household_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date);

    if v_active_lead_count > 0 then
      raise exception using errcode = '22023',
        message = 'Cannot change pastoral level: household currently has active leadership assignment(s). Conclude leadership before changing pastoral level.';
    end if;

    -- Verify current parent relationship is compatible with new pastoral level
    select pgn.*
    into v_parent_node
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    where gnr.organization_id = p_organization_id
      and gnr.child_node_id = p_household_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    limit 1;

    if v_parent_node.id is not null then
      select *
      into v_parent_type
      from public.governance_node_types gnt
      where gnt.id = v_parent_node.governance_node_type_id
        and gnt.organization_id = p_organization_id;

      if v_pastoral_level = 'member' then
        if v_parent_type.code = 'chapter' then
          select count(*)
          into v_unit_count_under_chap
          from public.governance_node_relationships gnr
          join public.governance_nodes un
            on un.id = gnr.child_node_id
           and un.organization_id = gnr.organization_id
          join public.governance_node_types unt
            on unt.id = un.governance_node_type_id
           and unt.organization_id = un.organization_id
          where gnr.organization_id = p_organization_id
            and gnr.parent_node_id = v_parent_node.id
            and gnr.relationship_type = 'primary_parent'
            and gnr.relationship_status = 'active'
            and unt.code = 'unit'
            and un.lifecycle_status = 'active';

          if v_unit_count_under_chap > 0 then
            raise exception using errcode = '22023',
              message = 'Cannot change pastoral level to member: current parent Chapter has active Units.';
          end if;
        elsif v_parent_type.code != 'unit' then
          raise exception using errcode = '22023',
            message = 'Cannot change pastoral level to member: current parent node is not a Unit or valid Chapter fallback.';
        end if;
      elsif v_pastoral_level = 'unit' and v_parent_type.code != 'unit' then
        raise exception using errcode = '22023',
          message = 'Cannot change pastoral level to unit: current parent node is not a Unit.';
      elsif v_pastoral_level = 'chapter' and v_parent_type.code != 'chapter' then
        raise exception using errcode = '22023',
          message = 'Cannot change pastoral level to chapter: current parent node is not a Chapter.';
      elsif v_pastoral_level in ('area', 'fraternal') and v_parent_type.code != 'area_state' then
        raise exception using errcode = '22023',
          message = 'Cannot change pastoral level to ' || v_pastoral_level || ': current parent node is not an Area/State node.';
      end if;
    end if;
  end if;

  -- 10. Validate Configuration Fields
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

  -- 11. Update governance_nodes
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
    pastoral_level        = v_pastoral_level,
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
      'pastoral_level',      v_pastoral_level,
      'is_couple_household', coalesce(p_is_couple_household, false)
    )
  );

  return jsonb_build_object(
    'status',           'updated',
    'household_id',     p_household_id,
    'name',             v_name,
    'code',             v_code,
    'pastoral_level',   v_pastoral_level,
    'lifecycle_status', v_node.lifecycle_status
  );
end;
$$;

comment on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean, text) is
  'Updates operational identity and pastoral configuration for a household. Pastoral level change is guarded: allowed only if household has no active memberships or active leadership.';

revoke execute on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean, text) from public, anon;
grant  execute on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 5: Update Leadership Assignment Guard Trigger Function
-- household_servant_leader may ONLY be assigned to households with pastoral_level = 'member'.
-- =============================================================================

create or replace function private.validate_leadership_assignment()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  v_role         public.leadership_role_definitions%rowtype;
  v_node_type_id uuid;
  v_active_count integer;
  v_pair         public.leadership_assignments%rowtype;
  v_hh_level     text;
begin
  select *
    into v_role
  from public.leadership_role_definitions
  where organization_id = new.organization_id
    and id = new.leadership_role_definition_id
    and is_active;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Leadership role is not active for the organization.';
  end if;

  select governance_node_type_id
    into v_node_type_id
  from public.governance_nodes
  where organization_id = new.organization_id
    and id = new.governance_node_id;

  if not exists (
    select 1
    from public.leadership_role_node_types m
    where m.organization_id = new.organization_id
      and m.leadership_role_definition_id = new.leadership_role_definition_id
      and m.governance_node_type_id = v_node_type_id
      and m.is_active
  ) then
    raise exception using
      errcode = '23514',
      message = 'Leadership role is not valid for this governance node type.';
  end if;

  -- Phase 6B-4 Formal Leadership Guard:
  -- household_servant_leader is permitted ONLY on Member Households (pastoral_level = 'member').
  -- Higher-level pastoral households (unit, chapter, area, fraternal) derive their leadership
  -- from governance node leadership assignments or peer facilitation.
  if v_role.code = 'household_servant_leader' then
    select h.pastoral_level
    into v_hh_level
    from public.households h
    where h.id = new.governance_node_id
      and h.organization_id = new.organization_id;

    if v_hh_level is distinct from 'member' then
      raise exception using
        errcode = '23514',
        message = 'Household Servant Leader appointment is only permitted on Member Households. This household has pastoral level: "' || coalesce(v_hh_level, 'unknown') || '".';
    end if;
  end if;

  if v_role.maximum_term_months is not null
     and new.effective_from is not null
     and new.effective_to is not null
     and new.effective_to > (new.effective_from + make_interval(months => v_role.maximum_term_months))::date then
    raise exception using
      errcode = '23514',
      message = 'Leadership assignment exceeds the approved maximum term.';
  end if;

  if new.assignment_status in ('approved', 'accepted', 'active', 'suspended') then
    select count(*)
      into v_active_count
    from public.leadership_assignments a
    where a.organization_id = new.organization_id
      and a.governance_node_id = new.governance_node_id
      and a.leadership_role_definition_id = new.leadership_role_definition_id
      and a.assignment_status in ('approved', 'accepted', 'active', 'suspended')
      and a.id <> new.id
      and (
        a.effective_to is null
        or new.effective_from is null
        or a.effective_to >= new.effective_from
      )
      and (
        new.effective_to is null
        or a.effective_from is null
        or new.effective_to >= a.effective_from
      );

    if v_role.cardinality_type = 'single' and v_active_count >= 1 then
      raise exception using
        errcode = '23514',
        message = 'Only one current assignment is allowed for this role and governance node.';
    end if;

    if v_role.maximum_assignees is not null
       and v_active_count >= v_role.maximum_assignees then
      raise exception using
        errcode = '23514',
        message = 'Maximum current assignees reached for this role and governance node.';
    end if;
  end if;

  if new.paired_assignment_id is not null then
    select *
      into v_pair
    from public.leadership_assignments
    where id = new.paired_assignment_id;

    if not found
       or v_pair.organization_id <> new.organization_id
       or v_pair.governance_node_id <> new.governance_node_id
       or v_pair.leadership_role_definition_id <> new.leadership_role_definition_id
       or v_pair.member_id = new.member_id then
      raise exception using
        errcode = '23514',
        message = 'Paired leadership assignment is incompatible.';
    end if;
  end if;

  if v_role.requires_couple_pair
     and new.assignment_status in ('active', 'suspended')
     and new.paired_assignment_id is null then
    raise exception using
      errcode = '23514',
      message = 'This active leadership role requires a paired assignment.';
  end if;

  return new;
end;
$function$;

-- =============================================================================
-- SECTION 6: Update Fraternal Household Membership Guard
-- Trigger on household_memberships: for fraternal households, membership_role must be 'member'.
-- =============================================================================

create or replace function private.validate_household_membership_pastoral_rules()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_pastoral_level text;
begin
  select h.pastoral_level
  into v_pastoral_level
  from public.households h
  where h.id = new.household_node_id
    and h.organization_id = new.organization_id;

  if v_pastoral_level = 'fraternal' then
    if new.membership_role != 'member' then
      raise exception using
        errcode = '23514',
        message = 'Fraternal Household members must have membership_role = ''member''. Servant or assistant roles are not permitted.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_household_memberships__pastoral_rules on public.household_memberships;
create trigger trg_household_memberships__pastoral_rules
  before insert or update on public.household_memberships
  for each row
  execute function private.validate_household_membership_pastoral_rules();

-- =============================================================================
-- SECTION 7: Update public.get_household_profile RPC
-- Exposes pastoral_level, pastoral_level_label, leadership_source.
-- Derives formal leadership and pastoral couples dynamically based on pastoral_level:
--   member:    from household node leadership_assignments (household_servant_leader)
--   unit:      from parent Unit node leadership_assignments (unit_servant_leader)
--   chapter:   from parent Chapter node leadership_assignments (chapter_servant_leader)
--   area:      from parent Area node leadership_assignments (area_servant_leader)
--   fraternal: empty leaders array, null household_leaders, leadership_source = 'rotating_facilitation'
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

  -- 4. Governance-scoped access check
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Identifier permission for roster member numbers
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Build profile payload with pastoral echelon derivation
  with household_identity as (
    select
      gn.id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      h.pastoral_level,
      case h.pastoral_level
        when 'member'    then 'Member Household'
        when 'unit'      then 'Unit Household'
        when 'chapter'   then 'Chapter Household'
        when 'area'      then 'Area Household'
        when 'fraternal' then 'Fraternal Household'
        else initcap(h.pastoral_level) || ' Household'
      end as pastoral_level_label,
      case h.pastoral_level
        when 'member'    then 'household_servant_leader'
        when 'unit'      then 'unit_servant_leader'
        when 'chapter'   then 'chapter_servant_leader'
        when 'area'      then 'area_servant_leader'
        when 'fraternal' then 'rotating_facilitation'
      end as leadership_source,
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
      case when gnr.relationship_status = 'active' and gnr.effective_from <= current_date and (gnr.effective_to is null or gnr.effective_to >= current_date) then 0 else 1 end,
      gnr.effective_to desc nulls first,
      gnr.effective_from desc,
      gnr.created_at desc
    limit 1
  ),
  active_members as (
    select
      hm.id as household_membership_id,
      m.id as member_id,
      case
        when v_has_id_perm then m.member_number
        else null
      end as member_number,
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
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    order by
      case when hm.membership_role in ('servant', 'leader') then 0 else 1 end,
      m.display_name asc
  ),
  derived_leaders as (
    -- Member: from household node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    join public.leadership_assignments la
      on la.governance_node_id = hi.id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'member'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'household_servant_leader'

    union all

    -- Unit: from parent Unit node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'unit'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'unit_servant_leader'

    union all

    -- Chapter: from parent Chapter node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'chapter'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'chapter_servant_leader'

    union all

    -- Area: from parent Area node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'area'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'area_servant_leader'
  ),
  couple_leaders as (
    select
      lead.member_id as servant_member_id,
      lead.display_name as servant_display_name,
      lead.effective_from as servant_effective_from,
      spouse_mem.display_name as spouse_display_name,
      spouse_mem.id as spouse_member_id,
      case hi.pastoral_level
        when 'member'  then 'Household Leaders'
        when 'unit'    then 'Unit Leaders'
        when 'chapter' then 'Chapter Leaders'
        when 'area'    then 'Area Leaders'
      end as couple_title
    from derived_leaders lead
    join household_identity hi on hi.is_couple_household = true
    -- Spousal relationship check
    join public.family_relationships fr
      on fr.organization_id = p_organization_id
     and fr.relationship_status = 'active'
     and fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')
     and (fr.effective_from is null or fr.effective_from <= current_date)
     and (fr.effective_to is null or fr.effective_to >= current_date)
     and (fr.from_member_id = lead.member_id or fr.to_member_id = lead.member_id)
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
     and frt.code = 'spouse'
    cross join lateral (
      values (case when fr.from_member_id = lead.member_id then fr.to_member_id else fr.from_member_id end)
    ) as target_spouse(member_id)
    -- Spouse active member check
    join public.members spouse_mem
      on spouse_mem.id = target_spouse.member_id
     and spouse_mem.organization_id = p_organization_id
     and spouse_mem.record_status = 'active'
     and not spouse_mem.is_deceased
    -- For member households: spouse must also be a member of this household
    left join active_members am_spouse
      on am_spouse.member_id = target_spouse.member_id
    where (hi.pastoral_level != 'member' or am_spouse.member_id is not null)
      and hi.pastoral_level in ('member', 'unit', 'chapter', 'area')
    limit 1
  )
  select jsonb_build_object(
    'household', (
      select jsonb_build_object(
        'id',                    hi.id,
        'name',                  hi.name,
        'code',                  hi.code,
        'lifecycle_status',      hi.lifecycle_status,
        'household_category',    hi.household_category,
        'pastoral_level',        hi.pastoral_level,
        'pastoral_level_label',  hi.pastoral_level_label,
        'leadership_source',     hi.leadership_source,
        'effective_from',        hi.effective_from,
        'effective_to',          hi.effective_to,
        'meeting_frequency',     hi.meeting_frequency,
        'meeting_day_of_week',   hi.meeting_day_of_week,
        'meeting_start_time',    hi.meeting_start_time,
        'meeting_timezone_name', hi.meeting_timezone_name,
        'meeting_location_type', hi.meeting_location_type,
        'target_member_count',   hi.target_member_count,
        'maximum_member_count',  hi.maximum_member_count,
        'accepts_new_members',   hi.accepts_new_members,
        'language_code',         hi.language_code,
        'is_couple_household',   hi.is_couple_household
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
    'leaders', case
      when (select hi.pastoral_level from household_identity hi) = 'fraternal' then '[]'::jsonb
      else coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'leadership_assignment_id', dl.leadership_assignment_id,
              'member_id',                dl.member_id,
              'display_name',             dl.display_name,
              'leadership_role_code',     dl.leadership_role_code,
              'leadership_role_name',     dl.leadership_role_name,
              'assignment_status',        dl.assignment_status,
              'effective_from',           dl.effective_from,
              'effective_to',             dl.effective_to
            )
          )
          from derived_leaders dl
        ),
        '[]'::jsonb
      )
    end,
    'household_leaders', case
      when (select hi.pastoral_level from household_identity hi) = 'fraternal' then null
      else (
        select jsonb_build_object(
          'husband', jsonb_build_object(
            'member_id',    cl.servant_member_id,
            'display_name', cl.servant_display_name
          ),
          'wife', jsonb_build_object(
            'member_id',    cl.spouse_member_id,
            'display_name', cl.spouse_display_name
          ),
          'pastoral_label', cl.couple_title,
          'formatted_names', cl.servant_display_name || ' & ' || cl.spouse_display_name,
          'effective_from', cl.servant_effective_from
        )
        from couple_leaders cl
        limit 1
      )
    end,
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
  ) into v_profile_data;

  return v_profile_data;
end;
$$;

comment on function public.get_household_profile(uuid, uuid) is
  'Returns the complete pastoral household profile with authoritative pastoral level, leadership source, and dynamically derived leaders for all pastoral echelons.';

revoke execute on function public.get_household_profile(uuid, uuid) from public, anon;
grant  execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 8: Update public.search_households RPC
-- Projects pastoral_level and pastoral_level_label in search results.
-- =============================================================================

create or replace function public.search_households(
  p_organization_id           uuid,
  p_search                    text default null,
  p_parent_governance_node_id uuid default null,
  p_lifecycle_status          text default 'active',
  p_limit                     integer default 50,
  p_offset                    integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_total      integer;
  v_results    jsonb;
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
    raise exception using errcode = '42501', message = 'You do not have permission to search household records.';
  end if;

  -- 4. Count total accessible matching households
  select count(*)
  into v_total
  from public.governance_nodes gn
  join public.governance_node_types gnt
    on gnt.id = gn.governance_node_type_id
   and gnt.organization_id = gn.organization_id
  join public.households h
    on h.id = gn.id
   and h.organization_id = gn.organization_id
  left join lateral (
    select gnr.parent_node_id
    from public.governance_node_relationships gnr
    where gnr.child_node_id = gn.id
      and gnr.organization_id = gn.organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ) p_rel on true
  where gn.organization_id = p_organization_id
    and gnt.code = 'household'
    and (p_lifecycle_status is null or gn.lifecycle_status = p_lifecycle_status)
    and (p_parent_governance_node_id is null or p_rel.parent_node_id = p_parent_governance_node_id)
    and (
      p_search is null
      or p_search = ''
      or gn.name ilike '%' || p_search || '%'
      or gn.code ilike '%' || p_search || '%'
    )
    and private.can_access_household('households.records.view', p_organization_id, gn.id);

  -- 5. Query page of matching households
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'household_id',          gn.id,
        'name',                  gn.name,
        'code',                  gn.code,
        'lifecycle_status',      gn.lifecycle_status,
        'household_category',    h.household_category,
        'pastoral_level',        h.pastoral_level,
        'pastoral_level_label',  case h.pastoral_level
                                   when 'member'    then 'Member Household'
                                   when 'unit'      then 'Unit Household'
                                   when 'chapter'   then 'Chapter Household'
                                   when 'area'      then 'Area Household'
                                   when 'fraternal' then 'Fraternal Household'
                                   else initcap(h.pastoral_level) || ' Household'
                                 end,
        'parent_node_id',        p_gov.parent_node_id,
        'parent_node_name',      p_gov.parent_node_name,
        'parent_node_type',      p_gov.parent_node_type,
        'active_member_count',   coalesce(m_cnt.cnt, 0),
        'target_member_count',   h.target_member_count,
        'maximum_member_count',  h.maximum_member_count,
        'accepts_new_members',   h.accepts_new_members,
        'meeting_frequency',     h.meeting_frequency
      )
      order by gn.name asc
    ),
    '[]'::jsonb
  ) into v_results
  from (
    select gn.id, gn.name, gn.code, gn.lifecycle_status, gn.organization_id
    from public.governance_nodes gn
    join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id
     and gnt.organization_id = gn.organization_id
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    left join lateral (
      select gnr.parent_node_id
      from public.governance_node_relationships gnr
      where gnr.child_node_id = gn.id
        and gnr.organization_id = gn.organization_id
        and gnr.relationship_type = 'primary_parent'
        and gnr.relationship_status = 'active'
        and (gnr.effective_to is null or gnr.effective_to >= current_date)
      order by gnr.effective_from desc
      limit 1
    ) p_rel on true
    where gn.organization_id = p_organization_id
      and gnt.code = 'household'
      and (p_lifecycle_status is null or gn.lifecycle_status = p_lifecycle_status)
      and (p_parent_governance_node_id is null or p_rel.parent_node_id = p_parent_governance_node_id)
      and (
        p_search is null
        or p_search = ''
        or gn.name ilike '%' || p_search || '%'
        or gn.code ilike '%' || p_search || '%'
      )
      and private.can_access_household('households.records.view', p_organization_id, gn.id)
    order by gn.name asc
    limit least(coalesce(p_limit, 50), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  ) gn_paged
  join public.governance_nodes gn
    on gn.id = gn_paged.id
  join public.households h
    on h.id = gn.id
  left join lateral (
    select
      gnr.parent_node_id,
      pgn.name as parent_node_name,
      pgnt.code as parent_node_type
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    join public.governance_node_types pgnt
      on pgnt.id = pgn.governance_node_type_id
     and pgnt.organization_id = pgn.organization_id
    where gnr.child_node_id = gn.id
      and gnr.organization_id = gn.organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ) p_gov on true
  left join lateral (
    select count(*) as cnt
    from public.household_memberships hm
    where hm.household_node_id = gn.id
      and hm.organization_id = gn.organization_id
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
  ) m_cnt on true;

  return jsonb_build_object(
    'total_count', coalesce(v_total, 0),
    'limit',       least(coalesce(p_limit, 50), 100),
    'offset',      greatest(coalesce(p_offset, 0), 0),
    'households',  v_results
  );
end;
$$;

comment on function public.search_households(uuid, text, uuid, text, integer, integer) is
  'Searches pastoral households with authoritative pastoral level and parent node metadata, scoped to caller view permissions.';

revoke execute on function public.search_households(uuid, text, uuid, text, integer, integer) from public, anon;
grant  execute on function public.search_households(uuid, text, uuid, text, integer, integer) to authenticated, service_role;

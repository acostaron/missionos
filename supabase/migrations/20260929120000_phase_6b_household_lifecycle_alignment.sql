-- =============================================================================
-- Migration: 20260929120000_phase_6b_household_lifecycle_alignment.sql
-- Description: Phase 6B-2 Household lifecycle alignment with canonical
--              governance node lifecycle status constraint.
--
-- Authoritative governance_nodes lifecycle vocabulary:
--   'planned', 'active', 'temporarily_inactive', 'closed', 'merged', 'archived'
-- (Note: 'draft', 'suspended', 'dissolved' do NOT exist in public.governance_nodes)
--
-- Alignments:
--   1. update_household:
--      Allows edits ONLY for: 'planned', 'active', 'temporarily_inactive'
--      Rejects edits for: 'closed', 'merged', 'archived' with SQLSTATE 22023
--      Removes obsolete check for 'dissolved'
--   2. archive_household:
--      Allows archive ONLY for: 'planned', 'active', 'temporarily_inactive'
--      Rejects archive for: 'closed', 'merged', 'archived' with SQLSTATE 22023
--      (Historical states closed/merged cannot be converted to archived)
-- =============================================================================

-- =============================================================================
-- SECTION 1: update_household lifecycle alignment
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
  'Updates operational identity and pastoral configuration for a household. Governance parent placement is immutable in this RPC. Rejects updates to closed, merged, or archived households.';

revoke execute on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) from public, anon;
grant  execute on function public.update_household(uuid, uuid, text, text, text, text, smallint, time, text, text, text, integer, integer, boolean, text, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 2: archive_household lifecycle alignment
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

  -- 7. Canonical lifecycle check: reject duplicate archive and historical states (closed, merged)
  -- Archive is eligible only for: 'planned', 'active', 'temporarily_inactive'
  if v_node.lifecycle_status in ('closed', 'merged', 'archived') then
    raise exception using errcode = '22023',
      message = case
        when v_node.lifecycle_status = 'archived' then 'Household is already archived.'
        else 'Cannot archive a ' || v_node.lifecycle_status || ' household.'
      end;
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
  'Safely archives a household if no active members or leaders remain. Concludes primary parent relationship and transitions node to archived status. Rejects closed, merged, or already archived households.';

revoke execute on function public.archive_household(uuid, uuid, text) from public, anon;
grant  execute on function public.archive_household(uuid, uuid, text) to authenticated, service_role;

-- =============================================================================
-- Migration: 20260929130000_phase_6b_household_member_management.sql
-- Phase:     Phase 6B-3 — Household Member Assignment & Transfers
--
-- Objectives:
--   1. Seed narrow permissions:
--      - households.members.assign   (risk: high, domain: households, action: assign)
--      - households.members.transfer (risk: high, domain: households, action: transfer)
--      - households.members.end      (risk: high, domain: households, action: end)
--      Assign initially ONLY to organization_administrator.
--
--   2. Drop legacy unhardened overload:
--      DROP FUNCTION IF EXISTS public.assign_member_to_household(uuid, uuid, uuid, date, boolean, uuid);
--
--   3. Implement public.assign_member_to_household:
--      Assigns an eligible member to an active pastoral household.
--      Validates authentication, organization access, permission, caller scope over member and household,
--      member eligibility (active, not deceased), household eligibility (lifecycle_status = 'active'),
--      no overlapping current primary household, and governance tree compatibility.
--      Governance mismatch returns warning with confirmation pattern.
--      Creates active, primary, role='member' row and lets trigger update cache.
--      Emits 'governance' / 'household.member.assigned' audit event.
--
--   4. Implement public.transfer_household_member:
--      Transfers member from current primary household to a new active household in one atomic transaction.
--      Validates scope over member, source household, and destination household.
--      Blocks transfer if active formal household leadership exists on source household.
--      Ends old row (status = 'ended', effective_to = p_effective_date, ending_reason = p_reason).
--      Inserts new row (status = 'active', role = 'member', effective_from = p_effective_date, placement_source = 'transfer').
--      Supports same-day transfer.
--      Emits 'governance' / 'household.member.transferred' audit event.
--
--   5. Implement public.end_household_membership:
--      Ends a member's current primary household assignment without transfer.
--      Preserves complete historical record.
--      Blocks if active formal household leadership exists.
--      Updates row to status = 'ended', effective_to = p_effective_to, ending_reason = p_reason.
--      Trigger clears members.primary_household_node_id to null.
--      Emits 'governance' / 'household.member.ended' audit event.
--
--   6. Implement public.search_unassigned_household_members:
--      Surfaces active, non-deceased members with no current primary household assignment.
--      Enforces caller scope and field minimization (no contact PII, notes, or auth IDs).
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
    'households.members.assign',
    'Assign household members',
    'Assign eligible members to active pastoral households.',
    'households',
    'assign',
    'governance',
    'high',
    false,
    false,
    true
  ),
  (
    'households.members.transfer',
    'Transfer household members',
    'Transfer pastoral household members between active households.',
    'households',
    'transfer',
    'governance',
    'high',
    true,
    true,
    true
  ),
  (
    'households.members.end',
    'End household assignments',
    'Conclude member household assignments without transfer.',
    'households',
    'end',
    'governance',
    'high',
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
    'households.members.assign',
    'households.members.transfer',
    'households.members.end'
  )
on conflict do nothing;

-- =============================================================================
-- SECTION 2: Drop legacy unhardened overload
-- =============================================================================

drop function if exists public.assign_member_to_household(uuid, uuid, uuid, date, boolean, uuid);

-- =============================================================================
-- SECTION 3: public.assign_member_to_household RPC
-- =============================================================================

create or replace function public.assign_member_to_household(
  p_organization_id               uuid,
  p_member_id                     uuid,
  p_household_id                  uuid,
  p_effective_from                date    default current_date,
  p_confirm_governance_mismatch   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id            uuid;
  v_member                public.members%rowtype;
  v_household_node        public.governance_nodes%rowtype;
  v_household_detail      public.households%rowtype;
  v_effective_from        date;
  v_current_membership    record;
  v_member_gov_id         uuid;
  v_member_gov_name       text;
  v_household_parent_id   uuid;
  v_household_parent_name text;
  v_is_compatible         boolean := false;
  v_new_membership_id     uuid;
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
  if not private.has_permission('households.members.assign', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to assign household members.';
  end if;

  -- 4. Scope checks (indistinguishable P0002)
  if not private.can_access_member('households.members.assign', p_organization_id, p_member_id) then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  if not private.can_access_household('households.members.assign', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Lock member row FOR SHARE
  select *
  into v_member
  from public.members
  where id = p_member_id
    and organization_id = p_organization_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  -- Member eligibility checks
  if v_member.record_status != 'active' then
    raise exception using errcode = '22023',
      message = 'Cannot assign a member whose record status is not active (current status: ' || v_member.record_status || ').';
  end if;

  if v_member.is_deceased then
    raise exception using errcode = '22023',
      message = 'Cannot assign a deceased member to a pastoral household.';
  end if;

  -- 6. Lock destination household node and detail
  select *
  into v_household_node
  from public.governance_nodes
  where id = p_household_id
    and organization_id = p_organization_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  select *
  into v_household_detail
  from public.households
  where id = p_household_id
    and organization_id = p_organization_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household detail record not found.';
  end if;

  -- Household lifecycle check: Destination must be active
  if v_household_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023',
      message = 'Cannot assign members to a household in ' || v_household_node.lifecycle_status || ' status.';
  end if;

  -- 7. Validate effective date
  v_effective_from := coalesce(p_effective_from, current_date);
  if v_member.joined_on is not null and v_effective_from < v_member.joined_on then
    raise exception using errcode = '22023',
      message = 'Assignment effective date cannot precede member join date (' || v_member.joined_on || ').';
  end if;

  -- 8. Duplicate / Overlapping Current Primary Assignment Check
  -- Defined as: is_primary = true AND membership_status in ('active','temporary') AND (effective_to is null or effective_to >= v_effective_from)
  select
    hm.id as membership_id,
    hm.household_node_id,
    gn.name as household_name
  into v_current_membership
  from public.household_memberships hm
  join public.governance_nodes gn
    on gn.id = hm.household_node_id
   and gn.organization_id = hm.organization_id
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= v_effective_from)
  order by (hm.effective_to is null) desc, hm.effective_from desc
  limit 1;

  if v_current_membership.membership_id is not null then
    if v_current_membership.household_node_id = p_household_id then
      return jsonb_build_object(
        'status',                'blocked',
        'blocker_type',          'already_member_of_destination',
        'existing_household_id', v_current_membership.household_node_id,
        'existing_household_name', v_current_membership.household_name,
        'message',               'Member already has an active primary membership in this household.'
      );
    else
      return jsonb_build_object(
        'status',                'blocked',
        'blocker_type',          'existing_primary_household',
        'existing_household_id', v_current_membership.household_node_id,
        'existing_household_name', v_current_membership.household_name,
        'message',               'This member already has a current primary household (' || v_current_membership.household_name || '). Use Transfer Household to change pastoral placement.'
      );
    end if;
  end if;

  -- 9. Governance Compatibility Check
  -- Resolve member primary governance node
  select
    mga.governance_node_id,
    gn.name
  into
    v_member_gov_id,
    v_member_gov_name
  from public.member_governance_assignments mga
  join public.governance_nodes gn
    on gn.id = mga.governance_node_id
   and gn.organization_id = mga.organization_id
  where mga.organization_id = p_organization_id
    and mga.member_id = p_member_id
    and mga.is_primary = true
    and mga.assignment_status = 'active'
    and (mga.effective_to is null or mga.effective_to >= v_effective_from)
  order by (mga.effective_to is null) desc, mga.effective_from desc
  limit 1;

  -- Resolve household parent governance node
  select
    gnr.parent_node_id,
    pgn.name
  into
    v_household_parent_id,
    v_household_parent_name
  from public.governance_node_relationships gnr
  join public.governance_nodes pgn
    on pgn.id = gnr.parent_node_id
   and pgn.organization_id = gnr.organization_id
  where gnr.organization_id = p_organization_id
    and gnr.child_node_id = p_household_id
    and gnr.relationship_type = 'primary_parent'
    and gnr.relationship_status = 'active'
    and (gnr.effective_to is null or gnr.effective_to >= v_effective_from)
  limit 1;

  if v_member_gov_id is null then
    -- Member is unplaced in governance
    if not p_confirm_governance_mismatch then
      return jsonb_build_object(
        'status',                    'warning',
        'warning_type',              'governance_unplaced',
        'household_parent_node_id',   v_household_parent_id,
        'household_parent_name',     v_household_parent_name,
        'message',                   'Member has no primary Unit or Chapter governance placement. Household assignment does not change governance placement.',
        'requires_confirmation',     true
      );
    end if;
  else
    -- Member is placed: check compatibility
    -- Compatible if:
    -- 1. household parent equals member governance node
    -- 2. OR household parent is a descendant of member governance node
    if v_household_parent_id = v_member_gov_id then
      v_is_compatible := true;
    else
      select exists (
        select 1
        from private.resolve_governance_descendants(
          p_organization_id,
          v_member_gov_id,
          v_effective_from,
          null
        ) d
        where d.descendant_node_id = v_household_parent_id
      ) into v_is_compatible;
    end if;

    if not v_is_compatible and not p_confirm_governance_mismatch then
      return jsonb_build_object(
        'status',                    'warning',
        'warning_type',              'governance_mismatch',
        'member_governance_node_id', v_member_gov_id,
        'member_governance_name',    v_member_gov_name,
        'household_parent_node_id',   v_household_parent_id,
        'household_parent_name',     v_household_parent_name,
        'message',                   'Household parent (' || coalesce(v_household_parent_name, 'Unknown') || ') does not match member governance placement (' || coalesce(v_member_gov_name, 'Unknown') || '). Household assignment does not change governance placement.',
        'requires_confirmation',     true
      );
    end if;
  end if;

  -- 10. Insert new household membership
  v_new_membership_id := gen_random_uuid();

  insert into public.household_memberships (
    id,
    organization_id,
    member_id,
    household_node_id,
    membership_status,
    membership_role,
    effective_from,
    effective_to,
    is_primary,
    placement_source,
    approved_at,
    approved_by_profile_id,
    created_by_profile_id,
    updated_by_profile_id
  ) values (
    v_new_membership_id,
    p_organization_id,
    p_member_id,
    p_household_id,
    'active',
    'member',
    v_effective_from,
    null,
    true,
    'administrative',
    now(),
    v_profile_id,
    v_profile_id,
    v_profile_id
  );

  -- 11. Write audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household.member.assigned',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_membership',
    p_entity_id        => v_new_membership_id,
    p_action           => 'assign',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_membership_id',       v_new_membership_id,
      'member_id',                     p_member_id,
      'household_id',                  p_household_id,
      'household_name',                v_household_node.name,
      'effective_from',                v_effective_from,
      'confirmed_governance_mismatch', p_confirm_governance_mismatch
    )
  );

  -- 12. Return structured success
  return jsonb_build_object(
    'status',                  'assigned',
    'household_membership_id', v_new_membership_id,
    'member_id',               p_member_id,
    'household_id',            p_household_id,
    'household_name',          v_household_node.name,
    'effective_from',          v_effective_from,
    'membership_role',         'member',
    'is_primary',              true
  );
end;
$$;

comment on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) is
  'Assigns an eligible member to an active pastoral household. Checks member and household access, member eligibility, active household status, existing primary membership, and governance compatibility with confirmation warning.';

revoke execute on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) from public, anon;
grant execute on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 4: public.transfer_household_member RPC
-- =============================================================================

create or replace function public.transfer_household_member(
  p_organization_id               uuid,
  p_member_id                     uuid,
  p_destination_household_id      uuid,
  p_effective_date                date    default current_date,
  p_reason                        text    default null,
  p_confirm_governance_mismatch   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id            uuid;
  v_reason                text;
  v_effective_date        date;
  v_current_membership    public.household_memberships%rowtype;
  v_current_count         integer;
  v_source_node           public.governance_nodes%rowtype;
  v_dest_node             public.governance_nodes%rowtype;
  v_dest_detail           public.households%rowtype;
  v_member                public.members%rowtype;
  v_active_leaders_count  integer;
  v_member_gov_id         uuid;
  v_member_gov_name       text;
  v_dest_parent_id        uuid;
  v_dest_parent_name      text;
  v_is_compatible         boolean := false;
  v_new_membership_id     uuid;
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
  if not private.has_permission('households.members.transfer', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to transfer household members.';
  end if;

  -- 4. Validate Reason
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = '23502', message = 'Transfer reason is required.';
  end if;

  -- 5. Scope check on target member (indistinguishable P0002)
  if not private.can_access_member('households.members.transfer', p_organization_id, p_member_id) then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  -- 6. Lock member record FOR SHARE
  select *
  into v_member
  from public.members
  where id = p_member_id
    and organization_id = p_organization_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  if v_member.record_status != 'active' then
    raise exception using errcode = '22023',
      message = 'Cannot transfer a member whose record status is not active (current status: ' || v_member.record_status || ').';
  end if;

  if v_member.is_deceased then
    raise exception using errcode = '22023',
      message = 'Cannot transfer a deceased member.';
  end if;

  v_effective_date := coalesce(p_effective_date, current_date);

  -- 7. Lock current primary membership FOR UPDATE
  -- Check for existing primary memberships
  select count(*)
  into v_current_count
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= v_effective_date);

  if v_current_count = 0 then
    return jsonb_build_object(
      'status',       'blocked',
      'blocker_type', 'no_current_household',
      'message',      'Member does not have a current primary household assignment. Use Assign Household instead.'
    );
  elsif v_current_count > 1 then
    return jsonb_build_object(
      'status',       'blocked',
      'blocker_type', 'data_integrity_error',
      'message',      'Member has multiple active primary household assignments. Manual data resolution is required before transferring.'
    );
  end if;

  select *
  into v_current_membership
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= v_effective_date)
  for update;

  -- 8. Scope check on source household
  if not private.can_access_household('households.members.transfer', p_organization_id, v_current_membership.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Source household not found or not accessible.';
  end if;

  -- 9. Destination same as source check
  if p_destination_household_id = v_current_membership.household_node_id then
    return jsonb_build_object(
      'status',       'blocked',
      'blocker_type', 'destination_same_as_source',
      'message',      'Destination household cannot be the same as the current household.'
    );
  end if;

  -- 10. Scope check on destination household
  if not private.can_access_household('households.members.transfer', p_organization_id, p_destination_household_id) then
    raise exception using errcode = 'P0002', message = 'Destination household not found or not accessible.';
  end if;

  -- 11. Lock destination household node and detail
  select *
  into v_dest_node
  from public.governance_nodes
  where id = p_destination_household_id
    and organization_id = p_organization_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'Destination household not found or not accessible.';
  end if;

  select *
  into v_dest_detail
  from public.households
  where id = p_destination_household_id
    and organization_id = p_organization_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'Destination household detail not found.';
  end if;

  -- Destination lifecycle check
  if v_dest_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023',
      message = 'Cannot transfer a member to a household in ' || v_dest_node.lifecycle_status || ' status.';
  end if;

  -- 12. Date consistency check
  if v_effective_date < v_current_membership.effective_from then
    raise exception using errcode = '22023',
      message = 'Transfer effective date (' || v_effective_date || ') cannot precede the current membership start date (' || v_current_membership.effective_from || ').';
  end if;

  -- 13. Active Leadership Safety Guard
  -- Check if member currently holds active formal leadership in the source household
  select count(*)
  into v_active_leaders_count
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.member_id = p_member_id
    and la.governance_node_id = v_current_membership.household_node_id
    and la.assignment_status = 'active'
    and (la.effective_to is null or la.effective_to >= v_effective_date);

  if v_active_leaders_count > 0 then
    return jsonb_build_object(
      'status',                  'blocked',
      'blocker_type',            'active_household_leadership',
      'active_leadership_count', v_active_leaders_count,
      'message',                 'Conclude the member''s household leadership appointment before changing this household assignment.'
    );
  end if;

  -- 14. Governance Compatibility Check on Destination
  select
    mga.governance_node_id,
    gn.name
  into
    v_member_gov_id,
    v_member_gov_name
  from public.member_governance_assignments mga
  join public.governance_nodes gn
    on gn.id = mga.governance_node_id
   and gn.organization_id = mga.organization_id
  where mga.organization_id = p_organization_id
    and mga.member_id = p_member_id
    and mga.is_primary = true
    and mga.assignment_status = 'active'
    and (mga.effective_to is null or mga.effective_to >= v_effective_date)
  order by (mga.effective_to is null) desc, mga.effective_from desc
  limit 1;

  select
    gnr.parent_node_id,
    pgn.name
  into
    v_dest_parent_id,
    v_dest_parent_name
  from public.governance_node_relationships gnr
  join public.governance_nodes pgn
    on pgn.id = gnr.parent_node_id
   and pgn.organization_id = gnr.organization_id
  where gnr.organization_id = p_organization_id
    and gnr.child_node_id = p_destination_household_id
    and gnr.relationship_type = 'primary_parent'
    and gnr.relationship_status = 'active'
    and (gnr.effective_to is null or gnr.effective_to >= v_effective_date)
  limit 1;

  if v_member_gov_id is null then
    if not p_confirm_governance_mismatch then
      return jsonb_build_object(
        'status',                    'warning',
        'warning_type',              'governance_unplaced',
        'household_parent_node_id',   v_dest_parent_id,
        'household_parent_name',     v_dest_parent_name,
        'message',                   'Member has no primary Unit or Chapter governance placement. Household transfer does not change governance placement.',
        'requires_confirmation',     true
      );
    end if;
  else
    if v_dest_parent_id = v_member_gov_id then
      v_is_compatible := true;
    else
      select exists (
        select 1
        from private.resolve_governance_descendants(
          p_organization_id,
          v_member_gov_id,
          v_effective_date,
          null
        ) d
        where d.descendant_node_id = v_dest_parent_id
      ) into v_is_compatible;
    end if;

    if not v_is_compatible and not p_confirm_governance_mismatch then
      return jsonb_build_object(
        'status',                    'warning',
        'warning_type',              'governance_mismatch',
        'member_governance_node_id', v_member_gov_id,
        'member_governance_name',    v_member_gov_name,
        'household_parent_node_id',   v_dest_parent_id,
        'household_parent_name',     v_dest_parent_name,
        'message',                   'Destination household parent (' || coalesce(v_dest_parent_name, 'Unknown') || ') does not match member governance placement (' || coalesce(v_member_gov_name, 'Unknown') || '). Household transfer does not change governance placement.',
        'requires_confirmation',     true
      );
    end if;
  end if;

  -- 15. Resolve source household name for response
  select name into v_source_node.name
  from public.governance_nodes
  where id = v_current_membership.household_node_id;

  -- 16. End old membership
  update public.household_memberships
  set
    membership_status     = 'ended',
    effective_to          = v_effective_date,
    ending_reason         = 'Transferred: ' || v_reason,
    updated_by_profile_id = v_profile_id
  where id = v_current_membership.id;

  -- 17. Insert new membership
  v_new_membership_id := gen_random_uuid();

  insert into public.household_memberships (
    id,
    organization_id,
    member_id,
    household_node_id,
    membership_status,
    membership_role,
    effective_from,
    effective_to,
    is_primary,
    placement_source,
    approved_at,
    approved_by_profile_id,
    created_by_profile_id,
    updated_by_profile_id
  ) values (
    v_new_membership_id,
    p_organization_id,
    p_member_id,
    p_destination_household_id,
    'active',
    'member',
    v_effective_date,
    null,
    true,
    'administrative',
    now(),
    v_profile_id,
    v_profile_id,
    v_profile_id
  );

  -- 18. Write audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household.member.transferred',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_membership',
    p_entity_id        => v_new_membership_id,
    p_action           => 'transfer',
    p_outcome          => 'success',
    p_access_reason    => v_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'old_household_membership_id',   v_current_membership.id,
      'new_household_membership_id',   v_new_membership_id,
      'member_id',                     p_member_id,
      'source_household_id',           v_current_membership.household_node_id,
      'source_household_name',         v_source_node.name,
      'destination_household_id',      p_destination_household_id,
      'destination_household_name',    v_dest_node.name,
      'effective_date',                v_effective_date,
      'transfer_reason',               v_reason,
      'confirmed_governance_mismatch', p_confirm_governance_mismatch
    )
  );

  -- 19. Return structured success
  return jsonb_build_object(
    'status',                      'transferred',
    'old_household_membership_id', v_current_membership.id,
    'new_household_membership_id', v_new_membership_id,
    'member_id',                   p_member_id,
    'source_household_id',         v_current_membership.household_node_id,
    'source_household_name',       v_source_node.name,
    'destination_household_id',    p_destination_household_id,
    'destination_household_name',  v_dest_node.name,
    'effective_date',              v_effective_date,
    'membership_role',             'member',
    'is_primary',                  true
  );
end;
$$;

comment on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) is
  'Transfers a member from their current primary household to an active destination household in one atomic transaction. Validates source and destination access, guards active leadership, updates source to ended, inserts destination as active, and preserves placement history.';

revoke execute on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) from public, anon;
grant execute on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 5: public.end_household_membership RPC
-- =============================================================================

create or replace function public.end_household_membership(
  p_organization_id uuid,
  p_member_id       uuid,
  p_effective_to    date default current_date,
  p_reason          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id           uuid;
  v_reason               text;
  v_effective_to         date;
  v_current_count        integer;
  v_current_membership   public.household_memberships%rowtype;
  v_household_node       public.governance_nodes%rowtype;
  v_active_leaders_count integer;
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
  if not private.has_permission('households.members.end', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to end household memberships.';
  end if;

  -- 4. Validate Reason
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = '23502', message = 'Ending reason is required.';
  end if;

  -- 5. Scope check on target member (indistinguishable P0002)
  if not private.can_access_member('households.members.end', p_organization_id, p_member_id) then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  v_effective_to := coalesce(p_effective_to, current_date);

  -- 6. Lock current primary membership FOR UPDATE
  select count(*)
  into v_current_count
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= v_effective_to);

  if v_current_count = 0 then
    raise exception using errcode = 'P0002',
      message = 'Member does not have an active household assignment to end.';
  elsif v_current_count > 1 then
    return jsonb_build_object(
      'status',       'blocked',
      'blocker_type', 'data_integrity_error',
      'message',      'Member has multiple active primary household assignments. Manual data resolution is required.'
    );
  end if;

  select *
  into v_current_membership
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= v_effective_to)
  for update;

  -- 7. Scope check on household
  if not private.can_access_household('households.members.end', p_organization_id, v_current_membership.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 8. Date consistency check
  if v_effective_to < v_current_membership.effective_from then
    raise exception using errcode = '22023',
      message = 'Effective end date (' || v_effective_to || ') cannot precede the membership start date (' || v_current_membership.effective_from || ').';
  end if;

  -- 9. Leadership Safety Guard
  select count(*)
  into v_active_leaders_count
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.member_id = p_member_id
    and la.governance_node_id = v_current_membership.household_node_id
    and la.assignment_status = 'active'
    and (la.effective_to is null or la.effective_to >= v_effective_to);

  if v_active_leaders_count > 0 then
    return jsonb_build_object(
      'status',                  'blocked',
      'blocker_type',            'active_household_leadership',
      'active_leadership_count', v_active_leaders_count,
      'message',                 'Conclude the member''s household leadership appointment before ending this household assignment.'
    );
  end if;

  -- 10. Resolve household node name for audit & response
  select *
  into v_household_node
  from public.governance_nodes
  where id = v_current_membership.household_node_id;

  -- 11. End membership
  update public.household_memberships
  set
    membership_status     = 'ended',
    effective_to          = v_effective_to,
    ending_reason         = v_reason,
    updated_by_profile_id = v_profile_id
  where id = v_current_membership.id;

  -- 12. Write audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household.member.ended',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_membership',
    p_entity_id        => v_current_membership.id,
    p_action           => 'end',
    p_outcome          => 'success',
    p_access_reason    => v_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_membership_id', v_current_membership.id,
      'member_id',               p_member_id,
      'household_id',            v_current_membership.household_node_id,
      'household_name',          v_household_node.name,
      'effective_to',            v_effective_to,
      'ending_reason',           v_reason
    )
  );

  -- 13. Return structured success
  return jsonb_build_object(
    'status',                  'ended',
    'household_membership_id', v_current_membership.id,
    'member_id',               p_member_id,
    'household_id',            v_current_membership.household_node_id,
    'household_name',          v_household_node.name,
    'effective_to',            v_effective_to,
    'ending_reason',           v_reason
  );
end;
$$;

comment on function public.end_household_membership(uuid, uuid, date, text) is
  'Concludes a member''s current primary household assignment without transfer. Validates scope, guards active leadership, updates status to ended, preserves assignment history, and triggers placement cache clearing.';

revoke execute on function public.end_household_membership(uuid, uuid, date, text) from public, anon;
grant execute on function public.end_household_membership(uuid, uuid, date, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 6: public.search_unassigned_household_members RPC
-- =============================================================================

create or replace function public.search_unassigned_household_members(
  p_organization_id uuid,
  p_search          text    default null,
  p_limit           integer default 50,
  p_offset          integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id          uuid;
  v_has_id_perm         boolean;
  v_search_query        text;
  v_limit               integer;
  v_offset              integer;
  v_total_count         bigint;
  v_members_arr         jsonb;
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
  if not private.has_permission('households.members.assign', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view unassigned household members.';
  end if;

  -- 4. Identifier permission
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  v_search_query := nullif(trim(p_search), '');
  v_limit := greatest(1, least(coalesce(p_limit, 50), 100));
  v_offset := greatest(0, coalesce(p_offset, 0));

  -- 5. Query candidate unassigned members (active, not deceased, no current primary household assignment)
  --    that caller has scope to access via private.can_access_member.
  with unassigned_candidates as (
    select
      m.id as member_id,
      m.member_number,
      m.display_name,
      m.sort_name,
      ms.code as membership_status_code,
      ms.name as membership_status_name,
      m.primary_governance_node_id,
      gn.name as governance_node_name,
      gnt.code as governance_node_type
    from public.members m
    join public.member_statuses ms
      on ms.id = m.membership_status_id
     and ms.organization_id = m.organization_id
    left join public.governance_nodes gn
      on gn.id = m.primary_governance_node_id
     and gn.organization_id = m.organization_id
    left join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id
     and gnt.organization_id = gn.organization_id
    where m.organization_id = p_organization_id
      and m.record_status = 'active'
      and not m.is_deceased
      and not exists (
        select 1
        from public.household_memberships hm
        where hm.organization_id = p_organization_id
          and hm.member_id = m.id
          and hm.is_primary = true
          and hm.membership_status in ('active', 'temporary')
          and (hm.effective_to is null or hm.effective_to >= current_date)
      )
      and private.can_access_member('households.members.assign', p_organization_id, m.id)
      and (
        v_search_query is null
        or m.display_name ilike '%' || v_search_query || '%'
        or (v_has_id_perm and m.member_number ilike '%' || v_search_query || '%')
      )
  ),
  counted as (
    select count(*) as total_count from unassigned_candidates
  ),
  paginated as (
    select *
    from unassigned_candidates
    order by sort_name asc, display_name asc
    limit v_limit
    offset v_offset
  )
  select
    coalesce((select total_count from counted), 0),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'member_id',                   p.member_id,
            'member_number',               case when v_has_id_perm then p.member_number else null end,
            'display_name',                p.display_name,
            'membership_status_code',      p.membership_status_code,
            'membership_status_name',      p.membership_status_name,
            'primary_governance_node_id',  p.primary_governance_node_id,
            'primary_governance_node_name', p.governance_node_name,
            'primary_governance_node_type', p.governance_node_type
          )
        )
        from paginated p
      ),
      '[]'::jsonb
    )
  into v_total_count, v_members_arr;

  return jsonb_build_object(
    'members',     v_members_arr,
    'total_count', v_total_count,
    'limit',       v_limit,
    'offset',      v_offset
  );
end;
$$;

comment on function public.search_unassigned_household_members(uuid, text, integer, integer) is
  'Returns paginated list of active non-deceased members with no current primary household assignment. Safe field projection, enforced governance scope, and identifier gating.';

revoke execute on function public.search_unassigned_household_members(uuid, text, integer, integer) from public, anon;
grant execute on function public.search_unassigned_household_members(uuid, text, integer, integer) to authenticated, service_role;

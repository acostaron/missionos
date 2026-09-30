-- =============================================================================
-- Migration: 20260929140000_phase_6b_household_member_integrity.sql
-- Phase:     Phase 6B-3 — Household Member Temporal Integrity & Terminology Alignment
--
-- Objectives:
--   1. Drop legacy routine name:
--      public.search_unassigned_household_members(uuid, text, integer, integer)
--
--   2. Implement canonical public.search_members_without_household:
--      - Correct domain terminology: members without household (not "unassigned household members")
--      - Robust current membership check: ignores future-dated legacy/imported rows:
--        effective_from <= current_date AND (effective_to IS NULL OR effective_to >= current_date)
--
--   3. Update public.assign_member_to_household:
--      - Temporal safety: rejects future effective dates (p_effective_from > current_date) with 22023.
--      - Accurate current duplicate check:
--        effective_from <= v_effective_from AND (effective_to IS NULL OR effective_to >= v_effective_from)
--
--   4. Update public.transfer_household_member:
--      - Temporal safety: rejects future transfer dates (p_effective_date > current_date) with 22023.
--      - Accurate current membership check:
--        effective_from <= v_effective_date AND (effective_to IS NULL OR effective_to >= v_effective_date)
--      - Leadership inconsistency safety guard: blocks transfer if membership_role in ('servant', 'assistant_servant')
--        with no matching active formal leadership appointment.
--
--   5. Update public.end_household_membership:
--      - Temporal safety: rejects future end dates (p_effective_to > current_date) with 22023.
--      - Accurate current membership check:
--        effective_from <= v_effective_to AND (effective_to IS NULL OR effective_to >= v_effective_to)
--      - Leadership inconsistency safety guard: blocks ending if membership_role in ('servant', 'assistant_servant')
--        with no matching active formal leadership appointment.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Drop old search_unassigned_household_members
-- =============================================================================

drop function if exists public.search_unassigned_household_members(uuid, text, integer, integer);

-- =============================================================================
-- SECTION 2: Canonical public.search_members_without_household RPC
-- =============================================================================

create or replace function public.search_members_without_household(
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
    raise exception using errcode = '42501', message = 'You do not have permission to view members without a household.';
  end if;

  -- 4. Identifier permission
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  v_search_query := nullif(trim(p_search), '');
  v_limit := greatest(1, least(coalesce(p_limit, 50), 100));
  v_offset := greatest(0, coalesce(p_offset, 0));

  -- 5. Query candidate members without household:
  --    Active, not deceased, and NO CURRENT primary household assignment
  --    (defined as is_primary = true, status in ('active', 'temporary'),
  --     effective_from <= current_date, and (effective_to is null or effective_to >= current_date)).
  with candidate_members as (
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
          and hm.effective_from <= current_date
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
    select count(*) as total_count from candidate_members
  ),
  paginated as (
    select *
    from candidate_members
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

comment on function public.search_members_without_household(uuid, text, integer, integer) is
  'Returns paginated list of active non-deceased members with no current primary household assignment. Safe field projection, enforced governance scope, and identifier gating.';

revoke execute on function public.search_members_without_household(uuid, text, integer, integer) from public, anon;
grant execute on function public.search_members_without_household(uuid, text, integer, integer) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: Update public.assign_member_to_household
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

  -- 7. Validate effective date & Future-Date Guard
  v_effective_from := coalesce(p_effective_from, current_date);

  if v_effective_from > current_date then
    raise exception using errcode = '22023',
      message = 'Future household assignment changes are not supported yet.';
  end if;

  if v_member.joined_on is not null and v_effective_from < v_member.joined_on then
    raise exception using errcode = '22023',
      message = 'Assignment effective date cannot precede member join date (' || v_member.joined_on || ').';
  end if;

  -- 8. Duplicate / Overlapping Current Primary Assignment Check
  -- Defined as: is_primary = true AND membership_status in ('active','temporary')
  -- AND effective_from <= v_effective_from AND (effective_to is null or effective_to >= v_effective_from)
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
    and hm.effective_from <= v_effective_from
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
    and mga.effective_from <= v_effective_from
    and (mga.effective_to is null or mga.effective_to >= v_effective_from)
  order by (mga.effective_to is null) desc, mga.effective_from desc
  limit 1;

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
    and gnr.effective_from <= v_effective_from
    and (gnr.effective_to is null or gnr.effective_to >= v_effective_from)
  limit 1;

  if v_member_gov_id is null then
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
  'Assigns an eligible member to an active pastoral household. Checks member and household access, member eligibility, active household status, existing primary membership, future date restriction, and governance compatibility with confirmation warning.';

revoke execute on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) from public, anon;
grant execute on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 4: Update public.transfer_household_member
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

  -- 7. Validate effective date & Future-Date Guard
  v_effective_date := coalesce(p_effective_date, current_date);

  if v_effective_date > current_date then
    raise exception using errcode = '22023',
      message = 'Future household assignment changes are not supported yet.';
  end if;

  -- 8. Lock current primary membership FOR UPDATE
  -- Defined as: is_primary = true AND membership_status in ('active','temporary')
  -- AND effective_from <= v_effective_date AND (effective_to is null or effective_to >= v_effective_date)
  select count(*)
  into v_current_count
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= v_effective_date
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
    and hm.effective_from <= v_effective_date
    and (hm.effective_to is null or hm.effective_to >= v_effective_date)
  for update;

  -- 9. Scope check on source household
  if not private.can_access_household('households.members.transfer', p_organization_id, v_current_membership.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Source household not found or not accessible.';
  end if;

  -- 10. Destination same as source check
  if p_destination_household_id = v_current_membership.household_node_id then
    return jsonb_build_object(
      'status',       'blocked',
      'blocker_type', 'destination_same_as_source',
      'message',      'Destination household cannot be the same as the current household.'
    );
  end if;

  -- 11. Scope check on destination household
  if not private.can_access_household('households.members.transfer', p_organization_id, p_destination_household_id) then
    raise exception using errcode = 'P0002', message = 'Destination household not found or not accessible.';
  end if;

  -- 12. Lock destination household node and detail
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

  -- 13. Date consistency check
  if v_effective_date < v_current_membership.effective_from then
    raise exception using errcode = '22023',
      message = 'Transfer effective date (' || v_effective_date || ') cannot precede the current membership start date (' || v_current_membership.effective_from || ').';
  end if;

  -- 14. Active Leadership Safety Guard
  select count(*)
  into v_active_leaders_count
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.member_id = p_member_id
    and la.governance_node_id = v_current_membership.household_node_id
    and la.assignment_status = 'active'
    and la.effective_from <= v_effective_date
    and (la.effective_to is null or la.effective_to >= v_effective_date);

  if v_active_leaders_count > 0 then
    return jsonb_build_object(
      'status',                  'blocked',
      'blocker_type',            'active_household_leadership',
      'active_leadership_count', v_active_leaders_count,
      'message',                 'Conclude the member''s household leadership appointment before changing this household assignment.'
    );
  end if;

  -- 15. Leadership-Role Inconsistency Guard
  -- If membership_role is servant or assistant_servant but no active formal appointment exists
  if v_current_membership.membership_role in ('servant', 'assistant_servant') then
    return jsonb_build_object(
      'status',          'blocked',
      'blocker_type',    'leadership_role_inconsistency',
      'membership_role', v_current_membership.membership_role,
      'message',         'This household membership carries a leadership role but no matching active formal leadership appointment was found. Resolve the leadership data before changing the household assignment.'
    );
  end if;

  -- 16. Governance Compatibility Check on Destination
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
    and mga.effective_from <= v_effective_date
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
    and gnr.effective_from <= v_effective_date
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

  -- 17. Resolve source household name for response
  select name into v_source_node.name
  from public.governance_nodes
  where id = v_current_membership.household_node_id;

  -- 18. End old membership
  update public.household_memberships
  set
    membership_status     = 'ended',
    effective_to          = v_effective_date,
    ending_reason         = 'Transferred: ' || v_reason,
    updated_by_profile_id = v_profile_id
  where id = v_current_membership.id;

  -- 19. Insert new membership
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

  -- 20. Write audit event
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

  -- 21. Return structured success
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
  'Transfers a member from their current primary household to an active destination household in one atomic transaction. Validates source and destination access, guards active leadership, guards leadership role inconsistency, enforces future date restrictions, updates source to ended, inserts destination as active, and preserves placement history.';

revoke execute on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) from public, anon;
grant execute on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) to authenticated, service_role;

-- =============================================================================
-- SECTION 5: Update public.end_household_membership
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

  -- 6. Validate effective date & Future-Date Guard
  v_effective_to := coalesce(p_effective_to, current_date);

  if v_effective_to > current_date then
    raise exception using errcode = '22023',
      message = 'Future household assignment changes are not supported yet.';
  end if;

  -- 7. Lock current primary membership FOR UPDATE
  -- Defined as: is_primary = true AND membership_status in ('active','temporary')
  -- AND effective_from <= v_effective_to AND (effective_to is null or effective_to >= v_effective_to)
  select count(*)
  into v_current_count
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= v_effective_to
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
    and hm.effective_from <= v_effective_to
    and (hm.effective_to is null or hm.effective_to >= v_effective_to)
  for update;

  -- 8. Scope check on household
  if not private.can_access_household('households.members.end', p_organization_id, v_current_membership.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 9. Date consistency check
  if v_effective_to < v_current_membership.effective_from then
    raise exception using errcode = '22023',
      message = 'Effective end date (' || v_effective_to || ') cannot precede the membership start date (' || v_current_membership.effective_from || ').';
  end if;

  -- 10. Leadership Safety Guard
  select count(*)
  into v_active_leaders_count
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.member_id = p_member_id
    and la.governance_node_id = v_current_membership.household_node_id
    and la.assignment_status = 'active'
    and la.effective_from <= v_effective_to
    and (la.effective_to is null or la.effective_to >= v_effective_to);

  if v_active_leaders_count > 0 then
    return jsonb_build_object(
      'status',                  'blocked',
      'blocker_type',            'active_household_leadership',
      'active_leadership_count', v_active_leaders_count,
      'message',                 'Conclude the member''s household leadership appointment before ending this household assignment.'
    );
  end if;

  -- 11. Leadership-Role Inconsistency Guard
  -- If membership_role is servant or assistant_servant but no active formal appointment exists
  if v_current_membership.membership_role in ('servant', 'assistant_servant') then
    return jsonb_build_object(
      'status',          'blocked',
      'blocker_type',    'leadership_role_inconsistency',
      'membership_role', v_current_membership.membership_role,
      'message',         'This household membership carries a leadership role but no matching active formal leadership appointment was found. Resolve the leadership data before changing the household assignment.'
    );
  end if;

  -- 12. Resolve household node name for audit & response
  select *
  into v_household_node
  from public.governance_nodes
  where id = v_current_membership.household_node_id;

  -- 13. End membership
  update public.household_memberships
  set
    membership_status     = 'ended',
    effective_to          = v_effective_to,
    ending_reason         = v_reason,
    updated_by_profile_id = v_profile_id
  where id = v_current_membership.id;

  -- 14. Write audit event
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

  -- 15. Return structured success
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
  'Concludes a member''s current primary household assignment without transfer. Validates scope, guards active leadership, guards leadership role inconsistency, enforces future date restrictions, updates status to ended, preserves assignment history, and triggers placement cache clearing.';

revoke execute on function public.end_household_membership(uuid, uuid, date, text) from public, anon;
grant execute on function public.end_household_membership(uuid, uuid, date, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 6: Update public.get_household_profile
-- Enforce effective_from <= current_date on active members roster and leaders
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
      and hm.effective_from <= current_date
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
      and la.effective_from <= current_date
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
  'Returns complete household pastoral profile, former or current parent governance context, active members roster, and formal leaders. Enforces temporal currentness (effective_from <= current_date).';

revoke execute on function public.get_household_profile(uuid, uuid) from public, anon;
grant  execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

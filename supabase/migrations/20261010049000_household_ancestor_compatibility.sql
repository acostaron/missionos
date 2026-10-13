-- Pass 5.0: household placement compatibility also accepts households whose parent is an ancestor of the member's placement (leadership and fraternal households). Different branches still warn.

CREATE OR REPLACE FUNCTION public.assign_member_to_household(p_organization_id uuid, p_member_id uuid, p_household_id uuid, p_effective_from date DEFAULT CURRENT_DATE, p_confirm_governance_mismatch boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
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
        'message',                   'Member has no placement yet (area, chapter or unit). Household assignment does not change governance placement.',
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

      if not v_is_compatible and v_household_parent_id is not null then
        select exists (
          select 1
          from private.resolve_governance_descendants(
            p_organization_id,
            v_household_parent_id,
            v_effective_from,
            null
          ) d
          where d.descendant_node_id = v_member_gov_id
        ) into v_is_compatible;
      end if;
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
$function$
;

CREATE OR REPLACE FUNCTION public.transfer_household_member(p_organization_id uuid, p_member_id uuid, p_destination_household_id uuid, p_effective_date date DEFAULT CURRENT_DATE, p_reason text DEFAULT NULL::text, p_confirm_governance_mismatch boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
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
        'message',                   'Member has no placement yet (area, chapter or unit). Household transfer does not change governance placement.',
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

      if not v_is_compatible and v_dest_parent_id is not null then
        select exists (
          select 1
          from private.resolve_governance_descendants(
            p_organization_id,
            v_dest_parent_id,
            v_effective_date,
            null
          ) d
          where d.descendant_node_id = v_member_gov_id
        ) into v_is_compatible;
      end if;
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
$function$
;

revoke execute on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) from public, anon;
grant execute on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) to authenticated, service_role;

revoke execute on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) from public, anon;
grant execute on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) to authenticated, service_role;

-- Pass 6.1A: sections are recognised by kind (public.sections.section_category), not by code, so each sub-area can have its own sections. Adds reusable sub-area section setup and creates the FMC New York sections.

--------------------------------------------------------------------------------
-- B1. HELPERS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.section_kind(p_section_node_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $$
  SELECT s.section_category
  FROM public.sections s
  WHERE s.id = p_section_node_id;
$$;

CREATE OR REPLACE FUNCTION private.section_sub_area(p_section_node_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $$
  SELECT p.id
  FROM public.governance_node_relationships r
  JOIN public.governance_nodes p ON p.id = r.parent_node_id
  JOIN public.governance_node_types pt ON pt.id = p.governance_node_type_id
  WHERE r.child_node_id = p_section_node_id
    AND r.relationship_type = 'primary_parent'
    AND r.is_primary = true
    AND r.relationship_status = 'active'
    AND (r.effective_to IS NULL OR r.effective_to >= current_date)
    AND pt.code = 'area_state'
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION private.section_kind(uuid) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION private.section_sub_area(uuid) FROM public, anon, authenticated;

--------------------------------------------------------------------------------
-- B2. REWRITE FOUR FUNCTIONS USING SECTION KIND
--------------------------------------------------------------------------------

-- 1. public.change_member_section
CREATE OR REPLACE FUNCTION public.change_member_section(p_organization_id uuid, p_member_id uuid, p_section_code text, p_effective_from date DEFAULT CURRENT_DATE, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_actor_profile_id uuid;
  v_can_manage boolean;
  v_member public.members%rowtype;
  v_cur_membership public.section_memberships%rowtype;
  v_cur_section_code text;
  v_target_node public.governance_nodes%rowtype;
  v_new_membership_id uuid;
  v_old_partner_id uuid;
  v_new_paired_member_id uuid := null;
  v_spouse_member_id uuid;
  v_spouse_couples_membership_id uuid;
  v_coordinator_assignment public.leadership_assignments%rowtype;
  v_elig jsonb;
begin
  -- 1. Authentication
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  -- 2. Organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- 3. Permission checks (member-records-manage permission + can_access_member)
  v_can_manage := (
    private.has_permission('members.records.update', p_organization_id)
    or private.has_permission('members.placements.manage', p_organization_id)
  ) and (
    private.can_access_member('members.records.update', p_organization_id, p_member_id)
    or private.can_access_member('members.placements.manage', p_organization_id, p_member_id)
  );

  if not v_can_manage then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission to manage member section or outside governance scope.';
  end if;

  -- 4. Reason validation (required, min 5 chars)
  if p_reason is null or length(trim(p_reason)) < 5 then
    raise exception using errcode = '22023', message = 'A reason of at least 5 characters is required.';
  end if;

  -- Effective date default & validation
  if p_effective_from is null then
    p_effective_from := current_date;
  end if;
  if p_effective_from > current_date then
    raise exception using errcode = '22023', message = 'Effective date cannot be in the future.';
  end if;

  -- 5. Member active check
  select * into v_member
  from public.members
  where id = p_member_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  if v_member.record_status != 'active' or v_member.is_deceased then
    raise exception using errcode = '22023', message = 'Member must be active to change section.';
  end if;

  -- 6. Target section node validation
  select * into v_target_node
  from public.governance_nodes gn
  where gn.organization_id = p_organization_id
    and gn.code = p_section_code
    and gn.lifecycle_status = 'active';

  if not found then
    raise exception using errcode = 'P0002', message = 'Target section not found or not active: ' || coalesce(p_section_code, 'null');
  end if;

  if not (
    exists (
      select 1 from public.governance_node_types gnt
      where gnt.id = v_target_node.governance_node_type_id
        and gnt.code = 'section'
    )
    and private.section_kind(v_target_node.id) is not null
  ) then
    raise exception using errcode = '22023', message = 'Invalid section code: ' || v_target_node.code;
  end if;

  -- 7. Current primary section membership
  select sm.* into v_cur_membership
  from public.section_memberships sm
  where sm.organization_id = p_organization_id
    and sm.member_id = p_member_id
    and sm.membership_status = 'active'
    and sm.is_primary = true
    and (sm.effective_to is null or sm.effective_to >= current_date)
  for update;

  if found then
    select gn.code into v_cur_section_code
    from public.governance_nodes gn
    where gn.id = v_cur_membership.section_node_id;

    if v_cur_membership.section_node_id = v_target_node.id then
      raise exception using errcode = '22023', message = 'Member is already in this section.';
    end if;

    if p_effective_from < v_cur_membership.effective_from then
      raise exception using errcode = '22023',
        message = format('Effective date (%s) cannot precede current section start date (%s).', p_effective_from, v_cur_membership.effective_from);
    end if;

    v_old_partner_id := v_cur_membership.paired_member_id;
  end if;

  -- 8. Couple pairing logic
  -- If leaving Couples: clear paired_member_id on BOTH partners' rows
  if private.section_kind(v_cur_membership.section_node_id) = 'couples' and private.section_kind(v_target_node.id) != 'couples' then
    if v_old_partner_id is not null then
      update public.section_memberships
      set paired_member_id = null,
          updated_at = clock_timestamp(),
          updated_by_profile_id = v_actor_profile_id
      where organization_id = p_organization_id
        and member_id = v_old_partner_id
        and membership_status = 'active'
        and is_primary = true;
    end if;
  end if;

  -- If joining Couples: pair automatically ONLY if an active administrator/document-verified spouse is also in Couples
  if private.section_kind(v_target_node.id) = 'couples' then
    select (case when fr.from_member_id = p_member_id then fr.to_member_id else fr.from_member_id end)
    into v_spouse_member_id
    from public.family_relationships fr
    join public.family_relationship_types frt on frt.id = fr.relationship_type_id
    where fr.organization_id = p_organization_id
      and frt.code = 'spouse'
      and fr.relationship_status = 'active'
      and (fr.effective_to is null or fr.effective_to >= current_date)
      and fr.verification_status in ('administrator_verified', 'document_verified')
      and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id)
    limit 1;

    if v_spouse_member_id is not null then
      select sm.id into v_spouse_couples_membership_id
      from public.section_memberships sm
      where sm.organization_id = p_organization_id
        and sm.member_id = v_spouse_member_id
        and sm.membership_status = 'active'
        and sm.is_primary = true
        and sm.section_node_id = v_target_node.id
        and (sm.effective_to is null or sm.effective_to >= current_date)
      limit 1;

      if v_spouse_couples_membership_id is not null then
        v_new_paired_member_id := v_spouse_member_id;

        update public.section_memberships
        set paired_member_id = p_member_id,
            updated_at = clock_timestamp(),
            updated_by_profile_id = v_actor_profile_id
        where id = v_spouse_couples_membership_id;
      end if;
    end if;
  end if;

  -- 9. End current primary membership
  if v_cur_membership.id is not null then
    update public.section_memberships
    set membership_status = 'ended',
        effective_to = p_effective_from,
        ending_reason = trim(p_reason),
        updated_at = clock_timestamp(),
        updated_by_profile_id = v_actor_profile_id
    where id = v_cur_membership.id;
  end if;

  -- 10. Insert new primary membership
  insert into public.section_memberships (
    organization_id,
    member_id,
    section_node_id,
    membership_status,
    effective_from,
    is_primary,
    placement_source,
    paired_member_id,
    created_by_profile_id,
    updated_by_profile_id
  ) values (
    p_organization_id,
    p_member_id,
    v_target_node.id,
    'active',
    p_effective_from,
    true,
    'administrative',
    v_new_paired_member_id,
    v_actor_profile_id,
    v_actor_profile_id
  ) returning id into v_new_membership_id;

  -- 11. Coordinator conflict check:
  -- If the member holds an active area_section_coordinator role whose eligibility would now fail
  -- -> 22023 "End this member's coordinator role first."
  select la.* into v_coordinator_assignment
  from public.leadership_assignments la
  join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
  where la.organization_id = p_organization_id
    and la.member_id = p_member_id
    and lrd.code = 'area_section_coordinator'
    and la.assignment_status = 'active'
  limit 1;

  if v_coordinator_assignment.id is not null then
    v_elig := private.section_coordinator_eligibility(
      p_organization_id,
      p_member_id,
      v_coordinator_assignment.governance_node_id
    );

    if not coalesce((v_elig->>'eligible')::boolean, false) then
      raise exception using errcode = '22023', message = 'End this member''s coordinator role first.';
    end if;
  end if;

  -- 12. Record audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.section.changed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'member',
    p_entity_id        => p_member_id,
    p_action           => 'transfer_section',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'previous_section_node_id', v_cur_membership.section_node_id,
      'previous_section_code', v_cur_section_code,
      'new_section_node_id', v_target_node.id,
      'new_section_code', v_target_node.code,
      'effective_from', p_effective_from,
      'reason', trim(p_reason),
      'new_paired_member_id', v_new_paired_member_id
    )
  );

  return jsonb_build_object(
    'status', 'success',
    'member_id', p_member_id,
    'previous_section_code', v_cur_section_code,
    'new_section_code', v_target_node.code,
    'new_section_name', v_target_node.name,
    'membership_id', v_new_membership_id,
    'paired_member_id', v_new_paired_member_id
  );
end;
$function$;

-- 2. public.change_members_section_bulk
CREATE OR REPLACE FUNCTION public.change_members_section_bulk(p_organization_id uuid, p_member_ids uuid[], p_section_code text, p_effective_from date DEFAULT CURRENT_DATE, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_actor_profile_id     uuid;
  v_can_manage           boolean;
  v_target_node          public.governance_nodes%rowtype;
  v_deduped_member_ids   uuid[];
  v_requested_count      integer;
  v_processed_count      integer := 0;
  v_changed_count        integer := 0;
  v_skipped_count        integer := 0;
  v_member_id            uuid;
  v_member               public.members%rowtype;
  v_changed_results      jsonb := '[]'::jsonb;
  v_skipped_results      jsonb := '[]'::jsonb;
  v_single_res           jsonb;
  v_correlation_id       uuid;
begin
  -- 1. Authentication
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  -- 2. Organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- 3. Permission checks (member-records-update or members.placements.manage)
  v_can_manage := (
    private.has_permission('members.records.update', p_organization_id)
    or private.has_permission('members.placements.manage', p_organization_id)
  );

  if not v_can_manage then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission to manage member sections.';
  end if;

  -- 4. Reason validation (required, min 5 chars)
  if p_reason is null or length(trim(p_reason)) < 5 then
    raise exception using errcode = '22023', message = 'A reason of at least 5 characters is required.';
  end if;

  -- 5. Effective date validation
  if p_effective_from is null or p_effective_from > current_date then
    raise exception using errcode = '22023', message = 'Effective date cannot be in the future.';
  end if;

  -- 6. Section validation
  if p_section_code is null then
    raise exception using errcode = '22023', message = 'Choose a valid section.';
  end if;

  select * into v_target_node
  from public.governance_nodes gn
  where gn.organization_id = p_organization_id
    and gn.code = p_section_code
    and gn.lifecycle_status = 'active';

  if not found or not (
    exists (
      select 1 from public.governance_node_types gnt
      where gnt.id = v_target_node.governance_node_type_id
        and gnt.code = 'section'
    )
    and private.section_kind(v_target_node.id) is not null
  ) then
    raise exception using errcode = '22023', message = 'Choose a valid section.';
  end if;

  -- 7. Member IDs deduplication & bounds check
  select coalesce(array_agg(mid order by min_ord), array[]::uuid[])
  into v_deduped_member_ids
  from (
    select mid, min(ord) as min_ord
    from unnest(coalesce(p_member_ids, array[]::uuid[])) with ordinality as u(mid, ord)
    where mid is not null
    group by mid
  ) s;

  v_requested_count := coalesce(cardinality(v_deduped_member_ids), 0);

  if v_requested_count = 0 then
    raise exception using errcode = '22023', message = 'Select at least one member.';
  end if;

  if v_requested_count > 100 then
    raise exception using errcode = '22023', message = 'You can change at most 100 members at a time.';
  end if;

  v_correlation_id := gen_random_uuid();

  -- 8. Process each member
  foreach v_member_id in array v_deduped_member_ids loop
    select * into v_member
    from public.members
    where id = v_member_id
      and organization_id = p_organization_id;

    if not found then
      v_skipped_count := v_skipped_count + 1;
      v_skipped_results := v_skipped_results || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'member_not_found'
      ));
      continue;
    end if;

    if v_member.record_status != 'active' then
      v_skipped_count := v_skipped_count + 1;
      v_skipped_results := v_skipped_results || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'record_not_active'
      ));
      continue;
    end if;

    if v_member.is_deceased then
      v_skipped_count := v_skipped_count + 1;
      v_skipped_results := v_skipped_results || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'deceased'
      ));
      continue;
    end if;

    if not (
      private.can_access_member('members.records.update', p_organization_id, v_member_id)
      or private.can_access_member('members.placements.manage', p_organization_id, v_member_id)
    ) then
      v_skipped_count := v_skipped_count + 1;
      v_skipped_results := v_skipped_results || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'outside_governance_scope'
      ));
      continue;
    end if;

    if v_member.primary_section_node_id = v_target_node.id then
      v_skipped_count := v_skipped_count + 1;
      v_skipped_results := v_skipped_results || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'already_in_section'
      ));
      continue;
    end if;

    -- Execute section change via canonical procedure
    v_single_res := public.change_member_section(
      p_organization_id  => p_organization_id,
      p_member_id        => v_member_id,
      p_section_code     => p_section_code,
      p_effective_from   => p_effective_from,
      p_reason           => p_reason
    );

    v_changed_count := v_changed_count + 1;
    v_changed_results := v_changed_results || jsonb_build_array(jsonb_build_object(
      'member_id', v_member_id,
      'previous_section_code', v_single_res->>'previous_section_code',
      'new_section_code', v_single_res->>'new_section_code',
      'paired_member_id', v_single_res->>'paired_member_id'
    ));
  end loop;

  v_processed_count := v_changed_count + v_skipped_count;

  -- 9. Batch summary audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.section.bulk_changed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'governance_node',
    p_entity_id        => v_target_node.id,
    p_action           => 'bulk_transfer_section',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => v_correlation_id,
    p_metadata         => jsonb_build_object(
      'target_section_node_id', v_target_node.id,
      'target_section_code', v_target_node.code,
      'effective_from', p_effective_from,
      'reason', trim(p_reason),
      'requested_count', v_requested_count,
      'changed_count', v_changed_count,
      'skipped_count', v_skipped_count
    )
  );

  return jsonb_build_object(
    'status',          'success',
    'requested_count', v_requested_count,
    'processed_count', v_processed_count,
    'changed_count',   v_changed_count,
    'skipped_count',   v_skipped_count,
    'changed',         v_changed_results,
    'skipped',         v_skipped_results
  );
end;
$function$;

-- 3. private.section_coordinator_eligibility
CREATE OR REPLACE FUNCTION private.section_coordinator_eligibility(p_org uuid, p_member uuid, p_section_node uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_member public.members%rowtype;
  v_section_node public.governance_nodes%rowtype;
  v_member_section_code text;
  v_spouse_member_id uuid;
  v_has_active_verified_spouse boolean := false;
begin
  select *
  into v_member
  from public.members
  where id = p_member
    and organization_id = p_org;

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'member_not_found',
      'message', 'Member not found.'
    );
  end if;

  if v_member.record_status != 'active' then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'member_not_active',
      'message', 'Candidate member record is not active.'
    );
  end if;

  if v_member.is_deceased then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'member_deceased',
      'message', 'Deceased members cannot serve as coordinators.'
    );
  end if;

  select *
  into v_section_node
  from public.governance_nodes
  where id = p_section_node
    and organization_id = p_org;

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'section_not_found',
      'message', 'Section node not found.'
    );
  end if;

  if private.section_kind(v_section_node.id) = 'couples' then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'sec_couples_no_coordinator',
      'message', 'Couples section does not have an area coordinator.'
    );
  end if;

  select private.section_kind(sm.section_node_id)
  into v_member_section_code
  from public.section_memberships sm
  where sm.organization_id = p_org
    and sm.member_id = p_member
    and sm.membership_status = 'active'
    and sm.is_primary = true
  limit 1;

  select (case when fr.from_member_id = p_member then fr.to_member_id else fr.from_member_id end)
  into v_spouse_member_id
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id
  where fr.organization_id = p_org
    and frt.code = 'spouse'
    and fr.relationship_status = 'active'
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and fr.verification_status in ('administrator_verified', 'document_verified')
    and (fr.from_member_id = p_member or fr.to_member_id = p_member)
  limit 1;

  if v_spouse_member_id is not null then
    select exists (
      select 1
      from public.members sp
      where sp.id = v_spouse_member_id
        and sp.organization_id = p_org
        and sp.record_status = 'active'
        and not sp.is_deceased
    ) into v_has_active_verified_spouse;
  end if;

  case private.section_kind(v_section_node.id)
    when 'handmaids' then
      if v_member.sex != 'female' then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'handmaids_female_only',
          'message', 'Handmaids section coordinator must be female.'
        );
      end if;

      if not (v_member_section_code = 'handmaids' or (v_member_section_code = 'couples' and v_has_active_verified_spouse)) then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'handmaids_section_or_couples_spouse',
          'message', 'Handmaids coordinator must be in Handmaids section or in Couples with an active verified spouse.'
        );
      end if;

    when 'servants' then
      if v_member.sex != 'male' then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'servants_male_only',
          'message', 'Servants section coordinator must be male.'
        );
      end if;

      if not (v_member_section_code = 'servants' or (v_member_section_code = 'couples' and v_has_active_verified_spouse)) then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'servants_section_or_couples_spouse',
          'message', 'Servants coordinator must be in Servants section or in Couples with an active verified spouse.'
        );
      end if;

    when 'kids', 'youth', 'singles', 'campus' then
      if (v_member.sex = 'male' and v_member_section_code = 'couples' and v_has_active_verified_spouse)
         or (v_member.sex = 'male') then
        null;
      else
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'family_section_couple_or_male',
          'message', 'Section coordinator for ' || coalesce(v_section_node.name, v_section_node.code) || ' must be a couple (husband in Couples with active verified spouse) or a male member.'
        );
      end if;

    else
      return jsonb_build_object(
        'eligible', false,
        'rule_failed', 'unsupported_section',
        'message', 'Unsupported section code for section coordinator: ' || v_section_node.code
      );
  end case;

  return jsonb_build_object(
    'eligible', true,
    'rule_failed', null,
    'message', 'Candidate member is eligible.'
  );
end;
$function$;

-- 4. private.appoint_area_coordinator_core
CREATE OR REPLACE FUNCTION private.appoint_area_coordinator_core(p_organization_id uuid, p_role_code text, p_node_id uuid, p_member_id uuid, p_effective_from date DEFAULT CURRENT_DATE, p_exception_reason text DEFAULT NULL::text, p_actor_profile_id uuid DEFAULT NULL::uuid, p_source text DEFAULT 'rpc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_role_code text;
  v_role_def public.leadership_role_definitions%rowtype;
  v_node public.governance_nodes%rowtype;
  v_node_type public.governance_node_types%rowtype;
  v_member public.members%rowtype;
  v_eligibility jsonb;
  v_is_exception boolean := false;
  v_exception_reason text := null;
  v_rule_failed text := null;
  v_existing_active_id uuid;
  v_new_assignment_id uuid;
  v_partner_member_id uuid;
  v_couple_partner_id uuid := null;
  v_partner_assignment_id uuid := null;
  v_metadata jsonb;
begin
  v_role_code := coalesce(p_role_code, 'area_section_coordinator');

  select *
  into v_node
  from public.governance_nodes gn
  where gn.id = p_node_id
    and gn.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  if v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Coordinators may only be appointed to active governance nodes.';
  end if;

  if private.section_kind(v_node.id) = 'couples' then
    raise exception using errcode = '22023', message = 'Couples section does not have an area coordinator.';
  end if;

  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.organization_id = p_organization_id
    and lrd.code = v_role_code
    and lrd.is_active = true;

  if not found then
    raise exception using errcode = '22023', message = 'Leadership role "' || v_role_code || '" is not configured or active.';
  end if;

  select gnt.*
  into v_node_type
  from public.governance_node_types gnt
  join public.leadership_role_node_types lrnt on lrnt.governance_node_type_id = gnt.id
  where lrnt.organization_id = p_organization_id
    and lrnt.leadership_role_definition_id = v_role_def.id
    and lrnt.is_active = true
    and gnt.id = v_node.governance_node_type_id;

  if not found then
    raise exception using errcode = '22023',
      message = 'Governance node type is not compatible with leadership role "' || v_role_code || '".';
  end if;

  select *
  into v_member
  from public.members m
  where m.id = p_member_id
    and m.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidate member not found.';
  end if;

  if v_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Candidate member record is not active.';
  end if;

  if v_member.is_deceased then
    raise exception using errcode = '22023', message = 'Cannot appoint a deceased member as coordinator.';
  end if;

  if v_role_code = 'area_section_coordinator' then
    v_eligibility := private.section_coordinator_eligibility(p_organization_id, p_member_id, p_node_id);
    if not (v_eligibility->>'eligible')::boolean then
      if p_exception_reason is null or trim(p_exception_reason) = '' then
        raise exception using errcode = '22023',
          message = coalesce(v_eligibility->>'message', 'Candidate member is not eligible for this section coordinator role.');
      else
        v_is_exception := true;
        v_exception_reason := trim(p_exception_reason);
        v_rule_failed := v_eligibility->>'rule_failed';
      end if;
    end if;
  end if;

  select la.id
  into v_existing_active_id
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date)
  limit 1;

  if v_existing_active_id is not null then
    raise exception using errcode = '23505',
      message = 'This section already has an active coordinator.';
  end if;

  select (case when fr.from_member_id = p_member_id then fr.to_member_id else fr.from_member_id end)
  into v_partner_member_id
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id
  where fr.organization_id = p_organization_id
    and frt.code = 'spouse'
    and fr.relationship_status = 'active'
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and fr.verification_status in ('administrator_verified', 'document_verified')
    and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id)
  limit 1;

  if private.section_kind(v_node.id) in ('campus', 'youth', 'singles', 'kids') and v_partner_member_id is not null then
    v_couple_partner_id := v_partner_member_id;
  end if;

  v_metadata := jsonb_build_object(
    'role_code', v_role_code,
    'source', p_source
  );

  if p_actor_profile_id is not null then
    v_metadata := v_metadata || jsonb_build_object('appointed_by_profile', p_actor_profile_id);
  end if;

  if v_couple_partner_id is not null then
    v_metadata := v_metadata || jsonb_build_object('couple_partner_member_id', v_couple_partner_id);
  end if;

  if v_is_exception then
    v_metadata := v_metadata || jsonb_build_object(
      'eligibility_exception', true,
      'exception_reason', v_exception_reason,
      'rule_failed', v_rule_failed
    );
  end if;

  insert into public.leadership_assignments (
    id,
    organization_id,
    member_id,
    governance_node_id,
    leadership_role_definition_id,
    assignment_status,
    effective_from,
    assignment_basis,
    metadata,
    created_by
  ) values (
    gen_random_uuid(),
    p_organization_id,
    p_member_id,
    p_node_id,
    v_role_def.id,
    'active',
    coalesce(p_effective_from, current_date),
    'appointment',
    v_metadata,
    p_actor_profile_id
  ) returning id into v_new_assignment_id;

  if v_couple_partner_id is not null then
    insert into public.leadership_assignments (
      id,
      organization_id,
      member_id,
      governance_node_id,
      leadership_role_definition_id,
      assignment_status,
      effective_from,
      assignment_basis,
      metadata,
      created_by
    ) values (
      gen_random_uuid(),
      p_organization_id,
      v_couple_partner_id,
      p_node_id,
      v_role_def.id,
      'active',
      coalesce(p_effective_from, current_date),
      'appointment',
      jsonb_build_object(
        'role_code', v_role_code,
        'source', p_source,
        'partner_of_member_id', p_member_id,
        'primary_assignment_id', v_new_assignment_id
      ),
      p_actor_profile_id
    ) returning id into v_partner_assignment_id;

    update public.leadership_assignments
    set metadata = metadata || jsonb_build_object('partner_assignment_id', v_partner_assignment_id)
    where id = v_new_assignment_id;
  end if;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'leadership.assigned',
    p_event_category   => 'governance',
    p_actor_profile_id => p_actor_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => v_new_assignment_id,
    p_action           => 'appoint',
    p_outcome          => 'success',
    p_access_reason    => v_exception_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'role_code', v_role_code,
      'governance_node_id', p_node_id,
      'member_id', p_member_id,
      'couple_partner_id', v_couple_partner_id,
      'is_exception', v_is_exception,
      'exception_reason', v_exception_reason
    )
  );

  return jsonb_build_object(
    'status', 'success',
    'assignment_id', v_new_assignment_id,
    'partner_assignment_id', v_partner_assignment_id,
    'member_id', p_member_id,
    'couple_partner_id', v_couple_partner_id,
    'is_exception', v_is_exception
  );
end;
$function$;

--------------------------------------------------------------------------------
-- B3. REUSABLE SUB-AREA SECTION SETUP
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.create_sub_area_sections_internal(
  p_organization_id uuid,
  p_sub_area_node_id uuid,
  p_actor_profile_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $$
DECLARE
  v_sub_area_id uuid;
  v_sub_area_code text;
  v_sub_area_type text;
  v_parent_is_area integer;
  v_section_type_id uuid;
  v_created text[] := array[]::text[];
  v_already_present text[] := array[]::text[];
  v_existing_sec_code text;
  v_new_sec_code text;
  v_new_sec_name text;
  v_new_sec_id uuid;
  r_spec record;
BEGIN
  -- Sub-area validation: active area_state node whose active primary parent is area_state
  SELECT gn.id, gn.code, gnt.code AS node_type_code
  INTO v_sub_area_id, v_sub_area_code, v_sub_area_type
  FROM public.governance_nodes gn
  JOIN public.governance_node_types gnt ON gnt.id = gn.governance_node_type_id
  WHERE gn.id = p_sub_area_node_id
    AND gn.organization_id = p_organization_id
    AND gn.lifecycle_status = 'active';

  IF NOT FOUND OR v_sub_area_type <> 'area_state' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'Choose a sub-area.';
  END IF;

  SELECT count(*) INTO v_parent_is_area
  FROM public.governance_node_relationships r
  JOIN public.governance_nodes p ON p.id = r.parent_node_id
  JOIN public.governance_node_types pt ON pt.id = p.governance_node_type_id
  WHERE r.organization_id = p_organization_id
    AND r.child_node_id = p_sub_area_node_id
    AND r.relationship_type = 'primary_parent'
    AND r.relationship_status = 'active'
    AND r.is_primary = true
    AND (r.effective_to IS NULL OR r.effective_to >= current_date)
    AND pt.code = 'area_state'
    AND p.lifecycle_status = 'active';

  IF v_parent_is_area = 0 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'Choose a sub-area.';
  END IF;

  SELECT id INTO STRICT v_section_type_id
  FROM public.governance_node_types
  WHERE organization_id = p_organization_id
    AND code = 'section';

  FOR r_spec IN
    SELECT * FROM (VALUES
      ('couples',   'Couples',   true,  true),
      ('handmaids', 'Handmaids', false, true),
      ('servants',  'Servants',  false, true),
      ('singles',   'Singles',   false, true),
      ('campus',    'Campus',    false, true),
      ('youth',     'Youth',     false, true),
      ('kids',      'Kids',      false, true)
    ) AS t(kind, name, supports_couple, supports_individual)
  LOOP
    v_existing_sec_code := NULL;

    SELECT gn.code INTO v_existing_sec_code
    FROM public.governance_node_relationships r
    JOIN public.governance_nodes gn ON gn.id = r.child_node_id
    WHERE r.organization_id = p_organization_id
      AND r.parent_node_id = p_sub_area_node_id
      AND r.relationship_type = 'primary_parent'
      AND r.relationship_status = 'active'
      AND r.is_primary = true
      AND (r.effective_to IS NULL OR r.effective_to >= current_date)
      AND private.section_kind(gn.id) = r_spec.kind
    LIMIT 1;

    IF v_existing_sec_code IS NOT NULL THEN
      v_already_present := array_append(v_already_present, v_existing_sec_code);
    ELSE
      v_new_sec_code := v_sub_area_code || '_sec_' || r_spec.kind;
      v_new_sec_name := r_spec.name;

      INSERT INTO public.governance_nodes (
        organization_id,
        governance_node_type_id,
        code,
        name,
        lifecycle_status,
        effective_from,
        created_at,
        updated_at
      ) VALUES (
        p_organization_id,
        v_section_type_id,
        v_new_sec_code,
        v_new_sec_name,
        'active',
        current_date,
        clock_timestamp(),
        clock_timestamp()
      )
      ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
      DO UPDATE SET
        name = EXCLUDED.name,
        lifecycle_status = 'active',
        updated_at = clock_timestamp()
      RETURNING id INTO v_new_sec_id;

      IF v_new_sec_id IS NULL THEN
        SELECT id INTO STRICT v_new_sec_id
        FROM public.governance_nodes
        WHERE organization_id = p_organization_id AND code = v_new_sec_code;
      END IF;

      INSERT INTO public.sections (
        id,
        organization_id,
        section_category,
        supports_couple_membership,
        supports_individual_membership,
        created_at,
        updated_at
      ) VALUES (
        v_new_sec_id,
        p_organization_id,
        r_spec.kind,
        r_spec.supports_couple,
        r_spec.supports_individual,
        clock_timestamp(),
        clock_timestamp()
      )
      ON CONFLICT (id) DO UPDATE SET
        section_category = EXCLUDED.section_category,
        supports_couple_membership = EXCLUDED.supports_couple_membership,
        supports_individual_membership = EXCLUDED.supports_individual_membership,
        updated_at = clock_timestamp();

      INSERT INTO public.governance_node_relationships (
        organization_id,
        parent_node_id,
        child_node_id,
        relationship_type,
        relationship_status,
        is_primary,
        effective_from,
        created_at,
        updated_at
      ) VALUES (
        p_organization_id,
        p_sub_area_node_id,
        v_new_sec_id,
        'primary_parent',
        'active',
        true,
        current_date,
        clock_timestamp(),
        clock_timestamp()
      )
      ON CONFLICT (organization_id, child_node_id)
        WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
      DO NOTHING;

      v_created := array_append(v_created, v_new_sec_code);
    END IF;
  END LOOP;

  IF coalesce(cardinality(v_created), 0) > 0 THEN
    PERFORM private.write_audit_event(
      p_organization_id  => p_organization_id,
      p_event_code       => 'governance.sub_area_sections_created',
      p_event_category   => 'governance',
      p_actor_profile_id => p_actor_profile_id,
      p_entity_type      => 'governance_node',
      p_entity_id        => p_sub_area_node_id,
      p_action           => 'create',
      p_outcome          => 'success',
      p_metadata         => jsonb_build_object(
        'sub_area_code', v_sub_area_code,
        'created_codes', to_jsonb(v_created)
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'sub_area_code', v_sub_area_code,
    'created', to_jsonb(v_created),
    'already_present', to_jsonb(v_already_present)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_sub_area_sections(
  p_organization_id uuid,
  p_sub_area_node_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
DECLARE
  v_actor_profile_id uuid;
BEGIN
  v_actor_profile_id := private.current_profile_id();
  IF v_actor_profile_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '28000', message = 'Authentication required: active profile context not found.';
  END IF;

  IF NOT private.has_organization_access(p_organization_id) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  END IF;

  IF NOT private.has_permission('governance.structure.manage', p_organization_id) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'Access denied: missing required permission governance.structure.manage.';
  END IF;

  RETURN private.create_sub_area_sections_internal(p_organization_id, p_sub_area_node_id, v_actor_profile_id);
END;
$$;

REVOKE ALL ON FUNCTION private.create_sub_area_sections_internal(uuid, uuid, uuid) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_sub_area_sections(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.create_sub_area_sections(uuid, uuid) TO authenticated;

--------------------------------------------------------------------------------
-- B4. CREATE FMC NEW YORK SECTIONS & GUARDS
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
  v_fmc_ny_id uuid;
  v_mfc_ny_id uuid;
  v_fmc_sections_count integer;
  v_mfc_sections_count integer;
BEGIN
  SELECT id INTO STRICT v_fmc_ny_id
  FROM public.governance_nodes
  WHERE organization_id = v_org_id AND code = 'fmc_ny';

  SELECT id INTO STRICT v_mfc_ny_id
  FROM public.governance_nodes
  WHERE organization_id = v_org_id AND code = 'mfc_ny';

  -- Create sections for fmc_ny
  PERFORM private.create_sub_area_sections_internal(v_org_id, v_fmc_ny_id, NULL);

  -- Guard: exactly 7 active sections under fmc_ny afterwards
  SELECT count(*) INTO v_fmc_sections_count
  FROM public.governance_node_relationships r
  JOIN public.governance_nodes gn ON gn.id = r.child_node_id
  JOIN public.governance_node_types gnt ON gnt.id = gn.governance_node_type_id
  WHERE r.organization_id = v_org_id
    AND r.parent_node_id = v_fmc_ny_id
    AND r.relationship_type = 'primary_parent'
    AND r.relationship_status = 'active'
    AND r.is_primary = true
    AND (r.effective_to IS NULL OR r.effective_to >= current_date)
    AND gnt.code = 'section';

  IF v_fmc_sections_count <> 7 THEN
    RAISE EXCEPTION 'Guard failed: expected 7 active sections under fmc_ny, got %', v_fmc_sections_count;
  END IF;

  -- Guard: the 7 sec_* under mfc_ny unchanged
  SELECT count(*) INTO v_mfc_sections_count
  FROM public.governance_node_relationships r
  JOIN public.governance_nodes gn ON gn.id = r.child_node_id
  JOIN public.governance_node_types gnt ON gnt.id = gn.governance_node_type_id
  WHERE r.organization_id = v_org_id
    AND r.parent_node_id = v_mfc_ny_id
    AND r.relationship_type = 'primary_parent'
    AND r.relationship_status = 'active'
    AND r.is_primary = true
    AND (r.effective_to IS NULL OR r.effective_to >= current_date)
    AND gnt.code = 'section'
    AND gn.code ILIKE 'sec_%';

  IF v_mfc_sections_count <> 7 THEN
    RAISE EXCEPTION 'Guard failed: expected 7 sec_* sections under mfc_ny, got %', v_mfc_sections_count;
  END IF;

  RAISE NOTICE 'Pass 6.1A FMC sections created and guards passed.';
END $$;

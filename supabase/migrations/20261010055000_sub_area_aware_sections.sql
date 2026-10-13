-- Pass 6.1B (backend): sub-area-aware sections and placement.
-- Built from the previous committed bodies, with only the marked additions:
--   public.change_member_section               <- 20261010053000 (+ 6b sub-area consistency check)
--   public.change_member_governance_assignment <- 20261010048000 (+ sub-area consistency check)
--   public.get_sections_overview               <- 20261010046000 (+ 'sub_areas' key; 'sections' and 'fmc' unchanged)
--   public.get_member_section                  <- 20261010043000 (+ section_node_id, section_kind, sub_area_* keys)
-- New: private.node_sub_area, public.get_sub_area_placement_targets, public.move_member_to_sub_area.

-- A. Helper: the sub-area a node belongs to (itself or nearest area_state ancestor whose parent is also an area_state).
--    Returns null for the joint New York Area and for nodes outside any sub-area.
create or replace function private.node_sub_area(p_node_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with recursive up(node_id, depth) as (
    select p_node_id, 0
    union all
    select r.parent_node_id, up.depth + 1
    from up
    join public.governance_node_relationships r
      on r.child_node_id = up.node_id
     and r.relationship_type = 'primary_parent'
     and r.is_primary = true
     and r.relationship_status = 'active'
     and r.effective_to is null
    where up.depth < 20
  )
  select up.node_id
  from up
  join public.governance_nodes n on n.id = up.node_id
  join public.governance_node_types t on t.id = n.governance_node_type_id and t.code = 'area_state'
  where exists (
    select 1
    from public.governance_node_relationships r2
    join public.governance_nodes pn on pn.id = r2.parent_node_id
    join public.governance_node_types pt on pt.id = pn.governance_node_type_id and pt.code = 'area_state'
    where r2.child_node_id = up.node_id
      and r2.relationship_type = 'primary_parent'
      and r2.is_primary = true
      and r2.relationship_status = 'active'
      and r2.effective_to is null
  )
  order by up.depth
  limit 1;
$$;

revoke all on function private.node_sub_area(uuid) from public, anon, authenticated;

-- B. change_member_section
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
  v_target_sub_area uuid;
  v_member_sub_area uuid;
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

  -- 6b. Sub-area consistency (Pass 6.1B): the section must be in the same sub-area as the member's placement.
  --     Skipped only inside public.move_member_to_sub_area, which changes both together.
  if coalesce(current_setting('missionos.sub_area_move', true), '') <> 'on' then
    v_target_sub_area := private.node_sub_area(v_target_node.id);
    select private.node_sub_area(mga.governance_node_id) into v_member_sub_area
    from public.member_governance_assignments mga
    where mga.organization_id = p_organization_id
      and mga.member_id = p_member_id
      and mga.is_primary = true
      and mga.assignment_status = 'active'
      and mga.effective_to is null
    limit 1;

    if v_target_sub_area is not null and v_member_sub_area is not null and v_target_sub_area <> v_member_sub_area then
      raise exception using errcode = '22023',
        message = format('This section is in %s, but the member is placed in %s. Use "Move to sub-area" instead.',
          (select name from public.governance_nodes where id = v_target_sub_area),
          (select name from public.governance_nodes where id = v_member_sub_area));
    end if;
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

-- C. change_member_governance_assignment
CREATE OR REPLACE FUNCTION public.change_member_governance_assignment(p_organization_id uuid, p_member_id uuid, p_target_governance_node_id uuid DEFAULT NULL::uuid, p_effective_from date DEFAULT CURRENT_DATE, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
    v_actor_profile_id uuid;
    v_cur_assignment public.member_governance_assignments%rowtype;
    v_target_node_code text;
    v_new_assignment_id uuid := null;
    v_target_sub_area uuid;
    v_member_sub_area uuid;
begin
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    if not private.has_permission('members.placements.manage', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.placements.manage.';
    end if;

    if not private.can_access_member('members.placements.manage', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: member is outside caller governance scope.';
    end if;

    -- Validate target node if provided
    if p_target_governance_node_id is not null then
        select nt.code into v_target_node_code
        from public.governance_nodes n
        join public.governance_node_types nt on nt.id = n.governance_node_type_id
        where n.id = p_target_governance_node_id
          and n.organization_id = p_organization_id
          and n.lifecycle_status = 'active';

        if not found then
            raise exception using errcode = 'P0002', message = 'Target governance node not found or not active.';
        end if;

        if v_target_node_code not in ('area_state', 'chapter', 'unit') then
            raise exception using errcode = '22023', message = 'Validation error: governance placement must target the area, a chapter or a unit.';
        end if;

        if not private.profile_has_governance_scope(auth.uid(), p_organization_id, p_target_governance_node_id, now()) then
            raise exception using errcode = '42501', message = 'Access denied: target governance node is outside caller scope.';
        end if;
    end if;

    -- Sub-area consistency (Pass 6.1B): the placement must be in the same sub-area as the member's section.
    -- Skipped only inside public.move_member_to_sub_area, which changes both together.
    if p_target_governance_node_id is not null
       and coalesce(current_setting('missionos.sub_area_move', true), '') <> 'on' then
        v_target_sub_area := private.node_sub_area(p_target_governance_node_id);
        select private.node_sub_area(sm.section_node_id) into v_member_sub_area
        from public.section_memberships sm
        where sm.organization_id = p_organization_id
          and sm.member_id = p_member_id
          and sm.membership_status = 'active'
          and sm.is_primary = true
          and (sm.effective_to is null or sm.effective_to >= current_date)
        limit 1;

        if v_target_sub_area is not null and v_member_sub_area is not null and v_target_sub_area <> v_member_sub_area then
            raise exception using errcode = '22023',
                message = format('This placement is in %s, but the member''s section is in %s. Use "Move to sub-area" instead.',
                    (select name from public.governance_nodes where id = v_target_sub_area),
                    (select name from public.governance_nodes where id = v_member_sub_area));
        end if;
    end if;

    -- Find current active primary assignment
    select * into v_cur_assignment
    from public.member_governance_assignments
    where organization_id = p_organization_id
      and member_id = p_member_id
      and is_primary = true
      and assignment_status = 'active'
      and effective_to is null;

    if found then
        -- Validate date ordering
        if p_effective_from < v_cur_assignment.effective_from then
            raise exception using errcode = '22023',
                message = format('Effective date (%s) cannot precede current placement start date (%s).', p_effective_from, v_cur_assignment.effective_from);
        end if;

        -- Close current assignment
        update public.member_governance_assignments
        set assignment_status = 'ended',
            effective_to = case when p_effective_from = v_cur_assignment.effective_from then p_effective_from else p_effective_from - 1 end,
            ending_reason = coalesce(p_reason, 'Transferred or removed by administration'),
            updated_at = now(),
            updated_by_profile_id = v_actor_profile_id
        where id = v_cur_assignment.id;
    end if;

    -- If target node is supplied, insert new active assignment
    if p_target_governance_node_id is not null then
        v_new_assignment_id := gen_random_uuid();
        insert into public.member_governance_assignments (
            id, organization_id, member_id, governance_node_id,
            assignment_type, assignment_status, effective_from,
            is_primary, assignment_basis, created_by_profile_id, updated_by_profile_id
        ) values (
            v_new_assignment_id, p_organization_id, p_member_id, p_target_governance_node_id,
            'primary', 'active', p_effective_from,
            true, 'administrative', v_actor_profile_id, v_actor_profile_id
        );
        -- The table trigger trg_member_governance_assignments__sync_cache sets members.primary_governance_node_id!
    end if;

    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.placement.changed',
        p_event_category   => 'governance',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => p_member_id,
        p_action           => 'transfer',
        p_outcome          => 'success',
        p_metadata         => jsonb_build_object(
            'previous_assignment_id', v_cur_assignment.id,
            'previous_governance_node_id', v_cur_assignment.governance_node_id,
            'target_governance_node_id', p_target_governance_node_id,
            'effective_from', p_effective_from,
            'reason', nullif(trim(p_reason), '')
        )
    );

    return jsonb_build_object(
        'status', 'success',
        'member_id', p_member_id,
        'previous_node_id', v_cur_assignment.governance_node_id,
        'new_node_id', p_target_governance_node_id,
        'assignment_id', v_new_assignment_id
    );
end;
$function$;

-- D. get_sections_overview
CREATE OR REPLACE FUNCTION public.get_sections_overview(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_actor_profile_id uuid;
  v_has_appoint boolean;
  v_sections jsonb;
  v_fmc jsonb;
  v_sub_areas jsonb;
begin
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  if not private.has_permission('members.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission members.records.view.';
  end if;

  v_has_appoint := private.has_permission('leadership.servant_leaders.appoint', p_organization_id);

  -- Sections array in canonical order: Couples, Handmaids, Servants, Singles, Campus, Youth, Kids
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'node_id', s.id,
        'code', s.code,
        'name', s.name,
        'active_member_count', s.active_member_count,
        'coordinator', s.coordinator
      )
    ),
    '[]'::jsonb
  )
  into v_sections
  from (
    select 
      gn.id,
      gn.code,
      gn.name,
      (
        select count(sm.id)
        from public.section_memberships sm
        where sm.section_node_id = gn.id
          and sm.organization_id = gn.organization_id
          and sm.membership_status = 'active'
          and sm.is_primary = true
          and (sm.effective_to is null or sm.effective_to >= current_date)
      ) as active_member_count,
      (
        select case
          when v_has_appoint then
            jsonb_build_object(
              'member_id', m.id,
              'member_number', m.member_number,
              'display_name', m.display_name,
              'partner', case 
                when la.metadata->>'couple_partner_member_id' is not null then (
                  select jsonb_build_object('member_id', mp.id, 'display_name', mp.display_name)
                  from public.members mp
                  where mp.id = (la.metadata->>'couple_partner_member_id')::uuid
                )
                else null
              end,
              'is_exception', coalesce((la.metadata->>'eligibility_exception')::boolean, false),
              'exception_reason', la.metadata->>'exception_reason'
            )
          else
            jsonb_build_object(
              'member_id', m.id,
              'member_number', m.member_number,
              'display_name', m.display_name,
              'partner', case 
                when la.metadata->>'couple_partner_member_id' is not null then (
                  select jsonb_build_object('member_id', mp.id, 'display_name', mp.display_name)
                  from public.members mp
                  where mp.id = (la.metadata->>'couple_partner_member_id')::uuid
                )
                else null
              end
            )
        end
        from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        join public.members m on m.id = la.member_id
        where lrd.code = 'area_section_coordinator'
          and la.governance_node_id = gn.id
          and la.organization_id = gn.organization_id
          and la.assignment_status = 'active'
        limit 1
      ) as coordinator
    from public.governance_nodes gn
    where gn.organization_id = p_organization_id
      and gn.code ilike 'sec_%'
      and gn.lifecycle_status = 'active'
    order by array_position(array['sec_couples', 'sec_handmaids', 'sec_servants', 'sec_singles', 'sec_campus', 'sec_youth', 'sec_kids'], gn.code)
  ) s;

  -- FMC entry
  select jsonb_build_object(
    'code', 'fmc',
    'name', 'FMC',
    'tagged_member_count', (
      select count(distinct m.id)
      from public.members m
      join public.entity_tags et on et.entity_id = m.id and et.entity_type = 'member'
      join public.tags t on t.id = et.tag_id
      where t.code = 'fmc'
        and m.organization_id = p_organization_id
        and m.record_status = 'active'
    ),
    'coordinator', (
      select case
        when v_has_appoint then
          jsonb_build_object(
            'member_id', m.id,
            'member_number', m.member_number,
            'display_name', m.display_name,
            'partner', case 
              when la.metadata->>'couple_partner_member_id' is not null then (
                select jsonb_build_object('member_id', mp.id, 'display_name', mp.display_name)
                from public.members mp
                where mp.id = (la.metadata->>'couple_partner_member_id')::uuid
              )
              else null
            end,
            'is_exception', coalesce((la.metadata->>'eligibility_exception')::boolean, false),
            'exception_reason', la.metadata->>'exception_reason'
          )
        else
          jsonb_build_object(
            'member_id', m.id,
            'member_number', m.member_number,
            'display_name', m.display_name,
            'partner', case 
              when la.metadata->>'couple_partner_member_id' is not null then (
                select jsonb_build_object('member_id', mp.id, 'display_name', mp.display_name)
                from public.members mp
                where mp.id = (la.metadata->>'couple_partner_member_id')::uuid
              )
              else null
            end
          )
      end
      from public.leadership_assignments la
      join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
      join public.members m on m.id = la.member_id
      where lrd.code = 'fmc_coordinator'
        and la.organization_id = p_organization_id
        and la.assignment_status = 'active'
      limit 1
    )
  )
  into v_fmc;

  -- Pass 6.1B: sections grouped by sub-area (MFC New York first). 'sections' above is kept unchanged for older app builds.
  select coalesce(jsonb_agg(sa.obj order by sa.sort_key, sa.name), '[]'::jsonb)
  into v_sub_areas
  from (
    select
      san.name,
      case when san.code = 'mfc_ny' then 0 else 1 end as sort_key,
      jsonb_build_object(
        'node_id', san.id,
        'code', san.code,
        'name', san.name,
        'sections', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'node_id', s.id,
              'code', s.code,
              'name', s.name,
              'kind', s.kind,
              'active_member_count', s.active_member_count,
              'coordinator', s.coordinator
            )
            order by array_position(array['couples','handmaids','servants','singles','campus','youth','kids'], s.kind)
          )
          from (
            select
              gn.id,
              gn.code,
              gn.name,
              private.section_kind(gn.id) as kind,
              (
                select count(sm.id)
                from public.section_memberships sm
                where sm.section_node_id = gn.id
                  and sm.organization_id = gn.organization_id
                  and sm.membership_status = 'active'
                  and sm.is_primary = true
                  and (sm.effective_to is null or sm.effective_to >= current_date)
              ) as active_member_count,
              (
        select case
          when v_has_appoint then
            jsonb_build_object(
              'member_id', m.id,
              'member_number', m.member_number,
              'display_name', m.display_name,
              'partner', case 
                when la.metadata->>'couple_partner_member_id' is not null then (
                  select jsonb_build_object('member_id', mp.id, 'display_name', mp.display_name)
                  from public.members mp
                  where mp.id = (la.metadata->>'couple_partner_member_id')::uuid
                )
                else null
              end,
              'is_exception', coalesce((la.metadata->>'eligibility_exception')::boolean, false),
              'exception_reason', la.metadata->>'exception_reason'
            )
          else
            jsonb_build_object(
              'member_id', m.id,
              'member_number', m.member_number,
              'display_name', m.display_name,
              'partner', case 
                when la.metadata->>'couple_partner_member_id' is not null then (
                  select jsonb_build_object('member_id', mp.id, 'display_name', mp.display_name)
                  from public.members mp
                  where mp.id = (la.metadata->>'couple_partner_member_id')::uuid
                )
                else null
              end
            )
        end
        from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        join public.members m on m.id = la.member_id
        where lrd.code = 'area_section_coordinator'
          and la.governance_node_id = gn.id
          and la.organization_id = gn.organization_id
          and la.assignment_status = 'active'
        limit 1
      ) as coordinator
            from public.governance_node_relationships r
            join public.governance_nodes gn on gn.id = r.child_node_id
            join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id and gnt.code = 'section'
            where r.organization_id = p_organization_id
              and r.parent_node_id = san.id
              and r.relationship_type = 'primary_parent'
              and r.is_primary = true
              and r.relationship_status = 'active'
              and r.effective_to is null
              and gn.lifecycle_status = 'active'
              and private.section_kind(gn.id) is not null
          ) s
        ), '[]'::jsonb)
      ) as obj
    from public.governance_nodes san
    join public.governance_node_types sant on sant.id = san.governance_node_type_id and sant.code = 'area_state'
    where san.organization_id = p_organization_id
      and san.lifecycle_status = 'active'
      and private.node_sub_area(san.id) = san.id
  ) sa;

  return jsonb_build_object(
    'sections', v_sections,
    'fmc', v_fmc,
    'sub_areas', v_sub_areas
  );
end;
$function$;

-- E. get_member_section
create or replace function public.get_member_section(
  p_organization_id uuid,
  p_member_id uuid
) returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor_profile_id uuid;
  v_res jsonb;
begin
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  if not private.has_permission('members.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission members.records.view.';
  end if;

  if not private.can_access_member('members.records.view', p_organization_id, p_member_id) then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  select jsonb_build_object(
    'section_code', gn.code,
    'section_name', gn.name,
    'section_node_id', gn.id,
    'section_kind', private.section_kind(gn.id),
    'sub_area_node_id', private.node_sub_area(gn.id),
    'sub_area_code', (select sa.code from public.governance_nodes sa where sa.id = private.node_sub_area(gn.id)),
    'sub_area_name', (select sa.name from public.governance_nodes sa where sa.id = private.node_sub_area(gn.id)),
    'effective_from', sm.effective_from,
    'paired_member', case
      when sm.paired_member_id is not null then (
        select jsonb_build_object('id', mp.id, 'display_name', mp.display_name)
        from public.members mp
        where mp.id = sm.paired_member_id
      )
      else null
    end
  )
  into v_res
  from public.section_memberships sm
  join public.governance_nodes gn on gn.id = sm.section_node_id and gn.organization_id = sm.organization_id
  where sm.organization_id = p_organization_id
    and sm.member_id = p_member_id
    and sm.membership_status = 'active'
    and sm.is_primary = true
    and (sm.effective_to is null or sm.effective_to >= current_date)
  order by sm.effective_from desc
  limit 1;

  return v_res;
end;
$$;

-- F. Placement targets inside one sub-area (the sub-area itself, its chapters and units), for the Move to sub-area screen.
create or replace function public.get_sub_area_placement_targets(
  p_organization_id uuid,
  p_sub_area_node_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor_profile_id uuid;
  v_res jsonb;
begin
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  if not private.has_permission('governance.structure.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission governance.structure.view.';
  end if;

  if p_sub_area_node_id is null or private.node_sub_area(p_sub_area_node_id) is distinct from p_sub_area_node_id then
    raise exception using errcode = '22023', message = 'Choose a sub-area.';
  end if;

  with recursive down(node_id, parent_id, depth) as (
    select p_sub_area_node_id, null::uuid, 0
    union all
    select r.child_node_id, r.parent_node_id, down.depth + 1
    from down
    join public.governance_node_relationships r
      on r.parent_node_id = down.node_id
     and r.organization_id = p_organization_id
     and r.relationship_type = 'primary_parent'
     and r.is_primary = true
     and r.relationship_status = 'active'
     and r.effective_to is null
    where down.depth < 10
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'node_id', n.id,
             'code', n.code,
             'name', n.name,
             'node_type', t.code,
             'parent_name', pn.name
           )
           order by t.hierarchy_rank, coalesce(pn.name, ''), n.name
         ), '[]'::jsonb)
  into v_res
  from down d
  join public.governance_nodes n on n.id = d.node_id and n.organization_id = p_organization_id and n.lifecycle_status = 'active'
  join public.governance_node_types t on t.id = n.governance_node_type_id
  left join public.governance_nodes pn on pn.id = d.parent_id
  where t.code in ('area_state', 'chapter', 'unit')
    and private.profile_has_governance_scope(v_actor_profile_id, p_organization_id, n.id, now());

  return v_res;
end;
$$;

revoke all on function public.get_sub_area_placement_targets(uuid, uuid) from public, anon;
grant execute on function public.get_sub_area_placement_targets(uuid, uuid) to authenticated;

-- G. Move a member to another sub-area: section and placement change together in one step.
create or replace function public.move_member_to_sub_area(
  p_organization_id uuid,
  p_member_id uuid,
  p_section_code text,
  p_target_governance_node_id uuid,
  p_effective_from date default current_date,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor_profile_id uuid;
  v_member public.members%rowtype;
  v_section public.governance_nodes%rowtype;
  v_sub_area uuid;
  v_target_type text;
  v_cur_section_id uuid;
  v_cur_section_code text;
  v_cur_node_id uuid;
  v_section_res jsonb := null;
  v_placement_res jsonb := null;
  v_effective_from date := coalesce(p_effective_from, current_date);
begin
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  if not private.has_permission('members.placements.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission members.placements.manage.';
  end if;

  if p_reason is null or length(btrim(p_reason)) < 5 then
    raise exception using errcode = '22023', message = 'A reason of at least 5 characters is required.';
  end if;

  if v_effective_from > current_date then
    raise exception using errcode = '22023', message = 'Effective date cannot be in the future.';
  end if;

  select * into v_member
  from public.members
  where id = p_member_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;
  if v_member.record_status <> 'active' or coalesce(v_member.is_deceased, false) then
    raise exception using errcode = '22023', message = 'Member must be active to move.';
  end if;

  -- Target section
  select gn.* into v_section
  from public.governance_nodes gn
  join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id and gnt.code = 'section'
  where gn.organization_id = p_organization_id
    and gn.code = p_section_code
    and gn.lifecycle_status = 'active';
  if not found or private.section_kind(v_section.id) is null then
    raise exception using errcode = '22023', message = 'Choose a valid section.';
  end if;

  v_sub_area := private.node_sub_area(v_section.id);
  if v_sub_area is null then
    raise exception using errcode = '22023', message = 'This section is not in a sub-area.';
  end if;

  -- Target placement must be the sub-area itself, or a chapter or unit inside it
  if p_target_governance_node_id is null then
    raise exception using errcode = '22023', message = 'Choose where to place the member.';
  end if;

  select gnt.code into v_target_type
  from public.governance_nodes gn
  join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id
  where gn.id = p_target_governance_node_id
    and gn.organization_id = p_organization_id
    and gn.lifecycle_status = 'active';
  if not found or v_target_type not in ('area_state', 'chapter', 'unit') then
    raise exception using errcode = '22023', message = 'Validation error: governance placement must target the area, a chapter or a unit.';
  end if;

  if private.node_sub_area(p_target_governance_node_id) is distinct from v_sub_area then
    raise exception using errcode = '22023', message = 'The placement must be in the same sub-area as the section.';
  end if;

  -- Household guard: households belong to one sub-area
  if exists (
    select 1 from public.household_memberships hm
    where hm.organization_id = p_organization_id
      and hm.member_id = p_member_id
      and hm.is_primary = true
      and hm.membership_status in ('active', 'temporary')
      and (hm.effective_to is null or hm.effective_to >= current_date)
  ) then
    raise exception using errcode = '22023', message = 'Remove this member from their household first.';
  end if;

  -- Current section and placement
  select sm.section_node_id, gn.code into v_cur_section_id, v_cur_section_code
  from public.section_memberships sm
  join public.governance_nodes gn on gn.id = sm.section_node_id
  where sm.organization_id = p_organization_id
    and sm.member_id = p_member_id
    and sm.membership_status = 'active'
    and sm.is_primary = true
    and (sm.effective_to is null or sm.effective_to >= current_date)
  limit 1;

  select mga.governance_node_id into v_cur_node_id
  from public.member_governance_assignments mga
  where mga.organization_id = p_organization_id
    and mga.member_id = p_member_id
    and mga.is_primary = true
    and mga.assignment_status = 'active'
    and mga.effective_to is null
  limit 1;

  if v_cur_section_id is not distinct from v_section.id and v_cur_node_id is not distinct from p_target_governance_node_id then
    raise exception using errcode = '22023', message = 'Member is already in this section and placement.';
  end if;

  perform set_config('missionos.sub_area_move', 'on', true);

  if v_cur_node_id is distinct from p_target_governance_node_id then
    v_placement_res := public.change_member_governance_assignment(
      p_organization_id, p_member_id, p_target_governance_node_id, v_effective_from, btrim(p_reason)
    );
  end if;

  if v_cur_section_id is distinct from v_section.id then
    v_section_res := public.change_member_section(
      p_organization_id, p_member_id, p_section_code, v_effective_from, btrim(p_reason)
    );
  end if;

  perform set_config('missionos.sub_area_move', 'off', true);

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.sub_area.moved',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'member',
    p_entity_id        => p_member_id,
    p_action           => 'move_sub_area',
    p_outcome          => 'success',
    p_metadata         => jsonb_build_object(
      'sub_area_node_id', v_sub_area,
      'previous_section_code', v_cur_section_code,
      'section_code', p_section_code,
      'previous_governance_node_id', v_cur_node_id,
      'target_governance_node_id', p_target_governance_node_id,
      'effective_from', v_effective_from,
      'reason', btrim(p_reason)
    )
  );

  return jsonb_build_object(
    'status', 'success',
    'member_id', p_member_id,
    'sub_area_code', (select code from public.governance_nodes where id = v_sub_area),
    'previous_section_code', v_cur_section_code,
    'section_code', p_section_code,
    'previous_node_id', v_cur_node_id,
    'new_node_id', p_target_governance_node_id,
    'paired_member_id', v_section_res->>'paired_member_id'
  );
end;
$$;

revoke all on function public.move_member_to_sub_area(uuid, uuid, text, uuid, date, text) from public, anon;
grant execute on function public.move_member_to_sub_area(uuid, uuid, text, uuid, date, text) to authenticated;

-- H. Guards
do $$
declare
  v_org uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
  v_bad integer;
begin
  if private.node_sub_area((select id from public.governance_nodes where organization_id = v_org and code = 'ny')) is not null then
    raise exception 'Guard failed: ny must not be a sub-area';
  end if;
  if private.node_sub_area((select id from public.governance_nodes where organization_id = v_org and code = 'hm_nyc_bronx'))
     is distinct from (select id from public.governance_nodes where organization_id = v_org and code = 'mfc_ny') then
    raise exception 'Guard failed: hm_nyc_bronx must resolve to mfc_ny';
  end if;
  if private.node_sub_area((select id from public.governance_nodes where organization_id = v_org and code = 'fmc_hm_bronx'))
     is distinct from (select id from public.governance_nodes where organization_id = v_org and code = 'fmc_ny') then
    raise exception 'Guard failed: fmc_hm_bronx must resolve to fmc_ny';
  end if;

  -- No member may already be split across sub-areas
  select count(*) into v_bad
  from public.members m
  join public.section_memberships sm on sm.member_id = m.id and sm.membership_status = 'active' and sm.is_primary
       and (sm.effective_to is null or sm.effective_to >= current_date)
  join public.member_governance_assignments mga on mga.member_id = m.id and mga.is_primary and mga.assignment_status = 'active' and mga.effective_to is null
  where m.organization_id = v_org
    and private.node_sub_area(sm.section_node_id) is not null
    and private.node_sub_area(mga.governance_node_id) is not null
    and private.node_sub_area(sm.section_node_id) <> private.node_sub_area(mga.governance_node_id);
  if v_bad <> 0 then
    raise exception 'Guard failed: % members already have section and placement in different sub-areas', v_bad;
  end if;
end $$;

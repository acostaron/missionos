-- Migration 111: sections_read_and_change_api
-- Provides read APIs for sections overview and member section, and change section RPC.

begin;

-- =============================================================================
-- A. get_sections_overview
-- =============================================================================
create or replace function public.get_sections_overview(
  p_organization_id uuid
) returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor_profile_id uuid;
  v_has_appoint boolean;
  v_sections jsonb;
  v_fmc jsonb;
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

  return jsonb_build_object(
    'sections', v_sections,
    'fmc', v_fmc
  );
end;
$$;

revoke all on function public.get_sections_overview(uuid) from public, anon;
grant execute on function public.get_sections_overview(uuid) to authenticated;

-- =============================================================================
-- B. get_member_section
-- =============================================================================
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

revoke all on function public.get_member_section(uuid, uuid) from public, anon;
grant execute on function public.get_member_section(uuid, uuid) to authenticated;

-- =============================================================================
-- C. change_member_section
-- =============================================================================
create or replace function public.change_member_section(
  p_organization_id uuid,
  p_member_id uuid,
  p_section_code text,
  p_effective_from date default current_date,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
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

  if not (v_target_node.code ilike 'sec_%') then
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
  if v_cur_section_code = 'sec_couples' and v_target_node.code != 'sec_couples' then
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
  if v_target_node.code = 'sec_couples' then
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
      join public.governance_nodes gn on gn.id = sm.section_node_id
      where sm.organization_id = p_organization_id
        and sm.member_id = v_spouse_member_id
        and sm.membership_status = 'active'
        and sm.is_primary = true
        and gn.code = 'sec_couples'
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
$$;

revoke all on function public.change_member_section(uuid, uuid, text, date, text) from public, anon;
grant execute on function public.change_member_section(uuid, uuid, text, date, text) to authenticated;

commit;

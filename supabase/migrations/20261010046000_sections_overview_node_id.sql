-- Pass 4.8-2B: expose section node_id in get_sections_overview for the Place Members section filter. Additive only.

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

  return jsonb_build_object(
    'sections', v_sections,
    'fmc', v_fmc
  );
end;
$function$;

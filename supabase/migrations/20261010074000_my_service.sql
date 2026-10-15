-- =============================================================================
-- Migration: 20261010074000_my_service.sql
-- MissionOS Pass 8.5A (written by Claude, 2026-10-15)
-- "My Service" card on My Profile: where the signed-in member leads or serves.
--   1. Their own current appointments (any leadership role: servant leaders, coordinators, …).
--   2. Couples-section servant leadership shared with their verified spouse (Ron's ministry rule:
--      in the Couples section, household/unit/chapter/area servant leaders serve as husband and wife
--      together) — shown on the spouse's card too, marked "with <partner>".
-- Read-only, self-service only (members.self_service.view), returns only the caller's own service.
-- =============================================================================

-- Is the member in the Couples section? (same test as the placement and household-leader logic)
create or replace function private.member_in_couples_section(p_organization_id uuid, p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select exists (
           select 1
           from public.members m
           join public.governance_nodes sgn on sgn.id = m.primary_section_node_id
           where m.id = p_member_id
             and m.organization_id = p_organization_id
             and (sgn.code ilike '%couple%' or sgn.name ilike '%couple%'
                  or coalesce(sgn.metadata->>'is_couple_section', 'false')::boolean = true
                  or coalesce(sgn.metadata->>'section_category', '') = 'couples'))
      or exists (
           select 1
           from public.member_governance_assignments mga
           join public.governance_nodes sgn on sgn.id = mga.governance_node_id
           join public.governance_node_types gnt on gnt.id = sgn.governance_node_type_id and gnt.code = 'section'
           where mga.member_id = p_member_id
             and mga.organization_id = p_organization_id
             and mga.assignment_status = 'active'
             and mga.effective_from <= current_date
             and (mga.effective_to is null or mga.effective_to >= current_date)
             and (sgn.code ilike '%couple%' or sgn.name ilike '%couple%'
                  or coalesce(sgn.metadata->>'is_couple_section', 'false')::boolean = true
                  or coalesce(sgn.metadata->>'section_category', '') = 'couples'))
$$;
revoke all on function private.member_in_couples_section(uuid, uuid) from public, anon, authenticated;

create or replace function public.get_my_service(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
  v_spouse_id uuid;
  v_spouse_name text;
  v_couples boolean;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);

  -- current verified spouse
  select case when fr.from_member_id = v_member_id then fr.to_member_id else fr.from_member_id end, sm.display_name
    into v_spouse_id, v_spouse_name
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
  join public.members sm on sm.id = case when fr.from_member_id = v_member_id then fr.to_member_id else fr.from_member_id end
                        and sm.record_status = 'active' and not sm.is_deceased
  where fr.organization_id = p_organization_id
    and fr.relationship_status = 'active'
    and fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')
    and (fr.effective_from is null or fr.effective_from <= current_date)
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and v_member_id in (fr.from_member_id, fr.to_member_id)
  limit 1;

  v_couples := private.member_in_couples_section(p_organization_id, v_member_id);

  return coalesce((
    select jsonb_agg(x.j order by x.sort_rank, x.node_name)
    from (
      -- 1. my own appointments
      select
        case lrd.code when 'area_servant_leader' then 1 when 'chapter_servant_leader' then 2
                      when 'unit_servant_leader' then 3 when 'household_servant_leader' then 4 else 5 end as sort_rank,
        gn.name as node_name,
        jsonb_build_object(
          'role_code',      lrd.code,
          'role_name',      lrd.name,
          'node_id',        gn.id,
          'node_name',      gn.name,
          'node_type',      gnt.name,
          'effective_from', la.effective_from,
          'basis',          'appointed',
          'partner_name',   case when v_couples and v_spouse_id is not null
                                  and lrd.code in ('household_servant_leader', 'unit_servant_leader',
                                                   'chapter_servant_leader', 'area_servant_leader')
                                 then v_spouse_name end
        ) as j
      from public.leadership_assignments la
      join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
      join public.governance_nodes gn on gn.id = la.governance_node_id
      left join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id
      where la.organization_id = p_organization_id
        and la.member_id = v_member_id
        and la.assignment_status = 'active'
        and (la.effective_from is null or la.effective_from <= current_date)
        and (la.effective_to is null or la.effective_to >= current_date)

      union all

      -- 2. servant leadership I share with my verified spouse (Couples section)
      select
        case lrd.code when 'area_servant_leader' then 1 when 'chapter_servant_leader' then 2
                      when 'unit_servant_leader' then 3 else 4 end,
        gn.name,
        jsonb_build_object(
          'role_code',      lrd.code,
          'role_name',      lrd.name,
          'node_id',        gn.id,
          'node_name',      gn.name,
          'node_type',      gnt.name,
          'effective_from', la.effective_from,
          'basis',          'with_spouse',
          'partner_name',   v_spouse_name
        )
      from public.leadership_assignments la
      join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
      join public.governance_nodes gn on gn.id = la.governance_node_id
      left join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id
      where v_spouse_id is not null
        and la.organization_id = p_organization_id
        and la.member_id = v_spouse_id
        and la.assignment_status = 'active'
        and (la.effective_from is null or la.effective_from <= current_date)
        and (la.effective_to is null or la.effective_to >= current_date)
        and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
        and (v_couples or private.member_in_couples_section(p_organization_id, v_spouse_id))
        -- not already appointed to the same role on the same node myself
        and not exists (
          select 1 from public.leadership_assignments mine
          where mine.organization_id = p_organization_id
            and mine.member_id = v_member_id
            and mine.governance_node_id = la.governance_node_id
            and mine.leadership_role_definition_id = la.leadership_role_definition_id
            and mine.assignment_status = 'active')
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.get_my_service(uuid) from public, anon;
grant execute on function public.get_my_service(uuid) to authenticated;

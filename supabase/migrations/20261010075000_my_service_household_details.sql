-- =============================================================================
-- Migration: 20261010075000_my_service_household_details.sql
-- MissionOS Pass 8.5B (written by Claude, 2026-10-15)
-- "My Service" card: Ron asked for the same details as the "My Household" card. For servant
-- leadership, each item now also returns the household being led (household/unit/chapter/area
-- household: name, level, members, meeting schedule, parent) and the leader names
-- ("<husband> & <wife>" when served as a couple). Other roles (e.g. coordinators) return household = null.
-- Guard: refuses to run if the live get_my_service is not the one from 20261010074000.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_my_service';
  if v_md5 is distinct from 'd65d3765631264a66f7c1212cf379087' then
    raise exception 'STOP: live get_my_service differs from migration 20261010074000 (md5 %). Not replacing it.', v_md5;
  end if;
end;
$guard$;

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
  v_my_name text;
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

  select m.display_name into v_my_name from public.members m where m.id = v_member_id;

  return coalesce((
    select jsonb_agg(
             x.j
             || jsonb_build_object(
                  -- husband first when both are named
                  'leader_names', case when x.j->>'partner_name' is null then null
                                       when (select sex from public.members where id = v_member_id) = 'female'
                                         then (x.j->>'partner_name') || ' & ' || v_my_name
                                       else v_my_name || ' & ' || (x.j->>'partner_name') end,
                  'household', (
                    select jsonb_build_object(
                      'household_id',          h.id,
                      'household_name',        hgn.name,
                      'pastoral_level',        h.pastoral_level,
                      'meeting_frequency',     h.meeting_frequency,
                      'meeting_day_of_week',   h.meeting_day_of_week,
                      'meeting_start_time',    to_char(h.meeting_start_time, 'HH24:MI:SS'),
                      'meeting_timezone_name', h.meeting_timezone_name,
                      'location_type',         h.meeting_location_type,
                      'parent_node_name',      pgn.name,
                      'active_member_count',   (select count(*) from public.household_memberships hm
                                                 where hm.household_node_id = h.id
                                                   and hm.organization_id = p_organization_id
                                                   and hm.membership_status in ('active', 'temporary')
                                                   and hm.effective_from <= current_date
                                                   and (hm.effective_to is null or hm.effective_to >= current_date)))
                    from (
                      -- the household this servant leadership leads
                      select hh.* from public.households hh
                      where hh.organization_id = p_organization_id
                        and (
                          (x.j->>'role_code' = 'household_servant_leader' and hh.id = (x.j->>'node_id')::uuid)
                          or (x.j->>'role_code' in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
                              and hh.pastoral_level = replace(x.j->>'role_code', '_servant_leader', '')
                              and exists (select 1 from public.governance_node_relationships r
                                          where r.child_node_id = hh.id
                                            and r.parent_node_id = (x.j->>'node_id')::uuid
                                            and r.relationship_type = 'primary_parent'
                                            and r.relationship_status = 'active'
                                            and (r.effective_to is null or r.effective_to >= current_date)))
                        )
                      limit 1
                    ) h
                    join public.governance_nodes hgn on hgn.id = h.id and hgn.lifecycle_status = 'active'
                    left join public.governance_node_relationships pr
                      on pr.child_node_id = h.id and pr.relationship_type = 'primary_parent'
                     and pr.relationship_status = 'active'
                     and (pr.effective_to is null or pr.effective_to >= current_date)
                    left join public.governance_nodes pgn on pgn.id = pr.parent_node_id
                    limit 1)
                )
             order by x.sort_rank, x.node_name)
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

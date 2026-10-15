-- =============================================================================
-- Migration: 20261010069000_my_household_meetings_leaders.sql
-- MissionOS Pass 8.4B (written by Claude, 2026-10-14)
-- A household's servant leader is usually not on its roster (unit/chapter/area households are led
-- by the servant leader appointed on the PARENT node). Pass 8.4A only showed meetings of households
-- the member belongs to, so leaders did not see the meetings of the household they lead.
-- Now list_my_household_meetings also returns meetings of households the member currently leads:
--   member-level household  -> active 'household_servant_leader' on the household node
--   unit/chapter/area       -> active 'unit/chapter/area_servant_leader' on the household's primary parent node
-- and, for couple households, of households led by the member's spouse (couple leadership).
-- Adds 'my_role' ('member' | 'leader') to each row. Everything else is unchanged.
-- =============================================================================
create or replace function public.list_my_household_meetings(
  p_organization_id uuid,
  p_from date,
  p_to   date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    raise exception using errcode = '22023', message = 'Choose a date range of up to 400 days.';
  end if;

  return coalesce((
    with me as (
      -- the member and (for couple leadership) their current spouse
      select v_member_id as member_id
      union
      select case when fr.from_member_id = v_member_id then fr.to_member_id else fr.from_member_id end
      from public.family_relationships fr
      join public.family_relationship_types frt
        on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      where fr.organization_id = p_organization_id
        and fr.relationship_status = 'active'
        and (fr.effective_from is null or fr.effective_from <= current_date)
        and (fr.effective_to is null or fr.effective_to >= current_date)
        and v_member_id in (fr.from_member_id, fr.to_member_id)
    ),
    my_leader_assignments as (
      select la.governance_node_id, lrd.code as role_code, la.member_id
      from public.leadership_assignments la
      join public.leadership_role_definitions lrd
        on lrd.id = la.leadership_role_definition_id
       and lrd.organization_id = la.organization_id
      where la.organization_id = p_organization_id
        and la.member_id in (select member_id from me)
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date)
        and lrd.code in ('household_servant_leader', 'unit_servant_leader',
                         'chapter_servant_leader', 'area_servant_leader')
    ),
    led_households as (
      -- member-level households: leader appointed on the household itself
      select h.id as household_id
      from public.households h
      join my_leader_assignments a
        on a.governance_node_id = h.id and a.role_code = 'household_servant_leader'
      where h.organization_id = p_organization_id
        and h.pastoral_level = 'member'
        and (a.member_id = v_member_id or h.is_couple_household)
      union
      -- unit / chapter / area households: leader appointed on the household's primary parent node
      select h.id
      from public.households h
      join public.governance_node_relationships gnr
        on gnr.child_node_id = h.id
       and gnr.organization_id = h.organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and gnr.effective_from <= current_date
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join my_leader_assignments a
        on a.governance_node_id = gnr.parent_node_id
       and a.role_code = h.pastoral_level || '_servant_leader'
      where h.organization_id = p_organization_id
        and h.pastoral_level in ('unit', 'chapter', 'area')
        and (a.member_id = v_member_id or h.is_couple_household)
    )
    select jsonb_agg(x.j order by x.meeting_date, x.scheduled_start_at nulls last, x.id)
    from (
      select hmt.id, hmt.meeting_date, hmt.scheduled_start_at,
             jsonb_build_object(
               'household_meeting_id', hmt.id,
               'household_id',         hmt.household_node_id,
               'household_name',       gn.name,
               'meeting_date',         hmt.meeting_date,
               'scheduled_start_at',   hmt.scheduled_start_at,
               'scheduled_end_at',     hmt.scheduled_end_at,
               'meeting_status',       hmt.meeting_status,
               'meeting_type',         hmt.meeting_type,
               'location_type',        hmt.location_type,
               'location_text',        hmt.location_text,
               'host_name',            host_m.display_name,
               'facilitator_name',     fac_m.display_name,
               'my_attendance_status', (select a.attendance_status
                                          from public.household_meeting_attendance a
                                         where a.household_meeting_id = hmt.id
                                           and a.member_id = v_member_id
                                         limit 1),
               'my_role',              case when lh.household_id is not null then 'leader' else 'member' end
             ) as j
      from public.household_meetings hmt
      join public.governance_nodes gn
        on gn.id = hmt.household_node_id
       and gn.organization_id = hmt.organization_id
      left join led_households lh
        on lh.household_id = hmt.household_node_id
      left join public.members host_m
        on host_m.id = hmt.host_member_id and host_m.organization_id = hmt.organization_id
      left join public.members fac_m
        on fac_m.id = hmt.facilitator_member_id and fac_m.organization_id = hmt.organization_id
      where hmt.organization_id = p_organization_id
        and hmt.meeting_date between p_from and p_to
        and (
          lh.household_id is not null
          or exists (
            select 1
            from public.household_memberships hm
            where hm.organization_id = p_organization_id
              and hm.household_node_id = hmt.household_node_id
              and hm.member_id = v_member_id
              and hm.membership_status in ('active', 'temporary')
              and hm.effective_from <= hmt.meeting_date
              and (hm.effective_to is null or hm.effective_to >= hmt.meeting_date)
          )
        )
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_household_meetings(uuid, date, date) from public, anon;
grant execute on function public.list_my_household_meetings(uuid, date, date) to authenticated;

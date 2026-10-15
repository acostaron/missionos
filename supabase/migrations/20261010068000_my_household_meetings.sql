-- =============================================================================
-- Migration: 20261010068000_my_household_meetings.sql
-- MissionOS Pass 8.4A (written by Claude, 2026-10-14)
-- Every household member can see their own household's meetings (scheduled, completed and
-- cancelled) in the member portal: Home, My Profile and My Events. Read-only.
-- A member sees a meeting when they belonged to that household on the meeting date
-- (active or temporary membership covering that date). Nothing about other households.
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
                                         limit 1)
             ) as j
      from public.household_meetings hmt
      join public.governance_nodes gn
        on gn.id = hmt.household_node_id
       and gn.organization_id = hmt.organization_id
      left join public.members host_m
        on host_m.id = hmt.host_member_id and host_m.organization_id = hmt.organization_id
      left join public.members fac_m
        on fac_m.id = hmt.facilitator_member_id and fac_m.organization_id = hmt.organization_id
      where hmt.organization_id = p_organization_id
        and hmt.meeting_date between p_from and p_to
        and exists (
          select 1
          from public.household_memberships hm
          where hm.organization_id = p_organization_id
            and hm.household_node_id = hmt.household_node_id
            and hm.member_id = v_member_id
            and hm.membership_status in ('active', 'temporary')
            and hm.effective_from <= hmt.meeting_date
            and (hm.effective_to is null or hm.effective_to >= hmt.meeting_date)
        )
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_household_meetings(uuid, date, date) from public, anon;
grant execute on function public.list_my_household_meetings(uuid, date, date) to authenticated;

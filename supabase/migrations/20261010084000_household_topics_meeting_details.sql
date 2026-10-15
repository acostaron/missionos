-- =============================================================================
-- Migration: 20261010084000_household_topics_meeting_details.sql
-- MissionOS Pass 9.8 (written by Claude, 2026-10-16)
-- Ron: My Events should not list household meetings twice. Household meetings now appear only in the
-- household topic cards; "Upcoming" keeps assemblies, teachings, retreats and other events.
-- So the cards carry what the Upcoming list used to show: location type/text and host, and upcoming
-- CANCELLED meetings (shown as cancelled, no topic actions).
-- Guarded: replaces public.list_my_household_topics only if it is still the 20261010082000 version.
-- =============================================================================
do $guard$
declare
  v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'list_my_household_topics';
  if v_md5 is distinct from '6b38c2c6dac4f589359ba2b1dac51595' then
    raise exception 'STOP: public.list_my_household_topics differs from 20261010082000 (md5 %).', v_md5;
  end if;
end;
$guard$;

create or replace function public.list_my_household_topics(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id  uuid;
  v_profile_id uuid;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  v_profile_id := private.current_profile_id();

  return coalesce((
    with my_hh as (
      select hm.household_node_id as household_id
      from public.household_memberships hm
      where hm.organization_id = p_organization_id
        and hm.member_id = v_member_id
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
      union
      select l.household_id from private.member_led_household_ids(p_organization_id, v_member_id) l
    )
    select jsonb_agg(jsonb_build_object(
             'household_id',   h.id,
             'household_name', gn.name,
             'pastoral_level', h.pastoral_level,
             'can_edit',       private.member_can_edit_household_topics(p_organization_id, v_member_id, v_profile_id, h.id),
             'meetings', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'household_meeting_id', mt.id,
                        'meeting_date',         mt.meeting_date,
                        'scheduled_start_at',   mt.scheduled_start_at,
                        'meeting_status',       mt.meeting_status,
                        'location_type',        mt.location_type,
                        'location_text',        mt.location_text,
                        'host_name',            host_m.display_name,
                        'topics', coalesce((
                          select jsonb_agg(jsonb_build_object(
                                   'assignment_id',      a.id,
                                   'topic_id',           a.topic_id,
                                   'title',              ft.title,
                                   'is_library_topic',   ft.series_code is not null,
                                   'assignment_status',  a.assignment_status,
                                   'change_reason_code', a.change_reason_code,
                                   'replaced_by_title',  coalesce(rb_ft.title, a.used_topic_title),
                                   'replaces_title',     rp_ft.title)
                                 order by a.assignment_status, ft.title)
                          from public.household_topic_assignments a
                          join public.formation_topics ft on ft.id = a.topic_id
                          left join public.household_topic_assignments rb on rb.id = a.replaced_by_assignment_id
                          left join public.formation_topics rb_ft on rb_ft.id = rb.topic_id
                          left join public.household_topic_assignments rp on rp.id = a.replaces_assignment_id
                          left join public.formation_topics rp_ft on rp_ft.id = rp.topic_id
                          where coalesce(a.completed_household_meeting_id, a.planned_household_meeting_id) = mt.id
                            and a.assignment_status in ('planned', 'completed', 'skipped')), '[]'::jsonb))
                      order by mt.meeting_date, mt.scheduled_start_at nulls last)
               from public.household_meetings mt
               left join public.members host_m
                 on host_m.id = mt.host_member_id and host_m.organization_id = mt.organization_id
               where mt.organization_id = p_organization_id
                 and mt.household_node_id = h.id
                 and (mt.meeting_status in ('scheduled', 'completed')
                      or (mt.meeting_status = 'cancelled' and mt.meeting_date >= current_date))
                 and mt.meeting_date between current_date - 30 and current_date + 90), '[]'::jsonb))
           order by gn.name)
    from my_hh
    join public.households h on h.id = my_hh.household_id and h.organization_id = p_organization_id
    join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_household_topics(uuid) from public, anon;
grant execute on function public.list_my_household_topics(uuid) to authenticated;

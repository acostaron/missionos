-- =============================================================================
-- Migration: 20261010082000_member_household_topics.sql
-- MissionOS Pass 9.7 (written by Claude, 2026-10-16)
-- Ron: the household topics card in My Events for EVERY household, not only Fraternal.
--   * All members see their household's meetings (30 days back, 90 ahead), the topic, Open topic.
--   * Who can choose / change the topic (Ron's decision "Leaders edit, all view"):
--       - Fraternal household: any active member (unchanged from 9.6)
--       - other households: that household's servant leaders — member level: household_servant_leader
--         on the household; unit/chapter/area: the <level>_servant_leader on its primary parent node —
--         and their spouse when the household is a couple household or the leader is in the Couples
--         section (husband and wife lead together); organization administrators.
--     This is a self-service path: it checks the leadership appointment itself, not the delegated
--     software-access grant used by the leader workspace.
--   * Households listed: those the member belongs to today + those the member (or spouse, as above) leads.
-- Uses private.change_meeting_topic_core (9.6). No existing function is changed.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Households a member leads (directly, or with their spouse in couple leadership)
-- -----------------------------------------------------------------------------
create or replace function private.member_led_household_ids(p_organization_id uuid, p_member_id uuid)
returns table (household_id uuid)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with me as (
    select p_member_id as member_id, true as is_self
    union
    select case when fr.from_member_id = p_member_id then fr.to_member_id else fr.from_member_id end, false
    from public.family_relationships fr
    join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
    where fr.organization_id = p_organization_id
      and fr.relationship_status = 'active'
      and fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')
      and (fr.effective_from is null or fr.effective_from <= current_date)
      and (fr.effective_to is null or fr.effective_to >= current_date)
      and p_member_id in (fr.from_member_id, fr.to_member_id)
  ),
  appts as (
    select la.governance_node_id, lrd.code as role_code, me.is_self,
           private.member_in_couples_section(p_organization_id, la.member_id) as leader_in_couples
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join me on me.member_id = la.member_id
    where la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
  )
  select h.id
  from public.households h
  join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
  join appts a on a.governance_node_id = h.id and a.role_code = 'household_servant_leader'
  where h.organization_id = p_organization_id and h.pastoral_level = 'member'
    and (a.is_self or h.is_couple_household or a.leader_in_couples)
  union
  select h.id
  from public.households h
  join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
  join public.governance_node_relationships gnr
    on gnr.child_node_id = h.id and gnr.organization_id = h.organization_id
   and gnr.relationship_type = 'primary_parent' and gnr.relationship_status = 'active'
   and gnr.effective_from <= current_date
   and (gnr.effective_to is null or gnr.effective_to >= current_date)
  join appts a on a.governance_node_id = gnr.parent_node_id and a.role_code = h.pastoral_level || '_servant_leader'
  where h.organization_id = p_organization_id and h.pastoral_level in ('unit', 'chapter', 'area')
    and (a.is_self or h.is_couple_household or a.leader_in_couples)
$$;
revoke all on function private.member_led_household_ids(uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Can this member choose / change topics for this household?
-- -----------------------------------------------------------------------------
create or replace function private.member_can_edit_household_topics(
  p_organization_id uuid,
  p_member_id       uuid,
  p_profile_id      uuid,
  p_household_id    uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select
    private.is_organization_administrator(p_profile_id, p_organization_id)
    or exists (select 1 from private.member_led_household_ids(p_organization_id, p_member_id) l
               where l.household_id = p_household_id)
    or exists (
      select 1
      from public.households h
      join public.household_memberships hm
        on hm.household_node_id = h.id and hm.organization_id = h.organization_id
      where h.id = p_household_id
        and h.organization_id = p_organization_id
        and h.pastoral_level = 'fraternal'
        and hm.member_id = p_member_id
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date))
$$;
revoke all on function private.member_can_edit_household_topics(uuid, uuid, uuid, uuid) from public, anon, authenticated;

create or replace function private.assert_member_can_edit_meeting_topics(p_organization_id uuid, p_meeting_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
  v_household uuid;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  select m.household_node_id into v_household
  from public.household_meetings m
  join public.governance_nodes gn on gn.id = m.household_node_id and gn.lifecycle_status = 'active'
  where m.id = p_meeting_id and m.organization_id = p_organization_id;
  if v_household is null then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;
  if not private.member_can_edit_household_topics(p_organization_id, v_member_id, private.current_profile_id(), v_household) then
    raise exception using errcode = '42501', message = 'Only this household''s servant leaders can change its topics.';
  end if;
  return v_household;
end;
$$;
revoke all on function private.assert_member_can_edit_meeting_topics(uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. My households: meetings and topics, with can_edit
-- -----------------------------------------------------------------------------
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
               where mt.organization_id = p_organization_id
                 and mt.household_node_id = h.id
                 and mt.meeting_status in ('scheduled', 'completed')
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

-- -----------------------------------------------------------------------------
-- 4. Choose a topic for a scheduled meeting (self-service)
-- -----------------------------------------------------------------------------
create or replace function public.member_assign_household_topic(
  p_organization_id uuid,
  p_meeting_id      uuid,
  p_topic_id        uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_household  uuid;
  v_profile_id uuid;
  v_meeting    public.household_meetings%rowtype;
  v_topic      public.formation_topics%rowtype;
  v_id         uuid;
begin
  v_household := private.assert_member_can_edit_meeting_topics(p_organization_id, p_meeting_id);
  v_profile_id := private.current_profile_id();

  select * into v_meeting from public.household_meetings where id = p_meeting_id;
  if v_meeting.meeting_status <> 'scheduled' then
    raise exception using errcode = '22023', message = 'Topics can only be planned for a scheduled meeting.';
  end if;

  select * into v_topic from public.formation_topics ft
  where ft.id = p_topic_id and (ft.organization_id is null or ft.organization_id = p_organization_id) and ft.is_active;
  if not found then
    raise exception using errcode = '22023', message = 'Formation topic not found or is inactive.';
  end if;

  if exists (select 1 from public.household_topic_assignments a
             where a.household_node_id = v_household and a.topic_id = p_topic_id
               and a.planned_for_date = v_meeting.meeting_date and a.assignment_status = 'planned') then
    raise exception using errcode = '23505', message = 'This topic is already planned for that meeting.';
  end if;

  insert into public.household_topic_assignments (
    organization_id, household_node_id, topic_id, planned_for_date, assignment_status,
    assigned_at, assigned_by_profile_id, planned_household_meeting_id,
    created_at, updated_at, created_by_profile_id, updated_by_profile_id)
  values (
    p_organization_id, v_household, p_topic_id, v_meeting.meeting_date, 'planned',
    now(), v_profile_id, v_meeting.id,
    now(), now(), v_profile_id, v_profile_id)
  returning id into v_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.assigned',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_id,
    p_action           => 'assign',
    p_outcome          => 'success',
    p_access_reason    => 'member_portal_topic_assign',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id', v_id, 'household_node_id', v_household, 'topic_id', p_topic_id,
      'household_meeting_id', v_meeting.id, 'planned_for_date', v_meeting.meeting_date));

  return jsonb_build_object('assignment_id', v_id, 'topic_title', v_topic.title,
                            'household_meeting_id', v_meeting.id, 'meeting_date', v_meeting.meeting_date);
end;
$$;
revoke all on function public.member_assign_household_topic(uuid, uuid, uuid) from public, anon;
grant execute on function public.member_assign_household_topic(uuid, uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Record a changed topic (self-service)
-- -----------------------------------------------------------------------------
create or replace function public.member_change_household_meeting_topic(
  p_organization_id        uuid,
  p_meeting_id             uuid,
  p_reason_code            text,
  p_replaced_assignment_id uuid default null,
  p_new_topic_id           uuid default null,
  p_other_title            text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  perform private.assert_member_can_edit_meeting_topics(p_organization_id, p_meeting_id);
  return private.change_meeting_topic_core(private.current_profile_id(), p_organization_id, p_meeting_id,
    p_reason_code, p_replaced_assignment_id, p_new_topic_id, p_other_title, 'member_portal_topic_replace');
end;
$$;
revoke all on function public.member_change_household_meeting_topic(uuid, uuid, text, uuid, uuid, text) from public, anon;
grant execute on function public.member_change_household_meeting_topic(uuid, uuid, text, uuid, uuid, text) to authenticated;

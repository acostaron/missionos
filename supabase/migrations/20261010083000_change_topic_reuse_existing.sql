-- =============================================================================
-- Migration: 20261010083000_change_topic_reuse_existing.sql
-- MissionOS Pass 9.7A (written by Claude, 2026-10-16)
-- Fix found by the 9.7 check: "Change topic used" failed with a duplicate-key error when the topic
-- actually used was ALREADY planned for that meeting (e.g. a meeting planned with both the Household
-- Topic and the Date Night topic; the Household Topic is then recorded as replaced by Date Night).
-- private.change_meeting_topic_core now reuses that existing assignment (linking it as the replacement,
-- with the reason) instead of inserting a duplicate. Nothing else changes.
-- Guarded: replaced only if the live body is still the 20261010081000 version.
-- =============================================================================
do $guard$
declare
  v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'change_meeting_topic_core';
  if v_md5 is distinct from '3b6fd30b2be67c59009fdf337b5a9c4e' then
    raise exception 'STOP: private.change_meeting_topic_core differs from 20261010081000 (md5 %).', v_md5;
  end if;
end;
$guard$;

create or replace function private.change_meeting_topic_core(
  p_profile_id             uuid,
  p_organization_id        uuid,
  p_meeting_id             uuid,
  p_reason_code            text,
  p_replaced_assignment_id uuid,
  p_new_topic_id           uuid,
  p_other_title            text,
  p_access_reason          text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile_id uuid;
  v_meeting    public.household_meetings%rowtype;
  v_old        public.household_topic_assignments%rowtype;
  v_new        public.formation_topics%rowtype;
  v_used_title text;
  v_other      text := nullif(trim(p_other_title), '');
  v_new_id     uuid;
begin
  v_profile_id := p_profile_id;
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  select * into v_meeting
  from public.household_meetings m
  where m.id = p_meeting_id and m.organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;

  if v_meeting.meeting_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'This meeting was cancelled.';
  end if;
  if p_reason_code is null or p_reason_code not in
     ('pastoral_need', 'leader_decision', 'material_unavailable', 'time_constraint', 'other') then
    raise exception using errcode = '22023', message = 'Choose a reason for the change.';
  end if;
  if (p_new_topic_id is null) = (v_other is null) then
    raise exception using errcode = '22023', message = 'Choose a topic from the library or type the topic that was used — one, not both.';
  end if;
  if v_other is not null and length(v_other) > 200 then
    raise exception using errcode = '22023', message = 'Topic title is too long.';
  end if;

  if p_new_topic_id is not null then
    select * into v_new from public.formation_topics ft
    where ft.id = p_new_topic_id and (ft.organization_id is null or ft.organization_id = p_organization_id)
      and ft.is_active;
    if not found then
      raise exception using errcode = '22023', message = 'Formation topic not found or is inactive.';
    end if;
    v_used_title := v_new.title;
  else
    v_used_title := v_other;
  end if;

  if p_replaced_assignment_id is not null then
    select * into v_old from public.household_topic_assignments a
    where a.id = p_replaced_assignment_id and a.organization_id = p_organization_id
      and (a.planned_household_meeting_id = v_meeting.id or a.completed_household_meeting_id = v_meeting.id)
      and a.assignment_status in ('planned', 'completed')
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The planned topic for this meeting was not found.';
    end if;
    if p_new_topic_id is not null and p_new_topic_id = v_old.topic_id then
      raise exception using errcode = '22023', message = 'That is the topic already planned for this meeting.';
    end if;
  elsif v_other is not null then
    raise exception using errcode = '22023',
      message = 'A typed topic can only be recorded in place of the topic planned for this meeting.';
  end if;

  -- record the library topic that was used (Pass 9.7A: if that topic is already on this meeting,
  -- or already planned for the same date, reuse it instead of creating a duplicate)
  if p_new_topic_id is not null then
    select a.id into v_new_id
    from public.household_topic_assignments a
    where a.organization_id = p_organization_id
      and a.household_node_id = v_meeting.household_node_id
      and a.topic_id = p_new_topic_id
      and a.id is distinct from v_old.id
      and (
        (coalesce(a.completed_household_meeting_id, a.planned_household_meeting_id) = v_meeting.id
         and a.assignment_status in ('planned', 'completed'))
        or (a.assignment_status = 'planned' and a.planned_for_date = v_meeting.meeting_date))
    order by (coalesce(a.completed_household_meeting_id, a.planned_household_meeting_id) = v_meeting.id) desc
    limit 1
    for update;

    if v_new_id is not null then
      update public.household_topic_assignments
         set planned_household_meeting_id   = v_meeting.id,
             assignment_status              = case when v_meeting.meeting_status = 'completed' then 'completed' else assignment_status end,
             completed_at                   = case when v_meeting.meeting_status = 'completed' then coalesce(completed_at, now()) else completed_at end,
             completed_by_profile_id        = case when v_meeting.meeting_status = 'completed' then coalesce(completed_by_profile_id, v_profile_id) else completed_by_profile_id end,
             completed_household_meeting_id = case when v_meeting.meeting_status = 'completed' then v_meeting.id else completed_household_meeting_id end,
             change_reason_code             = p_reason_code,
             replaces_assignment_id         = coalesce(v_old.id, replaces_assignment_id),
             updated_at                     = now(),
             updated_by_profile_id          = v_profile_id
       where id = v_new_id;
    else
      insert into public.household_topic_assignments (
        organization_id, household_node_id, topic_id, planned_for_date, assignment_status,
        assigned_at, assigned_by_profile_id, planned_household_meeting_id,
        completed_at, completed_by_profile_id, completed_household_meeting_id,
        change_reason_code, replaces_assignment_id,
        created_at, updated_at, created_by_profile_id, updated_by_profile_id)
      values (
        p_organization_id, v_meeting.household_node_id, p_new_topic_id, v_meeting.meeting_date,
        case when v_meeting.meeting_status = 'completed' then 'completed' else 'planned' end,
        now(), v_profile_id, v_meeting.id,
        case when v_meeting.meeting_status = 'completed' then now() end,
        case when v_meeting.meeting_status = 'completed' then v_profile_id end,
        case when v_meeting.meeting_status = 'completed' then v_meeting.id end,
        p_reason_code, v_old.id,
        now(), now(), v_profile_id, v_profile_id)
      returning id into v_new_id;
    end if;
  end if;

  -- planned topic -> skipped, topic replaced
  if v_old.id is not null then
    update public.household_topic_assignments
       set assignment_status              = 'skipped',
           skipped_at                     = now(),
           skipped_by_profile_id          = v_profile_id,
           completed_at                   = null,
           completed_by_profile_id        = null,
           completed_household_meeting_id = null,
           planned_household_meeting_id   = v_meeting.id,
           resolution_reason_code         = 'topic_replaced',
           change_reason_code             = p_reason_code,
           replaced_by_assignment_id      = v_new_id,
           used_topic_title               = v_other,
           updated_at                     = now(),
           updated_by_profile_id          = v_profile_id
     where id = v_old.id;
  end if;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.replaced',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => v_meeting.id,
    p_action           => 'replace_topic',
    p_outcome          => 'success',
    p_access_reason    => p_access_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', v_meeting.id,
      'replaced_assignment_id', v_old.id,
      'new_assignment_id', v_new_id,
      'new_topic_id', p_new_topic_id,
      'reason_code', p_reason_code,
      'typed_title', v_other is not null));

  return jsonb_build_object(
    'household_meeting_id', v_meeting.id,
    'replaced_assignment_id', v_old.id,
    'new_assignment_id', v_new_id,
    'used_title', v_used_title);
end;
$$;
revoke all on function private.change_meeting_topic_core(uuid, uuid, uuid, text, uuid, uuid, text, text) from public, anon, authenticated;

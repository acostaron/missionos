-- =============================================================================
-- Migration: 20261010079000_meeting_topic_change_reasons.sql
-- MissionOS Pass 9.4A (written by Claude, 2026-10-15)
-- Fix for 20261010078000: household_topic_assignments.resolution_notes was removed in
-- Phase 6B-10 (formation privacy boundary: no free-text notes). Ron confirmed keeping that rule:
-- the reason for a changed topic is a choice from a fixed list, not free text.
--   * New structured columns: change_reason_code, replaced_by_assignment_id, replaces_assignment_id,
--     used_topic_title (a topic TITLE typed only when the topic used is not in the library).
--   * change_meeting_topic is replaced (p_reason text -> p_reason_code).
--   * get_household_meeting_topics returns the structured fields instead of notes.
-- =============================================================================

alter table public.household_topic_assignments
  add column if not exists change_reason_code text null,
  add column if not exists replaced_by_assignment_id uuid null
    references public.household_topic_assignments(id) on delete set null,
  add column if not exists replaces_assignment_id uuid null
    references public.household_topic_assignments(id) on delete set null,
  add column if not exists used_topic_title text null;

alter table public.household_topic_assignments
  drop constraint if exists household_topic_assignments_change_reason_code_check;
alter table public.household_topic_assignments
  add constraint household_topic_assignments_change_reason_code_check check (
    change_reason_code is null or change_reason_code in (
      'pastoral_need', 'leader_decision', 'material_unavailable', 'time_constraint', 'other'));

alter table public.household_topic_assignments
  drop constraint if exists household_topic_assignments_used_topic_title_check;
alter table public.household_topic_assignments
  add constraint household_topic_assignments_used_topic_title_check check (
    used_topic_title is null or (length(trim(used_topic_title)) between 1 and 200));

drop function if exists public.change_meeting_topic(uuid, uuid, text, uuid, uuid, text);

create or replace function public.change_meeting_topic(
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
declare
  v_profile_id uuid;
  v_meeting    public.household_meetings%rowtype;
  v_old        public.household_topic_assignments%rowtype;
  v_new        public.formation_topics%rowtype;
  v_used_title text;
  v_other      text := nullif(trim(p_other_title), '');
  v_new_id     uuid;
begin
  v_profile_id := private.assert_formation_manage_prereqs(p_organization_id);

  select * into v_meeting
  from public.household_meetings m
  where m.id = p_meeting_id and m.organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;
  perform private.assert_formation_household_write(v_profile_id, p_organization_id, v_meeting.household_node_id, true);

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

  -- record the library topic that was used
  if p_new_topic_id is not null then
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
    p_access_reason    => 'household_formation_topic_replace',
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
revoke all on function public.change_meeting_topic(uuid, uuid, text, uuid, uuid, text) from public, anon;
grant execute on function public.change_meeting_topic(uuid, uuid, text, uuid, uuid, text) to authenticated, service_role;

create or replace function public.get_household_meeting_topics(
  p_organization_id   uuid,
  p_household_node_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;
  if not (private.can_access_household('households.formation.view', p_organization_id, p_household_node_id)
          or private.can_access_household('households.formation.manage', p_organization_id, p_household_node_id)) then
    raise exception using errcode = '42501', message = 'You do not have permission to view this household''s topics.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'assignment_id',          a.id,
             'household_meeting_id',   coalesce(a.completed_household_meeting_id, a.planned_household_meeting_id),
             'topic_id',               a.topic_id,
             'title',                  ft.title,
             'topic_code',             ft.topic_code,
             'material_kind',          ft.material_kind,
             'is_library_topic',       ft.series_code is not null,
             'assignment_status',      a.assignment_status,
             'resolution_reason_code', a.resolution_reason_code,
             'change_reason_code',     a.change_reason_code,
             'replaced_by_title',      coalesce(rb_ft.title, a.used_topic_title),
             'replaces_title',         rp_ft.title,
             'planned_for_date',       a.planned_for_date)
           order by a.planned_for_date nulls last, a.assignment_status, ft.title)
    from public.household_topic_assignments a
    join public.formation_topics ft on ft.id = a.topic_id
    left join public.household_topic_assignments rb on rb.id = a.replaced_by_assignment_id
    left join public.formation_topics rb_ft on rb_ft.id = rb.topic_id
    left join public.household_topic_assignments rp on rp.id = a.replaces_assignment_id
    left join public.formation_topics rp_ft on rp_ft.id = rp.topic_id
    where a.organization_id = p_organization_id
      and a.household_node_id = p_household_node_id
      and coalesce(a.completed_household_meeting_id, a.planned_household_meeting_id) is not null
      and a.assignment_status in ('planned', 'completed', 'skipped')
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.get_household_meeting_topics(uuid, uuid) from public, anon;
grant execute on function public.get_household_meeting_topics(uuid, uuid) to authenticated, service_role;

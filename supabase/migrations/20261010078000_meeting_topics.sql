-- =============================================================================
-- Migration: 20261010078000_meeting_topics.sql
-- MissionOS Pass 9.4 (written by Claude, 2026-10-15)
-- Household topics tied to the household's scheduled meetings (Ron's request):
--   1. A topic is planned FOR a scheduled meeting (planned_household_meeting_id); its planned
--      date follows the meeting date.
--   2. When the meeting is marked completed, the topic planned for it is completed automatically.
--      When the meeting is cancelled, the topic stays planned but is unlinked from it.
--   3. If a different topic was used on the day, the leader records the change: the planned topic
--      becomes "skipped — topic replaced" with the reason, and the topic actually used (from the
--      library, or another title typed in) is recorded against the meeting.
--   4. get_household_meeting_topics lists, per meeting, the planned / used / replaced topics.
-- Existing RPCs are not modified. No member data in this file.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Link column
-- -----------------------------------------------------------------------------
alter table public.household_topic_assignments
  add column if not exists planned_household_meeting_id uuid null
    references public.household_meetings(id) on delete set null;

create index if not exists idx_hh_topic_assignments_planned_meeting
  on public.household_topic_assignments (planned_household_meeting_id)
  where planned_household_meeting_id is not null;

-- -----------------------------------------------------------------------------
-- 2. Keep topics in step with their meeting (trigger)
-- -----------------------------------------------------------------------------
create or replace function private.sync_topics_with_meeting()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  r record;
begin
  -- meeting completed -> complete the topics planned for it
  if old.meeting_status = 'scheduled' and new.meeting_status = 'completed' then
    for r in
      update public.household_topic_assignments a
         set assignment_status              = 'completed',
             completed_at                   = now(),
             completed_by_profile_id        = new.updated_by_profile_id,
             completed_household_meeting_id = new.id,
             updated_at                     = now(),
             updated_by_profile_id          = new.updated_by_profile_id
       where a.planned_household_meeting_id = new.id
         and a.assignment_status = 'planned'
      returning a.id, a.topic_id
    loop
      perform private.write_audit_event(
        p_organization_id  => new.organization_id,
        p_event_code       => 'household_topic.completed',
        p_event_category   => 'governance',
        p_actor_profile_id => new.updated_by_profile_id,
        p_entity_type      => 'household_topic_assignment',
        p_entity_id        => r.id,
        p_action           => 'complete',
        p_outcome          => 'success',
        p_access_reason    => 'household_meeting_completed',
        p_correlation_id   => null,
        p_metadata         => jsonb_build_object(
          'assignment_id', r.id, 'topic_id', r.topic_id,
          'completed_household_meeting_id', new.id, 'meeting_date', new.meeting_date,
          'automatic', true));
    end loop;
  end if;

  -- meeting cancelled -> topic stays planned, no longer tied to that meeting
  if new.meeting_status = 'cancelled' and old.meeting_status is distinct from 'cancelled' then
    update public.household_topic_assignments a
       set planned_household_meeting_id = null,
           updated_at = now()
     where a.planned_household_meeting_id = new.id
       and a.assignment_status = 'planned';
  end if;

  -- meeting moved -> planned date follows
  if new.meeting_date is distinct from old.meeting_date then
    update public.household_topic_assignments a
       set planned_for_date = new.meeting_date,
           updated_at = now()
     where a.planned_household_meeting_id = new.id
       and a.assignment_status = 'planned';
  end if;

  return new;
end;
$$;
revoke all on function private.sync_topics_with_meeting() from public, anon, authenticated;

drop trigger if exists trg_household_meetings_sync_topics on public.household_meetings;
create trigger trg_household_meetings_sync_topics
  after update of meeting_status, meeting_date on public.household_meetings
  for each row
  execute function private.sync_topics_with_meeting();

-- -----------------------------------------------------------------------------
-- 3. Plan a topic for a scheduled meeting
--    (wraps assign_household_topic so permission checks and audit stay identical)
-- -----------------------------------------------------------------------------
create or replace function public.assign_household_topic_to_meeting(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_topic_id          uuid,
  p_meeting_id        uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_meeting public.household_meetings%rowtype;
  v_result  jsonb;
begin
  select * into v_meeting
  from public.household_meetings m
  where m.id = p_meeting_id and m.organization_id = p_organization_id;
  if not found or v_meeting.household_node_id <> p_household_node_id then
    raise exception using errcode = 'P0002', message = 'Meeting not found for this household.';
  end if;
  if v_meeting.meeting_status <> 'scheduled' then
    raise exception using errcode = '22023', message = 'Topics can only be planned for a scheduled meeting.';
  end if;

  v_result := public.assign_household_topic(
    p_organization_id, p_household_node_id, p_topic_id, v_meeting.meeting_date, null);

  update public.household_topic_assignments
     set planned_household_meeting_id = v_meeting.id
   where id = (v_result->>'assignment_id')::uuid;

  return v_result || jsonb_build_object('household_meeting_id', v_meeting.id, 'meeting_date', v_meeting.meeting_date);
end;
$$;
revoke all on function public.assign_household_topic_to_meeting(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.assign_household_topic_to_meeting(uuid, uuid, uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. Record that a different topic was used at a meeting
-- -----------------------------------------------------------------------------
create or replace function public.change_meeting_topic(
  p_organization_id        uuid,
  p_meeting_id             uuid,
  p_reason                 text,
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
  v_old_title  text;
  v_new        public.formation_topics%rowtype;
  v_used_title text;
  v_reason     text := nullif(trim(p_reason), '');
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
  if v_reason is null or length(v_reason) < 3 or length(v_reason) > 500 then
    raise exception using errcode = '22023', message = 'Please give a short reason for the change (3–500 characters).';
  end if;
  if (p_new_topic_id is null) = (v_other is null) then
    raise exception using errcode = '22023', message = 'Choose a topic from the library or type the topic that was used — one, not both.';
  end if;
  if v_other is not null and length(v_other) > 200 then
    raise exception using errcode = '22023', message = 'Topic title is too long.';
  end if;

  -- topic actually used
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

  -- planned topic being replaced
  if p_replaced_assignment_id is not null then
    select * into v_old from public.household_topic_assignments a
    where a.id = p_replaced_assignment_id and a.organization_id = p_organization_id
      and (a.planned_household_meeting_id = v_meeting.id or a.completed_household_meeting_id = v_meeting.id)
      and a.assignment_status in ('planned', 'completed')
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'The planned topic for this meeting was not found.';
    end if;
    select ft.title into v_old_title from public.formation_topics ft where ft.id = v_old.topic_id;
    if p_new_topic_id is not null and p_new_topic_id = v_old.topic_id then
      raise exception using errcode = '22023', message = 'That is the topic already planned for this meeting.';
    end if;

    update public.household_topic_assignments
       set assignment_status              = 'skipped',
           skipped_at                     = now(),
           skipped_by_profile_id          = v_profile_id,
           completed_at                   = null,
           completed_by_profile_id        = null,
           completed_household_meeting_id = null,
           planned_household_meeting_id   = v_meeting.id,
           resolution_reason_code         = 'topic_replaced',
           resolution_notes               = left(format('Replaced at the %s meeting by "%s". Reason: %s',
                                                        to_char(v_meeting.meeting_date, 'Mon DD, YYYY'), v_used_title, v_reason), 1000),
           updated_at                     = now(),
           updated_by_profile_id          = v_profile_id
     where id = v_old.id;
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
      resolution_notes, created_at, updated_at, created_by_profile_id, updated_by_profile_id)
    values (
      p_organization_id, v_meeting.household_node_id, p_new_topic_id, v_meeting.meeting_date,
      case when v_meeting.meeting_status = 'completed' then 'completed' else 'planned' end,
      now(), v_profile_id, v_meeting.id,
      case when v_meeting.meeting_status = 'completed' then now() end,
      case when v_meeting.meeting_status = 'completed' then v_profile_id end,
      case when v_meeting.meeting_status = 'completed' then v_meeting.id end,
      left(case when v_old_title is not null
                then format('Used instead of "%s". Reason: %s', v_old_title, v_reason)
                else format('Used at this meeting. Reason: %s', v_reason) end, 1000),
      now(), now(), v_profile_id, v_profile_id)
    returning id into v_new_id;
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
      'replaced_assignment_id', p_replaced_assignment_id,
      'new_assignment_id', v_new_id,
      'new_topic_id', p_new_topic_id,
      'typed_title', v_other is not null));

  return jsonb_build_object(
    'household_meeting_id', v_meeting.id,
    'replaced_assignment_id', p_replaced_assignment_id,
    'new_assignment_id', v_new_id,
    'used_title', v_used_title);
end;
$$;
revoke all on function public.change_meeting_topic(uuid, uuid, text, uuid, uuid, text) from public, anon;
grant execute on function public.change_meeting_topic(uuid, uuid, text, uuid, uuid, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. Topics per meeting, for the household page
-- -----------------------------------------------------------------------------
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
             'resolution_notes',       a.resolution_notes,
             'planned_for_date',       a.planned_for_date)
           order by a.planned_for_date nulls last, a.assignment_status, ft.title)
    from public.household_topic_assignments a
    join public.formation_topics ft on ft.id = a.topic_id
    where a.organization_id = p_organization_id
      and a.household_node_id = p_household_node_id
      and coalesce(a.completed_household_meeting_id, a.planned_household_meeting_id) is not null
      and a.assignment_status in ('planned', 'completed', 'skipped')
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.get_household_meeting_topics(uuid, uuid) from public, anon;
grant execute on function public.get_household_meeting_topics(uuid, uuid) to authenticated, service_role;

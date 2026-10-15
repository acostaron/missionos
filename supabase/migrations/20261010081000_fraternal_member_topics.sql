-- =============================================================================
-- Migration: 20261010081000_fraternal_member_topics.sql
-- MissionOS Pass 9.6 (written by Claude, 2026-10-16)
-- Ron: members of a Fraternal household (rotating facilitation) can plan the topic for their
-- household's scheduled meetings and record a changed topic, from the member portal.
--   * private.change_meeting_topic_core — the 9.4A change logic without the permission checks.
--   * public.change_meeting_topic — unchanged behaviour: leader checks, then the core.
--     (Guarded: replaced only if the live body is still the 20261010079000 version.)
--   * private.assert_fraternal_meeting_member — the caller (self-service) is an active member of
--     the fraternal household that owns the meeting.
--   * public.list_my_fraternal_topics / member_assign_fraternal_topic /
--     member_change_fraternal_meeting_topic — self-service RPCs for those members.
-- Reasons stay a fixed list (no free text). Members pick approved Household Library topics.
-- =============================================================================

do $guard$
declare
  v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'change_meeting_topic';
  if v_md5 is distinct from '3ebccb7dd2743c9a956c933dadb3861e' then
    raise exception 'STOP: public.change_meeting_topic differs from 20261010079000 (md5 %).', v_md5;
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- 1. Core (no permission checks — callers must check first)
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 2. Leader RPC: same checks as before, then the core
-- -----------------------------------------------------------------------------
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
  v_household  uuid;
begin
  v_profile_id := private.assert_formation_manage_prereqs(p_organization_id);
  select m.household_node_id into v_household
  from public.household_meetings m
  where m.id = p_meeting_id and m.organization_id = p_organization_id;
  if v_household is null then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;
  perform private.assert_formation_household_write(v_profile_id, p_organization_id, v_household, true);
  return private.change_meeting_topic_core(v_profile_id, p_organization_id, p_meeting_id, p_reason_code,
    p_replaced_assignment_id, p_new_topic_id, p_other_title, 'household_formation_topic_replace');
end;
$$;
revoke all on function public.change_meeting_topic(uuid, uuid, text, uuid, uuid, text) from public, anon;
grant execute on function public.change_meeting_topic(uuid, uuid, text, uuid, uuid, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Fraternal member check
-- -----------------------------------------------------------------------------
create or replace function private.assert_fraternal_meeting_member(
  p_organization_id uuid,
  p_meeting_id      uuid
)
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
  join public.households h on h.id = m.household_node_id and h.organization_id = m.organization_id
  join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
  where m.id = p_meeting_id
    and m.organization_id = p_organization_id
    and h.pastoral_level = 'fraternal';
  if v_household is null then
    raise exception using errcode = 'P0002', message = 'Meeting not found for a fraternal household.';
  end if;

  if not exists (
    select 1 from public.household_memberships hm
    where hm.organization_id = p_organization_id
      and hm.household_node_id = v_household
      and hm.member_id = v_member_id
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
  ) then
    raise exception using errcode = '42501', message = 'Only members of this fraternal household can do this.';
  end if;

  return v_household;
end;
$$;
revoke all on function private.assert_fraternal_meeting_member(uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. My fraternal households: meetings (30 days back, 90 ahead) and their topics
-- -----------------------------------------------------------------------------
create or replace function public.list_my_fraternal_topics(p_organization_id uuid)
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

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'household_id',   h.id,
             'household_name', gn.name,
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
    from public.households h
    join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
    where h.organization_id = p_organization_id
      and h.pastoral_level = 'fraternal'
      and exists (
        select 1 from public.household_memberships hm
        where hm.organization_id = p_organization_id
          and hm.household_node_id = h.id
          and hm.member_id = v_member_id
          and hm.membership_status in ('active', 'temporary')
          and hm.effective_from <= current_date
          and (hm.effective_to is null or hm.effective_to >= current_date))
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_fraternal_topics(uuid) from public, anon;
grant execute on function public.list_my_fraternal_topics(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Member plans a topic for a scheduled fraternal meeting
-- -----------------------------------------------------------------------------
create or replace function public.member_assign_fraternal_topic(
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
  v_household := private.assert_fraternal_meeting_member(p_organization_id, p_meeting_id);
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
    p_access_reason    => 'fraternal_member_topic_assign',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id', v_id, 'household_node_id', v_household, 'topic_id', p_topic_id,
      'household_meeting_id', v_meeting.id, 'planned_for_date', v_meeting.meeting_date));

  return jsonb_build_object('assignment_id', v_id, 'topic_title', v_topic.title,
                            'household_meeting_id', v_meeting.id, 'meeting_date', v_meeting.meeting_date);
end;
$$;
revoke all on function public.member_assign_fraternal_topic(uuid, uuid, uuid) from public, anon;
grant execute on function public.member_assign_fraternal_topic(uuid, uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Member records a changed topic for a fraternal meeting
-- -----------------------------------------------------------------------------
create or replace function public.member_change_fraternal_meeting_topic(
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
  perform private.assert_fraternal_meeting_member(p_organization_id, p_meeting_id);
  return private.change_meeting_topic_core(private.current_profile_id(), p_organization_id, p_meeting_id,
    p_reason_code, p_replaced_assignment_id, p_new_topic_id, p_other_title, 'fraternal_member_topic_replace');
end;
$$;
revoke all on function public.member_change_fraternal_meeting_topic(uuid, uuid, text, uuid, uuid, text) from public, anon;
grant execute on function public.member_change_fraternal_meeting_topic(uuid, uuid, text, uuid, uuid, text) to authenticated;

-- =============================================================================
-- Migration: 20261002260000_phase_6b_household_formation_corrections.sql
-- Phase:     Phase 6B-10 — Household Formation corrections
-- Purpose:   1. Remove unverified seeded shared topics
--            2. Drop dangling module/talk reference columns
--            3. Harden RPC execute privileges
--            4. Align write authorization (shared private helpers)
--            5. Require a completed meeting as completion evidence
--            6. Add factual access_reason / audit metadata to write RPCs
--            7. Clean up get_household_formation_plan duplicate join
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Remove unverified seeded shared topics
--    Delete when unreferenced; otherwise deactivate. No replacements inserted.
-- -----------------------------------------------------------------------------

delete from public.formation_topics ft
where ft.organization_id is null
  and ft.topic_code in (
    'PFO-01', 'PFO-02', 'PFO-03',
    'HT-FAM-01', 'HT-COM-01', 'HT-MIS-01',
    'SR-01', 'HT-LEAD-01'
  )
  and not exists (
    select 1
    from public.household_topic_assignments a
    where a.topic_id = ft.id
  );

update public.formation_topics
set is_active  = false,
    updated_at = now()
where organization_id is null
  and topic_code in (
    'PFO-01', 'PFO-02', 'PFO-03',
    'HT-FAM-01', 'HT-COM-01', 'HT-MIS-01',
    'SR-01', 'HT-LEAD-01'
  )
  and is_active = true;

-- -----------------------------------------------------------------------------
-- 2. Drop dangling module/talk reference columns
-- -----------------------------------------------------------------------------

alter table public.formation_topics
  drop column if exists formation_module_id,
  drop column if exists formation_talk_id;

-- -----------------------------------------------------------------------------
-- 3. Shared write-authorization helpers
-- -----------------------------------------------------------------------------

create or replace function private.assert_formation_manage_prereqs(
  p_organization_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.formation.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household formation topics.';
  end if;

  return v_profile_id;
end;
$$;

create or replace function private.assert_formation_household_write(
  p_profile_id        uuid,
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_require_active    boolean default true
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_lifecycle_status text;
begin
  select gn.lifecycle_status
  into v_lifecycle_status
  from public.governance_nodes gn
  where gn.id = p_household_node_id
    and gn.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not active.';
  end if;

  if p_require_active and v_lifecycle_status is distinct from 'active' then
    raise exception using errcode = 'P0002', message = 'Household not found or not active.';
  end if;

  -- Governance scope check
  if not private.can_access_household('households.formation.manage', p_organization_id, p_household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- Non-administrators: direct formal leadership + active delegated access
  -- (Phase 6B-9 double-lock). No oversight-scope writes to subordinate households.
  if not private.is_organization_administrator(p_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(p_profile_id, p_organization_id, p_household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;
end;
$$;

revoke all on function private.assert_formation_manage_prereqs(uuid) from public, anon, authenticated;
revoke all on function private.assert_formation_household_write(uuid, uuid, uuid, boolean) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. create_formation_topic (audit access reason)
-- -----------------------------------------------------------------------------

create or replace function public.create_formation_topic(
  p_organization_id              uuid,
  p_title                        text,
  p_source_type                  text    default 'household_topic',
  p_short_title                  text    default null,
  p_topic_code                   text    default null,
  p_description                  text    default null,
  p_objectives                   text    default null,
  p_scripture_reference          text    default null,
  p_recommended_duration_minutes integer default null,
  p_recommended_pastoral_level   text    default null,
  p_sort_order                   integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_title      text;
  v_topic      public.formation_topics%rowtype;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not (
    private.is_organization_administrator(v_profile_id, p_organization_id)
    or private.has_permission('households.formation.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to create formation topics.';
  end if;

  v_title := trim(coalesce(p_title, ''));
  if v_title = '' then
    raise exception using errcode = '22023', message = 'Topic title is required.';
  end if;

  if p_source_type not in (
    'official_formation', 'household_topic', 'scripture_reflection',
    'assembly_follow_up', 'mission_topic', 'special_topic', 'other'
  ) then
    raise exception using errcode = '22023', message = 'Invalid topic source type.';
  end if;

  if p_recommended_pastoral_level is not null and p_recommended_pastoral_level not in (
    'member', 'unit', 'chapter', 'area', 'fraternal'
  ) then
    raise exception using errcode = '22023', message = 'Invalid recommended pastoral level.';
  end if;

  insert into public.formation_topics (
    organization_id, title, short_title, topic_code, description, objectives,
    source_type, scripture_reference, recommended_duration_minutes,
    recommended_pastoral_level, sort_order, is_active,
    created_at, updated_at, created_by_profile_id, updated_by_profile_id
  )
  values (
    p_organization_id, v_title,
    nullif(trim(p_short_title), ''),
    nullif(trim(p_topic_code), ''),
    nullif(trim(p_description), ''),
    nullif(trim(p_objectives), ''),
    p_source_type,
    nullif(trim(p_scripture_reference), ''),
    p_recommended_duration_minutes,
    p_recommended_pastoral_level,
    p_sort_order, true,
    now(), now(), v_profile_id, v_profile_id
  )
  returning * into v_topic;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'formation_topic.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'formation_topic',
    p_entity_id        => v_topic.id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => 'formation_topic_catalog_create',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'topic_id',    v_topic.id,
      'source_type', v_topic.source_type,
      'topic_code',  v_topic.topic_code
    )
  );

  return jsonb_build_object(
    'id',                           v_topic.id,
    'organization_id',              v_topic.organization_id,
    'title',                        v_topic.title,
    'short_title',                  v_topic.short_title,
    'topic_code',                   v_topic.topic_code,
    'description',                  v_topic.description,
    'objectives',                   v_topic.objectives,
    'source_type',                  v_topic.source_type,
    'scripture_reference',          v_topic.scripture_reference,
    'recommended_duration_minutes', v_topic.recommended_duration_minutes,
    'recommended_pastoral_level',   v_topic.recommended_pastoral_level,
    'sort_order',                   v_topic.sort_order,
    'is_active',                    v_topic.is_active,
    'created_at',                   v_topic.created_at
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. assign_household_topic
-- -----------------------------------------------------------------------------

create or replace function public.assign_household_topic(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_topic_id          uuid,
  p_planned_for_date  date    default null,
  p_sequence_number   integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_topic      public.formation_topics%rowtype;
  v_assignment public.household_topic_assignments%rowtype;
begin
  v_profile_id := private.assert_formation_manage_prereqs(p_organization_id);

  perform private.assert_formation_household_write(v_profile_id, p_organization_id, p_household_node_id, true);

  select * into v_topic
  from public.formation_topics
  where id = p_topic_id
    and (organization_id is null or organization_id = p_organization_id);

  if not found or not v_topic.is_active then
    raise exception using errcode = '22023', message = 'Formation topic not found or is inactive.';
  end if;

  if p_planned_for_date is not null and exists (
    select 1
    from public.household_topic_assignments
    where household_node_id = p_household_node_id
      and topic_id = p_topic_id
      and planned_for_date = p_planned_for_date
      and assignment_status = 'planned'
  ) then
    raise exception using errcode = '23505',
      message = 'This topic is already planned for the specified date.';
  end if;

  insert into public.household_topic_assignments (
    organization_id, household_node_id, topic_id, sequence_number,
    planned_for_date, assignment_status, assigned_at, assigned_by_profile_id,
    created_at, updated_at, created_by_profile_id, updated_by_profile_id
  )
  values (
    p_organization_id, p_household_node_id, p_topic_id, p_sequence_number,
    p_planned_for_date, 'planned', now(), v_profile_id,
    now(), now(), v_profile_id, v_profile_id
  )
  returning * into v_assignment;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.assigned',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'assign',
    p_outcome          => 'success',
    p_access_reason    => 'household_formation_topic_assign',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',     v_assignment.id,
      'household_node_id', p_household_node_id,
      'topic_id',          p_topic_id,
      'planned_for_date',  p_planned_for_date,
      'sequence_number',   p_sequence_number
    )
  );

  return jsonb_build_object(
    'assignment_id',     v_assignment.id,
    'household_node_id', v_assignment.household_node_id,
    'topic_id',          v_assignment.topic_id,
    'topic_title',       v_topic.title,
    'topic_code',        v_topic.topic_code,
    'source_type',       v_topic.source_type,
    'assignment_status', v_assignment.assignment_status,
    'planned_for_date',  v_assignment.planned_for_date,
    'sequence_number',   v_assignment.sequence_number,
    'assigned_at',       v_assignment.assigned_at
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. reschedule_household_topic
-- -----------------------------------------------------------------------------

create or replace function public.reschedule_household_topic(
  p_organization_id               uuid,
  p_household_topic_assignment_id uuid,
  p_planned_for_date              date,
  p_reason                        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_assignment public.household_topic_assignments%rowtype;
  v_old_date   date;
begin
  v_profile_id := private.assert_formation_manage_prereqs(p_organization_id);

  if p_planned_for_date is null then
    raise exception using errcode = '22023', message = 'New planned date is required.';
  end if;

  select * into v_assignment
  from public.household_topic_assignments
  where id = p_household_topic_assignment_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Topic assignment not found.';
  end if;

  if v_assignment.assignment_status != 'planned' then
    raise exception using errcode = '22023', message = 'Only planned topic assignments can be rescheduled.';
  end if;

  perform private.assert_formation_household_write(v_profile_id, p_organization_id, v_assignment.household_node_id, true);

  v_old_date := v_assignment.planned_for_date;

  update public.household_topic_assignments
  set planned_for_date          = p_planned_for_date,
      rescheduled_at            = now(),
      rescheduled_by_profile_id = v_profile_id,
      resolution_reason_code    = 'schedule_change',
      resolution_notes          = nullif(trim(p_reason), ''),
      updated_at                = now(),
      updated_by_profile_id     = v_profile_id
  where id = v_assignment.id
  returning * into v_assignment;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.rescheduled',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => 'household_formation_topic_reschedule',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',         v_assignment.id,
      'household_node_id',     v_assignment.household_node_id,
      'topic_id',              v_assignment.topic_id,
      'previous_planned_date', v_old_date,
      'new_planned_date',      p_planned_for_date,
      'reason_code',           'schedule_change'
    )
  );

  return jsonb_build_object(
    'assignment_id',         v_assignment.id,
    'household_node_id',     v_assignment.household_node_id,
    'topic_id',              v_assignment.topic_id,
    'assignment_status',     v_assignment.assignment_status,
    'previous_planned_date', v_old_date,
    'planned_for_date',      v_assignment.planned_for_date,
    'rescheduled_at',        v_assignment.rescheduled_at
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. complete_household_topic (meeting must be an actually completed meeting)
-- -----------------------------------------------------------------------------

create or replace function public.complete_household_topic(
  p_organization_id               uuid,
  p_household_topic_assignment_id uuid,
  p_household_meeting_id          uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_assignment public.household_topic_assignments%rowtype;
  v_meeting    public.household_meetings%rowtype;
begin
  v_profile_id := private.assert_formation_manage_prereqs(p_organization_id);

  if p_household_meeting_id is null then
    raise exception using errcode = '22023', message = 'Household meeting ID is required to record topic completion.';
  end if;

  select * into v_assignment
  from public.household_topic_assignments
  where id = p_household_topic_assignment_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Topic assignment not found.';
  end if;

  if v_assignment.assignment_status = 'completed' then
    raise exception using errcode = '22023', message = 'Topic assignment is already completed.';
  end if;

  if v_assignment.assignment_status != 'planned' then
    raise exception using errcode = '22023', message = 'Only planned topic assignments can be completed.';
  end if;

  perform private.assert_formation_household_write(v_profile_id, p_organization_id, v_assignment.household_node_id, true);

  select * into v_meeting
  from public.household_meetings
  where id = p_household_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found.';
  end if;

  if v_meeting.household_node_id != v_assignment.household_node_id then
    raise exception using errcode = '22023',
      message = 'Household meeting does not belong to the household assigned to this topic.';
  end if;

  if v_meeting.meeting_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'Cannot link a cancelled household meeting.';
  end if;

  if v_meeting.meeting_status != 'completed' then
    raise exception using errcode = '22023',
      message = 'Household meeting must be completed before it can be used as topic completion evidence.';
  end if;

  update public.household_topic_assignments
  set assignment_status              = 'completed',
      completed_at                   = now(),
      completed_by_profile_id        = v_profile_id,
      completed_household_meeting_id = v_meeting.id,
      updated_at                     = now(),
      updated_by_profile_id          = v_profile_id
  where id = v_assignment.id
  returning * into v_assignment;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.completed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'complete',
    p_outcome          => 'success',
    p_access_reason    => 'household_formation_topic_complete',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',                  v_assignment.id,
      'household_node_id',              v_assignment.household_node_id,
      'topic_id',                       v_assignment.topic_id,
      'completed_household_meeting_id', v_meeting.id,
      'meeting_date',                   v_meeting.meeting_date,
      'meeting_status',                 v_meeting.meeting_status
    )
  );

  return jsonb_build_object(
    'assignment_id',                  v_assignment.id,
    'household_node_id',              v_assignment.household_node_id,
    'topic_id',                       v_assignment.topic_id,
    'assignment_status',              v_assignment.assignment_status,
    'completed_at',                   v_assignment.completed_at,
    'completed_household_meeting_id', v_assignment.completed_household_meeting_id,
    'meeting_date',                   v_meeting.meeting_date
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. skip_household_topic
-- -----------------------------------------------------------------------------

create or replace function public.skip_household_topic(
  p_organization_id               uuid,
  p_household_topic_assignment_id uuid,
  p_reason_code                   text default 'not_applicable',
  p_notes                         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_assignment  public.household_topic_assignments%rowtype;
  v_reason_code text;
begin
  v_profile_id := private.assert_formation_manage_prereqs(p_organization_id);

  v_reason_code := coalesce(p_reason_code, 'not_applicable');
  if v_reason_code not in ('schedule_change', 'topic_replaced', 'not_applicable', 'other') then
    raise exception using errcode = '22023', message = 'Invalid resolution reason code.';
  end if;

  select * into v_assignment
  from public.household_topic_assignments
  where id = p_household_topic_assignment_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Topic assignment not found.';
  end if;

  if v_assignment.assignment_status != 'planned' then
    raise exception using errcode = '22023', message = 'Only planned topic assignments can be skipped.';
  end if;

  perform private.assert_formation_household_write(v_profile_id, p_organization_id, v_assignment.household_node_id, true);

  update public.household_topic_assignments
  set assignment_status      = 'skipped',
      skipped_at             = now(),
      skipped_by_profile_id  = v_profile_id,
      resolution_reason_code = v_reason_code,
      resolution_notes       = nullif(trim(p_notes), ''),
      updated_at             = now(),
      updated_by_profile_id  = v_profile_id
  where id = v_assignment.id
  returning * into v_assignment;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.skipped',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'skip',
    p_outcome          => 'success',
    p_access_reason    => 'household_formation_topic_skip',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',          v_assignment.id,
      'household_node_id',      v_assignment.household_node_id,
      'topic_id',               v_assignment.topic_id,
      'resolution_reason_code', v_reason_code
    )
  );

  return jsonb_build_object(
    'assignment_id',          v_assignment.id,
    'household_node_id',      v_assignment.household_node_id,
    'topic_id',               v_assignment.topic_id,
    'assignment_status',      v_assignment.assignment_status,
    'skipped_at',             v_assignment.skipped_at,
    'resolution_reason_code', v_assignment.resolution_reason_code
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. cancel_household_topic_assignment
-- -----------------------------------------------------------------------------

create or replace function public.cancel_household_topic_assignment(
  p_organization_id               uuid,
  p_household_topic_assignment_id uuid,
  p_reason_code                   text default 'schedule_change',
  p_notes                         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_assignment  public.household_topic_assignments%rowtype;
  v_reason_code text;
begin
  v_profile_id := private.assert_formation_manage_prereqs(p_organization_id);

  v_reason_code := coalesce(p_reason_code, 'schedule_change');
  if v_reason_code not in ('schedule_change', 'topic_replaced', 'not_applicable', 'other') then
    raise exception using errcode = '22023', message = 'Invalid resolution reason code.';
  end if;

  select * into v_assignment
  from public.household_topic_assignments
  where id = p_household_topic_assignment_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Topic assignment not found.';
  end if;

  if v_assignment.assignment_status != 'planned' then
    raise exception using errcode = '22023', message = 'Only planned topic assignments can be cancelled.';
  end if;

  perform private.assert_formation_household_write(v_profile_id, p_organization_id, v_assignment.household_node_id, true);

  update public.household_topic_assignments
  set assignment_status       = 'cancelled',
      cancelled_at            = now(),
      cancelled_by_profile_id = v_profile_id,
      resolution_reason_code  = v_reason_code,
      resolution_notes        = nullif(trim(p_notes), ''),
      updated_at              = now(),
      updated_by_profile_id   = v_profile_id
  where id = v_assignment.id
  returning * into v_assignment;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.cancelled',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'cancel',
    p_outcome          => 'success',
    p_access_reason    => 'household_formation_topic_cancel',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',          v_assignment.id,
      'household_node_id',      v_assignment.household_node_id,
      'topic_id',               v_assignment.topic_id,
      'resolution_reason_code', v_reason_code
    )
  );

  return jsonb_build_object(
    'assignment_id',          v_assignment.id,
    'household_node_id',      v_assignment.household_node_id,
    'topic_id',               v_assignment.topic_id,
    'assignment_status',      v_assignment.assignment_status,
    'cancelled_at',           v_assignment.cancelled_at,
    'resolution_reason_code', v_assignment.resolution_reason_code
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. get_household_formation_plan (single topic join, deterministic ordering)
-- -----------------------------------------------------------------------------

create or replace function public.get_household_formation_plan(
  p_organization_id   uuid,
  p_household_node_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id      uuid;
  v_status          text;
  v_next_topic      jsonb;
  v_upcoming_topics jsonb;
  v_last_topic      jsonb;
  v_last_date       date;
  v_planned_count   integer;
  v_completed_count integer;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not (
    private.has_permission('households.formation.view', p_organization_id)
    or private.has_permission('households.formation.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household formation.';
  end if;

  if not private.can_access_household('households.formation.view', p_organization_id, p_household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  v_status := private.compute_household_formation_status(p_household_node_id);

  select
    count(*) filter (where a.assignment_status = 'planned'),
    count(*) filter (where a.assignment_status = 'completed')
  into v_planned_count, v_completed_count
  from public.household_topic_assignments a
  where a.household_node_id = p_household_node_id
    and a.organization_id = p_organization_id;

  -- Up to 5 planned topics in deterministic order; next_topic is the first.
  with planned as (
    select
      a.id                          as assignment_id,
      ft.id                         as topic_id,
      ft.title                      as title,
      ft.short_title                as short_title,
      ft.topic_code                 as topic_code,
      ft.source_type                as source_type,
      ft.scripture_reference        as scripture_reference,
      a.planned_for_date            as planned_for_date,
      a.sequence_number             as sequence_number,
      ft.recommended_duration_minutes as recommended_duration_minutes,
      row_number() over (
        order by a.planned_for_date asc nulls last,
                 a.sequence_number  asc nulls last,
                 a.created_at       asc,
                 a.id               asc
      ) as rn
    from public.household_topic_assignments a
    join public.formation_topics ft on ft.id = a.topic_id
    where a.household_node_id = p_household_node_id
      and a.organization_id = p_organization_id
      and a.assignment_status = 'planned'
  ),
  top5 as (
    select * from planned where rn <= 5
  )
  select
    (
      select jsonb_build_object(
        'assignment_id',                t.assignment_id,
        'topic_id',                     t.topic_id,
        'title',                        t.title,
        'short_title',                  t.short_title,
        'topic_code',                   t.topic_code,
        'source_type',                  t.source_type,
        'scripture_reference',          t.scripture_reference,
        'planned_for_date',             t.planned_for_date,
        'sequence_number',              t.sequence_number,
        'recommended_duration_minutes', t.recommended_duration_minutes
      )
      from top5 t
      where t.rn = 1
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'assignment_id',                t.assignment_id,
            'topic_id',                     t.topic_id,
            'title',                        t.title,
            'short_title',                  t.short_title,
            'topic_code',                   t.topic_code,
            'source_type',                  t.source_type,
            'scripture_reference',          t.scripture_reference,
            'planned_for_date',             t.planned_for_date,
            'sequence_number',              t.sequence_number,
            'recommended_duration_minutes', t.recommended_duration_minutes
          )
          order by t.rn
        )
        from top5 t
      ),
      '[]'::jsonb
    )
  into v_next_topic, v_upcoming_topics;

  select
    jsonb_build_object(
      'assignment_id',                  a.id,
      'topic_id',                       ft.id,
      'title',                          ft.title,
      'short_title',                    ft.short_title,
      'topic_code',                     ft.topic_code,
      'source_type',                    ft.source_type,
      'completed_at',                   a.completed_at,
      'completed_household_meeting_id', a.completed_household_meeting_id,
      'meeting_date',                   m.meeting_date
    ),
    coalesce(m.meeting_date, a.completed_at::date)
  into v_last_topic, v_last_date
  from public.household_topic_assignments a
  join public.formation_topics ft on ft.id = a.topic_id
  left join public.household_meetings m on m.id = a.completed_household_meeting_id
  where a.household_node_id = p_household_node_id
    and a.organization_id = p_organization_id
    and a.assignment_status = 'completed'
  order by a.completed_at desc, a.id desc
  limit 1;

  return jsonb_build_object(
    'household_id',         p_household_node_id,
    'formation_status',     v_status,
    'next_topic',           v_next_topic,
    'upcoming_topics',      v_upcoming_topics,
    'last_completed_topic', v_last_topic,
    'last_completed_date',  v_last_date,
    'planned_count',        coalesce(v_planned_count, 0),
    'completed_count',      coalesce(v_completed_count, 0)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 11. Harden RPC execute privileges (project pattern: authenticated + service_role)
-- -----------------------------------------------------------------------------

revoke all on function public.search_formation_topics(uuid, text, text, text, integer, integer) from public, anon;
revoke all on function public.create_formation_topic(uuid, text, text, text, text, text, text, text, integer, text, integer) from public, anon;
revoke all on function public.assign_household_topic(uuid, uuid, uuid, date, integer) from public, anon;
revoke all on function public.reschedule_household_topic(uuid, uuid, date, text) from public, anon;
revoke all on function public.complete_household_topic(uuid, uuid, uuid) from public, anon;
revoke all on function public.skip_household_topic(uuid, uuid, text, text) from public, anon;
revoke all on function public.cancel_household_topic_assignment(uuid, uuid, text, text) from public, anon;
revoke all on function public.get_household_topic_history(uuid, uuid, integer, integer) from public, anon;
revoke all on function public.get_household_formation_plan(uuid, uuid) from public, anon;

grant execute on function public.search_formation_topics(uuid, text, text, text, integer, integer) to authenticated, service_role;
grant execute on function public.create_formation_topic(uuid, text, text, text, text, text, text, text, integer, text, integer) to authenticated, service_role;
grant execute on function public.assign_household_topic(uuid, uuid, uuid, date, integer) to authenticated, service_role;
grant execute on function public.reschedule_household_topic(uuid, uuid, date, text) to authenticated, service_role;
grant execute on function public.complete_household_topic(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function public.skip_household_topic(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function public.cancel_household_topic_assignment(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function public.get_household_topic_history(uuid, uuid, integer, integer) to authenticated, service_role;
grant execute on function public.get_household_formation_plan(uuid, uuid) to authenticated, service_role;

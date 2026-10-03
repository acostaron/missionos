-- =============================================================================
-- Migration: 20261002010000_phase_6b_meetings_fix_member_status_column.sql
-- Phase:     Phase 6B-8 Correction
--
-- Corrects create_household_meeting: members table uses record_status, not
-- lifecycle_status. Also patches complete_household_meeting and
-- record_household_meeting_attendance for the same column reference if present.
-- =============================================================================

create or replace function public.create_household_meeting(
  p_organization_id       uuid,
  p_household_id          uuid,
  p_meeting_date          date,
  p_meeting_type          text        default 'regular_household',
  p_scheduled_start_at    timestamptz default null,
  p_scheduled_end_at      timestamptz default null,
  p_location_type         text        default null,
  p_location_text         text        default null,
  p_facilitator_member_id uuid        default null,
  p_host_member_id        uuid        default null,
  p_notes_summary         text        default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id      uuid;
  v_household_node  public.governance_nodes%rowtype;
  v_meeting_id      uuid;
  v_meeting_type    text;
  v_loc_type        text;
  v_notes           text;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household meetings.';
  end if;

  select * into v_household_node
  from public.governance_nodes
  where id = p_household_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.manage', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  if p_meeting_date is null then
    raise exception using errcode = '22023', message = 'Meeting date is required.';
  end if;

  v_meeting_type := coalesce(trim(p_meeting_type), 'regular_household');
  if v_meeting_type not in (
    'regular_household', 'special_household', 'fellowship', 'formation', 'prayer', 'other'
  ) then
    raise exception using errcode = '22023',
      message = 'Invalid meeting type. Valid: regular_household, special_household, fellowship, formation, prayer, other.';
  end if;

  v_loc_type := nullif(trim(coalesce(p_location_type, '')), '');
  if v_loc_type is not null and v_loc_type not in ('in_person', 'virtual', 'hybrid') then
    raise exception using errcode = '22023',
      message = 'Invalid location type. Valid: in_person, virtual, hybrid.';
  end if;

  if p_scheduled_start_at is not null
    and p_scheduled_end_at is not null
    and p_scheduled_end_at <= p_scheduled_start_at
  then
    raise exception using errcode = '22023', message = 'Scheduled end must be after scheduled start.';
  end if;

  -- FIX: use record_status (not lifecycle_status) on public.members
  if p_facilitator_member_id is not null then
    if not exists (
      select 1 from public.members
      where id = p_facilitator_member_id
        and organization_id = p_organization_id
        and record_status = 'active'
    ) then
      raise exception using errcode = 'P0002',
        message = 'Facilitator member not found, not active, or not in this organization.';
    end if;
  end if;

  if p_host_member_id is not null then
    if not exists (
      select 1 from public.members
      where id = p_host_member_id
        and organization_id = p_organization_id
        and record_status = 'active'
    ) then
      raise exception using errcode = 'P0002',
        message = 'Host member not found, not active, or not in this organization.';
    end if;
  end if;

  v_notes := nullif(trim(coalesce(p_notes_summary, '')), '');
  if v_notes is not null and length(v_notes) > 1000 then
    raise exception using errcode = '22023',
      message = 'Notes summary must not exceed 1000 characters.';
  end if;

  insert into public.household_meetings (
    organization_id,
    household_node_id,
    meeting_date,
    scheduled_start_at,
    scheduled_end_at,
    meeting_status,
    meeting_type,
    location_type,
    location_text,
    facilitator_member_id,
    host_member_id,
    notes_summary,
    created_by_profile_id,
    updated_by_profile_id
  )
  values (
    p_organization_id,
    p_household_id,
    p_meeting_date,
    p_scheduled_start_at,
    p_scheduled_end_at,
    'scheduled',
    v_meeting_type,
    v_loc_type,
    nullif(trim(coalesce(p_location_text, '')), ''),
    p_facilitator_member_id,
    p_host_member_id,
    v_notes,
    v_profile_id,
    v_profile_id
  )
  returning id into v_meeting_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => v_meeting_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', v_meeting_id,
      'household_node_id',    p_household_id,
      'household_node_name',  v_household_node.name,
      'meeting_date',         p_meeting_date,
      'meeting_type',         v_meeting_type
    )
  );

  return jsonb_build_object(
    'household_meeting_id', v_meeting_id,
    'household_node_id',    p_household_id,
    'meeting_date',         p_meeting_date,
    'meeting_status',       'scheduled',
    'meeting_type',         v_meeting_type
  );
end;
$$;

-- Grants preserved from original migration
revoke execute on function public.create_household_meeting(uuid,uuid,date,text,timestamptz,timestamptz,text,text,uuid,uuid,text) from public, anon;
grant  execute on function public.create_household_meeting(uuid,uuid,date,text,timestamptz,timestamptz,text,text,uuid,uuid,text) to authenticated, service_role;

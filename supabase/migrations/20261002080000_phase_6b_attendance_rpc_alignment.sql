-- Migration: 20261002080000_phase_6b_attendance_rpc_alignment.sql
-- Description: Align record_household_meeting_attendance with canonical table schema and direct servant leader guard

create or replace function public.record_household_meeting_attendance(
  p_organization_id  uuid,
  p_meeting_id       uuid,
  p_attendance       jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id      uuid;
  v_meeting         public.household_meetings%rowtype;
  v_item            jsonb;
  v_member_id       uuid;
  v_status          text;
  v_inserted        integer := 0;
  v_updated         integer := 0;
  v_existing_status text;
  v_any_correction  boolean := false;
  v_summary         jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.attendance.record', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to record attendance.';
  end if;

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.attendance.record', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- DIRECT SERVANT-LEADER RESPONSIBILITY GUARD
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, v_meeting.household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant-leader pastoral responsibility for this household.';
    end if;
  end if;

  -- Future-date guard
  if v_meeting.meeting_date > current_date then
    raise exception using errcode = '23514',
      message = 'Attendance cannot be recorded for a future meeting date.';
  end if;

  if v_meeting.meeting_status = 'cancelled' then
    raise exception using errcode = '23514',
      message = 'Attendance cannot be recorded for a cancelled meeting.';
  end if;

  if p_attendance is null or jsonb_typeof(p_attendance) != 'array' then
    raise exception using errcode = '22023',
      message = 'p_attendance must be a JSON array of {member_id, attendance_status} objects.';
  end if;

  if jsonb_array_length(p_attendance) = 0 then
    raise exception using errcode = '22023',
      message = 'p_attendance array must not be empty.';
  end if;

  for v_item in select * from jsonb_array_elements(p_attendance)
  loop
    begin
      v_member_id := (v_item->>'member_id')::uuid;
    exception when others then
      raise exception using errcode = '22023',
        message = format('Invalid member_id in attendance array: %s', v_item->>'member_id');
    end;

    if v_member_id is null then
      raise exception using errcode = '22023',
        message = 'Each attendance item must include a non-null member_id.';
    end if;

    v_status := trim(v_item->>'attendance_status');
    if v_status not in ('present', 'absent', 'excused') then
      raise exception using errcode = '22023',
        message = format('Invalid attendance_status ''%s''. Valid: present, absent, excused.', v_status);
    end if;

    -- SERVER-SIDE ELIGIBILITY CHECK:
    -- Member must appear in the historical primary-household expected roster
    -- as of the meeting date.
    if not exists (
      select 1
      from private.get_household_expected_roster(
        p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date
      ) r
      where r.member_id = v_member_id
    ) then
      raise exception using errcode = 'P0002',
        message = format(
          'Member %s is not eligible for attendance at this meeting. '
          'Eligible members are those with an active primary household membership '
          'in this household as of %s.',
          v_member_id, v_meeting.meeting_date
        );
    end if;

    -- Check if attendance already exists (correction tracking)
    select attendance_status into v_existing_status
    from public.household_meeting_attendance
    where household_meeting_id = p_meeting_id
      and organization_id = p_organization_id
      and member_id = v_member_id;

    if found then
      update public.household_meeting_attendance
      set
        attendance_status     = v_status,
        updated_at            = now(),
        updated_by_profile_id = v_profile_id
      where household_meeting_id = p_meeting_id
        and organization_id = p_organization_id
        and member_id = v_member_id;

      v_updated := v_updated + 1;
      if v_existing_status != v_status then
        v_any_correction := true;
      end if;
    else
      insert into public.household_meeting_attendance (
        organization_id,
        household_meeting_id,
        member_id,
        attendance_status,
        recorded_at,
        recorded_by_profile_id,
        updated_at,
        updated_by_profile_id
      )
      values (
        p_organization_id,
        p_meeting_id,
        v_member_id,
        v_status,
        now(),
        v_profile_id,
        now(),
        v_profile_id
      );

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  -- Stamp attendance_recorded_at on first recording pass
  update public.household_meetings
  set
    attendance_recorded_at            = coalesce(attendance_recorded_at, now()),
    attendance_recorded_by_profile_id = coalesce(attendance_recorded_by_profile_id, v_profile_id),
    updated_at                        = now(),
    updated_by_profile_id             = v_profile_id
  where id = p_meeting_id;

  v_summary := private.compute_attendance_summary(
    p_meeting_id,
    p_organization_id,
    v_meeting.meeting_date,
    v_meeting.household_node_id
  );

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => case when v_any_correction
                               then 'household_meeting.attendance_corrected'
                               else 'household_meeting.attendance_recorded'
                          end,
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => p_meeting_id,
    p_action           => 'record_attendance',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', p_meeting_id,
      'household_node_id',    v_meeting.household_node_id,
      'meeting_date',         v_meeting.meeting_date,
      'rows_inserted',        v_inserted,
      'rows_updated',         v_updated,
      'has_correction',       v_any_correction,
      'attendance_summary',   v_summary
    )
  );

  return jsonb_build_object(
    'household_meeting_id', p_meeting_id,
    'rows_inserted',        v_inserted,
    'rows_updated',         v_updated,
    'has_correction',       v_any_correction,
    'attendance_summary',   v_summary
  );
end;
$$;

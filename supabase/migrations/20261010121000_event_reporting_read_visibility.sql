-- Migration: 20261010121000_event_reporting_read_visibility.sql
-- Description: Restrict internal event reporting metadata to event managers and enforce strict HTTPS on virtual meeting URLs.

-- 1. Tighten check constraint on public.events to require https:// (rejecting plaintext http://)
alter table public.events drop constraint if exists chk_events_virtual_meeting_url;
alter table public.events add constraint chk_events_virtual_meeting_url
  check (
    virtual_meeting_url is null or (
      virtual_meeting_url ~* '^https://[^\s/$.?#].[^\s]*$'
      and virtual_meeting_url !~* '^(javascript|data):'
      and length(virtual_meeting_url) <= 1000
    )
  );

-- =============================================================================
-- 2. Update private.event_summary_json:
--    Mask include_in_quarterly_report, report_priority, and report_highlight
--    to NULL when the caller lacks event management permissions (can_manage = false).
--    Preserves meeting_type and virtual_meeting_url for all authorized event viewers.
-- =============================================================================

create or replace function private.event_summary_json(p_event public.events)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with present as (
    select a.member_id
    from public.event_attendance a
    where a.event_id = p_event.id and a.removed_at is null
  ),
  expected as (
    select m.id
    from public.members m
    where m.organization_id = p_event.organization_id
      and m.record_status = 'active'
      and m.archived_at is null
      and private.member_in_event_audience(m.organization_id, m.id, p_event.audience_node_id)
  ),
  manage_check as (
    select private.can_manage_event(p_event.organization_id, p_event.id) as can_manage
  )
  select jsonb_build_object(
    'id', p_event.id,
    'event_type', p_event.event_type,
    'title', p_event.title,
    'description', p_event.description,
    'starts_at', p_event.starts_at,
    'ends_at', p_event.ends_at,
    'location_text', p_event.location_text,
    'meeting_type', p_event.meeting_type,
    'virtual_meeting_url', p_event.virtual_meeting_url,
    'include_in_quarterly_report', case when (select can_manage from manage_check) then p_event.include_in_quarterly_report else null end,
    'report_priority', case when (select can_manage from manage_check) then p_event.report_priority else null end,
    'report_highlight', case when (select can_manage from manage_check) then p_event.report_highlight else null end,
    'event_status', p_event.event_status,
    'cancel_reason', p_event.cancel_reason,
    'audience_node_id', p_event.audience_node_id,
    'audience_code', (select n.code from public.governance_nodes n where n.id = p_event.audience_node_id),
    'audience_name', coalesce((select n.name from public.governance_nodes n where n.id = p_event.audience_node_id), 'All members'),
    'audience_type', (select t.code from public.governance_nodes n
                      join public.governance_node_types t on t.id = n.governance_node_type_id
                      where n.id = p_event.audience_node_id),
    'formation_program_id', p_event.formation_program_id,
    'formation_program_name', (select fp.title from public.formation_programs fp where fp.id = p_event.formation_program_id),
    'formation_talk_id', p_event.formation_talk_id,
    'formation_talk_title', (select ft.title from public.formation_talks ft where ft.id = p_event.formation_talk_id),
    'formation_posted_at', p_event.formation_posted_at,
    'expected_count', (select count(*) from expected),
    'present_count', (select count(*) from present),
    'present_expected_count', (select count(*) from present p where p.member_id in (select id from expected)),
    'guest_count', (select count(*) from present p where p.member_id not in (select id from expected)),
    'is_greeter', private.is_event_greeter(p_event.organization_id, p_event.id),
    'can_record', private.can_record_event_attendance(p_event.organization_id, p_event.id),
    'can_manage', (select can_manage from manage_check)
  )
$$;

revoke all on function private.event_summary_json(public.events) from public, anon, authenticated;

-- =============================================================================
-- 3. Update public.create_event to enforce strict https:// on virtual_meeting_url
-- =============================================================================

drop function if exists public.create_event(uuid, text, text, timestamptz, timestamptz, text, text, text, uuid, text, text, boolean, text, text);

create or replace function public.create_event(
  p_organization_id uuid,
  p_event_type text,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_location_text text,
  p_description text default null,
  p_audience_code text default null,
  p_formation_talk_id uuid default null,
  p_meeting_type text default 'in_person',
  p_virtual_meeting_url text default null,
  p_include_in_quarterly_report boolean default false,
  p_report_priority text default 'routine',
  p_report_highlight text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_audience uuid;
  v_program uuid;
  v_title text;
  v_event public.events%rowtype;
  v_virtual_url text;
  v_include_in_quarterly_report boolean;
  v_report_priority text;
  v_report_highlight text;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  select o_audience_node_id, o_formation_program_id, o_title into v_audience, v_program, v_title
  from private.validate_event_fields(p_organization_id, p_event_type, p_title, p_starts_at, p_ends_at, p_audience_code, p_formation_talk_id);

  if not private.caller_can_manage_audience(p_organization_id, v_audience) then
    raise exception using errcode = '42501', message = 'You can only create events for the area, chapter or section you serve.';
  end if;

  -- Validate meeting_type
  if p_meeting_type is null or p_meeting_type not in ('in_person', 'virtual') then
    raise exception using errcode = '22023', message = 'Meeting type must be either in_person or virtual.';
  end if;

  -- Validate virtual_meeting_url (strictly requires https://)
  if p_meeting_type = 'virtual' then
    v_virtual_url := nullif(btrim(coalesce(p_virtual_meeting_url, '')), '');
    if v_virtual_url is not null and (
      v_virtual_url !~* '^https://[^\s/$.?#].[^\s]*$'
      or v_virtual_url ~* '^(javascript|data):'
      or length(v_virtual_url) > 1000
    ) then
      raise exception using errcode = '22023', message = 'Virtual meeting URL must be a valid secure HTTPS web address.';
    end if;
  else
    v_virtual_url := null;
  end if;

  -- Validate reporting fields
  v_include_in_quarterly_report := coalesce(p_include_in_quarterly_report, false);
  v_report_priority := coalesce(p_report_priority, 'routine');
  if v_report_priority not in ('routine', 'ministry_activity', 'major_highlight') then
    raise exception using errcode = '22023', message = 'Report priority must be routine, ministry_activity, or major_highlight.';
  end if;

  v_report_highlight := nullif(btrim(coalesce(p_report_highlight, '')), '');
  if v_report_highlight is not null and length(v_report_highlight) > 2000 then
    raise exception using errcode = '22023', message = 'Report highlight must not exceed 2000 characters.';
  end if;

  if not v_include_in_quarterly_report then
    v_report_priority := 'routine';
    v_report_highlight := null;
  end if;

  insert into public.events (
    organization_id, event_type, title, description, starts_at, ends_at, location_text,
    audience_node_id, formation_program_id, formation_talk_id, event_status,
    meeting_type, virtual_meeting_url,
    include_in_quarterly_report, report_priority, report_highlight,
    created_by_profile_id, updated_by_profile_id
  ) values (
    p_organization_id, p_event_type, v_title, nullif(btrim(coalesce(p_description, '')), ''),
    p_starts_at, p_ends_at, nullif(btrim(coalesce(p_location_text, '')), ''),
    v_audience, v_program, p_formation_talk_id, 'scheduled',
    p_meeting_type, v_virtual_url,
    v_include_in_quarterly_report, v_report_priority, v_report_highlight,
    v_actor, v_actor
  ) returning * into v_event;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => v_event.id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'event_type', v_event.event_type,
      'starts_at', v_event.starts_at,
      'audience_node_id', v_event.audience_node_id,
      'formation_talk_id', v_event.formation_talk_id,
      'meeting_type', v_event.meeting_type,
      'include_in_quarterly_report', v_event.include_in_quarterly_report
    )
  );

  return jsonb_build_object('status', 'success', 'event', private.event_summary_json(v_event));
end;
$$;

revoke all on function public.create_event(uuid, text, text, timestamptz, timestamptz, text, text, text, uuid, text, text, boolean, text, text) from public, anon;
grant execute on function public.create_event(uuid, text, text, timestamptz, timestamptz, text, text, text, uuid, text, text, boolean, text, text) to authenticated;

-- =============================================================================
-- 4. Update public.update_event to enforce strict https:// on virtual_meeting_url
-- =============================================================================

drop function if exists public.update_event(uuid, uuid, text, timestamptz, timestamptz, text, text, text, uuid, text, text, boolean, text, text);

create or replace function public.update_event(
  p_organization_id uuid,
  p_event_id uuid,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_location_text text,
  p_description text default null,
  p_audience_code text default null,
  p_formation_talk_id uuid default null,
  p_meeting_type text default 'in_person',
  p_virtual_meeting_url text default null,
  p_include_in_quarterly_report boolean default false,
  p_report_priority text default 'routine',
  p_report_highlight text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_audience uuid;
  v_program uuid;
  v_title text;
  v_event public.events%rowtype;
  v_virtual_url text;
  v_include_in_quarterly_report boolean;
  v_report_priority text;
  v_report_highlight text;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_manage_event(p_organization_id, v_event.id) then
    raise exception using errcode = '42501', message = 'You can only manage events for the area, chapter or section you serve.';
  end if;
  if v_event.program_run_id is not null then
    raise exception using errcode = '22023', message = 'This is a program session. Change its date, time or place from the program page.';
  end if;

  select o_audience_node_id, o_formation_program_id, o_title into v_audience, v_program, v_title
  from private.validate_event_fields(p_organization_id, v_event.event_type, p_title, p_starts_at, p_ends_at, p_audience_code, p_formation_talk_id);

  if not private.caller_can_manage_audience(p_organization_id, v_audience) then
    raise exception using errcode = '42501', message = 'You can only move events to an area, chapter or section you serve.';
  end if;

  -- Validate meeting_type
  if p_meeting_type is null or p_meeting_type not in ('in_person', 'virtual') then
    raise exception using errcode = '22023', message = 'Meeting type must be either in_person or virtual.';
  end if;

  -- Validate virtual_meeting_url (strictly requires https://)
  if p_meeting_type = 'virtual' then
    v_virtual_url := nullif(btrim(coalesce(p_virtual_meeting_url, '')), '');
    if v_virtual_url is not null and (
      v_virtual_url !~* '^https://[^\s/$.?#].[^\s]*$'
      or v_virtual_url ~* '^(javascript|data):'
      or length(v_virtual_url) > 1000
    ) then
      raise exception using errcode = '22023', message = 'Virtual meeting URL must be a valid secure HTTPS web address.';
    end if;
  else
    v_virtual_url := null;
  end if;

  -- Validate reporting fields
  v_include_in_quarterly_report := coalesce(p_include_in_quarterly_report, false);
  v_report_priority := coalesce(p_report_priority, 'routine');
  if v_report_priority not in ('routine', 'ministry_activity', 'major_highlight') then
    raise exception using errcode = '22023', message = 'Report priority must be routine, ministry_activity, or major_highlight.';
  end if;

  v_report_highlight := nullif(btrim(coalesce(p_report_highlight, '')), '');
  if v_report_highlight is not null and length(v_report_highlight) > 2000 then
    raise exception using errcode = '22023', message = 'Report highlight must not exceed 2000 characters.';
  end if;

  if not v_include_in_quarterly_report then
    v_report_priority := 'routine';
    v_report_highlight := null;
  end if;

  update public.events set
    title = v_title,
    description = nullif(btrim(coalesce(p_description, '')), ''),
    starts_at = p_starts_at,
    ends_at = p_ends_at,
    location_text = nullif(btrim(coalesce(p_location_text, '')), ''),
    audience_node_id = v_audience,
    formation_program_id = v_program,
    formation_talk_id = p_formation_talk_id,
    meeting_type = p_meeting_type,
    virtual_meeting_url = v_virtual_url,
    include_in_quarterly_report = v_include_in_quarterly_report,
    report_priority = v_report_priority,
    report_highlight = v_report_highlight,
    updated_by_profile_id = v_actor,
    updated_at = now()
  where id = v_event.id
  returning * into v_event;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.updated',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => v_event.id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'event_type', v_event.event_type,
      'starts_at', v_event.starts_at,
      'audience_node_id', v_event.audience_node_id,
      'formation_talk_id', v_event.formation_talk_id,
      'meeting_type', v_event.meeting_type,
      'include_in_quarterly_report', v_event.include_in_quarterly_report
    )
  );

  return jsonb_build_object('status', 'success', 'event', private.event_summary_json(v_event));
end;
$$;

revoke all on function public.update_event(uuid, uuid, text, timestamptz, timestamptz, text, text, text, uuid, text, text, boolean, text, text) from public, anon;
grant execute on function public.update_event(uuid, uuid, text, timestamptz, timestamptz, text, text, text, uuid, text, text, boolean, text, text) to authenticated;

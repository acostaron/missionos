-- Pass 9.47: Event Reporting Metadata + In-Person / Virtual
-- 1. Adds meeting_type ('in_person', 'virtual') and virtual_meeting_url.
-- 2. Adds quarterly reporting metadata: include_in_quarterly_report, report_priority, report_highlight.
-- 3. Updates event create/update RPCs and summary projections.

-- =============================================================================
-- 1. Schema Changes
-- =============================================================================

alter table public.events
  add column if not exists meeting_type text not null default 'in_person',
  add column if not exists virtual_meeting_url text null,
  add column if not exists include_in_quarterly_report boolean not null default false,
  add column if not exists report_priority text not null default 'routine',
  add column if not exists report_highlight text null;

-- Constraints
alter table public.events drop constraint if exists chk_events_meeting_type;
alter table public.events add constraint chk_events_meeting_type
  check (
    meeting_type in ('in_person', 'virtual')
    and (meeting_type = 'virtual' or virtual_meeting_url is null)
  );

alter table public.events drop constraint if exists chk_events_virtual_meeting_url;
alter table public.events add constraint chk_events_virtual_meeting_url
  check (
    virtual_meeting_url is null or (
      virtual_meeting_url ~* '^https?://[^\s/$.?#].[^\s]*$'
      and virtual_meeting_url !~* '^(javascript|data):'
      and length(virtual_meeting_url) <= 1000
    )
  );

alter table public.events drop constraint if exists chk_events_report_priority;
alter table public.events add constraint chk_events_report_priority
  check (report_priority in ('routine', 'ministry_activity', 'major_highlight'));

alter table public.events drop constraint if exists chk_events_report_highlight;
alter table public.events add constraint chk_events_report_highlight
  check (report_highlight is null or length(btrim(report_highlight)) <= 2000);

-- Index for future quarterly report lookups
create index if not exists idx_events_org_quarterly_report
  on public.events (organization_id, starts_at)
  where include_in_quarterly_report = true;

-- =============================================================================
-- 2. Updated Event Summary Projection
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
    'include_in_quarterly_report', p_event.include_in_quarterly_report,
    'report_priority', p_event.report_priority,
    'report_highlight', p_event.report_highlight,
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
    'can_manage', private.can_manage_event(p_event.organization_id, p_event.id)
  )
$$;
revoke all on function private.event_summary_json(public.events) from public, anon, authenticated;

-- =============================================================================
-- 3. Public RPC: create_event
-- =============================================================================

drop function if exists public.create_event(uuid, text, text, timestamptz, timestamptz, text, text, text, uuid);

create or replace function public.create_event(
  p_organization_id uuid,
  p_event_type text,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz default null,
  p_location_text text default null,
  p_description text default null,
  p_audience_code text default 'mfc_ny',
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

  -- Validate virtual_meeting_url
  if p_meeting_type = 'virtual' then
    v_virtual_url := nullif(btrim(coalesce(p_virtual_meeting_url, '')), '');
    if v_virtual_url is not null and (
      v_virtual_url !~* '^https?://[^\s/$.?#].[^\s]*$'
      or v_virtual_url ~* '^(javascript|data):'
      or length(v_virtual_url) > 1000
    ) then
      raise exception using errcode = '22023', message = 'Virtual meeting URL must be a valid HTTP or HTTPS web address.';
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
-- 4. Public RPC: update_event
-- =============================================================================

drop function if exists public.update_event(uuid, uuid, text, text, timestamptz, timestamptz, text, text, text, uuid);

create or replace function public.update_event(
  p_organization_id uuid,
  p_event_id uuid,
  p_event_type text,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz default null,
  p_location_text text default null,
  p_description text default null,
  p_audience_code text default 'mfc_ny',
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
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'A cancelled event cannot be edited. Restore it first.';
  end if;
  if v_event.formation_posted_at is not null
     and (p_event_type is distinct from v_event.event_type or p_formation_talk_id is distinct from v_event.formation_talk_id) then
    raise exception using errcode = '22023', message = 'Attendance was already posted to formation records; the event type and talk can no longer change.';
  end if;

  select o_audience_node_id, o_formation_program_id, o_title into v_audience, v_program, v_title
  from private.validate_event_fields(p_organization_id, p_event_type, p_title, p_starts_at, p_ends_at, p_audience_code, p_formation_talk_id);

  if not private.caller_can_manage_audience(p_organization_id, v_audience) then
    raise exception using errcode = '42501', message = 'You can only move events to the area, chapter or section you serve.';
  end if;

  -- Validate meeting_type
  if p_meeting_type is null or p_meeting_type not in ('in_person', 'virtual') then
    raise exception using errcode = '22023', message = 'Meeting type must be either in_person or virtual.';
  end if;

  -- Validate virtual_meeting_url
  if p_meeting_type = 'virtual' then
    v_virtual_url := nullif(btrim(coalesce(p_virtual_meeting_url, '')), '');
    if v_virtual_url is not null and (
      v_virtual_url !~* '^https?://[^\s/$.?#].[^\s]*$'
      or v_virtual_url ~* '^(javascript|data):'
      or length(v_virtual_url) > 1000
    ) then
      raise exception using errcode = '22023', message = 'Virtual meeting URL must be a valid HTTP or HTTPS web address.';
    end if;
  else
    -- Switching or keeping in_person clears virtual_meeting_url
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

  update public.events
  set event_type = p_event_type,
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
      'meeting_type', v_event.meeting_type,
      'include_in_quarterly_report', v_event.include_in_quarterly_report
    )
  );

  return jsonb_build_object('status', 'success', 'event', private.event_summary_json(v_event));
end;
$$;
revoke all on function public.update_event(uuid, uuid, text, text, timestamptz, timestamptz, text, text, text, uuid, text, text, boolean, text, text) from public, anon;
grant execute on function public.update_event(uuid, uuid, text, text, timestamptz, timestamptz, text, text, text, uuid, text, text, boolean, text, text) to authenticated;

-- =============================================================================
-- 5. Public RPC: list_my_events (adds meeting_type and virtual_meeting_url)
-- =============================================================================

create or replace function public.list_my_events(p_organization_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
  v_from timestamptz;
  v_to timestamptz;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    raise exception using errcode = '22023', message = 'Choose a date range of up to 400 days.';
  end if;
  v_from := (p_from::timestamp) at time zone 'America/New_York';
  v_to := ((p_to + 1)::timestamp) at time zone 'America/New_York';

  return coalesce((
    select jsonb_agg(x.j order by x.starts_at)
    from (
      select e.starts_at,
             jsonb_build_object(
               'event_id', e.id,
               'event_type', e.event_type,
               'title', e.title,
               'starts_at', e.starts_at,
               'ends_at', e.ends_at,
               'location_text', e.location_text,
               'meeting_type', e.meeting_type,
               'virtual_meeting_url', e.virtual_meeting_url,
               'event_status', e.event_status,
               'audience_name', an.name,
               'program_title', pr.title,
               'session_number', e.session_number,
               'session_count', pr.session_count,
               'attended', exists (select 1 from public.event_attendance a
                                   where a.event_id = e.id and a.member_id = v_member_id and a.removed_at is null)
                           or exists (select 1 from public.program_participant_attendance pa
                                      join public.program_participants pp on pp.id = pa.participant_id
                                      where pa.event_id = e.id and pp.member_id = v_member_id and pa.removed_at is null)
             ) as j
      from public.events e
      left join public.governance_nodes an on an.id = e.audience_node_id
      left join public.program_runs pr on pr.id = e.program_run_id
      where e.organization_id = p_organization_id
        and e.starts_at >= v_from and e.starts_at < v_to
        and (
          (e.program_run_id is null and private.member_in_event_audience(p_organization_id, v_member_id, e.audience_node_id))
          or (e.program_run_id is not null and exists (
                select 1 from public.program_participants pp
                where pp.program_run_id = e.program_run_id and pp.member_id = v_member_id
                  and pp.participant_status = 'registered'))
          or exists (select 1 from public.event_attendance a
                     where a.event_id = e.id and a.member_id = v_member_id and a.removed_at is null)
        )
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_events(uuid, date, date) from public, anon;
grant execute on function public.list_my_events(uuid, date, date) to authenticated;

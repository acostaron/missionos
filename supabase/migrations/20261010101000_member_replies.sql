-- =============================================================================
-- Migration: 20261010101000_member_replies.sql
-- MissionOS Pass 9.28 (written by Claude, 2026-10-21) — run after 20261010100000.
-- Ron (2026-10-21): on My Events, members reply Attending / Not attending to their upcoming household meetings,
-- assemblies and formation teachings (buttons on each item). Household leaders, event organizers / admins and
-- leaders in scope see the replies.
--   * table public.member_replies (one reply per member per event / household meeting; RLS on, RPC access only);
--   * public.set_my_reply      — the member's own reply (null response clears it); upcoming, scheduled items only;
--   * public.list_my_replies   — the member's replies to upcoming items;
--   * public.get_event_replies — names + counts, for event managers / attendance recorders / admins / events.view in scope;
--   * public.get_meeting_replies — names + counts, for the household's leaders (same rule as recording attendance)
--     and for leaders with households.meetings.view over that household.
-- =============================================================================

create table if not exists public.member_replies (
  id                   uuid primary key default gen_random_uuid(),
  organization_id      uuid not null references public.organizations(id) on delete restrict,
  member_id            uuid not null references public.members(id) on delete restrict,
  event_id             uuid null references public.events(id) on delete cascade,
  household_meeting_id uuid null references public.household_meetings(id) on delete cascade,
  response             text not null check (response in ('attending', 'not_attending')),
  responded_at         timestamptz not null default now(),
  check ((event_id is null) <> (household_meeting_id is null))
);
create unique index if not exists uq_member_replies_event
  on public.member_replies (event_id, member_id) where event_id is not null;
create unique index if not exists uq_member_replies_meeting
  on public.member_replies (household_meeting_id, member_id) where household_meeting_id is not null;
create index if not exists ix_member_replies_member on public.member_replies (organization_id, member_id);
alter table public.member_replies enable row level security;
revoke all on public.member_replies from public, anon, authenticated;

-- Can this member see / reply to this event? (same rule as list_my_events)
create or replace function private.member_can_reply_event(p_organization_id uuid, p_member_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event_id and e.organization_id = p_organization_id
      and (
        (e.program_run_id is null and private.member_in_event_audience(p_organization_id, p_member_id, e.audience_node_id))
        or (e.program_run_id is not null and exists (
              select 1 from public.program_participants pp
              where pp.program_run_id = e.program_run_id and pp.member_id = p_member_id
                and pp.participant_status = 'registered'))
      )
  )
$$;
revoke all on function private.member_can_reply_event(uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.set_my_reply(
  p_organization_id      uuid,
  p_event_id             uuid default null,
  p_household_meeting_id uuid default null,
  p_response             text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member   uuid;
  v_response text := nullif(btrim(coalesce(p_response, '')), '');
  v_event    public.events%rowtype;
  v_meeting  public.household_meetings%rowtype;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  if (p_event_id is null) = (p_household_meeting_id is null) then
    raise exception using errcode = '22023', message = 'Choose one event or one household meeting.';
  end if;
  if v_response is not null and v_response not in ('attending', 'not_attending') then
    raise exception using errcode = '22023', message = 'Reply must be Attending or Not attending.';
  end if;

  if p_event_id is not null then
    select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
    if v_event.id is null or not private.member_can_reply_event(p_organization_id, v_member, p_event_id) then
      raise exception using errcode = 'P0002', message = 'Event not found.';
    end if;
    if v_event.event_status <> 'scheduled' or v_event.starts_at <= now() then
      raise exception using errcode = '22023', message = 'Replies close when the event starts.';
    end if;
    if v_response is null then
      delete from public.member_replies where event_id = p_event_id and member_id = v_member;
    else
      insert into public.member_replies (organization_id, member_id, event_id, response)
      values (p_organization_id, v_member, p_event_id, v_response)
      on conflict (event_id, member_id) where event_id is not null
      do update set response = excluded.response, responded_at = now();
    end if;
  else
    select * into v_meeting from public.household_meetings
     where id = p_household_meeting_id and organization_id = p_organization_id;
    if v_meeting.id is null or not exists (
         select 1 from public.household_memberships hm
         where hm.organization_id = p_organization_id and hm.member_id = v_member
           and hm.household_node_id = v_meeting.household_node_id
           and hm.membership_status in ('active', 'temporary')
           and (hm.effective_to is null or hm.effective_to >= current_date)) then
      raise exception using errcode = 'P0002', message = 'Household meeting not found.';
    end if;
    if v_meeting.meeting_status <> 'scheduled'
       or coalesce(v_meeting.scheduled_start_at, (v_meeting.meeting_date + 1)::timestamp at time zone 'America/New_York') <= now() then
      raise exception using errcode = '22023', message = 'Replies close when the meeting starts.';
    end if;
    if v_response is null then
      delete from public.member_replies where household_meeting_id = p_household_meeting_id and member_id = v_member;
    else
      insert into public.member_replies (organization_id, member_id, household_meeting_id, response)
      values (p_organization_id, v_member, p_household_meeting_id, v_response)
      on conflict (household_meeting_id, member_id) where household_meeting_id is not null
      do update set response = excluded.response, responded_at = now();
    end if;
  end if;

  return jsonb_build_object('status', 'saved', 'response', v_response);
end;
$$;
revoke all on function public.set_my_reply(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.set_my_reply(uuid, uuid, uuid, text) to authenticated;

create or replace function public.list_my_replies(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member uuid;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'event_id', r.event_id,
             'household_meeting_id', r.household_meeting_id,
             'response', r.response,
             'responded_at', r.responded_at))
    from public.member_replies r
    left join public.events e on e.id = r.event_id
    left join public.household_meetings hm on hm.id = r.household_meeting_id
    where r.organization_id = p_organization_id and r.member_id = v_member
      and (e.starts_at >= now() - interval '1 day' or hm.meeting_date >= current_date - 1)
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_replies(uuid) from public, anon;
grant execute on function public.list_my_replies(uuid) to authenticated;

-- Shared shape: { attending: [...], not_attending: [...], counts: {attending, not_attending} }
create or replace function private.replies_summary(p_event_id uuid, p_household_meeting_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select jsonb_build_object(
    'attending', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', m.id, 'member_number', m.member_number,
                                          'display_name', m.display_name, 'responded_at', r.responded_at)
                       order by lower(m.sort_name), m.id)
      from public.member_replies r join public.members m on m.id = r.member_id
      where r.response = 'attending'
        and (r.event_id = p_event_id or r.household_meeting_id = p_household_meeting_id)), '[]'::jsonb),
    'not_attending', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', m.id, 'member_number', m.member_number,
                                          'display_name', m.display_name, 'responded_at', r.responded_at)
                       order by lower(m.sort_name), m.id)
      from public.member_replies r join public.members m on m.id = r.member_id
      where r.response = 'not_attending'
        and (r.event_id = p_event_id or r.household_meeting_id = p_household_meeting_id)), '[]'::jsonb),
    'counts', jsonb_build_object(
      'attending', (select count(*) from public.member_replies r where r.response = 'attending'
                      and (r.event_id = p_event_id or r.household_meeting_id = p_household_meeting_id)),
      'not_attending', (select count(*) from public.member_replies r where r.response = 'not_attending'
                      and (r.event_id = p_event_id or r.household_meeting_id = p_household_meeting_id)))
  )
$$;
revoke all on function private.replies_summary(uuid, uuid) from public, anon, authenticated;

create or replace function public.get_event_replies(p_organization_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile uuid := private.current_profile_id();
  v_event   public.events%rowtype;
begin
  if v_profile is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
  if v_event.id is null or not private.has_organization_access(p_organization_id) then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not (
       private.is_organization_administrator(v_profile, p_organization_id)
       or private.can_manage_event(p_organization_id, p_event_id)
       or private.can_record_event_attendance(p_organization_id, p_event_id)
       or (private.has_permission('events.view', p_organization_id)
           and v_event.audience_node_id is not null
           and private.caller_covers_node(p_organization_id, v_event.audience_node_id))
     ) then
    raise exception using errcode = '42501', message = 'You do not have permission to see replies for this event.';
  end if;
  return private.replies_summary(p_event_id, null);
end;
$$;
revoke all on function public.get_event_replies(uuid, uuid) from public, anon;
grant execute on function public.get_event_replies(uuid, uuid) to authenticated;

create or replace function public.get_meeting_replies(p_organization_id uuid, p_household_meeting_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile uuid := private.current_profile_id();
  v_member  uuid;
  v_meeting public.household_meetings%rowtype;
begin
  if v_profile is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select * into v_meeting from public.household_meetings
   where id = p_household_meeting_id and organization_id = p_organization_id;
  if v_meeting.id is null or not private.has_organization_access(p_organization_id) then
    raise exception using errcode = 'P0002', message = 'Household meeting not found.';
  end if;
  v_member := private.current_member_id(p_organization_id);
  if not (
       (v_member is not null
        and private.member_can_edit_household_topics(p_organization_id, v_member, v_profile, v_meeting.household_node_id))
       or (private.has_permission('households.meetings.view', p_organization_id)
           and private.can_access_governance_node('households.meetings.view', p_organization_id, v_meeting.household_node_id))
     ) then
    raise exception using errcode = '42501', message = 'You do not have permission to see replies for this meeting.';
  end if;
  return private.replies_summary(null, p_household_meeting_id);
end;
$$;
revoke all on function public.get_meeting_replies(uuid, uuid) from public, anon;
grant execute on function public.get_meeting_replies(uuid, uuid) to authenticated;

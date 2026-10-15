-- =============================================================================
-- Migration: 20261010087000_event_qr_check_in.sql
-- MissionOS Pass 9.12 (written by Claude, 2026-10-16)
-- Ron: on the event day, check members in by scanning the QR code on their phone (My Card) or ID card,
-- and warn when the same QR has already been scanned (conference kit and T-shirt are given at check-in).
-- Ron's decisions (2026-10-16):
--   * One check-in = kit and T-shirt given. A second scan warns "already checked in".
--   * Multi-day events: members check in once PER DAY; the kit warning spans all days of the event.
--   * Payment for paid events comes in the next pass (fee + paid/partial/waived recorded in the app;
--     unpaid -> warn, collect, then check in).
-- Design:
--   * public.event_check_ins: one row per member per event day (who scanned, when).
--   * The first check-in of a member also records event attendance (event_attendance, method 'qr'), so the
--     attendance list, counts and formation posting keep working unchanged.
--   * Already checked in today = a check-in row for today, or attendance ticked on the list today.
--   * QR validation reuses public.resolve_member_qr (signature, replaced/revoked cards, inactive members).
-- No existing function is changed.
-- =============================================================================

create table if not exists public.event_check_ins (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid not null references public.events(id) on delete restrict,
  member_id              uuid not null references public.members(id) on delete restrict,
  check_in_date          date not null,
  check_in_method        text not null default 'qr' check (check_in_method in ('qr', 'tick')),
  recorded_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  recorded_at            timestamptz not null default now(),
  constraint uq_event_check_ins_day unique (event_id, member_id, check_in_date)
);
create index if not exists idx_event_check_ins_event_day on public.event_check_ins (event_id, check_in_date);
alter table public.event_check_ins enable row level security;
-- No policies: read and written only through the functions below.
revoke all on public.event_check_ins from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Event days (New York dates)
-- -----------------------------------------------------------------------------
create or replace function private.event_ny_first_day(p_event public.events)
returns date language sql stable
as $$ select (p_event.starts_at at time zone 'America/New_York')::date $$;

create or replace function private.event_ny_last_day(p_event public.events)
returns date language sql stable
as $$ select (coalesce(p_event.ends_at, p_event.starts_at) at time zone 'America/New_York')::date $$;

revoke all on function private.event_ny_first_day(public.events) from public, anon, authenticated;
revoke all on function private.event_ny_last_day(public.events) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Scan
-- -----------------------------------------------------------------------------
create or replace function public.scan_event_check_in(
  p_organization_id uuid,
  p_event_id        uuid,
  p_payload         text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor     uuid := private.current_profile_id();
  v_event     public.events%rowtype;
  v_today     date := (now() at time zone 'America/New_York')::date;
  v_qr        jsonb;
  v_member_id uuid;
  v_member    jsonb;
  v_prev_at   timestamptz;
  v_att       public.event_attendance%rowtype;
  v_first     boolean := false;
  v_days      integer;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'You cannot check members in for this event.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'This event was cancelled.';
  end if;
  if v_today < private.event_ny_first_day(v_event) then
    raise exception using errcode = '22023',
      message = format('Check-in opens on %s.', to_char(private.event_ny_first_day(v_event), 'FMDay, FMMonth FMDD'));
  end if;
  if v_today > private.event_ny_last_day(v_event) then
    raise exception using errcode = '22023',
      message = 'This event is over. Use the attendance list to correct attendance.';
  end if;

  v_qr := public.resolve_member_qr(p_organization_id, p_payload);
  if not coalesce((v_qr->>'valid')::boolean, false) then
    return jsonb_build_object('result', 'invalid', 'reason', coalesce(v_qr->>'reason', 'not_a_member_qr'),
                              'member', case when v_qr ? 'member_id' then jsonb_build_object(
                                'member_id', v_qr->'member_id', 'display_name', v_qr->'display_name',
                                'member_number', v_qr->'member_number', 'photo_path', v_qr->'photo_path') end);
  end if;

  v_member_id := (v_qr->>'member_id')::uuid;
  v_member := jsonb_build_object('member_id', v_member_id, 'display_name', v_qr->'display_name',
                                 'member_number', v_qr->'member_number', 'photo_path', v_qr->'photo_path');

  select * into v_att from public.event_attendance a
  where a.event_id = p_event_id and a.member_id = v_member_id and a.removed_at is null;

  -- already checked in today (scanned, or ticked on the list today)?
  select c.recorded_at into v_prev_at from public.event_check_ins c
  where c.event_id = p_event_id and c.member_id = v_member_id and c.check_in_date = v_today;
  if v_prev_at is null and v_att.id is not null
     and (v_att.recorded_at at time zone 'America/New_York')::date = v_today then
    v_prev_at := v_att.recorded_at;
  end if;
  if v_prev_at is not null then
    return jsonb_build_object('result', 'already_checked_in', 'member', v_member,
                              'checked_in_at', v_prev_at, 'kit_given_at', v_att.recorded_at);
  end if;

  begin
    insert into public.event_check_ins (organization_id, event_id, member_id, check_in_date, check_in_method,
                                        recorded_by_profile_id)
    values (p_organization_id, p_event_id, v_member_id, v_today, 'qr', v_actor);
  exception when unique_violation then
    -- scanned at the same moment at another desk
    select c.recorded_at into v_prev_at from public.event_check_ins c
    where c.event_id = p_event_id and c.member_id = v_member_id and c.check_in_date = v_today;
    return jsonb_build_object('result', 'already_checked_in', 'member', v_member,
                              'checked_in_at', v_prev_at, 'kit_given_at', v_att.recorded_at);
  end;

  if v_att.id is null then
    insert into public.event_attendance (organization_id, event_id, member_id, check_in_method, recorded_by_profile_id)
    values (p_organization_id, p_event_id, v_member_id, 'qr', v_actor);
    v_first := true;
  end if;

  v_days := private.event_ny_last_day(v_event) - private.event_ny_first_day(v_event) + 1;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.check_in.qr',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => p_event_id,
    p_action           => 'record_attendance',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('member_id', v_member_id, 'check_in_date', v_today,
                                             'first_check_in', v_first));

  return jsonb_build_object(
    'result',         'checked_in',
    'member',         v_member,
    'checked_in_at',  now(),
    'first_check_in', v_first,                       -- true: give the kit and T-shirt now
    'kit_given_at',   case when v_first then null else v_att.recorded_at end,
    'multi_day',      v_days > 1);
end;
$$;
revoke all on function public.scan_event_check_in(uuid, uuid, text) from public, anon;
grant execute on function public.scan_event_check_in(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Desk summary: today's count and the latest check-ins
-- -----------------------------------------------------------------------------
create or replace function public.get_event_check_in_summary(p_organization_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event public.events%rowtype;
  v_today date := (now() at time zone 'America/New_York')::date;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'You cannot check members in for this event.';
  end if;

  return jsonb_build_object(
    'today',            v_today,
    'first_day',        private.event_ny_first_day(v_event),
    'last_day',         private.event_ny_last_day(v_event),
    'event_status',     v_event.event_status,
    'checked_in_today', (
      select count(distinct x.member_id) from (
        select c.member_id from public.event_check_ins c where c.event_id = p_event_id and c.check_in_date = v_today
        union
        select a.member_id from public.event_attendance a
        where a.event_id = p_event_id and a.removed_at is null
          and (a.recorded_at at time zone 'America/New_York')::date = v_today) x),
    'attended_total',   (select count(*) from public.event_attendance a where a.event_id = p_event_id and a.removed_at is null),
    'recent', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', r.member_id, 'display_name', m.display_name,
                                          'member_number', m.member_number, 'recorded_at', r.recorded_at)
                       order by r.recorded_at desc)
      from (select c.member_id, c.recorded_at from public.event_check_ins c
            where c.event_id = p_event_id and c.check_in_date = v_today
            order by c.recorded_at desc limit 10) r
      join public.members m on m.id = r.member_id), '[]'::jsonb));
end;
$$;
revoke all on function public.get_event_check_in_summary(uuid, uuid) from public, anon;
grant execute on function public.get_event_check_in_summary(uuid, uuid) to authenticated;

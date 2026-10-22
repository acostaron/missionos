-- =============================================================================
-- Migration: 20261010107000_activity_page.sql
-- MissionOS Pass 9.35 (written by Claude, 2026-10-21) — run after 20261010106000.
-- Ron (2026-10-21): an admin page (instead of running SQL) to see, for any day, what reminders went out, who
-- logged in / opened the app, and who opened / did not open the emails and notifications.
--   * reminder_deliveries.opened_at / clicked_at:
--       email — opened (tracking image, approximate: some mail apps load images automatically, some block them)
--               and clicked (the "Open My Events" button);
--       push  — shown on the device and tapped.
--     Recorded by the send-reminders edge function through track_reminder_event (service role).
--   * app_activity_days: one row per person per New York day they open MissionOS (record_my_app_open, called by the
--     app; also keeps profiles.last_active_at).
--   * get_activity_report(org, day): organization administrators only.
-- No existing function is replaced.
-- =============================================================================

alter table public.reminder_deliveries
  add column if not exists opened_at  timestamptz null,
  add column if not exists clicked_at timestamptz null;
create index if not exists ix_reminder_deliveries_sent on public.reminder_deliveries (organization_id, sent_at);

create table if not exists public.app_activity_days (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  activity_date   date not null,
  first_at        timestamptz not null default now(),
  last_at         timestamptz not null default now(),
  opens           integer not null default 1,
  primary key (organization_id, profile_id, activity_date)
);
create index if not exists ix_app_activity_days_day on public.app_activity_days (organization_id, activity_date);
alter table public.app_activity_days enable row level security;
revoke all on public.app_activity_days from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 1. Opens / clicks (edge function, service role)
-- -----------------------------------------------------------------------------
create or replace function public.track_reminder_event(p_delivery_id uuid, p_event text)
returns boolean
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if p_event not in ('open', 'click') then
    return false;
  end if;
  update public.reminder_deliveries
     set opened_at  = coalesce(opened_at, now()),
         clicked_at = case when p_event = 'click' then coalesce(clicked_at, now()) else clicked_at end
   where id = p_delivery_id and status = 'sent';
  return found;
end;
$$;
revoke all on function public.track_reminder_event(uuid, text) from public, anon, authenticated;
grant execute on function public.track_reminder_event(uuid, text) to service_role;

-- -----------------------------------------------------------------------------
-- 2. App opened (signed-in users; the app calls this at most every 15 minutes)
-- -----------------------------------------------------------------------------
create or replace function public.record_my_app_open(p_organization_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_profile uuid := private.current_profile_id();
begin
  if v_profile is null or not private.has_organization_access(p_organization_id) then
    return;
  end if;
  insert into public.app_activity_days (organization_id, profile_id, activity_date)
  values (p_organization_id, v_profile, (now() at time zone 'America/New_York')::date)
  on conflict (organization_id, profile_id, activity_date) do update
    set last_at = now(), opens = public.app_activity_days.opens + 1;
  update public.profiles set last_active_at = now() where id = v_profile;
end;
$$;
revoke all on function public.record_my_app_open(uuid) from public, anon;
grant execute on function public.record_my_app_open(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Report (organization administrators)
-- -----------------------------------------------------------------------------
create or replace function private.profile_member_for(p_organization_id uuid, p_profile_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select l.member_id from public.profile_member_links l
  where l.organization_id = p_organization_id and l.profile_id = p_profile_id
    and l.link_type = 'self' and l.link_status = 'verified' and l.ended_at is null
  order by l.is_primary desc, l.verified_at desc nulls last
  limit 1
$$;
revoke all on function private.profile_member_for(uuid, uuid) from public, anon, authenticated;

create or replace function public.get_activity_report(p_organization_id uuid, p_day date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile uuid := private.current_profile_id();
  v_day     date := coalesce(p_day, (now() at time zone 'America/New_York')::date);
begin
  if v_profile is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if not private.is_organization_administrator(v_profile, p_organization_id) then
    raise exception using errcode = '42501', message = 'Only administrators can see the activity page.';
  end if;

  return jsonb_build_object(
    'day', v_day,
    'settings', (select jsonb_build_object('email_mode', s.email_mode, 'push_mode', s.push_mode,
                                           'daily_email_limit', s.daily_email_limit)
                 from public.organization_reminder_settings s where s.organization_id = p_organization_id),

    -- reminders sent / attempted that New York day
    'deliveries', coalesce((
      select jsonb_agg(jsonb_build_object(
               'delivery_id', d.id, 'member_id', m.id, 'display_name', m.display_name, 'member_number', m.member_number,
               'channel', d.channel, 'reminder_type', d.reminder_type, 'item_kind', d.item_kind,
               'item_title', it->>'title', 'group_name', it->>'group_name', 'days_before', d.days_before,
               'status', d.status, 'attempts', d.attempts, 'sent_at', d.sent_at,
               'opened_at', d.opened_at, 'clicked_at', d.clicked_at, 'error', d.error_text)
             order by d.channel, lower(m.sort_name), d.id)
      from public.reminder_deliveries d
      join public.members m on m.id = d.member_id
      cross join lateral (select private.reminder_item_json(d.item_kind, d.item_id, d.member_id) as it) x
      where d.organization_id = p_organization_id
        and (coalesce(d.sent_at, d.claimed_at) at time zone 'America/New_York')::date = v_day), '[]'::jsonb),

    -- people who opened the app that day
    'app_opens', coalesce((
      select jsonb_agg(jsonb_build_object(
               'profile_id', a.profile_id, 'member_id', pm.member_id,
               'display_name', coalesce(m.display_name, p.display_name), 'member_number', m.member_number,
               'first_at', a.first_at, 'last_at', a.last_at, 'opens', a.opens)
             order by a.last_at desc)
      from public.app_activity_days a
      join public.profiles p on p.id = a.profile_id
      cross join lateral (select private.profile_member_for(p_organization_id, a.profile_id) as member_id) pm
      left join public.members m on m.id = pm.member_id
      where a.organization_id = p_organization_id and a.activity_date = v_day), '[]'::jsonb),

    -- every linked member account: last sign-in and last time in the app
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'member_id', m.id, 'display_name', m.display_name, 'member_number', m.member_number,
               'last_sign_in_at', u.last_sign_in_at, 'last_active_at', p.last_active_at,
               'push_devices', (select count(*) from public.push_subscriptions ps
                                where ps.member_id = m.id and ps.disabled_at is null))
             order by greatest(coalesce(p.last_active_at, 'epoch'), coalesce(u.last_sign_in_at, 'epoch')) desc, lower(m.sort_name))
      from public.profile_member_links l
      join public.members m on m.id = l.member_id and m.record_status = 'active' and m.archived_at is null
      join public.profiles p on p.id = l.profile_id
      left join auth.users u on u.id = l.profile_id
      where l.organization_id = p_organization_id and l.link_type = 'self' and l.link_status = 'verified'
        and l.is_primary and l.ended_at is null), '[]'::jsonb),

    'members_active', (select count(*) from public.members m where m.organization_id = p_organization_id
                         and m.record_status = 'active' and m.archived_at is null and not m.is_deceased)
  );
end;
$$;
revoke all on function public.get_activity_report(uuid, date) from public, anon;
grant execute on function public.get_activity_report(uuid, date) to authenticated;

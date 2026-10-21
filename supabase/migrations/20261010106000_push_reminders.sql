-- =============================================================================
-- Migration: 20261010106000_push_reminders.sql
-- MissionOS Pass 9.34 (written by Claude, 2026-10-21) — run after 20261010105000.
-- Ron (2026-10-21): push notifications in the app, on the same schedule as the email reminders
-- (3 days and 1 day before; reminder to Attending / registered, "Will you attend?" to members who have not replied).
--   * push_subscriptions: one row per device (browser / installed app) a member turns notifications on for;
--   * organization_reminder_settings.push_mode: 'off' (default) | 'test' (only test_member_id) | 'on';
--   * claim_due_push_reminders (service role): who is due, with their devices; no daily limit (push is free);
--     the same delivery log as email (channel 'push'), once per person / item / day;
--   * record_push_results (service role): devices that are gone (404 / 410) or keep failing are switched off;
--   * My Profile: save / remove this device, status.
-- VAPID keys live only in Edge Function secrets (set by Ron with a local script); the public key is served by
-- send-reminders (GET ?push_public_key=1).
-- Guarded: replaces private.run_reminders only if unchanged from 20261010105000.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'run_reminders';
  if v_md5 is distinct from '46ff148685bd04e2d245c082f2ad9a72' then
    raise exception 'STOP: private.run_reminders differs from 20261010105000 (md5 %).', v_md5;
  end if;
end;
$guard$;

alter table public.organization_reminder_settings
  add column if not exists push_mode text not null default 'off';
alter table public.organization_reminder_settings drop constraint if exists organization_reminder_settings_push_mode_check;
alter table public.organization_reminder_settings add constraint organization_reminder_settings_push_mode_check
  check (push_mode in ('off', 'test', 'on'));

create table if not exists public.push_subscriptions (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  member_id        uuid not null references public.members(id) on delete cascade,
  profile_id       uuid null references public.profiles(id) on delete set null,
  endpoint         text not null unique check (endpoint ~ '^https://' and length(endpoint) <= 1000),
  p256dh           text not null check (length(p256dh) between 20 and 200),
  auth             text not null check (length(auth) between 8 and 100),
  device_label     text null check (device_label is null or length(device_label) <= 80),
  created_at       timestamptz not null default now(),
  last_success_at  timestamptz null,
  failure_count    integer not null default 0,
  disabled_at      timestamptz null
);
create index if not exists ix_push_subscriptions_member on public.push_subscriptions (member_id) where disabled_at is null;
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 1. My devices
-- -----------------------------------------------------------------------------
create or replace function public.save_my_push_subscription(
  p_organization_id uuid,
  p_endpoint        text,
  p_p256dh          text,
  p_auth            text,
  p_device_label    text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_member uuid;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  if p_endpoint is null or p_endpoint !~ '^https://' or length(p_endpoint) > 1000
     or length(coalesce(p_p256dh, '')) not between 20 and 200 or length(coalesce(p_auth, '')) not between 8 and 100 then
    raise exception using errcode = '22023', message = 'This device could not be set up for notifications.';
  end if;
  insert into public.push_subscriptions (organization_id, member_id, profile_id, endpoint, p256dh, auth, device_label)
  values (p_organization_id, v_member, private.current_profile_id(), p_endpoint, p_p256dh, p_auth,
          left(nullif(btrim(coalesce(p_device_label, '')), ''), 80))
  on conflict (endpoint) do update
    set organization_id = excluded.organization_id, member_id = excluded.member_id, profile_id = excluded.profile_id,
        p256dh = excluded.p256dh, auth = excluded.auth, device_label = excluded.device_label,
        failure_count = 0, disabled_at = null;
  return public.get_my_push_status(p_organization_id);
end;
$$;

create or replace function public.remove_my_push_subscription(p_organization_id uuid, p_endpoint text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_member uuid;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  delete from public.push_subscriptions where endpoint = p_endpoint and member_id = v_member;
  return public.get_my_push_status(p_organization_id);
end;
$$;

create or replace function public.get_my_push_status(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_member uuid;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  return jsonb_build_object(
    'devices', (select count(*) from public.push_subscriptions s where s.member_id = v_member and s.disabled_at is null),
    'push_active', exists (select 1 from public.organization_reminder_settings s
                           where s.organization_id = p_organization_id and s.push_mode = 'on'));
end;
$$;

revoke all on function public.save_my_push_subscription(uuid, text, text, text, text) from public, anon;
grant execute on function public.save_my_push_subscription(uuid, text, text, text, text) to authenticated;
revoke all on function public.remove_my_push_subscription(uuid, text) from public, anon;
grant execute on function public.remove_my_push_subscription(uuid, text) to authenticated;
revoke all on function public.get_my_push_status(uuid) from public, anon;
grant execute on function public.get_my_push_status(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Who is due (same rules as email, without the email-only filters)
-- -----------------------------------------------------------------------------
create or replace function private.reminder_people(p_organization_id uuid, p_today date)
returns table (
  member_id     uuid,
  item_kind     text,
  item_id       uuid,
  days_before   smallint,
  reminder_type text,
  reply         text,
  registered    boolean
)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with ev as (
    select e.*, ((e.starts_at at time zone 'America/New_York')::date - p_today)::smallint as d
    from public.events e
    where e.organization_id = p_organization_id and e.event_status = 'scheduled' and e.starts_at > now()
      and ((e.starts_at at time zone 'America/New_York')::date - p_today) in (1, 3)
  ),
  ev_people as (
    select ev.id as item_id, ev.d, m.id as member_id
    from ev join public.members m on m.organization_id = p_organization_id
    where ev.program_run_id is null
      and private.member_in_event_audience(p_organization_id, m.id, ev.audience_node_id)
    union
    select ev.id, ev.d, pp.member_id
    from ev join public.program_participants pp
      on pp.program_run_id = ev.program_run_id and pp.participant_status = 'registered'
    union
    select ev.id, ev.d, r.member_id
    from ev join public.event_registrations r on r.event_id = ev.id and r.cancelled_at is null
  ),
  mt as (
    select hm.*, (coalesce((hm.scheduled_start_at at time zone 'America/New_York')::date, hm.meeting_date) - p_today)::smallint as d
    from public.household_meetings hm
    where hm.organization_id = p_organization_id and hm.meeting_status = 'scheduled'
      and (coalesce((hm.scheduled_start_at at time zone 'America/New_York')::date, hm.meeting_date) - p_today) in (1, 3)
  ),
  mt_people as (
    select distinct mt.id as item_id, mt.d, hms.member_id
    from mt join public.household_memberships hms
      on hms.household_node_id = mt.household_node_id and hms.organization_id = p_organization_id
     and hms.membership_status in ('active', 'temporary')
     and (hms.effective_to is null or hms.effective_to >= p_today + mt.d)
  ),
  people as (
    select 'event'::text as item_kind, p.item_id, p.d, p.member_id,
           (select r.response from public.member_replies r where r.event_id = p.item_id and r.member_id = p.member_id) as reply,
           exists (select 1 from public.event_registrations x where x.event_id = p.item_id and x.member_id = p.member_id
                   and x.cancelled_at is null) as registered
    from ev_people p
    union all
    select 'meeting', p.item_id, p.d, p.member_id,
           (select r.response from public.member_replies r where r.household_meeting_id = p.item_id and r.member_id = p.member_id),
           false
    from mt_people p
  )
  select p.member_id, p.item_kind, p.item_id, p.d,
         case when p.reply = 'attending' or p.registered then 'reminder' else 'nudge' end,
         p.reply, p.registered
  from people p
  join public.members m on m.id = p.member_id
  where coalesce(p.reply, '') <> 'not_attending'
    and m.record_status = 'active' and m.archived_at is null and not m.is_deceased
$$;
revoke all on function private.reminder_people(uuid, date) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Claim / results (edge function, service role only)
-- -----------------------------------------------------------------------------
create or replace function public.claim_due_push_reminders(p_limit integer default 200, p_today date default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_now_ny timestamp := now() at time zone 'America/New_York';
  v_today  date := coalesce(p_today, v_now_ny::date);
  v_set    public.organization_reminder_settings%rowtype;
  v_out    jsonb := '[]'::jsonb;
  v_batch  jsonb;
  v_limit  integer := least(greatest(coalesce(p_limit, 200), 1), 500);
begin
  if p_today is null and extract(hour from v_now_ny) < 9 then
    return v_out;
  end if;

  for v_set in select * from public.organization_reminder_settings s
               where s.push_mode <> 'off' and (p_today is null or s.push_mode = 'test') loop
    continue when jsonb_array_length(v_out) >= v_limit;
    with c as (
      select c.* from private.reminder_people(v_set.organization_id, v_today) c
      where (v_set.push_mode = 'on' or c.member_id = v_set.test_member_id)
        and exists (select 1 from public.push_subscriptions ps where ps.member_id = c.member_id and ps.disabled_at is null)
        and not exists (select 1 from public.reminder_deliveries d
                        where d.member_id = c.member_id and d.item_kind = c.item_kind and d.item_id = c.item_id
                          and d.days_before = c.days_before and d.channel = 'push'
                          and (d.status = 'sent'
                               or (d.status = 'claimed' and d.claimed_at > now() - interval '30 minutes')
                               or (d.status = 'failed' and d.attempts >= 3)))
      order by (c.reminder_type = 'reminder') desc, c.days_before, c.item_id, c.member_id
      limit v_limit - jsonb_array_length(v_out)
    ),
    ins as (
      insert into public.reminder_deliveries as d (organization_id, member_id, item_kind, item_id, days_before, channel,
                                                   reminder_type, status)
      select v_set.organization_id, c.member_id, c.item_kind, c.item_id, c.days_before, 'push', c.reminder_type, 'claimed'
      from c
      on conflict (member_id, item_kind, item_id, days_before, channel) do update
        set status = 'claimed', attempts = d.attempts + 1, claimed_at = now(), reminder_type = excluded.reminder_type,
            error_text = null
        where d.status = 'failed' or (d.status = 'claimed' and d.claimed_at <= now() - interval '30 minutes')
      returning d.id, d.member_id, d.item_kind, d.item_id, d.days_before, d.reminder_type
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'delivery_id', ins.id, 'item_kind', ins.item_kind, 'item_id', ins.item_id,
             'days_before', ins.days_before, 'reminder_type', ins.reminder_type,
             'reply', c.reply, 'registered', c.registered,
             'item', private.reminder_item_json(ins.item_kind, ins.item_id, ins.member_id),
             'subscriptions', (select coalesce(jsonb_agg(jsonb_build_object('subscription_id', ps.id, 'endpoint', ps.endpoint,
                                                                            'p256dh', ps.p256dh, 'auth', ps.auth)), '[]'::jsonb)
                               from public.push_subscriptions ps
                               where ps.member_id = ins.member_id and ps.disabled_at is null))), '[]'::jsonb)
      into v_batch
    from ins
    join c on c.member_id = ins.member_id and c.item_kind = ins.item_kind and c.item_id = ins.item_id
          and c.days_before = ins.days_before;
    v_out := v_out || v_batch;
  end loop;
  return v_out;
end;
$$;
revoke all on function public.claim_due_push_reminders(integer, date) from public, anon, authenticated;
grant execute on function public.claim_due_push_reminders(integer, date) to service_role;

-- p_results: [{ subscription_id, ok: boolean, gone: boolean }]; gone (404 / 410) or 5 failures in a row = switched off
create or replace function public.record_push_results(p_results jsonb)
returns integer
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare v_n integer;
begin
  update public.push_subscriptions s
     set last_success_at = case when (x->>'ok')::boolean then now() else s.last_success_at end,
         failure_count   = case when (x->>'ok')::boolean then 0 else s.failure_count + 1 end,
         disabled_at     = case when coalesce((x->>'gone')::boolean, false)
                                     or (not (x->>'ok')::boolean and s.failure_count + 1 >= 5) then now()
                                else s.disabled_at end
    from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) x
   where s.id = (x->>'subscription_id')::uuid;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.record_push_results(jsonb) from public, anon, authenticated;
grant execute on function public.record_push_results(jsonb) to service_role;

-- -----------------------------------------------------------------------------
-- 4. Hourly caller also runs when only push is on
-- -----------------------------------------------------------------------------
create or replace function private.run_reminders()
returns integer
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare v_secret text;
begin
  if not exists (select 1 from public.organization_reminder_settings s where s.email_mode <> 'off' or s.push_mode <> 'off') then
    return 0;
  end if;
  select ds.decrypted_secret into v_secret
  from vault.decrypted_secrets ds where ds.name = 'missionos_reminders_secret';
  if v_secret is null then
    raise warning 'reminders: secret missing';
    return 0;
  end if;
  perform net.http_post(
    url := 'https://ypbtszvshofbsbvjfvmr.supabase.co/functions/v1/send-reminders',
    body := jsonb_build_object('mode', 'scheduled'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-reminders-secret', v_secret),
    timeout_milliseconds := 120000
  );
  return 1;
end;
$$;

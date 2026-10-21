-- =============================================================================
-- Migration: 20261010105000_email_reminders.sql
-- MissionOS Pass 9.33 (written by Claude, 2026-10-21) — run after 20261010104000.
-- Ron (2026-10-21): email reminders 3 days and 1 day before household meetings and events, at 9:00 AM New York.
--   * Reminder: members who replied Attending, or are registered for the event.
--   * Nudge ("Will you attend?"): members who could attend (event audience / registered program participants /
--     household members) and have not replied. Not attending = no email.
--   * Members can switch reminders off (My Profile) or with the unsubscribe link in every email.
--   * Push notifications and text messages come later on the same delivery log (channel column).
-- How it runs:
--   * pg_cron calls private.run_reminders() every hour at :05; it posts to the send-reminders edge function with a
--     random secret generated here into Vault ('missionos_reminders_secret', never in the repo).
--   * The edge function checks the secret (verify_reminders_secret), claims what is due
--     (claim_due_reminders — nothing before 9:00 AM New York; each person / item / day only once; reminders before
--     nudges; at most daily_email_limit per New York day), sends through Resend and records the result
--     (complete_reminders).
--   * organization_reminder_settings.email_mode: 'off' (default) | 'test' (only test_member_id) | 'on'.
--     In 'test' mode a run may pretend another day (test_today) so the test member gets a real email now.
-- No existing function is replaced.
-- =============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- -----------------------------------------------------------------------------
-- 1. Secret (Vault) and check
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'missionos_reminders_secret') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'missionos_reminders_secret',
      'MissionOS: shared secret for the scheduled email reminders (Pass 9.33).'
    );
  end if;
end;
$$;

create or replace function public.verify_reminders_secret(p_secret text)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog'
as $$
  select p_secret is not null
     and length(p_secret) >= 32
     and exists (select 1 from vault.decrypted_secrets ds
                 where ds.name = 'missionos_reminders_secret'
                   and ds.decrypted_secret = p_secret)
$$;
revoke all on function public.verify_reminders_secret(text) from public, anon, authenticated;
grant execute on function public.verify_reminders_secret(text) to service_role;

-- -----------------------------------------------------------------------------
-- 2. Tables
-- -----------------------------------------------------------------------------
create table if not exists public.organization_reminder_settings (
  organization_id       uuid primary key references public.organizations(id) on delete cascade,
  email_mode            text not null default 'off' check (email_mode in ('off', 'test', 'on')),
  test_member_id        uuid null references public.members(id) on delete set null,
  daily_email_limit     integer not null default 90 check (daily_email_limit between 0 and 50000),
  updated_at            timestamptz not null default now()
);
alter table public.organization_reminder_settings enable row level security;
revoke all on public.organization_reminder_settings from public, anon, authenticated;

create table if not exists public.member_reminder_preferences (
  member_id             uuid primary key references public.members(id) on delete cascade,
  organization_id       uuid not null references public.organizations(id) on delete cascade,
  email_enabled         boolean not null default true,
  unsubscribe_token     uuid not null default gen_random_uuid() unique,
  updated_at            timestamptz not null default now(),
  updated_by_profile_id uuid null references public.profiles(id) on delete set null
);
alter table public.member_reminder_preferences enable row level security;
revoke all on public.member_reminder_preferences from public, anon, authenticated;

create table if not exists public.reminder_deliveries (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations(id) on delete cascade,
  member_id           uuid not null references public.members(id) on delete cascade,
  item_kind           text not null check (item_kind in ('event', 'meeting')),
  item_id             uuid not null,
  days_before         smallint not null check (days_before in (1, 3)),
  channel             text not null default 'email' check (channel in ('email', 'push', 'sms')),
  reminder_type       text not null check (reminder_type in ('reminder', 'nudge')),
  status              text not null default 'claimed' check (status in ('claimed', 'sent', 'failed')),
  attempts            integer not null default 1,
  claimed_at          timestamptz not null default now(),
  sent_at             timestamptz null,
  provider_message_id text null check (provider_message_id is null or length(provider_message_id) <= 120),
  error_text          text null check (error_text is null or length(error_text) <= 300),
  constraint uq_reminder_deliveries unique (member_id, item_kind, item_id, days_before, channel)
);
create index if not exists ix_reminder_deliveries_org_day on public.reminder_deliveries (organization_id, claimed_at);
alter table public.reminder_deliveries enable row level security;
revoke all on public.reminder_deliveries from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Who is due
-- -----------------------------------------------------------------------------
-- The member's email for ministry messages (primary first), or null
create or replace function private.member_reminder_email(p_member_id uuid)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select e.email_address from public.member_emails e
  where e.member_id = p_member_id and e.allows_ministry_email
    and (e.effective_to_at is null or e.effective_to_at > now())
    and e.email_address like '%_@_%._%'
  order by e.is_primary desc, e.effective_from_at desc
  limit 1
$$;
revoke all on function private.member_reminder_email(uuid) from public, anon, authenticated;

-- Everything due on New York day p_today (3 days or 1 day before), before de-duplication
create or replace function private.reminder_candidates(p_organization_id uuid, p_today date)
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
    and not exists (select 1 from public.member_reminder_preferences pr where pr.member_id = p.member_id and not pr.email_enabled)
    and private.member_reminder_email(p.member_id) is not null
$$;
revoke all on function private.reminder_candidates(uuid, date) from public, anon, authenticated;

-- Details shown in the email
create or replace function private.reminder_item_json(p_item_kind text, p_item_id uuid, p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_e  public.events%rowtype;
  v_m  public.household_meetings%rowtype;
  v_st jsonb;
begin
  if p_item_kind = 'event' then
    select * into v_e from public.events where id = p_item_id;
    v_st := private.event_payment_status(v_e, p_member_id);
    return jsonb_build_object(
      'title', v_e.title, 'starts_at', v_e.starts_at, 'ends_at', v_e.ends_at, 'location_text', v_e.location_text,
      'group_name', (select n.name from public.governance_nodes n where n.id = v_e.audience_node_id),
      'registration_open', v_e.registration_open,
      'donation_pending', case when v_st->>'status' in ('unpaid', 'partial') then (v_st->>'balance')::numeric end);
  end if;
  select * into v_m from public.household_meetings where id = p_item_id;
  return jsonb_build_object(
    'title', 'Household meeting', 'starts_at', v_m.scheduled_start_at, 'meeting_date', v_m.meeting_date,
    'ends_at', v_m.scheduled_end_at, 'location_text', v_m.location_text,
    'group_name', (select n.name from public.governance_nodes n where n.id = v_m.household_node_id),
    'registration_open', false, 'donation_pending', null);
end;
$$;
revoke all on function private.reminder_item_json(text, uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. Claim / complete / unsubscribe (edge function, service role only)
-- -----------------------------------------------------------------------------
-- p_today null = today in New York, and nothing is claimed before 9:00 AM New York.
-- p_today given (a test run "as if today were …") = only organizations in 'test' mode, i.e. only the test member.
create or replace function public.claim_due_reminders(p_limit integer default 100, p_today date default null)
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
  v_room   integer;
  v_out    jsonb := '[]'::jsonb;
  v_batch  jsonb;
  v_limit  integer := least(greatest(coalesce(p_limit, 100), 1), 100);
begin
  if p_today is null and extract(hour from v_now_ny) < 9 then
    return v_out;
  end if;

  for v_set in select * from public.organization_reminder_settings s
               where s.email_mode <> 'off' and (p_today is null or s.email_mode = 'test') loop
    -- room left today (New York day) under the daily limit
    select greatest(v_set.daily_email_limit - count(*), 0)::integer into v_room
    from public.reminder_deliveries d
    where d.organization_id = v_set.organization_id and d.channel = 'email' and d.status in ('claimed', 'sent')
      and (d.claimed_at at time zone 'America/New_York')::date = v_today;
    v_room := least(v_room, v_limit - jsonb_array_length(v_out));
    continue when v_room <= 0;

    with c as (
      select c.* from private.reminder_candidates(v_set.organization_id, v_today) c
      where (v_set.email_mode = 'on' or c.member_id = v_set.test_member_id)
        and not exists (select 1 from public.reminder_deliveries d
                        where d.member_id = c.member_id and d.item_kind = c.item_kind and d.item_id = c.item_id
                          and d.days_before = c.days_before and d.channel = 'email'
                          and (d.status = 'sent'
                               or (d.status = 'claimed' and d.claimed_at > now() - interval '30 minutes')
                               or (d.status = 'failed' and d.attempts >= 3)))
      order by (c.reminder_type = 'reminder') desc, c.days_before, c.item_id, c.member_id
      limit v_room
    ),
    ins as (
      insert into public.reminder_deliveries as d (organization_id, member_id, item_kind, item_id, days_before, channel,
                                                   reminder_type, status)
      select v_set.organization_id, c.member_id, c.item_kind, c.item_id, c.days_before, 'email', c.reminder_type, 'claimed'
      from c
      on conflict (member_id, item_kind, item_id, days_before, channel) do update
        set status = 'claimed', attempts = d.attempts + 1, claimed_at = now(), reminder_type = excluded.reminder_type,
            error_text = null
        where d.status = 'failed' or (d.status = 'claimed' and d.claimed_at <= now() - interval '30 minutes')
      returning d.id, d.member_id, d.item_kind, d.item_id, d.days_before, d.reminder_type
    ),
    prefs as (
      insert into public.member_reminder_preferences (member_id, organization_id)
      select distinct ins.member_id, v_set.organization_id from ins
      on conflict (member_id) do nothing
      returning member_id, unsubscribe_token
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'delivery_id', ins.id, 'item_kind', ins.item_kind, 'item_id', ins.item_id,
             'days_before', ins.days_before, 'reminder_type', ins.reminder_type,
             'reply', c.reply, 'registered', c.registered,
             'email', private.member_reminder_email(ins.member_id),
             'name', coalesce(nullif(btrim(m.preferred_name), ''), m.display_name),
             'unsubscribe_token', coalesce((select pr.unsubscribe_token from public.member_reminder_preferences pr
                                            where pr.member_id = ins.member_id), prefs.unsubscribe_token),
             'item', private.reminder_item_json(ins.item_kind, ins.item_id, ins.member_id))), '[]'::jsonb)
      into v_batch
    from ins
    join c on c.member_id = ins.member_id and c.item_kind = ins.item_kind and c.item_id = ins.item_id
          and c.days_before = ins.days_before
    join public.members m on m.id = ins.member_id
    left join prefs on prefs.member_id = ins.member_id;
    v_out := v_out || v_batch;
  end loop;
  return v_out;
end;
$$;
revoke all on function public.claim_due_reminders(integer, date) from public, anon, authenticated;
grant execute on function public.claim_due_reminders(integer, date) to service_role;

-- p_results: [{ delivery_id, status: 'sent' | 'failed', provider_message_id?, error? }]
create or replace function public.complete_reminders(p_results jsonb)
returns integer
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare v_n integer;
begin
  update public.reminder_deliveries d
     set status = case when x->>'status' = 'sent' then 'sent' else 'failed' end,
         sent_at = case when x->>'status' = 'sent' then now() end,
         provider_message_id = left(x->>'provider_message_id', 120),
         error_text = left(x->>'error', 300)
    from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) x
   where d.id = (x->>'delivery_id')::uuid and d.status = 'claimed';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.complete_reminders(jsonb) from public, anon, authenticated;
grant execute on function public.complete_reminders(jsonb) to service_role;

create or replace function public.reminder_unsubscribe(p_token uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare v_member uuid;
begin
  update public.member_reminder_preferences
     set email_enabled = false, updated_at = now(), updated_by_profile_id = null
   where unsubscribe_token = p_token
  returning member_id into v_member;
  return jsonb_build_object('unsubscribed', v_member is not null);
end;
$$;
revoke all on function public.reminder_unsubscribe(uuid) from public, anon, authenticated;
grant execute on function public.reminder_unsubscribe(uuid) to service_role;

-- -----------------------------------------------------------------------------
-- 5. My Profile: my reminder setting
-- -----------------------------------------------------------------------------
create or replace function public.get_my_reminder_preferences(p_organization_id uuid)
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
    'email_enabled', coalesce((select pr.email_enabled from public.member_reminder_preferences pr where pr.member_id = v_member), true),
    'has_email', private.member_reminder_email(v_member) is not null,
    'reminders_active', exists (select 1 from public.organization_reminder_settings s
                                where s.organization_id = p_organization_id and s.email_mode = 'on'));
end;
$$;
revoke all on function public.get_my_reminder_preferences(uuid) from public, anon;
grant execute on function public.get_my_reminder_preferences(uuid) to authenticated;

create or replace function public.set_my_reminder_preferences(p_organization_id uuid, p_email_enabled boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_member uuid;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  insert into public.member_reminder_preferences (member_id, organization_id, email_enabled, updated_by_profile_id)
  values (v_member, p_organization_id, coalesce(p_email_enabled, true), private.current_profile_id())
  on conflict (member_id) do update
    set email_enabled = excluded.email_enabled, updated_at = now(), updated_by_profile_id = excluded.updated_by_profile_id;
  return public.get_my_reminder_preferences(p_organization_id);
end;
$$;
revoke all on function public.set_my_reminder_preferences(uuid, boolean) from public, anon;
grant execute on function public.set_my_reminder_preferences(uuid, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Scheduled caller: every hour at :05 (the claim waits for 9:00 AM New York)
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
  if not exists (select 1 from public.organization_reminder_settings s where s.email_mode <> 'off') then
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
revoke all on function private.run_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'missionos-reminders') then
    perform cron.unschedule('missionos-reminders');
  end if;
  perform cron.schedule('missionos-reminders', '5 * * * *', 'select private.run_reminders()');
end;
$$;

-- =============================================================================
-- Migration: 20261010077000_topic_library_auto_sync.sql
-- MissionOS Pass 9.3 (written by Claude, 2026-10-15)
-- Automatic monthly copy of MFC topics into the Household Library (Ron's choice).
--
--   * pg_cron runs private.run_topic_library_sync() daily at 14:00 UTC (10:00 New York
--     in daylight time) on days 20–31 and 1–5 of each month — the window in which MFC posts
--     the next month's topics.
--   * It calls the sync-topic-library edge function (pg_net) in "ingest" mode for every
--     organization that already uses the library. New or changed pages arrive as
--     "Awaiting approval" copies; nothing is shown to members until a manager approves.
--   * The call is authenticated with a random secret generated here into Vault
--     (never in the repo). The edge function checks it via verify_topic_sync_secret().
--   * Every ingest run (scheduled or manual) is logged in topic_library_sync_runs;
--     list_topic_library now returns the last run to managers.
-- =============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- -----------------------------------------------------------------------------
-- 1. Secret (Vault)
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'missionos_topic_sync_secret') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'missionos_topic_sync_secret',
      'MissionOS: shared secret for the scheduled Household Library sync (Pass 9.3).'
    );
  end if;
end;
$$;

create or replace function public.verify_topic_sync_secret(p_secret text)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog'
as $$
  select p_secret is not null
     and length(p_secret) >= 32
     and exists (select 1 from vault.decrypted_secrets ds
                 where ds.name = 'missionos_topic_sync_secret'
                   and ds.decrypted_secret = p_secret)
$$;
revoke all on function public.verify_topic_sync_secret(text) from public, anon, authenticated;
grant execute on function public.verify_topic_sync_secret(text) to service_role;

-- -----------------------------------------------------------------------------
-- 2. Run log
-- -----------------------------------------------------------------------------
create table if not exists public.topic_library_sync_runs (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references public.organizations(id) on delete cascade,
  trigger_source        text not null check (trigger_source in ('scheduled', 'manual')),
  ran_at                timestamptz not null default now(),
  newest_month          text null,
  new_count             integer not null default 0,
  changed_count         integer not null default 0,
  unchanged_count       integer not null default 0,
  failed_count          integer not null default 0,
  run_by_profile_id     uuid null references public.profiles(id) on delete set null
);
create index if not exists idx_topic_sync_runs_org_ran
  on public.topic_library_sync_runs (organization_id, ran_at desc);
alter table public.topic_library_sync_runs enable row level security;
revoke all on table public.topic_library_sync_runs from anon, authenticated;

create or replace function public.record_topic_library_sync_run(
  p_organization_id uuid,
  p_trigger_source  text,
  p_newest_month    text,
  p_new_count       integer,
  p_changed_count   integer,
  p_unchanged_count integer,
  p_failed_count    integer,
  p_run_by_profile_id uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_id uuid;
begin
  insert into public.topic_library_sync_runs (
    organization_id, trigger_source, newest_month, new_count, changed_count,
    unchanged_count, failed_count, run_by_profile_id)
  values (
    p_organization_id, p_trigger_source, p_newest_month, coalesce(p_new_count, 0), coalesce(p_changed_count, 0),
    coalesce(p_unchanged_count, 0), coalesce(p_failed_count, 0), p_run_by_profile_id)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.record_topic_library_sync_run(uuid, text, text, integer, integer, integer, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.record_topic_library_sync_run(uuid, text, text, integer, integer, integer, integer, uuid)
  to service_role;

-- -----------------------------------------------------------------------------
-- 3. Scheduled caller
-- -----------------------------------------------------------------------------
create or replace function private.run_topic_library_sync()
returns integer
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_secret text;
  v_org    uuid;
  v_calls  integer := 0;
begin
  select ds.decrypted_secret into v_secret
  from vault.decrypted_secrets ds where ds.name = 'missionos_topic_sync_secret';
  if v_secret is null then
    raise warning 'topic library sync: secret missing';
    return 0;
  end if;

  for v_org in
    select distinct ft.organization_id
    from public.formation_topics ft
    where ft.series_code is not null and ft.organization_id is not null
  loop
    perform net.http_post(
      url := 'https://ypbtszvshofbsbvjfvmr.supabase.co/functions/v1/sync-topic-library',
      body := jsonb_build_object('organization_id', v_org, 'mode', 'ingest'),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-sync-secret', v_secret),
      timeout_milliseconds := 120000
    );
    v_calls := v_calls + 1;
  end loop;
  return v_calls;
end;
$$;
revoke all on function private.run_topic_library_sync() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'missionos-topic-library-sync') then
    perform cron.unschedule('missionos-topic-library-sync');
  end if;
  perform cron.schedule(
    'missionos-topic-library-sync',
    '0 14 20-31,1-5 * *',
    'select private.run_topic_library_sync()'
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. list_topic_library: add last_sync for managers
-- -----------------------------------------------------------------------------
create or replace function public.list_topic_library(
  p_organization_id uuid,
  p_series_code     text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_manage boolean;
begin
  if not private.can_read_topic_library(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have access to the Household Library.';
  end if;
  v_manage := private.can_manage_topic_library(p_organization_id);

  return jsonb_build_object(
    'can_manage', v_manage,
    'pending_review_count', case when v_manage then (
        select count(*)::integer from public.formation_topic_content_versions v
        where v.organization_id = p_organization_id and v.review_status = 'pending') else 0 end,
    'last_sync', case when v_manage then (
        select jsonb_build_object(
                 'ran_at', r.ran_at, 'trigger_source', r.trigger_source, 'newest_month', r.newest_month,
                 'new_count', r.new_count, 'changed_count', r.changed_count,
                 'unchanged_count', r.unchanged_count, 'failed_count', r.failed_count)
        from public.topic_library_sync_runs r
        where r.organization_id = p_organization_id
        order by r.ran_at desc limit 1) else null end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'topic_id',       ft.id,
               'title',          ft.title,
               'topic_code',     ft.topic_code,
               'series_code',    ft.series_code,
               'series_title',   ft.series_title,
               'topic_month',    ft.topic_month,
               'material_kind',  ft.material_kind,
               'source_url',     ft.source_url,
               'has_content',    av.id is not null,
               'copied_at',      av.source_fetched_at,
               'has_pending',    case when v_manage then pv.id is not null else false end)
             order by ft.topic_month desc,
                      case ft.material_kind
                        when 'household_topic' then 1 when 'family_household_topic' then 2
                        when 'date_night_topic' then 3 when 'personal_sharing_guide' then 4
                        when 'chapter_teaching' then 5 else 6 end,
                      ft.title)
      from public.formation_topics ft
      left join public.formation_topic_content_versions av
        on av.topic_id = ft.id and av.review_status = 'approved'
      left join lateral (
        select v.id from public.formation_topic_content_versions v
        where v.topic_id = ft.id and v.review_status = 'pending' limit 1) pv on true
      where ft.organization_id = p_organization_id
        and ft.series_code is not null
        and (p_series_code is null or ft.series_code = p_series_code)
        and (v_manage or av.id is not null)
    ), '[]'::jsonb));
end;
$$;
revoke all on function public.list_topic_library(uuid, text) from public, anon;
grant execute on function public.list_topic_library(uuid, text) to authenticated;

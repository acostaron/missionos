-- =============================================================================
-- Migration: 20261010115000_support_documents.sql
-- MissionOS Pass 9.44 — Library Support: FAQs and Help Files from Google Drive
--
-- Adds a fourth Library tab "Support" for FAQs, help files, user guides and
-- onboarding material synchronized automatically from Google Drive folder:
-- 0APp9Lbib-DrLUk9PVA
--
-- Access Model:
--   * View: All authenticated users with active organization access.
--   * Manage: Organization administrators only.
--   * Storage: Private bucket "support-documents", signed URLs verified via
--     public.can_read_support_document(name).
--   * Sync: Nightly pg_cron job at 07:30 UTC plus manual "Sync now" for admins,
--     sharing Google Workspace credentials via sync-official-documents edge function.
--
-- Preserves existing official MFC documents and configurations unchanged.
-- =============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------
create table if not exists public.support_document_settings (
  organization_id       uuid primary key references public.organizations(id) on delete cascade,
  drive_folder_id       text null check (drive_folder_id is null or drive_folder_id ~ '^[A-Za-z0-9_-]{10,100}$'),
  updated_at            timestamptz not null default now(),
  updated_by_profile_id uuid null references public.profiles(id) on delete set null
);
alter table public.support_document_settings enable row level security;
revoke all on public.support_document_settings from public, anon, authenticated;

-- Configure initial production Support folder for MFCNY
insert into public.support_document_settings (organization_id, drive_folder_id)
values ('22efefb6-2858-4629-ace6-66ea4e20cfdf', '0APp9Lbib-DrLUk9PVA')
on conflict (organization_id) do update
  set drive_folder_id = excluded.drive_folder_id;

create table if not exists public.support_documents (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations(id) on delete cascade,
  drive_file_id       text not null,
  title               text not null,
  category            text not null default 'General',
  folder_path         text null,
  source_mime_type    text not null,
  stored_mime_type    text not null,
  file_extension      text not null,
  drive_modified_at   timestamptz not null,
  drive_md5           text null,
  storage_path        text null,          -- null until the first copy is made
  file_size           bigint null,
  copied_modified_at  timestamptz null,   -- drive_modified_at of the stored copy
  copied_md5          text null,
  copied_at           timestamptz null,
  first_seen_at       timestamptz not null default now(),
  unique (organization_id, drive_file_id)
);
create index if not exists ix_support_documents_org on public.support_documents (organization_id, category, title);
alter table public.support_documents enable row level security;
revoke all on public.support_documents from public, anon, authenticated;

create table if not exists public.support_document_sync_runs (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations(id) on delete cascade,
  trigger_source    text not null check (trigger_source in ('scheduled', 'manual')),
  ran_at            timestamptz not null default now(),
  listed_count      integer not null default 0,
  new_count         integer not null default 0,
  updated_count     integer not null default 0,
  removed_count     integer not null default 0,
  skipped_count     integer not null default 0,
  failed_count      integer not null default 0,
  pending_count     integer not null default 0,
  error_text        text null
);
create index if not exists ix_support_document_sync_runs on public.support_document_sync_runs (organization_id, ran_at desc);
alter table public.support_document_sync_runs enable row level security;
revoke all on public.support_document_sync_runs from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Authorization Helpers
-- -----------------------------------------------------------------------------
create or replace function private.can_view_support_documents(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.current_profile_id() is not null
     and private.has_organization_access(p_organization_id);
$$;
revoke all on function private.can_view_support_documents(uuid) from public, anon, authenticated;

-- Navigation tab access check
create or replace function public.get_support_documents_access(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select jsonb_build_object(
    'can_view',   coalesce(private.can_view_support_documents(p_organization_id), false),
    'can_manage', private.current_profile_id() is not null
                  and coalesce(private.is_organization_administrator(private.current_profile_id(), p_organization_id), false)
  );
$$;
revoke all on function public.get_support_documents_access(uuid) from public, anon;
grant execute on function public.get_support_documents_access(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Document Listing & Folder Configuration
-- -----------------------------------------------------------------------------
create or replace function public.list_support_documents(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_manage boolean;
begin
  if not private.can_view_support_documents(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have access to Support documents.';
  end if;
  v_manage := private.is_organization_administrator(private.current_profile_id(), p_organization_id);

  return jsonb_build_object(
    'can_manage', v_manage,
    'folder_set', exists (select 1 from public.support_document_settings s
                          where s.organization_id = p_organization_id and s.drive_folder_id is not null),
    'folder_id', case when v_manage then (select s.drive_folder_id from public.support_document_settings s
                                          where s.organization_id = p_organization_id) end,
    'last_sync', case when v_manage then (
        select jsonb_build_object('ran_at', r.ran_at, 'trigger_source', r.trigger_source,
                                  'listed_count', r.listed_count, 'new_count', r.new_count,
                                  'updated_count', r.updated_count, 'removed_count', r.removed_count,
                                  'skipped_count', r.skipped_count, 'failed_count', r.failed_count,
                                  'pending_count', r.pending_count, 'error', r.error_text)
        from public.support_document_sync_runs r
        where r.organization_id = p_organization_id
        order by r.ran_at desc limit 1) end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', d.id, 'title', d.title, 'category', d.category, 'folder_path', d.folder_path,
               'mime_type', d.stored_mime_type, 'file_extension', d.file_extension, 'file_size', d.file_size,
               'updated_at', d.drive_modified_at, 'copied_at', d.copied_at, 'storage_path', d.storage_path)
             order by case when d.category = 'General' then 1 else 0 end, lower(d.category),
                      lower(coalesce(d.folder_path, '')), lower(d.title))
      from public.support_documents d
      where d.organization_id = p_organization_id and d.storage_path is not null), '[]'::jsonb));
end;
$$;
revoke all on function public.list_support_documents(uuid) from public, anon;
grant execute on function public.list_support_documents(uuid) to authenticated;

create or replace function public.set_support_documents_folder(p_organization_id uuid, p_drive_folder_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor  uuid := private.current_profile_id();
  v_folder text := nullif(btrim(p_drive_folder_id), '');
begin
  if v_actor is null or not private.is_organization_administrator(v_actor, p_organization_id) then
    raise exception using errcode = '42501', message = 'Only administrators can set the Support Drive folder.';
  end if;
  if v_folder is not null and v_folder !~ '^[A-Za-z0-9_-]{10,100}$' then
    raise exception using errcode = '22023', message = 'That does not look like a Google Drive folder link.';
  end if;
  insert into public.support_document_settings (organization_id, drive_folder_id, updated_at, updated_by_profile_id)
  values (p_organization_id, v_folder, now(), v_actor)
  on conflict (organization_id) do update
    set drive_folder_id = excluded.drive_folder_id, updated_at = now(), updated_by_profile_id = v_actor;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'library.support_documents.folder_set',
    p_event_category   => 'system',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'organization',
    p_entity_id        => p_organization_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('folder_set', v_folder is not null)
  );
  return jsonb_build_object('status', 'saved', 'folder_set', v_folder is not null);
end;
$$;
revoke all on function public.set_support_documents_folder(uuid, text) from public, anon;
grant execute on function public.set_support_documents_folder(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Storage: Private Bucket & Access Check
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('support-documents', 'support-documents', false, 52428800)
on conflict (id) do nothing;

create or replace function public.can_read_support_document(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
begin
  if array_length(v_parts, 1) is distinct from 2
     or v_parts[1] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return private.can_view_support_documents(v_parts[1]::uuid);
end;
$$;
revoke all on function public.can_read_support_document(text) from public, anon;
grant execute on function public.can_read_support_document(text) to authenticated;

drop policy if exists "support_documents_select" on storage.objects;
create policy "support_documents_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'support-documents' and public.can_read_support_document(name));

-- -----------------------------------------------------------------------------
-- 5. Sync Service Functions (Service Role Only)
-- -----------------------------------------------------------------------------
create or replace function public.get_support_documents_folder(p_organization_id uuid)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select s.drive_folder_id from public.support_document_settings s where s.organization_id = p_organization_id
$$;
revoke all on function public.get_support_documents_folder(uuid) from public, anon, authenticated;
grant execute on function public.get_support_documents_folder(uuid) to service_role;

create or replace function public.apply_support_documents_listing(p_organization_id uuid, p_items jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_new     integer;
  v_removed jsonb;
begin
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'p_items must be an array.';
  end if;

  with src as (
    select distinct on (x->>'drive_file_id')
           x->>'drive_file_id' as drive_file_id,
           left(x->>'title', 300) as title,
           left(coalesce(nullif(x->>'category', ''), 'General'), 120) as category,
           left(nullif(x->>'folder_path', ''), 300) as folder_path,
           x->>'source_mime_type' as source_mime_type,
           x->>'stored_mime_type' as stored_mime_type,
           x->>'file_extension' as file_extension,
           (x->>'drive_modified_at')::timestamptz as drive_modified_at,
           nullif(x->>'drive_md5', '') as drive_md5
    from jsonb_array_elements(p_items) x
    where coalesce(x->>'drive_file_id', '') ~ '^[A-Za-z0-9_-]{10,200}$'
    order by x->>'drive_file_id'
  ), ins as (
    insert into public.support_documents as d (
      organization_id, drive_file_id, title, category, folder_path, source_mime_type, stored_mime_type,
      file_extension, drive_modified_at, drive_md5)
    select p_organization_id, s.drive_file_id, s.title, s.category, s.folder_path, s.source_mime_type,
           s.stored_mime_type, s.file_extension, s.drive_modified_at, s.drive_md5
    from src s
    on conflict (organization_id, drive_file_id) do update
      set title = excluded.title, category = excluded.category, folder_path = excluded.folder_path,
          source_mime_type = excluded.source_mime_type, stored_mime_type = excluded.stored_mime_type,
          file_extension = excluded.file_extension, drive_modified_at = excluded.drive_modified_at,
          drive_md5 = excluded.drive_md5
    returning (xmax = 0) as inserted
  )
  select count(*) filter (where inserted) into v_new from ins;

  if jsonb_array_length(p_items) > 0 then
    with del as (
      delete from public.support_documents d
      where d.organization_id = p_organization_id
        and d.drive_file_id not in (select x->>'drive_file_id' from jsonb_array_elements(p_items) x
                                    where x->>'drive_file_id' is not null)
      returning d.storage_path
    )
    select coalesce(jsonb_agg(storage_path) filter (where storage_path is not null), '[]'::jsonb) into v_removed from del;
  else
    v_removed := '[]'::jsonb;
  end if;

  return jsonb_build_object('new_count', v_new, 'removed_paths', v_removed);
end;
$$;
revoke all on function public.apply_support_documents_listing(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.apply_support_documents_listing(uuid, jsonb) to service_role;

create or replace function public.support_documents_to_copy(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'drive_file_id', d.drive_file_id, 'title', d.title, 'source_mime_type', d.source_mime_type,
           'stored_mime_type', d.stored_mime_type, 'file_extension', d.file_extension,
           'drive_modified_at', d.drive_modified_at, 'drive_md5', d.drive_md5,
           'old_storage_path', d.storage_path)
         order by d.storage_path is not null, d.title), '[]'::jsonb)
  from public.support_documents d
  where d.organization_id = p_organization_id
    and (d.storage_path is null
         or d.copied_modified_at is distinct from d.drive_modified_at
         or (d.drive_md5 is not null and d.copied_md5 is distinct from d.drive_md5))
$$;
revoke all on function public.support_documents_to_copy(uuid) from public, anon, authenticated;
grant execute on function public.support_documents_to_copy(uuid) to service_role;

create or replace function public.mark_support_document_copied(
  p_organization_id uuid, p_drive_file_id text, p_storage_path text, p_file_size bigint,
  p_copied_modified_at timestamptz, p_copied_md5 text)
returns text
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_was text;
begin
  if p_storage_path is null or p_storage_path not like p_organization_id::text || '/%' then
    raise exception using errcode = '22023', message = 'Storage path does not belong to this organization.';
  end if;
  select d.storage_path into v_was from public.support_documents d
  where d.organization_id = p_organization_id and d.drive_file_id = p_drive_file_id
  for update;
  if not found then
    return 'missing';
  end if;
  update public.support_documents
     set storage_path = p_storage_path, file_size = p_file_size, copied_modified_at = p_copied_modified_at,
         copied_md5 = nullif(p_copied_md5, ''), copied_at = now()
   where organization_id = p_organization_id and drive_file_id = p_drive_file_id;
  return case when v_was is null then 'copied' else 'updated' end;
end;
$$;
revoke all on function public.mark_support_document_copied(uuid, text, text, bigint, timestamptz, text) from public, anon, authenticated;
grant execute on function public.mark_support_document_copied(uuid, text, text, bigint, timestamptz, text) to service_role;

create or replace function public.record_support_documents_sync_run(
  p_organization_id uuid, p_trigger_source text, p_listed integer, p_new integer, p_updated integer,
  p_removed integer, p_skipped integer, p_failed integer, p_pending integer, p_error text)
returns uuid
language sql
volatile
security definer
set search_path to 'pg_catalog', 'public'
as $$
  insert into public.support_document_sync_runs (
    organization_id, trigger_source, listed_count, new_count, updated_count, removed_count, skipped_count,
    failed_count, pending_count, error_text)
  values (p_organization_id, p_trigger_source, coalesce(p_listed, 0), coalesce(p_new, 0), coalesce(p_updated, 0),
          coalesce(p_removed, 0), coalesce(p_skipped, 0), coalesce(p_failed, 0), coalesce(p_pending, 0),
          left(p_error, 500))
  returning id
$$;
revoke all on function public.record_support_documents_sync_run(uuid, text, integer, integer, integer, integer, integer, integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.record_support_documents_sync_run(uuid, text, integer, integer, integer, integer, integer, integer, integer, text)
  to service_role;

-- -----------------------------------------------------------------------------
-- 6. Scheduled Nightly Sync (07:30 UTC)
-- -----------------------------------------------------------------------------
create or replace function private.run_support_documents_sync()
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
  from vault.decrypted_secrets ds where ds.name = 'missionos_docs_sync_secret';
  if v_secret is null then
    raise warning 'support documents sync: secret missing';
    return 0;
  end if;
  for v_org in
    select s.organization_id from public.support_document_settings s where s.drive_folder_id is not null
  loop
    perform net.http_post(
      url := 'https://ypbtszvshofbsbvjfvmr.supabase.co/functions/v1/sync-official-documents',
      body := jsonb_build_object('organization_id', v_org, 'library', 'support'),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-sync-secret', v_secret),
      timeout_milliseconds := 150000
    );
    v_calls := v_calls + 1;
  end loop;
  return v_calls;
end;
$$;
revoke all on function private.run_support_documents_sync() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'missionos-support-documents-sync') then
    perform cron.unschedule('missionos-support-documents-sync');
  end if;
  perform cron.schedule(
    'missionos-support-documents-sync',
    '30 7 * * *',
    'select private.run_support_documents_sync()'
  );
end;
$$;

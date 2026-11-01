-- =============================================================================
-- Migration: 20261010126000_event_program_photos.sql
-- Pass 9.50: Event + Program photos, captions, quarterly report selection
--
-- Reuses the member-photos architecture (Pass 20261010063000):
--   private bucket + path-validated storage.objects policies backed by
--   SECURITY DEFINER helpers + RPC metadata + signed URLs on read.
--
-- Model: public.activity_photos targets EXACTLY ONE of
--   event_id -> public.events (standalone event or program session)
--   program_run_id -> public.program_runs (program-level)
-- Same shape as Pass 9.49 activity_speakers. Session photos live on the
-- session event and are aggregated into the Program read.
--
-- Storage path: <org>/events/<event_id>/<photo_uuid>.<ext>
--               <org>/programs/<run_id>/<photo_uuid>.<ext>
-- Upload flow:
--   1. create_activity_photo_upload -> validates rights, returns id + path
--   2. browser uploads to storage (policy re-checks rights from the path)
--   3. finalize_activity_photo -> verifies the object exists, takes MIME and
--      size from storage metadata (not the browser), inserts the record
-- Delete flow: delete_activity_photo removes the record and returns the path;
--   browser removes the object (DELETE policy re-checks rights from the path).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Bucket (private, 10 MB, raster images only)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('activity-photos', 'activity-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- 2. Table
-- -----------------------------------------------------------------------------
create table if not exists public.activity_photos (
  id                          uuid primary key,
  organization_id             uuid not null references public.organizations(id) on delete restrict,
  event_id                    uuid null references public.events(id) on delete cascade,
  program_run_id              uuid null references public.program_runs(id) on delete cascade,
  storage_bucket              text not null default 'activity-photos' check (storage_bucket = 'activity-photos'),
  storage_path                text not null unique check (length(storage_path) between 10 and 300),
  original_filename           text null check (original_filename is null or length(original_filename) <= 255),
  mime_type                   text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  file_size_bytes             bigint not null check (file_size_bytes > 0 and file_size_bytes <= 10485760),
  caption                     text null check (caption is null or length(caption) between 1 and 500),
  alt_text                    text null check (alt_text is null or length(alt_text) between 1 and 300),
  include_in_quarterly_report boolean not null default false,
  report_sort_order           integer not null default 0 check (report_sort_order between 0 and 10000),
  sort_order                  integer not null default 0 check (sort_order between 0 and 10000),
  uploaded_at                 timestamptz not null default now(),
  uploaded_by_profile_id      uuid not null references public.profiles(id) on delete restrict,
  updated_at                  timestamptz not null default now(),
  updated_by_profile_id       uuid null references public.profiles(id) on delete set null,
  constraint chk_activity_photos_target check (num_nonnulls(event_id, program_run_id) = 1)
);

create index if not exists idx_activity_photos_event on public.activity_photos (event_id) where event_id is not null;
create index if not exists idx_activity_photos_run on public.activity_photos (program_run_id) where program_run_id is not null;
create index if not exists idx_activity_photos_report on public.activity_photos (organization_id) where include_in_quarterly_report;

alter table public.activity_photos enable row level security;
revoke all on table public.activity_photos from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Helpers
-- -----------------------------------------------------------------------------

-- Parse '<org>/(events|programs)/<target>/<uuid>.<ext>'; nulls when malformed.
create or replace function private.activity_photo_path_parts(
  p_name text, out o_org uuid, out o_kind text, out o_target uuid, out o_photo uuid
)
language plpgsql
immutable
set search_path to 'pg_catalog'
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_uuid text := '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
begin
  o_org := null; o_kind := null; o_target := null; o_photo := null;
  if p_name is null or array_length(v_parts, 1) <> 4
     or v_parts[1] !~ ('^' || v_uuid || '$')
     or v_parts[2] not in ('events', 'programs')
     or v_parts[3] !~ ('^' || v_uuid || '$')
     or v_parts[4] !~ ('^' || v_uuid || '\.(jpg|png|webp)$') then
    return;
  end if;
  o_org := v_parts[1]::uuid;
  o_kind := v_parts[2];
  o_target := v_parts[3]::uuid;
  o_photo := substring(v_parts[4] from 1 for 36)::uuid;
end;
$$;
revoke all on function private.activity_photo_path_parts(text) from public, anon, authenticated;

-- Can the caller view an activity (same rules as get_activity_team / get_event / get_program_run)?
create or replace function private.can_view_activity(p_organization_id uuid, p_event_id uuid, p_program_run_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.current_profile_id() is not null
     and private.has_organization_access(p_organization_id)
     and case
           when p_event_id is not null then
             exists (select 1 from public.events e where e.id = p_event_id and e.organization_id = p_organization_id)
             and (private.can_manage_activity_event(p_organization_id, p_event_id)
                  or private.has_permission('events.view', p_organization_id)
                  or private.is_any_section_coordinator(p_organization_id)
                  or private.is_event_greeter(p_organization_id, p_event_id))
           when p_program_run_id is not null then
             exists (select 1 from public.program_runs r where r.id = p_program_run_id and r.organization_id = p_organization_id)
             and (private.can_manage_program_run(p_organization_id, p_program_run_id)
                  or private.has_permission('events.view', p_organization_id)
                  or private.is_any_section_coordinator(p_organization_id))
           else false
         end
$$;
revoke all on function private.can_view_activity(uuid, uuid, uuid) from public, anon, authenticated;

-- Can the caller manage the activity named by a photo path?
create or replace function private.can_manage_activity_photo_path(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_org uuid; v_kind text; v_target uuid; v_photo uuid;
begin
  select o_org, o_kind, o_target, o_photo into v_org, v_kind, v_target, v_photo
  from private.activity_photo_path_parts(p_name);
  if v_org is null or private.current_profile_id() is null or not private.has_organization_access(v_org) then
    return false;
  end if;
  if v_kind = 'events' then
    return private.can_manage_activity_event(v_org, v_target);
  end if;
  return private.can_manage_program_run(v_org, v_target);
end;
$$;
revoke all on function private.can_manage_activity_photo_path(text) from public, anon, authenticated;

-- Storage policy helpers (run as the signed-in user, so public + SECURITY DEFINER, like member photos).
create or replace function public.can_write_activity_photo(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
  select private.can_manage_activity_photo_path(p_object_name)
$$;
revoke all on function public.can_write_activity_photo(text) from public, anon;
grant execute on function public.can_write_activity_photo(text) to authenticated;

-- Read: object must belong to a finalized photo record the caller may view.
create or replace function public.can_read_activity_photo(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
  select coalesce((
    select private.can_view_activity(p.organization_id, p.event_id, p.program_run_id)
    from public.activity_photos p
    where p.storage_path = p_object_name
  ), false)
$$;
revoke all on function public.can_read_activity_photo(text) from public, anon;
grant execute on function public.can_read_activity_photo(text) to authenticated;

drop policy if exists "activity_photos_select" on storage.objects;
create policy "activity_photos_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'activity-photos' and public.can_read_activity_photo(name));

drop policy if exists "activity_photos_insert" on storage.objects;
create policy "activity_photos_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'activity-photos' and public.can_write_activity_photo(name));

drop policy if exists "activity_photos_delete" on storage.objects;
create policy "activity_photos_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'activity-photos' and public.can_write_activity_photo(name));
-- No UPDATE policy: objects are never overwritten (upsert disabled).

-- Activity must accept new photos (not cancelled).
create or replace function private.assert_activity_photo_target_open(p_event_id uuid, p_program_run_id uuid)
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if p_event_id is not null and exists (select 1 from public.events e where e.id = p_event_id and e.event_status = 'cancelled') then
    raise exception using errcode = '22023', message = 'Photos cannot be added to a cancelled event.';
  end if;
  if p_program_run_id is not null and exists (select 1 from public.program_runs r where r.id = p_program_run_id and r.run_status = 'cancelled') then
    raise exception using errcode = '22023', message = 'Photos cannot be added to a cancelled program.';
  end if;
end;
$$;
revoke all on function private.assert_activity_photo_target_open(uuid, uuid) from public, anon, authenticated;

create or replace function private.activity_photo_ext(p_mime text)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select case p_mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end
$$;
revoke all on function private.activity_photo_ext(text) from public, anon, authenticated;

-- Photo JSON. Manager-only: report flags, filename, size, upload audit.
create or replace function private.activity_photo_json(p public.activity_photos, p_manage boolean)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select jsonb_build_object(
    'id', p.id,
    'event_id', p.event_id,
    'program_run_id', coalesce(p.program_run_id, e.program_run_id),
    'session_number', e.session_number,
    'event_title', e.title,
    'storage_path', p.storage_path,
    'mime_type', p.mime_type,
    'caption', p.caption,
    'alt_text', p.alt_text,
    'sort_order', p.sort_order,
    'include_in_quarterly_report', case when p_manage then p.include_in_quarterly_report end,
    'report_sort_order', case when p_manage then p.report_sort_order end,
    'original_filename', case when p_manage then p.original_filename end,
    'file_size_bytes', case when p_manage then p.file_size_bytes end,
    'uploaded_at', case when p_manage then p.uploaded_at end,
    'uploaded_by_name', case when p_manage then (select pr.display_name from public.profiles pr where pr.id = p.uploaded_by_profile_id) end
  )
  from (select 1) one
  left join public.events e on e.id = p.event_id
$$;
revoke all on function private.activity_photo_json(public.activity_photos, boolean) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. Read: get_activity_photos (event, or program incl. session photos)
-- -----------------------------------------------------------------------------
create or replace function public.get_activity_photos(
  p_organization_id uuid,
  p_event_id uuid default null,
  p_program_run_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_manage boolean;
  v_photos jsonb;
  v_total integer;
  v_selected integer;
begin
  perform private.assert_activity_caller(p_organization_id);
  if num_nonnulls(p_event_id, p_program_run_id) <> 1 then
    raise exception using errcode = '22023', message = 'Choose exactly one event or program.';
  end if;
  if p_event_id is not null and not exists (select 1 from public.events e where e.id = p_event_id and e.organization_id = p_organization_id) then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if p_program_run_id is not null and not exists (select 1 from public.program_runs r where r.id = p_program_run_id and r.organization_id = p_organization_id) then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  if not private.can_view_activity(p_organization_id, p_event_id, p_program_run_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.view.';
  end if;
  v_manage := case when p_event_id is not null
                   then private.can_manage_activity_event(p_organization_id, p_event_id)
                   else private.can_manage_program_run(p_organization_id, p_program_run_id) end;

  select coalesce(jsonb_agg(private.activity_photo_json(p, v_manage)
                            order by coalesce(e.session_number, 0), p.sort_order, p.uploaded_at), '[]'::jsonb),
         count(*)::int,
         count(*) filter (where p.include_in_quarterly_report)::int
    into v_photos, v_total, v_selected
  from public.activity_photos p
  left join public.events e on e.id = p.event_id
  where p.organization_id = p_organization_id
    and (
      (p_event_id is not null and p.event_id = p_event_id)
      or (p_program_run_id is not null and (p.program_run_id = p_program_run_id
           or (e.program_run_id = p_program_run_id and e.event_status <> 'cancelled')))
    );

  return jsonb_build_object(
    'can_manage', v_manage,
    'photos', v_photos,
    'total_count', v_total,
    'selected_count', case when v_manage then v_selected end
  );
end;
$$;
revoke all on function public.get_activity_photos(uuid, uuid, uuid) from public, anon;
grant execute on function public.get_activity_photos(uuid, uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Upload step 1: create_activity_photo_upload
-- -----------------------------------------------------------------------------
create or replace function public.create_activity_photo_upload(
  p_organization_id uuid,
  p_event_id uuid default null,
  p_program_run_id uuid default null,
  p_mime_type text default null,
  p_file_size_bytes bigint default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_id uuid := gen_random_uuid();
  v_path text;
begin
  perform private.assert_activity_caller(p_organization_id);
  perform private.assert_activity_target(p_organization_id, p_event_id, p_program_run_id);
  perform private.assert_activity_photo_target_open(p_event_id, p_program_run_id);
  if p_mime_type is null or p_mime_type not in ('image/jpeg', 'image/png', 'image/webp') then
    raise exception using errcode = '22023', message = 'Please choose a JPG, PNG, or WebP photo.';
  end if;
  if p_file_size_bytes is null or p_file_size_bytes <= 0 or p_file_size_bytes > 10485760 then
    raise exception using errcode = '22023', message = 'Photo must be 10 MB or smaller.';
  end if;
  v_path := p_organization_id::text
            || case when p_event_id is not null then '/events/' || p_event_id::text else '/programs/' || p_program_run_id::text end
            || '/' || v_id::text || '.' || private.activity_photo_ext(p_mime_type);
  return jsonb_build_object('photo_id', v_id, 'storage_bucket', 'activity-photos', 'storage_path', v_path);
end;
$$;
revoke all on function public.create_activity_photo_upload(uuid, uuid, uuid, text, bigint) from public, anon;
grant execute on function public.create_activity_photo_upload(uuid, uuid, uuid, text, bigint) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Upload step 3: finalize_activity_photo
-- -----------------------------------------------------------------------------
create or replace function public.finalize_activity_photo(
  p_organization_id uuid,
  p_storage_path text,
  p_original_filename text default null,
  p_caption text default null,
  p_alt_text text default null,
  p_include_in_quarterly_report boolean default false
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_org uuid; v_kind text; v_target uuid; v_photo uuid;
  v_event uuid; v_run uuid;
  v_mime text; v_size bigint;
  v_caption text := nullif(btrim(coalesce(p_caption, '')), '');
  v_alt text := nullif(btrim(coalesce(p_alt_text, '')), '');
  v_sort integer;
  v_report_sort integer;
  v_row public.activity_photos%rowtype;
begin
  v_actor := private.assert_activity_caller(p_organization_id);

  select o_org, o_kind, o_target, o_photo into v_org, v_kind, v_target, v_photo
  from private.activity_photo_path_parts(p_storage_path);
  if v_org is null or v_org <> p_organization_id then
    raise exception using errcode = '22023', message = 'Invalid photo path.';
  end if;
  if v_kind = 'events' then v_event := v_target; else v_run := v_target; end if;

  perform private.assert_activity_target(p_organization_id, v_event, v_run);
  perform private.assert_activity_photo_target_open(v_event, v_run);

  if v_caption is not null and length(v_caption) > 500 then
    raise exception using errcode = '22023', message = 'Photo caption must be 500 characters or fewer.';
  end if;
  if v_alt is not null and length(v_alt) > 300 then
    raise exception using errcode = '22023', message = 'Alt text must be 300 characters or fewer.';
  end if;

  -- Server-trusted file facts come from the stored object, not the browser.
  select o.metadata->>'mimetype', nullif(o.metadata->>'size', '')::bigint into v_mime, v_size
  from storage.objects o
  where o.bucket_id = 'activity-photos' and o.name = p_storage_path;
  if not found then
    raise exception using errcode = 'P0002', message = 'Uploaded photo was not found. Please try again.';
  end if;
  if v_mime is null or v_mime not in ('image/jpeg', 'image/png', 'image/webp')
     or private.activity_photo_ext(v_mime) <> substring(p_storage_path from '\.([a-z]+)$') then
    raise exception using errcode = '22023', message = 'Please choose a JPG, PNG, or WebP photo.';
  end if;
  if v_size is null or v_size <= 0 or v_size > 10485760 then
    raise exception using errcode = '22023', message = 'Photo must be 10 MB or smaller.';
  end if;

  select coalesce(max(sort_order) + 1, 0) into v_sort from public.activity_photos
  where (v_event is not null and event_id = v_event) or (v_run is not null and program_run_id = v_run);
  select coalesce(max(report_sort_order) + 1, 0) into v_report_sort from public.activity_photos
  where include_in_quarterly_report
    and ((v_event is not null and event_id = v_event) or (v_run is not null and program_run_id = v_run));

  begin
    insert into public.activity_photos (
      id, organization_id, event_id, program_run_id, storage_path, original_filename,
      mime_type, file_size_bytes, caption, alt_text, include_in_quarterly_report,
      report_sort_order, sort_order, uploaded_by_profile_id, updated_by_profile_id
    ) values (
      v_photo, p_organization_id, v_event, v_run, p_storage_path,
      left(nullif(btrim(coalesce(p_original_filename, '')), ''), 255),
      v_mime, v_size, v_caption, v_alt, coalesce(p_include_in_quarterly_report, false),
      case when coalesce(p_include_in_quarterly_report, false) then v_report_sort else 0 end,
      v_sort, v_actor, v_actor
    ) returning * into v_row;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'This photo has already been saved.';
  end;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'activity.photo.added',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'activity_photo',
    p_entity_id        => v_row.id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('event_id', v_row.event_id, 'program_run_id', v_row.program_run_id,
                                             'file_size_bytes', v_row.file_size_bytes)
  );

  return jsonb_build_object('status', 'success', 'photo', private.activity_photo_json(v_row, true));
end;
$$;
revoke all on function public.finalize_activity_photo(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function public.finalize_activity_photo(uuid, text, text, text, text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. update_activity_photo (caption, alt text, report selection, ordering)
--    Null parameters keep current values; empty string clears caption/alt text.
-- -----------------------------------------------------------------------------
create or replace function public.update_activity_photo(
  p_organization_id uuid,
  p_photo_id uuid,
  p_caption text default null,
  p_alt_text text default null,
  p_include_in_quarterly_report boolean default null,
  p_report_sort_order integer default null,
  p_sort_order integer default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_row public.activity_photos%rowtype;
begin
  v_actor := private.assert_activity_caller(p_organization_id);
  select * into v_row from public.activity_photos
  where id = p_photo_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Photo not found.';
  end if;
  perform private.assert_activity_target(p_organization_id, v_row.event_id, v_row.program_run_id);

  if p_caption is not null and length(btrim(p_caption)) > 500 then
    raise exception using errcode = '22023', message = 'Photo caption must be 500 characters or fewer.';
  end if;
  if p_alt_text is not null and length(btrim(p_alt_text)) > 300 then
    raise exception using errcode = '22023', message = 'Alt text must be 300 characters or fewer.';
  end if;
  if (p_report_sort_order is not null and (p_report_sort_order < 0 or p_report_sort_order > 10000))
     or (p_sort_order is not null and (p_sort_order < 0 or p_sort_order > 10000)) then
    raise exception using errcode = '22023', message = 'Sort order must be between 0 and 10000.';
  end if;

  update public.activity_photos set
    caption = case when p_caption is null then caption else nullif(btrim(p_caption), '') end,
    alt_text = case when p_alt_text is null then alt_text else nullif(btrim(p_alt_text), '') end,
    include_in_quarterly_report = coalesce(p_include_in_quarterly_report, include_in_quarterly_report),
    report_sort_order = coalesce(p_report_sort_order, report_sort_order),
    sort_order = coalesce(p_sort_order, sort_order),
    updated_by_profile_id = v_actor,
    updated_at = now()
  where id = v_row.id
  returning * into v_row;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'activity.photo.updated',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'activity_photo',
    p_entity_id        => v_row.id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('include_in_quarterly_report', v_row.include_in_quarterly_report,
                                             'report_sort_order', v_row.report_sort_order)
  );

  return jsonb_build_object('status', 'success', 'photo', private.activity_photo_json(v_row, true));
end;
$$;
revoke all on function public.update_activity_photo(uuid, uuid, text, text, boolean, integer, integer) from public, anon;
grant execute on function public.update_activity_photo(uuid, uuid, text, text, boolean, integer, integer) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. delete_activity_photo: removes the record, returns the path for object removal
-- -----------------------------------------------------------------------------
create or replace function public.delete_activity_photo(
  p_organization_id uuid,
  p_photo_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_row public.activity_photos%rowtype;
begin
  v_actor := private.assert_activity_caller(p_organization_id);
  select * into v_row from public.activity_photos
  where id = p_photo_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Photo not found.';
  end if;
  perform private.assert_activity_target(p_organization_id, v_row.event_id, v_row.program_run_id);

  delete from public.activity_photos where id = v_row.id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'activity.photo.deleted',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'activity_photo',
    p_entity_id        => v_row.id,
    p_action           => 'delete',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('event_id', v_row.event_id, 'program_run_id', v_row.program_run_id,
                                             'storage_path', v_row.storage_path)
  );

  return jsonb_build_object('status', 'success', 'photo_id', v_row.id,
                            'storage_bucket', v_row.storage_bucket, 'storage_path', v_row.storage_path);
end;
$$;
revoke all on function public.delete_activity_photo(uuid, uuid) from public, anon;
grant execute on function public.delete_activity_photo(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. Report-ready read: selected photos of reportable activities in a period.
--    Both conditions required: activity include_in_quarterly_report AND photo
--    include_in_quarterly_report. Only activities the caller manages.
-- -----------------------------------------------------------------------------
create or replace function public.list_report_activity_photos(
  p_organization_id uuid,
  p_from date,
  p_to date
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  perform private.assert_activity_caller(p_organization_id);
  if p_from is null or p_to is null or p_to < p_from then
    raise exception using errcode = '22023', message = 'Choose a valid reporting period.';
  end if;

  return coalesce((
    select jsonb_agg(x.j order by x.activity_date, x.activity_title, x.report_sort_order, x.sort_order)
    from (
      -- Standalone reportable events
      select (private.activity_photo_json(p, true) || jsonb_build_object(
                'activity_kind', 'event', 'activity_id', e.id, 'activity_title', e.title,
                'activity_type', e.event_type, 'activity_date', e.starts_at)) as j,
             e.starts_at as activity_date, e.title as activity_title, p.report_sort_order, p.sort_order
      from public.activity_photos p
      join public.events e on e.id = p.event_id
      where p.organization_id = p_organization_id
        and p.include_in_quarterly_report
        and e.program_run_id is null
        and e.include_in_quarterly_report
        and e.event_status <> 'cancelled'
        and (e.starts_at at time zone 'America/New_York')::date between p_from and p_to
        and private.can_manage_activity_event(p_organization_id, e.id)
      union all
      -- Reportable programs (program-level + session photos)
      select (private.activity_photo_json(p, true) || jsonb_build_object(
                'activity_kind', 'program', 'activity_id', r.id, 'activity_title', r.title,
                'activity_type', r.program_code, 'activity_date', fs.first_at)) as j,
             fs.first_at, r.title, p.report_sort_order, p.sort_order
      from public.activity_photos p
      left join public.events se on se.id = p.event_id
      join public.program_runs r on r.id = coalesce(p.program_run_id, se.program_run_id)
      cross join lateral (
        select min(e2.starts_at) as first_at from public.events e2
        where e2.program_run_id = r.id and e2.event_status <> 'cancelled'
      ) fs
      where p.organization_id = p_organization_id
        and p.include_in_quarterly_report
        and (se.id is null or se.event_status <> 'cancelled')
        and r.include_in_quarterly_report
        and r.run_status <> 'cancelled'
        and exists (
          select 1 from public.events e3
          where e3.program_run_id = r.id and e3.event_status <> 'cancelled'
            and (e3.starts_at at time zone 'America/New_York')::date between p_from and p_to
        )
        and private.can_manage_program_run(p_organization_id, r.id)
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_report_activity_photos(uuid, date, date) from public, anon;
grant execute on function public.list_report_activity_photos(uuid, date, date) to authenticated;

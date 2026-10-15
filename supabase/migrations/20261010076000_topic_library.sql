-- =============================================================================
-- Migration: 20261010076000_topic_library.sql
-- MissionOS Pass 9.1 (written by Claude, 2026-10-15)
-- Household Library: MFC monthly topics (Household Topic, Family Household Topic,
-- Date Night Topic, Chapter Teaching, Chapter Assembly Guide, Personal Sharing Guide).
--
--   * Each monthly topic is a formation_topics row (so leaders can assign it to a household),
--     tagged with series, month, material kind and the official source URL.
--   * The copied content lives in formation_topic_content_versions: every copy is a version
--     that a manager approves before members can read it. The official link is always kept,
--     so members can open "the current version" on the MFC site.
--   * The copied text is stored ONLY in the database (written by the sync function).
--     No MFC content is ever placed in migrations or the repo.
--
-- Access:
--   read   — any member with self-service access, or households.formation.view/manage
--   review — households.formation.manage (private.assert_formation_manage_prereqs)
--   ingest — service_role only (the sync-topic-library edge function, Pass 9.2)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Library columns on formation_topics
-- -----------------------------------------------------------------------------
alter table public.formation_topics
  add column if not exists series_code   text null,
  add column if not exists series_title  text null,
  add column if not exists topic_month   date null,
  add column if not exists material_kind text null,
  add column if not exists source_url    text null;

alter table public.formation_topics
  drop constraint if exists formation_topics_material_kind_check;
alter table public.formation_topics
  add constraint formation_topics_material_kind_check check (
    material_kind is null or material_kind in (
      'household_topic', 'family_household_topic', 'date_night_topic',
      'chapter_teaching', 'chapter_assembly_guide', 'personal_sharing_guide'));

alter table public.formation_topics
  drop constraint if exists formation_topics_topic_month_first_day_check;
alter table public.formation_topics
  add constraint formation_topics_topic_month_first_day_check check (
    topic_month is null or extract(day from topic_month) = 1);

alter table public.formation_topics
  drop constraint if exists formation_topics_library_fields_check;
alter table public.formation_topics
  add constraint formation_topics_library_fields_check check (
    series_code is null
    or (organization_id is not null and topic_month is not null
        and material_kind is not null and source_url is not null
        and source_url ~ '^https://'));

create unique index if not exists idx_formation_topics_library_unique
  on public.formation_topics (organization_id, series_code, topic_month, material_kind, source_url)
  where series_code is not null;

create index if not exists idx_formation_topics_library_month
  on public.formation_topics (organization_id, topic_month)
  where series_code is not null;

-- -----------------------------------------------------------------------------
-- 2. Content versions
-- -----------------------------------------------------------------------------
create table if not exists public.formation_topic_content_versions (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete cascade,
  topic_id               uuid not null references public.formation_topics(id) on delete cascade,
  version_number         integer not null check (version_number > 0),
  content_blocks         jsonb not null check (jsonb_typeof(content_blocks) = 'array'),
  content_hash           text not null,
  source_url             text not null check (source_url ~ '^https://'),
  source_fetched_at      timestamptz not null,
  review_status          text not null default 'pending' check (
    review_status in ('pending', 'approved', 'rejected', 'superseded')),
  reviewed_at            timestamptz null,
  reviewed_by_profile_id uuid null references public.profiles(id) on delete set null,
  review_notes           text null,
  created_at             timestamptz not null default now(),
  unique (topic_id, version_number),
  unique (topic_id, content_hash)
);

create unique index if not exists idx_topic_content_one_approved
  on public.formation_topic_content_versions (topic_id)
  where review_status = 'approved';

create index if not exists idx_topic_content_org_status
  on public.formation_topic_content_versions (organization_id, review_status);

alter table public.formation_topic_content_versions enable row level security;
-- No policies: reached only through the security-definer RPCs below (service_role bypasses RLS).
revoke all on table public.formation_topic_content_versions from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Helpers
-- -----------------------------------------------------------------------------
create or replace function private.can_read_topic_library(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
  select private.current_profile_id() is not null
     and p_organization_id is not null
     and private.has_organization_access(p_organization_id)
     and (private.has_permission('members.self_service.view', p_organization_id)
          or private.has_permission('households.formation.view', p_organization_id)
          or private.has_permission('households.formation.manage', p_organization_id))
$$;
revoke all on function private.can_read_topic_library(uuid) from public, anon, authenticated;

create or replace function private.can_manage_topic_library(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
  select private.current_profile_id() is not null
     and p_organization_id is not null
     and private.has_organization_access(p_organization_id)
     and private.has_permission('households.formation.manage', p_organization_id)
$$;
revoke all on function private.can_manage_topic_library(uuid) from public, anon, authenticated;

-- Validates content blocks: [{type: heading|paragraph|list_item, text: string, level?: 1..4}]
create or replace function private.validate_topic_content_blocks(p_blocks jsonb)
returns void
language plpgsql
immutable
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  b jsonb;
begin
  if p_blocks is null or jsonb_typeof(p_blocks) <> 'array' then
    raise exception using errcode = '22023', message = 'Content must be a list of blocks.';
  end if;
  if jsonb_array_length(p_blocks) = 0 then
    raise exception using errcode = '22023', message = 'Content is empty.';
  end if;
  if jsonb_array_length(p_blocks) > 2000 or length(p_blocks::text) > 400000 then
    raise exception using errcode = '22023', message = 'Content is too large.';
  end if;
  for b in select value from jsonb_array_elements(p_blocks) loop
    if jsonb_typeof(b) <> 'object'
       or coalesce(b->>'type', '') not in ('heading', 'paragraph', 'list_item')
       or jsonb_typeof(b->'text') is distinct from 'string'
       or length(trim(b->>'text')) = 0 then
      raise exception using errcode = '22023', message = 'Invalid content block.';
    end if;
  end loop;
end;
$$;
revoke all on function private.validate_topic_content_blocks(jsonb) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. Ingest (service_role only) — called by the sync-topic-library edge function
--    Creates the topic if new (inactive until its first approval) and records a
--    pending content version when the content differs from every earlier copy.
-- -----------------------------------------------------------------------------
create or replace function public.ingest_topic_library_page(
  p_organization_id uuid,
  p_series_code     text,
  p_series_title    text,
  p_topic_month     date,
  p_material_kind   text,
  p_title           text,
  p_source_url      text,
  p_content_blocks  jsonb,
  p_fetched_at      timestamptz default now()
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_topic_id   uuid;
  v_new_topic  boolean := false;
  v_hash       text;
  v_version_id uuid;
  v_next       integer;
  v_approved   text;
begin
  if p_organization_id is null or not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception using errcode = '22023', message = 'Unknown organization.';
  end if;
  if nullif(trim(p_series_code), '') is null or nullif(trim(p_title), '') is null then
    raise exception using errcode = '22023', message = 'Series and title are required.';
  end if;
  if p_topic_month is null or extract(day from p_topic_month) <> 1 then
    raise exception using errcode = '22023', message = 'Topic month must be the first day of a month.';
  end if;
  if p_material_kind not in ('household_topic', 'family_household_topic', 'date_night_topic',
                             'chapter_teaching', 'chapter_assembly_guide', 'personal_sharing_guide') then
    raise exception using errcode = '22023', message = 'Unknown material kind.';
  end if;
  if p_source_url is null or p_source_url !~ '^https://' or length(p_source_url) > 500 then
    raise exception using errcode = '22023', message = 'Invalid source URL.';
  end if;
  perform private.validate_topic_content_blocks(p_content_blocks);

  v_hash := md5(p_content_blocks::text);

  select ft.id into v_topic_id
  from public.formation_topics ft
  where ft.organization_id = p_organization_id
    and ft.series_code = p_series_code
    and ft.topic_month = p_topic_month
    and ft.material_kind = p_material_kind
    and ft.source_url = p_source_url
  for update;

  if v_topic_id is null then
    insert into public.formation_topics (
      organization_id, title, short_title, topic_code, source_type, is_active,
      series_code, series_title, topic_month, material_kind, source_url)
    values (
      p_organization_id, trim(p_title), null,
      to_char(p_topic_month, 'YYYY-MM') || ' ' || case p_material_kind
        when 'household_topic' then 'HT' when 'family_household_topic' then 'FHT'
        when 'date_night_topic' then 'DN' when 'chapter_teaching' then 'CT'
        when 'chapter_assembly_guide' then 'CAG' else 'PSG' end,
      case when p_material_kind in ('chapter_teaching', 'chapter_assembly_guide') then 'other' else 'household_topic' end,
      false,
      p_series_code, nullif(trim(p_series_title), ''), p_topic_month, p_material_kind, p_source_url)
    returning id into v_topic_id;
    v_new_topic := true;
  end if;

  -- Same content already copied (in any review state): nothing to do.
  if exists (select 1 from public.formation_topic_content_versions v
             where v.topic_id = v_topic_id and v.content_hash = v_hash) then
    select v.review_status into v_approved
    from public.formation_topic_content_versions v
    where v.topic_id = v_topic_id and v.content_hash = v_hash;
    return jsonb_build_object('topic_id', v_topic_id, 'result', 'unchanged', 'existing_status', v_approved);
  end if;

  -- An older pending copy is replaced by the newer one.
  update public.formation_topic_content_versions
     set review_status = 'superseded', review_notes = 'Replaced by a newer copy before review.'
   where topic_id = v_topic_id and review_status = 'pending';

  select coalesce(max(version_number), 0) + 1 into v_next
  from public.formation_topic_content_versions where topic_id = v_topic_id;

  insert into public.formation_topic_content_versions (
    organization_id, topic_id, version_number, content_blocks, content_hash,
    source_url, source_fetched_at, review_status)
  values (
    p_organization_id, v_topic_id, v_next, p_content_blocks, v_hash,
    p_source_url, coalesce(p_fetched_at, now()), 'pending')
  returning id into v_version_id;

  return jsonb_build_object(
    'topic_id', v_topic_id,
    'version_id', v_version_id,
    'version_number', v_next,
    'result', case when v_new_topic then 'new_topic' else 'changed' end);
end;
$$;
revoke all on function public.ingest_topic_library_page(uuid, text, text, date, text, text, text, jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.ingest_topic_library_page(uuid, text, text, date, text, text, text, jsonb, timestamptz)
  to service_role;

-- -----------------------------------------------------------------------------
-- 5. list_topic_library — month-by-month list for the Household Library page
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

-- -----------------------------------------------------------------------------
-- 6. get_topic_library_item — reading view (approved copy + official link);
--    managers also get the pending copy to review.
-- -----------------------------------------------------------------------------
create or replace function public.get_topic_library_item(
  p_organization_id uuid,
  p_topic_id        uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_manage boolean;
  v_topic  public.formation_topics%rowtype;
  v_appr   public.formation_topic_content_versions%rowtype;
  v_pend   public.formation_topic_content_versions%rowtype;
begin
  if not private.can_read_topic_library(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have access to the Household Library.';
  end if;
  v_manage := private.can_manage_topic_library(p_organization_id);

  select * into v_topic from public.formation_topics ft
  where ft.id = p_topic_id and ft.organization_id = p_organization_id and ft.series_code is not null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Topic not found.';
  end if;

  select * into v_appr from public.formation_topic_content_versions v
  where v.topic_id = p_topic_id and v.review_status = 'approved';
  if v_appr.id is null and not v_manage then
    raise exception using errcode = 'P0002', message = 'Topic not found.';
  end if;

  if v_manage then
    select * into v_pend from public.formation_topic_content_versions v
    where v.topic_id = p_topic_id and v.review_status = 'pending'
    order by v.version_number desc limit 1;
  end if;

  return jsonb_build_object(
    'topic_id',      v_topic.id,
    'title',         v_topic.title,
    'topic_code',    v_topic.topic_code,
    'series_code',   v_topic.series_code,
    'series_title',  v_topic.series_title,
    'topic_month',   v_topic.topic_month,
    'material_kind', v_topic.material_kind,
    'source_url',    v_topic.source_url,
    'can_manage',    v_manage,
    'approved', case when v_appr.id is null then null else jsonb_build_object(
        'version_id', v_appr.id, 'version_number', v_appr.version_number,
        'copied_at', v_appr.source_fetched_at, 'approved_at', v_appr.reviewed_at,
        'blocks', v_appr.content_blocks) end,
    'pending', case when v_pend.id is null then null else jsonb_build_object(
        'version_id', v_pend.id, 'version_number', v_pend.version_number,
        'copied_at', v_pend.source_fetched_at, 'blocks', v_pend.content_blocks) end);
end;
$$;
revoke all on function public.get_topic_library_item(uuid, uuid) from public, anon;
grant execute on function public.get_topic_library_item(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. review_topic_content_version — approve or reject a pending copy
--    Approving replaces the earlier approved copy and makes the topic assignable.
-- -----------------------------------------------------------------------------
create or replace function public.review_topic_content_version(
  p_organization_id uuid,
  p_version_id      uuid,
  p_decision        text,
  p_notes           text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile_id uuid;
  v_ver        public.formation_topic_content_versions%rowtype;
begin
  v_profile_id := private.assert_formation_manage_prereqs(p_organization_id);

  if p_decision not in ('approve', 'reject') then
    raise exception using errcode = '22023', message = 'Decision must be approve or reject.';
  end if;

  select * into v_ver from public.formation_topic_content_versions v
  where v.id = p_version_id and v.organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Copy not found.';
  end if;
  if v_ver.review_status <> 'pending' then
    raise exception using errcode = '22023', message = 'This copy has already been reviewed.';
  end if;

  if p_decision = 'approve' then
    update public.formation_topic_content_versions
       set review_status = 'superseded'
     where topic_id = v_ver.topic_id and review_status = 'approved';

    update public.formation_topic_content_versions
       set review_status = 'approved', reviewed_at = now(),
           reviewed_by_profile_id = v_profile_id, review_notes = nullif(trim(p_notes), '')
     where id = v_ver.id;

    update public.formation_topics
       set is_active = true, updated_at = now(), updated_by_profile_id = v_profile_id
     where id = v_ver.topic_id and is_active = false;
  else
    update public.formation_topic_content_versions
       set review_status = 'rejected', reviewed_at = now(),
           reviewed_by_profile_id = v_profile_id, review_notes = nullif(trim(p_notes), '')
     where id = v_ver.id;
  end if;

  return jsonb_build_object('version_id', v_ver.id, 'topic_id', v_ver.topic_id,
                            'review_status', case when p_decision = 'approve' then 'approved' else 'rejected' end);
end;
$$;
revoke all on function public.review_topic_content_version(uuid, uuid, text, text) from public, anon;
grant execute on function public.review_topic_content_version(uuid, uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. can_manage_topic_library — used by the sync edge function (caller's JWT)
--    and the Library page to show the review tools.
-- -----------------------------------------------------------------------------
create or replace function public.can_manage_topic_library(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
  select private.can_manage_topic_library(p_organization_id)
$$;
revoke all on function public.can_manage_topic_library(uuid) from public, anon;
grant execute on function public.can_manage_topic_library(uuid) to authenticated;

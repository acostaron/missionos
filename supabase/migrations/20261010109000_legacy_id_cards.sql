-- =============================================================================
-- Migration: 20261010109000_legacy_id_cards.sql
-- MissionOS Pass 9.37 (written by Claude, 2026-10-22) — run after 20261010108000.
-- Ron (2026-10-22): the QR desk must also accept the QR printed on the OLD MFCNY ID cards (old attendance system)
-- until the new ID cards have been issued to everyone.
--   * Old card QR text: "<member number>,<first name>,<last name>,<email>,<role>" (comma separated, not signed).
--   * Matched to a member: by member number, confirmed by the card's email (any of the member's emails) or last
--     name (in the member's name); otherwise by the card's email alone (member number changed). Anything else is
--     refused ("does not match"). The member must be active.
--   * organization_check_in_settings.accept_legacy_id_cards (default ON); administrators switch it OFF when the
--     new cards are out (set_accept_legacy_id_cards). get_check_in_settings for the desk.
--   * public.resolve_member_qr: one added branch at the top (the rest unchanged). scan_event_check_in unchanged.
-- Guarded: resolve_member_qr must still be the 20261010064000 version.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'resolve_member_qr';
  if v_md5 is distinct from 'c7cc27eaa09f73c132df145b4da17caf' then
    raise exception 'STOP: public.resolve_member_qr differs from 20261010064000 (md5 %).', v_md5;
  end if;
end;
$guard$;

create table if not exists public.organization_check_in_settings (
  organization_id         uuid primary key references public.organizations(id) on delete cascade,
  accept_legacy_id_cards  boolean not null default true,
  updated_at              timestamptz not null default now(),
  updated_by_profile_id   uuid null references public.profiles(id) on delete set null
);
alter table public.organization_check_in_settings enable row level security;
revoke all on public.organization_check_in_settings from public, anon, authenticated;

-- lower case, common accents removed, letters only
create or replace function private.legacy_name_key(p_text text)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select regexp_replace(
           translate(lower(coalesce(p_text, '')), 'áàâäãéèêëíìîïóòôöõúùûüñç', 'aaaaaeeeeiiiiooooouuuunc'),
           '[^a-z]', '', 'g')
$$;

create or replace function private.resolve_legacy_id_card(p_organization_id uuid, p_payload text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_f      text[] := string_to_array(btrim(coalesce(p_payload, '')), ',');
  v_number text;
  v_last   text;
  v_email  text;
  v_on     boolean;
  v_m      record;
  v_by     text;
  v_ids    uuid[];
begin
  select coalesce((select s.accept_legacy_id_cards from public.organization_check_in_settings s
                   where s.organization_id = p_organization_id), true) into v_on;
  if not v_on then
    return jsonb_build_object('valid', false, 'reason', 'legacy_card_off', 'legacy', true);
  end if;

  v_number := upper(btrim(v_f[1]));
  v_last   := private.legacy_name_key(v_f[3]);
  v_email  := lower(btrim(coalesce(v_f[4], '')));
  if v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then
    v_email := null;
  end if;

  -- 1. member number, confirmed by email or last name
  select m.id, m.member_number, m.display_name, m.profile_photo_storage_path, m.record_status into v_m
  from public.members m
  where m.organization_id = p_organization_id and upper(m.member_number) = v_number and m.archived_at is null
    and ((v_email is not null and exists (select 1 from public.member_emails e
                                          where e.member_id = m.id and e.effective_to_at is null
                                            and lower(e.email_address) = v_email))
         or (length(v_last) >= 2
             and (position(v_last in private.legacy_name_key(m.display_name)) > 0
                  or position(v_last in private.legacy_name_key(m.sort_name)) > 0)))
  limit 1;
  if found then
    v_by := 'number';
  elsif v_email is not null then
    -- 2. the card's email alone (only if exactly one member has it)
    select array_agg(distinct e.member_id) into v_ids
    from public.member_emails e
    join public.members m2 on m2.id = e.member_id
    where m2.organization_id = p_organization_id and m2.archived_at is null
      and e.effective_to_at is null and lower(e.email_address) = v_email;
    if coalesce(array_length(v_ids, 1), 0) = 1 then
      select m.id, m.member_number, m.display_name, m.profile_photo_storage_path, m.record_status into v_m
      from public.members m where m.id = v_ids[1];
    end if;
    if coalesce(array_length(v_ids, 1), 0) = 1 then
      v_by := 'email';
    end if;
  end if;

  if v_by is null then
    return jsonb_build_object('valid', false, 'legacy', true,
      'reason', case when exists (select 1 from public.members m where m.organization_id = p_organization_id
                                    and upper(m.member_number) = v_number and m.archived_at is null)
                     then 'legacy_mismatch' else 'legacy_unknown' end);
  end if;

  return jsonb_build_object('valid', v_m.record_status = 'active',
                            'reason', case when v_m.record_status = 'active' then null else 'member_not_active' end,
                            'legacy', true, 'matched_by', v_by,
                            'member_id', v_m.id, 'member_number', v_m.member_number,
                            'display_name', v_m.display_name, 'photo_path', v_m.profile_photo_storage_path);
end;
$$;
revoke all on function private.legacy_name_key(text) from public, anon, authenticated;
revoke all on function private.resolve_legacy_id_card(uuid, text) from public, anon, authenticated;

-- resolve_member_qr: the 064 version plus the old-card branch
create or replace function public.resolve_member_qr(p_organization_id uuid, p_payload text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_parts text[];
  v_t record;
  v_m record;
  v_current_number text;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if not (private.has_permission('events.attendance.record', p_organization_id)
          or private.has_permission('members.qr.view', p_organization_id)
          or exists (select 1 from public.event_greeters g
                     join public.events e on e.id = g.event_id
                     join public.members gm on gm.id = g.member_id
                     where e.organization_id = p_organization_id
                       and gm.id = private.current_member_id(p_organization_id)
                       and g.removed_at is null
                       and e.event_status = 'scheduled')) then
    raise exception using errcode = '42501', message = 'You do not have permission to scan member QR codes.';
  end if;

  -- Pass 9.37: old MFCNY ID card (old attendance system): "NY10329,First,Last,email,Role" — no signature
  if btrim(coalesce(p_payload, '')) ~* '^NY[0-9]{5}\s*,' then
    return private.resolve_legacy_id_card(p_organization_id, p_payload);
  end if;

  v_parts := string_to_array(btrim(coalesce(p_payload, '')), ':');
  if array_length(v_parts, 1) <> 4 or v_parts[1] <> 'MFCNY1' or v_parts[2] !~ '^(NY[0-9]{5})?$'
     or lower(v_parts[3]) !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or v_parts[4] !~ '^[0-9a-f]{20}$' then
    return jsonb_build_object('valid', false, 'reason', 'not_a_member_qr');
  end if;

  select t.* into v_t
  from public.member_qr_tokens t
  where t.token_public_id = lower(v_parts[3])::uuid and t.organization_id = p_organization_id;
  if not found then
    return jsonb_build_object('valid', false, 'reason', 'unknown_qr');
  end if;

  select m.member_number into v_current_number from public.members m where m.id = v_t.member_id;

  if v_parts[2] is distinct from coalesce(v_current_number, '') then
    if private.member_qr_sign(v_t.token_public_id::text, v_t.token_version, nullif(v_parts[2], '')) = v_parts[4] then
      insert into public.member_qr_token_events (organization_id, member_id, member_qr_token_id, event_type, actor_profile_id,
                                                 reason_code, event_summary, metadata, occurred_at)
      values (p_organization_id, v_t.member_id, v_t.id, 'rejected', v_actor, 'number_changed',
              'QR shows an earlier envelope number', '{}'::jsonb, clock_timestamp());
      return jsonb_build_object('valid', false, 'reason', 'number_changed');
    end if;
  end if;

  if private.member_qr_sign(v_t.token_public_id::text, v_t.token_version, nullif(v_parts[2], '')) <> v_parts[4] then
    insert into public.member_qr_token_events (organization_id, member_id, member_qr_token_id, event_type, actor_profile_id,
                                               reason_code, event_summary, metadata, occurred_at)
    values (p_organization_id, v_t.member_id, v_t.id, 'rejected', v_actor, 'bad_signature', 'QR signature did not match', '{}'::jsonb, clock_timestamp());
    return jsonb_build_object('valid', false, 'reason', 'tampered');
  end if;

  if v_t.token_status <> 'active' then
    insert into public.member_qr_token_events (organization_id, member_id, member_qr_token_id, event_type, actor_profile_id,
                                               reason_code, event_summary, metadata, occurred_at)
    values (p_organization_id, v_t.member_id, v_t.id, 'rejected', v_actor, v_t.token_status, 'QR is no longer active', '{}'::jsonb, clock_timestamp());
    return jsonb_build_object('valid', false, 'reason', 'replaced_or_revoked');
  end if;

  select m.id, m.member_number, m.display_name, m.profile_photo_storage_path, m.record_status
  into v_m
  from public.members m where m.id = v_t.member_id;

  update public.member_qr_tokens set use_count = use_count + 1, last_used_at = clock_timestamp() where id = v_t.id;
  insert into public.member_qr_token_events (organization_id, member_id, member_qr_token_id, event_type, actor_profile_id,
                                             event_summary, metadata, occurred_at)
  values (p_organization_id, v_t.member_id, v_t.id, 'validated', v_actor, 'QR scanned', '{}'::jsonb, clock_timestamp());

  return jsonb_build_object('valid', v_m.record_status = 'active',
                            'reason', case when v_m.record_status = 'active' then null else 'member_not_active' end,
                            'member_id', v_m.id, 'member_number', v_m.member_number,
                            'display_name', v_m.display_name, 'photo_path', v_m.profile_photo_storage_path);
end;
$$;
revoke all on function public.resolve_member_qr(uuid, text) from public, anon;
grant execute on function public.resolve_member_qr(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Settings (desk reads; administrators change)
-- -----------------------------------------------------------------------------
create or replace function public.get_check_in_settings(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select jsonb_build_object(
    'accept_legacy_id_cards', coalesce((select s.accept_legacy_id_cards from public.organization_check_in_settings s
                                        where s.organization_id = p_organization_id), true),
    'can_manage', private.current_profile_id() is not null
                  and coalesce(private.is_organization_administrator(private.current_profile_id(), p_organization_id), false))
  where private.has_organization_access(p_organization_id)
$$;
revoke all on function public.get_check_in_settings(uuid) from public, anon;
grant execute on function public.get_check_in_settings(uuid) to authenticated;

create or replace function public.set_accept_legacy_id_cards(p_organization_id uuid, p_accept boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor uuid := private.current_profile_id();
begin
  if v_actor is null or not private.is_organization_administrator(v_actor, p_organization_id) then
    raise exception using errcode = '42501', message = 'Only administrators can change this setting.';
  end if;
  insert into public.organization_check_in_settings (organization_id, accept_legacy_id_cards, updated_at, updated_by_profile_id)
  values (p_organization_id, coalesce(p_accept, true), now(), v_actor)
  on conflict (organization_id) do update
    set accept_legacy_id_cards = excluded.accept_legacy_id_cards, updated_at = now(), updated_by_profile_id = v_actor;
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.check_in.legacy_cards_set',
    p_event_category   => 'system',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'organization',
    p_entity_id        => p_organization_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('accept_legacy_id_cards', coalesce(p_accept, true)));
  return jsonb_build_object('status', 'saved', 'accept_legacy_id_cards', coalesce(p_accept, true));
end;
$$;
revoke all on function public.set_accept_legacy_id_cards(uuid, boolean) from public, anon;
grant execute on function public.set_accept_legacy_id_cards(uuid, boolean) to authenticated;

-- =============================================================================
-- Migration: 20261010064000_member_qr_uuid_fix.sql  (revised: envelope number in QR)
-- MissionOS Pass 8.2-fix (written by Claude, 2026-10-14)
-- Verification of migration 132 showed:
--   * member_qr_tokens.token_public_id is a uuid (not text) → issuing/reading a QR failed with "uuid = text".
--     QR text is now  MFCNY1:<token public uuid>:<20-hex HMAC signature>;  the card id uses the table default.
--   * Administrators could not replace a member's QR (no members.qr.manage) → leaders who may update the member's
--     record (members.records.update in scope) or hold members.qr.manage may now replace it.
--   * Ron (2026-10-14): the QR must also carry the member's envelope number (members.member_number, assigned by
--     the Finance admin). QR text is now
--         MFCNY1:<envelope number>:<token public uuid>:<20-hex HMAC>
--     The signature covers the token id, version AND the envelope number, so the number cannot be altered.
--     If Finance later changes a member's number, the member's card shows the new number automatically; an old
--     screenshot is then refused as 'number_changed'. Members without a number yet get an empty number segment.
-- Only these functions change; bodies are otherwise identical to migration 132.
-- =============================================================================

-- QR text: MFCNY1:<envelope number>:<public id>:<signature over id, version and number>
drop function if exists private.member_qr_payload(text, integer);
create or replace function private.member_qr_sign(p_token_public_id text, p_token_version integer, p_member_number text)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'private'
as $$
  select private.member_qr_signature(p_token_public_id || ':' || coalesce(p_member_number, ''), p_token_version);
$$;
revoke all on function private.member_qr_sign(text, integer, text) from public, anon, authenticated;

create or replace function private.member_qr_payload(p_token_public_id text, p_token_version integer, p_member_number text)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'private'
as $$
  select 'MFCNY1:' || coalesce(p_member_number, '') || ':' || p_token_public_id || ':'
         || private.member_qr_sign(p_token_public_id, p_token_version, p_member_number);
$$;
revoke all on function private.member_qr_payload(text, integer, text) from public, anon, authenticated;

create or replace function private.issue_member_qr(
  p_organization_id uuid, p_member_id uuid, p_actor uuid, p_reason text
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'extensions'
as $$
declare
  v_old_ids uuid[];
  v_version integer;
  v_public_id uuid := gen_random_uuid();
  v_token_id uuid := gen_random_uuid();
  v_card_id uuid := gen_random_uuid();
  v_sig text;
begin
  select array_agg(t.id), coalesce(max(t.token_version), 0)
  into v_old_ids, v_version
  from public.member_qr_tokens t
  where t.organization_id = p_organization_id and t.member_id = p_member_id;

  -- close every active card and token first
  update public.member_id_cards
  set card_status = 'replaced', revoked_at = clock_timestamp(), revoked_by_profile_id = p_actor,
      revocation_reason = coalesce(p_reason, 'Replaced by a new card')
  where organization_id = p_organization_id and member_id = p_member_id and card_status = 'active';

  update public.member_qr_tokens
  set token_status = 'replaced', is_primary = false, revoked_at = clock_timestamp(), revoked_by_profile_id = p_actor,
      revocation_reason = coalesce(p_reason, 'Replaced by a new QR')
  where organization_id = p_organization_id and member_id = p_member_id and token_status = 'active';

  v_version := v_version + 1;
  v_sig := private.member_qr_sign(v_public_id::text, v_version,
                                  (select m.member_number from public.members m where m.id = p_member_id));

  insert into public.member_qr_tokens (
    id, organization_id, member_id, token_hash, token_public_id, token_status, token_version,
    is_primary, issued_at, issued_by_profile_id, use_count
  ) values (
    v_token_id, p_organization_id, p_member_id, encode(digest(v_sig, 'sha256'), 'hex'), v_public_id, 'active', v_version,
    true, clock_timestamp(), p_actor, 0
  );

  update public.member_qr_tokens
  set replaced_by_token_id = v_token_id
  where id = any(coalesce(v_old_ids, '{}'::uuid[])) and token_status = 'replaced' and replaced_by_token_id is null;

  insert into public.member_id_cards (
    id, organization_id, member_id, member_qr_token_id, card_status, card_version,
    issued_at, issued_by_profile_id
  ) values (
    v_card_id, p_organization_id, p_member_id, v_token_id, 'active', v_version,
    clock_timestamp(), p_actor
  );

  insert into public.member_qr_token_events (organization_id, member_id, member_qr_token_id, event_type, actor_profile_id,
                                             event_summary, metadata, occurred_at)
  values (p_organization_id, p_member_id, v_token_id, 'issued', p_actor, coalesce(p_reason, 'QR issued'),
          jsonb_build_object('token_version', v_version), clock_timestamp()),
         (p_organization_id, p_member_id, v_token_id, 'card_issued', p_actor, 'ID card issued',
          jsonb_build_object('card_id', v_card_id), clock_timestamp());

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.qr.issued',
    p_event_category   => 'member',
    p_actor_profile_id => p_actor,
    p_entity_type      => 'member',
    p_entity_id        => p_member_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_metadata         => jsonb_build_object('token_id', v_token_id, 'card_id', v_card_id, 'token_version', v_version,
                                             'reason', p_reason)
  );

  return v_token_id;
end;
$$;
revoke all on function private.issue_member_qr(uuid, uuid, uuid, text) from public, anon, authenticated;

create or replace function private.member_card_json(p_organization_id uuid, p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_t record;
  v_ctx jsonb;
begin
  select t.id, t.token_public_id, t.token_version, t.issued_at, c.card_public_id, c.card_status
  into v_t
  from public.member_qr_tokens t
  left join public.member_id_cards c on c.member_qr_token_id = t.id and c.card_status = 'active'
  where t.organization_id = p_organization_id and t.member_id = p_member_id and t.token_status = 'active'
  order by t.issued_at desc
  limit 1;
  if v_t.id is null then
    return null;
  end if;

  v_ctx := private.build_member_self_context(p_organization_id, p_member_id);

  return jsonb_build_object(
    'qr_payload', private.member_qr_payload(v_t.token_public_id::text, v_t.token_version,
                                            (select m.member_number from public.members m where m.id = p_member_id)),
    'card_public_id', v_t.card_public_id,
    'issued_at', v_t.issued_at,
    'member_id', p_member_id,
    'member_number', v_ctx->'member'->>'member_number',
    'display_name', v_ctx->'member'->>'display_name',
    'membership_status', v_ctx->'member'->>'membership_status',
    'photo_path', (select m.profile_photo_storage_path from public.members m where m.id = p_member_id),
    'organizational_context', v_ctx->'organizational_context',
    'household_name', v_ctx->'household'->>'household_name'
  );
end;
$$;
revoke all on function private.member_card_json(uuid, uuid) from public, anon, authenticated;

create or replace function public.reissue_member_card(
  p_organization_id uuid,
  p_member_id uuid default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_member_id uuid;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if p_member_id is null or p_member_id = private.current_member_id(p_organization_id) then
    v_member_id := private.assert_member_self_edit(p_organization_id);
  else
    if not (private.can_access_member('members.qr.manage', p_organization_id, p_member_id)
            or private.can_access_member('members.records.update', p_organization_id, p_member_id)) then
      raise exception using errcode = '42501', message = 'You do not have permission to replace this member''s QR.';
    end if;
    if nullif(btrim(p_reason), '') is null then
      raise exception using errcode = '23502', message = 'Please give a reason for replacing the QR.';
    end if;
    v_member_id := p_member_id;
  end if;

  if not exists (select 1 from public.members m where m.id = v_member_id and m.organization_id = p_organization_id
                 and m.record_status = 'active') then
    raise exception using errcode = '22023', message = 'Only active members can have an ID card.';
  end if;

  perform private.issue_member_qr(p_organization_id, v_member_id, v_actor,
                                  coalesce(nullif(btrim(p_reason), ''), 'Replaced by the member'));
  return private.member_card_json(p_organization_id, v_member_id);
end;
$$;
revoke all on function public.reissue_member_card(uuid, uuid, text) from public, anon;
grant execute on function public.reissue_member_card(uuid, uuid, text) to authenticated;

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

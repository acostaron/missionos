-- =============================================================================
-- Migration: 20261010063000_member_portal_self_service.sql
-- MissionOS Pass 8.2 — Member portal backend (written by Claude, 2026-10-14)
--
-- Ron's decisions (2026-10-14): members edit their own profile DIRECTLY (every change is logged); members upload
-- their own photo (admins can replace it); every member has a QR ID card on their phone; portal v1 shows
-- My profile, My QR card, My events, My attendance. Wedding date = family_relationships.effective_from on the
-- active spouse row (no new column).
--
-- 1. Permission members.self_service.edit (granted only to the system 'member' role).
-- 2. Self-service RPCs (the caller's member is resolved from their verified self link; no member id is accepted):
--      get_my_profile_details, update_my_basic_profile, set_my_contact_point, set_my_wedding_date
-- 3. Photos: private storage bucket 'member-photos' (path <org>/<member>/<file>), storage policies, and
--      set_member_photo (self, or leaders with members.records.update for that member).
-- 4. QR ID card: HMAC-signed QR (key kept in Vault, only a hash stored), using the existing member_qr_tokens,
--      member_id_cards and member_qr_token_events tables:
--      get_my_member_card (issues one the first time), reissue_member_card (self or members.qr.manage),
--      resolve_member_qr (for check-in later; events.attendance.record or members.qr.view).
-- 5. My events / my attendance: list_my_events, list_my_attendance.
-- =============================================================================

-- =============================================================================
-- 1. Permission
-- =============================================================================
insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
)
values (
  'members.self_service.edit',
  'Edit own member profile',
  'Allows a signed-in linked member to change ONLY their own name spelling, birth date, sex, contact details, wedding date and photo through the self-service RPCs. Every change is logged.',
  'members', 'update', 'organization', 'standard', false, true, true
)
on conflict (code) do nothing;

insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code = 'member'
  and r.is_system_role
  and p.code = 'members.self_service.edit'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

-- =============================================================================
-- 2. Self-service helpers and RPCs
-- =============================================================================

-- Caller must be a linked, active member with members.self_service.edit. Returns their member id.
create or replace function private.assert_member_self_edit(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  if not private.has_permission('members.self_service.edit', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to edit your own profile.';
  end if;
  if not exists (
    select 1 from public.members m
    where m.id = v_member_id and m.organization_id = p_organization_id
      and m.record_status = 'active' and coalesce(m.is_deceased, false) = false
  ) then
    raise exception using errcode = '42501', message = 'Your member record is not active. Please contact your chapter servant.';
  end if;
  return v_member_id;
end;
$$;
revoke all on function private.assert_member_self_edit(uuid) from public, anon, authenticated;

-- The active spouse row(s) of a member (rows are stored once per couple, either direction).
create or replace function private.member_spouse_row_ids(p_organization_id uuid, p_member_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select fr.id
  from public.family_relationships fr
  join public.family_relationship_types t on t.id = fr.relationship_type_id
  where fr.organization_id = p_organization_id
    and t.code = 'spouse'
    and fr.relationship_status = 'active'
    and fr.effective_to is null
    and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id);
$$;
revoke all on function private.member_spouse_row_ids(uuid, uuid) from public, anon, authenticated;

-- 2a. Everything the "Edit my profile" screen needs
create or replace function public.get_my_profile_details(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
  v_m record;
  v_n record;
  v_spouse jsonb;
  v_addr jsonb;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);

  select m.id, m.member_number, m.display_name, m.preferred_name, m.birth_date, m.sex, m.civil_status,
         m.profile_photo_storage_path, m.record_status
  into v_m
  from public.members m
  where m.id = v_member_id and m.organization_id = p_organization_id;

  select n.given_names, n.middle_names, n.family_name, n.preferred_given_name
  into v_n
  from public.member_names n
  where n.organization_id = p_organization_id and n.member_id = v_member_id
    and n.is_primary and n.effective_to is null
  limit 1;

  select jsonb_build_object(
           'display_name', sm.display_name,
           'wedding_date', fr.effective_from)
  into v_spouse
  from public.family_relationships fr
  join public.members sm
    on sm.id = case when fr.from_member_id = v_member_id then fr.to_member_id else fr.from_member_id end
  where fr.id in (select private.member_spouse_row_ids(p_organization_id, v_member_id))
  order by fr.is_primary_relationship desc, fr.created_at desc
  limit 1;

  select jsonb_build_object(
           'member_address_id', ma.id,
           'line1', a.address_line_1, 'line2', a.address_line_2,
           'city', a.city_name, 'state', a.state_province_name,
           'postal', a.postal_code, 'country', a.country_code)
  into v_addr
  from public.member_addresses ma
  join public.addresses a on a.id = ma.address_id
  where ma.organization_id = p_organization_id and ma.member_id = v_member_id
    and ma.address_type = 'home' and ma.effective_to is null
  order by ma.is_primary desc, ma.effective_from desc nulls last
  limit 1;

  return jsonb_build_object(
    'member_id', v_m.id,
    'member_number', v_m.member_number,
    'display_name', v_m.display_name,
    'given_names', v_n.given_names,
    'middle_names', v_n.middle_names,
    'family_name', v_n.family_name,
    'preferred_name', v_n.preferred_given_name,
    'birth_date', v_m.birth_date,
    'sex', v_m.sex,
    'civil_status', v_m.civil_status,
    'photo_path', v_m.profile_photo_storage_path,
    'can_edit', private.has_permission('members.self_service.edit', p_organization_id) and v_m.record_status = 'active',
    'emails', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'email', e.email_address, 'type', e.email_type, 'is_primary', e.is_primary)
                       order by e.is_primary desc, e.effective_from_at)
      from public.member_emails e
      where e.organization_id = p_organization_id and e.member_id = v_member_id and e.effective_to_at is null), '[]'::jsonb),
    'phones', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'phone', p.phone_number, 'type', p.phone_type, 'is_primary', p.is_primary)
                       order by p.is_primary desc, p.effective_from_at)
      from public.member_phones p
      where p.organization_id = p_organization_id and p.member_id = v_member_id and p.effective_to_at is null), '[]'::jsonb),
    'home_address', v_addr,
    'spouse', v_spouse
  );
end;
$$;
revoke all on function public.get_my_profile_details(uuid) from public, anon;
grant execute on function public.get_my_profile_details(uuid) to authenticated;

-- 2b. Name spelling, birth date, sex (spelling corrections only; legal name changes stay with leaders)
create or replace function public.update_my_basic_profile(
  p_organization_id uuid,
  p_given_names text,
  p_family_name text,
  p_middle_names text default null,
  p_preferred_name text default null,
  p_birth_date date default null,
  p_sex text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_member_id uuid;
  v_cur public.member_names%rowtype;
  v_before jsonb;
  v_full text; v_pref text; v_disp text; v_sort text;
begin
  v_member_id := private.assert_member_self_edit(p_organization_id);

  if nullif(btrim(p_given_names), '') is null or nullif(btrim(p_family_name), '') is null then
    raise exception using errcode = '23502', message = 'First name and last name are required.';
  end if;
  if length(btrim(p_given_names)) > 100 or length(btrim(p_family_name)) > 100
     or length(coalesce(btrim(p_middle_names), '')) > 100 or length(coalesce(btrim(p_preferred_name), '')) > 100 then
    raise exception using errcode = '22023', message = 'Names can be at most 100 characters.';
  end if;
  if p_birth_date is not null and (p_birth_date > current_date or p_birth_date < date '1900-01-01') then
    raise exception using errcode = '22023', message = 'Please enter a valid birth date.';
  end if;
  if nullif(btrim(p_sex), '') is not null and btrim(p_sex) not in ('male', 'female') then
    raise exception using errcode = '22023', message = 'Sex must be male or female.';
  end if;

  select * into v_cur
  from public.member_names
  where organization_id = p_organization_id and member_id = v_member_id
    and is_primary = true and effective_to is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Your name record was not found. Please contact your chapter servant.';
  end if;

  select jsonb_build_object('given_names', v_cur.given_names, 'middle_names', v_cur.middle_names,
                            'family_name', v_cur.family_name, 'preferred_name', v_cur.preferred_given_name,
                            'birth_date', m.birth_date, 'sex', m.sex)
  into v_before
  from public.members m where m.id = v_member_id;

  v_full := btrim(btrim(p_given_names) || ' ' || coalesce(nullif(btrim(p_middle_names), '') || ' ', '') || btrim(p_family_name));
  v_pref := coalesce(nullif(btrim(p_preferred_name), ''), btrim(p_given_names));
  v_disp := btrim(v_pref || ' ' || btrim(p_family_name));
  v_sort := btrim(btrim(p_family_name) || ', ' || btrim(p_given_names) || coalesce(' ' || nullif(btrim(p_middle_names), ''), ''));

  update public.member_names
  set given_names = btrim(p_given_names),
      middle_names = nullif(btrim(p_middle_names), ''),
      family_name = btrim(p_family_name),
      preferred_given_name = nullif(btrim(p_preferred_name), ''),
      full_name = v_full,
      sort_name = v_sort,
      updated_at = now(),
      updated_by_profile_id = v_actor
  where id = v_cur.id;

  update public.members
  set preferred_name = v_pref,
      display_name = v_disp,
      sort_name = v_sort,
      birth_date = p_birth_date,
      sex = coalesce(nullif(btrim(p_sex), ''), sex),
      updated_at = now(),
      updated_by_profile_id = v_actor
  where id = v_member_id and organization_id = p_organization_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.updated',
    p_event_category   => 'member',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'member',
    p_entity_id        => v_member_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_metadata         => jsonb_build_object(
      'via', 'self_service',
      'before', v_before,
      'after', jsonb_build_object('given_names', btrim(p_given_names), 'middle_names', nullif(btrim(p_middle_names), ''),
                                  'family_name', btrim(p_family_name), 'preferred_name', nullif(btrim(p_preferred_name), ''),
                                  'birth_date', p_birth_date, 'sex', coalesce(nullif(btrim(p_sex), ''), v_before->>'sex')))
  );

  return jsonb_build_object('status', 'success', 'member_id', v_member_id, 'display_name', v_disp);
end;
$$;
revoke all on function public.update_my_basic_profile(uuid, text, text, text, text, date, text) from public, anon;
grant execute on function public.update_my_basic_profile(uuid, text, text, text, text, date, text) to authenticated;

-- 2c. My email / phone / home address (same storage rules as the leader screen)
--   p_contact_type: 'email' | 'phone' | 'address'
--   p_operation:    'add' (email/phone) | 'replace_primary' | 'remove' (needs p_target_id)
--   p_address_data: {"line1","line2","city","state","postal","country"} for addresses
create or replace function public.set_my_contact_point(
  p_organization_id uuid,
  p_contact_type text,
  p_operation text,
  p_target_id uuid default null,
  p_value text default null,
  p_address_data jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_member_id uuid;
  v_norm text;
  v_new_id uuid;
  v_addr_id uuid;
  v_has_primary boolean;
  v_make_primary boolean;
begin
  v_member_id := private.assert_member_self_edit(p_organization_id);

  if p_contact_type not in ('email', 'phone', 'address') then
    raise exception using errcode = '22023', message = 'Contact type must be email, phone or address.';
  end if;
  if p_operation not in ('add', 'replace_primary', 'remove') then
    raise exception using errcode = '22023', message = 'Operation must be add, replace_primary or remove.';
  end if;
  if p_contact_type = 'address' and p_operation = 'add' then
    raise exception using errcode = '22023', message = 'Use replace_primary to set your home address.';
  end if;
  if p_operation = 'remove' and p_target_id is null then
    raise exception using errcode = '23502', message = 'Choose which item to remove.';
  end if;

  -- ---------------------------------------------------------------- EMAIL
  if p_contact_type = 'email' then
    if p_operation = 'remove' then
      update public.member_emails
      set effective_to_at = greatest(clock_timestamp(), effective_from_at + interval '1 millisecond'),
          is_primary = false, updated_at = now(), updated_by_profile_id = v_actor
      where id = p_target_id and organization_id = p_organization_id and member_id = v_member_id
        and effective_to_at is null;
      if not found then
        raise exception using errcode = 'P0002', message = 'That email was not found on your profile.';
      end if;
      v_new_id := p_target_id;
    else
      if nullif(btrim(p_value), '') is null or btrim(p_value) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(btrim(p_value)) > 254 then
        raise exception using errcode = '22023', message = 'Please enter a valid email address.';
      end if;
      v_norm := private.normalize_email(p_value);
      if exists (select 1 from public.member_emails e
                 where e.member_id = v_member_id and e.effective_to_at is null and e.normalized_email = v_norm) then
        raise exception using errcode = '23505', message = 'This email is already on your profile.';
      end if;
      if p_operation = 'replace_primary' then
        update public.member_emails
        set effective_to_at = greatest(clock_timestamp(), effective_from_at + interval '1 millisecond'),
            is_primary = false, updated_at = now(), updated_by_profile_id = v_actor
        where organization_id = p_organization_id and member_id = v_member_id
          and is_primary = true and effective_to_at is null;
      end if;
      select exists (select 1 from public.member_emails e
                     where e.member_id = v_member_id and e.effective_to_at is null and e.is_primary)
      into v_has_primary;
      v_make_primary := (p_operation = 'replace_primary') or not v_has_primary;
      v_new_id := gen_random_uuid();
      insert into public.member_emails (
        id, organization_id, member_id, email_address, normalized_email,
        email_type, is_primary, is_shared, verification_status, allows_ministry_email,
        effective_from_at, created_by_profile_id, updated_by_profile_id
      ) values (
        v_new_id, p_organization_id, v_member_id, btrim(p_value), v_norm,
        case when v_norm like '%@mfcny.net' then 'ministry' else 'personal' end,
        v_make_primary, false, 'unverified', true,
        clock_timestamp(), v_actor, v_actor
      );
    end if;

  -- ---------------------------------------------------------------- PHONE
  elsif p_contact_type = 'phone' then
    if p_operation = 'remove' then
      update public.member_phones
      set effective_to_at = greatest(clock_timestamp(), effective_from_at + interval '1 millisecond'),
          is_primary = false, updated_at = now(), updated_by_profile_id = v_actor
      where id = p_target_id and organization_id = p_organization_id and member_id = v_member_id
        and effective_to_at is null;
      if not found then
        raise exception using errcode = 'P0002', message = 'That phone number was not found on your profile.';
      end if;
      v_new_id := p_target_id;
    else
      if nullif(btrim(p_value), '') is null then
        raise exception using errcode = '23502', message = 'Please enter a phone number.';
      end if;
      v_norm := private.normalize_phone_e164(p_value, 'US');
      if v_norm is null then
        raise exception using errcode = '22023', message = 'Please enter a 10-digit US number, or an international number starting with +.';
      end if;
      if exists (select 1 from public.member_phones p
                 where p.member_id = v_member_id and p.effective_to_at is null and p.normalized_e164 = v_norm) then
        raise exception using errcode = '23505', message = 'This number is already on your profile.';
      end if;
      if p_operation = 'replace_primary' then
        update public.member_phones
        set effective_to_at = greatest(clock_timestamp(), effective_from_at + interval '1 millisecond'),
            is_primary = false, updated_at = now(), updated_by_profile_id = v_actor
        where organization_id = p_organization_id and member_id = v_member_id
          and is_primary = true and effective_to_at is null;
      end if;
      select exists (select 1 from public.member_phones p
                     where p.member_id = v_member_id and p.effective_to_at is null and p.is_primary)
      into v_has_primary;
      v_make_primary := (p_operation = 'replace_primary') or not v_has_primary;
      v_new_id := gen_random_uuid();
      insert into public.member_phones (
        id, organization_id, member_id, phone_number, normalized_e164,
        phone_type, country_code, is_primary, is_shared, verification_status,
        allows_voice_calls, allows_sms, allows_messaging_apps, effective_from_at,
        created_by_profile_id, updated_by_profile_id
      ) values (
        v_new_id, p_organization_id, v_member_id, btrim(p_value), v_norm,
        'mobile', 'US', v_make_primary, false, 'unverified',
        true, true, false, clock_timestamp(), v_actor, v_actor
      );
    end if;

  -- ---------------------------------------------------------------- ADDRESS
  else
    if p_operation = 'remove' then
      update public.member_addresses
      set effective_to = current_date, is_primary = false, updated_at = now(), updated_by_profile_id = v_actor
      where id = p_target_id and organization_id = p_organization_id and member_id = v_member_id
        and effective_to is null;
      if not found then
        raise exception using errcode = 'P0002', message = 'That address was not found on your profile.';
      end if;
      v_new_id := p_target_id;
    else
      if p_address_data is null or jsonb_typeof(p_address_data) <> 'object'
         or nullif(btrim(p_address_data->>'line1'), '') is null
         or nullif(btrim(p_address_data->>'city'), '') is null then
        raise exception using errcode = '23502', message = 'Street address and city are required.';
      end if;
      -- end the current home address today (or remove it if it started today)
      update public.member_addresses
      set effective_to = case when effective_from = current_date then current_date else current_date - 1 end,
          is_primary = false, updated_at = now(), updated_by_profile_id = v_actor
      where organization_id = p_organization_id and member_id = v_member_id
        and address_type = 'home' and effective_to is null;

      v_addr_id := gen_random_uuid();
      insert into public.addresses (
        id, organization_id, address_line_1, address_line_2,
        city_name, state_province_name, postal_code, country_code,
        verification_status, source, created_by_profile_id, updated_by_profile_id
      ) values (
        v_addr_id, p_organization_id, btrim(p_address_data->>'line1'), nullif(btrim(p_address_data->>'line2'), ''),
        btrim(p_address_data->>'city'), nullif(btrim(p_address_data->>'state'), ''), nullif(btrim(p_address_data->>'postal'), ''),
        coalesce(nullif(btrim(p_address_data->>'country'), ''), 'US'), 'unverified', 'manual',
        v_actor, v_actor
      );
      v_new_id := gen_random_uuid();
      insert into public.member_addresses (
        id, organization_id, member_id, address_id, address_type,
        is_primary, is_mailing_address, is_shared_family_address,
        effective_from, visibility, created_by_profile_id, updated_by_profile_id
      ) values (
        v_new_id, p_organization_id, v_member_id, v_addr_id, 'home',
        true, true, false,
        current_date, 'leaders_only', v_actor, v_actor
      );
    end if;
  end if;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.contact.updated',
    p_event_category   => 'member',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'member',
    p_entity_id        => v_member_id,
    p_action           => p_operation,
    p_outcome          => 'success',
    p_metadata         => jsonb_build_object('via', 'self_service', 'contact_type', p_contact_type,
                                             'operation', p_operation, 'record_id', v_new_id)
  );

  return jsonb_build_object('status', 'success', 'member_id', v_member_id,
                            'contact_type', p_contact_type, 'operation', p_operation, 'record_id', v_new_id);
end;
$$;
revoke all on function public.set_my_contact_point(uuid, text, text, uuid, text, jsonb) from public, anon;
grant execute on function public.set_my_contact_point(uuid, text, text, uuid, text, jsonb) to authenticated;

-- 2d. Wedding date (on the active spouse row; both spouses see the same date)
create or replace function public.set_my_wedding_date(p_organization_id uuid, p_wedding_date date)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_member_id uuid;
  v_ids uuid[];
  v_before date;
begin
  v_member_id := private.assert_member_self_edit(p_organization_id);

  if p_wedding_date is not null and (p_wedding_date > current_date or p_wedding_date < date '1930-01-01') then
    raise exception using errcode = '22023', message = 'Please enter a valid wedding date.';
  end if;

  select array_agg(x) into v_ids from private.member_spouse_row_ids(p_organization_id, v_member_id) x;
  if v_ids is null then
    raise exception using errcode = 'P0002',
      message = 'Your spouse is not linked to your record yet. Please ask your chapter servant to link your spouse first.';
  end if;

  select min(fr.effective_from) into v_before from public.family_relationships fr where fr.id = any(v_ids);

  update public.family_relationships
  set effective_from = p_wedding_date, updated_at = now(), updated_by_profile_id = v_actor
  where id = any(v_ids);

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.wedding_date.updated',
    p_event_category   => 'member',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'member',
    p_entity_id        => v_member_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_metadata         => jsonb_build_object('via', 'self_service', 'relationship_ids', to_jsonb(v_ids),
                                             'before', v_before, 'after', p_wedding_date)
  );

  return jsonb_build_object('status', 'success', 'wedding_date', p_wedding_date, 'rows_updated', cardinality(v_ids));
end;
$$;
revoke all on function public.set_my_wedding_date(uuid, date) from public, anon;
grant execute on function public.set_my_wedding_date(uuid, date) to authenticated;

-- =============================================================================
-- 3. Member photos
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('member-photos', 'member-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Parse '<org uuid>/<member uuid>/<file>' safely; null when the path has another shape.
create or replace function private.member_photo_path_parts(p_name text, out o_org uuid, out o_member uuid)
language plpgsql
immutable
set search_path to 'pg_catalog'
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_uuid_re text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  o_org := null; o_member := null;
  if p_name is null or array_length(v_parts, 1) <> 3 or coalesce(v_parts[3], '') = ''
     or v_parts[1] !~ v_uuid_re or v_parts[2] !~ v_uuid_re then
    return;
  end if;
  o_org := v_parts[1]::uuid;
  o_member := v_parts[2]::uuid;
end;
$$;
revoke all on function private.member_photo_path_parts(text) from public, anon, authenticated;

-- Used by the storage policies (run as the signed-in user, so they live in public and are SECURITY DEFINER).
create or replace function public.can_write_member_photo(p_object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_org uuid; v_member uuid;
begin
  select o_org, o_member into v_org, v_member from private.member_photo_path_parts(p_object_name);
  if v_org is null or private.current_profile_id() is null then
    return false;
  end if;
  if private.current_member_id(v_org) = v_member
     and private.has_permission('members.self_service.edit', v_org) then
    return true;
  end if;
  return private.can_access_member('members.records.update', v_org, v_member);
end;
$$;
revoke all on function public.can_write_member_photo(text) from public, anon;
grant execute on function public.can_write_member_photo(text) to authenticated;

create or replace function public.can_read_member_photo(p_object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_org uuid; v_member uuid;
begin
  select o_org, o_member into v_org, v_member from private.member_photo_path_parts(p_object_name);
  if v_org is null or private.current_profile_id() is null then
    return false;
  end if;
  if private.current_member_id(v_org) = v_member
     and private.has_permission('members.self_service.view', v_org) then
    return true;
  end if;
  return private.can_access_member('members.records.view', v_org, v_member);
end;
$$;
revoke all on function public.can_read_member_photo(text) from public, anon;
grant execute on function public.can_read_member_photo(text) to authenticated;

drop policy if exists "member_photos_select" on storage.objects;
create policy "member_photos_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'member-photos' and public.can_read_member_photo(name));

drop policy if exists "member_photos_insert" on storage.objects;
create policy "member_photos_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'member-photos' and public.can_write_member_photo(name));

drop policy if exists "member_photos_update" on storage.objects;
create policy "member_photos_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'member-photos' and public.can_write_member_photo(name))
  with check (bucket_id = 'member-photos' and public.can_write_member_photo(name));

drop policy if exists "member_photos_delete" on storage.objects;
create policy "member_photos_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'member-photos' and public.can_write_member_photo(name));

-- Point the member record at an uploaded photo (p_member_id null = myself). p_storage_path null = remove photo.
create or replace function public.set_member_photo(
  p_organization_id uuid,
  p_member_id uuid default null,
  p_storage_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth', 'storage'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_member_id uuid;
  v_self boolean;
  v_org uuid; v_path_member uuid;
  v_before text;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if p_member_id is null or p_member_id = private.current_member_id(p_organization_id) then
    v_member_id := private.assert_member_self_edit(p_organization_id);
    v_self := true;
  else
    if not private.can_access_member('members.records.update', p_organization_id, p_member_id) then
      raise exception using errcode = '42501', message = 'You do not have permission to change this member''s photo.';
    end if;
    v_member_id := p_member_id;
    v_self := false;
  end if;

  if p_storage_path is not null then
    select o_org, o_member into v_org, v_path_member from private.member_photo_path_parts(p_storage_path);
    if v_org is distinct from p_organization_id or v_path_member is distinct from v_member_id then
      raise exception using errcode = '22023', message = 'The photo path does not belong to this member.';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'member-photos' and o.name = p_storage_path) then
      raise exception using errcode = 'P0002', message = 'The photo was not found. Please upload it again.';
    end if;
  end if;

  select m.profile_photo_storage_path into v_before
  from public.members m where m.id = v_member_id and m.organization_id = p_organization_id;

  update public.members
  set profile_photo_storage_path = p_storage_path, updated_at = now(), updated_by_profile_id = v_actor
  where id = v_member_id and organization_id = p_organization_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.photo.updated',
    p_event_category   => 'member',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'member',
    p_entity_id        => v_member_id,
    p_action           => case when p_storage_path is null then 'remove' else 'update' end,
    p_outcome          => 'success',
    p_metadata         => jsonb_build_object('via', case when v_self then 'self_service' else 'leader' end,
                                             'before', v_before, 'after', p_storage_path)
  );

  return jsonb_build_object('status', 'success', 'member_id', v_member_id, 'photo_path', p_storage_path,
                            'previous_photo_path', v_before);
end;
$$;
revoke all on function public.set_member_photo(uuid, uuid, text) from public, anon;
grant execute on function public.set_member_photo(uuid, uuid, text) to authenticated;

-- =============================================================================
-- 4. QR ID card
-- =============================================================================
-- Signing key lives in Vault (generated here, never in the repo).
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'missionos_member_qr_hmac_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'missionos_member_qr_hmac_key',
      'MissionOS: HMAC key that signs member QR ID codes (Pass 8.2). Rotating it invalidates every printed/saved QR.'
    );
  end if;
end;
$$;

create or replace function private.member_qr_signature(p_token_public_id text, p_token_version integer)
returns text
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'extensions'
as $$
declare
  v_key text;
begin
  select ds.decrypted_secret into v_key
  from vault.decrypted_secrets ds
  where ds.name = 'missionos_member_qr_hmac_key';
  if v_key is null then
    raise exception using errcode = 'P0002', message = 'QR signing key is missing.';
  end if;
  return left(encode(hmac(p_token_public_id || ':' || p_token_version::text, v_key, 'sha256'), 'hex'), 20);
end;
$$;
revoke all on function private.member_qr_signature(text, integer) from public, anon, authenticated;

-- QR text shown on the card: MFCNY1:<public id>:<signature>
create or replace function private.member_qr_payload(p_token_public_id text, p_token_version integer)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'private'
as $$
  select 'MFCNY1:' || p_token_public_id || ':' || private.member_qr_signature(p_token_public_id, p_token_version);
$$;
revoke all on function private.member_qr_payload(text, integer) from public, anon, authenticated;

-- Replace any active token/card and issue a new pair. Returns the new token id.
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
  v_public_id text;
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
  loop
    v_public_id := upper(encode(gen_random_bytes(6), 'hex'));
    exit when not exists (select 1 from public.member_qr_tokens t where t.token_public_id = v_public_id);
  end loop;
  v_sig := private.member_qr_signature(v_public_id, v_version);

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
    id, organization_id, member_id, member_qr_token_id, card_public_id, card_status, card_version,
    issued_at, issued_by_profile_id
  ) values (
    v_card_id, p_organization_id, p_member_id, v_token_id, 'C' || v_public_id, 'active', v_version,
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

-- Card content for a member's active token
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
    'qr_payload', private.member_qr_payload(v_t.token_public_id, v_t.token_version),
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

-- 4a. My QR ID card (issued automatically the first time)
create or replace function public.get_my_member_card(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
  v_card jsonb;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  if not exists (select 1 from public.members m where m.id = v_member_id and m.record_status = 'active') then
    raise exception using errcode = '42501', message = 'Your member record is not active, so no ID card can be shown.';
  end if;

  v_card := private.member_card_json(p_organization_id, v_member_id);
  if v_card is null then
    perform private.issue_member_qr(p_organization_id, v_member_id, private.current_profile_id(), 'First card (member portal)');
    v_card := private.member_card_json(p_organization_id, v_member_id);
  end if;
  return v_card;
end;
$$;
revoke all on function public.get_my_member_card(uuid) from public, anon;
grant execute on function public.get_my_member_card(uuid) to authenticated;

-- 4b. Replace a QR (lost phone, shared screenshot). p_member_id null = myself.
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
    if not (private.has_permission('members.qr.manage', p_organization_id)
            and private.can_access_member('members.qr.manage', p_organization_id, p_member_id)) then
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

-- 4c. Read a scanned QR (for check-in, Pass 7.4). Returns {valid, reason} or {valid, member...}.
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
  if array_length(v_parts, 1) <> 3 or v_parts[1] <> 'MFCNY1' or v_parts[2] !~ '^[0-9A-F]{12}$' or v_parts[3] !~ '^[0-9a-f]{20}$' then
    return jsonb_build_object('valid', false, 'reason', 'not_a_member_qr');
  end if;

  select t.* into v_t
  from public.member_qr_tokens t
  where t.token_public_id = v_parts[2] and t.organization_id = p_organization_id;
  if not found then
    return jsonb_build_object('valid', false, 'reason', 'unknown_qr');
  end if;

  if private.member_qr_signature(v_t.token_public_id, v_t.token_version) <> v_parts[3] then
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

-- =============================================================================
-- 5. My events / my attendance
-- =============================================================================
-- Events for me between two New York dates: events whose audience includes me, program sessions I am registered for,
-- and any event where my attendance was recorded. Cancelled events are included (flagged) so members are informed.
create or replace function public.list_my_events(p_organization_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
  v_from timestamptz;
  v_to timestamptz;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    raise exception using errcode = '22023', message = 'Choose a date range of up to 400 days.';
  end if;
  v_from := (p_from::timestamp) at time zone 'America/New_York';
  v_to := ((p_to + 1)::timestamp) at time zone 'America/New_York';

  return coalesce((
    select jsonb_agg(x.j order by x.starts_at)
    from (
      select e.starts_at,
             jsonb_build_object(
               'event_id', e.id,
               'event_type', e.event_type,
               'title', e.title,
               'starts_at', e.starts_at,
               'ends_at', e.ends_at,
               'location_text', e.location_text,
               'event_status', e.event_status,
               'audience_name', an.name,
               'program_title', pr.title,
               'session_number', e.session_number,
               'session_count', pr.session_count,
               'attended', exists (select 1 from public.event_attendance a
                                   where a.event_id = e.id and a.member_id = v_member_id and a.removed_at is null)
                           or exists (select 1 from public.program_participant_attendance pa
                                      join public.program_participants pp on pp.id = pa.participant_id
                                      where pa.event_id = e.id and pp.member_id = v_member_id and pa.removed_at is null)
             ) as j
      from public.events e
      left join public.governance_nodes an on an.id = e.audience_node_id
      left join public.program_runs pr on pr.id = e.program_run_id
      where e.organization_id = p_organization_id
        and e.starts_at >= v_from and e.starts_at < v_to
        and (
          (e.program_run_id is null and private.member_in_event_audience(p_organization_id, v_member_id, e.audience_node_id))
          or (e.program_run_id is not null and exists (
                select 1 from public.program_participants pp
                where pp.program_run_id = e.program_run_id and pp.member_id = v_member_id
                  and pp.participant_status = 'registered'))
          or exists (select 1 from public.event_attendance a
                     where a.event_id = e.id and a.member_id = v_member_id and a.removed_at is null)
        )
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_events(uuid, date, date) from public, anon;
grant execute on function public.list_my_events(uuid, date, date) to authenticated;

-- My attendance record (events where I was marked present), newest first.
create or replace function public.list_my_attendance(p_organization_id uuid, p_from date default null, p_to date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member_id uuid;
  v_from timestamptz;
  v_to timestamptz;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  v_from := (coalesce(p_from, date '2000-01-01')::timestamp) at time zone 'America/New_York';
  v_to := ((coalesce(p_to, (now() at time zone 'America/New_York')::date) + 1)::timestamp) at time zone 'America/New_York';

  return coalesce((
    select jsonb_agg(x.j order by x.starts_at desc)
    from (
      select e.starts_at,
             jsonb_build_object(
               'event_id', e.id,
               'event_type', e.event_type,
               'title', e.title,
               'starts_at', e.starts_at,
               'event_status', e.event_status,
               'program_title', pr.title,
               'session_number', e.session_number,
               'recorded_at', att.recorded_at,
               'check_in_method', att.check_in_method
             ) as j
      from public.events e
      left join public.program_runs pr on pr.id = e.program_run_id
      join lateral (
        select a.recorded_at, a.check_in_method
        from public.event_attendance a
        where a.event_id = e.id and a.member_id = v_member_id and a.removed_at is null
        union all
        select pa.recorded_at, 'tick'::text
        from public.program_participant_attendance pa
        join public.program_participants pp on pp.id = pa.participant_id
        where pa.event_id = e.id and pp.member_id = v_member_id and pa.removed_at is null
        order by 1
        limit 1
      ) att on true
      where e.organization_id = p_organization_id
        and e.event_status <> 'cancelled'
        and e.starts_at >= v_from and e.starts_at < v_to
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_attendance(uuid, date, date) from public, anon;
grant execute on function public.list_my_attendance(uuid, date, date) to authenticated;

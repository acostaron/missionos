-- Pass 8.1: Member Portal — personal claim codes for member logins (written by Claude, 2026-10-14).
-- Ministry decision (Ron, 2026-10-14): members get their MissionOS login in two ways —
--   (1) a one-time personal claim code handed out / texted by their chapter servant or an admin, and
--   (2) email invitations later, once leaders have collected emails on the chapter sheets.
-- Discovery (Pass 8.0): only 3 of 313 active members have an email on file, so codes come first.
--
-- How a code works:
--   * An admin, or a chapter servant for members in their chapter, issues codes ("MFC-XXXX-XXXX").
--     The plain code is shown ONCE to the issuer; only its SHA-256 hash is stored.
--   * One active code per member; issuing a new code revokes the previous one. Codes expire after 30 days.
--   * The member opens app.mfcny.net/claim, enters the code, their own email and a password. The Edge Function
--     claim-member-account creates the login and calls redeem_member_claim_code (service role only), which links
--     the login to the member record exactly like an accepted invitation, and records the email on the member's
--     record when they have none.
--   * Wrong codes are counted per network address; after 10 wrong tries in 15 minutes that address is blocked
--     for 15 minutes.

-- =============================================================================
-- 1. Tables
-- =============================================================================
create table if not exists public.member_claim_codes (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  member_id              uuid not null references public.members(id) on delete restrict,
  code_hash              text not null unique,
  code_hint              text not null,
  code_status            text not null default 'active' check (code_status in ('active', 'redeemed', 'revoked', 'expired')),
  issued_by_profile_id   uuid not null references public.profiles(id) on delete restrict,
  issued_at              timestamptz not null default now(),
  expires_at             timestamptz not null default (now() + interval '30 days'),
  redeemed_at            timestamptz null,
  redeemed_profile_id    uuid null references public.profiles(id) on delete set null,
  revoked_at             timestamptz null,
  revoked_by_profile_id  uuid null references public.profiles(id) on delete set null,
  constraint chk_member_claim_codes_expiry check (expires_at > issued_at)
);
create unique index if not exists uq_member_claim_codes_active_member
  on public.member_claim_codes (member_id) where code_status = 'active';
create index if not exists idx_member_claim_codes_org on public.member_claim_codes (organization_id, code_status);

create table if not exists public.member_claim_code_failures (
  id          bigserial primary key,
  client_key  text not null,
  failed_at   timestamptz not null default now()
);
create index if not exists idx_member_claim_code_failures_key on public.member_claim_code_failures (client_key, failed_at);

alter table public.member_claim_codes enable row level security;
alter table public.member_claim_code_failures enable row level security;

-- =============================================================================
-- 2. Permission
-- =============================================================================
insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
)
select 'members.accounts.issue_codes', 'Issue member login codes',
       'Allows issuing one-time personal claim codes so members can create their MissionOS login. Chapter servants: members in their scope only.',
       'members', 'manage', 'organization', 'high', false, true, true
where not exists (select 1 from public.permissions where code = 'members.accounts.issue_codes');

insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code in ('organization_administrator', 'chapter_servant_leader_access')
  and r.is_system_role
  and p.code = 'members.accounts.issue_codes'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

-- =============================================================================
-- 3. Helpers
-- =============================================================================

-- Normalise a typed code: upper-case, keep A-Z 0-9 only (dashes/spaces optional when typing)
create or replace function private.normalize_claim_code(p_code text)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
$$;
revoke all on function private.normalize_claim_code(text) from public, anon, authenticated;

create or replace function private.hash_claim_code(p_code text)
returns text
language sql
immutable
set search_path to 'pg_catalog', 'extensions', 'public'
as $$
  select encode(digest(private.normalize_claim_code(p_code), 'sha256'), 'hex')
$$;
revoke all on function private.hash_claim_code(text) from public, anon, authenticated;

-- New random code "MFC-XXXX-XXXX" from an alphabet without look-alike characters (no 0 O 1 I L)
create or replace function private.generate_claim_code()
returns text
language plpgsql
volatile
set search_path to 'pg_catalog', 'extensions', 'public'
as $$
declare
  v_alpha constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes bytea := gen_random_bytes(8);
  v_out text := '';
  i int;
begin
  for i in 0..7 loop
    v_out := v_out || substr(v_alpha, (get_byte(v_bytes, i) % length(v_alpha)) + 1, 1);
  end loop;
  return 'MFC-' || substr(v_out, 1, 4) || '-' || substr(v_out, 5, 4);
end;
$$;
revoke all on function private.generate_claim_code() from public, anon, authenticated;

-- Is the caller's network address currently blocked for wrong codes?
create or replace function private.claim_code_client_blocked(p_client_key text)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select (select count(*) from public.member_claim_code_failures f
          where f.client_key = coalesce(p_client_key, 'unknown')
            and f.failed_at > now() - interval '15 minutes') >= 10
$$;
revoke all on function private.claim_code_client_blocked(text) from public, anon, authenticated;

-- Member's login state: 'linked' | 'code_active' | 'code_expired' | 'none'
create or replace function private.member_login_state(p_organization_id uuid, p_member_id uuid)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select case
    when exists (select 1 from public.profile_member_links l
                 where l.organization_id = p_organization_id and l.member_id = p_member_id
                   and l.link_type = 'self' and l.link_status = 'verified' and l.is_primary and l.ended_at is null)
      then 'linked'
    when exists (select 1 from public.member_claim_codes c
                 where c.member_id = p_member_id and c.code_status = 'active' and c.expires_at > now())
      then 'code_active'
    when exists (select 1 from public.member_claim_codes c
                 where c.member_id = p_member_id and (c.code_status = 'expired'
                                                      or (c.code_status = 'active' and c.expires_at <= now())))
      then 'code_expired'
    else 'none'
  end
$$;
revoke all on function private.member_login_state(uuid, uuid) from public, anon, authenticated;

-- =============================================================================
-- 4. Leader / admin RPCs
-- =============================================================================

-- 4a. issue_member_claim_codes: returns the plain codes ONCE. Members out of scope, already linked,
--     archived or deceased are skipped with a reason. A new code replaces any active code.
create or replace function public.issue_member_claim_codes(
  p_organization_id uuid,
  p_member_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth', 'extensions'
as $$
declare
  v_actor uuid;
  v_ids uuid[];
  v_mid uuid;
  v_member public.members%rowtype;
  v_code text;
  v_issued jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_expires timestamptz := now() + interval '30 days';
  v_try int;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_permission('members.accounts.issue_codes', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission members.accounts.issue_codes.';
  end if;

  select array_agg(distinct x) into v_ids from unnest(coalesce(p_member_ids, '{}'::uuid[])) x where x is not null;
  if v_ids is null or array_length(v_ids, 1) = 0 then
    raise exception using errcode = '22023', message = 'Select at least one member.';
  end if;
  if array_length(v_ids, 1) > 200 then
    raise exception using errcode = '22023', message = 'At most 200 codes can be issued at once.';
  end if;

  foreach v_mid in array v_ids loop
    select * into v_member from public.members where id = v_mid and organization_id = p_organization_id;
    if not found then
      v_skipped := v_skipped || jsonb_build_object('member_id', v_mid, 'reason', 'not_found');
      continue;
    end if;
    if not private.can_access_member('members.accounts.issue_codes', p_organization_id, v_mid) then
      v_skipped := v_skipped || jsonb_build_object('member_id', v_mid, 'reason', 'out_of_scope');
      continue;
    end if;
    if v_member.archived_at is not null or v_member.record_status <> 'active' or coalesce(v_member.is_deceased, false) then
      v_skipped := v_skipped || jsonb_build_object('member_id', v_mid, 'reason', 'not_active');
      continue;
    end if;
    if private.member_login_state(p_organization_id, v_mid) = 'linked' then
      v_skipped := v_skipped || jsonb_build_object('member_id', v_mid, 'reason', 'already_has_login');
      continue;
    end if;

    update public.member_claim_codes
    set code_status = 'revoked', revoked_at = now(), revoked_by_profile_id = v_actor
    where member_id = v_mid and code_status = 'active';

    v_try := 0;
    loop
      v_try := v_try + 1;
      v_code := private.generate_claim_code();
      exit when not exists (select 1 from public.member_claim_codes where code_hash = private.hash_claim_code(v_code));
      if v_try > 5 then
        raise exception using errcode = 'P0001', message = 'Could not generate a unique code; please try again.';
      end if;
    end loop;

    insert into public.member_claim_codes (
      organization_id, member_id, code_hash, code_hint, code_status, issued_by_profile_id, expires_at
    ) values (
      p_organization_id, v_mid, private.hash_claim_code(v_code), right(v_code, 2), 'active', v_actor, v_expires
    );

    v_issued := v_issued || jsonb_build_object(
      'member_id', v_mid,
      'display_name', v_member.display_name,
      'member_number', v_member.member_number,
      'code', v_code,
      'expires_at', v_expires);
  end loop;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'members.account.claim_codes_issued',
    p_event_category   => 'security',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'organization',
    p_entity_id        => p_organization_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => 'Leader issued one-time member login codes',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('issued_count', jsonb_array_length(v_issued),
                                             'skipped_count', jsonb_array_length(v_skipped),
                                             'member_ids', (select jsonb_agg(e->'member_id') from jsonb_array_elements(v_issued) e))
  );

  return jsonb_build_object('status', 'success', 'issued', v_issued, 'skipped', v_skipped);
end;
$$;
revoke all on function public.issue_member_claim_codes(uuid, uuid[]) from public, anon;
grant execute on function public.issue_member_claim_codes(uuid, uuid[]) to authenticated;

-- 4b. revoke_member_claim_code
create or replace function public.revoke_member_claim_code(
  p_organization_id uuid,
  p_member_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_count int;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.can_access_member('members.accounts.issue_codes', p_organization_id, p_member_id) then
    raise exception using errcode = '42501', message = 'Access denied: member is outside your scope or permission is missing.';
  end if;

  update public.member_claim_codes
  set code_status = 'revoked', revoked_at = now(), revoked_by_profile_id = v_actor
  where organization_id = p_organization_id and member_id = p_member_id and code_status = 'active';
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception using errcode = 'P0002', message = 'This member has no active code.';
  end if;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'members.account.claim_code_revoked', p_event_category => 'security',
    p_actor_profile_id => v_actor, p_entity_type => 'member', p_entity_id => p_member_id, p_action => 'revoke',
    p_outcome => 'success', p_access_reason => 'Leader revoked a member login code', p_correlation_id => null,
    p_metadata => '{}'::jsonb);

  return jsonb_build_object('status', 'success', 'member_id', p_member_id);
end;
$$;
revoke all on function public.revoke_member_claim_code(uuid, uuid) from public, anon;
grant execute on function public.revoke_member_claim_code(uuid, uuid) to authenticated;

-- 4c. list_member_login_status: members in the caller's scope with their login state (for the "Member logins" page)
create or replace function public.list_member_login_status(
  p_organization_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_permission('members.accounts.issue_codes', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission members.accounts.issue_codes.';
  end if;

  return coalesce((
    select jsonb_agg(x.j order by x.sort_name)
    from (
      select m.sort_name,
             jsonb_build_object(
               'member_id', m.id,
               'display_name', m.display_name,
               'member_number', m.member_number,
               'section_name', (select n.name from public.governance_nodes n where n.id = m.primary_section_node_id),
               'placement_name', (select n.name from public.governance_nodes n where n.id = m.primary_governance_node_id),
               'chapter_name', (
                 select c.name from public.governance_nodes c
                 join public.governance_node_types t on t.id = c.governance_node_type_id and t.code = 'chapter'
                 where c.organization_id = m.organization_id
                   and private.node_is_within(m.primary_governance_node_id, c.id)
                 limit 1),
               'has_email', exists (select 1 from public.member_emails e
                                    where e.member_id = m.id and e.is_primary and e.effective_to_at is null),
               'login_state', private.member_login_state(m.organization_id, m.id),
               'code_expires_at', (select c.expires_at from public.member_claim_codes c
                                   where c.member_id = m.id and c.code_status = 'active' limit 1),
               'code_hint', (select c.code_hint from public.member_claim_codes c
                             where c.member_id = m.id and c.code_status = 'active' limit 1)
             ) as j
      from public.members m
      where m.organization_id = p_organization_id
        and m.record_status = 'active'
        and m.archived_at is null
        and private.can_access_member('members.accounts.issue_codes', p_organization_id, m.id)
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_member_login_status(uuid) from public, anon;
grant execute on function public.list_member_login_status(uuid) to authenticated;

-- =============================================================================
-- 5. Service-role RPCs used only by the Edge Function claim-member-account
-- =============================================================================

-- 5a. check_member_claim_code: is the code valid? Returns a masked name (first name + last initial).
create or replace function public.check_member_claim_code(
  p_code text,
  p_client_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'extensions'
as $$
declare
  v_code public.member_claim_codes%rowtype;
  v_member public.members%rowtype;
  v_given text;
  v_found boolean;
begin
  if private.claim_code_client_blocked(p_client_key) then
    return jsonb_build_object('valid', false, 'reason', 'too_many_attempts');
  end if;

  select * into v_code from public.member_claim_codes
  where code_hash = private.hash_claim_code(p_code);
  v_found := found;

  if not v_found or v_code.code_status <> 'active' or v_code.expires_at <= now() then
    insert into public.member_claim_code_failures (client_key) values (coalesce(p_client_key, 'unknown'));
    if v_found and v_code.code_status = 'active' and v_code.expires_at <= now() then
      update public.member_claim_codes set code_status = 'expired' where id = v_code.id;
      return jsonb_build_object('valid', false, 'reason', 'expired');
    end if;
    return jsonb_build_object('valid', false,
      'reason', case when not v_found then 'not_found' when v_code.code_status = 'redeemed' then 'already_used' else 'not_active' end);
  end if;

  select * into v_member from public.members where id = v_code.member_id;
  select nm.given_names into v_given from public.member_names nm
  where nm.member_id = v_member.id and nm.is_primary and nm.effective_to is null limit 1;

  return jsonb_build_object(
    'valid', true,
    'masked_name', coalesce(nullif(btrim(v_given), ''), split_part(v_member.display_name, ' ', 1))
                   || ' ' || left(split_part(v_member.sort_name, ',', 1), 1) || '.',
    'expires_at', v_code.expires_at);
end;
$$;
revoke all on function public.check_member_claim_code(text, text) from public, anon, authenticated;
grant execute on function public.check_member_claim_code(text, text) to service_role;

-- 5b. claim_email_has_login: does an auth login already exist for this email?
create or replace function public.claim_email_has_login(p_email text)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'auth'
as $$
  select exists (select 1 from auth.users u where lower(u.email) = lower(btrim(coalesce(p_email, ''))))
$$;
revoke all on function public.claim_email_has_login(text) from public, anon, authenticated;
grant execute on function public.claim_email_has_login(text) to service_role;

-- 5c. redeem_member_claim_code: link the auth user to the member (same outcome as an accepted invitation)
create or replace function public.redeem_member_claim_code(
  p_code text,
  p_auth_user_id uuid,
  p_email text,
  p_client_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth', 'extensions'
as $$
declare
  v_code public.member_claim_codes%rowtype;
  v_member public.members%rowtype;
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_membership_id uuid;
  v_provision jsonb;
  v_has_default boolean;
begin
  if p_auth_user_id is null or v_email = '' then
    raise exception using errcode = '22023', message = 'Login and email are required.';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_auth_user_id) then
    raise exception using errcode = 'P0002', message = 'Login not found.';
  end if;
  if private.claim_code_client_blocked(p_client_key) then
    raise exception using errcode = '42501', message = 'Too many wrong codes were tried. Please wait 15 minutes and try again.';
  end if;

  select * into v_code from public.member_claim_codes
  where code_hash = private.hash_claim_code(p_code)
  for update;
  if not found or v_code.code_status <> 'active' or v_code.expires_at <= now() then
    insert into public.member_claim_code_failures (client_key) values (coalesce(p_client_key, 'unknown'));
    raise exception using errcode = '22023', message = 'This code is not valid, has expired or was already used. Ask your chapter servant for a new code.';
  end if;

  select * into v_member from public.members where id = v_code.member_id for update;
  if v_member.archived_at is not null or v_member.record_status <> 'active' or coalesce(v_member.is_deceased, false) then
    raise exception using errcode = '23514', message = 'This member record is not active. Please contact your chapter servant.';
  end if;
  if private.member_login_state(v_code.organization_id, v_member.id) = 'linked' then
    raise exception using errcode = '23505', message = 'This member already has a MissionOS login.';
  end if;

  -- Profile (profiles.id = auth.users.id)
  insert into public.profiles (id, display_name, preferred_name, account_status, is_platform_administrator, created_at, updated_at)
  values (p_auth_user_id, v_member.display_name, v_member.preferred_name, 'active', false, now(), now())
  on conflict (id) do update set
    account_status = case when public.profiles.account_status = 'pending' then 'active' else public.profiles.account_status end,
    updated_at = now();

  if exists (select 1 from public.profiles where id = p_auth_user_id and account_status in ('suspended', 'disabled', 'closed')) then
    raise exception using errcode = '23514', message = 'This login is not active. Please contact an administrator.';
  end if;

  -- Organization membership
  select id into v_membership_id from public.profile_organization_memberships
  where profile_id = p_auth_user_id and organization_id = v_code.organization_id and effective_to_at is null
  limit 1;
  select exists (select 1 from public.profile_organization_memberships
                 where profile_id = p_auth_user_id and is_default and effective_to_at is null) into v_has_default;
  if v_membership_id is not null then
    update public.profile_organization_memberships
    set membership_status = 'active', accepted_at = coalesce(accepted_at, now()),
        effective_from_at = coalesce(effective_from_at, now()), updated_at = now()
    where id = v_membership_id;
  else
    insert into public.profile_organization_memberships (
      profile_id, organization_id, membership_status, is_default,
      effective_from_at, invited_at, invited_by_profile_id, accepted_at,
      created_by_profile_id, created_at, updated_at
    ) values (
      p_auth_user_id, v_code.organization_id, 'active', not v_has_default,
      now(), v_code.issued_at, v_code.issued_by_profile_id, now(),
      v_code.issued_by_profile_id, now(), now()
    );
  end if;

  -- Verified self link + member role (same helper as invitation acceptance)
  v_provision := private.provision_member_access(
    p_profile_id => p_auth_user_id,
    p_organization_id => v_code.organization_id,
    p_member_id => v_member.id,
    p_verification_method => 'claim_code',
    p_verification_summary => 'Member redeemed a one-time login code issued by a leader',
    p_actor_profile_id => v_code.issued_by_profile_id
  );

  update public.member_claim_codes
  set code_status = 'redeemed', redeemed_at = now(), redeemed_profile_id = p_auth_user_id
  where id = v_code.id;

  -- Record the email on the member's record when they have none
  if not exists (select 1 from public.member_emails e
                 where e.member_id = v_member.id and e.organization_id = v_code.organization_id and e.effective_to_at is null) then
    insert into public.member_emails (
      id, organization_id, member_id, email_address, normalized_email,
      email_type, is_primary, is_shared, verification_status, allows_ministry_email,
      effective_from_at, created_by_profile_id, updated_by_profile_id
    ) values (
      gen_random_uuid(), v_code.organization_id, v_member.id, btrim(p_email), private.normalize_email(p_email),
      'personal', true, false, 'unverified', true,
      clock_timestamp(), p_auth_user_id, p_auth_user_id
    );
  end if;

  perform private.write_audit_event(
    p_organization_id  => v_code.organization_id,
    p_event_code       => 'members.account.claim_code_redeemed',
    p_event_category   => 'security',
    p_actor_profile_id => p_auth_user_id,
    p_entity_type      => 'member',
    p_entity_id        => v_member.id,
    p_action           => 'accept',
    p_outcome          => 'success',
    p_access_reason    => 'Member redeemed a one-time login code',
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('claim_code_id', v_code.id, 'issued_by_profile_id', v_code.issued_by_profile_id,
                                             'link_id', v_provision->'link_id')
  );

  return jsonb_build_object('status', 'success', 'organization_id', v_code.organization_id,
                            'member_id', v_member.id, 'profile_id', p_auth_user_id);
end;
$$;
revoke all on function public.redeem_member_claim_code(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.redeem_member_claim_code(text, uuid, text, text) to service_role;

-- =============================================================================
-- Migration: 20261002390000_member_account_invitation_corrections.sql
-- Description: Forward-only corrections for member account invitation foundation:
--   1. Update ck_member_account_invitations__status to include
--      'existing_account_invitation_pending'.
--   2. Update partial unique indexes for active invitations to include
--      'existing_account_invitation_pending'.
--   3. Correct record_member_account_invitation_failure:
--      - audit event outcome set to 'failed' (satisfies ck_audit_events__outcome)
--      - clear target auth/profile foreign keys upon failure transition to
--        guarantee safe compensation without foreign key failure.
--   4. Update lookup_auth_user_for_invitation:
--      - classify whether existing Auth user account is usable
--      - return is_usable and unusable_reason.
--   5. Update prepare_member_account_invitation and finalize_member_account_invitation
--      to align with active status sets.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Status Check Constraint & Partial Unique Indexes
-- ---------------------------------------------------------------------------
alter table public.member_account_invitations
  drop constraint if exists ck_member_account_invitations__status;

alter table public.member_account_invitations
  add constraint ck_member_account_invitations__status
  check (invitation_status in (
    'pending',
    'sent',
    'accepted',
    'cancelled',
    'expired',
    'failed',
    'existing_account_invitation_pending'
  ));

drop index if exists public.ux_member_account_invitations_active_member;
create unique index ux_member_account_invitations_active_member
  on public.member_account_invitations (organization_id, member_id)
  where invitation_status in ('pending', 'sent', 'existing_account_invitation_pending');

drop index if exists public.ux_member_account_invitations_active_email;
create unique index ux_member_account_invitations_active_email
  on public.member_account_invitations (organization_id, normalized_email)
  where invitation_status in ('pending', 'sent', 'existing_account_invitation_pending');

-- ---------------------------------------------------------------------------
-- 2. Corrected record_member_account_invitation_failure
-- ---------------------------------------------------------------------------
create or replace function public.record_member_account_invitation_failure(
  p_organization_id uuid,
  p_member_id uuid,
  p_email text,
  p_actor_profile_id uuid,
  p_failure_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_normalized_email text := lower(btrim(p_email));
  v_invitation_id uuid;
begin
  if current_user <> 'service_role' and auth.role() <> 'service_role' then
    raise exception 'Restricted to service role'
      using errcode = '42501';
  end if;

  select id into v_invitation_id
  from public.member_account_invitations
  where organization_id = p_organization_id
    and member_id = p_member_id
    and invitation_status in ('pending', 'sent', 'existing_account_invitation_pending')
  limit 1;

  if v_invitation_id is not null then
    update public.member_account_invitations
    set
      invitation_status = 'failed',
      failure_reason = p_failure_reason,
      auth_user_id = null,
      profile_id = null,
      updated_at = now()
    where id = v_invitation_id;
  else
    insert into public.member_account_invitations (
      organization_id, member_id, email, normalized_email,
      invitation_status, invited_by_profile_id, failure_reason,
      created_at, updated_at
    )
    values (
      p_organization_id, p_member_id, p_email, v_normalized_email,
      'failed', p_actor_profile_id, p_failure_reason,
      now(), now()
    )
    returning id into v_invitation_id;
  end if;

  perform private.write_audit_event(
    p_organization_id => p_organization_id,
    p_event_code => 'members.account.invitation_failed',
    p_event_category => 'security',
    p_actor_profile_id => p_actor_profile_id,
    p_entity_type => 'member',
    p_entity_id => p_member_id,
    p_action => 'invite',
    p_outcome => 'failed',
    p_access_reason => 'Member account invitation failed',
    p_metadata => jsonb_build_object(
      'invitation_id', v_invitation_id,
      'organization_id', p_organization_id,
      'member_id', p_member_id,
      'email', v_normalized_email,
      'failure_reason', p_failure_reason
    )
  );

  return jsonb_build_object(
    'invitation_id', v_invitation_id,
    'status', 'failed',
    'failure_reason', p_failure_reason
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Corrected lookup_auth_user_for_invitation (Usable Account Classification)
-- ---------------------------------------------------------------------------
create or replace function public.lookup_auth_user_for_invitation(
  p_organization_id uuid,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_normalized_email text := lower(btrim(p_email));
  v_user record;
  v_profile record;
  v_membership record;
  v_other_member_link record;
  v_is_usable boolean := false;
  v_unusable_reason text := null;
begin
  if current_user <> 'service_role' and auth.role() <> 'service_role' then
    raise exception 'Lookup is restricted to service role'
      using errcode = '42501';
  end if;

  select
    u.id,
    u.email,
    (u.email_confirmed_at is not null or u.confirmed_at is not null) as is_confirmed,
    (u.deleted_at is not null) as is_deleted,
    (u.banned_until is not null and u.banned_until > now()) as is_banned,
    coalesce(u.is_anonymous, false) as is_anonymous
  into v_user
  from auth.users u
  where lower(u.email) = v_normalized_email
  limit 1;

  if v_user.id is null then
    return jsonb_build_object(
      'user_exists', false,
      'auth_user_id', null,
      'is_usable', false
    );
  end if;

  select p.id, p.account_status, p.display_name
  into v_profile
  from public.profiles p
  where p.id = v_user.id;

  select pom.id, pom.membership_status
  into v_membership
  from public.profile_organization_memberships pom
  where pom.profile_id = v_user.id
    and pom.organization_id = p_organization_id
    and pom.effective_to_at is null
  limit 1;

  select l.id, l.member_id, l.link_status
  into v_other_member_link
  from public.profile_member_links l
  where l.profile_id = v_user.id
    and l.organization_id = p_organization_id
    and l.link_type = 'self' and l.link_status = 'verified'
    and l.is_primary and l.ended_at is null
  limit 1;

  -- Classification of usable active account:
  -- Must be confirmed, not deleted, not banned, not anonymous,
  -- and if profile exists it must not be suspended, disabled, or closed.
  if v_user.is_deleted then
    v_is_usable := false;
    v_unusable_reason := 'Auth user is deleted';
  elsif v_user.is_banned then
    v_is_usable := false;
    v_unusable_reason := 'Auth user is currently banned';
  elsif v_user.is_anonymous then
    v_is_usable := false;
    v_unusable_reason := 'Auth user is an anonymous account';
  elsif v_profile.account_status in ('suspended', 'disabled', 'closed') then
    v_is_usable := false;
    v_unusable_reason := 'MissionOS profile status is ' || v_profile.account_status;
  elsif not v_user.is_confirmed then
    v_is_usable := false;
    v_unusable_reason := 'Auth user email is unconfirmed';
  else
    v_is_usable := true;
  end if;

  return jsonb_build_object(
    'user_exists', true,
    'auth_user_id', v_user.id,
    'email_confirmed', v_user.is_confirmed,
    'is_usable', v_is_usable,
    'unusable_reason', v_unusable_reason,
    'profile_exists', (v_profile.id is not null),
    'profile_account_status', v_profile.account_status,
    'organization_membership_exists', (v_membership.id is not null),
    'organization_membership_status', v_membership.membership_status,
    'is_linked_to_member', (v_other_member_link.id is not null),
    'linked_member_id', v_other_member_link.member_id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Corrected prepare_member_account_invitation
-- ---------------------------------------------------------------------------
create or replace function public.prepare_member_account_invitation(
  p_organization_id uuid,
  p_member_id uuid,
  p_email text,
  p_acknowledge_shared boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_member_id uuid;
  v_normalized_email text;
  v_archived_at timestamptz;
  v_is_deceased boolean;
  v_record_status text;
  v_display_name text;
  v_is_shared boolean := false;
  v_shared_count integer := 0;
begin
  if v_actor is null or not private.can_provision_member_accounts(p_organization_id) then
    raise exception 'Not authorized to provision member accounts'
      using errcode = '42501';
  end if;

  if p_organization_id is null or p_member_id is null or p_email is null then
    raise exception 'organization, member and email are required'
      using errcode = '22023';
  end if;

  v_normalized_email := lower(btrim(p_email));
  if v_normalized_email !~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'Invalid email address format'
      using errcode = '22023';
  end if;

  -- Member resolution & existence
  v_member_id := private.resolve_canonical_member_id(p_organization_id, p_member_id);
  if v_member_id is null or not exists (
    select 1 from public.members m
    where m.id = v_member_id and m.organization_id = p_organization_id
  ) then
    raise exception 'Member not found in this organization'
      using errcode = 'P0002';
  end if;

  if v_member_id <> p_member_id then
    raise exception 'Member has been merged into a surviving record'
      using errcode = '23514';
  end if;

  select m.archived_at, m.is_deceased, m.record_status, m.display_name
  into v_archived_at, v_is_deceased, v_record_status, v_display_name
  from public.members m
  where m.id = v_member_id and m.organization_id = p_organization_id;

  if v_archived_at is not null or v_record_status = 'archived' then
    raise exception 'Archived members cannot be invited'
      using errcode = '23514';
  end if;

  if v_is_deceased then
    raise exception 'Deceased members cannot be invited'
      using errcode = '23514';
  end if;

  -- Member already linked to a profile in this organization
  if exists (
    select 1 from public.profile_member_links l
    where l.organization_id = p_organization_id
      and l.member_id = v_member_id
      and l.link_type = 'self' and l.link_status = 'verified'
      and l.is_primary and l.ended_at is null
  ) then
    raise exception 'Member is already linked to an account in this organization'
      using errcode = '23505';
  end if;

  -- Active or pending invitation already exists for this member
  if exists (
    select 1 from public.member_account_invitations i
    where i.organization_id = p_organization_id
      and i.member_id = v_member_id
      and i.invitation_status in ('pending', 'sent', 'existing_account_invitation_pending')
  ) then
    raise exception 'An active invitation already exists for this member'
      using errcode = '23505';
  end if;

  -- Active or pending invitation for this email exists for another member
  if exists (
    select 1 from public.member_account_invitations i
    where i.organization_id = p_organization_id
      and i.normalized_email = v_normalized_email
      and i.member_id <> v_member_id
      and i.invitation_status in ('pending', 'sent', 'existing_account_invitation_pending')
  ) then
    raise exception 'An active invitation with this email already exists for another member'
      using errcode = '23505';
  end if;

  -- Existing profile linked to a different member in this organization
  if exists (
    select 1
    from auth.users u
    join public.profile_member_links l on l.profile_id = u.id
    where lower(u.email) = v_normalized_email
      and l.organization_id = p_organization_id
      and l.member_id <> v_member_id
      and l.link_type = 'self' and l.link_status = 'verified'
      and l.is_primary and l.ended_at is null
  ) then
    raise exception 'An account with this email is already linked to a different member'
      using errcode = '23505';
  end if;

  -- Shared email inspection
  select
    coalesce(bool_or(me.is_shared), false),
    count(distinct me.member_id)
  into v_is_shared, v_shared_count
  from public.member_emails me
  where me.organization_id = p_organization_id
    and me.normalized_email = v_normalized_email
    and me.effective_to_at is null;

  if (v_is_shared or v_shared_count > 1) then
    if not coalesce(p_acknowledge_shared, false) then
      return jsonb_build_object(
        'eligible', false,
        'status', 'requires_shared_acknowledgment',
        'warning', 'Email is shared or associated with multiple members. Explicit administrator acknowledgment is required.',
        'organization_id', p_organization_id,
        'member_id', v_member_id,
        'email', v_normalized_email,
        'is_shared_email', true
      );
    end if;
  end if;

  return jsonb_build_object(
    'eligible', true,
    'status', 'eligible',
    'organization_id', p_organization_id,
    'member_id', v_member_id,
    'email', v_normalized_email,
    'display_name', v_display_name,
    'is_shared_email', (v_is_shared or v_shared_count > 1)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Corrected finalize_member_account_invitation
-- ---------------------------------------------------------------------------
create or replace function public.finalize_member_account_invitation(
  p_organization_id uuid,
  p_member_id uuid,
  p_auth_user_id uuid,
  p_email text,
  p_actor_profile_id uuid,
  p_invitation_status text default 'sent'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_normalized_email text;
  v_member_name text;
  v_preferred_name text;
  v_invitation_id uuid;
  v_invitation_status text := coalesce(nullif(btrim(p_invitation_status), ''), 'sent');
  v_membership_id uuid;
begin
  if current_user <> 'service_role' and auth.role() <> 'service_role' then
    raise exception 'Finalization is restricted to service role'
      using errcode = '42501';
  end if;

  if p_organization_id is null or p_member_id is null or p_auth_user_id is null
     or p_email is null or p_actor_profile_id is null then
    raise exception 'organization, member, auth_user_id, email, and actor are required'
      using errcode = '22023';
  end if;

  v_normalized_email := lower(btrim(p_email));

  -- Verify member exists in org
  select m.display_name, m.preferred_name
  into v_member_name, v_preferred_name
  from public.members m
  where m.id = p_member_id and m.organization_id = p_organization_id;

  if v_member_name is null then
    raise exception 'Member not found in this organization' using errcode = 'P0002';
  end if;

  -- 1. Create or ensure public.profiles
  -- Rule: profiles.id = auth.users.id
  insert into public.profiles (
    id, display_name, preferred_name, account_status, is_platform_administrator, created_at, updated_at
  )
  values (
    p_auth_user_id, coalesce(v_member_name, v_normalized_email), v_preferred_name, 'pending', false, now(), now()
  )
  on conflict (id) do update set
    updated_at = now();

  -- 2. Create or ensure profile_organization_memberships
  select id into v_membership_id
  from public.profile_organization_memberships
  where profile_id = p_auth_user_id
    and organization_id = p_organization_id
    and effective_to_at is null
  limit 1;

  if v_membership_id is not null then
    update public.profile_organization_memberships
    set
      invited_at = coalesce(invited_at, now()),
      invited_by_profile_id = coalesce(invited_by_profile_id, p_actor_profile_id),
      membership_status = case
        when membership_status = 'active' then 'active'
        else 'invited'
      end,
      updated_at = now()
    where id = v_membership_id;
  else
    insert into public.profile_organization_memberships (
      profile_id, organization_id, membership_status, is_default,
      effective_from_at, invited_at, invited_by_profile_id, accepted_at,
      created_by_profile_id, created_at, updated_at
    )
    values (
      p_auth_user_id, p_organization_id, 'invited', false,
      now(), now(), p_actor_profile_id, null,
      p_actor_profile_id, now(), now()
    );
  end if;

  -- 3. Upsert into public.member_account_invitations
  select id into v_invitation_id
  from public.member_account_invitations
  where organization_id = p_organization_id
    and member_id = p_member_id
    and invitation_status in ('pending', 'sent', 'existing_account_invitation_pending')
  limit 1;

  if v_invitation_id is not null then
    update public.member_account_invitations
    set
      auth_user_id = p_auth_user_id,
      profile_id = p_auth_user_id,
      email = p_email,
      normalized_email = v_normalized_email,
      invitation_status = v_invitation_status,
      invited_by_profile_id = p_actor_profile_id,
      invited_at = now(),
      updated_at = now()
    where id = v_invitation_id;
  else
    insert into public.member_account_invitations (
      organization_id, member_id, email, normalized_email,
      auth_user_id, profile_id, invitation_status,
      invited_by_profile_id, invited_at, created_at, updated_at
    )
    values (
      p_organization_id, p_member_id, p_email, v_normalized_email,
      p_auth_user_id, p_auth_user_id, v_invitation_status,
      p_actor_profile_id, now(), now(), now()
    )
    returning id into v_invitation_id;
  end if;

  -- 4. Audit event: members.account.invited
  perform private.write_audit_event(
    p_organization_id => p_organization_id,
    p_event_code => 'members.account.invited',
    p_event_category => 'security',
    p_actor_profile_id => p_actor_profile_id,
    p_entity_type => 'member',
    p_entity_id => p_member_id,
    p_action => 'invite',
    p_outcome => 'success',
    p_access_reason => 'Member account invitation provisioned',
    p_metadata => jsonb_build_object(
      'invitation_id', v_invitation_id,
      'organization_id', p_organization_id,
      'member_id', p_member_id,
      'profile_id', p_auth_user_id,
      'email', v_normalized_email,
      'status', v_invitation_status,
      'actor_profile_id', p_actor_profile_id
    )
  );

  return jsonb_build_object(
    'invitation_id', v_invitation_id,
    'organization_id', p_organization_id,
    'member_id', p_member_id,
    'profile_id', p_auth_user_id,
    'email', v_normalized_email,
    'status', v_invitation_status,
    'invited_at', now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Grants & Revokes
-- ---------------------------------------------------------------------------
revoke all on function public.prepare_member_account_invitation(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.prepare_member_account_invitation(uuid, uuid, text, boolean) to authenticated, service_role;

revoke all on function public.finalize_member_account_invitation(uuid, uuid, uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function public.finalize_member_account_invitation(uuid, uuid, uuid, text, uuid, text) to service_role;

revoke all on function public.lookup_auth_user_for_invitation(uuid, text) from public, anon, authenticated;
grant execute on function public.lookup_auth_user_for_invitation(uuid, text) to service_role;

revoke all on function public.record_member_account_invitation_failure(uuid, uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function public.record_member_account_invitation_failure(uuid, uuid, text, uuid, text) to service_role;

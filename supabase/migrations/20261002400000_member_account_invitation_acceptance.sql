-- =============================================================================
-- Migration: 20261002400000_member_account_invitation_acceptance.sql
-- Description: Member account invitation acceptance lifecycle.
--              1. public.accept_member_account_invitation
--              2. public.get_member_account_invitation_details
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Acceptance RPC: accept_member_account_invitation
-- ---------------------------------------------------------------------------
create or replace function public.accept_member_account_invitation(
  p_invitation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, audit
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid := private.current_profile_id();
  v_profile record;
  v_inv record;
  v_inv_count integer;
  v_accepted_inv_id uuid;
  v_canonical_member_id uuid;
  v_member record;
  v_membership_id uuid;
  v_membership_status text;
  v_provision_res jsonb;
  v_verifier uuid;
begin
  -- 1. Identity & Profile authentication
  if v_auth_user_id is null or v_profile_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_profile_id;

  if v_profile.id is null then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  if v_profile.account_status in ('suspended', 'disabled', 'closed') then
    raise exception 'Profile account is % and cannot accept invitations', v_profile.account_status
      using errcode = '23514';
  end if;

  -- 2. Locate invitation
  if p_invitation_id is not null then
    select * into v_inv
    from public.member_account_invitations
    where id = p_invitation_id
    for update;

    if v_inv.id is null then
      raise exception 'Invitation not found' using errcode = 'P0002';
    end if;

    if v_inv.profile_id <> v_profile_id or v_inv.auth_user_id <> v_auth_user_id then
      raise exception 'Invitation does not belong to current authenticated profile'
        using errcode = '42501';
    end if;
  else
    select count(*) into v_inv_count
    from public.member_account_invitations
    where (profile_id = v_profile_id or auth_user_id = v_auth_user_id)
      and invitation_status in ('sent', 'existing_account_invitation_pending');

    if v_inv_count = 0 then
      select id into v_accepted_inv_id
      from public.member_account_invitations
      where (profile_id = v_profile_id or auth_user_id = v_auth_user_id)
        and invitation_status = 'accepted'
      order by accepted_at desc
      limit 1;

      if v_accepted_inv_id is not null then
        select * into v_inv
        from public.member_account_invitations
        where id = v_accepted_inv_id
        for update;
      else
        raise exception 'No pending invitation found for current profile' using errcode = 'P0002';
      end if;
    elsif v_inv_count > 1 then
      raise exception 'Multiple pending invitations found; explicit invitation_id is required'
        using errcode = '42702';
    else
      select * into v_inv
      from public.member_account_invitations
      where (profile_id = v_profile_id or auth_user_id = v_auth_user_id)
        and invitation_status in ('sent', 'existing_account_invitation_pending')
      for update
      limit 1;
    end if;
  end if;

  -- 3. Resolve canonical member
  v_canonical_member_id := private.resolve_canonical_member_id(v_inv.organization_id, v_inv.member_id);
  if v_canonical_member_id is null then
    v_canonical_member_id := v_inv.member_id;
  end if;

  -- 4. Idempotency & Status Checks
  if v_inv.invitation_status = 'accepted' then
    if exists (
      select 1 from public.profile_organization_memberships pom
      where pom.profile_id = v_profile_id
        and pom.organization_id = v_inv.organization_id
        and pom.membership_status = 'active'
        and pom.effective_to_at is null
    ) and exists (
      select 1 from public.profile_member_links l
      where l.profile_id = v_profile_id
        and l.organization_id = v_inv.organization_id
        and l.member_id = v_canonical_member_id
        and l.link_type = 'self' and l.link_status = 'verified'
        and l.is_primary and l.ended_at is null
    ) and exists (
      select 1 from public.profile_role_assignments pra
      join public.app_roles ar on ar.id = pra.app_role_id
      where pra.profile_id = v_profile_id
        and pra.organization_id = v_inv.organization_id
        and ar.code = 'member'
        and pra.assignment_status = 'active'
    ) then
      return jsonb_build_object(
        'invitation_id', v_inv.id,
        'status', 'already_accepted',
        'organization_id', v_inv.organization_id,
        'member_id', v_canonical_member_id,
        'profile_id', v_profile_id,
        'link_status', 'verified',
        'member_access_status', 'active',
        'accepted_at', v_inv.accepted_at
      );
    else
      raise exception 'Invitation is marked accepted but associated membership/access state is inconsistent'
        using errcode = '23514';
    end if;
  end if;

  if v_inv.invitation_status in ('cancelled', 'failed', 'expired') then
    raise exception 'Invitation is % and cannot be accepted', v_inv.invitation_status
      using errcode = '23514';
  end if;

  if v_inv.invitation_status not in ('sent', 'existing_account_invitation_pending') then
    raise exception 'Invitation status % is not valid for acceptance', v_inv.invitation_status
      using errcode = '23514';
  end if;

  -- Expiration check
  if v_inv.expires_at is not null and v_inv.expires_at <= now() then
    update public.member_account_invitations
    set invitation_status = 'expired', updated_at = now()
    where id = v_inv.id;

    raise exception 'Invitation has expired' using errcode = '23514';
  end if;

  -- 5. Target member validation
  select * into v_member
  from public.members
  where id = v_canonical_member_id
    and organization_id = v_inv.organization_id;

  if v_member.id is null then
    raise exception 'Member not found in organization' using errcode = 'P0002';
  end if;

  if v_member.archived_at is not null then
    raise exception 'Archived members cannot be linked to an account' using errcode = '23514';
  end if;

  if coalesce(v_member.is_deceased, false) or v_member.record_status = 'deceased' then
    raise exception 'Deceased members cannot be linked to an account' using errcode = '23514';
  end if;

  -- 6. Profile Activation (pending -> active)
  if v_profile.account_status = 'pending' then
    update public.profiles
    set account_status = 'active',
        updated_at = now()
    where id = v_profile_id;
  end if;

  -- 7. Organization Membership Activation (invited -> active)
  select id, membership_status into v_membership_id, v_membership_status
  from public.profile_organization_memberships
  where profile_id = v_profile_id
    and organization_id = v_inv.organization_id
    and effective_to_at is null
  limit 1;

  if v_membership_id is not null then
    update public.profile_organization_memberships
    set
      membership_status = 'active',
      accepted_at = coalesce(accepted_at, now()),
      effective_from_at = coalesce(effective_from_at, now()),
      updated_at = now()
    where id = v_membership_id;
  else
    insert into public.profile_organization_memberships (
      profile_id, organization_id, membership_status, is_default,
      effective_from_at, invited_at, invited_by_profile_id, accepted_at,
      created_by_profile_id, created_at, updated_at
    )
    values (
      v_profile_id, v_inv.organization_id, 'active', false,
      now(), v_inv.invited_at, v_inv.invited_by_profile_id, now(),
      coalesce(v_inv.invited_by_profile_id, v_profile_id), now(), now()
    )
    returning id into v_membership_id;
  end if;

  -- 8. Establish Verified Primary Self-Link and Provision Member Role
  v_verifier := coalesce(v_inv.invited_by_profile_id, v_profile_id);

  v_provision_res := private.provision_member_access(
    p_profile_id => v_profile_id,
    p_organization_id => v_inv.organization_id,
    p_member_id => v_canonical_member_id,
    p_verification_method => 'email_invitation_acceptance',
    p_verification_summary => 'Member accepted administrator-issued MissionOS invitation',
    p_actor_profile_id => v_verifier
  );

  -- 9. Update Invitation Status
  update public.member_account_invitations
  set
    invitation_status = 'accepted',
    accepted_at = now(),
    updated_at = now()
  where id = v_inv.id;

  -- 10. Audit event: members.account.accepted
  perform private.write_audit_event(
    p_organization_id => v_inv.organization_id,
    p_event_code => 'members.account.accepted',
    p_event_category => 'security',
    p_actor_profile_id => v_profile_id,
    p_entity_type => 'member_account_invitation',
    p_entity_id => v_inv.id,
    p_action => 'accept',
    p_outcome => 'success',
    p_access_reason => 'Member accepted administrator-issued MissionOS invitation',
    p_metadata => jsonb_build_object(
      'invitation_id', v_inv.id,
      'organization_id', v_inv.organization_id,
      'member_id', v_canonical_member_id,
      'profile_id', v_profile_id,
      'invited_by_profile_id', v_inv.invited_by_profile_id,
      'verification_method', 'email_invitation_acceptance'
    )
  );

  -- 11. Return clean payload
  return jsonb_build_object(
    'invitation_id', v_inv.id,
    'status', 'accepted',
    'organization_id', v_inv.organization_id,
    'member_id', v_canonical_member_id,
    'profile_id', v_profile_id,
    'link_id', v_provision_res->'link_id',
    'link_status', 'verified',
    'member_access_status', 'active',
    'accepted_at', now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Query RPC: get_member_account_invitation_details
-- ---------------------------------------------------------------------------
create or replace function public.get_member_account_invitation_details(
  p_invitation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid := private.current_profile_id();
  v_profile record;
  v_inv record;
  v_inv_count integer;
  v_org_name text;
  v_member_name text;
  v_can_accept boolean := true;
  v_unusable_reason text := null;
  v_is_expired boolean := false;
begin
  if v_auth_user_id is null or v_profile_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_profile_id;

  if v_profile.id is null then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  if p_invitation_id is not null then
    select * into v_inv
    from public.member_account_invitations
    where id = p_invitation_id;

    if v_inv.id is null or (v_inv.profile_id <> v_profile_id and v_inv.auth_user_id <> v_auth_user_id) then
      raise exception 'Invitation not found' using errcode = 'P0002';
    end if;
  else
    select count(*) into v_inv_count
    from public.member_account_invitations
    where (profile_id = v_profile_id or auth_user_id = v_auth_user_id)
      and invitation_status in ('sent', 'existing_account_invitation_pending', 'accepted');

    if v_inv_count = 0 then
      raise exception 'No invitation found for current profile' using errcode = 'P0002';
    elsif v_inv_count > 1 then
      -- If multiple, pick the most recent pending if only one is pending
      select * into v_inv
      from public.member_account_invitations
      where (profile_id = v_profile_id or auth_user_id = v_auth_user_id)
        and invitation_status in ('sent', 'existing_account_invitation_pending')
      order by invited_at desc
      limit 1;

      if v_inv.id is null then
        select * into v_inv
        from public.member_account_invitations
        where (profile_id = v_profile_id or auth_user_id = v_auth_user_id)
        order by invited_at desc
        limit 1;
      end if;
    else
      select * into v_inv
      from public.member_account_invitations
      where (profile_id = v_profile_id or auth_user_id = v_auth_user_id)
      limit 1;
    end if;
  end if;

  -- Organization name
  select o.name into v_org_name
  from public.organizations o
  where o.id = v_inv.organization_id;

  -- Member name
  select coalesce(m.preferred_name, m.display_name) into v_member_name
  from public.members m
  where m.id = v_inv.member_id;

  -- Evaluation
  if v_inv.expires_at is not null and v_inv.expires_at <= now() then
    v_is_expired := true;
    v_can_accept := false;
    v_unusable_reason := 'This invitation has expired.';
  elsif v_inv.invitation_status = 'accepted' then
    v_can_accept := false;
    v_unusable_reason := 'This invitation has already been accepted.';
  elsif v_inv.invitation_status in ('cancelled', 'failed', 'expired') then
    v_can_accept := false;
    v_unusable_reason := 'This invitation is no longer valid (' || v_inv.invitation_status || ').';
  elsif v_profile.account_status in ('suspended', 'disabled', 'closed') then
    v_can_accept := false;
    v_unusable_reason := 'Your account profile is currently ' || v_profile.account_status || '.';
  end if;

  return jsonb_build_object(
    'invitation_id', v_inv.id,
    'status', v_inv.invitation_status,
    'organization_id', v_inv.organization_id,
    'organization_name', coalesce(v_org_name, 'Organization'),
    'member_id', v_inv.member_id,
    'member_name', coalesce(v_member_name, 'Member'),
    'email', v_inv.email,
    'invited_at', v_inv.invited_at,
    'expires_at', v_inv.expires_at,
    'is_expired', v_is_expired,
    'can_accept', v_can_accept,
    'unusable_reason', v_unusable_reason
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Hardening & Grants
-- ---------------------------------------------------------------------------
revoke all on function public.accept_member_account_invitation(uuid) from public, anon;
grant execute on function public.accept_member_account_invitation(uuid) to authenticated, service_role;

revoke all on function public.get_member_account_invitation_details(uuid) from public, anon;
grant execute on function public.get_member_account_invitation_details(uuid) to authenticated, service_role;

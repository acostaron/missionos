-- =============================================================================
-- Migration: 20261002430000_member_account_status_read_correction.sql
-- Description: Correction to public.get_member_account_status.
--              Use verified_at / created_at on profile_member_links
--              (profile_member_links has verified_at, not linked_at).
-- =============================================================================

create or replace function public.get_member_account_status(
  p_organization_id uuid,
  p_member_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_member record;
  v_canonical_member_id uuid;
  v_link record;
  v_inv record;
  v_profile record;
  v_user record;
  v_pom record;
  v_has_active_member_role boolean := false;
  v_has_drift boolean := false;
  v_account_state text := 'none';
  v_email text := null;
  v_invited_at timestamptz := null;
  v_accepted_at timestamptz := null;
  v_linked_at timestamptz := null;
  v_invitation_status text := null;
  v_profile_status text := null;
  v_suggested_emails jsonb := '[]'::jsonb;
begin
  -- 1. Authorization: Organization Administrator with account provisioning/linking authority
  if v_actor is null or not (
    private.has_permission('members.accounts.provision', p_organization_id)
    or private.has_permission('members.account_links.manage', p_organization_id)
    or private.has_permission('security.profile_member_links.manage', p_organization_id)
  ) then
    raise exception 'Not authorized to view member account status' using errcode = '42501';
  end if;

  if p_organization_id is null or p_member_id is null then
    raise exception 'organization and member are required' using errcode = '22023';
  end if;

  -- 2. Member existence & canonical check
  select m.id, m.archived_at, m.is_deceased, m.record_status
  into v_member
  from public.members m
  where m.id = p_member_id and m.organization_id = p_organization_id;

  if v_member.id is null then
    raise exception 'Member not found in this organization' using errcode = 'P0002';
  end if;

  v_canonical_member_id := private.resolve_canonical_member_id(p_organization_id, p_member_id);

  -- 3. Check for existing active self-link in profile_member_links
  select l.id, l.profile_id, l.verified_at, l.link_status, l.is_primary, l.ended_at, l.created_at
  into v_link
  from public.profile_member_links l
  where l.organization_id = p_organization_id
    and l.member_id = p_member_id
    and l.link_type = 'self'
    and l.is_primary
    and l.ended_at is null
  order by l.created_at desc
  limit 1;

  if v_link.id is not null then
    -- Linked profile details
    select p.id, p.account_status into v_profile
    from public.profiles p
    where p.id = v_link.profile_id;

    -- Auth user email
    select u.id, u.email into v_user
    from auth.users u
    where u.id = v_link.profile_id;

    -- Organization membership
    select pom.id, pom.membership_status, pom.accepted_at into v_pom
    from public.profile_organization_memberships pom
    where pom.profile_id = v_link.profile_id
      and pom.organization_id = p_organization_id
      and pom.effective_to_at is null
    order by pom.created_at desc
    limit 1;

    -- Active system 'member' role assignment
    select exists (
      select 1
      from public.profile_role_assignments a
      join public.app_roles r on r.id = a.app_role_id
      where a.profile_id = v_link.profile_id
        and a.organization_id = p_organization_id
        and a.assignment_status = 'active'
        and r.code = 'member'
        and r.is_system_role
        and r.organization_id is null
    ) into v_has_active_member_role;

    -- Check for corresponding accepted invitation record if any
    select i.email, i.invited_at, i.accepted_at, i.invitation_status into v_inv
    from public.member_account_invitations i
    where i.organization_id = p_organization_id
      and i.member_id = p_member_id
      and i.profile_id = v_link.profile_id
    order by i.accepted_at desc nulls last, i.invited_at desc
    limit 1;

    v_email := coalesce(v_user.email, v_inv.email);
    v_linked_at := coalesce(v_link.verified_at, v_link.created_at);
    v_accepted_at := coalesce(v_inv.accepted_at, v_pom.accepted_at);
    v_invited_at := v_inv.invited_at;
    v_invitation_status := v_inv.invitation_status;
    v_profile_status := v_profile.account_status;

    -- Drift / Integrity Evaluation:
    -- Verified link requires:
    -- - verified link_status
    -- - active profile account_status
    -- - active profile organization membership
    -- - active 'member' system role
    -- - canonical active member (not archived, not deceased, not merged)
    if v_link.link_status <> 'verified'
       or v_profile.account_status <> 'active'
       or v_pom.id is null
       or v_pom.membership_status <> 'active'
       or not v_has_active_member_role
       or v_member.archived_at is not null
       or v_member.record_status = 'archived'
       or v_member.is_deceased
       or v_canonical_member_id <> p_member_id then
      v_account_state := 'needs_review';
    else
      v_account_state := 'active';
    end if;

  else
    -- 4. No active self link. Check for active pending invitation
    select i.id, i.email, i.invited_at, i.invitation_status, i.profile_id, i.expires_at
    into v_inv
    from public.member_account_invitations i
    where i.organization_id = p_organization_id
      and i.member_id = p_member_id
      and i.invitation_status in ('sent', 'existing_account_invitation_pending', 'pending')
    order by i.invited_at desc
    limit 1;

    if v_inv.id is not null then
      if v_inv.expires_at is not null and v_inv.expires_at <= now() then
        -- Expired invitation
        v_inv := null;
      else
        if v_member.archived_at is not null
           or v_member.record_status = 'archived'
           or v_member.is_deceased
           or v_canonical_member_id <> p_member_id then
          v_account_state := 'needs_review';
        else
          v_account_state := 'invitation_pending';
        end if;
        v_email := v_inv.email;
        v_invited_at := v_inv.invited_at;
        v_invitation_status := v_inv.invitation_status;
        if v_inv.profile_id is not null then
          select p.account_status into v_profile_status from public.profiles p where p.id = v_inv.profile_id;
        end if;
      end if;
    end if;

    -- 5. If neither link nor pending invite, check eligibility
    if v_account_state = 'none' then
      if v_canonical_member_id <> p_member_id
         or v_member.archived_at is not null
         or v_member.record_status = 'archived'
         or v_member.is_deceased then
        v_account_state := 'unavailable';
      else
        v_account_state := 'none';
      end if;
    end if;
  end if;

  -- 6. Collect suggested emails from member_emails
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'email_address', me.email_address,
        'email_type', me.email_type,
        'is_primary', me.is_primary,
        'is_shared', coalesce(me.is_shared, false) or (
          select count(distinct me2.member_id)
          from public.member_emails me2
          where me2.organization_id = p_organization_id
            and me2.normalized_email = me.normalized_email
            and me2.effective_to_at is null
        ) > 1
      ) order by me.is_primary desc, me.created_at asc
    ),
    '[]'::jsonb
  ) into v_suggested_emails
  from public.member_emails me
  where me.organization_id = p_organization_id
    and me.member_id = p_member_id
    and (me.effective_to_at is null or me.effective_to_at > now());

  return jsonb_build_object(
    'member_id', p_member_id,
    'account_state', v_account_state,
    'email', v_email,
    'invited_at', v_invited_at,
    'accepted_at', v_accepted_at,
    'linked_at', v_linked_at,
    'invitation_status', v_invitation_status,
    'profile_status', v_profile_status,
    'suggested_emails', coalesce(v_suggested_emails, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_member_account_status(uuid, uuid) from public, anon;
grant execute on function public.get_member_account_status(uuid, uuid) to authenticated, service_role;

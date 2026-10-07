-- =============================================================================
-- Migration: 20261002360000_member_account_link_verification_metadata.sql
-- Description: Correction to Pass 2F. Caller-supplied verification method and
--   summary are passed straight into verify_profile_member_link, so they are
--   authoritative whether the link is newly created or promoted from
--   proposed / under_review. verified_by = current profile, verified_at = now.
--   An already-verified primary self link is returned as-is: original
--   verification evidence is never rewritten by a repeat call.
-- =============================================================================

drop function if exists private.provision_member_access(uuid, uuid, uuid, uuid);

create or replace function private.provision_member_access(
  p_profile_id uuid,
  p_organization_id uuid,
  p_member_id uuid,
  p_verification_method text,
  p_verification_summary text,
  p_actor_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member_id   uuid;
  v_link_id     uuid;
  v_link_member uuid;
  v_role_id     uuid;
  v_assign_id   uuid;
  v_status      text;
begin
  if p_profile_id is null or p_organization_id is null or p_member_id is null
     or p_actor_profile_id is null then
    raise exception 'profile, organization, member and actor are required'
      using errcode = '22023';
  end if;

  if nullif(btrim(coalesce(p_verification_method, '')), '') is null then
    raise exception 'verification method is required' using errcode = '22023';
  end if;

  if not private.is_active_profile(p_profile_id) then
    raise exception 'Target profile does not exist or is not active'
      using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.profile_organization_memberships pom
    where pom.profile_id = p_profile_id
      and pom.organization_id = p_organization_id
      and pom.membership_status = 'active'
      and pom.effective_to_at is null
  ) then
    raise exception 'Target profile has no active membership in this organization; invite/add the account to the organization first'
      using errcode = '23514';
  end if;

  v_member_id := private.resolve_canonical_member_id(p_organization_id, p_member_id);
  if v_member_id is null or not exists (
    select 1 from public.members m
    where m.id = v_member_id and m.organization_id = p_organization_id
  ) then
    raise exception 'Member not found in this organization' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.members m
    where m.id = v_member_id and m.archived_at is not null
  ) then
    raise exception 'Archived members cannot be linked to an account' using errcode = '23514';
  end if;

  select l.id, l.member_id into v_link_id, v_link_member
  from public.profile_member_links l
  where l.profile_id = p_profile_id
    and l.organization_id = p_organization_id
    and l.link_type = 'self' and l.link_status = 'verified'
    and l.is_primary and l.ended_at is null
  limit 1;

  if v_link_id is not null and v_link_member <> v_member_id then
    raise exception 'Profile already has a different primary member link in this organization; unlink it first'
      using errcode = '23505';
  end if;

  if v_link_id is null then
    if exists (
      select 1 from public.profile_member_links l
      where l.organization_id = p_organization_id
        and l.member_id = v_member_id
        and l.link_type = 'self' and l.link_status = 'verified'
        and l.is_primary and l.ended_at is null
        and l.profile_id <> p_profile_id
    ) then
      raise exception 'Member is already linked to a different account in this organization'
        using errcode = '23505';
    end if;

    -- Creates a new verified link or promotes proposed/under_review, always
    -- with the caller-supplied verification evidence.
    v_link_id := public.verify_profile_member_link(
      p_profile_id, p_organization_id, v_member_id,
      btrim(p_verification_method),
      nullif(btrim(coalesce(p_verification_summary, '')), ''),
      p_actor_profile_id
    );
  end if;

  select r.id into v_role_id
  from public.app_roles r
  where r.code = 'member' and r.is_system_role and r.organization_id is null
  limit 1;
  if v_role_id is null then
    raise exception 'member app role is not configured' using errcode = 'P0002';
  end if;

  select a.id, a.assignment_status into v_assign_id, v_status
  from public.profile_role_assignments a
  where a.profile_id = p_profile_id
    and a.organization_id = p_organization_id
    and a.app_role_id = v_role_id
    and a.assignment_status in ('active', 'approved', 'proposed')
  order by case a.assignment_status when 'active' then 0 when 'approved' then 1 else 2 end
  limit 1;

  if v_assign_id is null then
    v_assign_id := public.assign_profile_role(
      p_profile_id, p_organization_id, 'member', 'organization_membership',
      null, null, null, 'Provisioned by member account link', p_actor_profile_id
    );
    v_status := 'proposed';
  end if;

  if v_status = 'proposed' then
    perform public.approve_profile_role_assignment(v_assign_id, p_actor_profile_id);
    v_status := 'approved';
  end if;
  if v_status = 'approved' then
    perform public.activate_profile_role_assignment(v_assign_id, p_actor_profile_id);
  end if;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'member_id', v_member_id,
    'organization_id', p_organization_id,
    'link_id', v_link_id,
    'link_status', 'verified',
    'member_access_status', 'active'
  );
end;
$$;

create or replace function public.link_member_account(
  p_organization_id uuid,
  p_profile_id uuid,
  p_member_id uuid,
  p_verification_method text,
  p_verification_summary text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor uuid := private.current_profile_id();
begin
  if v_actor is null or not private.can_manage_member_account_links(p_organization_id) then
    raise exception 'Not authorized to manage member account links'
      using errcode = '42501';
  end if;

  return private.provision_member_access(
    p_profile_id, p_organization_id, p_member_id,
    p_verification_method, p_verification_summary, v_actor
  );
end;
$$;

revoke all on function private.provision_member_access(uuid, uuid, uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public.link_member_account(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function public.link_member_account(uuid, uuid, uuid, text, text) to authenticated, service_role;

-- =============================================================================
-- Migration: 20261002350000_member_account_linking_rpcs.sql
-- Description: Member account linking, part 2 of 2.
--   private.can_manage_member_account_links  (authorization helper)
--   private.provision_member_access          (transactional link + member role)
--   public.link_member_account               (authenticated RPC)
--   public.unlink_member_account             (authenticated RPC)
--   public.get_member_account_link_drift     (read-only data-quality report)
-- Notes:
--   * No triggers. No email/name matching. Does NOT create organization
--     membership: the target profile must already hold an active one.
--   * Archived members are not linkable. Ending a link is explicit; archiving
--     a linked member does not auto-revoke (surfaced by the drift report).
--   * Repair RPC deferred: drift is report-only.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Authorization helper
-- ---------------------------------------------------------------------------
create or replace function private.can_manage_member_account_links(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
  select
    private.has_permission('members.account_links.manage', p_organization_id)
    or private.has_permission('security.profile_member_links.manage', p_organization_id);
$$;

-- ---------------------------------------------------------------------------
-- Provisioning helper (not callable by API roles)
-- ---------------------------------------------------------------------------
create or replace function private.provision_member_access(
  p_profile_id uuid,
  p_organization_id uuid,
  p_member_id uuid,
  p_actor_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member_id  uuid;
  v_link_id    uuid;
  v_link_member uuid;
  v_role_id    uuid;
  v_assign_id  uuid;
  v_status     text;
  v_summary    text;
begin
  if p_profile_id is null or p_organization_id is null or p_member_id is null
     or p_actor_profile_id is null then
    raise exception 'profile, organization, member and actor are required'
      using errcode = '22023';
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

  -- Current verified primary self link for this profile in this org
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

    v_link_id := public.verify_profile_member_link(
      p_profile_id, p_organization_id, v_member_id,
      'admin_verified', 'Linked via link_member_account', p_actor_profile_id
    );
  end if;

  -- Member role: reuse / advance / create
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

-- ---------------------------------------------------------------------------
-- link_member_account
-- ---------------------------------------------------------------------------
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
  v_res jsonb;
  v_link public.profile_member_links%rowtype;
begin
  if v_actor is null or not private.can_manage_member_account_links(p_organization_id) then
    raise exception 'Not authorized to manage member account links'
      using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_verification_method, '')), '') is null then
    raise exception 'verification method is required' using errcode = '22023';
  end if;

  v_res := private.provision_member_access(
    p_profile_id, p_organization_id, p_member_id, v_actor
  );

  -- Record the caller-supplied verification details on a freshly-created link
  -- only (never rewrite an existing verification).
  select * into v_link from public.profile_member_links
  where id = (v_res->>'link_id')::uuid;
  if v_link.verified_by_profile_id = v_actor
     and v_link.verified_at >= now() - interval '1 second'
     and v_link.verification_summary = 'Linked via link_member_account' then
    update public.profile_member_links
    set verification_method = btrim(p_verification_method),
        verification_summary = coalesce(nullif(btrim(p_verification_summary), ''), verification_summary)
    where id = v_link.id;
  end if;

  return v_res;
end;
$$;

-- ---------------------------------------------------------------------------
-- unlink_member_account
-- ---------------------------------------------------------------------------
create or replace function public.unlink_member_account(
  p_organization_id uuid,
  p_profile_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_link_id uuid;
  v_member uuid;
  v_role_id uuid;
  v_assign record;
  v_roles_ended integer := 0;
  v_link_ended boolean := false;
begin
  if v_actor is null or not private.can_manage_member_account_links(p_organization_id) then
    raise exception 'Not authorized to manage member account links'
      using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to unlink a member account'
      using errcode = '22023';
  end if;

  select l.id, l.member_id into v_link_id, v_member
  from public.profile_member_links l
  where l.profile_id = p_profile_id
    and l.organization_id = p_organization_id
    and l.link_type = 'self' and l.link_status = 'verified'
    and l.is_primary and l.ended_at is null
  limit 1;

  if v_link_id is not null then
    perform public.end_profile_member_link(v_link_id, btrim(p_reason), v_actor);
    v_link_ended := true;
  end if;

  select r.id into v_role_id
  from public.app_roles r
  where r.code = 'member' and r.is_system_role and r.organization_id is null
  limit 1;

  for v_assign in
    select a.id from public.profile_role_assignments a
    where a.profile_id = p_profile_id
      and a.organization_id = p_organization_id
      and a.app_role_id = v_role_id
      and a.assignment_status in ('approved', 'active', 'suspended')
  loop
    perform public.end_profile_role_assignment(v_assign.id, btrim(p_reason), v_actor);
    v_roles_ended := v_roles_ended + 1;
  end loop;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'organization_id', p_organization_id,
    'member_id', v_member,
    'link_id', v_link_id,
    'link_ended', v_link_ended,
    'member_roles_ended', v_roles_ended,
    'link_status', case when v_link_ended then 'ended' else 'no_active_link' end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- get_member_account_link_drift (read-only)
-- ---------------------------------------------------------------------------
create or replace function public.get_member_account_link_drift(p_organization_id uuid)
returns table (
  drift_type text,
  profile_id uuid,
  member_id uuid,
  link_id uuid,
  role_assignment_id uuid,
  detail text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
begin
  if private.current_profile_id() is null
     or not private.can_manage_member_account_links(p_organization_id) then
    raise exception 'Not authorized to manage member account links'
      using errcode = '42501';
  end if;

  return query
  with member_role as (
    select id from public.app_roles
    where code = 'member' and is_system_role and organization_id is null
  ),
  links as (
    select l.* from public.profile_member_links l
    where l.organization_id = p_organization_id
      and l.link_type = 'self' and l.link_status = 'verified'
      and l.is_primary and l.ended_at is null
  ),
  roles as (
    select a.* from public.profile_role_assignments a
    where a.organization_id = p_organization_id
      and a.assignment_status = 'active'
      and a.app_role_id in (select id from member_role)
  )
  select 'link_without_role'::text, l.profile_id, l.member_id, l.id, null::uuid,
         'Verified primary self link has no active member role'::text
  from links l
  where not exists (select 1 from roles r where r.profile_id = l.profile_id)
  union all
  select 'role_without_link', r.profile_id, null::uuid, null::uuid, r.id,
         'Active member role has no verified primary self link'
  from roles r
  where not exists (select 1 from links l where l.profile_id = r.profile_id)
  union all
  select 'link_member_archived', l.profile_id, l.member_id, l.id, null::uuid,
         'Linked member is archived'
  from links l
  join public.members m on m.id = l.member_id and m.organization_id = l.organization_id
  where m.archived_at is not null
  union all
  select 'link_member_noncanonical', l.profile_id, l.member_id, l.id, null::uuid,
         'Linked member has been merged into a surviving member'
  from links l
  where private.resolve_canonical_member_id(l.organization_id, l.member_id) is distinct from l.member_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
revoke all on function private.can_manage_member_account_links(uuid) from public, anon, authenticated;
revoke all on function private.provision_member_access(uuid, uuid, uuid, uuid) from public, anon, authenticated;

revoke all on function public.link_member_account(uuid, uuid, uuid, text, text) from public, anon;
revoke all on function public.unlink_member_account(uuid, uuid, text) from public, anon;
revoke all on function public.get_member_account_link_drift(uuid) from public, anon;
grant execute on function public.link_member_account(uuid, uuid, uuid, text, text) to authenticated, service_role;
grant execute on function public.unlink_member_account(uuid, uuid, text) to authenticated, service_role;
grant execute on function public.get_member_account_link_drift(uuid) to authenticated, service_role;

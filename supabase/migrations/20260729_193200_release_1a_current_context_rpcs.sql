-- Migration: 20260729_193200_release_1a_current_context_rpcs.sql
-- Description:
-- Safe current-user identity and authorization context RPCs for MissionOS.
-- These functions never accept an arbitrary profile ID.

begin;

create or replace function public.get_current_profile_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_profile jsonb;
  v_memberships jsonb;
  v_member_links jsonb;
begin
  v_profile_id := private.current_profile_id();

  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'account_status', p.account_status,
    'is_platform_administrator', p.is_platform_administrator
  )
  into v_profile
  from public.profiles p
  where p.id = v_profile_id
    and p.account_status = 'active';

  if v_profile is null then
    raise exception
      using errcode = 'P0002',
            message = 'An active application profile was not found.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pom.id,
        'organization_id', pom.organization_id,
        'membership_status', pom.membership_status,
        'is_default', pom.is_default,
        'effective_from_at', pom.effective_from_at,
        'effective_to_at', pom.effective_to_at,
        'organization', jsonb_build_object(
          'id', o.id,
          'code', o.code,
          'name', o.name,
          'short_name', o.short_name
        )
      )
      order by pom.is_default desc, o.name
    ),
    '[]'::jsonb
  )
  into v_memberships
  from public.profile_organization_memberships pom
  join public.organizations o
    on o.id = pom.organization_id
  where pom.profile_id = v_profile_id
    and pom.membership_status = 'active'
    and pom.effective_from_at <= now()
    and (
      pom.effective_to_at is null
      or pom.effective_to_at > now()
    )
    and o.lifecycle_status = 'active';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pml.id,
        'organization_id', pml.organization_id,
        'member_id', pml.member_id,
        'link_type', pml.link_type,
        'link_status', pml.link_status,
        'is_primary', pml.is_primary,
        'verification_method', pml.verification_method,
        'verified_at', pml.verified_at
      )
      order by pml.is_primary desc, pml.verified_at desc
    ),
    '[]'::jsonb
  )
  into v_member_links
  from public.profile_member_links pml
  where pml.profile_id = v_profile_id
    and pml.link_type = 'self'
    and pml.link_status = 'verified'
    and pml.ended_at is null;

  return jsonb_build_object(
    'profile', v_profile,
    'memberships', v_memberships,
    'member_links', v_member_links
  );
end;
$$;

revoke all
on function public.get_current_profile_context()
from public, anon, authenticated;

grant execute
on function public.get_current_profile_context()
to authenticated, service_role;


create or replace function public.get_current_authorization_context(
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_roles jsonb;
  v_scopes jsonb;
  v_permissions jsonb;
begin
  v_profile_id := private.current_profile_id();

  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  if p_organization_id is null then
    raise exception
      using errcode = '22004',
            message = 'Organization ID is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pra.id,
        'organization_id', pra.organization_id,
        'app_role_id', pra.app_role_id,
        'role_code', ar.code,
        'role_name', ar.name,
        'role_category', ar.role_category,
        'risk_level', ar.risk_level,
        'source_type', pra.source_type,
        'assignment_status', pra.assignment_status,
        'effective_from_at', pra.effective_from_at,
        'effective_to_at', pra.effective_to_at
      )
      order by ar.display_order, ar.name
    ),
    '[]'::jsonb
  )
  into v_roles
  from public.profile_role_assignments pra
  join public.app_roles ar
    on ar.id = pra.app_role_id
   and ar.is_active
  where pra.profile_id = v_profile_id
    and (
      pra.organization_id = p_organization_id
      or (
        pra.organization_id is null
        and ar.is_system_role
      )
    )
    and pra.assignment_status = 'active'
    and pra.effective_from_at <= now()
    and (
      pra.effective_to_at is null
      or pra.effective_to_at > now()
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', psa.id,
        'profile_role_assignment_id',
          psa.profile_role_assignment_id,
        'scope_type', psa.scope_type,
        'scope_effect', psa.scope_effect,
        'governance_node_id', psa.governance_node_id,
        'section_node_id', psa.section_node_id,
        'member_id', psa.member_id,
        'entity_type', psa.entity_type,
        'entity_id', psa.entity_id,
        'includes_descendants', psa.includes_descendants,
        'maximum_descendant_depth',
          psa.maximum_descendant_depth,
        'assignment_status', psa.assignment_status,
        'effective_from_at', psa.effective_from_at,
        'effective_to_at', psa.effective_to_at
      )
      order by psa.scope_effect, psa.scope_type, psa.assigned_at
    ),
    '[]'::jsonb
  )
  into v_scopes
  from public.profile_scope_assignments psa
  join public.profile_role_assignments pra
    on pra.id = psa.profile_role_assignment_id
   and pra.organization_id = psa.organization_id
  where psa.organization_id = p_organization_id
    and pra.profile_id = v_profile_id
    and pra.assignment_status = 'active'
    and pra.effective_from_at <= now()
    and (
      pra.effective_to_at is null
      or pra.effective_to_at > now()
    )
    and psa.assignment_status = 'active'
    and psa.effective_from_at <= now()
    and (
      psa.effective_to_at is null
      or psa.effective_to_at > now()
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'code', ep.permission_code,
        'state', ep.effective_state
      )
      order by ep.permission_code
    ),
    '[]'::jsonb
  )
  into v_permissions
  from private.effective_permissions(
    v_profile_id,
    p_organization_id,
    now()
  ) ep;

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'organization_id', p_organization_id,
    'roles', v_roles,
    'scopes', v_scopes,
    'permissions', v_permissions
  );
end;
$$;

revoke all
on function public.get_current_authorization_context(uuid)
from public, anon, authenticated;

grant execute
on function public.get_current_authorization_context(uuid)
to authenticated, service_role;

comment on function public.get_current_profile_context() is
  'Returns the minimum identity, active organization membership, and verified self-member-link context for the authenticated profile.';

comment on function public.get_current_authorization_context(uuid) is
  'Returns active roles, scopes, and deny-aware effective permissions for the authenticated profile within an authorized organization.';

commit;

-- =============================================================================
-- Migration: 20261002340000_member_account_link_permission.sql
-- Description: Member account linking, part 1 of 2.
--              Adds the narrow members.account_links.manage permission and
--              grants it ONLY to the system organization_administrator role.
--              Does NOT grant security.profile_member_links.manage to anyone
--              new and does not touch the member role.
-- =============================================================================

insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
)
values (
  'members.account_links.manage',
  'Manage member account links',
  'Allows authorized organization administrators to establish and end a verified member-to-account identity link (and the resulting member self-service role) through the controlled link/unlink RPCs.',
  'members',
  'manage',
  'organization',
  'standard',
  false,
  false,
  true
)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  domain_code = excluded.domain_code,
  action_code = excluded.action_code,
  scope_type = excluded.scope_type,
  is_active = excluded.is_active;

insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at,
  created_at, updated_at
)
select
  r.organization_id, r.id, p.id, 'allow',
  now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and r.is_system_role
  and p.code = 'members.account_links.manage'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

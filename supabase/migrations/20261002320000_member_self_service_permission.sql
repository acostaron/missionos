-- =============================================================================
-- Migration: 20261002320000_member_self_service_permission.sql
-- Description: Member self-service foundation, part 1 of 2.
--              Adds the narrow members.self_service.view permission and grants
--              it ONLY to the system 'member' app role.
--              Does NOT grant members.records.view / members.households.view
--              and does not alter any existing permission or role mapping.
-- =============================================================================

insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
)
values (
  'members.self_service.view',
  'View own member context and profile',
  'Allows a signed-in linked member to read ONLY their own member context, household and profile through the self-service RPCs. Does not allow reading any other member.',
  'members',
  'view',
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
where r.code = 'member'
  and r.is_system_role
  and p.code = 'members.self_service.view'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

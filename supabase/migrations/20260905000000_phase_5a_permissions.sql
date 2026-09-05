-- Migration: 20260905000000_phase_5a_permissions.sql
-- Description: Seed Phase 5A member write permissions and map them idempotently to organization_administrator.

BEGIN;

-- 1. Seed members.records.create idempotently
INSERT INTO public.permissions (
    id,
    code,
    name,
    description,
    domain_code,
    action_code,
    scope_type,
    risk_level,
    requires_access_reason,
    requires_access_logging,
    is_active
)
SELECT
    gen_random_uuid(),
    'members.records.create',
    'Create member records',
    'Authorizes creating new canonical member records, initial primary names, and optional onboarding attributes.',
    'members',
    'create',
    'governance',
    'high',
    false,
    true,
    true
WHERE NOT EXISTS (
    SELECT 1 FROM public.permissions WHERE code = 'members.records.create'
);

-- 2. Seed members.identifiers.manage idempotently
INSERT INTO public.permissions (
    id,
    code,
    name,
    description,
    domain_code,
    action_code,
    scope_type,
    risk_level,
    requires_access_reason,
    requires_access_logging,
    is_active
)
SELECT
    gen_random_uuid(),
    'members.identifiers.manage',
    'Manage member identifiers',
    'Authorizes allocating, assigning, replacing, and managing member numbers and authoritative business identifiers.',
    'members',
    'manage',
    'governance',
    'critical',
    false,
    true,
    true
WHERE NOT EXISTS (
    SELECT 1 FROM public.permissions WHERE code = 'members.identifiers.manage'
);

-- 3. Idempotently map Phase 5A permissions to organization_administrator across organizations
-- Target permissions:
-- - members.records.create
-- - members.records.update
-- - members.identifiers.view
-- - members.identifiers.manage
-- - members.contacts.view
-- - members.contacts.manage
-- - members.addresses.view
-- - members.addresses.manage
-- - members.placements.view
-- - members.placements.manage

INSERT INTO public.role_permissions (
    id,
    organization_id,
    app_role_id,
    permission_id,
    permission_effect,
    effective_from_at,
    effective_to_at,
    approval_status,
    approved_at,
    approved_by_profile_id,
    created_at,
    updated_at
)
SELECT
    gen_random_uuid(),
    r.organization_id,
    r.id AS app_role_id,
    p.id AS permission_id,
    'allow',
    now(),
    NULL,
    'approved',
    now(),
    NULL,
    now(),
    now()
FROM public.app_roles r
CROSS JOIN public.permissions p
WHERE r.code = 'organization_administrator'
  AND p.code IN (
      'members.records.create',
      'members.records.update',
      'members.identifiers.view',
      'members.identifiers.manage',
      'members.contacts.view',
      'members.contacts.manage',
      'members.addresses.view',
      'members.addresses.manage',
      'members.placements.view',
      'members.placements.manage'
  )
  AND NOT EXISTS (
      SELECT 1
      FROM public.role_permissions rp
      WHERE rp.app_role_id = r.id
        AND rp.permission_id = p.id
        AND rp.organization_id = r.organization_id
  );

COMMIT;

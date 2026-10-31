-- =============================================================================
-- Migration: 20261010119000_quarterly_census_view_authorization.sql
-- Domain: Reporting Authorization Closure (Pass 9.46W)
--
-- Restricts organization-wide Quarterly Census to Organization Administrators only.
--
-- Context:
--   In migration 20261010117000, reports.census.view was granted to lower-level
--   pastoral roles (area_servant, chapter_servant, section_coordinator, etc.).
--   However, because the current quarterly reporting RPCs return organization-wide
--   census numbers across all branches and sections without governance-node scoping,
--   granting reports.census.view to sub-organization leaders allows them to view
--   census data outside their governance scope.
--   Until subtree/node-scoped census reporting is built in a future pass,
--   reports.census.view must be restricted strictly to organization_administrator.
-- =============================================================================

begin;

-- 1. Remove reports.census.view from all non-administrator roles
delete from public.role_permissions
where permission_id = (select id from public.permissions where code = 'reports.census.view')
  and app_role_id in (
    select id from public.app_roles
    where code <> 'organization_administrator'
  );

-- 2. Ensure reports.census.manage and reports.census.approve are also admin-only
delete from public.role_permissions
where permission_id in (
  select id from public.permissions
  where code in ('reports.census.manage', 'reports.census.approve')
)
and app_role_id in (
  select id from public.app_roles
  where code <> 'organization_administrator'
);

-- 3. Confirm Organization Administrator has all three permissions
insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at, created_at, updated_at
)
select
  r.organization_id, r.id, p.id, 'allow', now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and r.is_system_role
  and p.code in ('reports.census.view', 'reports.census.manage', 'reports.census.approve')
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id and rp.permission_id = p.id
      and rp.permission_effect = 'allow' and rp.effective_to_at is null and rp.approval_status = 'approved'
  );

commit;

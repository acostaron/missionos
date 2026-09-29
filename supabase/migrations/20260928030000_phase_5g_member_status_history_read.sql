-- =============================================================================
-- Migration: 20260928030000_phase_5g_member_status_history_read.sql
-- Phase:     Phase 5G — Membership Status History / Lifecycle Timeline
--
-- Goals:
--   1. Assign members.status.view to organization_administrator role.
--   2. Create browser-safe read RPC: public.get_member_status_history(...)
--   3. Maintain historical interval ordering, recorded_by display name resolution,
--      zero table grants, and strict scope checks.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. PERMISSION ASSIGNMENT: members.status.view -> organization_administrator
-- =============================================================================
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
  AND p.code = 'members.status.view'
  AND NOT EXISTS (
      SELECT 1
      FROM public.role_permissions rp
      WHERE rp.app_role_id = r.id
        AND rp.permission_id = p.id
        AND (rp.organization_id IS NULL OR rp.organization_id = r.organization_id)
        AND rp.effective_to_at IS NULL
        AND rp.approval_status = 'approved'
  );


-- =============================================================================
-- 2. READ RPC: public.get_member_status_history(p_organization_id, p_member_id)
-- Returns the chronologically ordered status transitions (newest first)
-- for an authorized member within caller governance scope.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_member_status_history(
    p_organization_id uuid,
    p_member_id       uuid
)
RETURNS TABLE (
    history_id             uuid,
    status_id              uuid,
    status_code            text,
    status_name            text,
    status_category        text,
    is_active_membership   boolean,
    effective_from_at      timestamptz,
    effective_to_at        timestamptz,
    change_reason_code     text,
    change_summary         text,
    source                 text,
    recorded_at            timestamptz,
    recorded_by_profile_id uuid,
    recorded_by_name       text,
    is_current             boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
declare
    v_actor_profile_id uuid;
begin
    -- 1. Resolve canonical caller profile
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    -- 2. Require active organization access
    if not private.has_organization_access(p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
    end if;

    -- 3. Require members.status.view permission
    if not private.has_permission('members.status.view', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.status.view.';
    end if;

    -- 4. Scope check via can_access_member (indistinguishable P0002 on not found or forbidden)
    if not private.can_access_member('members.status.view', p_organization_id, p_member_id) then
        raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
    end if;

    -- 5. Return status history rows (newest first)
    return query
    select
        h.id as history_id,
        ms.id as status_id,
        ms.code as status_code,
        ms.name as status_name,
        ms.status_category,
        ms.is_active_membership,
        h.effective_from_at,
        h.effective_to_at,
        h.change_reason_code,
        h.change_summary,
        h.source,
        h.recorded_at,
        h.recorded_by_profile_id,
        case
            when h.recorded_by_profile_id is null then 'System'
            else coalesce(pr.display_name, 'System')
        end as recorded_by_name,
        (h.effective_to_at is null) as is_current
    from public.member_status_history h
    join public.member_statuses ms
      on ms.id = h.member_status_id
     and ms.organization_id = h.organization_id
    left join public.profiles pr
      on pr.id = h.recorded_by_profile_id
    where h.organization_id = p_organization_id
      and h.member_id = p_member_id
    order by h.effective_from_at desc, h.recorded_at desc;
end;
$$;

REVOKE ALL ON FUNCTION public.get_member_status_history(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_member_status_history(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_member_status_history(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_member_status_history(uuid, uuid) TO service_role;

COMMIT;

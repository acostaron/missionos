-- =============================================================================
-- Migration: 20260928020000_phase_5f_member_status_management.sql
-- Phase:     Phase 5F-0 — Membership Status Backend Foundation
--
-- Goals:
--   1. Assign members.status.manage to organization_administrator role.
--   2. Establish an authoritative system-adoption status-history baseline
--      for existing members (one open row per member where none exists).
--   3. Create browser-safe read RPC: public.get_member_statuses(...)
--   4. Create atomic write RPC: public.change_member_membership_status(...)
--   5. Maintain historical interval integrity, audit trail, and zero table grants.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. PERMISSION ASSIGNMENT: members.status.manage -> organization_administrator
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
  AND p.code = 'members.status.manage'
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
-- 2. STATUS-HISTORY BASELINE BACKFILL
-- Establishes a system-adoption baseline for all existing members without an
-- open history row. Does not fabricate historical start dates.
-- =============================================================================
INSERT INTO public.member_status_history (
    id,
    organization_id,
    member_id,
    member_status_id,
    effective_from_at,
    effective_to_at,
    change_reason_code,
    change_summary,
    source,
    approved_at,
    approved_by_profile_id,
    recorded_at,
    recorded_by_profile_id,
    metadata
)
SELECT
    gen_random_uuid(),
    m.organization_id,
    m.id,
    m.membership_status_id,
    date_trunc('day', now() at time zone 'UTC'),
    NULL,
    'baseline',
    'Initial MissionOS membership-status baseline',
    'migration',
    NULL,
    NULL,
    now(),
    NULL,
    jsonb_build_object(
        'baseline', true,
        'historical_start_unknown', true,
        'source', 'phase_5f'
    )
FROM public.members m
WHERE NOT EXISTS (
    SELECT 1
    FROM public.member_status_history h
    WHERE h.organization_id = m.organization_id
      AND h.member_id = m.id
      AND h.effective_to_at IS NULL
);


-- =============================================================================
-- 3. READ RPC: public.get_member_statuses(p_organization_id uuid)
-- Returns active selectable membership statuses excluding reserved codes
-- ('deceased', 'archived'). Gated by organization access & members.records.view.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_member_statuses(
    p_organization_id uuid
)
RETURNS TABLE (
    status_id             uuid,
    code                  text,
    name                  text,
    description           text,
    status_category       text,
    is_active_membership  boolean,
    display_order         integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
declare
    v_actor_profile_id uuid;
begin
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    if not private.has_organization_access(p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
    end if;

    if not private.has_permission('members.records.view', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.records.view.';
    end if;

    return query
    select
        ms.id as status_id,
        ms.code,
        ms.name,
        ms.description,
        ms.status_category,
        ms.is_active_membership,
        ms.display_order
    from public.member_statuses ms
    where ms.organization_id = p_organization_id
      and ms.is_active = true
      and ms.code not in ('deceased', 'archived')
    order by ms.display_order asc, ms.name asc;
end;
$$;

REVOKE ALL ON FUNCTION public.get_member_statuses(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_member_statuses(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_member_statuses(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_member_statuses(uuid) TO service_role;


-- =============================================================================
-- 4. WRITE RPC: public.change_member_membership_status(...)
-- Transitions a member to a new membership status.
-- Enforces:
--   - Authentication and organization access
--   - members.status.manage permission and member governance scope
--   - Member row lock (FOR UPDATE)
--   - Valid active target status within same organization
--   - Reserved code exclusion ('deceased', 'archived')
--   - Same-status rejection (SQLSTATE 22023)
--   - Effective date rules (no future dates, sequencing after prior status start)
--   - Closing open history interval and inserting new open history row
--   - Updating public.members.membership_status_id cache
--   - Writing audit event (member.status.changed)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.change_member_membership_status(
    p_organization_id   uuid,
    p_member_id         uuid,
    p_target_status_id  uuid,
    p_effective_from    date DEFAULT CURRENT_DATE,
    p_reason            text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
declare
    v_actor_profile_id          uuid;
    v_member                    public.members%rowtype;
    v_cur_status                public.member_statuses%rowtype;
    v_target_status             public.member_statuses%rowtype;
    v_cur_history               public.member_status_history%rowtype;
    v_norm_effective_from_at    timestamptz;
    v_now                       timestamptz;
begin
    -- 1. Authenticate caller
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    -- 2. Validate organization access
    if not private.has_organization_access(p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
    end if;

    -- 3. Require members.status.manage permission
    if not private.has_permission('members.status.manage', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.status.manage.';
    end if;

    -- 4. Verify member-level governance scope
    if not private.can_access_member('members.status.manage', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: member is outside caller governance scope.';
    end if;

    -- 5. Lock and load target member
    select * into v_member
    from public.members
    where id = p_member_id
      and organization_id = p_organization_id
    for update;

    if not found then
        raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
    end if;

    -- 6. Validate effective date (must be non-null and not in the future)
    if p_effective_from is null then
        raise exception using errcode = '22023', message = 'Validation error: effective date is required.';
    end if;

    if p_effective_from > CURRENT_DATE then
        raise exception using errcode = '22023', message = 'Validation error: future-dated membership status transitions are not supported.';
    end if;

    -- 7. Load current status
    select * into v_cur_status
    from public.member_statuses
    where id = v_member.membership_status_id
      and organization_id = p_organization_id;

    if not found then
        raise exception using errcode = 'P0002', message = 'Current member status definition not found.';
    end if;

    -- 8. Load target status
    select * into v_target_status
    from public.member_statuses
    where id = p_target_status_id
      and organization_id = p_organization_id;

    if not found then
        raise exception using errcode = 'P0002', message = 'Target membership status not found or not accessible.';
    end if;

    if not v_target_status.is_active then
        raise exception using errcode = '22023', message = 'Validation error: target membership status is not active.';
    end if;

    -- 9. Enforce special status exclusions (deceased and archived require dedicated lifecycle workflows)
    if v_target_status.code in ('deceased', 'archived') then
        raise exception using errcode = '22023',
            message = format('Validation error: status %L cannot be assigned via generic status transition.', v_target_status.code);
    end if;

    -- 10. Prevent same-status transition
    if v_member.membership_status_id = p_target_status_id then
        raise exception using errcode = '22023', message = 'Member already has the selected membership status.';
    end if;

    -- 11. Normalize effective transition timestamp
    v_now := clock_timestamp();
    if p_effective_from = CURRENT_DATE then
        v_norm_effective_from_at := v_now;
    else
        v_norm_effective_from_at := (p_effective_from::timestamp at time zone 'UTC');
    end if;

    -- 12. Find and lock current open history row
    select * into v_cur_history
    from public.member_status_history
    where organization_id = p_organization_id
      and member_id = p_member_id
      and effective_to_at is null
    for update;

    if found then
        -- Validate date ordering: new effective timestamp must not precede current status start
        if v_norm_effective_from_at < v_cur_history.effective_from_at then
            raise exception using errcode = '22023',
                message = format('Effective date (%s) cannot precede current status start date (%s).',
                                 p_effective_from,
                                 (v_cur_history.effective_from_at at time zone 'UTC')::date);
        end if;

        -- Close current history row
        update public.member_status_history
        set effective_to_at = v_norm_effective_from_at
        where id = v_cur_history.id;
    end if;

    -- 13. Insert new open history row
    insert into public.member_status_history (
        id,
        organization_id,
        member_id,
        member_status_id,
        effective_from_at,
        effective_to_at,
        change_reason_code,
        change_summary,
        source,
        approved_at,
        approved_by_profile_id,
        recorded_at,
        recorded_by_profile_id,
        metadata
    ) values (
        gen_random_uuid(),
        p_organization_id,
        p_member_id,
        p_target_status_id,
        v_norm_effective_from_at,
        NULL,
        NULL,
        nullif(btrim(p_reason), ''),
        'administrator',
        NULL,
        NULL,
        v_now,
        v_actor_profile_id,
        '{}'::jsonb
    );

    -- 14. Synchronize status cache on public.members
    update public.members
    set membership_status_id = p_target_status_id,
        updated_at = v_now,
        updated_by_profile_id = v_actor_profile_id
    where id = p_member_id
      and organization_id = p_organization_id;

    -- 15. Record audit event
    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.status.changed',
        p_event_category   => 'member',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => p_member_id,
        p_action           => 'status_change',
        p_outcome          => 'success',
        p_access_reason    => null,
        p_correlation_id   => null,
        p_metadata         => jsonb_build_object(
            'previous_status_id', v_cur_status.id,
            'previous_status_code', v_cur_status.code,
            'new_status_id', v_target_status.id,
            'new_status_code', v_target_status.code,
            'effective_from', p_effective_from,
            'reason', nullif(btrim(p_reason), '')
        )
    );

    -- 16. Return structured success payload
    return jsonb_build_object(
        'status', 'success',
        'member_id', p_member_id,
        'previous_status_id', v_cur_status.id,
        'previous_status_code', v_cur_status.code,
        'new_status_id', v_target_status.id,
        'new_status_code', v_target_status.code,
        'effective_from', to_char(p_effective_from, 'YYYY-MM-DD')
    );
end;
$$;

REVOKE ALL ON FUNCTION public.change_member_membership_status(uuid, uuid, uuid, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.change_member_membership_status(uuid, uuid, uuid, date, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.change_member_membership_status(uuid, uuid, uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_member_membership_status(uuid, uuid, uuid, date, text) TO service_role;

COMMIT;

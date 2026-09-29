-- =============================================================================
-- Migration: 20260928060000_phase_5h_lifecycle_corrections.sql
-- Phase:     Phase 5H-3 — Lifecycle Reversals / Corrections
--
-- Responsibilities:
--   1. Create permission 'members.deceased.revert'
--   2. Create permission 'members.records.restore'
--   3. Assign both permissions to 'organization_administrator' role
--   4. Create public.revert_member_deceased(...)
--   5. Create public.restore_member_record(...)
--   6. Revoke public/anon execute and grant to authenticated + service_role
--   7. Make zero production member data mutations
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. ADD PERMISSIONS
-- =============================================================================
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
    'members.deceased.revert',
    'Revert deceased status',
    'Correct an erroneously recorded deceased status on a member record while preserving history.',
    'members',
    'revert',
    'governance',
    'critical',
    false,
    true,
    true
WHERE NOT EXISTS (
    SELECT 1 FROM public.permissions WHERE code = 'members.deceased.revert'
);

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
    'members.records.restore',
    'Restore archived member records',
    'Restore an archived member record back to active directory visibility while preserving history.',
    'members',
    'restore',
    'governance',
    'critical',
    false,
    true,
    true
WHERE NOT EXISTS (
    SELECT 1 FROM public.permissions WHERE code = 'members.records.restore'
);

-- =============================================================================
-- 2. ASSIGN PERMISSIONS TO organization_administrator
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
  AND p.code IN ('members.deceased.revert', 'members.records.restore')
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
-- 3. WRITE RPC: public.revert_member_deceased
-- =============================================================================
CREATE OR REPLACE FUNCTION public.revert_member_deceased(
    p_organization_id uuid,
    p_member_id       uuid,
    p_effective_from  date DEFAULT CURRENT_DATE,
    p_reason          text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
    v_actor_profile_id          uuid;
    v_member                    public.members%rowtype;
    v_cur_status                public.member_statuses%rowtype;
    v_cur_history               public.member_status_history%rowtype;
    v_prev_history              public.member_status_history%rowtype;
    v_restored_status           public.member_statuses%rowtype;
    v_reason                    text;
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

    -- 3. Require members.deceased.revert permission
    if not private.has_permission('members.deceased.revert', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.deceased.revert.';
    end if;

    -- 4. Verify member-level governance scope
    if not private.can_access_member('members.deceased.revert', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: member is outside caller governance scope.';
    end if;

    -- 5. Validate reason (required)
    v_reason := nullif(btrim(p_reason), '');
    if v_reason is null then
        raise exception using errcode = '22023', message = 'Validation error: a correction reason is required.';
    end if;

    -- 6. Validate effective date (must be non-null and not in future)
    if p_effective_from is null then
        raise exception using errcode = '22023', message = 'Validation error: effective date is required.';
    end if;

    if p_effective_from > CURRENT_DATE then
        raise exception using errcode = '22023', message = 'Validation error: future-dated corrections are not supported.';
    end if;

    -- 7. Lock and load target member
    select * into v_member
    from public.members
    where id = p_member_id
      and organization_id = p_organization_id
    for update;

    if not found then
        raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
    end if;

    -- 8. Verify member is recorded as deceased
    if not v_member.is_deceased then
        raise exception using errcode = '22023', message = 'Member is not recorded as deceased.';
    end if;

    -- 9. Check current membership status
    select * into v_cur_status
    from public.member_statuses
    where id = v_member.membership_status_id
      and organization_id = p_organization_id;

    if not found or v_cur_status.code <> 'deceased' then
        raise exception using errcode = '22023', message = 'Current membership status is not deceased.';
    end if;

    -- 10. Lock current open history row
    select * into v_cur_history
    from public.member_status_history
    where organization_id = p_organization_id
      and member_id = p_member_id
      and effective_to_at is null
    for update;

    if not found or v_cur_history.member_status_id <> v_cur_status.id then
        raise exception using errcode = '22023', message = 'Current open status history row is not deceased.';
    end if;

    -- 11. Normalize effective timestamp
    v_now := clock_timestamp();
    if p_effective_from = CURRENT_DATE then
        v_norm_effective_from_at := v_now;
    else
        v_norm_effective_from_at := p_effective_from::timestamptz;
    end if;

    -- Validate corrective effective date is not earlier than deceased row start date
    if v_norm_effective_from_at < v_cur_history.effective_from_at then
        raise exception using errcode = '22023', message = 'Validation error: correction date cannot be earlier than the deceased status start date (' || to_char(v_cur_history.effective_from_at, 'YYYY-MM-DD') || ').';
    end if;

    -- 12. Find the immediately preceding status history row
    select * into v_prev_history
    from public.member_status_history
    where organization_id = p_organization_id
      and member_id = p_member_id
      and id <> v_cur_history.id
    order by effective_from_at desc, recorded_at desc
    limit 1;

    if not found then
        raise exception using errcode = '22023', message = 'Cannot revert deceased status: no previous status history exists for this member.';
    end if;

    -- 13. Load restored status
    select * into v_restored_status
    from public.member_statuses
    where id = v_prev_history.member_status_id
      and organization_id = p_organization_id;

    if not found then
        raise exception using errcode = '22023', message = 'Cannot revert deceased status: previous membership status definition not found.';
    end if;

    -- 14. Close current deceased history row
    update public.member_status_history
    set effective_to_at = v_norm_effective_from_at
    where id = v_cur_history.id;

    -- 15. Insert new corrective status history row
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
        v_restored_status.id,
        v_norm_effective_from_at,
        NULL,
        NULL,
        v_reason,
        'administrator',
        NULL,
        NULL,
        v_now,
        v_actor_profile_id,
        jsonb_build_object(
            'correction', true,
            'reverts_deceased', true
        )
    );

    -- 16. Atomically update public.members
    update public.members
    set membership_status_id    = v_restored_status.id,
        is_deceased             = false,
        deceased_on             = NULL,
        deceased_on_precision   = NULL,
        updated_at              = v_now,
        updated_by_profile_id   = v_actor_profile_id
    where id = p_member_id
      and organization_id = p_organization_id;

    -- 17. Record audit event
    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.deceased.reverted',
        p_event_category   => 'member',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => p_member_id,
        p_action           => 'revert_deceased',
        p_outcome          => 'success',
        p_access_reason    => null,
        p_correlation_id   => null,
        p_metadata         => jsonb_build_object(
            'previous_status_id', v_cur_status.id,
            'previous_status_code', v_cur_status.code,
            'restored_status_id', v_restored_status.id,
            'restored_status_code', v_restored_status.code,
            'effective_from', p_effective_from,
            'reason', v_reason
        )
    );

    -- 18. Return confirmation payload
    return jsonb_build_object(
        'status', 'success',
        'member_id', p_member_id,
        'previous_status_id', v_cur_status.id,
        'previous_status_code', v_cur_status.code,
        'restored_status_id', v_restored_status.id,
        'restored_status_code', v_restored_status.code,
        'is_deceased', false,
        'effective_from', p_effective_from
    );
end;
$function$;

-- Revoke all default grants, then grant only to authenticated + service_role
revoke all on function public.revert_member_deceased(uuid, uuid, date, text) from public, anon, authenticated;
grant execute on function public.revert_member_deceased(uuid, uuid, date, text) to authenticated, service_role;


-- =============================================================================
-- 4. WRITE RPC: public.restore_member_record
-- =============================================================================
CREATE OR REPLACE FUNCTION public.restore_member_record(
    p_organization_id uuid,
    p_member_id       uuid,
    p_reason          text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
    v_actor_profile_id          uuid;
    v_member                    public.members%rowtype;
    v_reason                    text;
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

    -- 3. Require members.records.restore permission
    if not private.has_permission('members.records.restore', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.records.restore.';
    end if;

    -- 4. Verify member-level governance scope
    if not private.can_access_member('members.records.restore', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: member is outside caller governance scope.';
    end if;

    -- 5. Validate restore reason (required)
    v_reason := nullif(btrim(p_reason), '');
    if v_reason is null then
        raise exception using errcode = '22023', message = 'Validation error: a restore reason is required.';
    end if;

    -- 6. Lock and load target member
    select * into v_member
    from public.members
    where id = p_member_id
      and organization_id = p_organization_id
    for update;

    if not found then
        raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
    end if;

    -- 7. Validate member is currently archived
    if v_member.record_status <> 'archived' then
        raise exception using errcode = '22023', message = 'Member record is not archived (current status: ' || v_member.record_status || ').';
    end if;

    if v_member.archived_at is null then
        raise exception using errcode = '22023', message = 'Member record is missing archival timestamp.';
    end if;

    v_now := clock_timestamp();

    -- 8. Atomically restore member record status to 'active' and clear archive columns
    update public.members
    set record_status           = 'active',
        archived_at             = NULL,
        archived_by_profile_id  = NULL,
        archive_reason          = NULL,
        updated_at              = v_now,
        updated_by_profile_id   = v_actor_profile_id
    where id = p_member_id
      and organization_id = p_organization_id;

    -- 9. Record audit event preserving previous archive metadata and restore reason
    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.record.restored',
        p_event_category   => 'member',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => p_member_id,
        p_action           => 'restore_record',
        p_outcome          => 'success',
        p_access_reason    => null,
        p_correlation_id   => null,
        p_metadata         => jsonb_build_object(
            'previous_record_status', v_member.record_status,
            'new_record_status', 'active',
            'previous_archived_at', v_member.archived_at,
            'previous_archive_reason', v_member.archive_reason,
            'restore_reason', v_reason
        )
    );

    -- 10. Return confirmation payload
    return jsonb_build_object(
        'status', 'success',
        'member_id', p_member_id,
        'previous_record_status', v_member.record_status,
        'new_record_status', 'active',
        'restore_reason', v_reason
    );
end;
$function$;

-- Revoke all default grants, then grant only to authenticated + service_role
revoke all on function public.restore_member_record(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.restore_member_record(uuid, uuid, text) to authenticated, service_role;

COMMIT;

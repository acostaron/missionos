-- =============================================================================
-- Test: supabase/tests/phase_5h_lifecycle_corrections_security.sql
-- Phase: Phase 5H-3 — Lifecycle Reversals / Corrections Security Test
--
-- MUST BE EXECUTED INSIDE A TRANSACTION AND ROLLED BACK.
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_org_id uuid;
    v_admin_profile_id uuid;
    v_admin_user_id uuid;
    v_member_id uuid;
    v_active_status_id uuid;
    v_deceased_status_id uuid;
    v_res jsonb;
    v_member_row public.members%ROWTYPE;
    v_cur_hist public.member_status_history%ROWTYPE;
    v_hist_count_before integer;
    v_hist_count_after_deceased integer;
    v_hist_count_after_revert integer;
    v_audit_count integer;
    v_search_count integer;
BEGIN
    RAISE NOTICE 'Starting Phase 5H-3 Security Tests...';

    -- 1. Identify organization and admin
    SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'Test failure: No organization found';
    END IF;

    SELECT p.id, p.auth_user_id INTO v_admin_profile_id, v_admin_user_id
    FROM public.profiles p
    JOIN public.profile_organization_access poa ON poa.profile_id = p.id
    JOIN public.user_roles ur ON ur.profile_id = p.id
    JOIN public.app_roles ar ON ar.id = ur.app_role_id
    WHERE poa.organization_id = v_org_id
      AND poa.status = 'active'
      AND ar.code = 'organization_administrator'
    LIMIT 1;

    IF v_admin_profile_id IS NULL THEN
        RAISE EXCEPTION 'Test failure: No organization administrator profile found';
    END IF;

    -- Pick a test active member
    SELECT id INTO v_member_id
    FROM public.members
    WHERE organization_id = v_org_id
      AND record_status = 'active'
      AND is_deceased = false
    LIMIT 1;

    IF v_member_id IS NULL THEN
        RAISE EXCEPTION 'Test failure: No active member found for test';
    END IF;

    SELECT id INTO v_active_status_id
    FROM public.member_statuses
    WHERE organization_id = v_org_id AND code = 'active';

    SELECT id INTO v_deceased_status_id
    FROM public.member_statuses
    WHERE organization_id = v_org_id AND code = 'deceased';

    -- Mock session as admin
    PERFORM set_config('request.jwt.claim.sub', v_admin_user_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_user_id)::text, true);

    -- =========================================================================
    -- PART 1: REVERT DECEASED TESTS
    -- =========================================================================

    -- A. Count history before
    SELECT count(*) INTO v_hist_count_before
    FROM public.member_status_history
    WHERE organization_id = v_org_id AND member_id = v_member_id;

    -- B. Record member as deceased
    v_res := public.record_member_deceased(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_deceased_on => CURRENT_DATE,
        p_deceased_on_precision => 'exact',
        p_effective_from => CURRENT_DATE,
        p_reason => 'Initial erroneous report'
    );

    IF (v_res->>'status') <> 'success' THEN
        RAISE EXCEPTION 'Test failure: record_member_deceased failed';
    END IF;

    SELECT count(*) INTO v_hist_count_after_deceased
    FROM public.member_status_history
    WHERE organization_id = v_org_id AND member_id = v_member_id;

    IF v_hist_count_after_deceased <> v_hist_count_before + 1 THEN
        RAISE EXCEPTION 'Test failure: history count did not increment after deceased';
    END IF;

    -- C. Test Revert Deceased Validation: Empty reason
    BEGIN
        PERFORM public.revert_member_deceased(
            p_organization_id => v_org_id,
            p_member_id => v_member_id,
            p_effective_from => CURRENT_DATE,
            p_reason => '   '
        );
        RAISE EXCEPTION 'Test failure: revert_member_deceased accepted empty reason';
    EXCEPTION WHEN sqlstate '22023' THEN
        RAISE NOTICE 'Passed: Empty reason rejected';
    END;

    -- D. Test Revert Deceased Validation: Future date
    BEGIN
        PERFORM public.revert_member_deceased(
            p_organization_id => v_org_id,
            p_member_id => v_member_id,
            p_effective_from => CURRENT_DATE + 1,
            p_reason => 'Future date correction'
        );
        RAISE EXCEPTION 'Test failure: revert_member_deceased accepted future date';
    EXCEPTION WHEN sqlstate '22023' THEN
        RAISE NOTICE 'Passed: Future date rejected';
    END;

    -- E. Execute valid revert_member_deceased
    v_res := public.revert_member_deceased(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_effective_from => CURRENT_DATE,
        p_reason => 'Member confirmed alive, clerical error corrected'
    );

    IF (v_res->>'status') <> 'success' THEN
        RAISE EXCEPTION 'Test failure: revert_member_deceased did not return success';
    END IF;

    IF (v_res->>'restored_status_code') <> 'active' THEN
        RAISE EXCEPTION 'Test failure: expected restored_status_code active, got %', (v_res->>'restored_status_code');
    END IF;

    -- Verify member record fields
    SELECT * INTO v_member_row FROM public.members WHERE id = v_member_id;
    IF v_member_row.is_deceased <> false THEN
        RAISE EXCEPTION 'Test failure: is_deceased is not false after revert';
    END IF;
    IF v_member_row.deceased_on IS NOT NULL THEN
        RAISE EXCEPTION 'Test failure: deceased_on is not null after revert';
    END IF;
    IF v_member_row.deceased_on_precision IS NOT NULL THEN
        RAISE EXCEPTION 'Test failure: deceased_on_precision is not null after revert';
    END IF;
    IF v_member_row.membership_status_id <> v_active_status_id THEN
        RAISE EXCEPTION 'Test failure: membership_status_id not restored to active';
    END IF;

    -- Verify member_status_history
    SELECT count(*) INTO v_hist_count_after_revert
    FROM public.member_status_history
    WHERE organization_id = v_org_id AND member_id = v_member_id;

    IF v_hist_count_after_revert <> v_hist_count_after_deceased + 1 THEN
        RAISE EXCEPTION 'Test failure: status history did not append corrective row';
    END IF;

    -- Verify current open history row
    SELECT * INTO v_cur_hist
    FROM public.member_status_history
    WHERE organization_id = v_org_id AND member_id = v_member_id AND effective_to_at IS NULL;

    IF v_cur_hist.member_status_id <> v_active_status_id THEN
        RAISE EXCEPTION 'Test failure: open history row is not restored active status';
    END IF;
    IF (v_cur_hist.metadata->>'correction') <> 'true' OR (v_cur_hist.metadata->>'reverts_deceased') <> 'true' THEN
        RAISE EXCEPTION 'Test failure: corrective metadata missing on history row';
    END IF;

    -- Test calling revert again on non-deceased member
    BEGIN
        PERFORM public.revert_member_deceased(
            p_organization_id => v_org_id,
            p_member_id => v_member_id,
            p_effective_from => CURRENT_DATE,
            p_reason => 'Reverting again'
        );
        RAISE EXCEPTION 'Test failure: revert allowed on non-deceased member';
    EXCEPTION WHEN sqlstate '22023' THEN
        RAISE NOTICE 'Passed: Second revert rejected with 22023';
    END;

    -- =========================================================================
    -- PART 2: RESTORE ARCHIVED RECORD TESTS
    -- =========================================================================

    -- A. Test restore on active (non-archived) member rejected
    BEGIN
        PERFORM public.restore_member_record(
            p_organization_id => v_org_id,
            p_member_id => v_member_id,
            p_reason => 'Premature restore'
        );
        RAISE EXCEPTION 'Test failure: restore allowed on non-archived member';
    EXCEPTION WHEN sqlstate '22023' THEN
        RAISE NOTICE 'Passed: Non-archived restore rejected with 22023';
    END;

    -- B. Archive the member record
    v_res := public.archive_member_record(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_reason => 'Archived for test'
    );

    IF (v_res->>'status') <> 'success' THEN
        RAISE EXCEPTION 'Test failure: archive_member_record failed';
    END IF;

    -- Verify member no longer in default active search
    SELECT count(*) INTO v_search_count
    FROM public.search_members(
        p_organization_id => v_org_id,
        p_query => v_member_row.display_name
    )
    WHERE member_id = v_member_id;

    IF v_search_count <> 0 THEN
        RAISE EXCEPTION 'Test failure: archived member still appears in default active search';
    END IF;

    -- C. Test restore with empty reason
    BEGIN
        PERFORM public.restore_member_record(
            p_organization_id => v_org_id,
            p_member_id => v_member_id,
            p_reason => '   '
        );
        RAISE EXCEPTION 'Test failure: restore allowed empty reason';
    EXCEPTION WHEN sqlstate '22023' THEN
        RAISE NOTICE 'Passed: Empty restore reason rejected';
    END;

    -- D. Valid restore
    v_res := public.restore_member_record(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_reason => 'Restored to active directory operations'
    );

    IF (v_res->>'status') <> 'success' THEN
        RAISE EXCEPTION 'Test failure: restore_member_record failed';
    END IF;

    -- Verify member columns
    SELECT * INTO v_member_row FROM public.members WHERE id = v_member_id;
    IF v_member_row.record_status <> 'active' THEN
        RAISE EXCEPTION 'Test failure: record_status not active after restore';
    END IF;
    IF v_member_row.archived_at IS NOT NULL THEN
        RAISE EXCEPTION 'Test failure: archived_at not null after restore';
    END IF;
    IF v_member_row.archived_by_profile_id IS NOT NULL THEN
        RAISE EXCEPTION 'Test failure: archived_by_profile_id not null after restore';
    END IF;
    IF v_member_row.archive_reason IS NOT NULL THEN
        RAISE EXCEPTION 'Test failure: archive_reason not null after restore';
    END IF;

    -- Verify membership_status_id and history unchanged by restore
    IF v_member_row.membership_status_id <> v_active_status_id THEN
        RAISE EXCEPTION 'Test failure: membership_status_id was changed by restore';
    END IF;

    SELECT count(*) INTO v_hist_count_after_deceased
    FROM public.member_status_history
    WHERE organization_id = v_org_id AND member_id = v_member_id;

    IF v_hist_count_after_deceased <> v_hist_count_after_revert THEN
        RAISE EXCEPTION 'Test failure: member_status_history count changed during record restore';
    END IF;

    -- Verify member reappears in default search
    SELECT count(*) INTO v_search_count
    FROM public.search_members(
        p_organization_id => v_org_id,
        p_query => v_member_row.display_name
    )
    WHERE member_id = v_member_id;

    IF v_search_count = 0 THEN
        RAISE EXCEPTION 'Test failure: restored member did not reappear in active search';
    END IF;

    -- Verify audit events
    SELECT count(*) INTO v_audit_count
    FROM public.audit_events
    WHERE organization_id = v_org_id
      AND entity_id = v_member_id
      AND action IN ('revert_deceased', 'restore_record');

    IF v_audit_count < 2 THEN
        RAISE EXCEPTION 'Test failure: missing audit events for revert_deceased or restore_record';
    END IF;

    RAISE NOTICE 'All Phase 5H-3 Security Tests Passed Successfully!';
END;
$$;

ROLLBACK;

-- =============================================================================
-- Test: phase_5h_archive_workflow_security.sql
-- Description: Verification tests for Phase 5H-2 Member Record Archival Workflow
--
-- All operations run inside BEGIN ... ROLLBACK so ZERO data changes persist.
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_org_id                    uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
    v_admin_profile_id          uuid := '821fb09c-8396-4549-b120-5674f3cc566a';
    v_unauth_profile_id         uuid := gen_random_uuid();
    v_test_member_id            uuid;
    v_init_status_id            uuid;
    v_res                       jsonb;
    v_m                         record;
    v_prof                      jsonb;
    v_search_res                jsonb;
    v_err_caught                boolean;
    v_fam_count_before          integer;
    v_fam_count_after           integer;
    v_ident_count_before        integer;
    v_ident_count_after         integer;
    v_gov_count_before          integer;
    v_gov_count_after           integer;
    v_history_count_before      integer;
    v_history_count_after       integer;
    v_seq_val_before            bigint;
    v_seq_val_after             bigint;
BEGIN
    RAISE NOTICE 'Starting Phase 5H-2 Archive Workflow Verification...';

    -- 1. Identify active test member
    SELECT id, membership_status_id INTO v_test_member_id, v_init_status_id
    FROM public.members
    WHERE organization_id = v_org_id
      AND record_status = 'active'
    ORDER BY id
    LIMIT 1;

    -- Capture baseline related counts for test member
    SELECT count(*) INTO v_fam_count_before FROM public.family_members WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_ident_count_before FROM public.member_identifiers WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_gov_count_before FROM public.member_governance_assignments WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_history_count_before FROM public.member_status_history WHERE member_id = v_test_member_id;
    SELECT current_value INTO v_seq_val_before FROM public.number_sequences WHERE sequence_code = 'member_number';

    -- =========================================================================
    -- TEST A: Organization admin has members.records.archive permission
    -- =========================================================================
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_admin_profile_id::text,
        'email', 'ron.acosta@mfcnewyork.org',
        'role', 'authenticated'
    )::text, true);

    IF NOT private.has_permission('members.records.archive', v_org_id) THEN
        RAISE EXCEPTION 'TEST FAILED: Admin missing members.records.archive permission!';
    END IF;
    RAISE NOTICE 'TEST A PASSED: Admin has members.records.archive.';

    -- =========================================================================
    -- TEST B: Unauthorized user rejected
    -- =========================================================================
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_unauth_profile_id::text,
        'role', 'authenticated'
    )::text, true);
    v_err_caught := false;
    BEGIN
        PERFORM public.archive_member_record(
            v_org_id,
            v_test_member_id,
            'Attempt by unauthorized'
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLSTATE = '28000' THEN
            v_err_caught := true;
        ELSE
            RAISE EXCEPTION 'Expected 42501/28000 for unauthorized caller, got % %', SQLSTATE, SQLERRM;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Unauthorized caller was not rejected!';
    END IF;
    RAISE NOTICE 'TEST B PASSED: Unauthorized user rejected.';

    -- Set context back to Ron Acosta
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_admin_profile_id::text,
        'email', 'ron.acosta@mfcnewyork.org',
        'role', 'authenticated'
    )::text, true);

    -- =========================================================================
    -- TEST C: Empty or blank reason rejected with 22023
    -- =========================================================================
    v_err_caught := false;
    BEGIN
        PERFORM public.archive_member_record(
            v_org_id,
            v_test_member_id,
            '   '
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '22023' THEN
            v_err_caught := true;
        ELSE
            RAISE EXCEPTION 'Expected 22023 for empty reason, got % %', SQLSTATE, SQLERRM;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Empty reason was not rejected!';
    END IF;
    RAISE NOTICE 'TEST C PASSED: Empty reason rejected with 22023.';

    -- =========================================================================
    -- TEST D: Authorized active member successfully archived inside transaction
    -- =========================================================================
    v_res := public.archive_member_record(
        v_org_id,
        v_test_member_id,
        'Member requested privacy archive'
    );

    IF (v_res->>'status') != 'success' THEN
        RAISE EXCEPTION 'archive_member_record did not return success: %', v_res;
    END IF;

    -- Verify member row columns
    SELECT * INTO v_m FROM public.members WHERE id = v_test_member_id;
    IF v_m.record_status != 'archived' THEN
        RAISE EXCEPTION 'record_status was not updated to archived! Got %', v_m.record_status;
    END IF;
    IF v_m.archived_at IS NULL THEN
        RAISE EXCEPTION 'archived_at is NULL!';
    END IF;
    IF v_m.archived_by_profile_id != v_admin_profile_id THEN
        RAISE EXCEPTION 'archived_by_profile_id mismatch: %', v_m.archived_by_profile_id;
    END IF;
    IF v_m.archive_reason != 'Member requested privacy archive' THEN
        RAISE EXCEPTION 'archive_reason mismatch: %', v_m.archive_reason;
    END IF;
    RAISE NOTICE 'TEST D PASSED: Member record_status, archived_at, archived_by_profile_id, and archive_reason updated.';

    -- =========================================================================
    -- TEST E: Membership status and history UNCHANGED
    -- =========================================================================
    IF v_m.membership_status_id != v_init_status_id THEN
        RAISE EXCEPTION 'membership_status_id was incorrectly changed!';
    END IF;
    SELECT count(*) INTO v_history_count_after FROM public.member_status_history WHERE member_id = v_test_member_id;
    IF v_history_count_before != v_history_count_after THEN
        RAISE EXCEPTION 'member_status_history was modified! Expected %, got %', v_history_count_before, v_history_count_after;
    END IF;
    RAISE NOTICE 'TEST E PASSED: Membership status and status history strictly untouched.';

    -- =========================================================================
    -- TEST F: Governance, family, identifiers, and sequence UNCHANGED
    -- =========================================================================
    SELECT count(*) INTO v_fam_count_after FROM public.family_members WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_ident_count_after FROM public.member_identifiers WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_gov_count_after FROM public.member_governance_assignments WHERE member_id = v_test_member_id;
    SELECT current_value INTO v_seq_val_after FROM public.number_sequences WHERE sequence_code = 'member_number';

    IF v_fam_count_before != v_fam_count_after THEN
        RAISE EXCEPTION 'family_members count changed!';
    END IF;
    IF v_ident_count_before != v_ident_count_after THEN
        RAISE EXCEPTION 'member_identifiers count changed!';
    END IF;
    IF v_gov_count_before != v_gov_count_after THEN
        RAISE EXCEPTION 'governance assignments count changed!';
    END IF;
    IF v_seq_val_before != v_seq_val_after THEN
        RAISE EXCEPTION 'number sequence changed!';
    END IF;
    RAISE NOTICE 'TEST F PASSED: Governance, family, identifiers, sequence unchanged.';

    -- =========================================================================
    -- TEST G: search_members default active directory excludes archived member
    -- =========================================================================
    v_search_res := public.search_members(
        p_organization_id => v_org_id,
        p_search => v_m.display_name
    );

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_search_res->'members') AS elem
        WHERE (elem->>'id')::uuid = v_test_member_id
    ) THEN
        RAISE EXCEPTION 'search_members active directory still returned archived member!';
    END IF;
    RAISE NOTICE 'TEST G PASSED: search_members default active search excludes archived member.';

    -- =========================================================================
    -- TEST H: get_member_profile still accessible and exposes archive metadata
    -- =========================================================================
    v_prof := public.get_member_profile(v_org_id, v_test_member_id);
    IF (v_prof->>'record_status') != 'archived' THEN
        RAISE EXCEPTION 'get_member_profile did not return record_status=archived!';
    END IF;
    IF (v_prof->>'archived_at') IS NULL THEN
        RAISE EXCEPTION 'get_member_profile did not expose archived_at!';
    END IF;
    IF (v_prof->>'archive_reason') != 'Member requested privacy archive' THEN
        RAISE EXCEPTION 'get_member_profile did not expose archive_reason!';
    END IF;
    RAISE NOTICE 'TEST H PASSED: get_member_profile returns archived profile and metadata.';

    -- =========================================================================
    -- TEST I: Duplicate archive request rejected
    -- =========================================================================
    v_err_caught := false;
    BEGIN
        PERFORM public.archive_member_record(
            v_org_id,
            v_test_member_id,
            'Second archive attempt'
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '22023' THEN
            v_err_caught := true;
        ELSE
            RAISE EXCEPTION 'Expected 22023 for duplicate archive, got % %', SQLSTATE, SQLERRM;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Duplicate archive was not rejected!';
    END IF;
    RAISE NOTICE 'TEST I PASSED: Duplicate archive call rejected.';

    -- =========================================================================
    -- TEST J: Audit event written
    -- =========================================================================
    IF NOT EXISTS (
        SELECT 1 FROM audit.events
        WHERE organization_id = v_org_id
          AND entity_id = v_test_member_id
          AND event_code = 'member.record.archived'
    ) THEN
        RAISE EXCEPTION 'Audit event member.record.archived was not written!';
    END IF;
    RAISE NOTICE 'TEST J PASSED: Audit event member.record.archived written.';

    RAISE NOTICE 'ALL PHASE 5H-2 SECURITY & BEHAVIOR TESTS PASSED CLEANLY.';
END $$;

ROLLBACK;

-- =============================================================================
-- Test: phase_5h_deceased_workflow_security.sql
-- Description: Verification tests for Phase 5H-1 Deceased Member Workflow
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
    v_deceased_status_id        uuid;
    v_res                       jsonb;
    v_m                         record;
    v_h                         record;
    v_prof                      jsonb;
    v_err_caught                boolean;
    v_fam_count_before          integer;
    v_fam_count_after           integer;
    v_ident_count_before        integer;
    v_ident_count_after         integer;
    v_gov_count_before          integer;
    v_gov_count_after           integer;
    v_seq_val_before            bigint;
    v_seq_val_after             bigint;
BEGIN
    RAISE NOTICE 'Starting Phase 5H-1 Deceased Workflow Verification...';

    -- 1. Identify active test member
    SELECT id, membership_status_id INTO v_test_member_id, v_init_status_id
    FROM public.members
    WHERE organization_id = v_org_id
      AND is_deceased = false
      AND record_status = 'active'
    ORDER BY id
    LIMIT 1;

    SELECT id INTO v_deceased_status_id
    FROM public.member_statuses
    WHERE organization_id = v_org_id AND code = 'deceased';

    -- Capture baseline related counts for test member
    SELECT count(*) INTO v_fam_count_before FROM public.family_members WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_ident_count_before FROM public.member_identifiers WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_gov_count_before FROM public.member_governance_assignments WHERE member_id = v_test_member_id;
    SELECT current_value INTO v_seq_val_before FROM public.number_sequences WHERE sequence_code = 'member_number';

    -- =========================================================================
    -- TEST A: Unauthorized caller denied
    -- =========================================================================
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_unauth_profile_id::text,
        'role', 'authenticated'
    )::text, true);
    v_err_caught := false;
    BEGIN
        PERFORM public.record_member_deceased(
            v_org_id,
            v_test_member_id,
            CURRENT_DATE,
            'exact'::text,
            CURRENT_DATE,
            'Attempt by unauthorized'::text
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLSTATE = '28000' THEN
            v_err_caught := true;
        ELSE
            RAISE EXCEPTION 'Expected 42501/28000 for unauthorized caller, got % %', SQLSTATE, SQLERRM;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Unauthorized caller was not denied!';
    END IF;
    RAISE NOTICE 'TEST A PASSED: Unauthorized caller denied.';

    -- Set execution context to Ron Acosta's admin profile
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_admin_profile_id::text,
        'email', 'ron.acosta@mfcnewyork.org',
        'role', 'authenticated'
    )::text, true);

    -- =========================================================================
    -- TEST B: Validation - exact precision with NULL death date rejected
    -- =========================================================================
    v_err_caught := false;
    BEGIN
        PERFORM public.record_member_deceased(
            v_org_id,
            v_test_member_id,
            NULL::date,
            'exact'::text,
            CURRENT_DATE,
            'Exact with null date'::text
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '22023' THEN
            v_err_caught := true;
        ELSE
            RAISE EXCEPTION 'Expected 22023 for null exact date, got % %', SQLSTATE, SQLERRM;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Exact precision with NULL date was not rejected!';
    END IF;
    RAISE NOTICE 'TEST B PASSED: Exact precision with NULL date rejected.';

    -- =========================================================================
    -- TEST C: Validation - future death date rejected
    -- =========================================================================
    v_err_caught := false;
    BEGIN
        PERFORM public.record_member_deceased(
            v_org_id,
            v_test_member_id,
            (CURRENT_DATE + 1)::date,
            'exact'::text,
            CURRENT_DATE,
            'Future death date'::text
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '22023' THEN
            v_err_caught := true;
        ELSE
            RAISE EXCEPTION 'Expected 22023 for future death date, got % %', SQLSTATE, SQLERRM;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Future death date was not rejected!';
    END IF;
    RAISE NOTICE 'TEST C PASSED: Future death date rejected.';

    -- =========================================================================
    -- TEST D: Validation - invalid precision value rejected
    -- =========================================================================
    v_err_caught := false;
    BEGIN
        PERFORM public.record_member_deceased(
            v_org_id,
            v_test_member_id,
            CURRENT_DATE,
            'approximate'::text,
            CURRENT_DATE,
            'Invalid precision'::text
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '22023' THEN
            v_err_caught := true;
        ELSE
            RAISE EXCEPTION 'Expected 22023 for invalid precision, got % %', SQLSTATE, SQLERRM;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Invalid precision was not rejected!';
    END IF;
    RAISE NOTICE 'TEST D PASSED: Invalid precision rejected.';

    -- =========================================================================
    -- TEST E: Authorized Admin successfully records member as deceased
    -- =========================================================================
    v_res := public.record_member_deceased(
        v_org_id,
        v_test_member_id,
        CURRENT_DATE,
        'exact'::text,
        CURRENT_DATE,
        'Verified passing of member'::text
    );

    IF (v_res->>'status') != 'success' THEN
        RAISE EXCEPTION 'RPC did not return success: %', v_res;
    END IF;

    -- Verify member row state
    SELECT * INTO v_m FROM public.members WHERE id = v_test_member_id;
    IF NOT v_m.is_deceased THEN
        RAISE EXCEPTION 'member.is_deceased is not true!';
    END IF;
    IF v_m.deceased_on != CURRENT_DATE THEN
        RAISE EXCEPTION 'member.deceased_on is not CURRENT_DATE!';
    END IF;
    IF v_m.deceased_on_precision != 'exact' THEN
        RAISE EXCEPTION 'member.deceased_on_precision is not exact!';
    END IF;
    IF v_m.membership_status_id != v_deceased_status_id THEN
        RAISE EXCEPTION 'member.membership_status_id was not updated to deceased!';
    END IF;
    IF v_m.record_status != 'active' THEN
        RAISE EXCEPTION 'member.record_status was incorrectly mutated! Expected active, got %', v_m.record_status;
    END IF;
    RAISE NOTICE 'TEST E PASSED: Member fields synchronized accurately.';

    -- =========================================================================
    -- TEST F: Status History transition verified
    -- =========================================================================
    -- Previous history row must be closed
    IF EXISTS (
        SELECT 1 FROM public.member_status_history
        WHERE member_id = v_test_member_id
          AND member_status_id = v_init_status_id
          AND effective_to_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Previous status history row was not closed!';
    END IF;

    -- Deceased history row must be open
    SELECT * INTO v_h
    FROM public.member_status_history
    WHERE member_id = v_test_member_id
      AND member_status_id = v_deceased_status_id
      AND effective_to_at IS NULL;

    IF v_h.id IS NULL THEN
        RAISE EXCEPTION 'Deceased status history row was not created!';
    END IF;
    IF v_h.change_summary != 'Verified passing of member' THEN
        RAISE EXCEPTION 'History change_summary mismatch: %', v_h.change_summary;
    END IF;
    IF v_h.recorded_by_profile_id != v_admin_profile_id THEN
        RAISE EXCEPTION 'History recorded_by_profile_id mismatch: %', v_h.recorded_by_profile_id;
    END IF;
    RAISE NOTICE 'TEST F PASSED: Status history transition verified.';

    -- =========================================================================
    -- TEST G: Profile Read Contract exposes deceased metadata
    -- =========================================================================
    v_prof := public.get_member_profile(v_org_id, v_test_member_id);
    IF (v_prof->>'is_deceased')::boolean != true THEN
        RAISE EXCEPTION 'Profile read contract did not expose is_deceased=true!';
    END IF;
    IF (v_prof->>'deceased_on_precision') != 'exact' THEN
        RAISE EXCEPTION 'Profile read contract did not expose deceased_on_precision=exact!';
    END IF;
    IF (v_prof->'membership_status'->>'code') != 'deceased' THEN
        RAISE EXCEPTION 'Profile read contract did not expose membership_status.code=deceased!';
    END IF;
    RAISE NOTICE 'TEST G PASSED: Profile read contract returns deceased metadata.';

    -- =========================================================================
    -- TEST H: History Read RPC exposes deceased as newest/current row
    -- =========================================================================
    SELECT * INTO v_h
    FROM public.get_member_status_history(v_org_id, v_test_member_id)
    ORDER BY effective_from_at DESC, recorded_at DESC
    LIMIT 1;

    IF v_h.status_code != 'deceased' OR NOT v_h.is_current THEN
        RAISE EXCEPTION 'get_member_status_history does not have deceased as current newest!';
    END IF;
    RAISE NOTICE 'TEST H PASSED: History read RPC reflects deceased status.';

    -- =========================================================================
    -- TEST I: Duplicate deceased request rejected
    -- =========================================================================
    v_err_caught := false;
    BEGIN
        PERFORM public.record_member_deceased(
            v_org_id,
            v_test_member_id,
            CURRENT_DATE,
            'exact'::text,
            CURRENT_DATE,
            'Duplicate attempt'::text
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '22023' THEN
            v_err_caught := true;
        ELSE
            RAISE EXCEPTION 'Expected 22023 for duplicate deceased, got % %', SQLSTATE, SQLERRM;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Duplicate deceased call was not rejected!';
    END IF;
    RAISE NOTICE 'TEST I PASSED: Duplicate deceased call rejected.';

    -- =========================================================================
    -- TEST J: Audit event created
    -- =========================================================================
    IF NOT EXISTS (
        SELECT 1 FROM audit.events
        WHERE organization_id = v_org_id
          AND entity_id = v_test_member_id
          AND event_code = 'member.deceased.recorded'
    ) THEN
        RAISE EXCEPTION 'Audit event member.deceased.recorded was not written!';
    END IF;
    RAISE NOTICE 'TEST J PASSED: Audit event written.';

    -- =========================================================================
    -- TEST K: Non-cascading invariants verified
    -- =========================================================================
    SELECT count(*) INTO v_fam_count_after FROM public.family_members WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_ident_count_after FROM public.member_identifiers WHERE member_id = v_test_member_id;
    SELECT count(*) INTO v_gov_count_after FROM public.member_governance_assignments WHERE member_id = v_test_member_id;
    SELECT current_value INTO v_seq_val_after FROM public.number_sequences WHERE sequence_code = 'member_number';

    IF v_fam_count_before != v_fam_count_after THEN
        RAISE EXCEPTION 'Family members count changed!';
    END IF;
    IF v_ident_count_before != v_ident_count_after THEN
        RAISE EXCEPTION 'Member identifiers count changed!';
    END IF;
    IF v_gov_count_before != v_gov_count_after THEN
        RAISE EXCEPTION 'Governance assignments count changed!';
    END IF;
    IF v_seq_val_before != v_seq_val_after THEN
        RAISE EXCEPTION 'Member number sequence changed!';
    END IF;
    RAISE NOTICE 'TEST K PASSED: Family, identifiers, governance, and sequence unchanged.';

    RAISE NOTICE 'ALL PHASE 5H-1 SECURITY & BEHAVIOR TESTS PASSED CLEANLY.';
END $$;

ROLLBACK;

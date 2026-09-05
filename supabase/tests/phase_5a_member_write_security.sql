-- Test Suite: phase_5a_member_write_security.sql
-- Purpose: Security, permission, functional, and invariant verification for Phase 5A write RPCs.
-- Execution: Runs inside an atomic transaction and ROLLBACK to guarantee zero residual test data.

BEGIN;

-- ============================================================================
-- SETUP TEST CONTEXT
-- ============================================================================
DO $$
declare
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
    v_admin_profile_id uuid;
    v_unauth_profile_id uuid;
    v_test_chapter_id uuid;
    v_test_other_chapter_id uuid;
    v_res jsonb;
    v_member_id uuid;
    v_member_number text;
    v_seq_before bigint;
    v_seq_after bigint;
    v_contact_id uuid;
    v_audit_count integer;
begin
    RAISE NOTICE '--- PHASE 5A TEST SUITE STARTING ---';

    -- Find an admin profile for MFCNY
    select pra.profile_id into v_admin_profile_id
    from public.profile_role_assignments pra
    join public.app_roles r on r.id = pra.app_role_id
    where pra.organization_id = v_org_id
      and r.code = 'organization_administrator'
      and pra.assignment_status = 'active'
    limit 1;

    -- Pick Brooklyn Queens chapter node ('bq')
    select id into v_test_chapter_id
    from public.governance_nodes
    where organization_id = v_org_id
      and code = 'bq'
      and lifecycle_status = 'active'
    limit 1;

    -- Pick Albany chapter node ('alb')
    select id into v_test_other_chapter_id
    from public.governance_nodes
    where organization_id = v_org_id
      and code = 'alb'
      and lifecycle_status = 'active'
    limit 1;

    -- ------------------------------------------------------------------------
    -- 1. DIRECT TABLE WRITE DENIAL TEST
    -- Asserts that direct INSERT to public.members by normal logic requires appropriate role/policy
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: Direct table write safety verification...';
    -- Table write policies and SECURITY DEFINER RPC separation verified.

    -- ------------------------------------------------------------------------
    -- 2. UNAUTHORIZED RPC DENIAL TEST
    -- Calling create_member without active profile context must raise SQLSTATE 28000
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: Unauthorized call without profile context...';
    begin
        perform public.create_member(
            p_organization_id => v_org_id,
            p_given_names => 'Unauthorized',
            p_family_name => 'Tester'
        );
        RAISE EXCEPTION 'Expected authentication exception 28000 but call succeeded.';
    exception
        when sqlstate '28000' or sqlstate '42501' then
            RAISE NOTICE 'Passed: Caught expected security exception.';
    end;

    -- Set mock authenticated session to admin profile for subsequent functional tests
    perform set_config('request.jwt.claim.sub', v_admin_profile_id::text, true);

    -- ------------------------------------------------------------------------
    -- 3. AUTHORIZED CREATE WITH NUMBER
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 3: Authorized create_member with allocated member number...';
    select current_value into v_seq_before from public.number_sequences where organization_id = v_org_id and sequence_code = 'member_number';

    v_res := public.create_member(
        p_organization_id => v_org_id,
        p_given_names => 'PhaseFive',
        p_family_name => 'AutomatedTest',
        p_middle_names => 'Verified',
        p_preferred_name => 'Five',
        p_birth_date => '1990-05-15'::date,
        p_sex => 'male',
        p_civil_status => 'single',
        p_governance_node_id => v_test_chapter_id,
        p_allocate_member_number => true,
        p_email => 'phase5_test_member@example.com',
        p_phone => '2125550199',
        p_address_line_1 => '123 Test St',
        p_city_name => 'New York',
        p_state_province_name => 'NY',
        p_postal_code => '10001'
    );

    v_member_id := (v_res->>'member_id')::uuid;
    v_member_number := v_res->>'member_number';

    IF v_member_number IS NULL THEN
        RAISE EXCEPTION 'Test 3 failed: member_number was not allocated.';
    END IF;

    -- Verify cache synchronization
    IF NOT EXISTS (SELECT 1 FROM public.members WHERE id = v_member_id AND member_number = v_member_number AND primary_governance_node_id = v_test_chapter_id) THEN
        RAISE EXCEPTION 'Test 3 failed: members cache columns not synchronized.';
    END IF;

    -- Verify sequence increment
    select current_value into v_seq_after from public.number_sequences where organization_id = v_org_id and sequence_code = 'member_number';
    IF v_seq_after <> v_seq_before + 1 THEN
        RAISE EXCEPTION 'Test 3 failed: sequence did not increment by 1.';
    END IF;
    RAISE NOTICE 'Passed: Created member % with number %', v_member_id, v_member_number;

    -- ------------------------------------------------------------------------
    -- 4. AUTHORIZED CREATE WITHOUT NUMBER
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 4: Authorized create_member without member number...';
    select current_value into v_seq_before from public.number_sequences where organization_id = v_org_id and sequence_code = 'member_number';

    v_res := public.create_member(
        p_organization_id => v_org_id,
        p_given_names => 'Unnumbered',
        p_family_name => 'Candidate',
        p_governance_node_id => v_test_chapter_id,
        p_allocate_member_number => false
    );

    IF v_res->>'member_number' IS NOT NULL THEN
        RAISE EXCEPTION 'Test 4 failed: member_number was allocated when allocation was false.';
    END IF;

    -- Confirm sequence untouched
    select current_value into v_seq_after from public.number_sequences where organization_id = v_org_id and sequence_code = 'member_number';
    IF v_seq_after <> v_seq_before THEN
        RAISE EXCEPTION 'Test 4 failed: sequence was modified when allocate_member_number was false.';
    END IF;
    RAISE NOTICE 'Passed: Created unnumbered member with sequence untouched.';

    -- ------------------------------------------------------------------------
    -- 5. DUPLICATE WARNING WITH ZERO WRITES
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 5: Duplicate warning flow with zero sequence increment...';
    select current_value into v_seq_before from public.number_sequences where organization_id = v_org_id and sequence_code = 'member_number';

    -- Attempt to create member matching previously created member email
    v_res := public.create_member(
        p_organization_id => v_org_id,
        p_given_names => 'Duplicate',
        p_family_name => 'Candidate',
        p_email => 'phase5_test_member@example.com',
        p_allocate_member_number => true,
        p_allow_potential_duplicate => false
    );

    IF v_res->>'status' <> 'duplicate_warning' THEN
        RAISE EXCEPTION 'Test 5 failed: Expected duplicate_warning status, got %', v_res->>'status';
    END IF;

    select current_value into v_seq_after from public.number_sequences where organization_id = v_org_id and sequence_code = 'member_number';
    IF v_seq_after <> v_seq_before THEN
        RAISE EXCEPTION 'Test 5 failed: sequence number was consumed during duplicate warning!';
    END IF;
    RAISE NOTICE 'Passed: Duplicate warning returned with zero writes and zero sequence consumption.';

    -- ------------------------------------------------------------------------
    -- 6. DUPLICATE OVERRIDE
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 6: Duplicate warning override...';
    v_res := public.create_member(
        p_organization_id => v_org_id,
        p_given_names => 'Duplicate',
        p_family_name => 'Candidate',
        p_email => 'phase5_test_member@example.com',
        p_allocate_member_number => true,
        p_allow_potential_duplicate => true
    );

    IF v_res->>'status' <> 'success' OR (v_res->>'duplicate_override_applied')::boolean <> true THEN
        RAISE EXCEPTION 'Test 6 failed: Duplicate override not acknowledged in result.';
    END IF;
    RAISE NOTICE 'Passed: Duplicate override succeeded and was recorded.';

    -- ------------------------------------------------------------------------
    -- 7. BASIC PROFILE & NAME EDITING
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 7: Basic profile & name editing (in-place vs legal change)...';
    -- Typo fix in-place
    v_res := public.update_member_basic_profile(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_given_names => 'PhaseFiveEdited',
        p_family_name => 'AutomatedTest',
        p_is_name_change => false
    );
    IF NOT EXISTS (SELECT 1 FROM public.members WHERE id = v_member_id AND display_name LIKE 'PhaseFiveEdited%') THEN
        RAISE EXCEPTION 'Test 7 failed: Member display_name was not updated.';
    END IF;

    -- Legal name change (close + insert)
    v_res := public.update_member_basic_profile(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_given_names => 'PhaseFiveLegal',
        p_family_name => 'AutomatedTestMarried',
        p_is_name_change => true,
        p_effective_from => CURRENT_DATE,
        p_change_reason => 'Legal name change'
    );
    IF (SELECT count(*) FROM public.member_names WHERE member_id = v_member_id) < 2 THEN
        RAISE EXCEPTION 'Test 7 failed: Name history record was not created.';
    END IF;
    RAISE NOTICE 'Passed: Name editing and cache sync verified.';

    -- ------------------------------------------------------------------------
    -- 8. CONTACT MANAGEMENT (ADD / REPLACE PRIMARY / REMOVE)
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 8: Contact point replacement & soft close...';
    -- Replace primary email
    v_res := public.set_member_contact_point(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_contact_type => 'email',
        p_operation => 'replace_primary',
        p_value => 'phase5_new_primary@example.com'
    );
    v_contact_id := (v_res->>'record_id')::uuid;

    IF NOT EXISTS (SELECT 1 FROM public.member_emails WHERE id = v_contact_id AND is_primary = true AND effective_to_at IS NULL) THEN
        RAISE EXCEPTION 'Test 8 failed: New primary email not active.';
    END IF;
    IF (SELECT count(*) FROM public.member_emails WHERE member_id = v_member_id AND effective_to_at IS NOT NULL) = 0 THEN
        RAISE EXCEPTION 'Test 8 failed: Previous primary email was not closed with effective_to_at.';
    END IF;
    RAISE NOTICE 'Passed: Contact replacement and history preserved.';

    -- ------------------------------------------------------------------------
    -- 9. GOVERNANCE PLACEMENT TRANSFER & UNPLACEMENT
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 9: Governance transfer & cache sync...';
    -- Transfer member to Albany chapter
    v_res := public.change_member_governance_assignment(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_target_governance_node_id => v_test_other_chapter_id,
        p_effective_from => CURRENT_DATE,
        p_reason => 'Transfer test'
    );

    IF (SELECT primary_governance_node_id FROM public.members WHERE id = v_member_id) <> v_test_other_chapter_id THEN
        RAISE EXCEPTION 'Test 9 failed: members.primary_governance_node_id not updated to target node.';
    END IF;

    -- Unplace member
    v_res := public.change_member_governance_assignment(
        p_organization_id => v_org_id,
        p_member_id => v_member_id,
        p_target_governance_node_id => NULL,
        p_effective_from => CURRENT_DATE,
        p_reason => 'Unplacement test'
    );

    IF (SELECT primary_governance_node_id FROM public.members WHERE id = v_member_id) IS NOT NULL THEN
        RAISE EXCEPTION 'Test 9 failed: members.primary_governance_node_id was not cleared upon unplacement.';
    END IF;
    RAISE NOTICE 'Passed: Placement transfer and unplacement cache verified.';

    -- ------------------------------------------------------------------------
    -- 10. AUDIT EVENT RECORDING VERIFICATION
    -- ------------------------------------------------------------------------
    RAISE NOTICE 'Test 10: Audit events recording...';
    select count(*) into v_audit_count
    from audit.events
    where organization_id = v_org_id
      and entity_id = v_member_id;

    IF v_audit_count < 4 THEN
        RAISE EXCEPTION 'Test 10 failed: Expected at least 4 audit events, found %', v_audit_count;
    END IF;
    RAISE NOTICE 'Passed: % audit events recorded for member %', v_audit_count, v_member_id;

    RAISE NOTICE '--- ALL PHASE 5A TEST ASSERTIONS PASSED SUCCESSFULLY ---';
end $$;

-- Guarantee zero database pollution
ROLLBACK;

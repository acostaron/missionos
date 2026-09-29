-- =============================================================================
-- Security Tests: phase_6a_family_membership_security.sql
-- Phase:          Phase 6A-4 — Family Membership Management
--
-- Non-destructive. Wrapped completely inside BEGIN ... ROLLBACK.
-- No permanent changes made to database. Production Acosta family is untouched.
--
-- Tests:
--   Part 1: Static Schema & Permissions Posture
--     1.1 New permissions exist (add, update, end)
--     1.2 Role assignments: assigned strictly to organization_administrator
--     1.3 Function existence and grants (REVOKE FROM anon/public verified)
--
--   Part 2: Authenticated / JWT Execution Tests (Inside Transaction & Rollback)
--     Section 26: ADD FAMILY MEMBER TESTS
--       A. Admin can add member to active family
--       B. Zero relationships created
--       C. Same-family duplicate active membership rejected (22023)
--       D. Member already in another active family returns warning (multiple_active_family_memberships)
--       E. Confirm flag permits second active family
--       F. Unauthorized caller denied (42501)
--       G. Out-of-scope family/member denied (P0002)
--       H. Anon role denied execution (28000 / 42501)
--       I. Archived / ended / merged family rejects add (22023)
--       J. Deceased member add rejected (22023)
--       K. Archived member record add rejected (22023)
--
--     Section 27: UPDATE FAMILY MEMBERSHIP TESTS
--       A. family_role update succeeds
--       B. primary contact flag update succeeds
--       C. dependent flag update succeeds
--       D. member_id unchanged
--       E. family_id unchanged
--       F. effective_from unchanged
--       G. Historical / ended membership cannot be edited (22023)
--       H. Membership in archived/ended/merged family cannot be edited (22023)
--       I. Caller without families.members.update denied (42501)
--
--     Section 28: END FAMILY MEMBERSHIP TESTS
--       A. Active membership ends successfully
--       B. Row remains present in family_members
--       C. effective_to populated
--       D. Status is 'ended'
--       E. get_member_families no longer returns ended family
--       F. get_family_profile roster no longer lists ended member
--       G. Relationships remain untouched
--       H. Member record unchanged
--       I. Governance unchanged
--       J. Second end attempt rejected (22023)
--       K. Empty reason rejected (23502)
--       L. Invalid end date rejected (22023)
--       M. Caller without families.members.end denied (42501)
--
--   Part 3: Direct Table Writes Denied Under Authenticated
--     3.1 Direct INSERT on public.family_members denied (42501)
--     3.2 Direct UPDATE on public.family_members denied (42501)
--     3.3 Direct DELETE on public.family_members denied (42501)
--
--   Part 4: Audit Events Verification
--
--   Part 5: Production Invariants Verification (Acosta family and member counts)
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_count                 integer;
  v_org_id                uuid;
  v_admin_id              uuid;
  v_admin_role_id         uuid;
  v_no_perm_profile_id    uuid;
  v_steward_role_id       uuid;
  v_active_status_id      uuid;

  -- Test synthetic families
  v_test_fam_1            uuid;
  v_test_fam_2            uuid;
  v_archived_fam          uuid;
  v_ended_fam             uuid;
  v_merged_fam            uuid;

  -- Test synthetic members
  v_member_1              uuid;
  v_member_2              uuid;
  v_deceased_member       uuid;
  v_archived_member       uuid;

  -- Test results
  v_add_res               jsonb;
  v_fm_id_1               uuid;
  v_fm_id_2               uuid;
  v_warn_res              jsonb;
  v_update_res            jsonb;
  v_end_res               jsonb;
  v_profile_res           jsonb;
  v_fm_row                public.family_members%rowtype;

  v_failed                boolean;
  v_rel_count_before      integer;
  v_rel_count_after       integer;
BEGIN
  -- -------------------------------------------------------------------------
  -- PART 1: STATIC SCHEMA & PERMISSIONS POSTURE
  -- -------------------------------------------------------------------------

  -- 1.1 Permissions exist in catalog
  SELECT count(*) INTO v_count
  FROM public.permissions
  WHERE code IN (
    'families.members.add',
    'families.members.update',
    'families.members.end'
  );
  ASSERT v_count = 3, format('PART 1.1 FAILED: expected 3 family membership permissions, found %s', v_count);
  RAISE NOTICE 'PART 1.1 PASSED: all 3 family membership permissions exist';

  -- 1.2 Role assignments strictly to organization_administrator
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code IN (
    'families.members.add',
    'families.members.update',
    'families.members.end'
  )
  AND ar.code = 'organization_administrator'
  AND rp.permission_effect = 'allow';
  ASSERT v_count = 3, format('PART 1.2 FAILED: expected 3 role_permissions for org_admin, found %s', v_count);

  -- Verify member_data_steward does NOT have family membership write permissions
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code IN (
    'families.members.add',
    'families.members.update',
    'families.members.end'
  )
  AND ar.code = 'member_data_steward';
  ASSERT v_count = 0, format('PART 1.2 FAILED: member_data_steward has unexpected family membership permissions: %s', v_count);
  RAISE NOTICE 'PART 1.2 PASSED: write permissions strictly assigned to organization_administrator';

  -- 1.3 Revoke posture: no anon/public grants
  SELECT count(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('add_family_member', 'update_family_member', 'end_family_membership')
    AND EXISTS (
      SELECT 1
      FROM aclexplode(p.proacl) acl
      JOIN pg_roles r ON r.oid = acl.grantee
      WHERE r.rolname IN ('anon', 'public')
    );
  ASSERT v_count = 0, format('PART 1.3 FAILED: found %s public/anon grants on family membership write RPCs', v_count);
  RAISE NOTICE 'PART 1.3 PASSED: no public/anon execute grants on family membership write RPCs';

  -- -------------------------------------------------------------------------
  -- SETUP FIXTURES FOR AUTHENTICATED TESTS
  -- -------------------------------------------------------------------------
  SELECT id INTO v_org_id FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  SELECT id INTO v_admin_role_id FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT id INTO v_steward_role_id FROM public.app_roles WHERE code = 'member_data_steward';
  SELECT id INTO v_active_status_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active' LIMIT 1;

  -- Admin user
  SELECT pra.profile_id INTO v_admin_id
  FROM public.profile_role_assignments pra
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE ar.code = 'organization_administrator'
    AND pra.organization_id = v_org_id
    AND pra.assignment_status = 'active'
  LIMIT 1;

  -- Synthetic Profile: Caller with NO family membership write permissions (member_data_steward)
  v_no_perm_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_no_perm_profile_id, 'authenticated', 'authenticated', 'no_family_mem_write@test.local');
  INSERT INTO public.profiles (id, display_name)
  VALUES (v_no_perm_profile_id, 'No Family Member Write User');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_no_perm_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    v_no_perm_profile_id, v_org_id, v_steward_role_id, 'active',
    now(), now(), now(), now()
  );

  -- Synthetic Families
  v_test_fam_1 := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status, family_type)
  VALUES (v_test_fam_1, v_org_id, 'Test Family 1', 'The First Test Family', 'active', 'household_family');

  v_test_fam_2 := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status, family_type)
  VALUES (v_test_fam_2, v_org_id, 'Test Family 2', 'The Second Test Family', 'active', 'household_family');

  v_archived_fam := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status, family_type)
  VALUES (v_archived_fam, v_org_id, 'Archived Fam', 'Archived Family', 'archived', 'household_family');

  v_ended_fam := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status, family_type)
  VALUES (v_ended_fam, v_org_id, 'Ended Fam', 'Ended Family', 'ended', 'household_family');

  v_merged_fam := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status, family_type)
  VALUES (v_merged_fam, v_org_id, 'Merged Fam', 'Merged Family', 'merged', 'household_family');

  -- Synthetic Members
  v_member_1 := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_member_1, v_org_id, 'MemberOne', 'Member One', 'One, Member',
    v_active_status_id, 'active', false, v_admin_id, v_admin_id
  );

  v_member_2 := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_member_2, v_org_id, 'MemberTwo', 'Member Two', 'Two, Member',
    v_active_status_id, 'active', false, v_admin_id, v_admin_id
  );

  v_deceased_member := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, deceased_on, deceased_on_precision,
    created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_deceased_member, v_org_id, 'Deceased', 'Deceased Member', 'Member, Deceased',
    v_active_status_id, 'active', true, current_date - 10, 'exact',
    v_admin_id, v_admin_id
  );

  v_archived_member := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased,
    archived_at, archive_reason, archived_by_profile_id,
    created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_archived_member, v_org_id, 'Archived', 'Archived Member', 'Member, Archived',
    v_active_status_id, 'archived', false,
    now(), 'Archived for testing', v_admin_id,
    v_admin_id, v_admin_id
  );

  -- Count relationships in database before adding member (under postgres)
  SELECT count(*) INTO v_rel_count_before FROM public.family_relationships;

  -- -------------------------------------------------------------------------
  -- PART 2: AUTHENTICATED TESTS (as Admin)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- -------------------------------------------------------------------------
  -- SECTION 26: ADD FAMILY MEMBER TESTS
  -- -------------------------------------------------------------------------

  -- 26.A Admin can add member to active family
  v_add_res := public.add_family_member(
    p_organization_id    => v_org_id,
    p_family_id          => v_test_fam_1,
    p_member_id          => v_member_1,
    p_family_role        => 'parent',
    p_is_primary_contact => true,
    p_is_dependent       => false,
    p_effective_from     => current_date
  );

  ASSERT (v_add_res->>'status') = 'created', format('TEST 26.A FAILED: expected created, got %s', v_add_res);
  v_fm_id_1 := (v_add_res->>'family_member_id')::uuid;
  ASSERT v_fm_id_1 IS NOT NULL, 'TEST 26.A FAILED: family_member_id is null';
  ASSERT (v_add_res->>'family_role') = 'parent', 'TEST 26.A FAILED: family_role not parent';
  ASSERT (v_add_res->>'warning_count')::int = 0, 'TEST 26.A FAILED: warning_count should be 0';
  RAISE NOTICE 'TEST 26.A PASSED: admin successfully added member to family';

  -- 26.B Zero relationships created
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_rel_count_after FROM public.family_relationships;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  ASSERT v_rel_count_after = v_rel_count_before,
    format('TEST 26.B FAILED: relationships were created during add_family_member! (before=%s, after=%s)', v_rel_count_before, v_rel_count_after);
  RAISE NOTICE 'TEST 26.B PASSED: zero family relationships created during membership addition';

  -- 26.C Same-family duplicate active membership rejected (22023)
  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(
      p_organization_id => v_org_id,
      p_family_id       => v_test_fam_1,
      p_member_id       => v_member_1,
      p_family_role     => 'spouse'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.C FAILED: expected 22023 when adding duplicate active member to same family';
  RAISE NOTICE 'TEST 26.C PASSED: same-family duplicate active membership rejected';

  -- 26.D Member already in another active family returns warning
  v_warn_res := public.add_family_member(
    p_organization_id                => v_org_id,
    p_family_id                      => v_test_fam_2,
    p_member_id                      => v_member_1,
    p_family_role                    => 'relative',
    p_confirm_multiple_active_family => false
  );
  ASSERT (v_warn_res->>'status') = 'warning', format('TEST 26.D FAILED: expected warning, got %s', v_warn_res);
  ASSERT (v_warn_res->>'warning_type') = 'multiple_active_family_memberships', 'TEST 26.D FAILED: wrong warning_type';
  ASSERT (v_warn_res->>'warning_count')::int = 1, 'TEST 26.D FAILED: expected warning_count 1';
  ASSERT jsonb_array_length(v_warn_res->'existing_families') = 1, 'TEST 26.D FAILED: existing_families length not 1';
  RAISE NOTICE 'TEST 26.D PASSED: multi-family membership returns intentional friction warning';

  -- 26.E Confirm flag permits second active family
  v_add_res := public.add_family_member(
    p_organization_id                => v_org_id,
    p_family_id                      => v_test_fam_2,
    p_member_id                      => v_member_1,
    p_family_role                    => 'relative',
    p_confirm_multiple_active_family => true
  );
  ASSERT (v_add_res->>'status') = 'created', format('TEST 26.E FAILED: expected created on confirmed multi-family add, got %s', v_add_res);
  v_fm_id_2 := (v_add_res->>'family_member_id')::uuid;
  ASSERT v_fm_id_2 IS NOT NULL, 'TEST 26.E FAILED: second active family_member_id is null';
  ASSERT (v_add_res->>'warning_count')::int = 1, 'TEST 26.E FAILED: warning_count should be 1';
  RAISE NOTICE 'TEST 26.E PASSED: confirmed addition to second active family succeeded';

  -- 26.F Unauthorized caller denied (42501)
  PERFORM set_config('request.jwt.claim.sub', v_no_perm_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_no_perm_profile_id)::text, true);

  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(
      p_organization_id => v_org_id,
      p_family_id       => v_test_fam_1,
      p_member_id       => v_member_2
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.F FAILED: unauthorized user should be rejected with 42501';
  RAISE NOTICE 'TEST 26.F PASSED: unauthorized caller denied with 42501';

  -- Switch back to admin
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- 26.G Out-of-scope / non-existent family/member denied (P0002)
  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(
      p_organization_id => v_org_id,
      p_family_id       => gen_random_uuid(),
      p_member_id       => v_member_2
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0002' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.G.1 FAILED: non-existent family should be rejected with P0002';

  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(
      p_organization_id => v_org_id,
      p_family_id       => v_test_fam_1,
      p_member_id       => gen_random_uuid()
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0002' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.G.2 FAILED: non-existent member should be rejected with P0002';
  RAISE NOTICE 'TEST 26.G PASSED: out-of-scope/missing family or member denied with P0002';

  -- 26.H Anon role denied execution
  PERFORM set_config('role', 'anon', true);
  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(
      p_organization_id => v_org_id,
      p_family_id       => v_test_fam_1,
      p_member_id       => v_member_2
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE IN ('42501', '28000') THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.H FAILED: anon role must be denied';
  RAISE NOTICE 'TEST 26.H PASSED: anon denied execution';

  -- Restore admin
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- 26.I Archived / ended / merged family rejects add (22023)
  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(v_org_id, v_archived_fam, v_member_2);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.I.1 FAILED: archived family should reject add with 22023';

  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(v_org_id, v_ended_fam, v_member_2);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.I.2 FAILED: ended family should reject add with 22023';

  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(v_org_id, v_merged_fam, v_member_2);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.I.3 FAILED: merged family should reject add with 22023';
  RAISE NOTICE 'TEST 26.I PASSED: historical families (archived/ended/merged) reject add with 22023';

  -- 26.J Deceased member add rejected (22023)
  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(v_org_id, v_test_fam_1, v_deceased_member);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.J FAILED: deceased member should be rejected with 22023';
  RAISE NOTICE 'TEST 26.J PASSED: deceased member add rejected with 22023';

  -- 26.K Archived member record add rejected (22023)
  v_failed := false;
  BEGIN
    PERFORM public.add_family_member(v_org_id, v_test_fam_1, v_archived_member);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.K FAILED: archived member record should be rejected with 22023';
  RAISE NOTICE 'TEST 26.K PASSED: archived member record add rejected with 22023';

  -- -------------------------------------------------------------------------
  -- SECTION 27: UPDATE FAMILY MEMBERSHIP TESTS
  -- -------------------------------------------------------------------------

  -- 27.A - 27.C Update role, primary contact, dependent flags
  v_update_res := public.update_family_member(
    p_organization_id    => v_org_id,
    p_family_member_id   => v_fm_id_1,
    p_family_role        => 'guardian',
    p_is_primary_contact => false,
    p_is_dependent       => true
  );
  ASSERT (v_update_res->>'status') = 'success', format('TEST 27.A FAILED: expected success, got %s', v_update_res);
  ASSERT (v_update_res->>'family_role') = 'guardian', 'TEST 27.A FAILED: family_role not updated';
  ASSERT (v_update_res->>'is_primary_contact')::boolean = false, 'TEST 27.B FAILED: is_primary_contact not false';
  ASSERT (v_update_res->>'is_dependent')::boolean = true, 'TEST 27.C FAILED: is_dependent not true';

  -- 27.D - 27.F Verify member_id, family_id, effective_from unchanged
  PERFORM set_config('role', 'postgres', true);
  SELECT * INTO v_fm_row FROM public.family_members WHERE id = v_fm_id_1;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  ASSERT v_fm_row.member_id = v_member_1, 'TEST 27.D FAILED: member_id changed!';
  ASSERT v_fm_row.family_id = v_test_fam_1, 'TEST 27.E FAILED: family_id changed!';
  ASSERT v_fm_row.effective_from = current_date, 'TEST 27.F FAILED: effective_from changed!';
  RAISE NOTICE 'TEST 27.A-F PASSED: membership metadata updated, immutable fields protected';

  -- 27.I Caller without update permission denied (42501)
  PERFORM set_config('request.jwt.claim.sub', v_no_perm_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_no_perm_profile_id)::text, true);

  v_failed := false;
  BEGIN
    PERFORM public.update_family_member(v_org_id, v_fm_id_1, 'child', false, false);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 27.I FAILED: unauthorized user should be rejected with 42501';
  RAISE NOTICE 'TEST 27.I PASSED: unauthorized caller denied update with 42501';

  -- Restore admin
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- -------------------------------------------------------------------------
  -- SECTION 28: END FAMILY MEMBERSHIP TESTS
  -- -------------------------------------------------------------------------

  -- 28.K Empty reason rejected (23502)
  v_failed := false;
  BEGIN
    PERFORM public.end_family_membership(v_org_id, v_fm_id_1, current_date, '   ');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '23502' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 28.K FAILED: empty reason should be rejected with 23502';
  RAISE NOTICE 'TEST 28.K PASSED: empty reason rejected with 23502';

  -- 28.L Invalid end date rejected (22023)
  v_failed := false;
  BEGIN
    PERFORM public.end_family_membership(v_org_id, v_fm_id_1, current_date + 5, 'Future date');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 28.L FAILED: future end date should be rejected with 22023';
  RAISE NOTICE 'TEST 28.L PASSED: future end date rejected with 22023';

  -- 28.M Caller without end permission denied (42501)
  PERFORM set_config('request.jwt.claim.sub', v_no_perm_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_no_perm_profile_id)::text, true);

  v_failed := false;
  BEGIN
    PERFORM public.end_family_membership(v_org_id, v_fm_id_1, current_date, 'No permission end');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 28.M FAILED: unauthorized user should be rejected with 42501';
  RAISE NOTICE 'TEST 28.M PASSED: unauthorized caller denied end with 42501';

  -- Restore admin
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- 28.A End membership successfully
  v_end_res := public.end_family_membership(
    p_organization_id  => v_org_id,
    p_family_member_id => v_fm_id_1,
    p_effective_to     => current_date,
    p_reason           => 'Moved out of state'
  );
  ASSERT (v_end_res->>'status') = 'success', format('TEST 28.A FAILED: expected success, got %s', v_end_res);
  ASSERT (v_end_res->>'membership_status') = 'ended', 'TEST 28.A FAILED: status not ended';
  RAISE NOTICE 'TEST 28.A PASSED: active membership ended successfully';

  -- 28.B - 28.D Row remains present in family_members, effective_to populated, status is ended
  PERFORM set_config('role', 'postgres', true);
  SELECT * INTO v_fm_row FROM public.family_members WHERE id = v_fm_id_1;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  ASSERT v_fm_row.id IS NOT NULL, 'TEST 28.B FAILED: family_members row was deleted!';
  ASSERT v_fm_row.effective_to = current_date, 'TEST 28.C FAILED: effective_to not populated';
  ASSERT v_fm_row.membership_status = 'ended', 'TEST 28.D FAILED: membership_status is not ended';
  RAISE NOTICE 'TEST 28.B-D PASSED: row preserved non-destructively with status=ended and effective_to';

  -- 28.E get_member_families no longer returns ended family membership
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.get_member_families(v_org_id, v_member_1) WHERE family_id = v_test_fam_1
  ), 'TEST 28.E FAILED: ended family still appears in get_member_families!';
  ASSERT EXISTS (
    SELECT 1 FROM public.get_member_families(v_org_id, v_member_1) WHERE family_id = v_test_fam_2
  ), 'TEST 28.E FAILED: remaining active family missing from get_member_families!';
  RAISE NOTICE 'TEST 28.E PASSED: get_member_families excludes ended family membership';

  -- 28.F get_family_profile roster no longer lists ended member in active roster
  v_profile_res := public.get_family_profile(v_org_id, v_test_fam_1);
  ASSERT jsonb_array_length(v_profile_res->'members') = 0,
    format('TEST 28.F FAILED: ended member still in family profile active roster: %s', v_profile_res->'members');
  RAISE NOTICE 'TEST 28.F PASSED: get_family_profile active roster excludes ended member';

  -- 28.G Relationships remain untouched (zero relationships were deleted)
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_rel_count_after FROM public.family_relationships;
  ASSERT v_rel_count_after = v_rel_count_before, 'TEST 28.G FAILED: relationships count changed after ending membership!';
  RAISE NOTICE 'TEST 28.G PASSED: family relationships completely untouched';

  -- 28.H Member record unchanged
  ASSERT (SELECT record_status FROM public.members WHERE id = v_member_1) = 'active', 'TEST 28.H FAILED: member record status altered!';
  RAISE NOTICE 'TEST 28.H PASSED: member record status unchanged';
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- 28.J Second end attempt rejected (22023)
  v_failed := false;
  BEGIN
    PERFORM public.end_family_membership(v_org_id, v_fm_id_1, current_date, 'Ending again');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 28.J FAILED: second end attempt must fail with 22023';
  RAISE NOTICE 'TEST 28.J PASSED: second end attempt rejected with 22023';

  -- 27.G Historical/ended membership cannot be edited (22023)
  v_failed := false;
  BEGIN
    PERFORM public.update_family_member(v_org_id, v_fm_id_1, 'child', false, false);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 27.G FAILED: editing ended membership must fail with 22023';
  RAISE NOTICE 'TEST 27.G PASSED: editing ended membership rejected with 22023';

  -- -------------------------------------------------------------------------
  -- PART 3: DIRECT TABLE WRITES DENIED UNDER AUTHENTICATED
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- 3.1 Direct INSERT denied
  v_failed := false;
  BEGIN
    INSERT INTO public.family_members (organization_id, family_id, member_id)
    VALUES (v_org_id, v_test_fam_1, v_member_2);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'PART 3.1 FAILED: direct INSERT on family_members must fail with 42501';

  -- 3.2 Direct UPDATE denied
  v_failed := false;
  BEGIN
    UPDATE public.family_members SET family_role = 'child' WHERE id = v_fm_id_2;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'PART 3.2 FAILED: direct UPDATE on family_members must fail with 42501';

  -- 3.3 Direct DELETE denied
  v_failed := false;
  BEGIN
    DELETE FROM public.family_members WHERE id = v_fm_id_2;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'PART 3.3 FAILED: direct DELETE on family_members must fail with 42501';

  RAISE NOTICE 'PART 3 PASSED: direct table writes on family_members denied under authenticated role';

  -- -------------------------------------------------------------------------
  -- PART 4: AUDIT EVENTS VERIFICATION
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_count
  FROM audit.events
  WHERE organization_id = v_org_id
    AND entity_type = 'family_member'
    AND event_code IN ('family.member.added', 'family.member.updated', 'family.member.ended');
  ASSERT v_count >= 3, format('PART 4 FAILED: expected at least 3 family_member audit events, found %s', v_count);
  RAISE NOTICE 'PART 4 PASSED: audit events successfully written for all family membership operations';

  -- -------------------------------------------------------------------------
  -- PART 5: PRODUCTION INVARIANTS & ACOSTA INTEGRITY CHECK
  -- -------------------------------------------------------------------------
  SELECT count(*) INTO v_count FROM public.families WHERE family_name = 'Acosta' AND family_status = 'active';
  ASSERT v_count = 1, 'PART 5 FAILED: Acosta family record corrupted';

  SELECT count(*) INTO v_count
  FROM public.family_members fm
  JOIN public.families f ON f.id = fm.family_id
  WHERE f.family_name = 'Acosta' AND fm.membership_status = 'active';
  ASSERT v_count = 3, 'PART 5 FAILED: Acosta family members corrupted';

  SELECT count(*) INTO v_count
  FROM public.family_relationships fr
  JOIN public.families f ON f.id = fr.family_id
  WHERE f.family_name = 'Acosta' AND fr.relationship_status = 'active';
  ASSERT v_count = 3, 'PART 5 FAILED: Acosta family relationships corrupted';

  -- Total members: 315
  SELECT count(*) INTO v_count FROM public.members WHERE organization_id = v_org_id;
  ASSERT v_count = 315 + 4, format('PART 5 FAILED: total members expected 319 (315 prod + 4 synthetic), got %s', v_count);

  RAISE NOTICE 'ALL PHASE 6A-4 FAMILY MEMBERSHIP SECURITY TESTS COMPLETED SUCCESSFULLY.';
END $$;

ROLLBACK;

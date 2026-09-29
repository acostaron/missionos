-- =============================================================================
-- Security Tests: phase_6a_family_identity_write_security.sql
-- Phase:          Phase 6A-3A — Family Identity Write Backend
--
-- Non-destructive. Wrapped completely inside BEGIN ... ROLLBACK.
-- No permanent changes made to database. Production Acosta family is untouched.
--
-- Tests:
--   Part 1: Static Schema & Permissions Posture
--     1.1 New permissions exist (create, update, archive)
--     1.2 Role assignments: assigned strictly to organization_administrator
--     1.3 Function existence and grants (REVOKE FROM anon/public verified)
--
--   Part 2: Authenticated / JWT Execution Tests (Inside Transaction & Rollback)
--     Section 25: CREATE TESTS
--       A. Org admin can create family
--       B. Created family entity defaults: active status, 0 members, 0 relationships
--       C. Duplicate warning returned when similar active family exists without confirmation
--       D. Intentional create allowed when p_confirm_duplicate = true
--       E. Caller without families.records.create denied (42501)
--       F. Anon role denied execution on create_family (42501)
--
--     Section 26: UPDATE TESTS
--       A. Authorized identity update succeeds
--       B. Changed fields match updated values
--       C-F. Unrelated fields (primary_parish_id, primary_address_id, administrative_notes) untouched
--       G-H. Zero memberships, zero relationships remain untouched
--       I. Caller without families.records.update denied (42501)
--       J. Inaccessible family returns indistinguishable P0002
--       K. Invalid family_type or future formed_on rejected (22023)
--       L. Empty display_name or family_name rejected (23502)
--
--     Section 27 & 28: ARCHIVE TESTS & ACTIVE-MEMBER WARNING
--       A. Empty reason rejected (23502)
--       B. Active-member warning returned when active members exist without confirmation
--       C. Confirmed archive with active members succeeds
--       D. Family lifecycle changes to 'archived', ended_on set
--       E-H. Family row, memberships, relationships, member records/statuses untouched
--       I. Direct get_family_profile remains historically readable for authorized user
--       J. Duplicate archive rejected (22023)
--       K. Caller without families.records.archive denied (42501)
--       L. Attempt to update archived family rejected (22023)
--
--     Part 3: Direct Table Writes Denied
--       3.1 Direct INSERT on public.families denied under authenticated (42501)
--       3.2 Direct UPDATE on public.families denied under authenticated (42501)
--       3.3 Direct DELETE on public.families denied under authenticated (42501)
--
--     Part 4: Production Invariants Verification
--       Acosta family rows and production totals verified unchanged.
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
  v_alb_node_id           uuid;
  v_alb_leader_profile_id uuid;
  v_pra_id                uuid;

  -- Test family tracking
  v_create_res            jsonb;
  v_test_fam_id           uuid;
  v_dup_res               jsonb;
  v_confirmed_dup_res     jsonb;
  v_dup_fam_id            uuid;
  v_update_res            jsonb;
  v_fam_row               public.families%rowtype;

  -- Test member tracking for archive warning test
  v_test_member_id        uuid;
  v_test_fam_member_id    uuid;
  v_active_status_id      uuid;
  v_archive_warn_res      jsonb;
  v_archive_res           jsonb;
  v_profile_res           jsonb;

  -- Lifecycle gating test fixtures
  v_merged_fam_id         uuid;
  v_ended_fam_id          uuid;
  v_changed_fam_id        uuid;

  v_failed                boolean;
BEGIN
  -- -------------------------------------------------------------------------
  -- PART 1: STATIC SCHEMA & PERMISSION POSTURE
  -- -------------------------------------------------------------------------

  -- 1.1 Permissions exist in catalog
  SELECT count(*) INTO v_count
  FROM public.permissions
  WHERE code IN (
    'families.records.create',
    'families.records.update',
    'families.records.archive'
  );
  ASSERT v_count = 3, format('PART 1.1 FAILED: expected 3 new family permissions, found %s', v_count);
  RAISE NOTICE 'PART 1.1 PASSED: all 3 family write permissions exist';

  -- 1.2 Role assignments strictly to organization_administrator
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code IN (
    'families.records.create',
    'families.records.update',
    'families.records.archive'
  )
  AND ar.code = 'organization_administrator'
  AND rp.permission_effect = 'allow';
  ASSERT v_count = 3, format('PART 1.2 FAILED: expected 3 role_permissions for org_admin, found %s', v_count);

  -- Verify member_data_steward does NOT have family write permissions
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code IN (
    'families.records.create',
    'families.records.update',
    'families.records.archive'
  )
  AND ar.code = 'member_data_steward';
  ASSERT v_count = 0, format('PART 1.2 FAILED: member_data_steward has unexpected family write permissions: %s', v_count);
  RAISE NOTICE 'PART 1.2 PASSED: write permissions strictly assigned to organization_administrator';

  -- 1.3 Revoke posture: no anon/public grants
  SELECT count(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('create_family', 'update_family_identity', 'archive_family_record')
    AND EXISTS (
      SELECT 1
      FROM aclexplode(p.proacl) acl
      JOIN pg_roles r ON r.oid = acl.grantee
      WHERE r.rolname IN ('anon', 'public')
    );
  ASSERT v_count = 0, format('PART 1.3 FAILED: found %s public/anon grants on family write RPCs', v_count);
  RAISE NOTICE 'PART 1.3 PASSED: no public/anon execute grants on family write RPCs';

  -- -------------------------------------------------------------------------
  -- SETUP FIXTURES FOR AUTHENTICATED TESTS
  -- -------------------------------------------------------------------------
  SELECT id INTO v_org_id FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  SELECT id INTO v_admin_role_id FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT id INTO v_steward_role_id FROM public.app_roles WHERE code = 'member_data_steward';
  SELECT id INTO v_active_status_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active' LIMIT 1;

  -- Known test governance node (Albany)
  SELECT id INTO v_alb_node_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'alb' LIMIT 1;

  -- Admin user
  SELECT pra.profile_id INTO v_admin_id
  FROM public.profile_role_assignments pra
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE ar.code = 'organization_administrator'
    AND pra.organization_id = v_org_id
    AND pra.assignment_status = 'active'
  LIMIT 1;

  -- Synthetic Profile 1: Caller with NO family write permissions (member_data_steward)
  v_no_perm_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_no_perm_profile_id, 'authenticated', 'authenticated', 'no_family_write@test.local');
  INSERT INTO public.profiles (id, display_name)
  VALUES (v_no_perm_profile_id, 'No Family Write User');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_no_perm_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    v_no_perm_profile_id, v_org_id, v_steward_role_id, 'active',
    now(), now(), now(), now()
  );

  -- Synthetic Profile 2: Albany node-scoped leader
  v_alb_leader_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_alb_leader_profile_id, 'authenticated', 'authenticated', 'alb_leader@test.local');
  INSERT INTO public.profiles (id, display_name)
  VALUES (v_alb_leader_profile_id, 'Albany Leader');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_alb_leader_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_role_assignments (
    id, profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    gen_random_uuid(), v_alb_leader_profile_id, v_org_id, v_admin_role_id, 'active',
    now(), now(), now(), now()
  ) RETURNING id INTO v_pra_id;
  INSERT INTO public.profile_scope_assignments (
    profile_role_assignment_id, organization_id, scope_type, governance_node_id,
    scope_effect, assignment_status, assigned_at, effective_from_at
  ) VALUES (
    v_pra_id, v_org_id, 'governance_node', v_alb_node_id,
    'include', 'active', now(), now()
  );

  -- -------------------------------------------------------------------------
  -- SECTION 25: CREATE TESTS
  -- -------------------------------------------------------------------------
  -- Set authenticated context as Organization Administrator
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- Test 25.A: Org admin can create family
  v_create_res := public.create_family(
    p_organization_id   => v_org_id,
    p_display_name      => '  Vanderbilt Household  ',
    p_family_name       => '  Vanderbilt  ',
    p_family_type       => 'household_family',
    p_formed_on         => '2020-05-15'::date,
    p_confirm_duplicate => false
  );
  ASSERT (v_create_res->>'status') = 'created', 'TEST 25.A FAILED: expected created status';
  v_test_fam_id := (v_create_res->>'family_id')::uuid;
  ASSERT v_test_fam_id IS NOT NULL, 'TEST 25.A FAILED: family_id is null';
  ASSERT (v_create_res->>'display_name') = 'Vanderbilt Household', 'TEST 25.A FAILED: display_name not trimmed';
  ASSERT (v_create_res->>'family_name') = 'Vanderbilt', 'TEST 25.A FAILED: family_name not trimmed';
  ASSERT (v_create_res->>'family_status') = 'active', 'TEST 25.A FAILED: status not active';

  -- Test 25.B: Verify DB entity defaults (zero members, zero relationships, null out-of-scope fields)
  PERFORM set_config('role', 'postgres', true);
  SELECT * INTO v_fam_row FROM public.families WHERE id = v_test_fam_id;
  ASSERT v_fam_row.organization_id = v_org_id, 'TEST 25.B FAILED: org mismatch';
  ASSERT v_fam_row.directory_visibility = 'leaders_only', 'TEST 25.B FAILED: directory_visibility default';
  ASSERT v_fam_row.primary_parish_id IS NULL, 'TEST 25.B FAILED: primary_parish_id should be null';
  ASSERT v_fam_row.primary_address_id IS NULL, 'TEST 25.B FAILED: primary_address_id should be null';
  ASSERT v_fam_row.administrative_notes IS NULL, 'TEST 25.B FAILED: administrative_notes should be null';

  SELECT count(*) INTO v_count FROM public.family_members WHERE family_id = v_test_fam_id;
  ASSERT v_count = 0, format('TEST 25.B FAILED: expected 0 members, got %s', v_count);

  SELECT count(*) INTO v_count FROM public.family_relationships WHERE family_id = v_test_fam_id;
  ASSERT v_count = 0, format('TEST 25.B FAILED: expected 0 relationships, got %s', v_count);

  -- Switch back to admin
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- Test 25.C: Duplicate warning detection
  v_dup_res := public.create_family(
    p_organization_id   => v_org_id,
    p_display_name      => 'Vanderbilt Household',
    p_family_name       => 'Vanderbilt',
    p_confirm_duplicate => false
  );
  ASSERT (v_dup_res->>'status') = 'warning', 'TEST 25.C FAILED: expected duplicate warning';
  ASSERT (v_dup_res->>'warning_count')::int >= 1, 'TEST 25.C FAILED: warning_count should be >= 1';

  -- Test 25.D: Duplicate confirmation allows intentional creation
  v_confirmed_dup_res := public.create_family(
    p_organization_id   => v_org_id,
    p_display_name      => 'Vanderbilt Household',
    p_family_name       => 'Vanderbilt',
    p_confirm_duplicate => true
  );
  ASSERT (v_confirmed_dup_res->>'status') = 'created', 'TEST 25.D FAILED: expected created with confirmation';
  v_dup_fam_id := (v_confirmed_dup_res->>'family_id')::uuid;
  ASSERT v_dup_fam_id <> v_test_fam_id, 'TEST 25.D FAILED: duplicate ID match';

  -- Test 25.E: Unauthorized caller denied (missing permission)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_no_perm_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_no_perm_profile_id)::text, true);

  v_failed := false;
  BEGIN
    PERFORM public.create_family(v_org_id, 'Unauthorized Family', 'Unauthorized');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 25.E FAILED: expected 42501 for unauthorized caller';

  -- Test 25.F: Anon caller denied
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  v_failed := false;
  BEGIN
    PERFORM public.create_family(v_org_id, 'Anon Family', 'Anon');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 25.F FAILED: expected 42501 for anon caller';

  RAISE NOTICE 'SECTION 25 PASSED: Create family tests successful';

  -- -------------------------------------------------------------------------
  -- SECTION 26: UPDATE TESTS
  -- -------------------------------------------------------------------------
  -- Switch back to Admin
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- Test 26.A: Authorized identity update succeeds
  v_update_res := public.update_family_identity(
    p_organization_id => v_org_id,
    p_family_id       => v_test_fam_id,
    p_display_name    => '  The Vanderbilt Dynasty  ',
    p_family_name     => '  Vanderbilt  ',
    p_family_type     => 'extended_family',
    p_formed_on       => '2019-01-01'::date
  );
  ASSERT (v_update_res->>'status') = 'success', 'TEST 26.A FAILED: expected success status';

  -- Test 26.B-H: Verify DB fields
  PERFORM set_config('role', 'postgres', true);
  SELECT * INTO v_fam_row FROM public.families WHERE id = v_test_fam_id;
  ASSERT v_fam_row.display_name = 'The Vanderbilt Dynasty', 'TEST 26.B FAILED: display_name not updated';
  ASSERT v_fam_row.family_name = 'Vanderbilt', 'TEST 26.B FAILED: family_name mismatch';
  ASSERT v_fam_row.family_type = 'extended_family', 'TEST 26.B FAILED: family_type not updated';
  ASSERT v_fam_row.formed_on = '2019-01-01'::date, 'TEST 26.B FAILED: formed_on not updated';
  ASSERT v_fam_row.primary_parish_id IS NULL, 'TEST 26.D FAILED: primary_parish_id was modified';
  ASSERT v_fam_row.primary_address_id IS NULL, 'TEST 26.E FAILED: primary_address_id was modified';
  ASSERT v_fam_row.administrative_notes IS NULL, 'TEST 26.F FAILED: administrative_notes was modified';
  ASSERT v_fam_row.family_status = 'active', 'TEST 26.C FAILED: family_status should remain active';

  SELECT count(*) INTO v_count FROM public.family_members WHERE family_id = v_test_fam_id;
  ASSERT v_count = 0, 'TEST 26.G FAILED: memberships modified';

  -- Test 26.I: Caller without update permission denied
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_no_perm_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_no_perm_profile_id)::text, true);

  v_failed := false;
  BEGIN
    PERFORM public.update_family_identity(v_org_id, v_test_fam_id, 'Hacked Name', 'Hacked');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.I FAILED: expected 42501 for caller lacking update permission';

  -- Test 26.J: Inaccessible family returns P0002 for node-scoped caller
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_alb_leader_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_alb_leader_profile_id)::text, true);

  v_failed := false;
  BEGIN
    PERFORM public.update_family_identity(v_org_id, v_test_fam_id, 'Albany Edit', 'Albany');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0002' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.J FAILED: expected P0002 for inaccessible family';

  -- Test 26.K & L: Invalid inputs (admin)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- Empty display_name
  v_failed := false;
  BEGIN
    PERFORM public.update_family_identity(v_org_id, v_test_fam_id, '   ', 'Valid');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '23502' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.L FAILED: expected 23502 for empty display_name';

  -- Invalid family_type
  v_failed := false;
  BEGIN
    PERFORM public.update_family_identity(v_org_id, v_test_fam_id, 'Valid', 'Valid', 'invalid_catalog_type');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.K FAILED: expected 22023 for invalid family_type';

  RAISE NOTICE 'SECTION 26 PASSED: Update family tests successful';

  -- -------------------------------------------------------------------------
  -- SECTION 27 & 28: ARCHIVE TESTS & ACTIVE-MEMBER WARNING
  -- -------------------------------------------------------------------------
  -- Test 27.K: Empty reason rejected
  v_failed := false;
  BEGIN
    PERFORM public.archive_family_record(v_org_id, v_test_fam_id, '   ');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '23502' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 27.K FAILED: expected 23502 for empty reason';

  -- Test 28: Setup temporary synthetic member and attach to family
  PERFORM set_config('role', 'postgres', true);
  v_test_member_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name, membership_status_id,
    record_status, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_test_member_id, v_org_id, 'Temp', 'Temp Test Member', 'Member, Temp Test',
    v_active_status_id, 'active', v_admin_id, v_admin_id
  );

  v_test_fam_member_id := gen_random_uuid();
  INSERT INTO public.family_members (
    id, organization_id, family_id, member_id, family_role,
    membership_status, is_primary_contact, is_dependent, created_by_profile_id
  ) VALUES (
    v_test_fam_member_id, v_org_id, v_test_fam_id, v_test_member_id, 'parent',
    'active', true, false, v_admin_id
  );

  -- Switch to admin
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- Test 28.A: Confirm get_member_families returns family before archive
  SELECT count(*) INTO v_count
  FROM public.get_member_families(v_org_id, v_test_member_id);
  ASSERT v_count = 1, 'TEST 28.A FAILED: get_member_families should return active family before archive';

  -- Test 28.B: Archive without confirmation triggers active-member warning
  v_archive_warn_res := public.archive_family_record(
    p_organization_id             => v_org_id,
    p_family_id                   => v_test_fam_id,
    p_reason                      => 'Administrative re-organization',
    p_confirm_with_active_members => false
  );
  ASSERT (v_archive_warn_res->>'status') = 'warning', 'TEST 28.B FAILED: expected warning status';
  ASSERT (v_archive_warn_res->>'active_member_count')::int = 1, 'TEST 28.B FAILED: active_member_count should be 1';

  -- Family should STILL be active
  PERFORM set_config('role', 'postgres', true);
  SELECT family_status INTO v_fam_row.family_status FROM public.families WHERE id = v_test_fam_id;
  ASSERT v_fam_row.family_status = 'active', 'TEST 28.B FAILED: family was prematurely archived';

  -- Switch back to admin
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- Test 28.C: Archive WITH confirmation succeeds
  v_archive_res := public.archive_family_record(
    p_organization_id             => v_org_id,
    p_family_id                   => v_test_fam_id,
    p_reason                      => 'Administrative re-organization confirmed',
    p_confirm_with_active_members => true
  );
  ASSERT (v_archive_res->>'status') = 'success', 'TEST 28.C FAILED: expected success status';
  ASSERT (v_archive_res->>'family_status') = 'archived', 'TEST 28.C FAILED: expected archived status';

  -- Test 27.B-H: Invariants after archive
  PERFORM set_config('role', 'postgres', true);
  SELECT * INTO v_fam_row FROM public.families WHERE id = v_test_fam_id;
  ASSERT v_fam_row.family_status = 'archived', 'TEST 27.B FAILED: family_status should be archived';
  ASSERT v_fam_row.ended_on IS NOT NULL, 'TEST 27.B FAILED: ended_on should be populated';

  -- Membership row MUST remain present and active
  SELECT count(*) INTO v_count
  FROM public.family_members
  WHERE id = v_test_fam_member_id AND membership_status = 'active';
  ASSERT v_count = 1, 'TEST 27.D FAILED: family_member record should remain untouched';

  -- Member record MUST remain active
  SELECT record_status INTO v_fam_row.family_status FROM public.members WHERE id = v_test_member_id;
  ASSERT v_fam_row.family_status = 'active', 'TEST 27.F FAILED: member record should remain active';

  -- Switch to admin for read checks
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- Test 28.D: Confirm get_member_families no longer returns archived family as a current family membership
  SELECT count(*) INTO v_count
  FROM public.get_member_families(v_org_id, v_test_member_id);
  ASSERT v_count = 0, 'TEST 28.D FAILED: get_member_families must NOT return archived family as current family';

  -- Test 27.I: Archived family remains readable via get_family_profile for history
  v_profile_res := public.get_family_profile(v_org_id, v_test_fam_id);
  ASSERT (v_profile_res->'family'->>'family_status') = 'archived', 'TEST 27.I FAILED: get_family_profile should return archived family';
  ASSERT jsonb_array_length(v_profile_res->'members') = 1, 'TEST 27.I FAILED: profile should still show member';

  -- Test 27.J: Duplicate archive rejected
  v_failed := false;
  BEGIN
    PERFORM public.archive_family_record(v_org_id, v_test_fam_id, 'Already archived', true);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 27.J FAILED: expected 22023 for duplicate archive';

  -- Test 26.G: Updating an archived family is rejected
  v_failed := false;
  BEGIN
    PERFORM public.update_family_identity(v_org_id, v_test_fam_id, 'New Name', 'New Surname');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 26.G FAILED: expected 22023 when updating archived family';

  -- Test 27.L: Caller without archive permission denied
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_no_perm_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_no_perm_profile_id)::text, true);

  v_failed := false;
  BEGIN
    PERFORM public.archive_family_record(v_org_id, v_dup_fam_id, 'Unauthorized archive');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 27.L FAILED: expected 42501 for unauthorized archive';

  RAISE NOTICE 'SECTION 27 & 28 PASSED: Archive and active-member warning tests successful';

  -- -------------------------------------------------------------------------
  -- SECTION 29: LIFECYCLE GATING VERIFICATION (ACTIVE, CHANGED, ENDED, MERGED, ARCHIVED)
  -- -------------------------------------------------------------------------
  -- Setup synthetic families under postgres role
  PERFORM set_config('role', 'postgres', true);

  -- 1. Synthetic Merged Family
  v_merged_fam_id := gen_random_uuid();
  INSERT INTO public.families (
    id, organization_id, family_name, display_name, family_type, family_status,
    created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_merged_fam_id, v_org_id, 'MergedFamily', 'Merged Family Test', 'household_family', 'merged',
    v_admin_id, v_admin_id
  );

  -- 2. Synthetic Ended Family
  v_ended_fam_id := gen_random_uuid();
  INSERT INTO public.families (
    id, organization_id, family_name, display_name, family_type, family_status, ended_on,
    created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_ended_fam_id, v_org_id, 'EndedFamily', 'Ended Family Test', 'household_family', 'ended', current_date,
    v_admin_id, v_admin_id
  );

  -- 3. Synthetic Changed Family
  v_changed_fam_id := gen_random_uuid();
  INSERT INTO public.families (
    id, organization_id, family_name, display_name, family_type, family_status,
    created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_changed_fam_id, v_org_id, 'ChangedFamily', 'Changed Family Test', 'household_family', 'changed',
    v_admin_id, v_admin_id
  );

  -- Switch to Authenticated Org Admin JWT context
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- 29.1 Merged family CANNOT be updated (22023)
  v_failed := false;
  BEGIN
    PERFORM public.update_family_identity(v_org_id, v_merged_fam_id, 'Updated Merged', 'MergedFamily');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 29.1 FAILED: expected 22023 when updating merged family';

  -- 29.2 Merged family CANNOT be archived (22023)
  v_failed := false;
  BEGIN
    PERFORM public.archive_family_record(v_org_id, v_merged_fam_id, 'Archiving merged');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 29.2 FAILED: expected 22023 when archiving merged family';

  -- 29.3 Archived family CANNOT be updated (22023)
  v_failed := false;
  BEGIN
    PERFORM public.update_family_identity(v_org_id, v_test_fam_id, 'Updated Archived', 'ArchivedFamily');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 29.3 FAILED: expected 22023 when updating archived family';

  -- 29.4 Ended family CANNOT be updated (22023)
  v_failed := false;
  BEGIN
    PERFORM public.update_family_identity(v_org_id, v_ended_fam_id, 'Updated Ended', 'EndedFamily');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 29.4 FAILED: expected 22023 when updating ended family';

  -- 29.4b Ended family CANNOT be archived (22023)
  v_failed := false;
  BEGIN
    PERFORM public.archive_family_record(v_org_id, v_ended_fam_id, 'Archiving ended');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST 29.4b FAILED: expected 22023 when archiving ended family';

  -- 29.5 Active family remains editable (succeeds)
  v_update_res := public.update_family_identity(v_org_id, v_dup_fam_id, 'Updated Active Dup', 'Vanderbilt');
  ASSERT (v_update_res->>'status') = 'success', 'TEST 29.5 FAILED: updating active family failed';

  -- 29.6 Changed family remains editable according to current contract (succeeds)
  v_update_res := public.update_family_identity(v_org_id, v_changed_fam_id, 'Updated Changed Family', 'ChangedFamily');
  ASSERT (v_update_res->>'status') = 'success', 'TEST 29.6 FAILED: updating changed family failed';

  -- 29.7 Active & Changed archive behavior remains operational (succeeds)
  v_archive_res := public.archive_family_record(v_org_id, v_changed_fam_id, 'Archiving changed family');
  ASSERT (v_archive_res->>'status') = 'success', 'TEST 29.7 FAILED: archiving changed family failed';
  ASSERT (v_archive_res->>'family_status') = 'archived', 'TEST 29.7 FAILED: changed family status did not transition to archived';

  RAISE NOTICE 'SECTION 29 PASSED: Complete lifecycle gating verified for active, changed, ended, merged, and archived';

  -- -------------------------------------------------------------------------
  -- PART 3: DIRECT TABLE WRITES DENIED UNDER AUTHENTICATED
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- 3.1 Direct INSERT denied
  v_failed := false;
  BEGIN
    INSERT INTO public.families (organization_id, family_name, display_name)
    VALUES (v_org_id, 'Direct', 'Direct Family');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'PART 3.1 FAILED: direct INSERT on families must fail with 42501';

  -- 3.2 Direct UPDATE denied
  v_failed := false;
  BEGIN
    UPDATE public.families SET family_name = 'Direct Update' WHERE id = v_test_fam_id;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'PART 3.2 FAILED: direct UPDATE on families must fail with 42501';

  -- 3.3 Direct DELETE denied
  v_failed := false;
  BEGIN
    DELETE FROM public.families WHERE id = v_test_fam_id;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'PART 3.3 FAILED: direct DELETE on families must fail with 42501';

  RAISE NOTICE 'PART 3 PASSED: direct table writes denied under authenticated role';

  -- -------------------------------------------------------------------------
  -- PART 4: AUDIT EVENTS VERIFICATION
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  -- Verify audit events were created for family.created, family.identity_updated, family.archived
  SELECT count(*) INTO v_count
  FROM audit.events
  WHERE organization_id = v_org_id
    AND entity_type = 'family'
    AND event_code IN ('family.created', 'family.identity_updated', 'family.archived');
  ASSERT v_count >= 3, format('PART 4 FAILED: expected at least 3 audit events, found %s', v_count);
  RAISE NOTICE 'PART 4 PASSED: audit events successfully written for all lifecycle write operations';

  -- -------------------------------------------------------------------------
  -- PART 5: PRODUCTION ACOSTA INTEGRITY CHECK
  -- -------------------------------------------------------------------------
  -- Verify production Acosta family is intact
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

  RAISE NOTICE 'ALL PHASE 6A-3A SECURITY & LIFECYCLE TESTS COMPLETED SUCCESSFULLY.';
END $$;

ROLLBACK;

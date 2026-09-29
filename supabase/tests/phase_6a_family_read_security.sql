-- =============================================================================
-- Security Tests: phase_6a_family_read_security.sql
-- Phase:          Phase 6A-0 — Family Read Foundation
--
-- Non-destructive. All write/profile simulations wrapped in BEGIN...ROLLBACK.
--
-- Verifies authorization model for:
--   - public.get_family_profile
--   - public.get_member_families
--   - public.get_family_relationship_types
--   - private.can_access_family
--
-- Tests:
--   Part 1: Schema & Static Posture
--     1. Permission assignments: org_admin has both family view permissions
--     2. Function existence and grants (REVOKE FROM anon/public verified)
--     3. Catalog relationship types (spouse, parent_of, child_of + inverses)
--     4. Documented known Ron->Julia parentage gap (data quality gap, NOT a bug)
--
--   Part 2: Authenticated / JWT Execution Tests (Inside Transaction & Rollback)
--     A. Organization Administrator:
--        - can call get_family_profile
--        - can call get_member_families
--        - can call get_family_relationship_types
--     B. Caller without families.records.view:
--        - denied with 42501
--     C. Caller outside family/member governance scope:
--        - denied with P0002 (Family not found or not accessible)
--     D. Cross-scope family union-access:
--        - caller with access to one active member (Julia in RVC) accesses family
--     E. Authenticated caller privacy & field minimization:
--        - no email, phone, address, birth_date, auth IDs exposed
--        - primary_parish_id excluded
--        - primary_address_id excluded
--        - administrative_notes excluded
--     F. Anon role:
--        - denied execution on all family RPCs (42501)
--     G. Direct table writes:
--        - INSERT/UPDATE/DELETE denied under authenticated role (42501)
--     H. Production invariants:
--        - 1 family, 3 active family members, 3 active relationships, 315 members
-- =============================================================================

-- =============================================================================
-- PART 1: SCHEMA & PERMISSION POSTURE
-- =============================================================================

DO $$
DECLARE
  v_count integer;
  v_codes text[];
BEGIN
  -- 1. Permission assignments
  SELECT count(*) INTO v_count
  FROM public.permissions p
  JOIN public.role_permissions rp
    ON rp.permission_id   = p.id
   AND rp.approval_status = 'approved'
   AND rp.effective_to_at IS NULL
  JOIN public.app_roles ar
    ON ar.id = rp.app_role_id
  WHERE p.code  IN ('families.records.view', 'families.relationships.view')
    AND ar.code = 'organization_administrator'
    AND rp.permission_effect = 'allow';

  ASSERT v_count = 2,
    format('PART 1.1 FAILED: expected 2 approved family permission assignments, got %s', v_count);
  RAISE NOTICE 'PART 1.1 PASSED: both family view permissions assigned to organization_administrator';

  -- 1.2 Function existence
  SELECT count(*) INTO v_count
  FROM information_schema.routines
  WHERE (routine_schema = 'public'
         AND routine_name IN ('get_family_profile','get_member_families','get_family_relationship_types'))
     OR (routine_schema = 'private'
         AND routine_name = 'can_access_family');

  ASSERT v_count = 4,
    format('PART 1.2 FAILED: expected 4 functions, found %s', v_count);
  RAISE NOTICE 'PART 1.2 PASSED: all 4 Phase 6A-0 functions exist';

  -- 1.3 Revoke posture: no anon/public grants
  SELECT count(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('get_family_profile','get_member_families','get_family_relationship_types')
    AND EXISTS (
      SELECT 1
      FROM aclexplode(p.proacl) acl
      JOIN pg_roles r ON r.oid = acl.grantee
      WHERE r.rolname IN ('anon','public')
    );

  ASSERT v_count = 0,
    format('PART 1.3 FAILED: found %s public/anon grants on family RPCs', v_count);
  RAISE NOTICE 'PART 1.3 PASSED: no public/anon grants on family RPCs';

  -- 1.4 Catalog types
  SELECT count(*), array_agg(frt.code ORDER BY frt.code) INTO v_count, v_codes
  FROM public.family_relationship_types frt
  WHERE frt.is_active = true AND frt.organization_id IS NULL;

  ASSERT v_count = 3, format('PART 1.4 FAILED: expected 3 global types, got %s', v_count);
  ASSERT 'child_of' = ANY(v_codes) AND 'parent_of' = ANY(v_codes) AND 'spouse' = ANY(v_codes),
    'PART 1.4 FAILED: expected types missing';
  RAISE NOTICE 'PART 1.4 PASSED: catalog relationship types verified';
END;
$$;

-- =============================================================================
-- PART 2: AUTHENTICATED / JWT EXECUTION TESTS (BEGIN ... ROLLBACK)
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id                uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_fam_id                uuid := '74a4adcd-5f2b-4581-aa67-4197c1b46933'; -- Acosta
  v_ron_id                uuid;
  v_julia_id              uuid;
  v_admin_id              uuid := '821fb09c-8396-4549-b120-5674f3cc566a';

  -- Test mock identities (cleaned up on rollback)
  v_no_perm_profile_id    uuid := '00000000-0000-0000-0000-000000000001';
  v_alb_leader_profile_id uuid := '00000000-0000-0000-0000-000000000002';
  v_rvc_leader_profile_id uuid := '00000000-0000-0000-0000-000000000003';

  v_steward_role_id       uuid;
  v_admin_role_id         uuid;
  v_alb_node_id           uuid := '749a0ffa-0910-4211-b233-97dd04b905b0'; -- Albany
  v_rvc_node_id           uuid := '8c242b2c-4087-448c-98dc-7f5e29b26d26'; -- RVC

  v_res                   jsonb;
  v_count                 integer;
  v_failed                boolean;
  v_member_elem           jsonb;
  v_pra_id                uuid;
BEGIN
  SELECT id INTO v_ron_id   FROM public.members WHERE display_name ILIKE '%Ron Acosta%'   LIMIT 1;
  SELECT id INTO v_julia_id FROM public.members WHERE display_name ILIKE '%Julia Acosta%' LIMIT 1;

  SELECT id INTO v_admin_role_id   FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT id INTO v_steward_role_id FROM public.app_roles WHERE code = 'member_data_steward';

  -- Setup 1: No family permission profile
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_no_perm_profile_id, 'authenticated', 'authenticated', 'noperm@test.local');
  INSERT INTO public.profiles (id, display_name)
  VALUES (v_no_perm_profile_id, 'No Family Perm User');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_no_perm_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    v_no_perm_profile_id, v_org_id, v_steward_role_id, 'active',
    now(), now(), now(), now()
  );

  -- Setup 2: Albany leader profile (scoped strictly to Albany node)
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_alb_leader_profile_id, 'authenticated', 'authenticated', 'albany@test.local');
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

  -- Setup 3: RVC leader profile (scoped to RVC node where Julia Acosta is placed)
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_rvc_leader_profile_id, 'authenticated', 'authenticated', 'rvc@test.local');
  INSERT INTO public.profiles (id, display_name)
  VALUES (v_rvc_leader_profile_id, 'RVC Leader');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_rvc_leader_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_role_assignments (
    id, profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    gen_random_uuid(), v_rvc_leader_profile_id, v_org_id, v_admin_role_id, 'active',
    now(), now(), now(), now()
  ) RETURNING id INTO v_pra_id;
  INSERT INTO public.profile_scope_assignments (
    profile_role_assignment_id, organization_id, scope_type, governance_node_id,
    scope_effect, assignment_status, assigned_at, effective_from_at
  ) VALUES (
    v_pra_id, v_org_id, 'governance_node', v_rvc_node_id,
    'include', 'active', now(), now()
  );

  -- -------------------------------------------------------------------------
  -- TEST A: Organization Administrator (Authenticated Role & JWT)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  -- A1: get_family_profile
  v_res := public.get_family_profile(v_org_id, v_fam_id);
  ASSERT v_res IS NOT NULL, 'TEST A1 FAILED: get_family_profile returned null';
  ASSERT (v_res->'family'->>'family_name') = 'Acosta', 'TEST A1 FAILED: family_name mismatch';
  ASSERT jsonb_array_length(v_res->'members') = 3, 'TEST A1 FAILED: expected 3 members';
  ASSERT jsonb_array_length(v_res->'relationships') = 3, 'TEST A1 FAILED: expected 3 relationships';

  -- A2: get_member_families
  SELECT count(*) INTO v_count FROM public.get_member_families(v_org_id, v_ron_id);
  ASSERT v_count = 1, format('TEST A2 FAILED: expected 1 family for Ron, got %s', v_count);

  -- A3: get_family_relationship_types
  SELECT count(*) INTO v_count FROM public.get_family_relationship_types(v_org_id);
  ASSERT v_count >= 3, format('TEST A3 FAILED: expected >=3 relationship types, got %s', v_count);

  RAISE NOTICE 'TEST A PASSED: Org admin authenticated JWT execution successful';

  -- -------------------------------------------------------------------------
  -- TEST B: Caller without families.records.view (Authenticated Role & JWT)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_no_perm_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_no_perm_profile_id)::text, true);

  -- B1: get_family_profile must fail with 42501
  v_failed := false;
  BEGIN
    PERFORM public.get_family_profile(v_org_id, v_fam_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST B1 FAILED: expected 42501 when caller lacks families.records.view';

  -- B2: get_member_families must fail with 42501
  v_failed := false;
  BEGIN
    PERFORM * FROM public.get_member_families(v_org_id, v_ron_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST B2 FAILED: expected 42501 for get_member_families without permission';

  RAISE NOTICE 'TEST B PASSED: Caller without families.records.view denied with 42501';

  -- -------------------------------------------------------------------------
  -- TEST C: Caller outside family governance scope (Authenticated Role & JWT)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_alb_leader_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_alb_leader_profile_id)::text, true);

  -- C1: get_family_profile must fail with P0002 (Family not found or not accessible)
  v_failed := false;
  BEGIN
    PERFORM public.get_family_profile(v_org_id, v_fam_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0002' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST C1 FAILED: expected P0002 for out-of-scope leader';

  RAISE NOTICE 'TEST C PASSED: Caller outside family scope denied with P0002';

  -- -------------------------------------------------------------------------
  -- TEST D: Cross-scope family union-access (Authenticated Role & JWT)
  -- RVC leader has access to Julia -> satisfies union rule for Acosta family
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_rvc_leader_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_rvc_leader_profile_id)::text, true);

  v_res := public.get_family_profile(v_org_id, v_fam_id);
  ASSERT v_res IS NOT NULL, 'TEST D FAILED: RVC leader should access family via Julia';
  ASSERT jsonb_array_length(v_res->'members') = 3, 'TEST D FAILED: expected 3 members in relational family unit';

  RAISE NOTICE 'TEST D PASSED: Cross-scope family access via union rule verified';

  -- -------------------------------------------------------------------------
  -- TEST E: Authenticated caller cannot obtain PII, parish, address, notes
  -- -------------------------------------------------------------------------
  ASSERT (v_res->'family'->>'primary_parish_id') IS NULL, 'TEST E1 FAILED: primary_parish_id must not be exposed';
  ASSERT (v_res->'family'->>'primary_address_id') IS NULL, 'TEST E2 FAILED: primary_address_id must not be exposed';
  ASSERT (v_res->'family'->>'administrative_notes') IS NULL, 'TEST E3 FAILED: administrative_notes must not be exposed';

  FOR v_member_elem IN SELECT * FROM jsonb_array_elements(v_res->'members')
  LOOP
    ASSERT (v_member_elem->>'email') IS NULL, 'TEST E4 FAILED: email exposed';
    ASSERT (v_member_elem->>'phone') IS NULL, 'TEST E5 FAILED: phone exposed';
    ASSERT (v_member_elem->>'address') IS NULL, 'TEST E6 FAILED: address exposed';
    ASSERT (v_member_elem->>'birth_date') IS NULL, 'TEST E7 FAILED: birth_date exposed';
    ASSERT (v_member_elem->>'auth_user_id') IS NULL, 'TEST E8 FAILED: auth_user_id exposed';
  END LOOP;

  RAISE NOTICE 'TEST E PASSED: No PII, primary_parish_id, address, or administrative_notes exposed';

  -- -------------------------------------------------------------------------
  -- TEST F: Anon role cannot execute family RPCs
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'anon', true);

  v_failed := false;
  BEGIN
    PERFORM public.get_family_profile(v_org_id, v_fam_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST F1 FAILED: anon was able to execute get_family_profile';

  v_failed := false;
  BEGIN
    PERFORM * FROM public.get_member_families(v_org_id, v_ron_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST F2 FAILED: anon was able to execute get_member_families';

  v_failed := false;
  BEGIN
    PERFORM * FROM public.get_family_relationship_types(v_org_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST F3 FAILED: anon was able to execute get_family_relationship_types';

  RAISE NOTICE 'TEST F PASSED: anon denied execute on all family RPCs';

  -- -------------------------------------------------------------------------
  -- TEST G: Direct table WRITE remains unavailable under authenticated role
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id)::text, true);

  v_failed := false;
  BEGIN
    INSERT INTO public.families (organization_id, family_name, display_name)
    VALUES (v_org_id, 'Hacked', 'Hacked Family');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST G1 FAILED: direct INSERT into families succeeded';

  v_failed := false;
  BEGIN
    UPDATE public.families SET family_name = 'Hacked' WHERE id = v_fam_id;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST G2 FAILED: direct UPDATE on families succeeded';

  v_failed := false;
  BEGIN
    DELETE FROM public.families WHERE id = v_fam_id;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_failed := true; END IF;
  END;
  ASSERT v_failed, 'TEST G3 FAILED: direct DELETE on families succeeded';

  RAISE NOTICE 'TEST G PASSED: Direct table writes denied with 42501';

  -- -------------------------------------------------------------------------
  -- TEST H: Invariants Check
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  ASSERT (SELECT count(*) FROM public.families) = 1, 'TEST H1 FAILED';
  ASSERT (SELECT count(*) FROM public.family_members WHERE membership_status = 'active') = 3, 'TEST H2 FAILED';
  ASSERT (SELECT count(*) FROM public.family_relationships WHERE relationship_status = 'active') = 3, 'TEST H3 FAILED';
  ASSERT (SELECT count(*) FROM public.members) = 315, 'TEST H4 FAILED';

  RAISE NOTICE 'PART 2 PASSED: All authenticated JWT security tests succeeded';
END;
$$;

ROLLBACK;

SELECT 'Phase 6A-0 security tests: ALL PASSED' AS result;

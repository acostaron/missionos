-- =============================================================================
-- Security Tests: phase_6b_household_read_security.sql
-- Phase:          Phase 6B-1 — Household Read Foundation
--
-- Non-destructive. All synthetic household creation and execution tests
-- are wrapped inside a transaction and strictly ROLLED BACK.
-- =============================================================================

-- =============================================================================
-- PART 1: SCHEMA & PERMISSION POSTURE
-- =============================================================================

DO $$
DECLARE
  v_count integer;
BEGIN
  -- 1.1 Permission registered
  SELECT count(*) INTO v_count
  FROM public.permissions
  WHERE code = 'households.records.view'
    AND domain_code = 'households'
    AND action_code = 'view'
    AND is_active = true;

  ASSERT v_count = 1,
    format('PART 1.1 FAILED: households.records.view permission not found, count: %s', v_count);
  RAISE NOTICE 'PART 1.1 PASSED: households.records.view permission registered';

  -- 1.2 members.households.view assigned to organization_administrator
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'members.households.view'
    AND ar.code = 'organization_administrator'
    AND rp.permission_effect = 'allow'
    AND rp.approval_status = 'approved';

  ASSERT v_count = 1,
    format('PART 1.2 FAILED: members.households.view not assigned to organization_administrator, count: %s', v_count);
  RAISE NOTICE 'PART 1.2 PASSED: members.households.view assigned to organization_administrator';

  -- 1.3 households.records.view assigned to organization_administrator and servant roles
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'households.records.view'
    AND ar.code IN ('organization_administrator', 'area_servant', 'chapter_servant', 'unit_servant', 'household_servant')
    AND rp.permission_effect = 'allow'
    AND rp.approval_status = 'approved';

  ASSERT v_count = 5,
    format('PART 1.3 FAILED: expected 5 role assignments for households.records.view, got: %s', v_count);
  RAISE NOTICE 'PART 1.3 PASSED: households.records.view assigned to 5 leadership and admin roles';

  -- 1.4 Function existence
  SELECT count(*) INTO v_count
  FROM information_schema.routines
  WHERE (routine_schema = 'public' AND routine_name IN ('get_household_profile', 'get_member_households', 'search_households'))
     OR (routine_schema = 'private' AND routine_name = 'can_access_household');

  ASSERT v_count = 4,
    format('PART 1.4 FAILED: expected 4 routines, found: %s', v_count);
  RAISE NOTICE 'PART 1.4 PASSED: all 4 routines exist in public and private';

  -- 1.5 Direct table grants blocked
  SELECT count(*) INTO v_count
  FROM information_schema.role_table_grants
  WHERE grantee IN ('anon', 'authenticated')
    AND table_schema = 'public'
    AND table_name IN ('households', 'household_memberships')
    AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');

  ASSERT v_count = 0,
    format('PART 1.5 FAILED: direct table writes should have 0 grants, found: %s', v_count);
  RAISE NOTICE 'PART 1.5 PASSED: direct table writes to households/household_memberships are completely blocked';
END $$;

-- =============================================================================
-- PART 2: AUTHENTICATED / JWT EXECUTION TESTS (BEGIN ... ROLLBACK)
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id          uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_admin_profile   uuid := '821fb09c-8396-4549-b120-5674f3cc566a';
  v_member_id       uuid := '99235c89-3ea9-4866-af00-1ec5932cd410';
  v_unit_node_id    uuid := 'dcc74b6b-ee5e-41cd-a836-b939c143060c'; -- RVC Unit 1
  v_hh_type_id      uuid := '9e686cf6-b4fc-4eb0-b25c-0029f0147967'; -- household type
  v_synthetic_hh_id uuid := 'a0000000-0000-0000-0000-000000000001';
  v_res_json        jsonb;
  v_err_code        text;
  v_err_msg         text;
BEGIN
  -- ---------------------------------------------------------------------------
  -- Test J: Empty production search behavior (before creating synthetic node)
  -- ---------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  v_res_json := public.search_households(v_org_id);
  ASSERT (v_res_json->>'total_count')::int = 0,
    format('Test J FAILED: expected 0 households in empty production state, got %s', v_res_json->>'total_count');
  ASSERT jsonb_array_length(v_res_json->'households') = 0,
    'Test J FAILED: expected empty households array';
  RAISE NOTICE 'Test J PASSED: search_households returns empty set on production';

  -- ---------------------------------------------------------------------------
  -- Test K: Member with no household returns empty list
  -- ---------------------------------------------------------------------------
  v_res_json := public.get_member_households(v_org_id, v_member_id);
  ASSERT jsonb_array_length(v_res_json) = 0,
    format('Test K FAILED: expected 0 member households, got %s', jsonb_array_length(v_res_json));
  RAISE NOTICE 'Test K PASSED: member with no household returns []';

  -- ---------------------------------------------------------------------------
  -- Setup Synthetic Household Data (inside transaction only)
  -- ---------------------------------------------------------------------------
  -- 1. Governance node
  INSERT INTO public.governance_nodes (
    id,
    organization_id,
    governance_node_type_id,
    name,
    code,
    lifecycle_status,
    effective_from
  ) VALUES (
    v_synthetic_hh_id,
    v_org_id,
    v_hh_type_id,
    'Synthetic St. Joseph Household',
    'rvc_u01_synth01',
    'active',
    current_date
  );

  -- 2. Household specialized detail row
  INSERT INTO public.households (
    id,
    organization_id,
    household_category,
    meeting_frequency,
    meeting_day_of_week,
    meeting_start_time,
    meeting_timezone_name,
    meeting_location_type,
    meeting_location_text,
    target_member_count,
    maximum_member_count,
    accepts_new_members
  ) VALUES (
    v_synthetic_hh_id,
    v_org_id,
    'pastoral',
    'weekly',
    5,
    '19:30:00'::time,
    'America/New_York',
    'residence',
    'Home of Brother A',
    8,
    12,
    true
  );

  -- 3. Primary parent relationship under RVC Unit 1
  INSERT INTO public.governance_node_relationships (
    organization_id,
    parent_node_id,
    child_node_id,
    relationship_type,
    is_primary,
    relationship_status,
    effective_from
  ) VALUES (
    v_org_id,
    v_unit_node_id,
    v_synthetic_hh_id,
    'primary_parent',
    true,
    'active',
    current_date
  );

  -- 4. Household membership for member
  INSERT INTO public.household_memberships (
    organization_id,
    member_id,
    household_node_id,
    membership_status,
    membership_role,
    is_primary,
    effective_from
  ) VALUES (
    v_org_id,
    v_member_id,
    v_synthetic_hh_id,
    'active',
    'member',
    true,
    current_date
  );

  -- ---------------------------------------------------------------------------
  -- Test A: Organization Administrator read capabilities
  -- ---------------------------------------------------------------------------
  -- A.1 get_household_profile
  v_res_json := public.get_household_profile(v_org_id, v_synthetic_hh_id);
  ASSERT v_res_json->'household'->>'name' = 'Synthetic St. Joseph Household',
    format('Test A.1 FAILED: expected name Synthetic St. Joseph Household, got %s', v_res_json->'household'->>'name');
  ASSERT v_res_json->'household'->>'code' = 'rvc_u01_synth01',
    'Test A.1 FAILED: code mismatch';
  ASSERT (v_res_json->'counts'->>'active_member_count')::int = 1,
    format('Test A.1 FAILED: expected active_member_count 1, got %s', v_res_json->'counts'->>'active_member_count');

  -- A.2 Parent governance resolved correctly (Test I)
  ASSERT v_res_json->'parent_governance'->>'parent_node_name' = 'Rockville Center Unit 1',
    format('Test I FAILED: parent governance not resolved, got %s', v_res_json->'parent_governance'->>'parent_node_name');
  ASSERT v_res_json->'parent_governance'->>'parent_node_type' = 'unit',
    'Test I FAILED: parent governance type mismatch';
  RAISE NOTICE 'Test I PASSED: parent governance node resolved to Rockville Center Unit 1 (unit)';

  -- A.3 Privacy & Field minimization (Test H)
  ASSERT NOT (v_res_json->'members'->0 ? 'email'), 'Test H FAILED: email exposed on member';
  ASSERT NOT (v_res_json->'members'->0 ? 'phone'), 'Test H FAILED: phone exposed on member';
  ASSERT NOT (v_res_json->'members'->0 ? 'address'), 'Test H FAILED: address exposed on member';
  ASSERT NOT (v_res_json->'members'->0 ? 'birth_date'), 'Test H FAILED: birth_date exposed on member';
  ASSERT NOT (v_res_json->'household' ? 'meeting_address_id'), 'Test H FAILED: meeting_address_id exposed';
  ASSERT NOT (v_res_json ? 'confidential_notes'), 'Test H FAILED: confidential notes exposed';
  RAISE NOTICE 'Test H PASSED: safe read contract strictly omits contact PII, addresses, and auth IDs';

  -- A.4 get_member_households
  v_res_json := public.get_member_households(v_org_id, v_member_id);
  ASSERT jsonb_array_length(v_res_json) = 1,
    format('Test A.4 FAILED: expected 1 member household assignment, got %s', jsonb_array_length(v_res_json));
  ASSERT v_res_json->0->>'household_name' = 'Synthetic St. Joseph Household',
    'Test A.4 FAILED: household_name mismatch on member assignment';
  ASSERT v_res_json->0->>'parent_node_name' = 'Rockville Center Unit 1',
    'Test A.4 FAILED: parent_node_name mismatch on member assignment';
  RAISE NOTICE 'Test A.4 PASSED: get_member_households correctly returns assigned household';

  -- A.5 search_households (finds synthetic household)
  v_res_json := public.search_households(v_org_id, 'Synthetic');
  ASSERT (v_res_json->>'total_count')::int = 1,
    format('Test A.5 FAILED: expected search total_count 1, got %s', v_res_json->>'total_count');
  ASSERT v_res_json->'households'->0->>'code' = 'rvc_u01_synth01',
    'Test A.5 FAILED: searched household code mismatch';
  RAISE NOTICE 'Test A PASSED: organization administrator successfully reads synthetic household profile, search, and member placements';

  -- ---------------------------------------------------------------------------
  -- Test C: Caller outside governance scope receives P0002
  -- ---------------------------------------------------------------------------
  -- Setup temporary caller with scope strictly on Albany Chapter
  DECLARE
    v_albany_profile uuid := 'b0000000-0000-0000-0000-000000000001';
    v_albany_node_id uuid := '749a0ffa-0910-4211-b233-97dd04b905b0'; -- Albany Chapter
    v_chapter_role   uuid;
    v_pra_id         uuid;
  BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_albany_profile, 'authenticated', 'authenticated', 'albany.servant@test.local');

    INSERT INTO public.profiles (id, display_name)
    VALUES (v_albany_profile, 'Albany Chapter Servant');

    INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
    VALUES (v_albany_profile, v_org_id, 'active', now());

    SELECT id INTO v_chapter_role FROM public.app_roles WHERE code = 'chapter_servant';

    INSERT INTO public.profile_role_assignments (
      id, organization_id, profile_id, app_role_id, assignment_status,
      proposed_at, approved_at, activated_at, effective_from_at
    ) VALUES (
      gen_random_uuid(), v_org_id, v_albany_profile, v_chapter_role, 'active',
      now(), now(), now(), now()
    ) RETURNING id INTO v_pra_id;

    INSERT INTO public.profile_scope_assignments (
      organization_id, profile_role_assignment_id, scope_type, governance_node_id,
      includes_descendants, scope_effect, assignment_status, effective_from_at
    ) VALUES (
      v_org_id, v_pra_id, 'governance_node', v_albany_node_id, true, 'include', 'active', now()
    );

    -- Impersonate Albany caller
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_albany_profile, 'role', 'authenticated')::text, true);

    BEGIN
      PERFORM public.get_household_profile(v_org_id, v_synthetic_hh_id);
      RAISE EXCEPTION 'Test C FAILED: out-of-scope caller was able to access RVC household!';
    EXCEPTION WHEN SQLSTATE 'P0002' THEN
      RAISE NOTICE 'Test C PASSED: out-of-scope caller received P0002 (indistinguishable not-found/inaccessible)';
    END;

    -- Albany caller searching households sees 0 RVC households
    v_res_json := public.search_households(v_org_id);
    ASSERT (v_res_json->>'total_count')::int = 0,
      format('Test C.2 FAILED: out-of-scope caller saw %s households', v_res_json->>'total_count');
    RAISE NOTICE 'Test C.2 PASSED: out-of-scope caller search yields 0 out-of-scope households';

    -- -------------------------------------------------------------------------
    -- Test B: Properly scoped Chapter caller CAN read descendant household
    -- -------------------------------------------------------------------------
    -- Update scope to RVC Chapter (ancestor of RVC Unit 1 -> synthetic household)
    UPDATE public.profile_scope_assignments
    SET governance_node_id = '8c242b2c-4087-448c-98dc-7f5e29b26d26' -- RVC Chapter
    WHERE profile_role_assignment_id = v_pra_id;

    v_res_json := public.get_household_profile(v_org_id, v_synthetic_hh_id);
    ASSERT v_res_json->'household'->>'name' = 'Synthetic St. Joseph Household',
      'Test B FAILED: in-scope RVC chapter servant could not read descendant household';
    RAISE NOTICE 'Test B PASSED: properly scoped chapter servant can read descendant household';
  END;

  -- ---------------------------------------------------------------------------
  -- Test D: Caller without households.records.view denied with 42501
  -- ---------------------------------------------------------------------------
  DECLARE
    v_plain_profile uuid := 'b0000000-0000-0000-0000-000000000002';
    v_member_role   uuid;
    v_pra_id        uuid;
  BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_plain_profile, 'authenticated', 'authenticated', 'plain.member@test.local');

    INSERT INTO public.profiles (id, display_name)
    VALUES (v_plain_profile, 'Plain Member User');

    INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
    VALUES (v_plain_profile, v_org_id, 'active', now());

    SELECT id INTO v_member_role FROM public.app_roles WHERE code = 'member';

    INSERT INTO public.profile_role_assignments (
      id, organization_id, profile_id, app_role_id, assignment_status,
      proposed_at, approved_at, activated_at, effective_from_at
    ) VALUES (
      gen_random_uuid(), v_org_id, v_plain_profile, v_member_role, 'active',
      now(), now(), now(), now()
    ) RETURNING id INTO v_pra_id;

    INSERT INTO public.profile_scope_assignments (
      organization_id, profile_role_assignment_id, scope_type, scope_effect, assignment_status, effective_from_at
    ) VALUES (
      v_org_id, v_pra_id, 'organization', 'include', 'active', now()
    );

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_plain_profile, 'role', 'authenticated')::text, true);

    BEGIN
      PERFORM public.get_household_profile(v_org_id, v_synthetic_hh_id);
      RAISE EXCEPTION 'Test D FAILED: caller without households.records.view was allowed!';
    EXCEPTION WHEN SQLSTATE '42501' THEN
      RAISE NOTICE 'Test D PASSED: caller without households.records.view denied with 42501';
    END;

    -- Test E: Caller without members.households.view denied with 42501
    BEGIN
      PERFORM public.get_member_households(v_org_id, v_member_id);
      RAISE EXCEPTION 'Test E FAILED: caller without members.households.view was allowed!';
    EXCEPTION WHEN SQLSTATE '42501' THEN
      RAISE NOTICE 'Test E PASSED: caller without members.households.view denied with 42501';
    END;
  END;

  -- ---------------------------------------------------------------------------
  -- Test L: Leadership assignment does NOT grant software application permissions
  -- ---------------------------------------------------------------------------
  DECLARE
    v_leader_profile uuid := 'b0000000-0000-0000-0000-000000000003';
    v_leader_member  uuid := 'f7812117-9206-4f16-b4cb-fd97190dee34'; -- Existing member (Alan Ybay)
  BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_leader_profile, 'authenticated', 'authenticated', 'leader.test@test.local');

    INSERT INTO public.profiles (id, display_name)
    VALUES (v_leader_profile, 'Household Leader User');

    INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
    VALUES (v_leader_profile, v_org_id, 'active', now());

    -- Link profile to member
    INSERT INTO public.profile_member_links (
      organization_id, profile_id, member_id, link_type, link_status, is_primary,
      verified_at, verified_by_profile_id, verification_method
    ) VALUES (
      v_org_id, v_leader_profile, v_leader_member, 'self', 'verified', true,
      now(), v_admin_profile, 'manual'
    );

    -- Member is appointed as household servant via membership role
    INSERT INTO public.household_memberships (
      organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from
    ) VALUES (
      v_org_id, v_leader_member, v_synthetic_hh_id, 'active', 'servant', true, current_date
    );

    -- No app_roles or profile_role_assignments were granted to this profile!
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_leader_profile, 'role', 'authenticated')::text, true);

    -- Member attempts to call get_household_profile -> denied with 42501
    BEGIN
      PERFORM public.get_household_profile(v_org_id, v_synthetic_hh_id);
      RAISE EXCEPTION 'Test L FAILED: appointing pastoral leader granted software permissions automatically!';
    EXCEPTION WHEN SQLSTATE '42501' THEN
      RAISE NOTICE 'Test L PASSED: pastoral leadership appointment does NOT grant application permissions';
    END;
  END;

  RAISE NOTICE 'ALL PHASE 6B-1 SECURITY TESTS COMPLETED SUCCESSFULLY.';
END $$;

ROLLBACK;

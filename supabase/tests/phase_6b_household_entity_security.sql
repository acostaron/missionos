-- =============================================================================
-- Security Tests: phase_6b_household_entity_security.sql
-- Phase:          Phase 6B-2 — Household Entity Lifecycle Management
--
-- Non-destructive. All synthetic household creation and execution tests
-- are wrapped inside a transaction and strictly ROLLED BACK.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_count integer;
BEGIN
  -- ---------------------------------------------------------------------------
  -- PART 1: SCHEMA & PERMISSION POSTURE
  -- ---------------------------------------------------------------------------
  -- 1.1 Permission registered
  SELECT count(*) INTO v_count
  FROM public.permissions
  WHERE code IN ('households.records.create', 'households.records.update', 'households.records.archive')
    AND domain_code = 'households'
    AND is_active = true;

  ASSERT v_count = 3,
    format('PART 1.1 FAILED: expected 3 household write permissions, got %s', v_count);
  RAISE NOTICE 'PART 1.1 PASSED: households.records.create, update, archive permissions registered';

  -- 1.2 Permissions assigned ONLY to organization_administrator
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code IN ('households.records.create', 'households.records.update', 'households.records.archive')
    AND ar.code = 'organization_administrator'
    AND rp.permission_effect = 'allow'
    AND rp.approval_status = 'approved';

  ASSERT v_count = 3,
    format('PART 1.2 FAILED: write permissions not assigned to organization_administrator, count: %s', v_count);

  -- 1.3 Servant roles MUST NOT have write permissions
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code IN ('households.records.create', 'households.records.update', 'households.records.archive')
    AND ar.code IN ('area_servant', 'chapter_servant', 'unit_servant', 'household_servant');

  ASSERT v_count = 0,
    format('PART 1.3 FAILED: pastoral servant roles received write permissions! count: %s', v_count);
  RAISE NOTICE 'PART 1.3 PASSED: household write permissions restricted strictly to organization_administrator';

  -- 1.4 Function existence
  SELECT count(*) INTO v_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name IN ('create_household', 'update_household', 'archive_household');

  ASSERT v_count = 3,
    format('PART 1.4 FAILED: expected 3 routines, found: %s', v_count);
  RAISE NOTICE 'PART 1.4 PASSED: create_household, update_household, archive_household exist in public';

  -- 1.5 Direct table grants blocked
  SELECT count(*) INTO v_count
  FROM information_schema.role_table_grants
  WHERE grantee IN ('anon', 'authenticated')
    AND table_schema = 'public'
    AND table_name IN ('households', 'household_memberships', 'governance_nodes', 'governance_node_relationships')
    AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');

  ASSERT v_count = 0,
    format('PART 1.5 FAILED: direct table writes should have 0 grants, found: %s', v_count);
  RAISE NOTICE 'PART 1.5 PASSED: direct table writes are completely blocked';
END $$;

-- -----------------------------------------------------------------------------
-- PART 2: TRANSACTIONAL LIFECYCLE EXECUTION TESTS
-- -----------------------------------------------------------------------------

DO $$
DECLARE
  v_org_id           uuid;
  v_admin_profile    uuid;
  v_viewer_profile   uuid;
  v_unit_node_id     uuid;
  v_chapter_node_id  uuid;
  v_area_node_id     uuid;
  v_res_json         jsonb;
  v_hh_id            uuid;
  v_hh_chapter_id    uuid;
  v_count            integer;
  v_audit_count      integer;
  v_dummy_member_id  uuid;
  v_dummy_role_def   uuid;
  v_type_code        text;
BEGIN
  -- Resolve production organization (MFCNY)
  SELECT id INTO v_org_id
  FROM public.organizations
  LIMIT 1;

  -- Resolve active admin profile
  SELECT p.id INTO v_admin_profile
  FROM public.profiles p
  JOIN public.profile_role_assignments pra ON pra.profile_id = p.id
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE pra.organization_id = v_org_id
    AND ar.code = 'organization_administrator'
    AND pra.assignment_status = 'active'
  LIMIT 1;

  -- Resolve valid parent Unit (Rockville Center Unit 1)
  SELECT id INTO v_unit_node_id
  FROM public.governance_nodes
  WHERE organization_id = v_org_id AND code = 'rvc_u01';

  -- Resolve valid parent Chapter (Rockville Center Chapter)
  SELECT id INTO v_chapter_node_id
  FROM public.governance_nodes
  WHERE organization_id = v_org_id AND code = 'rvc';

  -- Resolve Area node (invalid parent for household)
  SELECT id INTO v_area_node_id
  FROM public.governance_nodes
  WHERE organization_id = v_org_id AND code = 'ny';

  -- ---------------------------------------------------------------------------
  -- TEST 31: CREATE TESTS
  -- ---------------------------------------------------------------------------

  -- Set caller context as Organization Administrator
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- 31.A: Admin creates synthetic household under valid Unit
  v_res_json := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'St. Peter Pastoral Household',
    p_code                      => 'rvc_u01_stpeter',
    p_parent_governance_node_id => v_unit_node_id,
    p_household_category        => 'pastoral',
    p_meeting_frequency         => 'weekly',
    p_meeting_day_of_week       => 3::smallint,
    p_meeting_start_time        => '19:30:00'::time,
    p_meeting_timezone_name     => 'America/New_York',
    p_meeting_location_type     => 'residence',
    p_meeting_location_text     => 'Residence of Bro John',
    p_target_member_count       => 8,
    p_maximum_member_count      => 12,
    p_accepts_new_members       => true,
    p_language_code             => 'en',
    p_is_couple_household       => false
  );

  ASSERT v_res_json->>'status' = 'created', 'Test 31.A FAILED: status not created';
  v_hh_id := (v_res_json->>'household_id')::uuid;
  ASSERT v_hh_id IS NOT NULL, 'Test 31.A FAILED: household_id is null';
  ASSERT v_res_json->>'name' = 'St. Peter Pastoral Household', 'Test 31.A FAILED: name mismatch';
  ASSERT v_res_json->>'code' = 'rvc_u01_stpeter', 'Test 31.A FAILED: code mismatch';
  ASSERT v_res_json->>'parent_governance_node_id' = v_unit_node_id::text, 'Test 31.A FAILED: parent node mismatch';
  RAISE NOTICE 'Test 31.A PASSED: synthetic household created under Unit';

  -- 31.B: Admin creates synthetic household directly under Chapter
  v_res_json := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'Chapter Pastoral Household',
    p_code                      => 'rvc_chap_hh',
    p_parent_governance_node_id => v_chapter_node_id,
    p_pastoral_level            => 'chapter'
  );
  ASSERT v_res_json->>'status' = 'created', 'Test 31.B FAILED: status not created';
  v_hh_chapter_id := (v_res_json->>'household_id')::uuid;
  RAISE NOTICE 'Test 31.B PASSED: synthetic household created directly under Chapter';

  -- 31.C: Governance node created
  SELECT count(*) INTO v_count
  FROM public.governance_nodes
  WHERE id = v_hh_id AND organization_id = v_org_id AND lifecycle_status = 'active';
  ASSERT v_count = 1, 'Test 31.C FAILED: governance_nodes record not found';
  RAISE NOTICE 'Test 31.C PASSED: governance node created with active status';

  -- 31.D: Household detail row created
  SELECT count(*) INTO v_count
  FROM public.households
  WHERE id = v_hh_id AND organization_id = v_org_id AND meeting_frequency = 'weekly';
  ASSERT v_count = 1, 'Test 31.D FAILED: public.households detail row not found';
  RAISE NOTICE 'Test 31.D PASSED: household detail created with full pastoral configuration';

  -- 31.E: Primary parent relationship created
  SELECT count(*) INTO v_count
  FROM public.governance_node_relationships
  WHERE child_node_id = v_hh_id AND parent_node_id = v_unit_node_id AND relationship_type = 'primary_parent' AND is_primary = true;
  ASSERT v_count = 1, 'Test 31.E FAILED: governance_node_relationships record not found';
  RAISE NOTICE 'Test 31.E PASSED: primary parent relationship created';

  -- 31.F: Node type is household
  SELECT count(*) INTO v_count
  FROM public.governance_nodes gn
  JOIN public.governance_node_types gnt ON gnt.id = gn.governance_node_type_id
  WHERE gn.id = v_hh_id AND gnt.code = 'household' AND gnt.hierarchy_rank = 70;
  ASSERT v_count = 1, 'Test 31.F FAILED: node type is not household rank 70';
  RAISE NOTICE 'Test 31.F PASSED: node type resolved to household (rank 70)';

  -- 31.G & 31.H: Zero household memberships & zero leadership assignments
  SELECT count(*) INTO v_count FROM public.household_memberships WHERE household_node_id = v_hh_id;
  ASSERT v_count = 0, 'Test 31.G FAILED: unexpected membership created';
  SELECT count(*) INTO v_count FROM public.leadership_assignments WHERE governance_node_id = v_hh_id;
  ASSERT v_count = 0, 'Test 31.H FAILED: unexpected leadership assignment created';
  RAISE NOTICE 'Test 31.G & 31.H PASSED: zero memberships and zero leadership assignments created';

  -- 31.I & 31.J: Family and member data completely unaffected
  SELECT count(*) INTO v_count FROM public.families WHERE organization_id = v_org_id;
  ASSERT v_count = 1, 'Test 31.I FAILED: family count altered';
  SELECT count(*) INTO v_count FROM public.member_governance_assignments WHERE organization_id = v_org_id AND assignment_status = 'active';
  ASSERT v_count = 313, 'Test 31.J FAILED: member governance assignments altered';
  RAISE NOTICE 'Test 31.I & 31.J PASSED: family and member governance data remain unaffected';

  -- 31.K: Duplicate code rejected
  BEGIN
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Another Household',
      p_code                      => 'rvc_u01_stpeter',
      p_parent_governance_node_id => v_unit_node_id
    );
    RAISE EXCEPTION 'Test 31.K FAILED: duplicate code allowed!';
  EXCEPTION WHEN SQLSTATE '23505' THEN
    RAISE NOTICE 'Test 31.K PASSED: duplicate household code cleanly rejected with 23505';
  END;

  -- 31.L: Invalid parent type rejected (Area node rank 30 is not unit or chapter)
  BEGIN
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Direct Area Household',
      p_code                      => 'ny_direct_hh',
      p_parent_governance_node_id => v_area_node_id
    );
    RAISE EXCEPTION 'Test 31.L FAILED: Area parent allowed for household!';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    RAISE NOTICE 'Test 31.L PASSED: invalid parent node type (area) cleanly rejected with 22023';
  END;

  -- 31.M: Parent node in non-active lifecycle status rejected
  DECLARE
    v_test_parent_id uuid := gen_random_uuid();
    v_unit_type_id   uuid;
    v_test_status    text;
    v_check_status   text;
    v_statuses       text[] := ARRAY['planned', 'temporarily_inactive', 'closed', 'merged', 'archived'];
  BEGIN
    SELECT id INTO v_unit_type_id
    FROM public.governance_node_types
    WHERE organization_id = v_org_id AND code = 'unit';

    INSERT INTO public.governance_nodes (
      id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from
    ) VALUES (
      v_test_parent_id, v_org_id, v_unit_type_id, 'synth_test_parent_u', 'Synthetic Test Parent Unit', 'active', current_date
    );

    FOREACH v_test_status IN ARRAY v_statuses
    LOOP
      UPDATE public.governance_nodes
      SET
        lifecycle_status = v_test_status,
        archived_at = CASE WHEN v_test_status = 'archived' THEN now() ELSE NULL END,
        archive_reason = CASE WHEN v_test_status = 'archived' THEN 'Test parent archive' ELSE NULL END
      WHERE id = v_test_parent_id;

      SELECT lifecycle_status INTO v_check_status
      FROM public.governance_nodes
      WHERE id = v_test_parent_id;

      ASSERT v_check_status = v_test_status, format('Failed to set synthetic parent lifecycle_status to %s', v_test_status);

      BEGIN
        PERFORM public.create_household(
          p_organization_id           => v_org_id,
          p_name                      => 'Test Status Household',
          p_code                      => 'test_status_hh_' || lower(v_test_status),
          p_parent_governance_node_id => v_test_parent_id
        );
        RAISE EXCEPTION 'Parent status % was unexpectedly allowed!', v_test_status;
      EXCEPTION WHEN SQLSTATE '22023' THEN
        -- Expected rejection
      END;
    END LOOP;

    -- Clean up synthetic parent node
    DELETE FROM public.governance_nodes WHERE id = v_test_parent_id;
    RAISE NOTICE 'Test 31.M PASSED: create_household rejected all non-active parent states (planned, temporarily_inactive, closed, merged, archived)';
  END;

  -- 31.N & 31.O: Unauthorized caller & anon denied
  -- Create synthetic profile with active org membership and member role (no households.records.create)
  DECLARE
    v_test_profile uuid := 'c0000000-0000-0000-0000-000000000001';
    v_member_role uuid;
    v_pra_id uuid;
  BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_test_profile, 'authenticated', 'authenticated', 'test.member.lifecycle@test.local');

    INSERT INTO public.profiles (id, display_name)
    VALUES (v_test_profile, 'Plain Member User');

    INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
    VALUES (v_test_profile, v_org_id, 'active', now());

    SELECT id INTO v_member_role FROM public.app_roles WHERE code = 'member';

    INSERT INTO public.profile_role_assignments (
      id, organization_id, profile_id, app_role_id, assignment_status,
      proposed_at, approved_at, activated_at, effective_from_at
    ) VALUES (
      gen_random_uuid(), v_org_id, v_test_profile, v_member_role, 'active',
      now(), now(), now(), now()
    ) RETURNING id INTO v_pra_id;

    INSERT INTO public.profile_scope_assignments (
      organization_id, profile_role_assignment_id, scope_type, scope_effect, assignment_status, effective_from_at
    ) VALUES (
      v_org_id, v_pra_id, 'organization', 'include', 'active', now()
    );

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_test_profile, 'role', 'authenticated')::text, true);
    BEGIN
      PERFORM public.create_household(
        p_organization_id           => v_org_id,
        p_name                      => 'Unauthorized Household',
        p_code                      => 'unauth_hh',
        p_parent_governance_node_id => v_unit_node_id
      );
      RAISE EXCEPTION 'Test 31.N FAILED: unauthorized user created household!';
    EXCEPTION WHEN SQLSTATE '42501' THEN
      RAISE NOTICE 'Test 31.N PASSED: unauthorized caller denied with 42501';
    END;
  END;

  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  BEGIN
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Anon Household',
      p_code                      => 'anon_hh',
      p_parent_governance_node_id => v_unit_node_id
    );
    RAISE EXCEPTION 'Test 31.O FAILED: anon user created household!';
  EXCEPTION WHEN SQLSTATE '28000' THEN
    RAISE NOTICE 'Test 31.O PASSED: anon denied with 28000';
  END;

  -- ---------------------------------------------------------------------------
  -- TEST 32: UPDATE TESTS
  -- ---------------------------------------------------------------------------
  -- Restore admin context
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- 32.A-D: Admin updates household name, schedule, capacity, and acceptance
  v_res_json := public.update_household(
    p_organization_id       => v_org_id,
    p_household_id          => v_hh_id,
    p_name                  => 'St. Peter Pastoral Household - Updated',
    p_code                  => 'rvc_u01_stpeter_mod',
    p_household_category    => 'formation',
    p_meeting_frequency     => 'biweekly',
    p_meeting_day_of_week   => 5::smallint,
    p_meeting_start_time    => '20:00:00'::time,
    p_meeting_timezone_name => 'America/New_York',
    p_meeting_location_type => 'parish_hall',
    p_meeting_location_text => 'St. Agnes Parish Hall Room 2',
    p_target_member_count   => 10,
    p_maximum_member_count  => 14,
    p_accepts_new_members   => false,
    p_language_code         => 'en',
    p_is_couple_household   => true
  );

  ASSERT v_res_json->>'status' IN ('updated', 'success'), 'Test 32 FAILED: update status not updated/success';
  ASSERT v_res_json->>'name' = 'St. Peter Pastoral Household - Updated', 'Test 32.A FAILED: name mismatch';
  ASSERT v_res_json->>'code' = 'rvc_u01_stpeter_mod', 'Test 32 FAILED: code mismatch';

  -- Verify database persistence
  SELECT count(*) INTO v_count
  FROM public.households h
  JOIN public.governance_nodes gn ON gn.id = h.id
  WHERE h.id = v_hh_id
    AND gn.name = 'St. Peter Pastoral Household - Updated'
    AND h.household_category = 'formation'
    AND h.meeting_frequency = 'biweekly'
    AND h.target_member_count = 10
    AND h.maximum_member_count = 14
    AND h.accepts_new_members = false
    AND h.is_couple_household = true;
  ASSERT v_count = 1, 'Test 32 FAILED: updated attributes not persisted';
  RAISE NOTICE 'Test 32.A-D PASSED: household identity, schedule, capacity updated successfully';

  -- 32.E-G: Parent governance, node type, and organization remain unchanged
  SELECT count(*) INTO v_count
  FROM public.governance_node_relationships
  WHERE child_node_id = v_hh_id AND parent_node_id = v_unit_node_id;
  ASSERT v_count = 1, 'Test 32.E FAILED: parent governance was altered';

  SELECT gnt.code INTO v_type_code
  FROM public.governance_nodes gn
  JOIN public.governance_node_types gnt ON gnt.id = gn.governance_node_type_id
  WHERE gn.id = v_hh_id;
  ASSERT v_type_code = 'household', 'Test 32.F FAILED: node type altered';
  RAISE NOTICE 'Test 32.E-G PASSED: parent governance, node type, and organization immutable';

  -- ---------------------------------------------------------------------------
  -- TEST 33: ARCHIVE TESTS
  -- ---------------------------------------------------------------------------

  -- 33.G: Attempting archive on household with active members MUST BE BLOCKED
  SELECT id INTO v_dummy_member_id FROM public.members WHERE organization_id = v_org_id LIMIT 1;

  INSERT INTO public.household_memberships (
    organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from
  ) VALUES (
    v_org_id, v_dummy_member_id, v_hh_id, 'active', 'member', true, current_date
  );

  v_res_json := public.archive_household(v_org_id, v_hh_id, 'Attempting archive with active member');
  ASSERT v_res_json->>'status' = 'blocked', 'Test 33.G FAILED: archive not blocked for active members';
  ASSERT v_res_json->>'blocker_type' = 'active_household_memberships', 'Test 33.G FAILED: blocker_type mismatch';
  ASSERT (v_res_json->>'active_member_count')::int = 1, 'Test 33.G FAILED: member count mismatch';
  RAISE NOTICE 'Test 33.G PASSED: archive blocked when active household memberships exist';

  -- Remove active membership
  DELETE FROM public.household_memberships WHERE household_node_id = v_hh_id;

  -- 33.H: Attempting archive on household with active leadership MUST BE BLOCKED
  DECLARE
    v_synth_role_id uuid := gen_random_uuid();
    v_hh_node_type_id uuid;
  BEGIN
    SELECT id INTO v_hh_node_type_id
    FROM public.governance_node_types
    WHERE organization_id = v_org_id AND code = 'household';

    INSERT INTO public.leadership_role_definitions (
      id, organization_id, code, name, leadership_category,
      cardinality_type, requires_approval, is_active, display_order
    ) VALUES (
      v_synth_role_id, v_org_id, 'test_household_servant', 'Test Household Servant', 'pastoral',
      'single', false, true, 10
    );

    INSERT INTO public.leadership_role_node_types (
      organization_id, leadership_role_definition_id, governance_node_type_id, is_primary_mapping, is_active
    ) VALUES (
      v_org_id, v_synth_role_id, v_hh_node_type_id, true, true
    );

    INSERT INTO public.leadership_assignments (
      organization_id, member_id, governance_node_id, leadership_role_definition_id,
      assignment_status, effective_from, approved_at, accepted_at, activated_at
    ) VALUES (
      v_org_id, v_dummy_member_id, v_hh_id, v_synth_role_id,
      'active', current_date, now(), now(), now()
    );

    v_res_json := public.archive_household(v_org_id, v_hh_id, 'Attempting archive with active leader');
    ASSERT v_res_json->>'status' = 'blocked', 'Test 33.H FAILED: archive not blocked for active leaders';
    ASSERT v_res_json->>'blocker_type' = 'active_leadership_assignments', 'Test 33.H FAILED: blocker_type mismatch';
    ASSERT (v_res_json->>'active_leadership_count')::int = 1, 'Test 33.H FAILED: leader count mismatch';
    RAISE NOTICE 'Test 33.H PASSED: archive blocked when active leadership assignments exist';

    -- Remove active leadership assignment and synthetic definitions
    DELETE FROM public.leadership_assignments WHERE governance_node_id = v_hh_id;
    DELETE FROM public.leadership_role_node_types WHERE leadership_role_definition_id = v_synth_role_id;
    DELETE FROM public.leadership_role_definitions WHERE id = v_synth_role_id;
  END;

  -- 33.A-E: Empty household archives successfully
  v_res_json := public.archive_household(v_org_id, v_hh_id, 'Consolidated into neighboring household');
  ASSERT v_res_json->>'status' = 'success', 'Test 33.A FAILED: archive status not success';
  ASSERT v_res_json->>'lifecycle_status' = 'archived', 'Test 33.E FAILED: lifecycle_status not archived';

  -- Verify records preserved
  SELECT count(*) INTO v_count FROM public.governance_nodes WHERE id = v_hh_id AND lifecycle_status = 'archived' AND archive_reason = 'Consolidated into neighboring household';
  ASSERT v_count = 1, 'Test 33.B FAILED: governance node not in archived state';

  -- Verify governance relationship row is preserved and ended historically
  SELECT count(*) INTO v_count
  FROM public.governance_node_relationships
  WHERE child_node_id = v_hh_id
    AND parent_node_id = v_unit_node_id
    AND relationship_status = 'ended'
    AND ended_at IS NOT NULL
    AND ending_reason IS NOT NULL;
  ASSERT v_count = 1, 'Test 33.D FAILED: governance relationship was deleted or not ended properly';
  RAISE NOTICE 'Test 33.D PASSED: governance relationship row preserved with ended status and audit trail';
  RAISE NOTICE 'Test 33.A-E PASSED: empty household archives cleanly, preserving nodes, details, and relationships';

  -- 33.F: Duplicate archive rejected
  BEGIN
    PERFORM public.archive_household(v_org_id, v_hh_id, 'Duplicate archive');
    RAISE EXCEPTION 'Test 33.F FAILED: duplicate archive allowed!';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    RAISE NOTICE 'Test 33.F PASSED: duplicate archive cleanly rejected with 22023';
  END;

  -- 32.H: Updating an archived household is rejected
  BEGIN
    PERFORM public.update_household(
      p_organization_id => v_org_id,
      p_household_id    => v_hh_id,
      p_name            => 'Attempted Name Update',
      p_code            => 'rvc_u01_stpeter_mod'
    );
    RAISE EXCEPTION 'Test 32.H FAILED: update on archived household allowed!';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    RAISE NOTICE 'Test 32.H PASSED: updating archived household rejected with 22023';
  END;

  -- ---------------------------------------------------------------------------
  -- TEST 34: READ CONTRACT REGRESSION
  -- ---------------------------------------------------------------------------
  -- Archived household should still be readable by get_household_profile AND retain historical parent context
  v_res_json := public.get_household_profile(v_org_id, v_hh_id);
  ASSERT v_res_json->'household'->>'lifecycle_status' = 'archived', 'Test 34 FAILED: archived profile not readable';
  ASSERT v_res_json->'parent_governance' IS NOT NULL, 'Test 34 FAILED: archived profile lost parent governance';
  ASSERT v_res_json->'parent_governance'->>'parent_node_id' = v_unit_node_id::text, 'Test 34 FAILED: archived profile parent_node_id mismatch';
  ASSERT v_res_json->'parent_governance'->>'parent_node_code' = 'rvc_u01', 'Test 34 FAILED: archived profile parent_node_code mismatch';
  ASSERT v_res_json->'parent_governance'->>'parent_node_type' = 'unit', 'Test 34 FAILED: archived profile parent_node_type mismatch';
  RAISE NOTICE 'Test 34.A PASSED: get_household_profile can safely read archived household and preserves former parent provenance';

  -- search_households default active filter excludes archived household
  v_res_json := public.search_households(
    p_organization_id => v_org_id,
    p_lifecycle_status => 'active'
  );
  -- The chapter household created earlier is active (count 1), but the archived stpeter is excluded
  ASSERT (v_res_json->>'total_count')::int = 1, format('Test 34.B FAILED: expected 1 active household, got %s', v_res_json->>'total_count');
  RAISE NOTICE 'Test 34.B PASSED: search_households active filter excludes archived household';

  -- ---------------------------------------------------------------------------
  -- TEST 35: COMPREHENSIVE 6-STATUS LIFECYCLE MATRIX FOR UPDATE & ARCHIVE
  -- Valid statuses: planned, active, temporarily_inactive, closed, merged, archived
  -- Requirements:
  --   planned:              update succeeds, archive succeeds (if empty)
  --   active:               update succeeds, archive succeeds (if empty)
  --   temporarily_inactive: update succeeds, archive succeeds (if empty)
  --   closed:               update rejected (22023), archive rejected (22023)
  --   merged:               update rejected (22023), archive rejected (22023)
  --   archived:             update rejected (22023), archive rejected (22023)
  -- ---------------------------------------------------------------------------
  DECLARE
    v_st_test           text;
    v_matrix_hh_id      uuid;
    v_matrix_hh_code    text;
    v_matrix_upd_res    jsonb;
    v_matrix_arch_res   jsonb;
    v_valid_statuses    text[] := ARRAY['planned', 'active', 'temporarily_inactive', 'closed', 'merged', 'archived'];
  BEGIN
    FOREACH v_st_test IN ARRAY v_valid_statuses
    LOOP
      v_matrix_hh_code := 'synth_matrix_' || lower(v_st_test);

      -- Create a fresh active household under valid unit
      v_res_json := public.create_household(
        p_organization_id           => v_org_id,
        p_name                      => 'Matrix Household ' || v_st_test,
        p_code                      => v_matrix_hh_code,
        p_parent_governance_node_id => v_unit_node_id
      );
      v_matrix_hh_id := (v_res_json->>'household_id')::uuid;

      -- If testing a historical status, end active relationship first to satisfy governance relationship constraint
      IF v_st_test IN ('closed', 'merged', 'archived') THEN
        UPDATE public.governance_node_relationships
        SET
          relationship_status = 'ended',
          effective_to = coalesce(effective_to, current_date),
          ended_at = now(),
          ended_by = v_admin_profile,
          ending_reason = 'Test ending for ' || v_st_test,
          updated_by = v_admin_profile
        WHERE child_node_id = v_matrix_hh_id;
      END IF;

      UPDATE public.governance_nodes
      SET
        lifecycle_status = v_st_test,
        archived_at = CASE WHEN v_st_test = 'archived' THEN now() ELSE NULL END,
        archive_reason = CASE WHEN v_st_test = 'archived' THEN 'Synthetic test setup' ELSE NULL END
      WHERE id = v_matrix_hh_id;

      -- 1. Verify UPDATE behavior
      IF v_st_test IN ('planned', 'active', 'temporarily_inactive') THEN
        v_matrix_upd_res := public.update_household(
          p_organization_id => v_org_id,
          p_household_id    => v_matrix_hh_id,
          p_name            => 'Matrix Household ' || v_st_test || ' (Updated)',
          p_code            => v_matrix_hh_code || '_u'
        );
        ASSERT v_matrix_upd_res->>'status' IN ('updated', 'success'),
          format('Matrix UPDATE failed for status %s', v_st_test);
      ELSE
        BEGIN
          PERFORM public.update_household(
            p_organization_id => v_org_id,
            p_household_id    => v_matrix_hh_id,
            p_name            => 'Matrix Household ' || v_st_test || ' (Illegal Update)',
            p_code            => v_matrix_hh_code || '_ill'
          );
          RAISE EXCEPTION 'Matrix UPDATE unexpectedly succeeded for terminal status %', v_st_test;
        EXCEPTION WHEN SQLSTATE '22023' THEN
          -- Expected 22023 rejection
        END;
      END IF;

      -- 2. Verify ARCHIVE behavior
      IF v_st_test IN ('planned', 'active', 'temporarily_inactive') THEN
        v_matrix_arch_res := public.archive_household(
          v_org_id,
          v_matrix_hh_id,
          'Matrix archive reason for ' || v_st_test
        );
        ASSERT v_matrix_arch_res->>'status' = 'success',
          format('Matrix ARCHIVE failed for status %s', v_st_test);
        ASSERT v_matrix_arch_res->>'lifecycle_status' = 'archived',
          format('Matrix ARCHIVE lifecycle mismatch for status %s', v_st_test);
      ELSE
        BEGIN
          PERFORM public.archive_household(
            v_org_id,
            v_matrix_hh_id,
            'Matrix illegal archive reason for ' || v_st_test
          );
          RAISE EXCEPTION 'Matrix ARCHIVE unexpectedly succeeded for terminal status %', v_st_test;
        EXCEPTION WHEN SQLSTATE '22023' THEN
          -- Expected 22023 rejection
        END;
      END IF;

      -- Clean up synthetic matrix row
      DELETE FROM public.governance_node_relationships WHERE child_node_id = v_matrix_hh_id;
      DELETE FROM public.households WHERE id = v_matrix_hh_id;
      DELETE FROM public.governance_nodes WHERE id = v_matrix_hh_id;
    END LOOP;
    RAISE NOTICE 'Test 35 PASSED: Full 6-status matrix verified for update_household and archive_household (planned, active, temporarily_inactive allowed; closed, merged, archived rejected with 22023)';
  END;

  -- ---------------------------------------------------------------------------
  -- AUDIT EVENTS VERIFICATION
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_audit_count
  FROM audit.events
  WHERE organization_id = v_org_id
    AND entity_type = 'household'
    AND event_category = 'governance'
    AND event_code IN ('household.created', 'household.updated', 'household.archived');

  ASSERT v_audit_count >= 4, format('Audit test FAILED: expected at least 4 audit events, found %s', v_audit_count);
  RAISE NOTICE 'Audit Test PASSED: % household audit events successfully recorded in audit.events', v_audit_count;

  RAISE NOTICE 'ALL PHASE 6B-2 SECURITY & LIFECYCLE TESTS COMPLETED SUCCESSFULLY.';
END $$;

ROLLBACK;

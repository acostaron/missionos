-- =============================================================================
-- Test Suite: phase_6b_canonical_leadership_roles_security.sql
-- Phase:      Phase 6B-3 — Canonical MFC Leadership Role Definitions Security Tests
--
-- Tests & Validates:
--  1. Exactly four canonical pastoral role definitions exist in leadership_role_definitions.
--  2. Each canonical role maps ONLY to its authoritative governance node type:
--       - household_servant_leader -> household (rank 70)
--       - unit_servant_leader      -> unit (rank 60)
--       - chapter_servant_leader   -> chapter (rank 50)
--       - area_servant_leader      -> area_state (rank 30)
--  3. Vacancy is allowed (minimum_assignees = 0).
--  4. Second concurrent active assignment is blocked by validate_leadership_assignment (cardinality = single).
--  5. couple_pair is NOT required (requires_couple_pair = false).
--  6. Zero application authorization / app_roles / profile_role_assignments created.
--  7. Legacy pastoral role codes (household_servant, H-SERV, etc.) are NOT seeded.
--  8. Software app_roles remain untouched.
--  9. Corrective RPC public.get_household_profile successfully derives Household Leaders
--     using canonical household_servant_leader.
--
-- Non-destructive. Wrapped in a transaction and strictly ROLLED BACK.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id                    uuid;
  v_admin_profile             uuid;
  v_count                     integer;
  v_role_hsl_id               uuid;
  v_role_usl_id               uuid;
  v_role_csl_id               uuid;
  v_role_asl_id               uuid;
  v_node_hh_id                uuid;
  v_node_unit_id              uuid;
  v_node_chapter_id           uuid;
  v_node_area_id              uuid;
  v_member_1_id               uuid;
  v_member_2_id               uuid;
  v_member_wife_id            uuid;
  v_family_id                 uuid;
  v_rel_id                    uuid;
  v_assign_1_id               uuid;
  v_assign_2_id               uuid;
  v_profile_json              jsonb;
  v_household_leaders         jsonb;
  v_status_active_id          uuid;
  v_rel_type_spouse_id        uuid;
  v_hh_type_id                uuid;
  v_blocked                   boolean;
BEGIN
  -- ---------------------------------------------------------------------------
  -- 0. Deterministic Org & Context Setup
  -- ---------------------------------------------------------------------------
  SELECT id INTO STRICT v_org_id FROM public.organizations LIMIT 1;

  SELECT p.id INTO v_admin_profile
  FROM public.profiles p
  JOIN public.profile_role_assignments pra ON pra.profile_id = p.id
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE pra.organization_id = v_org_id
    AND ar.code = 'organization_administrator'
    AND pra.assignment_status = 'active'
  LIMIT 1;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ---------------------------------------------------------------------------
  -- Test 1: Exactly four canonical role definitions exist
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.leadership_role_definitions
  WHERE organization_id = v_org_id
    AND is_active = true
    AND code IN ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader');
  ASSERT v_count = 4, 'Test 1 FAILED: Expected exactly 4 canonical pastoral role definitions, found ' || v_count;
  RAISE NOTICE 'Test 1 PASSED: Exactly 4 canonical pastoral role definitions exist.';

  -- Resolve IDs
  SELECT id INTO STRICT v_role_hsl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'household_servant_leader';
  SELECT id INTO STRICT v_role_usl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'unit_servant_leader';
  SELECT id INTO STRICT v_role_csl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'chapter_servant_leader';
  SELECT id INTO STRICT v_role_asl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'area_servant_leader';

  -- ---------------------------------------------------------------------------
  -- Test 2: Each canonical role maps ONLY to correct governance node type
  -- ---------------------------------------------------------------------------
  -- household_servant_leader -> household (rank 70)
  SELECT count(*) INTO v_count
  FROM public.leadership_role_node_types lrnt
  JOIN public.governance_node_types gnt ON gnt.id = lrnt.governance_node_type_id
  WHERE lrnt.organization_id = v_org_id
    AND lrnt.leadership_role_definition_id = v_role_hsl_id
    AND lrnt.is_active = true
    AND gnt.code = 'household'
    AND lrnt.minimum_node_rank = 70
    AND lrnt.maximum_node_rank = 70;
  ASSERT v_count = 1, 'Test 2A FAILED: household_servant_leader mapping incorrect';

  -- unit_servant_leader -> unit (rank 60)
  SELECT count(*) INTO v_count
  FROM public.leadership_role_node_types lrnt
  JOIN public.governance_node_types gnt ON gnt.id = lrnt.governance_node_type_id
  WHERE lrnt.organization_id = v_org_id
    AND lrnt.leadership_role_definition_id = v_role_usl_id
    AND lrnt.is_active = true
    AND gnt.code = 'unit'
    AND lrnt.minimum_node_rank = 60
    AND lrnt.maximum_node_rank = 60;
  ASSERT v_count = 1, 'Test 2B FAILED: unit_servant_leader mapping incorrect';

  -- chapter_servant_leader -> chapter (rank 50)
  SELECT count(*) INTO v_count
  FROM public.leadership_role_node_types lrnt
  JOIN public.governance_node_types gnt ON gnt.id = lrnt.governance_node_type_id
  WHERE lrnt.organization_id = v_org_id
    AND lrnt.leadership_role_definition_id = v_role_csl_id
    AND lrnt.is_active = true
    AND gnt.code = 'chapter'
    AND lrnt.minimum_node_rank = 50
    AND lrnt.maximum_node_rank = 50;
  ASSERT v_count = 1, 'Test 2C FAILED: chapter_servant_leader mapping incorrect';

  -- area_servant_leader -> area_state (rank 30)
  SELECT count(*) INTO v_count
  FROM public.leadership_role_node_types lrnt
  JOIN public.governance_node_types gnt ON gnt.id = lrnt.governance_node_type_id
  WHERE lrnt.organization_id = v_org_id
    AND lrnt.leadership_role_definition_id = v_role_asl_id
    AND lrnt.is_active = true
    AND gnt.code = 'area_state'
    AND lrnt.minimum_node_rank = 30
    AND lrnt.maximum_node_rank = 30;
  ASSERT v_count = 1, 'Test 2D FAILED: area_servant_leader mapping incorrect';
  RAISE NOTICE 'Test 2 PASSED: Each canonical role maps only to its authoritative node type and exact rank range.';

  -- ---------------------------------------------------------------------------
  -- Test 3: Vacancy allowed (minimum_assignees = 0)
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.leadership_role_definitions
  WHERE organization_id = v_org_id
    AND code IN ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    AND (minimum_assignees <> 0 OR maximum_assignees <> 1 OR cardinality_type <> 'single');
  ASSERT v_count = 0, 'Test 3 FAILED: Vacancy configuration incorrect (minimum_assignees must be 0, maximum 1, single)';
  RAISE NOTICE 'Test 3 PASSED: Vacancy explicitly permitted across all 4 roles.';

  -- ---------------------------------------------------------------------------
  -- Test 4: Second concurrent active assignment is blocked
  -- ---------------------------------------------------------------------------
  -- Create synthetic test household node
  SELECT id INTO STRICT v_hh_type_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'household';
  SELECT id INTO STRICT v_status_active_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active';

  v_node_hh_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_hh_id, v_org_id, v_hh_type_id, 'synth_test_hh', 'Synthetic Test HH', 'active', current_date - 10);
  INSERT INTO public.households (id, organization_id, is_couple_household, accepts_new_members)
  VALUES (v_node_hh_id, v_org_id, true, true);

  -- Create Member 1 and Member 2
  v_member_1_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_member_1_id, v_org_id, 'M9901', 'TestMan1', 'Test Man One', 'One, Test Man', 'married', v_status_active_id, current_date - 30, 'active', false);

  v_member_2_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_member_2_id, v_org_id, 'M9902', 'TestMan2', 'Test Man Two', 'Two, Test Man', 'married', v_status_active_id, current_date - 30, 'active', false);

  -- First assignment: succeeds
  v_assign_1_id := gen_random_uuid();
  INSERT INTO public.leadership_assignments (
    id, organization_id, member_id, governance_node_id, leadership_role_definition_id,
    assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at
  ) VALUES (
    v_assign_1_id, v_org_id, v_member_1_id, v_node_hh_id, v_role_hsl_id,
    'active', 'regular', current_date - 10, now(), now(), now(), now()
  );

  -- Second concurrent assignment: MUST be blocked
  v_blocked := false;
  BEGIN
    v_assign_2_id := gen_random_uuid();
    INSERT INTO public.leadership_assignments (
      id, organization_id, member_id, governance_node_id, leadership_role_definition_id,
      assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at
    ) VALUES (
      v_assign_2_id, v_org_id, v_member_2_id, v_node_hh_id, v_role_hsl_id,
      'active', 'regular', current_date - 5, now(), now(), now(), now()
    );
  EXCEPTION WHEN sqlstate '23514' THEN
    v_blocked := true;
  END;

  ASSERT v_blocked = true, 'Test 4 FAILED: Second concurrent assignment was NOT blocked by cardinality constraint!';
  RAISE NOTICE 'Test 4 PASSED: Second concurrent active assignment correctly blocked.';

  -- ---------------------------------------------------------------------------
  -- Test 5: couple_pair is NOT required (requires_couple_pair = false)
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.leadership_role_definitions
  WHERE organization_id = v_org_id
    AND code IN ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    AND requires_couple_pair = true;
  ASSERT v_count = 0, 'Test 5 FAILED: requires_couple_pair must be false for all canonical roles';
  RAISE NOTICE 'Test 5 PASSED: requires_couple_pair is false across all canonical roles.';

  -- ---------------------------------------------------------------------------
  -- Test 6: Zero application authorization / app_roles granted
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.profile_role_assignments pra
  JOIN public.profiles p ON p.id = pra.profile_id
  WHERE p.id IN (v_member_1_id, v_member_2_id);
  ASSERT v_count = 0, 'Test 6 FAILED: Pastoral assignment created software permissions!';
  RAISE NOTICE 'Test 6 PASSED: Pastoral assignment created zero software authorization.';

  -- ---------------------------------------------------------------------------
  -- Test 7: Legacy pastoral role codes are NOT seeded
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.leadership_role_definitions
  WHERE organization_id = v_org_id
    AND code IN ('household_servant', 'H-SERV', 'unit_leader', 'chapter_leader', 'area_leader', 'area_head');
  ASSERT v_count = 0, 'Test 7 FAILED: Legacy pastoral role code found in leadership_role_definitions!';
  RAISE NOTICE 'Test 7 PASSED: Zero legacy pastoral role codes seeded in database.';

  -- ---------------------------------------------------------------------------
  -- Test 8: Software app_roles remain untouched
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.app_roles
  WHERE code IN ('area_servant', 'chapter_servant', 'unit_servant', 'household_servant');
  ASSERT v_count = 4, 'Test 8 FAILED: Software app_roles modified or missing!';
  RAISE NOTICE 'Test 8 PASSED: Software app_roles remain untouched.';

  -- ---------------------------------------------------------------------------
  -- Test 9: Profile derives Household Leaders using canonical household_servant_leader
  -- ---------------------------------------------------------------------------
  -- Create wife & spouse relationship
  v_member_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_member_wife_id, v_org_id, 'M9903', 'TestWife', 'Test Wife One', 'One, Test Wife', 'married', v_status_active_id, current_date - 30, 'active', false);

  -- Memberships in household
  INSERT INTO public.household_memberships (organization_id, member_id, household_node_id, membership_status, membership_role, effective_from, is_primary)
  VALUES
    (v_org_id, v_member_1_id, v_node_hh_id, 'active', 'servant', current_date - 10, true),
    (v_org_id, v_member_wife_id, v_node_hh_id, 'active', 'member', current_date - 10, true);

  -- Family & verified spouse relationship
  v_family_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name)
  VALUES (v_family_id, v_org_id, 'One Family', 'The One Family');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES
    (v_org_id, v_family_id, v_member_1_id, 'spouse', 'active', current_date - 30),
    (v_org_id, v_family_id, v_member_wife_id, 'spouse', 'active', current_date - 30);

  SELECT id INTO STRICT v_rel_type_spouse_id FROM public.family_relationship_types WHERE code = 'spouse' LIMIT 1;

  v_rel_id := gen_random_uuid();
  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    v_rel_id, v_org_id, v_family_id,
    least(v_member_1_id, v_member_wife_id), greatest(v_member_1_id, v_member_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  -- Execute profile RPC
  v_profile_json := public.get_household_profile(v_org_id, v_node_hh_id);
  v_household_leaders := v_profile_json->'household_leaders';
  ASSERT v_household_leaders IS NOT NULL, 'Test 9 FAILED: household_leaders is null using canonical role';
  ASSERT v_household_leaders->'husband'->>'member_id' = v_member_1_id::text, 'Test 9 FAILED: husband member_id mismatch';
  ASSERT v_household_leaders->'wife'->>'member_id' = v_member_wife_id::text, 'Test 9 FAILED: wife member_id mismatch';
  ASSERT v_household_leaders->>'formatted_names' = 'Test Man One & Test Wife One', 'Test 9 FAILED: formatted_names mismatch';
  RAISE NOTICE 'Test 9 PASSED: get_household_profile derives Household Leaders using canonical household_servant_leader.';

  RAISE NOTICE 'ALL CANONICAL LEADERSHIP ROLE DEFINITION TESTS PASSED SUCCESSFULLY.';
END $$;

ROLLBACK;

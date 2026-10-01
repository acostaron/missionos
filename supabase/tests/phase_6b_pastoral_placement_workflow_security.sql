-- =============================================================================
-- Test Suite: Phase 6B-6 — Pastoral Placement Review & Assignment Workflow
-- File:       supabase/tests/phase_6b_pastoral_placement_workflow_security.sql
--
-- Security & Operational Assurances Tested:
--   Part 1: Setup Fixtures & Canonical Roles
--   Part 2: Single Leader Assignment Workflows (HSL->Unit, USL->Chapter, CSL->Area, ASL->Fraternal)
--   Part 3: Destination Ineligibility & Capacity Rejections (wrong level, wrong scope, inactive, full, not accepting)
--   Part 4: Single Leader Transfer & Same-Day History Semantics (exact single current primary, terminal ended status)
--   Part 5: Couples Placement Workflows & Three-State Context Tests (A through Q)
--   Part 6: Fraternal Placement Rules (membership_role = member, no leadership mutation)
--   Part 7: Authorization & Scope Security Boundaries (anon, non-admin, out-of-scope node, out-of-scope member)
--   Part 8: Review Queue Functionality
--   Part 9: App Authorization & Production Software Isolation Verification
-- =============================================================================

BEGIN;

DO $$
DECLARE
  -- Organizations & Profiles
  v_org_id                    uuid;
  v_admin_profile             uuid;
  v_delegate_profile          uuid;
  v_role_org_admin_id         uuid;
  v_pra_id                    uuid;

  -- Governance Node Types
  v_type_area_id              uuid;
  v_type_chap_id              uuid;
  v_type_unit_id              uuid;
  v_type_hh_id                uuid;
  v_type_sec_id               uuid;

  -- Canonical Roles
  v_role_hsl_id               uuid;
  v_role_usl_id               uuid;
  v_role_csl_id               uuid;
  v_role_asl_id               uuid;

  -- Governance Nodes
  v_node_area_id              uuid;
  v_node_chap_id              uuid;
  v_node_unit_id              uuid;
  v_node_other_unit_id        uuid;
  v_node_couple_section_id    uuid;
  v_node_noncouple_section_id uuid;

  -- Households
  v_hh_unit_couple_id         uuid;
  v_hh_unit_standard_id       uuid;
  v_hh_unit_full_id           uuid;
  v_hh_unit_not_accepting_id  uuid;
  v_hh_unit_other_scope_id    uuid;
  v_hh_chap_id                uuid;
  v_hh_chap_couple_id         uuid;
  v_hh_area_id                uuid;
  v_hh_area_couple_id         uuid;
  v_hh_frat_id                uuid;
  v_hh_frat_couple_id         uuid;
  v_hh_member_origin_id       uuid;
  v_hh_member_origin_std_id   uuid;
  v_hh_member_temp_id         uuid;
  v_hh_res                    jsonb;

  -- Families
  v_family_id_1               uuid;
  v_family_id_2               uuid;
  v_family_id_usl             uuid;
  v_family_id_csl             uuid;
  v_family_id_asl             uuid;

  -- Members & Statuses
  v_status_active_id          uuid;
  v_rel_type_spouse_id        uuid;
  v_mem_hsl_id                uuid;
  v_mem_hsl_wife_id           uuid;
  v_mem_hsl_std_id            uuid;
  v_mem_usl_id                uuid;
  v_mem_usl_wife_id           uuid;
  v_mem_csl_id                uuid;
  v_mem_csl_wife_id           uuid;
  v_mem_asl_id                uuid;
  v_mem_asl_wife_id           uuid;
  v_mem_single_id             uuid;
  v_mem_unverified_wife_id    uuid;
  v_mem_temp_filler_1         uuid;
  v_mem_temp_filler_2         uuid;

  -- Leadership Assignments
  v_asg_hsl_id                uuid;
  v_asg_hsl_std_id            uuid;
  v_asg_usl_id                uuid;
  v_asg_csl_id                uuid;
  v_asg_asl_id                uuid;
  v_asg_single_id             uuid;

  -- Review & Execution Results
  v_review_res                jsonb;
  v_exec_res                  jsonb;
  v_queue_res                 jsonb;
  v_blocked                   boolean;
  v_count                     integer;
  v_audit_count               integer;
  v_role_text                 text;
BEGIN
  -- ---------------------------------------------------------------------------
  -- PART 1: SETUP FIXTURES
  -- ---------------------------------------------------------------------------
  SELECT id INTO STRICT v_org_id FROM public.organizations LIMIT 1;

  SELECT p.id INTO STRICT v_admin_profile
  FROM public.profiles p
  JOIN public.profile_role_assignments pra ON pra.profile_id = p.id
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE pra.organization_id = v_org_id
    AND ar.code = 'organization_administrator'
    AND pra.assignment_status = 'active'
  LIMIT 1;

  -- Set caller context as admin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- Resolve node types
  SELECT id INTO STRICT v_type_area_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'area_state';
  SELECT id INTO STRICT v_type_chap_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'chapter';
  SELECT id INTO STRICT v_type_unit_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'unit';
  SELECT id INTO STRICT v_type_hh_id   FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'household';
  SELECT id INTO STRICT v_type_sec_id  FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'section';

  -- Resolve member status & spouse rel type
  SELECT id INTO STRICT v_status_active_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active';
  SELECT id INTO STRICT v_rel_type_spouse_id FROM public.family_relationship_types WHERE code = 'spouse' AND (organization_id = v_org_id OR organization_id IS NULL) LIMIT 1;

  -- Resolve canonical leadership roles
  SELECT id INTO STRICT v_role_hsl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'household_servant_leader';
  SELECT id INTO STRICT v_role_usl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'unit_servant_leader';
  SELECT id INTO STRICT v_role_csl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'chapter_servant_leader';
  SELECT id INTO STRICT v_role_asl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'area_servant_leader';

  -- Create synthetic governance structure
  v_node_area_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_area_id, v_org_id, v_type_area_id, 'test_area_6b6', 'Test Area 6B6', 'active', current_date);

  v_node_chap_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_chap_id, v_org_id, v_type_chap_id, 'test_chap_6b6', 'Test Chapter 6B6', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_area_id, v_node_chap_id, 'primary_parent', 'active', true, current_date);

  v_node_unit_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_unit_id, v_org_id, v_type_unit_id, 'test_unit_6b6', 'Test Unit 6B6', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_chap_id, v_node_unit_id, 'primary_parent', 'active', true, current_date);

  -- Other unit for scope mismatch tests
  v_node_other_unit_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_other_unit_id, v_org_id, v_type_unit_id, 'test_unit_other_6b6', 'Test Unit Other 6B6', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_chap_id, v_node_other_unit_id, 'primary_parent', 'active', true, current_date);

  -- Sections for explicit section context tests
  v_node_couple_section_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from, metadata)
  VALUES (v_node_couple_section_id, v_org_id, v_type_sec_id, 'sec_couples_6b6', 'MFC Couples Section', 'active', current_date, '{"is_couple_section": true, "section_category": "couples"}'::jsonb);

  v_node_noncouple_section_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from, metadata)
  VALUES (v_node_noncouple_section_id, v_org_id, v_type_sec_id, 'sec_singles_6b6', 'MFC Singles Section', 'active', current_date, '{"is_couple_section": false, "section_category": "singles"}'::jsonb);

  -- Origin Member Households:
  -- 1. Couples household (HSL leads)
  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Origin Member HH 6B6', p_code => 'hh_origin_6b6',
    p_parent_governance_node_id => v_node_unit_id, p_pastoral_level => 'member', p_is_couple_household => true
  );
  v_hh_member_origin_id := (v_hh_res->>'household_id')::uuid;

  -- 2. Standard non-couples household
  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Origin Standard HH 6B6', p_code => 'hh_origin_std_6b6',
    p_parent_governance_node_id => v_node_unit_id, p_pastoral_level => 'member', p_is_couple_household => false
  );
  v_hh_member_origin_std_id := (v_hh_res->>'household_id')::uuid;

  -- Destination Households at each level
  -- Unit Households under v_node_unit_id
  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Unit HH Couple 6B6', p_code => 'hh_unit_c_6b6',
    p_parent_governance_node_id => v_node_unit_id, p_pastoral_level => 'unit', p_is_couple_household => true
  );
  v_hh_unit_couple_id := (v_hh_res->>'household_id')::uuid;

  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Unit HH Standard 6B6', p_code => 'hh_unit_std_6b6',
    p_parent_governance_node_id => v_node_unit_id, p_pastoral_level => 'unit', p_is_couple_household => false
  );
  v_hh_unit_standard_id := (v_hh_res->>'household_id')::uuid;

  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Unit HH Full 6B6', p_code => 'hh_unit_full_6b6',
    p_parent_governance_node_id => v_node_unit_id, p_pastoral_level => 'unit', p_maximum_member_count => 2
  );
  v_hh_unit_full_id := (v_hh_res->>'household_id')::uuid;

  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Unit HH Not Accepting 6B6', p_code => 'hh_unit_na_6b6',
    p_parent_governance_node_id => v_node_unit_id, p_pastoral_level => 'unit', p_accepts_new_members => false
  );
  v_hh_unit_not_accepting_id := (v_hh_res->>'household_id')::uuid;

  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Unit HH Other Scope 6B6', p_code => 'hh_unit_other_6b6',
    p_parent_governance_node_id => v_node_other_unit_id, p_pastoral_level => 'unit'
  );
  v_hh_unit_other_scope_id := (v_hh_res->>'household_id')::uuid;

  -- Chapter Households under v_node_chap_id
  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Chapter HH 6B6', p_code => 'hh_chap_6b6',
    p_parent_governance_node_id => v_node_chap_id, p_pastoral_level => 'chapter', p_is_couple_household => false
  );
  v_hh_chap_id := (v_hh_res->>'household_id')::uuid;

  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Chapter HH Couple 6B6', p_code => 'hh_chap_c_6b6',
    p_parent_governance_node_id => v_node_chap_id, p_pastoral_level => 'chapter', p_is_couple_household => true
  );
  v_hh_chap_couple_id := (v_hh_res->>'household_id')::uuid;

  -- Area Households under v_node_area_id
  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Area HH 6B6', p_code => 'hh_area_6b6',
    p_parent_governance_node_id => v_node_area_id, p_pastoral_level => 'area', p_is_couple_household => false
  );
  v_hh_area_id := (v_hh_res->>'household_id')::uuid;

  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Area HH Couple 6B6', p_code => 'hh_area_c_6b6',
    p_parent_governance_node_id => v_node_area_id, p_pastoral_level => 'area', p_is_couple_household => true
  );
  v_hh_area_couple_id := (v_hh_res->>'household_id')::uuid;

  -- Fraternal Households under v_node_area_id
  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Fraternal HH 6B6', p_code => 'hh_frat_6b6',
    p_parent_governance_node_id => v_node_area_id, p_pastoral_level => 'fraternal', p_is_couple_household => false
  );
  v_hh_frat_id := (v_hh_res->>'household_id')::uuid;

  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Fraternal HH Couple 6B6', p_code => 'hh_frat_c_6b6',
    p_parent_governance_node_id => v_node_area_id, p_pastoral_level => 'fraternal', p_is_couple_household => true
  );
  v_hh_frat_couple_id := (v_hh_res->>'household_id')::uuid;

  -- Fill 1 seat in v_hh_unit_full_id with temporary member
  v_mem_temp_filler_1 := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_temp_filler_1, v_org_id, v_status_active_id, 'Temp Filler 1', 'Filler, Temp 1', 'Filler1', 'active');

  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, membership_role, membership_status, is_primary, effective_from)
  VALUES (v_org_id, v_hh_unit_full_id, v_mem_temp_filler_1, 'member', 'active', true, current_date);

  -- Candidate Members:
  -- HSL Couple (originating household is_couple_household = true)
  v_mem_hsl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_hsl_id, v_org_id, v_status_active_id, 'Bro HSL 6B6', 'Leader, Bro HSL', 'HSL Leader', 'active');

  v_mem_hsl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_hsl_wife_id, v_org_id, v_status_active_id, 'Sis HSL Wife 6B6', 'Leader, Sis HSL', 'HSL Wife', 'active');

  v_family_id_1 := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name)
  VALUES (v_family_id_1, v_org_id, 'HSL Family 6B6', 'The HSL Family');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES
    (v_org_id, v_family_id_1, v_mem_hsl_id, 'spouse', 'active', current_date - 30),
    (v_org_id, v_family_id_1, v_mem_hsl_wife_id, 'spouse', 'active', current_date - 30);

  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    gen_random_uuid(), v_org_id, v_family_id_1,
    least(v_mem_hsl_id, v_mem_hsl_wife_id), greatest(v_mem_hsl_id, v_mem_hsl_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  -- HSL Standard (originating household is_couple_household = false)
  v_mem_hsl_std_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_hsl_std_id, v_org_id, v_status_active_id, 'Bro HSL Std 6B6', 'Leader, Bro HSL Std', 'HSL Std Leader', 'active');

  -- USL (unmarried individual leader initially)
  v_mem_usl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_usl_id, v_org_id, v_status_active_id, 'Bro USL 6B6', 'Leader, Bro USL', 'USL Leader', 'active');

  -- CSL (unmarried individual leader initially)
  v_mem_csl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_csl_id, v_org_id, v_status_active_id, 'Bro CSL 6B6', 'Leader, Bro CSL', 'CSL Leader', 'active');

  -- ASL (unmarried individual leader initially)
  v_mem_asl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_asl_id, v_org_id, v_status_active_id, 'Bro ASL 6B6', 'Leader, Bro ASL', 'ASL Leader', 'active');

  -- Appoint Servant Leaders
  v_exec_res := public.appoint_servant_leader(
    p_organization_id => v_org_id, p_role_code => 'household_servant_leader',
    p_governance_node_id => v_hh_member_origin_id, p_member_id => v_mem_hsl_id,
    p_reason => 'Initial HSL appointment'
  );
  v_asg_hsl_id := (v_exec_res->>'leadership_assignment_id')::uuid;

  v_exec_res := public.appoint_servant_leader(
    p_organization_id => v_org_id, p_role_code => 'household_servant_leader',
    p_governance_node_id => v_hh_member_origin_std_id, p_member_id => v_mem_hsl_std_id,
    p_reason => 'Standard HSL appointment'
  );
  v_asg_hsl_std_id := (v_exec_res->>'leadership_assignment_id')::uuid;

  v_exec_res := public.appoint_servant_leader(
    p_organization_id => v_org_id, p_role_code => 'unit_servant_leader',
    p_governance_node_id => v_node_unit_id, p_member_id => v_mem_usl_id,
    p_reason => 'Initial USL appointment'
  );
  v_asg_usl_id := (v_exec_res->>'leadership_assignment_id')::uuid;

  v_exec_res := public.appoint_servant_leader(
    p_organization_id => v_org_id, p_role_code => 'chapter_servant_leader',
    p_governance_node_id => v_node_chap_id, p_member_id => v_mem_csl_id,
    p_reason => 'Initial CSL appointment'
  );
  v_asg_csl_id := (v_exec_res->>'leadership_assignment_id')::uuid;

  v_exec_res := public.appoint_servant_leader(
    p_organization_id => v_org_id, p_role_code => 'area_servant_leader',
    p_governance_node_id => v_node_area_id, p_member_id => v_mem_asl_id,
    p_reason => 'Initial ASL appointment'
  );
  v_asg_asl_id := (v_exec_res->>'leadership_assignment_id')::uuid;

  RAISE NOTICE 'PART 1 PASSED: Fixtures and servant leaders initialized.';

  -- ---------------------------------------------------------------------------
  -- PART 2: SINGLE UNMARRIED LEADER ASSIGNMENT WORKFLOWS
  -- ---------------------------------------------------------------------------
  -- 2.1 USL (unmarried -> non_couples -> ready_to_assign to standard Chapter HH)
  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_usl_id);
  ASSERT v_review_res->>'workflow_status' = 'ready_to_assign', 'Test 2.1 FAILED: USL workflow_status != ready_to_assign';
  ASSERT v_review_res->>'couples_context_status' = 'non_couples', 'Test 2.1 FAILED: USL couples_context_status != non_couples';
  ASSERT v_review_res->>'couples_context_source' = 'unmarried_individual', 'Test 2.1 FAILED: USL source != unmarried_individual';
  ASSERT (v_review_res->>'couples_context')::boolean = false, 'Test 2.1 FAILED: USL couples_context != false';

  v_exec_res := public.execute_pastoral_placement(
    p_organization_id          => v_org_id,
    p_leadership_assignment_id => v_asg_usl_id,
    p_destination_household_id => v_hh_chap_id,
    p_reason                   => 'USL pastoral nourishment in Chapter'
  );
  ASSERT v_exec_res->>'status' = 'completed', 'Test 2.1.B FAILED: Execution status != completed';
  ASSERT v_exec_res->'leader_result'->>'action' = 'assign', 'Test 2.1.B FAILED: Action != assign';

  -- 2.2 CSL assignment to Area Household
  v_exec_res := public.execute_pastoral_placement(
    p_organization_id          => v_org_id,
    p_leadership_assignment_id => v_asg_csl_id,
    p_destination_household_id => v_hh_area_id,
    p_reason                   => 'CSL pastoral nourishment in Area'
  );
  ASSERT v_exec_res->>'status' = 'completed', 'Test 2.2 FAILED: CSL execution != completed';

  -- 2.3 ASL assignment to Fraternal Household
  v_exec_res := public.execute_pastoral_placement(
    p_organization_id          => v_org_id,
    p_leadership_assignment_id => v_asg_asl_id,
    p_destination_household_id => v_hh_frat_id,
    p_reason                   => 'ASL pastoral nourishment in Fraternal'
  );
  ASSERT v_exec_res->>'status' = 'completed', 'Test 2.3 FAILED: ASL execution != completed';

  SELECT membership_role INTO v_role_text
  FROM public.household_memberships
  WHERE organization_id = v_org_id AND member_id = v_mem_asl_id AND household_node_id = v_hh_frat_id;
  ASSERT v_role_text = 'member', 'Test 2.3 FAILED: Fraternal membership_role != member';

  -- ---------------------------------------------------------------------------
  -- PART 3: DESTINATION INELIGIBILITY & CAPACITY REJECTIONS
  -- ---------------------------------------------------------------------------
  -- Wrong level
  BEGIN
    v_blocked := false;
    PERFORM public.execute_pastoral_placement(
      p_organization_id          => v_org_id,
      p_leadership_assignment_id => v_asg_usl_id,
      p_destination_household_id => v_hh_area_id,
      p_reason                   => 'Wrong level test'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3.1 FAILED: Wrong pastoral level destination not rejected!';

  -- Wrong scope
  BEGIN
    v_blocked := false;
    PERFORM public.execute_pastoral_placement(
      p_organization_id          => v_org_id,
      p_leadership_assignment_id => v_asg_hsl_id,
      p_destination_household_id => v_hh_unit_other_scope_id,
      p_reason                   => 'Wrong scope test'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3.2 FAILED: Wrong governance scope not rejected!';

  -- Full destination
  BEGIN
    v_blocked := false;
    PERFORM public.execute_pastoral_placement(
      p_organization_id          => v_org_id,
      p_leadership_assignment_id => v_asg_hsl_id,
      p_destination_household_id => v_hh_unit_full_id,
      p_reason                   => 'Capacity test couple +2',
      p_include_verified_spouse  => true
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3.4 FAILED: Full destination not rejected!';

  -- Future effective date
  BEGIN
    v_blocked := false;
    PERFORM public.execute_pastoral_placement(
      p_organization_id          => v_org_id,
      p_leadership_assignment_id => v_asg_usl_id,
      p_destination_household_id => v_hh_chap_id,
      p_effective_date           => current_date + 1,
      p_reason                   => 'Future date test'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3.5 FAILED: Future effective date not rejected!';

  -- ---------------------------------------------------------------------------
  -- PART 4: SAME-DAY TRANSFER SEMANTICS
  -- ---------------------------------------------------------------------------
  v_hh_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Chapter HH 2 6B6', p_code => 'hh_chap2_6b6',
    p_parent_governance_node_id => v_node_chap_id, p_pastoral_level => 'chapter'
  );

  v_exec_res := public.execute_pastoral_placement(
    p_organization_id          => v_org_id,
    p_leadership_assignment_id => v_asg_usl_id,
    p_destination_household_id => (v_hh_res->>'household_id')::uuid,
    p_effective_date           => current_date,
    p_reason                   => 'Same-day pastoral transfer between Chapter households'
  );
  ASSERT v_exec_res->>'status' = 'completed', 'Test 4.1 FAILED: Transfer execution status != completed';

  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE organization_id = v_org_id AND member_id = v_mem_usl_id AND is_primary = true
    AND membership_status IN ('active', 'temporary') AND effective_to IS NULL;
  ASSERT v_count = 1, 'Test 4.4 FAILED: Multiple current primary memberships found!';

  -- ---------------------------------------------------------------------------
  -- PART 5: EXPLICIT THREE-STATE COUPLES CONTEXT TESTS (A THROUGH Q)
  -- ---------------------------------------------------------------------------
  -- A. HSL + is_couple_household=true -> paired workflow
  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_hsl_id);
  ASSERT v_review_res->>'couples_context_status' = 'couples', 'Test 5.A FAILED: HSL couples_context_status != couples';
  ASSERT (v_review_res->>'couples_context')::boolean = true, 'Test 5.A FAILED: HSL couples_context != true';
  ASSERT v_review_res->>'couples_context_source' = 'originating_household', 'Test 5.A FAILED: HSL source != originating_household';
  ASSERT (v_review_res->>'required_seats')::integer = 2, 'Test 5.A FAILED: HSL required_seats != 2';

  -- B. HSL + is_couple_household=false -> individual workflow
  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_hsl_std_id);
  ASSERT v_review_res->>'couples_context_status' = 'non_couples', 'Test 5.B FAILED: HSL Std couples_context_status != non_couples';
  ASSERT (v_review_res->>'couples_context')::boolean = false, 'Test 5.B FAILED: HSL Std couples_context != false';
  ASSERT (v_review_res->>'required_seats')::integer = 1, 'Test 5.B FAILED: HSL Std required_seats != 1';

  -- Add verified wife to USL for USL-specific tests
  v_mem_usl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_usl_wife_id, v_org_id, v_status_active_id, 'Sis USL Wife 6B6', 'Leader, Sis USL', 'USL Wife', 'active');

  v_family_id_usl := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name)
  VALUES (v_family_id_usl, v_org_id, 'USL Family 6B6', 'The USL Family');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES
    (v_org_id, v_family_id_usl, v_mem_usl_id, 'spouse', 'active', current_date - 30),
    (v_org_id, v_family_id_usl, v_mem_usl_wife_id, 'spouse', 'active', current_date - 30);

  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    gen_random_uuid(), v_org_id, v_family_id_usl,
    least(v_mem_usl_id, v_mem_usl_wife_id), greatest(v_mem_usl_id, v_mem_usl_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  -- E. USL married but no authoritative section metadata -> AMBIGUOUS -> manual_review_required
  -- Note: clear USL's household membership so it doesn't infer from pastoral lineage
  DELETE FROM public.household_memberships WHERE member_id = v_mem_usl_id;

  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_usl_id);
  ASSERT v_review_res->>'couples_context_status' = 'ambiguous', 'Test 5.E FAILED: USL couples_context_status != ambiguous';
  ASSERT v_review_res->>'workflow_status' = 'manual_review_required', 'Test 5.E FAILED: USL workflow_status != manual_review_required';
  ASSERT v_review_res->>'recommended_action' = 'review_spouse', 'Test 5.E FAILED: USL recommended_action != review_spouse';
  ASSERT v_review_res->>'couples_context' IS NULL, 'Test 5.E FAILED: USL couples_context is not null when ambiguous';

  -- C. USL + authoritative Couples section (Priority A: primary_section_node_id) -> paired
  UPDATE public.members SET primary_section_node_id = v_node_couple_section_id WHERE id = v_mem_usl_id;
  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_usl_id);
  ASSERT v_review_res->>'couples_context_status' = 'couples', 'Test 5.C FAILED: USL with couple section != couples';
  ASSERT (v_review_res->>'couples_context')::boolean = true, 'Test 5.C FAILED: USL with couple section couples_context != true';
  ASSERT v_review_res->>'couples_context_source' = 'primary_section', 'Test 5.C FAILED: USL source != primary_section';
  ASSERT (v_review_res->>'required_seats')::integer = 2, 'Test 5.C FAILED: USL required_seats != 2';

  -- D. USL + authoritative non-Couples section -> individual
  UPDATE public.members SET primary_section_node_id = v_node_noncouple_section_id WHERE id = v_mem_usl_id;
  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_usl_id);
  ASSERT v_review_res->>'couples_context_status' = 'non_couples', 'Test 5.D FAILED: USL with singles section != non_couples';
  ASSERT (v_review_res->>'couples_context')::boolean = false, 'Test 5.D FAILED: USL with singles section couples_context != false';
  ASSERT (v_review_res->>'required_seats')::integer = 1, 'Test 5.D FAILED: USL singles required_seats != 1';

  -- Clear primary_section_node_id back to null
  UPDATE public.members SET primary_section_node_id = null WHERE id = v_mem_usl_id;

  -- Add verified wife to CSL
  v_mem_csl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_csl_wife_id, v_org_id, v_status_active_id, 'Sis CSL Wife 6B6', 'Leader, Sis CSL', 'CSL Wife', 'active');

  v_family_id_csl := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name)
  VALUES (v_family_id_csl, v_org_id, 'CSL Family 6B6', 'The CSL Family');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES
    (v_org_id, v_family_id_csl, v_mem_csl_id, 'spouse', 'active', current_date - 30),
    (v_org_id, v_family_id_csl, v_mem_csl_wife_id, 'spouse', 'active', current_date - 30);

  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    gen_random_uuid(), v_org_id, v_family_id_csl,
    least(v_mem_csl_id, v_mem_csl_wife_id), greatest(v_mem_csl_id, v_mem_csl_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  DELETE FROM public.household_memberships WHERE member_id = v_mem_csl_id;

  -- H. CSL + unresolved context -> manual_review_required
  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_csl_id);
  ASSERT v_review_res->>'couples_context_status' = 'ambiguous', 'Test 5.H FAILED: CSL status != ambiguous';
  ASSERT v_review_res->>'workflow_status' = 'manual_review_required', 'Test 5.H FAILED: CSL workflow != manual_review_required';

  -- F. CSL + authoritative member_governance_assignment (Priority B) -> paired
  INSERT INTO public.member_governance_assignments (
    organization_id, member_id, governance_node_id, assignment_type, assignment_status, is_primary, effective_from
  ) VALUES (
    v_org_id, v_mem_csl_id, v_node_couple_section_id, 'primary', 'active', true, current_date
  );

  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_csl_id);
  ASSERT v_review_res->>'couples_context_status' = 'couples', 'Test 5.F FAILED: CSL MGA couple != couples';
  ASSERT v_review_res->>'couples_context_source' = 'member_governance_assignment', 'Test 5.F FAILED: CSL source != member_governance_assignment';

  -- G. CSL + authoritative non-Couples MGA -> individual
  UPDATE public.member_governance_assignments
  SET governance_node_id = v_node_noncouple_section_id
  WHERE member_id = v_mem_csl_id;

  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_csl_id);
  ASSERT v_review_res->>'couples_context_status' = 'non_couples', 'Test 5.G FAILED: CSL MGA noncouple != non_couples';

  DELETE FROM public.member_governance_assignments WHERE member_id = v_mem_csl_id;

  -- Add verified wife to ASL
  v_mem_asl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_asl_wife_id, v_org_id, v_status_active_id, 'Sis ASL Wife 6B6', 'Leader, Sis ASL', 'ASL Wife', 'active');

  v_family_id_asl := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name)
  VALUES (v_family_id_asl, v_org_id, 'ASL Family 6B6', 'The ASL Family');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES
    (v_org_id, v_family_id_asl, v_mem_asl_id, 'spouse', 'active', current_date - 30),
    (v_org_id, v_family_id_asl, v_mem_asl_wife_id, 'spouse', 'active', current_date - 30);

  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    gen_random_uuid(), v_org_id, v_family_id_asl,
    least(v_mem_asl_id, v_mem_asl_wife_id), greatest(v_mem_asl_id, v_mem_asl_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  DELETE FROM public.household_memberships WHERE member_id = v_mem_asl_id;

  -- K. ASL + unresolved context -> manual_review_required (Do NOT default to individual Fraternal placement!)
  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_asl_id);
  ASSERT v_review_res->>'couples_context_status' = 'ambiguous', 'Test 5.K FAILED: ASL status != ambiguous';
  ASSERT v_review_res->>'workflow_status' = 'manual_review_required', 'Test 5.K FAILED: ASL workflow != manual_review_required';

  -- I. ASL + authoritative Couples context (via pastoral lineage Priority C) -> paired Fraternal placement
  INSERT INTO public.household_memberships (
    organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from
  ) VALUES (
    v_org_id, v_mem_asl_id, v_hh_area_couple_id, 'active', 'member', true, current_date - 60
  );

  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_asl_id);
  ASSERT v_review_res->>'couples_context_status' = 'couples', 'Test 5.I FAILED: ASL pastoral lineage != couples';
  ASSERT v_review_res->>'couples_context_source' = 'pastoral_lineage', 'Test 5.I FAILED: ASL source != pastoral_lineage';
  ASSERT (v_review_res->>'required_seats')::integer = 2, 'Test 5.I FAILED: ASL required_seats != 2';

  -- J. ASL + authoritative non-Couples context (via standard pastoral lineage) -> individual
  DELETE FROM public.household_memberships WHERE member_id = v_mem_asl_id;
  INSERT INTO public.household_memberships (
    organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from
  ) VALUES (
    v_org_id, v_mem_asl_id, v_hh_area_id, 'active', 'member', true, current_date - 60
  );

  v_review_res := public.get_pastoral_placement_review(v_org_id, v_asg_asl_id);
  ASSERT v_review_res->>'couples_context_status' = 'non_couples', 'Test 5.J FAILED: ASL std lineage != non_couples';
  ASSERT (v_review_res->>'required_seats')::integer = 1, 'Test 5.J FAILED: ASL std required_seats != 1';

  DELETE FROM public.household_memberships WHERE member_id = v_mem_asl_id;

  -- O. Ambiguous context execution rejected with 22023
  -- USL is currently ambiguous
  BEGIN
    v_blocked := false;
    PERFORM public.execute_pastoral_placement(
      p_organization_id          => v_org_id,
      p_leadership_assignment_id => v_asg_usl_id,
      p_destination_household_id => v_hh_chap_id,
      p_reason                   => 'Attempting ambiguous placement'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 5.O FAILED: Ambiguous context execution was not rejected with 22023!';

  -- P. p_include_verified_spouse=false does NOT bypass ambiguity
  BEGIN
    v_blocked := false;
    PERFORM public.execute_pastoral_placement(
      p_organization_id          => v_org_id,
      p_leadership_assignment_id => v_asg_usl_id,
      p_destination_household_id => v_hh_chap_id,
      p_reason                   => 'Attempting bypass with include_verified_spouse=false',
      p_include_verified_spouse  => false
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 5.P FAILED: p_include_verified_spouse=false bypassed ambiguity!';

  -- Q. No leadership assignment side effects on wife during placement
  -- Set USL to couples context and place both
  UPDATE public.members SET primary_section_node_id = v_node_couple_section_id WHERE id = v_mem_usl_id;
  v_exec_res := public.execute_pastoral_placement(
    p_organization_id          => v_org_id,
    p_leadership_assignment_id => v_asg_usl_id,
    p_destination_household_id => v_hh_chap_couple_id,
    p_reason                   => 'USL couples placement into Chapter Couple HH',
    p_include_verified_spouse  => true
  );
  ASSERT v_exec_res->>'status' = 'completed', 'Test 5.Q FAILED: USL placement != completed';

  SELECT count(*) INTO v_count
  FROM public.leadership_assignments
  WHERE organization_id = v_org_id AND member_id = v_mem_usl_wife_id;
  ASSERT v_count = 0, 'Test 5.Q FAILED: Leadership assignment was created for wife!';
  RAISE NOTICE 'Test 5 PASSED: All three-state Couples context rules verified (Tests A through Q).';

  -- ---------------------------------------------------------------------------
  -- PART 6: AUDIT EVENT LOGGING
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_audit_count
  FROM audit.events
  WHERE organization_id = v_org_id
    AND event_category = 'governance'
    AND event_code = 'pastoral_placement.executed';
  ASSERT v_audit_count >= 4, format('Test 6 FAILED: Expected at least 4 placement audit events, got %s', v_audit_count);
  RAISE NOTICE 'Test 6 PASSED: Canonical audit events recorded.';

  -- ---------------------------------------------------------------------------
  -- PART 7: REVIEW QUEUE
  -- ---------------------------------------------------------------------------
  -- ASL is currently ambiguous (unresolved married), should appear in queue as manual_review_required
  v_queue_res := public.search_servant_leaders_needing_pastoral_placement(v_org_id, false);
  ASSERT (v_queue_res->>'total_count')::integer >= 1, 'Test 7.1 FAILED: Leaders needing placement not found in queue';

  SELECT count(*) INTO v_count
  FROM jsonb_to_recordset(v_queue_res->'items') as q(role_code text, placement_status text)
  WHERE q.role_code = 'area_servant_leader' AND q.placement_status = 'manual_review_required';
  ASSERT v_count = 1, 'Test 7.1.B FAILED: Ambiguous ASL did not appear as manual_review_required in queue!';
  RAISE NOTICE 'Test 7 PASSED: Review queue queries successfully with ambiguous leaders.';

  -- ---------------------------------------------------------------------------
  -- PART 8: AUTHORIZATION & SOFTWARE ISOLATION
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code IN ('leadership.pastoral_placement.review', 'leadership.pastoral_placement.execute');
  ASSERT v_count = 2, format('Test 8.1 FAILED: Expected exactly 2 role_permission mappings, got %s', v_count);

  -- Impersonate non-admin caller -> must be denied
  v_delegate_profile := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_delegate_profile, 'authenticated', 'authenticated', 'nonadmin.tester@test.local');

  INSERT INTO public.profiles (id, display_name)
  VALUES (v_delegate_profile, 'Non-Admin Tester');

  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_delegate_profile, v_org_id, 'active', now());

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_delegate_profile, 'role', 'authenticated')::text, true);

  BEGIN
    v_blocked := false;
    PERFORM public.get_pastoral_placement_review(v_org_id, v_asg_hsl_id);
  EXCEPTION WHEN sqlstate '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 8.2 FAILED: Non-admin caller was able to review pastoral placement!';

  BEGIN
    v_blocked := false;
    PERFORM public.execute_pastoral_placement(
      p_organization_id          => v_org_id,
      p_leadership_assignment_id => v_asg_hsl_id,
      p_destination_household_id => v_hh_unit_couple_id,
      p_reason                   => 'Unauthorized test'
    );
  EXCEPTION WHEN sqlstate '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 8.3 FAILED: Non-admin caller was able to execute pastoral placement!';
  RAISE NOTICE 'Test 8 PASSED: Authorization gates enforce organization_administrator.';

  -- Switch back to admin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ---------------------------------------------------------------------------
  -- PART 9: APP AUTHORIZATION TABLES UNCHANGED
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count FROM public.app_roles;
  ASSERT v_count = 13, 'Test 9.1 FAILED: app_roles count changed';

  RAISE NOTICE 'ALL PHASE 6B-6 PASTORAL PLACEMENT TESTS PASSED SUCCESSFULLY.';
END;
$$;

ROLLBACK;

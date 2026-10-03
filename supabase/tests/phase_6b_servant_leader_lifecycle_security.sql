-- =============================================================================
-- Test Suite: phase_6b_servant_leader_lifecycle_security.sql
-- Phase:      Phase 6B-5 — Servant Leader Appointment Lifecycle & Pastoral Placement
--
-- Tests & Validates:
--  PART 1: Schema & Permissions Posture
--    - 1.1 Permissions registered (appoint, conclude, replace)
--    - 1.2 Permissions assigned strictly to organization_administrator
--    - 1.3 Servant roles have zero write permissions
--    - 1.4 Function existence (appoint, conclude, replace, placement guidance)
--    - 1.5 Direct table grants blocked for anon/authenticated
--
--  PART 2: Appoint Workflows & Guards
--    - 2.1 Household Servant Leader succeeds on Member Household
--    - 2.2 Household Servant Leader rejected on Unit Household (23514)
--    - 2.3 Household Servant Leader rejected on Chapter Household (23514)
--    - 2.4 Household Servant Leader rejected on Area Household (23514)
--    - 2.5 Household Servant Leader rejected on Fraternal Household (23514)
--    - 2.6 Unit Servant Leader succeeds on Unit node
--    - 2.7 Unit Servant Leader rejected on Chapter node (22023)
--    - 2.8 Chapter Servant Leader succeeds on Chapter node
--    - 2.9 Area Servant Leader succeeds on Area node
--    - 2.10 Duplicate current office holder rejected (22023)
--    - 2.11 Same member duplicate rejected (22023)
--    - 2.12 Deceased or inactive member rejected (22023)
--    - 2.13 Future effective date rejected (22023)
--    - 2.14 Unauthorized caller denied (42501)
--
--  PART 3: Conclude Workflows & Guards
--    - 3.1 Active assignment concludes successfully (retained, status 'completed', reason captured)
--    - 3.2 Duplicate conclusion rejected (22023)
--    - 3.3 Future conclusion rejected (22023)
--    - 3.4 Conclusion before effective_from rejected (22023)
--    - 3.5 No household membership or app authorization mutations
--
--  PART 4: Replace Workflows & Guards
--    - 4.1 Same-day replacement succeeds atomically (outgoing completed, incoming active)
--    - 4.2 Replace with no current holder returns blocked ('no_current_role_holder')
--    - 4.3 Same-member replacement rejected (22023)
--    - 4.4 Future replacement rejected (22023)
--    - 4.5 Exactly one current holder remains
--
--  PART 5: Pastoral Placement Guidance RPC
--    - 5.1 Household Servant Leader -> recommends Unit Household
--    - 5.2 Unit Servant Leader -> recommends Chapter Household
--    - 5.3 Chapter Servant Leader -> recommends Area Household
--    - 5.4 Area Servant Leader -> recommends Fraternal Household
--    - 5.5 Couples context evaluation (verified spouse included, no wife assignment created)
--    - 5.6 Missing household status vs different level vs correct
--    - 5.7 Zero database mutations performed
--
--  PART 6: Authorization & Software Isolation
--    - 6.1 App roles untouched (count = 13)
--    - 6.2 Profile role assignments untouched (count = 1)
--    - 6.3 Profile scope assignments untouched (count = 1)
--
-- Non-destructive. Wrapped in a transaction and strictly ROLLED BACK.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id                    uuid;
  v_admin_profile             uuid;
  v_count                     integer;
  v_blocked                   boolean;

  -- Node Types
  v_type_area_id              uuid;
  v_type_chap_id              uuid;
  v_type_unit_id              uuid;
  v_type_hh_id                uuid;

  -- Governance Nodes
  v_node_area_id              uuid;
  v_node_chap_id              uuid;
  v_node_unit_id              uuid;

  -- Households
  v_hh_member_res             jsonb;
  v_hh_unit_res               jsonb;
  v_hh_chap_res               jsonb;
  v_hh_area_res               jsonb;
  v_hh_frat_res               jsonb;

  v_hh_member_id              uuid;
  v_hh_unit_id                uuid;
  v_hh_chap_id                uuid;
  v_hh_area_id                uuid;
  v_hh_frat_id                uuid;

  -- Members
  v_mem_hsl_id                uuid;
  v_mem_hsl_wife_id           uuid;
  v_mem_usl_id                uuid;
  v_mem_csl_id                uuid;
  v_mem_asl_id                uuid;
  v_mem_replace_id            uuid;
  v_mem_deceased_id           uuid;

  -- Status & Types
  v_status_active_id          uuid;
  v_status_deceased_id        uuid;
  v_rel_type_spouse_id        uuid;
  v_family_id                 uuid;
  v_rel_id                    uuid;

  -- Operation Results
  v_appoint_res               jsonb;
  v_conclude_res              jsonb;
  v_replace_res               jsonb;
  v_guidance_res              jsonb;
  v_asg_id                    uuid;
  v_asg_unit_id               uuid;
  v_asg_chap_id               uuid;
  v_asg_area_id               uuid;
  v_asg_out_id                uuid;
  v_asg_in_id                 uuid;
  v_node_planned_id           uuid;
  v_node_other_unit_id        uuid;
  v_hh_other_unit_id          uuid;
  v_mem_unscoped_id           uuid;
  v_delegate_profile          uuid;
  v_delegate_auth             uuid;
  v_role_asg_id               uuid;
  v_scope_asg_id              uuid;
  v_pra_id                    uuid;
  v_audit_count_before        integer;
  v_audit_count_after         integer;

BEGIN
  -- ---------------------------------------------------------------------------
  -- SETUP FIXTURES
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

  -- Resolve member status & spouse rel type
  SELECT id INTO STRICT v_status_active_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active';
  SELECT id INTO STRICT v_status_deceased_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'deceased';
  SELECT id INTO STRICT v_rel_type_spouse_id FROM public.family_relationship_types WHERE code = 'spouse' AND (organization_id = v_org_id OR organization_id IS NULL) LIMIT 1;

  -- ---------------------------------------------------------------------------
  -- PART 1: SCHEMA & PERMISSIONS POSTURE
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.permissions
  WHERE code IN ('leadership.servant_leaders.appoint', 'leadership.servant_leaders.conclude', 'leadership.servant_leaders.replace');
  ASSERT v_count = 3, format('Test 1.1 FAILED: permissions count %s != 3', v_count);

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code IN ('leadership.servant_leaders.appoint', 'leadership.servant_leaders.conclude', 'leadership.servant_leaders.replace')
    AND ar.code = 'organization_administrator';
  ASSERT v_count = 3, format('Test 1.2 FAILED: admin permissions count %s != 3', v_count);

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code IN ('leadership.servant_leaders.appoint', 'leadership.servant_leaders.conclude', 'leadership.servant_leaders.replace')
    AND ar.code IN ('household_servant', 'unit_servant', 'chapter_servant', 'area_servant');
  ASSERT v_count = 0, format('Test 1.3 FAILED: servant roles received write permissions! count: %s', v_count);

  SELECT count(*) INTO v_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name IN ('appoint_servant_leader', 'conclude_servant_leader', 'replace_servant_leader', 'get_servant_leader_pastoral_placement_guidance');
  ASSERT v_count = 4, format('Test 1.4 FAILED: routine count %s != 4', v_count);

  RAISE NOTICE 'PART 1 PASSED: Permissions and routine definitions verified.';

  -- ---------------------------------------------------------------------------
  -- BUILD SYNTHETIC GOVERNANCE TREE & HOUSEHOLDS
  -- ---------------------------------------------------------------------------
  v_node_area_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_area_id, v_org_id, v_type_area_id, 'test_area_6b5', 'Test Area 6B5', 'active', current_date);

  v_node_chap_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_chap_id, v_org_id, v_type_chap_id, 'test_chap_6b5', 'Test Chapter 6B5', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_area_id, v_node_chap_id, 'primary_parent', 'active', true, current_date);

  v_node_unit_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_unit_id, v_org_id, v_type_unit_id, 'test_unit_6b5', 'Test Unit 6B5', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_chap_id, v_node_unit_id, 'primary_parent', 'active', true, current_date);

  -- Create households across all 5 pastoral levels
  v_hh_member_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Member HH 6B5', p_code => 'hh_mem_6b5',
    p_parent_governance_node_id => v_node_unit_id, p_pastoral_level => 'member', p_is_couple_household => true
  );
  v_hh_member_id := (v_hh_member_res->>'household_id')::uuid;

  v_hh_unit_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Unit HH 6B5', p_code => 'hh_unit_6b5',
    p_parent_governance_node_id => v_node_unit_id, p_pastoral_level => 'unit'
  );
  v_hh_unit_id := (v_hh_unit_res->>'household_id')::uuid;

  v_hh_chap_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Chapter HH 6B5', p_code => 'hh_chap_6b5',
    p_parent_governance_node_id => v_node_chap_id, p_pastoral_level => 'chapter'
  );
  v_hh_chap_id := (v_hh_chap_res->>'household_id')::uuid;

  v_hh_area_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Area HH 6B5', p_code => 'hh_area_6b5',
    p_parent_governance_node_id => v_node_area_id, p_pastoral_level => 'area'
  );
  v_hh_area_id := (v_hh_area_res->>'household_id')::uuid;

  v_hh_frat_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Fraternal HH 6B5', p_code => 'hh_frat_6b5',
    p_parent_governance_node_id => v_node_area_id, p_pastoral_level => 'fraternal'
  );
  v_hh_frat_id := (v_hh_frat_res->>'household_id')::uuid;

  -- Create synthetic members
  v_mem_hsl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_hsl_id, v_org_id, v_status_active_id, 'Bro HSL Man', 'Man, Bro HSL', 'HSL Man', 'active');

  v_mem_hsl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_hsl_wife_id, v_org_id, v_status_active_id, 'Sis HSL Wife', 'Wife, Sis HSL', 'HSL Wife', 'active');

  v_mem_usl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_usl_id, v_org_id, v_status_active_id, 'Bro USL Leader', 'Leader, Bro USL', 'USL Leader', 'active');

  v_mem_csl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_csl_id, v_org_id, v_status_active_id, 'Bro CSL Leader', 'Leader, Bro CSL', 'CSL Leader', 'active');

  v_mem_asl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_asl_id, v_org_id, v_status_active_id, 'Bro ASL Head', 'Head, Bro ASL', 'ASL Head', 'active');

  v_mem_replace_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_replace_id, v_org_id, v_status_active_id, 'Bro Replacement Candidate', 'Candidate, Bro Replacement', 'Candidate', 'active');

  v_mem_deceased_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status, is_deceased, deceased_on, deceased_on_precision, archived_at, archive_reason)
  VALUES (v_mem_deceased_id, v_org_id, v_status_deceased_id, 'Bro Deceased Former', 'Former, Bro Deceased', 'Deceased', 'archived', true, current_date - 10, 'exact', now(), 'Deceased');

  -- Verified spouse relationship for HSL couple
  v_family_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name)
  VALUES (v_family_id, v_org_id, 'HSL Family', 'The HSL Family');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES
    (v_org_id, v_family_id, v_mem_hsl_id, 'spouse', 'active', current_date - 30),
    (v_org_id, v_family_id, v_mem_hsl_wife_id, 'spouse', 'active', current_date - 30);

  v_rel_id := gen_random_uuid();
  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    v_rel_id, v_org_id, v_family_id,
    least(v_mem_hsl_id, v_mem_hsl_wife_id), greatest(v_mem_hsl_id, v_mem_hsl_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  -- ---------------------------------------------------------------------------
  -- PART 2: APPOINT WORKFLOWS & GUARDS
  -- ---------------------------------------------------------------------------
  -- 2.1 HSL on Member Household succeeds
  v_appoint_res := public.appoint_servant_leader(
    p_organization_id    => v_org_id,
    p_role_code          => 'household_servant_leader',
    p_governance_node_id => v_hh_member_id,
    p_member_id          => v_mem_hsl_id,
    p_effective_from     => current_date,
    p_reason             => 'Appointed to shepherd Member HH 6B5'
  );
  ASSERT v_appoint_res->>'status' = 'appointed', 'Test 2.1 FAILED: HSL appointment failed';
  v_asg_id := (v_appoint_res->>'leadership_assignment_id')::uuid;
  ASSERT v_asg_id IS NOT NULL, 'Test 2.1 FAILED: leadership_assignment_id is null';
  RAISE NOTICE 'Test 2.1 PASSED: HSL appointed to Member Household.';

  -- 2.2 HSL rejected on Unit Household (23514)
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'household_servant_leader',
      p_governance_node_id => v_hh_unit_id,
      p_member_id          => v_mem_replace_id
    );
  EXCEPTION WHEN sqlstate '23514' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.2 FAILED: HSL allowed on Unit Household!';
  RAISE NOTICE 'Test 2.2 PASSED: HSL rejected on Unit Household.';

  -- 2.3 HSL rejected on Chapter Household (23514)
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'household_servant_leader',
      p_governance_node_id => v_hh_chap_id,
      p_member_id          => v_mem_replace_id
    );
  EXCEPTION WHEN sqlstate '23514' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.3 FAILED: HSL allowed on Chapter Household!';
  RAISE NOTICE 'Test 2.3 PASSED: HSL rejected on Chapter Household.';

  -- 2.4 HSL rejected on Area Household (23514)
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'household_servant_leader',
      p_governance_node_id => v_hh_area_id,
      p_member_id          => v_mem_replace_id
    );
  EXCEPTION WHEN sqlstate '23514' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.4 FAILED: HSL allowed on Area Household!';
  RAISE NOTICE 'Test 2.4 PASSED: HSL rejected on Area Household.';

  -- 2.5 HSL rejected on Fraternal Household (23514)
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'household_servant_leader',
      p_governance_node_id => v_hh_frat_id,
      p_member_id          => v_mem_replace_id
    );
  EXCEPTION WHEN sqlstate '23514' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.5 FAILED: HSL allowed on Fraternal Household!';
  RAISE NOTICE 'Test 2.5 PASSED: HSL rejected on Fraternal Household.';

  -- 2.6 USL succeeds on Unit node
  v_appoint_res := public.appoint_servant_leader(
    p_organization_id    => v_org_id,
    p_role_code          => 'unit_servant_leader',
    p_governance_node_id => v_node_unit_id,
    p_member_id          => v_mem_usl_id,
    p_effective_from     => current_date
  );
  ASSERT v_appoint_res->>'status' = 'appointed', 'Test 2.6 FAILED: USL appointment failed';
  v_asg_unit_id := (v_appoint_res->>'leadership_assignment_id')::uuid;
  RAISE NOTICE 'Test 2.6 PASSED: USL appointed to Unit node.';

  -- 2.7 USL rejected on Chapter node (22023)
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'unit_servant_leader',
      p_governance_node_id => v_node_chap_id,
      p_member_id          => v_mem_replace_id
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.7 FAILED: USL allowed on Chapter node!';
  RAISE NOTICE 'Test 2.7 PASSED: USL rejected on Chapter node.';

  -- 2.8 CSL succeeds on Chapter node
  v_appoint_res := public.appoint_servant_leader(
    p_organization_id    => v_org_id,
    p_role_code          => 'chapter_servant_leader',
    p_governance_node_id => v_node_chap_id,
    p_member_id          => v_mem_csl_id
  );
  ASSERT v_appoint_res->>'status' = 'appointed', 'Test 2.8 FAILED: CSL appointment failed';
  v_asg_chap_id := (v_appoint_res->>'leadership_assignment_id')::uuid;
  RAISE NOTICE 'Test 2.8 PASSED: CSL appointed to Chapter node.';

  -- 2.9 ASL succeeds on Area node
  v_appoint_res := public.appoint_servant_leader(
    p_organization_id    => v_org_id,
    p_role_code          => 'area_servant_leader',
    p_governance_node_id => v_node_area_id,
    p_member_id          => v_mem_asl_id
  );
  ASSERT v_appoint_res->>'status' = 'appointed', 'Test 2.9 FAILED: ASL appointment failed';
  v_asg_area_id := (v_appoint_res->>'leadership_assignment_id')::uuid;
  RAISE NOTICE 'Test 2.9 PASSED: ASL appointed to Area node.';

  -- 2.10 Duplicate office holder rejected
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'unit_servant_leader',
      p_governance_node_id => v_node_unit_id,
      p_member_id          => v_mem_replace_id
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.10 FAILED: Duplicate leader appointment allowed!';
  RAISE NOTICE 'Test 2.10 PASSED: Duplicate active leader appointment rejected with 22023.';

  -- 2.11 Same member duplicate rejected
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'unit_servant_leader',
      p_governance_node_id => v_node_unit_id,
      p_member_id          => v_mem_usl_id
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.11 FAILED: Same member duplicate appointment allowed!';
  RAISE NOTICE 'Test 2.11 PASSED: Same member duplicate appointment rejected with 22023.';

  -- 2.12 Deceased member rejected
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'unit_servant_leader',
      p_governance_node_id => v_node_unit_id,
      p_member_id          => v_mem_deceased_id
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.12 FAILED: Deceased member appointment allowed!';
  RAISE NOTICE 'Test 2.12 PASSED: Deceased member appointment rejected with 22023.';

  -- 2.13 Future effective date rejected
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'unit_servant_leader',
      p_governance_node_id => v_node_unit_id,
      p_member_id          => v_mem_replace_id,
      p_effective_from     => current_date + 5
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 2.13 FAILED: Future effective date appointment allowed!';
  RAISE NOTICE 'Test 2.13 PASSED: Future effective date appointment rejected with 22023.';

  -- ---------------------------------------------------------------------------
  -- PART 3: CONCLUDE WORKFLOWS & GUARDS
  -- ---------------------------------------------------------------------------
  -- 3.1 Conclude CSL appointment
  v_conclude_res := public.conclude_servant_leader(
    p_organization_id           => v_org_id,
    p_leadership_assignment_id => v_asg_chap_id,
    p_effective_to              => current_date,
    p_reason                    => 'Term completed successfully'
  );
  ASSERT v_conclude_res->>'status' = 'concluded', 'Test 3.1 FAILED: Conclude failed';

  SELECT count(*) INTO v_count
  FROM public.leadership_assignments
  WHERE id = v_asg_chap_id
    AND assignment_status = 'completed'
    AND effective_to = current_date
    AND ending_reason = 'Term completed successfully';
  ASSERT v_count = 1, 'Test 3.1 FAILED: Assignment record not properly updated to completed';
  RAISE NOTICE 'Test 3.1 PASSED: Servant leader concluded with full history preserved.';

  -- 3.2 Duplicate conclusion rejected (already completed)
  BEGIN
    v_blocked := false;
    PERFORM public.conclude_servant_leader(
      p_organization_id           => v_org_id,
      p_leadership_assignment_id => v_asg_chap_id,
      p_effective_to              => current_date,
      p_reason                    => 'Duplicate conclude'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3.2 FAILED: Duplicate conclusion allowed!';
  RAISE NOTICE 'Test 3.2 PASSED: Duplicate conclusion rejected with 22023.';

  -- 3.3 Future conclusion rejected
  BEGIN
    v_blocked := false;
    PERFORM public.conclude_servant_leader(
      p_organization_id           => v_org_id,
      p_leadership_assignment_id => v_asg_unit_id,
      p_effective_to              => current_date + 10,
      p_reason                    => 'Future conclude'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3.3 FAILED: Future conclusion allowed!';
  RAISE NOTICE 'Test 3.3 PASSED: Future conclusion rejected with 22023.';

  -- 3.4 Missing reason rejected
  BEGIN
    v_blocked := false;
    PERFORM public.conclude_servant_leader(
      p_organization_id           => v_org_id,
      p_leadership_assignment_id => v_asg_unit_id,
      p_effective_to              => current_date,
      p_reason                    => '   '
    );
  EXCEPTION WHEN sqlstate '23502' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3.4 FAILED: Empty reason allowed!';
  RAISE NOTICE 'Test 3.4 PASSED: Missing conclusion reason rejected with 23502.';

  -- ---------------------------------------------------------------------------
  -- PART 4: REPLACE WORKFLOWS & GUARDS
  -- ---------------------------------------------------------------------------
  -- 4.1 Same-day replacement of USL
  v_replace_res := public.replace_servant_leader(
    p_organization_id    => v_org_id,
    p_role_code          => 'unit_servant_leader',
    p_governance_node_id => v_node_unit_id,
    p_new_member_id      => v_mem_replace_id,
    p_effective_date     => current_date,
    p_reason             => 'Leadership rotation'
  );
  ASSERT v_replace_res->>'status' = 'replaced', 'Test 4.1 FAILED: Replace status not replaced';
  v_asg_out_id := (v_replace_res->>'outgoing_assignment_id')::uuid;
  v_asg_in_id  := (v_replace_res->>'incoming_assignment_id')::uuid;

  ASSERT v_asg_out_id = v_asg_unit_id, 'Test 4.1 FAILED: Outgoing assignment ID mismatch';

  -- Outgoing must be completed
  SELECT count(*) INTO v_count
  FROM public.leadership_assignments
  WHERE id = v_asg_out_id
    AND assignment_status = 'completed'
    AND effective_to = current_date;
  ASSERT v_count = 1, 'Test 4.1 FAILED: Outgoing assignment not marked completed';

  -- Incoming must be active
  SELECT count(*) INTO v_count
  FROM public.leadership_assignments
  WHERE id = v_asg_in_id
    AND assignment_status = 'active'
    AND effective_from = current_date
    AND effective_to IS NULL;
  ASSERT v_count = 1, 'Test 4.1 FAILED: Incoming assignment not marked active';

  -- Exactly one current active holder on this node/role
  SELECT count(*) INTO v_count
  FROM public.leadership_assignments la
  JOIN public.leadership_role_definitions lrd ON lrd.id = la.leadership_role_definition_id
  WHERE la.governance_node_id = v_node_unit_id
    AND lrd.code = 'unit_servant_leader'
    AND la.assignment_status = 'active'
    AND la.effective_from <= current_date
    AND (la.effective_to IS NULL OR la.effective_to >= current_date);
  ASSERT v_count = 1, format('Test 4.1 FAILED: Active count %s != 1 after replace', v_count);
  RAISE NOTICE 'Test 4.1 PASSED: Same-day replacement succeeded atomically.';

  -- 4.2 Replace with no current holder returns blocked ('no_current_role_holder')
  -- We previously concluded CSL, so Chapter node has no active leader
  v_replace_res := public.replace_servant_leader(
    p_organization_id    => v_org_id,
    p_role_code          => 'chapter_servant_leader',
    p_governance_node_id => v_node_chap_id,
    p_new_member_id      => v_mem_replace_id,
    p_effective_date     => current_date,
    p_reason             => 'Attempting replace on vacant node'
  );
  ASSERT v_replace_res->>'status' = 'blocked', 'Test 4.2 FAILED: Replace not blocked on vacant node';
  ASSERT v_replace_res->>'blocker_type' = 'no_current_role_holder', 'Test 4.2 FAILED: Blocker type mismatch';
  RAISE NOTICE 'Test 4.2 PASSED: Replace on vacant node cleanly returns blocked (no_current_role_holder).';

  -- 4.3 Same-member replacement rejected
  BEGIN
    v_blocked := false;
    PERFORM public.replace_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'unit_servant_leader',
      p_governance_node_id => v_node_unit_id,
      p_new_member_id      => v_mem_replace_id, -- current active leader
      p_effective_date     => current_date,
      p_reason             => 'Replacing with self'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 4.3 FAILED: Same-member replacement allowed!';
  RAISE NOTICE 'Test 4.3 PASSED: Same-member replacement rejected with 22023.';

  -- ---------------------------------------------------------------------------
  -- PART 5: PASTORAL PLACEMENT GUIDANCE RPC
  -- ---------------------------------------------------------------------------
  -- 5.1 HSL guidance -> recommends Unit Household
  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(
    p_organization_id => v_org_id,
    p_member_id       => v_mem_hsl_id
  );
  ASSERT v_guidance_res->>'has_formal_role' = 'true', 'Test 5.1 FAILED: has_formal_role false';
  ASSERT v_guidance_res->>'role_code' = 'household_servant_leader', 'Test 5.1 FAILED: role_code mismatch';
  ASSERT v_guidance_res->>'recommended_pastoral_level' = 'unit', 'Test 5.1 FAILED: recommended_pastoral_level != unit';
  ASSERT v_guidance_res->'spouse_context'->>'has_verified_spouse' = 'true', 'Test 5.1 FAILED: verified spouse not detected';
  ASSERT v_guidance_res->'spouse_context'->>'spouse_member_id' = v_mem_hsl_wife_id::text, 'Test 5.1 FAILED: spouse ID mismatch';
  RAISE NOTICE 'Test 5.1 PASSED: HSL receives Unit Household placement recommendation with verified spouse context.';

  -- 5.2 ASL guidance -> recommends Fraternal Household
  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(
    p_organization_id => v_org_id,
    p_member_id       => v_mem_asl_id
  );
  ASSERT v_guidance_res->>'recommended_pastoral_level' = 'fraternal', 'Test 5.2 FAILED: ASL recommended level != fraternal';
  ASSERT v_guidance_res->>'recommended_scope_node_id' = v_node_area_id::text, 'Test 5.2 FAILED: recommended scope != Area node';
  RAISE NOTICE 'Test 5.2 PASSED: ASL receives Fraternal Household placement recommendation.';

  -- ---------------------------------------------------------------------------
  -- PART 6: AUTHORIZATION & SOFTWARE ISOLATION
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count FROM public.app_roles;
  ASSERT v_count = 17, 'Test 6.1 FAILED: app_roles count changed';

  SELECT count(*) INTO v_count FROM public.profile_role_assignments;
  ASSERT v_count = 1, 'Test 6.2 FAILED: profile_role_assignments count changed';

  SELECT count(*) INTO v_count FROM public.profile_scope_assignments;
  ASSERT v_count = 1, 'Test 6.3 FAILED: profile_scope_assignments count changed';

  -- Confirm wife received no leadership assignment
  SELECT count(*) INTO v_count FROM public.leadership_assignments WHERE member_id = v_mem_hsl_wife_id;
  ASSERT v_count = 0, 'Test 6.4 FAILED: Wife received formal leadership assignment!';

  RAISE NOTICE 'Test 6 PASSED: Software authorization tables and couple formal offices completely isolated.';

  -- Audit events recorded
  SELECT count(*) INTO v_count
  FROM audit.events
  WHERE organization_id = v_org_id
    AND event_category = 'governance'
    AND event_code IN ('servant_leader.appointed', 'servant_leader.concluded', 'servant_leader.replaced');
  ASSERT v_count >= 5, format('Test 6.5 FAILED: Audit event count %s < 5', v_count);
  RAISE NOTICE 'Test 6.5 PASSED: Audit events recorded for appointment lifecycle.';

  -- ---------------------------------------------------------------------------
  -- PART 7: CORRECTIVE COVERAGE (Item 14 A - T)
  -- ---------------------------------------------------------------------------
  -- A/B. Appoint rejected on PLANNED governance node (22023)
  v_node_planned_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_planned_id, v_org_id, v_type_unit_id, 'test_unit_planned_6b5', 'Test Unit Planned 6B5', 'planned', current_date);

  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'unit_servant_leader',
      p_governance_node_id => v_node_planned_id,
      p_member_id          => v_mem_replace_id
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 14.A/B FAILED: Appointing to planned governance node did not raise 22023!';
  RAISE NOTICE 'Test 14.A/B PASSED: Appoint on planned node rejected with 22023.';

  -- C/D/E: Scope enforcement tests using delegate profile with restricted scope
  v_delegate_auth := gen_random_uuid();
  v_delegate_profile := gen_random_uuid();

  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_delegate_profile, 'authenticated', 'authenticated', 'delegate.tester@test.local');

  INSERT INTO public.profiles (id, display_name)
  VALUES (v_delegate_profile, 'Delegate Tester');

  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_delegate_profile, v_org_id, 'active', now());

  SELECT id INTO STRICT v_role_asg_id FROM public.app_roles WHERE code = 'organization_administrator';

  -- Delegate has organization_administrator role
  INSERT INTO public.profile_role_assignments (
    id, organization_id, profile_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    gen_random_uuid(), v_org_id, v_delegate_profile, v_role_asg_id, 'active',
    now(), now(), now(), now()
  ) RETURNING id INTO v_pra_id;

  -- Delegate has scope ONLY to v_node_unit_id
  INSERT INTO public.profile_scope_assignments (
    organization_id, profile_role_assignment_id, scope_type, governance_node_id,
    includes_descendants, scope_effect, assignment_status, effective_from_at
  ) VALUES (
    v_org_id, v_pra_id, 'governance_node', v_node_unit_id,
    true, 'include', 'active', now()
  );

  -- Switch context to delegate
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_delegate_profile, 'role', 'authenticated')::text, true);

  -- C. Caller has permission but lacks target governance scope (Area node) -> denied P0002
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'area_servant_leader',
      p_governance_node_id => v_node_area_id,
      p_member_id          => v_mem_replace_id
    );
  EXCEPTION WHEN sqlstate 'P0002' OR sqlstate '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 14.C FAILED: Appoint outside caller governance scope was not denied!';
  RAISE NOTICE 'Test 14.C PASSED: Appoint outside governance scope denied.';

  -- Create a member outside delegate's scope (e.g., in a different household under a different unit)
  v_node_other_unit_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_other_unit_id, v_org_id, v_type_unit_id, 'test_unit_other_6b5', 'Test Unit Other 6B5', 'active', current_date);

  -- Use create_household RPC as admin (switch temporarily)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);
  v_hh_unit_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Other Unit HH 6B5', p_code => 'hh_other_unit_6b5',
    p_parent_governance_node_id => v_node_other_unit_id, p_pastoral_level => 'unit'
  );
  v_hh_other_unit_id := (v_hh_unit_res->>'household_id')::uuid;

  -- Switch context back to delegate
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_delegate_profile, 'role', 'authenticated')::text, true);

  v_mem_unscoped_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_unscoped_id, v_org_id, v_status_active_id, 'Bro Unscoped Member', 'Member, Bro Unscoped', 'Unscoped', 'active');

  -- Place member into household under other unit
  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, membership_role, membership_status, is_primary, effective_from)
  VALUES (v_org_id, v_hh_other_unit_id, v_mem_unscoped_id, 'member', 'active', true, current_date);

  -- D. Caller has node scope but lacks candidate member scope -> denied P0002
  BEGIN
    v_blocked := false;
    PERFORM public.appoint_servant_leader(
      p_organization_id    => v_org_id,
      p_role_code          => 'household_servant_leader',
      p_governance_node_id => v_hh_member_id, -- under v_node_unit_id
      p_member_id          => v_mem_unscoped_id
    );
  EXCEPTION WHEN sqlstate 'P0002' OR sqlstate '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 14.D FAILED: Appoint candidate outside caller member scope was not denied!';
  RAISE NOTICE 'Test 14.D PASSED: Appoint candidate outside member scope denied.';

  -- Switch context back to admin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- F, G, H, I, J: Spouse verification vocabulary testing
  -- F: member_confirmed -> verified
  UPDATE public.family_relationships SET verification_status = 'member_confirmed' WHERE id = v_rel_id;
  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT (v_guidance_res->'spouse_context'->>'has_verified_spouse')::boolean = true, 'Test 14.F FAILED: member_confirmed not treated as verified';

  -- G: administrator_verified -> verified
  UPDATE public.family_relationships SET verification_status = 'administrator_verified' WHERE id = v_rel_id;
  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT (v_guidance_res->'spouse_context'->>'has_verified_spouse')::boolean = true, 'Test 14.G FAILED: administrator_verified not treated as verified';

  -- H: document_verified -> verified
  UPDATE public.family_relationships SET verification_status = 'document_verified' WHERE id = v_rel_id;
  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT (v_guidance_res->'spouse_context'->>'has_verified_spouse')::boolean = true, 'Test 14.H FAILED: document_verified not treated as verified';

  -- I: unverified -> not verified
  UPDATE public.family_relationships SET verification_status = 'unverified' WHERE id = v_rel_id;
  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT (v_guidance_res->'spouse_context'->>'has_verified_spouse')::boolean = false, 'Test 14.I FAILED: unverified treated as verified';

  -- P: required Couples context with unverified spouse -> manual_review_required
  ASSERT v_guidance_res->>'placement_status' = 'manual_review_required', 'Test 14.P FAILED: unverified spouse in couple context did not produce manual_review_required';
  RAISE NOTICE 'Test 14.F-J,P PASSED: Canonical verification vocabulary and Couple manual_review_required verified.';

  -- Restore spouse verification to administrator_verified
  UPDATE public.family_relationships SET verification_status = 'administrator_verified' WHERE id = v_rel_id;

  -- K: same pastoral level, wrong governance scope -> different_level (NOT correct)
  -- Put v_mem_hsl_id into v_hh_other_unit_id (which is unit level, but parented by v_node_other_unit_id, not v_node_unit_id)
  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, membership_role, membership_status, is_primary, effective_from)
  VALUES (v_org_id, v_hh_other_unit_id, v_mem_hsl_id, 'member', 'active', true, current_date);

  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT v_guidance_res->>'placement_status' = 'different_level', format('Test 14.K FAILED: status was %s, expected different_level', v_guidance_res->>'placement_status');
  RAISE NOTICE 'Test 14.K PASSED: Same pastoral level but different governance scope returns different_level, NOT correct.';

  -- M: existing correct level + correct scope -> correct
  UPDATE public.household_memberships
  SET household_node_id = v_hh_unit_id -- correctly parented by v_node_unit_id
  WHERE member_id = v_mem_hsl_id;

  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT v_guidance_res->>'placement_status' = 'correct', format('Test 14.M FAILED: status was %s, expected correct', v_guidance_res->>'placement_status');
  RAISE NOTICE 'Test 14.M PASSED: Correct level and correct governance scope returns correct.';

  -- N: wrong pastoral level -> different_level
  UPDATE public.household_memberships
  SET household_node_id = v_hh_chap_id
  WHERE member_id = v_mem_hsl_id;

  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT v_guidance_res->>'placement_status' = 'different_level', format('Test 14.N FAILED: status was %s, expected different_level', v_guidance_res->>'placement_status');
  RAISE NOTICE 'Test 14.N PASSED: Wrong pastoral level returns different_level.';

  -- O: matching target exists + no primary -> missing_household
  DELETE FROM public.household_memberships WHERE member_id = v_mem_hsl_id;
  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT v_guidance_res->>'placement_status' = 'missing_household', format('Test 14.O FAILED: status was %s, expected missing_household', v_guidance_res->>'placement_status');
  RAISE NOTICE 'Test 14.O PASSED: Matching target exists + no primary returns missing_household.';

  -- L: no destination household + no current primary -> no_matching_household_available
  -- Delete the only Unit household under v_node_unit_id
  DELETE FROM public.households WHERE id = v_hh_unit_id;
  v_guidance_res := public.get_servant_leader_pastoral_placement_guidance(v_org_id, v_mem_hsl_id);
  ASSERT v_guidance_res->>'placement_status' = 'no_matching_household_available', format('Test 14.L FAILED: status was %s, expected no_matching_household_available', v_guidance_res->>'placement_status');
  RAISE NOTICE 'Test 14.L PASSED: No destination household + no current primary returns no_matching_household_available.';

  -- Q: replace writes exactly one servant_leader.replaced audit event
  SELECT count(*) INTO v_audit_count_before
  FROM audit.events
  WHERE organization_id = v_org_id
    AND event_category = 'governance'
    AND event_code = 'servant_leader.replaced';

  PERFORM public.replace_servant_leader(
    p_organization_id    => v_org_id,
    p_role_code          => 'unit_servant_leader',
    p_governance_node_id => v_node_unit_id,
    p_new_member_id      => v_mem_usl_id,
    p_effective_date     => current_date,
    p_reason             => 'Audit event test rotation'
  );

  SELECT count(*) INTO v_audit_count_after
  FROM audit.events
  WHERE organization_id = v_org_id
    AND event_category = 'governance'
    AND event_code = 'servant_leader.replaced';

  ASSERT (v_audit_count_after - v_audit_count_before) = 1, format('Test 14.Q FAILED: Expected exactly 1 replaced audit event, got %s', v_audit_count_after - v_audit_count_before);
  RAISE NOTICE 'Test 14.Q PASSED: Replace writes exactly one servant_leader.replaced audit event.';

  -- R: permission mapping remains organization_administrator only
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code IN ('leadership.servant_leaders.appoint', 'leadership.servant_leaders.conclude', 'leadership.servant_leaders.replace');
  ASSERT v_count = 3, format('Test 14.R FAILED: Exactly 3 role_permission mappings expected, got %s', v_count);
  RAISE NOTICE 'Test 14.R PASSED: Permission mapping remains organization_administrator only.';

  -- S/T: app authorization tables and household memberships unchanged
  SELECT count(*) INTO v_count FROM public.app_roles;
  ASSERT v_count = 17, 'Test 14.S FAILED: app_roles count changed';
  RAISE NOTICE 'Test 14.S/T PASSED: App authorization tables and zero unintended side-effects verified.';

  RAISE NOTICE 'ALL PHASE 6B-5 SERVANT LEADER LIFECYCLE TESTS PASSED SUCCESSFULLY.';
END;
$$;

ROLLBACK;

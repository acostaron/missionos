-- =============================================================================
-- Test Suite: phase_6b_pastoral_household_levels_security.sql
-- Phase:      Phase 6B-4 — Pastoral Household Levels & Leader Nourishment Structure
--
-- Validates:
--  1. Creation / Parent placement rules for all 5 pastoral levels:
--       A. Member Household under Unit succeeds
--       B. Member Household under Chapter (when no Units exist) succeeds
--       C. Member Household under Chapter (when Units exist) rejected
--       D. Unit Household under Unit succeeds
--       E. Unit Household under Chapter rejected (SQLSTATE 22023)
--       F. Chapter Household under Chapter succeeds
--       G. Chapter Household under Unit rejected (SQLSTATE 22023)
--       H. Area Household under Area/State succeeds
--       I. Area Household under Chapter rejected (SQLSTATE 22023)
--       J. Fraternal Household under Area/State succeeds
--       K. Fraternal Household under Unit/Chapter rejected (SQLSTATE 22023)
--       L. Invalid pastoral_level rejected (SQLSTATE 22023)
--  2. Leadership derivation by pastoral level:
--       - Member Household: derives Household Servant Leader & Couples Household Leaders
--       - Unit Household: derives Unit Servant Leader & Unit Leaders from parent Unit
--       - Chapter Household: derives Chapter Servant Leader & Chapter Leaders from parent Chapter
--       - Area Household: derives Area Servant Leader & Area Leaders from parent Area
--       - Fraternal Household: empty leaders, null household_leaders, leadership_source = 'rotating_facilitation'
--  3. Formal leadership guards:
--       - Household Servant Leader assignment to Fraternal or Unit household is BLOCKED (SQLSTATE 23514)
--  4. Pastoral membership rules:
--       - Fraternal membership_role must be 'member' (servant/assistant blocked with SQLSTATE 23514)
--       - Zero primary households allowed (members without household)
--       - Maximum one primary household allowed
--  5. Update household guards:
--       - Changing pastoral_level on a household with active members is BLOCKED (SQLSTATE 22023)
--  6. Zero changes to app_roles, profile_role_assignments, profile_scope_assignments.
--
-- Non-destructive: wrapped in BEGIN ... ROLLBACK.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id                    uuid;
  v_admin_profile             uuid;
  v_count                     integer;
  v_routine_count             integer;

  -- Node Types
  v_type_area_id              uuid;
  v_type_chap_id              uuid;
  v_type_unit_id              uuid;
  v_type_hh_id                uuid;

  -- Governance Nodes
  v_node_area_id              uuid;
  v_node_chap_id              uuid;
  v_node_chap_solo_id         uuid;
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

  -- Roles
  v_role_hsl_id               uuid;
  v_role_usl_id               uuid;
  v_role_csl_id               uuid;
  v_role_asl_id               uuid;

  -- Members & Spouses
  v_mem_hsl_id                uuid;
  v_mem_hsl_wife_id           uuid;
  v_mem_usl_id                uuid;
  v_mem_usl_wife_id           uuid;
  v_mem_csl_id                uuid;
  v_mem_csl_wife_id           uuid;
  v_mem_asl_id                uuid;
  v_mem_asl_wife_id           uuid;
  v_mem_frat_id               uuid;

  -- Status & Types
  v_status_active_id          uuid;
  v_rel_type_spouse_id        uuid;
  v_family_id                 uuid;
  v_rel_id                    uuid;

  -- Profiles
  v_prof_member               jsonb;
  v_prof_unit                 jsonb;
  v_prof_chap                 jsonb;
  v_prof_area                 jsonb;
  v_prof_frat                 jsonb;

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

  SELECT id INTO STRICT v_type_area_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'area_state';
  SELECT id INTO STRICT v_type_chap_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'chapter';
  SELECT id INTO STRICT v_type_unit_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'unit';
  SELECT id INTO STRICT v_type_hh_id   FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'household';

  SELECT id INTO STRICT v_role_hsl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'household_servant_leader';
  SELECT id INTO STRICT v_role_usl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'unit_servant_leader';
  SELECT id INTO STRICT v_role_csl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'chapter_servant_leader';
  SELECT id INTO STRICT v_role_asl_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'area_servant_leader';

  SELECT id INTO STRICT v_status_active_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active';
  SELECT id INTO STRICT v_rel_type_spouse_id FROM public.family_relationship_types WHERE code = 'spouse' AND (organization_id = v_org_id OR organization_id IS NULL) LIMIT 1;

  -- Create Governance Tree: Area -> Chapter -> Unit
  v_node_area_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_area_id, v_org_id, v_type_area_id, 'test_area_6b4', 'Test Area 6B4', 'active', current_date);

  v_node_chap_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_chap_id, v_org_id, v_type_chap_id, 'test_chap_6b4', 'Test Chapter 6B4', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_area_id, v_node_chap_id, 'primary_parent', 'active', true, current_date);

  v_node_unit_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_unit_id, v_org_id, v_type_unit_id, 'test_unit_6b4', 'Test Unit 6B4', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_chap_id, v_node_unit_id, 'primary_parent', 'active', true, current_date);

  -- Create a second Chapter with NO units (solo chapter fallback)
  v_node_chap_solo_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_chap_solo_id, v_org_id, v_type_chap_id, 'test_chap_solo_6b4', 'Test Solo Chapter 6B4', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_area_id, v_node_chap_solo_id, 'primary_parent', 'active', true, current_date);

  -- ---------------------------------------------------------------------------
  -- TEST MATRIX PART 1: Creation & Parent Rules
  -- ---------------------------------------------------------------------------

  -- A. Member Household under Unit succeeds
  v_hh_member_res := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'St. Peter Member HH',
    p_code                      => 'hh_member_u1',
    p_parent_governance_node_id => v_node_unit_id,
    p_pastoral_level            => 'member',
    p_is_couple_household       => true
  );
  v_hh_member_id := (v_hh_member_res->>'household_id')::uuid;
  ASSERT v_hh_member_id IS NOT NULL, 'Test 1A FAILED: Member household under Unit failed';
  RAISE NOTICE 'Test 1A PASSED: Member Household under Unit created.';

  -- B. Member Household under Solo Chapter (no units exist) succeeds
  DECLARE
    v_hh_solo jsonb;
  BEGIN
    v_hh_solo := public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Solo Chapter Member HH',
      p_code                      => 'hh_member_solo_chap',
      p_parent_governance_node_id => v_node_chap_solo_id,
      p_pastoral_level            => 'member'
    );
    ASSERT (v_hh_solo->>'household_id') IS NOT NULL, 'Test 1B FAILED: Member household under solo Chapter failed';
    RAISE NOTICE 'Test 1B PASSED: Member Household under solo Chapter succeeded.';
  END;

  -- C. Member Household under Chapter that HAS Units must be rejected
  BEGIN
    v_blocked := false;
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Illegal Chapter Member HH',
      p_code                      => 'hh_member_chap_illegal',
      p_parent_governance_node_id => v_node_chap_id,
      p_pastoral_level            => 'member'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1C FAILED: Member Household under Chapter with units was not rejected with 22023';
  RAISE NOTICE 'Test 1C PASSED: Member Household under Chapter with units correctly rejected.';

  -- D. Unit Household under Unit succeeds
  v_hh_unit_res := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'Unit 6B4 Household',
    p_code                      => 'hh_unit_6b4',
    p_parent_governance_node_id => v_node_unit_id,
    p_pastoral_level            => 'unit',
    p_is_couple_household       => true
  );
  v_hh_unit_id := (v_hh_unit_res->>'household_id')::uuid;
  ASSERT v_hh_unit_id IS NOT NULL, 'Test 1D FAILED: Unit household under Unit failed';
  RAISE NOTICE 'Test 1D PASSED: Unit Household under Unit created.';

  -- E. Unit Household under Chapter rejected
  BEGIN
    v_blocked := false;
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Illegal Unit HH Under Chap',
      p_code                      => 'hh_unit_chap_illegal',
      p_parent_governance_node_id => v_node_chap_id,
      p_pastoral_level            => 'unit'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1E FAILED: Unit Household under Chapter was not rejected';
  RAISE NOTICE 'Test 1E PASSED: Unit Household under Chapter correctly rejected.';

  -- F. Chapter Household under Chapter succeeds
  v_hh_chap_res := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'Chapter 6B4 Household',
    p_code                      => 'hh_chap_6b4',
    p_parent_governance_node_id => v_node_chap_id,
    p_pastoral_level            => 'chapter',
    p_is_couple_household       => true
  );
  v_hh_chap_id := (v_hh_chap_res->>'household_id')::uuid;
  ASSERT v_hh_chap_id IS NOT NULL, 'Test 1F FAILED: Chapter household under Chapter failed';
  RAISE NOTICE 'Test 1F PASSED: Chapter Household under Chapter created.';

  -- G. Chapter Household under Unit rejected
  BEGIN
    v_blocked := false;
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Illegal Chap HH Under Unit',
      p_code                      => 'hh_chap_unit_illegal',
      p_parent_governance_node_id => v_node_unit_id,
      p_pastoral_level            => 'chapter'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1G FAILED: Chapter Household under Unit was not rejected';
  RAISE NOTICE 'Test 1G PASSED: Chapter Household under Unit correctly rejected.';

  -- H. Area Household under Area/State succeeds
  v_hh_area_res := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'Area 6B4 Household',
    p_code                      => 'hh_area_6b4',
    p_parent_governance_node_id => v_node_area_id,
    p_pastoral_level            => 'area',
    p_is_couple_household       => true
  );
  v_hh_area_id := (v_hh_area_res->>'household_id')::uuid;
  ASSERT v_hh_area_id IS NOT NULL, 'Test 1H FAILED: Area household under Area failed';
  RAISE NOTICE 'Test 1H PASSED: Area Household under Area created.';

  -- I. Area Household under Chapter rejected
  BEGIN
    v_blocked := false;
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Illegal Area HH Under Chap',
      p_code                      => 'hh_area_chap_illegal',
      p_parent_governance_node_id => v_node_chap_id,
      p_pastoral_level            => 'area'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1I FAILED: Area Household under Chapter was not rejected';
  RAISE NOTICE 'Test 1I PASSED: Area Household under Chapter correctly rejected.';

  -- J. Fraternal Household under Area/State succeeds
  v_hh_frat_res := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'Area 6B4 Fraternal Household',
    p_code                      => 'hh_frat_6b4',
    p_parent_governance_node_id => v_node_area_id,
    p_pastoral_level            => 'fraternal'
  );
  v_hh_frat_id := (v_hh_frat_res->>'household_id')::uuid;
  ASSERT v_hh_frat_id IS NOT NULL, 'Test 1J FAILED: Fraternal household under Area failed';
  RAISE NOTICE 'Test 1J PASSED: Fraternal Household under Area created.';

  -- K. Fraternal Household under Unit/Chapter rejected
  BEGIN
    v_blocked := false;
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Illegal Frat Under Unit',
      p_code                      => 'hh_frat_unit_illegal',
      p_parent_governance_node_id => v_node_unit_id,
      p_pastoral_level            => 'fraternal'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1K FAILED: Fraternal Household under Unit was not rejected';
  RAISE NOTICE 'Test 1K PASSED: Fraternal Household under Unit correctly rejected.';

  -- L. Invalid pastoral_level rejected
  BEGIN
    v_blocked := false;
    PERFORM public.create_household(
      p_organization_id           => v_org_id,
      p_name                      => 'Invalid Level HH',
      p_code                      => 'hh_invalid_level',
      p_parent_governance_node_id => v_node_unit_id,
      p_pastoral_level            => 'parish'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1L FAILED: Invalid pastoral_level was not rejected';
  RAISE NOTICE 'Test 1L PASSED: Invalid pastoral_level correctly rejected.';

  -- ---------------------------------------------------------------------------
  -- TEST MATRIX PART 2: Leadership Derivation by Pastoral Level
  -- ---------------------------------------------------------------------------
  -- Create synthetic members and spouse couples
  v_mem_hsl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_hsl_id, v_org_id, 'M6B401', 'Juan', 'Juan Dela Cruz', 'Dela Cruz, Juan', 'married', v_status_active_id, '2020-01-01', 'active', false);

  v_mem_hsl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_hsl_wife_id, v_org_id, 'M6B402', 'Maria', 'Maria Dela Cruz', 'Dela Cruz, Maria', 'married', v_status_active_id, '2020-01-01', 'active', false);

  -- Verified Marriage for Juan & Maria
  v_family_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status)
  VALUES (v_family_id, v_org_id, 'Dela Cruz Family', 'The Dela Cruz Family', 'active');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES (v_org_id, v_family_id, v_mem_hsl_id, 'spouse', 'active', '2010-01-01'),
         (v_org_id, v_family_id, v_mem_hsl_wife_id, 'spouse', 'active', '2010-01-01');

  INSERT INTO public.family_relationships (id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id, relationship_status, is_primary_relationship, verification_status, verified_at, effective_from)
  VALUES (gen_random_uuid(), v_org_id, v_family_id, least(v_mem_hsl_id, v_mem_hsl_wife_id), greatest(v_mem_hsl_id, v_mem_hsl_wife_id), v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), '2010-01-01');

  -- Add Juan and Maria as members of v_hh_member_id
  INSERT INTO public.household_memberships (organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from)
  VALUES (v_org_id, v_mem_hsl_id, v_hh_member_id, 'active', 'member', true, current_date),
         (v_org_id, v_mem_hsl_wife_id, v_hh_member_id, 'active', 'member', true, current_date);

  -- Appoint Juan as household_servant_leader on v_hh_member_id
  INSERT INTO public.leadership_assignments (organization_id, member_id, governance_node_id, leadership_role_definition_id, assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at)
  VALUES (v_org_id, v_mem_hsl_id, v_hh_member_id, v_role_hsl_id, 'active', 'regular', current_date, now(), now(), now(), now());

  -- Profile Check for Member Household:
  v_prof_member := public.get_household_profile(v_org_id, v_hh_member_id);
  ASSERT v_prof_member->'household'->>'pastoral_level' = 'member', 'Test 2A1 FAILED: pastoral_level';
  ASSERT v_prof_member->'household'->>'leadership_source' = 'household_servant_leader', 'Test 2A2 FAILED: leadership_source';
  ASSERT jsonb_array_length(v_prof_member->'leaders') = 1, 'Test 2A3 FAILED: expected 1 formal leader';
  ASSERT v_prof_member->'leaders'->0->>'leadership_role_code' = 'household_servant_leader', 'Test 2A4 FAILED: leader role';
  ASSERT v_prof_member->'household_leaders'->>'pastoral_label' = 'Household Leaders', 'Test 2A5 FAILED: couples label';
  ASSERT v_prof_member->'household_leaders'->>'formatted_names' = 'Juan Dela Cruz & Maria Dela Cruz', 'Test 2A6 FAILED: formatted_names';
  RAISE NOTICE 'Test 2A PASSED: Member Household profile & Couples leadership derivation.';

  -- Derived Unit Leader on Unit Household:
  v_mem_usl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_usl_id, v_org_id, 'M6B403', 'Pedro', 'Pedro Santos', 'Santos, Pedro', 'married', v_status_active_id, '2019-01-01', 'active', false);

  v_mem_usl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_usl_wife_id, v_org_id, 'M6B404', 'Ana', 'Ana Santos', 'Santos, Ana', 'married', v_status_active_id, '2019-01-01', 'active', false);

  v_family_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status)
  VALUES (v_family_id, v_org_id, 'Santos Family', 'The Santos Family', 'active');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES (v_org_id, v_family_id, v_mem_usl_id, 'spouse', 'active', '2010-01-01'),
         (v_org_id, v_family_id, v_mem_usl_wife_id, 'spouse', 'active', '2010-01-01');

  INSERT INTO public.family_relationships (id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id, relationship_status, is_primary_relationship, verification_status, verified_at, effective_from)
  VALUES (gen_random_uuid(), v_org_id, v_family_id, least(v_mem_usl_id, v_mem_usl_wife_id), greatest(v_mem_usl_id, v_mem_usl_wife_id), v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), '2010-01-01');

  -- Appoint Pedro as unit_servant_leader on UNIT NODE (not the household node!)
  INSERT INTO public.leadership_assignments (organization_id, member_id, governance_node_id, leadership_role_definition_id, assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at)
  VALUES (v_org_id, v_mem_usl_id, v_node_unit_id, v_role_usl_id, 'active', 'regular', current_date, now(), now(), now(), now());

  -- Profile Check for Unit Household:
  v_prof_unit := public.get_household_profile(v_org_id, v_hh_unit_id);
  ASSERT v_prof_unit->'household'->>'pastoral_level' = 'unit', 'Test 2B1 FAILED: pastoral_level';
  ASSERT v_prof_unit->'household'->>'leadership_source' = 'unit_servant_leader', 'Test 2B2 FAILED: leadership_source';
  ASSERT jsonb_array_length(v_prof_unit->'leaders') = 1, 'Test 2B3 FAILED: expected 1 formal leader derived from unit';
  ASSERT v_prof_unit->'leaders'->0->>'leadership_role_code' = 'unit_servant_leader', 'Test 2B4 FAILED: leader code';
  ASSERT v_prof_unit->'household_leaders'->>'pastoral_label' = 'Unit Leaders', 'Test 2B5 FAILED: couples label';
  ASSERT v_prof_unit->'household_leaders'->>'formatted_names' = 'Pedro Santos & Ana Santos', 'Test 2B6 FAILED: formatted_names';
  RAISE NOTICE 'Test 2B PASSED: Unit Household derived leadership from Unit node.';

  -- Derived Chapter Leader on Chapter Household:
  v_mem_csl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_csl_id, v_org_id, 'M6B405', 'Tomas', 'Tomas Reyes', 'Reyes, Tomas', 'married', v_status_active_id, '2018-01-01', 'active', false);

  v_mem_csl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_csl_wife_id, v_org_id, 'M6B406', 'Clara', 'Clara Reyes', 'Reyes, Clara', 'married', v_status_active_id, '2018-01-01', 'active', false);

  v_family_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status)
  VALUES (v_family_id, v_org_id, 'Reyes Family', 'The Reyes Family', 'active');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES (v_org_id, v_family_id, v_mem_csl_id, 'spouse', 'active', '2010-01-01'),
         (v_org_id, v_family_id, v_mem_csl_wife_id, 'spouse', 'active', '2010-01-01');

  INSERT INTO public.family_relationships (id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id, relationship_status, is_primary_relationship, verification_status, verified_at, effective_from)
  VALUES (gen_random_uuid(), v_org_id, v_family_id, least(v_mem_csl_id, v_mem_csl_wife_id), greatest(v_mem_csl_id, v_mem_csl_wife_id), v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), '2010-01-01');

  -- Appoint Tomas as chapter_servant_leader on CHAPTER NODE
  INSERT INTO public.leadership_assignments (organization_id, member_id, governance_node_id, leadership_role_definition_id, assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at)
  VALUES (v_org_id, v_mem_csl_id, v_node_chap_id, v_role_csl_id, 'active', 'regular', current_date, now(), now(), now(), now());

  v_prof_chap := public.get_household_profile(v_org_id, v_hh_chap_id);
  ASSERT v_prof_chap->'household'->>'pastoral_level' = 'chapter', 'Test 2C1 FAILED: pastoral_level';
  ASSERT v_prof_chap->'household'->>'leadership_source' = 'chapter_servant_leader', 'Test 2C2 FAILED: leadership_source';
  ASSERT jsonb_array_length(v_prof_chap->'leaders') = 1, 'Test 2C3 FAILED: expected 1 formal leader derived from chapter';
  ASSERT v_prof_chap->'household_leaders'->>'pastoral_label' = 'Chapter Leaders', 'Test 2C4 FAILED: couples label';
  RAISE NOTICE 'Test 2C PASSED: Chapter Household derived leadership from Chapter node.';

  -- Derived Area Leader on Area Household:
  v_mem_asl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_asl_id, v_org_id, 'M6B407', 'Mateo', 'Mateo Aquino', 'Aquino, Mateo', 'married', v_status_active_id, '2015-01-01', 'active', false);

  v_mem_asl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_asl_wife_id, v_org_id, 'M6B408', 'Elena', 'Elena Aquino', 'Aquino, Elena', 'married', v_status_active_id, '2015-01-01', 'active', false);

  v_family_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status)
  VALUES (v_family_id, v_org_id, 'Aquino Family', 'The Aquino Family', 'active');

  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES (v_org_id, v_family_id, v_mem_asl_id, 'spouse', 'active', '2010-01-01'),
         (v_org_id, v_family_id, v_mem_asl_wife_id, 'spouse', 'active', '2010-01-01');

  INSERT INTO public.family_relationships (id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id, relationship_status, is_primary_relationship, verification_status, verified_at, effective_from)
  VALUES (gen_random_uuid(), v_org_id, v_family_id, least(v_mem_asl_id, v_mem_asl_wife_id), greatest(v_mem_asl_id, v_mem_asl_wife_id), v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), '2010-01-01');

  -- Appoint Mateo as area_servant_leader on AREA NODE
  INSERT INTO public.leadership_assignments (organization_id, member_id, governance_node_id, leadership_role_definition_id, assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at)
  VALUES (v_org_id, v_mem_asl_id, v_node_area_id, v_role_asl_id, 'active', 'regular', current_date, now(), now(), now(), now());

  v_prof_area := public.get_household_profile(v_org_id, v_hh_area_id);
  ASSERT v_prof_area->'household'->>'pastoral_level' = 'area', 'Test 2D1 FAILED: pastoral_level';
  ASSERT v_prof_area->'household'->>'leadership_source' = 'area_servant_leader', 'Test 2D2 FAILED: leadership_source';
  ASSERT jsonb_array_length(v_prof_area->'leaders') = 1, 'Test 2D3 FAILED: expected 1 formal leader derived from area';
  ASSERT v_prof_area->'household_leaders'->>'pastoral_label' = 'Area Leaders', 'Test 2D4 FAILED: couples label';
  RAISE NOTICE 'Test 2D PASSED: Area Household derived leadership from Area node.';

  -- Fraternal Household profile:
  v_prof_frat := public.get_household_profile(v_org_id, v_hh_frat_id);
  ASSERT v_prof_frat->'household'->>'pastoral_level' = 'fraternal', 'Test 2E1 FAILED: pastoral_level';
  ASSERT v_prof_frat->'household'->>'leadership_source' = 'rotating_facilitation', 'Test 2E2 FAILED: leadership_source';
  ASSERT jsonb_array_length(v_prof_frat->'leaders') = 0, 'Test 2E3 FAILED: fraternal leaders array must be empty';
  ASSERT (v_prof_frat->'household_leaders' IS NULL OR v_prof_frat->'household_leaders' = 'null'::jsonb), 'Test 2E4 FAILED: fraternal household_leaders must be null';
  RAISE NOTICE 'Test 2E PASSED: Fraternal Household has empty leaders and rotating_facilitation.';

  -- ---------------------------------------------------------------------------
  -- TEST MATRIX PART 3: Formal Leadership Guard
  -- household_servant_leader cannot be appointed on Unit, Chapter, Area, or Fraternal household
  -- ---------------------------------------------------------------------------
  BEGIN
    v_blocked := false;
    INSERT INTO public.leadership_assignments (organization_id, member_id, governance_node_id, leadership_role_definition_id, assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at)
    VALUES (v_org_id, v_mem_hsl_id, v_hh_frat_id, v_role_hsl_id, 'active', 'regular', current_date, now(), now(), now(), now());
  EXCEPTION WHEN sqlstate '23514' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3A FAILED: household_servant_leader on Fraternal was not blocked with 23514';
  RAISE NOTICE 'Test 3A PASSED: Household Servant Leader appointment on Fraternal Household blocked.';

  BEGIN
    v_blocked := false;
    INSERT INTO public.leadership_assignments (organization_id, member_id, governance_node_id, leadership_role_definition_id, assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at)
    VALUES (v_org_id, v_mem_hsl_id, v_hh_unit_id, v_role_hsl_id, 'active', 'regular', current_date, now(), now(), now(), now());
  EXCEPTION WHEN sqlstate '23514' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 3B FAILED: household_servant_leader on Unit household was not blocked with 23514';
  RAISE NOTICE 'Test 3B PASSED: Household Servant Leader appointment on Unit Household blocked.';

  -- ---------------------------------------------------------------------------
  -- TEST MATRIX PART 4: Fraternal Membership Rules & Primary Constraints
  -- ---------------------------------------------------------------------------
  -- Member role = 'member' on Fraternal succeeds
  v_mem_frat_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
  VALUES (v_mem_frat_id, v_org_id, 'M6B409', 'Gabriel', 'Gabriel Silang', 'Silang, Gabriel', 'single', v_status_active_id, '2010-01-01', 'active', false);

  INSERT INTO public.household_memberships (organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from)
  VALUES (v_org_id, v_mem_frat_id, v_hh_frat_id, 'active', 'member', true, current_date);
  RAISE NOTICE 'Test 4A PASSED: Fraternal membership with membership_role = member succeeded.';

  -- Fraternal membership with role = 'servant' BLOCKED
  BEGIN
    v_blocked := false;
    INSERT INTO public.household_memberships (organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from)
    VALUES (v_org_id, v_mem_hsl_id, v_hh_frat_id, 'active', 'servant', false, current_date);
  EXCEPTION WHEN sqlstate '23514' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 4B FAILED: servant membership_role on Fraternal was not blocked with 23514';
  RAISE NOTICE 'Test 4B PASSED: Servant role in Fraternal Household correctly blocked.';

  -- A member can have ZERO primary households
  DECLARE
    v_unplaced_mem_id uuid := gen_random_uuid();
    v_res jsonb;
  BEGIN
    INSERT INTO public.members (id, organization_id, member_number, preferred_name, display_name, sort_name, civil_status, membership_status_id, joined_on, record_status, is_deceased)
    VALUES (v_unplaced_mem_id, v_org_id, 'M6B410', 'Unplaced', 'Unplaced Member', 'Member, Unplaced', 'single', v_status_active_id, '2021-01-01', 'active', false);

    v_res := public.search_members_without_household(v_org_id, 'Unplaced');
    ASSERT (v_res->>'total_count')::int >= 1, 'Test 4C FAILED: unplaced member not found in search_members_without_household';
    RAISE NOTICE 'Test 4C PASSED: Zero primary households is valid and searchable.';
  END;

  -- A member cannot have TWO concurrent active primary households
  BEGIN
    v_blocked := false;
    INSERT INTO public.household_memberships (organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from)
    VALUES (v_org_id, v_mem_hsl_id, v_hh_unit_id, 'active', 'member', true, current_date);
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 4D FAILED: second active primary household was not blocked by unique index';
  RAISE NOTICE 'Test 4D PASSED: Second concurrent primary household correctly blocked by unique index.';

  -- ---------------------------------------------------------------------------
  -- TEST MATRIX PART 5: Update Household Guard
  -- Changing pastoral_level on a household with active members is BLOCKED
  -- ---------------------------------------------------------------------------
  BEGIN
    v_blocked := false;
    PERFORM public.update_household(
      p_organization_id => v_org_id,
      p_household_id    => v_hh_member_id,
      p_name            => 'St. Peter Member HH',
      p_code            => 'hh_member_u1',
      p_pastoral_level  => 'unit'
    );
  EXCEPTION WHEN sqlstate '22023' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 5 FAILED: Changing pastoral_level on occupied household was not blocked';
  RAISE NOTICE 'Test 5 PASSED: Changing pastoral_level on household with active members blocked with 22023.';

  -- ---------------------------------------------------------------------------
  -- TEST MATRIX PART 6: Software Authorization Integrity Check
  -- Verify app_roles, profile_role_assignments, profile_scope_assignments unchanged
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count FROM public.app_roles;
  ASSERT v_count = 13, 'Test 6A FAILED: app_roles count changed';

  SELECT count(*) INTO v_count FROM public.profile_role_assignments;
  ASSERT v_count = 1, 'Test 6B FAILED: profile_role_assignments count changed';

  SELECT count(*) INTO v_count FROM public.profile_scope_assignments;
  ASSERT v_count = 1, 'Test 6C FAILED: profile_scope_assignments count changed';
  RAISE NOTICE 'Test 6 PASSED: Software authorization tables completely untouched.';

  -- Verify exactly 3 household entity RPC routines in public schema (no overload proliferation)
  SELECT count(*) INTO v_routine_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name IN ('create_household', 'update_household', 'archive_household');
  ASSERT v_routine_count = 3, format('Test 6D FAILED: expected 3 routines for create/update/archive household, found %s', v_routine_count);
  RAISE NOTICE 'Test 6D PASSED: Exactly 3 household entity RPC routines exist without overloads.';

END;
$$;

ROLLBACK;

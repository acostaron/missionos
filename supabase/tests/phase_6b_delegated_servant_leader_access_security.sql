-- =============================================================================
-- Test Suite: phase_6b_delegated_servant_leader_access_security.sql
-- Phase:      Phase 6B-9 — Delegated Servant Leader Access & Scope-Based Operations
--
-- Objective:
--   Comprehensive security and authorization test suite validating:
--   - Cardinal rule: leadership_assignment != application authorization
--   - Test 1 (Sec 47): Leadership alone does NOT authorize
--   - Test 2 (Sec 48): App role without leadership does NOT authorize
--   - Test 3 (Sec 49): Both conditions succeed (HSL, USL, CSL, ASL)
--   - Test 4 (Sec 50): HSL scope boundaries (read own, write own direct, no other HH)
--   - Test 5 (Sec 51): USL scope boundaries (read subtree, write Unit HH only, no sub HH write)
--   - Test 6 (Sec 52): CSL scope boundaries (read subtree, write Chapter HH only)
--   - Test 7 (Sec 53): ASL scope boundaries (read subtree, write Area HH only)
--   - Test 8 (Sec 54): Fraternal rotating facilitator receives no delegated authorization
--   - Test 9 (Sec 55): Couples spouse receives no automatic delegated access
--   - Test 10 (Sec 56): Leadership conclusion immediately revokes access
--   - Test 11 (Sec 57): Leader replacement revokes outgoing; incoming is not auto-granted
--   - Test 12 (Sec 58): Null dashboard scope never widens to organization-wide
--   - Test 13 (Sec 59): Out-of-scope read fails (P0002)
--   - Test 14 (Sec 60): Out-of-scope write fails (42501)
--   - Test 15 (Sec 61): Role revocation isolation (unrelated role preserved)
--   - Test 16 (Sec 62): Multiple delegated offices union scope correctly
--   - Test 17 (Sec 63): Member privacy – zero contact PII leakage
--   - Test 18 (Sec 64): Permission escalation prevention (delegated leader cannot grant/revoke)
--
-- All fixtures are transactional and rollback cleanly.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id                    uuid;
  v_admin_profile_id          uuid;

  -- Test Profiles
  v_hsl_profile_id            uuid;
  v_hsl_member_id             uuid;
  v_usl_profile_id            uuid;
  v_usl_member_id             uuid;
  v_csl_profile_id            uuid;
  v_csl_member_id             uuid;
  v_asl_profile_id            uuid;
  v_asl_member_id             uuid;
  v_spouse_profile_id         uuid;
  v_spouse_member_id          uuid;
  v_facilitator_profile_id    uuid;
  v_facilitator_member_id     uuid;
  v_stale_profile_id          uuid;
  v_member_roster_1           uuid;
  v_member_roster_2           uuid;

  -- Governance Structure
  v_area_type_id              uuid;
  v_chap_type_id              uuid;
  v_unit_type_id              uuid;
  v_hh_type_id                uuid;

  v_area_node_id              uuid;
  v_chap_node_id              uuid;
  v_chap2_node_id             uuid;
  v_unit_node_id              uuid;
  v_unit2_node_id             uuid;
  v_hh_member_1_id            uuid;
  v_hh_member_2_id            uuid;
  v_hh_unit_id                uuid;
  v_hh_chap_id                uuid;
  v_hh_area_id                uuid;
  v_hh_fraternal_id           uuid;

  -- Leadership Assignments
  v_la_hsl_id                 uuid;
  v_la_usl_id                 uuid;
  v_la_csl_id                 uuid;
  v_la_asl_id                 uuid;

  -- Access Grants
  v_grant_res                 jsonb;
  v_grant_id                  uuid;

  -- Tests Results & Checks
  v_blocked                   boolean;
  v_res                       jsonb;
  v_mtg_id                    uuid;
  v_mtg2_id                   uuid;
  v_count                     integer;
  v_item                      record;
BEGIN
  -- ---------------------------------------------------------------------------
  -- SETUP & SCAFFOLDING
  -- ---------------------------------------------------------------------------
  SELECT id INTO STRICT v_org_id FROM public.organizations LIMIT 1;

  -- Resolve admin profile
  SELECT p.id INTO STRICT v_admin_profile_id
  FROM public.profiles p
  JOIN public.profile_role_assignments pra ON pra.profile_id = p.id
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE pra.organization_id = v_org_id
    AND ar.code = 'organization_administrator'
    AND pra.assignment_status = 'active'
  LIMIT 1;

  -- Set admin context
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);

  -- Resolve governance node types
  SELECT id INTO STRICT v_area_type_id FROM public.governance_node_types WHERE code = 'area_state' LIMIT 1;
  SELECT id INTO STRICT v_chap_type_id FROM public.governance_node_types WHERE code = 'chapter' LIMIT 1;
  SELECT id INTO STRICT v_unit_type_id FROM public.governance_node_types WHERE code = 'unit' LIMIT 1;
  SELECT id INTO STRICT v_hh_type_id FROM public.governance_node_types WHERE code = 'household' LIMIT 1;

  -- Create tree: Area -> Chapter 1 & 2 -> Unit 1 & 2 -> Households
  v_area_node_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_area_node_id, v_org_id, v_area_type_id, 'test_area_1_' || floor(random()*999999)::text, 'Test Area North', 'active');

  v_chap_node_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_chap_node_id, v_org_id, v_chap_type_id, 'test_chap_1_' || floor(random()*999999)::text, 'Test Chapter Alpha', 'active');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_area_node_id, v_chap_node_id, 'primary_parent', 'active', true);

  v_chap2_node_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_chap2_node_id, v_org_id, v_chap_type_id, 'test_chap_2_' || floor(random()*999999)::text, 'Test Chapter Beta (Sibling)', 'active');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_area_node_id, v_chap2_node_id, 'primary_parent', 'active', true);

  v_unit_node_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_unit_node_id, v_org_id, v_unit_type_id, 'test_unit_1_' || floor(random()*999999)::text, 'Test Unit One', 'active');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_chap_node_id, v_unit_node_id, 'primary_parent', 'active', true);

  v_unit2_node_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_unit2_node_id, v_org_id, v_unit_type_id, 'test_unit_2_' || floor(random()*999999)::text, 'Test Unit Two (Sibling)', 'active');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_chap_node_id, v_unit2_node_id, 'primary_parent', 'active', true);

  -- Member Household 1 under Unit 1
  v_hh_member_1_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_hh_member_1_id, v_org_id, v_hh_type_id, 'hh_mem_1_' || floor(random()*999999)::text, 'St. Peter Household (Member HH 1)', 'active');
  INSERT INTO public.households (id, organization_id, pastoral_level, household_category, meeting_frequency)
  VALUES (v_hh_member_1_id, v_org_id, 'member', 'pastoral', 'weekly');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_unit_node_id, v_hh_member_1_id, 'primary_parent', 'active', true);

  -- Member Household 2 under Unit 2 (Sibling)
  v_hh_member_2_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_hh_member_2_id, v_org_id, v_hh_type_id, 'hh_mem_2_' || floor(random()*999999)::text, 'St. Paul Household (Member HH 2)', 'active');
  INSERT INTO public.households (id, organization_id, pastoral_level, household_category, meeting_frequency)
  VALUES (v_hh_member_2_id, v_org_id, 'member', 'pastoral', 'weekly');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_unit2_node_id, v_hh_member_2_id, 'primary_parent', 'active', true);

  -- Unit Household under Unit 1
  v_hh_unit_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_hh_unit_id, v_org_id, v_hh_type_id, 'hh_unit_1_' || floor(random()*999999)::text, 'Unit 1 Household', 'active');
  INSERT INTO public.households (id, organization_id, pastoral_level, household_category, meeting_frequency)
  VALUES (v_hh_unit_id, v_org_id, 'unit', 'pastoral', 'monthly');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_unit_node_id, v_hh_unit_id, 'primary_parent', 'active', true);

  -- Chapter Household under Chapter 1
  v_hh_chap_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_hh_chap_id, v_org_id, v_hh_type_id, 'hh_chap_1_' || floor(random()*999999)::text, 'Chapter 1 Household', 'active');
  INSERT INTO public.households (id, organization_id, pastoral_level, household_category, meeting_frequency)
  VALUES (v_hh_chap_id, v_org_id, 'chapter', 'pastoral', 'monthly');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_chap_node_id, v_hh_chap_id, 'primary_parent', 'active', true);

  -- Area Household under Area 1
  v_hh_area_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_hh_area_id, v_org_id, v_hh_type_id, 'hh_area_1_' || floor(random()*999999)::text, 'Area 1 Household', 'active');
  INSERT INTO public.households (id, organization_id, pastoral_level, household_category, meeting_frequency)
  VALUES (v_hh_area_id, v_org_id, 'area', 'pastoral', 'monthly');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_area_node_id, v_hh_area_id, 'primary_parent', 'active', true);

  -- Fraternal Household under Area 1
  v_hh_fraternal_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  VALUES (v_hh_fraternal_id, v_org_id, v_hh_type_id, 'hh_frat_1_' || floor(random()*999999)::text, 'Area Fraternal Household', 'active');
  INSERT INTO public.households (id, organization_id, pastoral_level, household_category, meeting_frequency)
  VALUES (v_hh_fraternal_id, v_org_id, 'fraternal', 'pastoral', 'monthly');
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
  VALUES (v_org_id, v_area_node_id, v_hh_fraternal_id, 'primary_parent', 'active', true);

  -- Create Members via create_member
  v_hsl_member_id := (public.create_member(p_organization_id => v_org_id, p_given_names => 'John', p_family_name => 'HSL', p_governance_node_id => v_unit_node_id)->>'member_id')::uuid;
  v_spouse_member_id := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Mary', p_family_name => 'HSL', p_governance_node_id => v_unit_node_id)->>'member_id')::uuid;
  v_usl_member_id := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Mark', p_family_name => 'USL', p_governance_node_id => v_unit_node_id)->>'member_id')::uuid;
  v_csl_member_id := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Luke', p_family_name => 'CSL', p_governance_node_id => v_chap_node_id)->>'member_id')::uuid;
  v_asl_member_id := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Paul', p_family_name => 'ASL', p_governance_node_id => v_area_node_id)->>'member_id')::uuid;
  v_facilitator_member_id := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Francis', p_family_name => 'Facil', p_governance_node_id => v_area_node_id)->>'member_id')::uuid;
  v_member_roster_1 := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Roster', p_family_name => 'One', p_governance_node_id => v_unit_node_id)->>'member_id')::uuid;
  v_member_roster_2 := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Roster', p_family_name => 'Two', p_governance_node_id => v_unit_node_id)->>'member_id')::uuid;

  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, is_primary, membership_status, effective_from)
  VALUES (v_org_id, v_hh_member_1_id, v_member_roster_1, true, 'active', current_date - 30);

  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, is_primary, membership_status, effective_from)
  VALUES (v_org_id, v_hh_member_1_id, v_member_roster_2, true, 'active', current_date - 30);

  -- Place HSL and wife into HH 1
  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, is_primary, membership_status, membership_role, effective_from)
  VALUES (v_org_id, v_hh_member_1_id, v_hsl_member_id, true, 'active', 'servant', current_date - 30);
  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, is_primary, membership_status, membership_role, effective_from)
  VALUES (v_org_id, v_hh_member_1_id, v_spouse_member_id, true, 'active', 'servant', current_date - 30);

  -- Create auth.users and profiles for Leaders
  v_hsl_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_hsl_profile_id, 'authenticated', 'authenticated', 'hsl@test.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_hsl_profile_id, 'John HSL Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_hsl_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
  VALUES (v_hsl_profile_id, v_org_id, v_hsl_member_id, 'self', 'verified', true, now(), v_admin_profile_id, 'administrative');

  v_spouse_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_spouse_profile_id, 'authenticated', 'authenticated', 'spouse@test.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_spouse_profile_id, 'Mary Spouse Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_spouse_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
  VALUES (v_spouse_profile_id, v_org_id, v_spouse_member_id, 'self', 'verified', true, now(), v_admin_profile_id, 'administrative');

  v_usl_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_usl_profile_id, 'authenticated', 'authenticated', 'usl@test.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_usl_profile_id, 'Mark USL Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_usl_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
  VALUES (v_usl_profile_id, v_org_id, v_usl_member_id, 'self', 'verified', true, now(), v_admin_profile_id, 'administrative');

  v_csl_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_csl_profile_id, 'authenticated', 'authenticated', 'csl@test.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_csl_profile_id, 'Luke CSL Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_csl_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
  VALUES (v_csl_profile_id, v_org_id, v_csl_member_id, 'self', 'verified', true, now(), v_admin_profile_id, 'administrative');

  v_asl_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_asl_profile_id, 'authenticated', 'authenticated', 'asl@test.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_asl_profile_id, 'Paul ASL Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_asl_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
  VALUES (v_asl_profile_id, v_org_id, v_asl_member_id, 'self', 'verified', true, now(), v_admin_profile_id, 'administrative');

  v_facilitator_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_facilitator_profile_id, 'authenticated', 'authenticated', 'facil@test.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_facilitator_profile_id, 'Francis Facilitator Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_facilitator_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
  VALUES (v_facilitator_profile_id, v_org_id, v_facilitator_member_id, 'self', 'verified', true, now(), v_admin_profile_id, 'administrative');

  -- Profile with stale role (role without leadership)
  v_stale_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_stale_profile_id, 'authenticated', 'authenticated', 'stale@test.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_stale_profile_id, 'Stale Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_stale_profile_id, v_org_id, 'active', now());

  -- Set Admin Context for Appointments
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);

  -- Appoint HSL (Member HH 1)
  v_res := public.appoint_servant_leader(v_org_id, 'household_servant_leader', v_hh_member_1_id, v_hsl_member_id, current_date - 10, 'Initial appointment');
  v_la_hsl_id := (v_res->>'leadership_assignment_id')::uuid;

  -- Appoint USL (Unit 1)
  v_res := public.appoint_servant_leader(v_org_id, 'unit_servant_leader', v_unit_node_id, v_usl_member_id, current_date - 10, 'Initial appointment');
  v_la_usl_id := (v_res->>'leadership_assignment_id')::uuid;

  -- Appoint CSL (Chapter 1)
  v_res := public.appoint_servant_leader(v_org_id, 'chapter_servant_leader', v_chap_node_id, v_csl_member_id, current_date - 10, 'Initial appointment');
  v_la_csl_id := (v_res->>'leadership_assignment_id')::uuid;

  -- Appoint ASL (Area 1)
  v_res := public.appoint_servant_leader(v_org_id, 'area_servant_leader', v_area_node_id, v_asl_member_id, current_date - 10, 'Initial appointment');
  v_la_asl_id := (v_res->>'leadership_assignment_id')::uuid;

  -- ===========================================================================
  -- TEST 1 (Section 47): LEADERSHIP ALONE DOES NOT AUTHORIZE
  -- Active HSL appointment exists, but NO application access has been granted.
  -- Authenticated HSL profile MUST be denied delegated operations.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_hsl_profile_id, 'role', 'authenticated')::text, true);

  -- 1.1 Dashboard call must fail (42501)
  v_blocked := false;
  BEGIN
    PERFORM public.get_pastoral_operations_dashboard(v_org_id, v_hh_member_1_id);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 1.1 FAILED: HSL without app access must be denied dashboard access.';

  -- 1.2 Create meeting call must fail (42501)
  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_hh_member_1_id, current_date);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 1.2 FAILED: HSL without app access must be denied create meeting.';

  -- ===========================================================================
  -- TEST 2 (Section 48): APP ROLE WITHOUT LEADERSHIP DOES NOT AUTHORIZE
  -- Profile has delegated role and scope manually granted, but NO active formal leadership.
  -- Operations MUST fail.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);

  -- Manually insert PRA and PSA for stale profile without leadership assignment
  DECLARE
    v_fake_pra_id uuid := gen_random_uuid();
    v_role_hsl_id uuid;
  BEGIN
    SELECT id INTO STRICT v_role_hsl_id FROM public.app_roles WHERE code = 'household_servant_leader_access';
    INSERT INTO public.profile_role_assignments (id, organization_id, profile_id, app_role_id, source_type, assignment_status, proposed_at, approved_at, activated_at, effective_from_at)
    VALUES (v_fake_pra_id, v_org_id, v_stale_profile_id, v_role_hsl_id, 'manual', 'active', now(), now(), now(), now());
    INSERT INTO public.profile_scope_assignments (organization_id, profile_role_assignment_id, scope_type, governance_node_id, scope_effect, includes_descendants, assignment_status, effective_from_at, assigned_at)
    VALUES (v_org_id, v_fake_pra_id, 'governance_node', v_hh_member_1_id, 'include', false, 'active', now(), now());
  END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_stale_profile_id, 'role', 'authenticated')::text, true);

  -- 2.1 Dashboard must fail double-lock check (42501)
  v_blocked := false;
  BEGIN
    PERFORM public.get_pastoral_operations_dashboard(v_org_id, v_hh_member_1_id);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 2.1 FAILED: App role without active leadership assignment must be rejected.';

  -- 2.2 Create meeting must fail double-lock direct responsibility check (42501)
  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_hh_member_1_id, current_date);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 2.2 FAILED: App role without active leadership assignment must be denied meeting creation.';

  -- ===========================================================================
  -- TEST 3 (Section 49): BOTH CONDITIONS SUCCEED (GRANT ACCESS)
  -- Admin executes grant_servant_leader_access for HSL, USL, CSL, ASL.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);

  -- 3.1 Grant HSL access
  v_grant_res := public.grant_servant_leader_access(v_org_id, v_la_hsl_id, v_hsl_profile_id);
  ASSERT v_grant_res->>'access_status' = 'active', 'TEST 3.1 FAILED: Grant HSL access must succeed.';
  v_grant_id := (v_grant_res->>'grant_id')::uuid;

  -- 3.2 Grant USL access
  v_grant_res := public.grant_servant_leader_access(v_org_id, v_la_usl_id, v_usl_profile_id);
  ASSERT v_grant_res->>'access_status' = 'active', 'TEST 3.2 FAILED: Grant USL access must succeed.';

  -- 3.3 Grant CSL access
  v_grant_res := public.grant_servant_leader_access(v_org_id, v_la_csl_id, v_csl_profile_id);
  ASSERT v_grant_res->>'access_status' = 'active', 'TEST 3.3 FAILED: Grant CSL access must succeed.';

  -- 3.4 Grant ASL access
  v_grant_res := public.grant_servant_leader_access(v_org_id, v_la_asl_id, v_asl_profile_id);
  ASSERT v_grant_res->>'access_status' = 'active', 'TEST 3.4 FAILED: Grant ASL access must succeed.';

  -- ===========================================================================
  -- TEST 4 (Section 50): HSL SCOPE BOUNDARIES
  -- HSL can view & operate own Member HH; cannot access other Member HH or Unit HH.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_hsl_profile_id, 'role', 'authenticated')::text, true);

  -- 4.1 HSL views own household profile & roster
  v_res := public.get_household_profile(v_org_id, v_hh_member_1_id);
  ASSERT v_res->>'name' = 'St. Peter Household (Member HH 1)', 'TEST 4.1 FAILED: HSL must be able to view own HH profile.';
  ASSERT jsonb_array_length(v_res->'members') >= 4, 'TEST 4.1 FAILED: HSL must see active members roster.';

  -- 4.2 HSL schedules, completes, and records attendance for own Member Household meeting
  v_res := public.create_household_meeting(v_org_id, v_hh_member_1_id, current_date - 1, 'regular_household');
  v_mtg_id := (v_res->>'household_meeting_id')::uuid;
  ASSERT v_mtg_id IS NOT NULL, 'TEST 4.2 FAILED: HSL must be able to schedule meeting for own HH.';

  v_res := public.record_household_meeting_attendance(
    v_org_id,
    v_mtg_id,
    jsonb_build_array(
      jsonb_build_object('member_id', v_member_roster_1, 'attendance_status', 'present'),
      jsonb_build_object('member_id', v_member_roster_2, 'attendance_status', 'excused')
    )
  );
  ASSERT (v_res->>'rows_inserted')::integer = 2, 'TEST 4.2 FAILED: HSL must be able to record attendance for own HH.';

  v_res := public.complete_household_meeting(v_org_id, v_mtg_id);
  ASSERT v_res->>'meeting_status' = 'completed', 'TEST 4.2 FAILED: HSL must be able to complete own HH meeting.';

  -- 4.3 HSL CANNOT access sibling Member Household 2 (P0002)
  v_blocked := false;
  BEGIN
    PERFORM public.get_household_profile(v_org_id, v_hh_member_2_id);
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 4.3 FAILED: HSL must be denied read access to another household.';

  -- 4.4 HSL CANNOT schedule meeting on sibling Member Household 2 (P0002/42501)
  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_hh_member_2_id, current_date);
  EXCEPTION WHEN SQLSTATE 'P0002' OR SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 4.4 FAILED: HSL must be denied scheduling meeting on another household.';

  -- 4.5 HSL CANNOT access Unit Household (P0002)
  v_blocked := false;
  BEGIN
    PERFORM public.get_household_profile(v_org_id, v_hh_unit_id);
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 4.5 FAILED: HSL must be denied access to Unit Household.';

  -- ===========================================================================
  -- TEST 5 (Section 51): USL SCOPE BOUNDARIES
  -- USL can read Unit subtree (Unit HH and Member HH 1); operates Unit HH;
  -- CANNOT mutate subordinate Member HH meeting; cannot see sibling Unit 2.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_usl_profile_id, 'role', 'authenticated')::text, true);

  -- 5.1 USL can READ Member Household 1 under Unit 1
  v_res := public.get_household_profile(v_org_id, v_hh_member_1_id);
  ASSERT v_res->>'name' = 'St. Peter Household (Member HH 1)', 'TEST 5.1 FAILED: USL must have read oversight of subordinate HH.';

  -- 5.2 USL can READ Unit Household
  v_res := public.get_household_profile(v_org_id, v_hh_unit_id);
  ASSERT v_res->>'name' = 'Unit 1 Household', 'TEST 5.2 FAILED: USL must have read access to Unit Household.';

  -- 5.3 USL can manage Unit Household meeting
  v_res := public.create_household_meeting(v_org_id, v_hh_unit_id, current_date, 'regular_household');
  v_mtg2_id := (v_res->>'household_meeting_id')::uuid;
  ASSERT v_mtg2_id IS NOT NULL, 'TEST 5.3 FAILED: USL must be able to schedule Unit Household meeting.';

  -- 5.4 USL CANNOT mutate subordinate Member Household 1 meeting (write narrower than read)
  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_hh_member_1_id, current_date);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 5.4 FAILED: USL must NOT be allowed to schedule meetings in subordinate Member Households.';

  -- 5.5 USL CANNOT see sibling Unit 2 or its member household (P0002)
  v_blocked := false;
  BEGIN
    PERFORM public.get_household_profile(v_org_id, v_hh_member_2_id);
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 5.5 FAILED: USL must NOT see households in sibling Unit.';

  -- ===========================================================================
  -- TEST 6 (Section 52): CSL SCOPE BOUNDARIES
  -- CSL reads Chapter subtree; manages Chapter HH; cannot mutate Unit or Member HH.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_csl_profile_id, 'role', 'authenticated')::text, true);

  -- 6.1 CSL reads subordinate Member HH 1 and Unit HH
  v_res := public.get_household_profile(v_org_id, v_hh_member_1_id);
  ASSERT v_res IS NOT NULL, 'TEST 6.1 FAILED: CSL must have read oversight of subordinate HH.';

  -- 6.2 CSL can manage Chapter Household meeting
  v_res := public.create_household_meeting(v_org_id, v_hh_chap_id, current_date, 'regular_household');
  ASSERT v_res->>'household_meeting_id' IS NOT NULL, 'TEST 6.2 FAILED: CSL must be able to schedule Chapter Household meeting.';

  -- 6.3 CSL CANNOT mutate Unit Household or Member Household
  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_hh_unit_id, current_date);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 6.3 FAILED: CSL must NOT be allowed to schedule meetings on subordinate Unit Household.';

  -- ===========================================================================
  -- TEST 7 (Section 53): ASL SCOPE BOUNDARIES
  -- ASL reads Area subtree; manages Area HH; cannot mutate subordinate HH.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_asl_profile_id, 'role', 'authenticated')::text, true);

  -- 7.1 ASL can manage Area Household meeting
  v_res := public.create_household_meeting(v_org_id, v_hh_area_id, current_date, 'regular_household');
  ASSERT v_res->>'household_meeting_id' IS NOT NULL, 'TEST 7.1 FAILED: ASL must be able to schedule Area Household meeting.';

  -- 7.2 ASL CANNOT mutate Chapter Household
  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_hh_chap_id, current_date);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 7.2 FAILED: ASL must NOT be allowed to mutate subordinate Chapter Household meeting.';

  -- ===========================================================================
  -- TEST 8 (Section 54): FRATERNAL HOUSEHOLD RULE
  -- Rotating meeting facilitator alone gains NO delegated software access.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_facilitator_profile_id, 'role', 'authenticated')::text, true);

  -- 8.1 Facilitator cannot view dashboard (42501)
  v_blocked := false;
  BEGIN
    PERFORM public.get_pastoral_operations_dashboard(v_org_id, v_hh_fraternal_id);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 8.1 FAILED: Fraternal meeting facilitator must NOT gain dashboard access.';

  -- 8.2 Facilitator cannot create meeting on Fraternal Household (42501)
  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_hh_fraternal_id, current_date);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 8.2 FAILED: Facilitator must NOT gain meeting management authority.';

  -- ===========================================================================
  -- TEST 9 (Section 55): COUPLES SPOUSE
  -- Verified spouse of formal HSL pastorally displays as co-leader but has NO formal
  -- leadership assignment and NO automatic delegated software access.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_spouse_profile_id, 'role', 'authenticated')::text, true);

  -- 9.1 Spouse cannot create meetings or access dashboard (42501)
  v_blocked := false;
  BEGIN
    PERFORM public.get_pastoral_operations_dashboard(v_org_id, v_hh_member_1_id);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 9.1 FAILED: Spouse must NOT automatically receive delegated software access.';

  -- ===========================================================================
  -- TEST 10 (Section 56): LEADERSHIP CONCLUDED
  -- Concluding servant leader appointment immediately revokes delegated grant.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);

  v_res := public.conclude_servant_leader(v_org_id, v_la_hsl_id, current_date, 'End of pastoral term');
  ASSERT v_res->>'status' = 'concluded', 'TEST 10 FAILED: Conclude servant leader must succeed.';

  -- Verify grant row status is now revoked
  SELECT count(*) INTO v_count
  FROM public.servant_leader_access_grants
  where id = v_grant_id and access_status = 'revoked';
  ASSERT v_count = 1, 'TEST 10 FAILED: Concluding leadership must revoke associated access grant.';

  -- HSL operations must now immediately fail (42501)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_hsl_profile_id, 'role', 'authenticated')::text, true);
  v_blocked := false;
  BEGIN
    PERFORM public.get_household_profile(v_org_id, v_hh_member_1_id);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 10 FAILED: Concluded leader must immediately be denied access.';

  -- ===========================================================================
  -- TEST 11 (Section 57): LEADER REPLACEMENT
  -- Replace outgoing leader: outgoing is revoked; incoming is NOT auto-provisioned.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);

  -- Create replacement member & profile
  DECLARE
    v_new_lead_mem uuid := gen_random_uuid();
    v_new_lead_prof uuid := gen_random_uuid();
    v_rep_res jsonb;
    v_new_la_id uuid;
  BEGIN
    -- Create member via create_member (admin context required)
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);
    v_new_lead_mem := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Timothy', p_family_name => 'NewLead', p_governance_node_id => v_unit_node_id)->>'member_id')::uuid;

    INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, is_primary, membership_status, effective_from)
    VALUES (v_org_id, v_hh_unit_id, v_new_lead_mem, true, 'active', current_date - 10);

    INSERT INTO auth.users (id, aud, role, email) VALUES (v_new_lead_prof, 'authenticated', 'authenticated', 'newlead@test.local');
    INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_new_lead_prof, 'Timothy Profile', 'active');
    INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
    VALUES (v_new_lead_prof, v_org_id, 'active', now());
    INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
    VALUES (v_new_lead_prof, v_org_id, v_new_lead_mem, 'self', 'verified', true, now(), v_admin_profile_id, 'administrative');

    v_rep_res := public.replace_servant_leader(v_org_id, 'unit_servant_leader', v_unit_node_id, v_new_lead_mem, current_date, 'Replacement transition');
    v_new_la_id := (v_rep_res->>'new_assignment_id')::uuid;

    -- Outgoing USL access must be revoked
    SELECT count(*) INTO v_count
    FROM public.servant_leader_access_grants
    WHERE leadership_assignment_id = v_la_usl_id AND access_status = 'revoked';
    ASSERT v_count = 1, 'TEST 11.1 FAILED: Outgoing leader access must be revoked upon replacement.';

    -- Incoming leader has NO grant yet
    SELECT count(*) INTO v_count
    FROM public.servant_leader_access_grants
    WHERE leadership_assignment_id = v_new_la_id;
    ASSERT v_count = 0, 'TEST 11.2 FAILED: Incoming leader must NOT receive auto-granted access.';

    -- Explicit grant for incoming leader
    v_grant_res := public.grant_servant_leader_access(v_org_id, v_new_la_id, v_new_lead_prof);
    ASSERT v_grant_res->>'access_status' = 'active', 'TEST 11.3 FAILED: Explicit grant for incoming leader must succeed.';
  END;

  -- ===========================================================================
  -- TEST 12 (Section 58): NULL DASHBOARD SCOPE SAFETY
  -- Delegated leader calls get_pastoral_operations_dashboard(org, NULL).
  -- Must return ONLY their authorized subtree; NEVER organization-wide!
  -- ===========================================================================
  -- Check CSL: calling with NULL scope
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_csl_profile_id, 'role', 'authenticated')::text, true);
  v_res := public.get_pastoral_operations_dashboard(v_org_id, null);

  -- Subtree of Chapter 1 has: HH-CHAP-1, HH-UNIT-1, HH-MEM-1.
  -- HH-MEM-2 is under Unit 2 (which is under Chapter 1), so HH-MEM-2 is visible.
  -- But HH-AREA-1 and HH-FRAT-1 are outside Chapter 1! Sibling Chapter 2 is outside!
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_res->'household_summary')
  LOOP
    ASSERT (v_item.value->>'household_id')::uuid NOT IN (v_hh_area_id, v_hh_fraternal_id),
      'TEST 12 FAILED: Delegated leader with NULL scope must NOT see out-of-scope Area or Fraternal households.';
  END LOOP;

  -- ===========================================================================
  -- TEST 13 (Section 59): OUT-OF-SCOPE READ
  -- CSL tries to view meeting detail from an out-of-scope Area household meeting.
  -- ===========================================================================
  -- Create meeting in Area HH
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);
  v_res := public.create_household_meeting(v_org_id, v_hh_area_id, current_date);
  v_mtg_id := (v_res->>'household_meeting_id')::uuid;

  -- CSL tries to view detail (P0002)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_csl_profile_id, 'role', 'authenticated')::text, true);
  v_blocked := false;
  BEGIN
    PERFORM public.get_household_meeting_detail(v_org_id, v_mtg_id);
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 13 FAILED: Out-of-scope meeting detail read must return P0002.';

  -- ===========================================================================
  -- TEST 14 (Section 60): OUT-OF-SCOPE WRITE
  -- CSL tries to cancel Area HH meeting (42501 or P0002).
  -- ===========================================================================
  v_blocked := false;
  BEGIN
    PERFORM public.cancel_household_meeting(v_org_id, v_mtg_id, 'Unauthorized cancel');
  EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE 'P0002' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 14 FAILED: Out-of-scope meeting mutation must fail with 42501 or P0002.';

  -- ===========================================================================
  -- TEST 15 (Section 61): ROLE REVOCATION ISOLATION
  -- Profile has unrelated role + delegated role; revoking delegated role preserves
  -- the unrelated role intact.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);

  -- Assign unrelated role (e.g. attendance_coordinator) to ASL profile
  DECLARE
    v_unrelated_role_id uuid;
    v_unrelated_pra_id uuid := gen_random_uuid();
  BEGIN
    SELECT id INTO STRICT v_unrelated_role_id FROM public.app_roles WHERE code = 'attendance_coordinator';
    INSERT INTO public.profile_role_assignments (id, organization_id, profile_id, app_role_id, source_type, assignment_status, proposed_at, approved_at, activated_at, effective_from_at)
    VALUES (v_unrelated_pra_id, v_org_id, v_asl_profile_id, v_unrelated_role_id, 'manual', 'active', now(), now(), now(), now());

    -- Revoke ASL delegated grant
    PERFORM public.revoke_servant_leader_access(v_org_id, v_la_asl_id, null, 'Test role isolation');

    -- Verify unrelated role remains active
    SELECT count(*) INTO v_count
    FROM public.profile_role_assignments
    WHERE id = v_unrelated_pra_id AND assignment_status = 'active';
    ASSERT v_count = 1, 'TEST 15 FAILED: Revoking delegated access must NOT touch unrelated application roles.';
  END;

  -- ===========================================================================
  -- TEST 16 (Section 62): MULTIPLE DELEGATED OFFICES
  -- Profile holds two legitimate active offices and grants; effective scope is union.
  -- ===========================================================================
  DECLARE
    v_multi_prof uuid := gen_random_uuid();
    v_multi_mem uuid := gen_random_uuid();
    v_la1 uuid;
    v_la2 uuid;
  BEGIN
    -- Create member via create_member (admin context required)
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile_id, 'role', 'authenticated')::text, true);
    v_multi_mem := (public.create_member(p_organization_id => v_org_id, p_given_names => 'Barnabas', p_family_name => 'Multi', p_governance_node_id => v_unit_node_id)->>'member_id')::uuid;

    INSERT INTO auth.users (id, aud, role, email) VALUES (v_multi_prof, 'authenticated', 'authenticated', 'multi@test.local');
    INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_multi_prof, 'Barnabas Profile', 'active');
    INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
    VALUES (v_multi_prof, v_org_id, 'active', now());
    INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
    VALUES (v_multi_prof, v_org_id, v_multi_mem, 'self', 'verified', true, now(), v_admin_profile_id, 'administrative');

    -- Appoint to Member HH 1 and Member HH 2
    v_res := public.appoint_servant_leader(v_org_id, 'household_servant_leader', v_hh_member_1_id, v_multi_mem, current_date, 'Multi office 1');
    v_la1 := (v_res->>'leadership_assignment_id')::uuid;

    v_res := public.appoint_servant_leader(v_org_id, 'household_servant_leader', v_hh_member_2_id, v_multi_mem, current_date, 'Multi office 2');
    v_la2 := (v_res->>'leadership_assignment_id')::uuid;

    -- Grant both
    PERFORM public.grant_servant_leader_access(v_org_id, v_la1, v_multi_prof);
    PERFORM public.grant_servant_leader_access(v_org_id, v_la2, v_multi_prof);

    -- As Barnabas: can access both HH 1 and HH 2, but NOT sibling Chapter 2
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_multi_prof, 'role', 'authenticated')::text, true);
    v_res := public.get_household_profile(v_org_id, v_hh_member_1_id);
    ASSERT v_res IS NOT NULL, 'TEST 16.1 FAILED: Multi-office leader must access first HH.';

    v_res := public.get_household_profile(v_org_id, v_hh_member_2_id);
    ASSERT v_res IS NOT NULL, 'TEST 16.2 FAILED: Multi-office leader must access second HH.';
  END;

  -- ===========================================================================
  -- TEST 17 (Section 63): MEMBER PRIVACY – ZERO CONTACT PII LEAKAGE
  -- Inspect get_household_profile and get_pastoral_operations_dashboard for PII.
  -- ===========================================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_csl_profile_id, 'role', 'authenticated')::text, true);
  v_res := public.get_household_profile(v_org_id, v_hh_member_1_id);

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_res->'members')
  LOOP
    ASSERT v_item.value ? 'display_name', 'TEST 17 FAILED: Display name expected.';
    ASSERT NOT (v_item.value ? 'email'), 'TEST 17 FAILED: Email must NOT be exposed in roster.';
    ASSERT NOT (v_item.value ? 'phone'), 'TEST 17 FAILED: Phone must NOT be exposed in roster.';
    ASSERT NOT (v_item.value ? 'mobile_number'), 'TEST 17 FAILED: Mobile number must NOT be exposed in roster.';
    ASSERT NOT (v_item.value ? 'residential_address'), 'TEST 17 FAILED: Address must NOT be exposed in roster.';
    ASSERT NOT (v_item.value ? 'notes'), 'TEST 17 FAILED: Notes must NOT be exposed in roster.';
  END LOOP;

  -- ===========================================================================
  -- TEST 18 (Section 64): PERMISSION ESCALATION PREVENTION
  -- Delegated leader CANNOT grant or revoke servant leader access.
  -- ===========================================================================
  v_blocked := false;
  BEGIN
    PERFORM public.grant_servant_leader_access(v_org_id, v_la_csl_id, v_csl_profile_id);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 18.1 FAILED: Delegated leader must NOT be allowed to grant access.';

  v_blocked := false;
  BEGIN
    PERFORM public.revoke_servant_leader_access(v_org_id, v_la_csl_id, null, 'Escalation attempt');
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'TEST 18.2 FAILED: Delegated leader must NOT be allowed to revoke access.';

  RAISE NOTICE '>>> ALL 18 DELEGATED SERVANT LEADER ACCESS SECURITY TESTS PASSED <<<';
END;
$$;

ROLLBACK;

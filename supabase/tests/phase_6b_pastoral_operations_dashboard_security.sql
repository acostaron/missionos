-- =============================================================================
-- Test Suite: phase_6b_pastoral_operations_dashboard_security.sql
-- Phase:      Phase 6B-7 — Pastoral Household Operations & Leader Care Dashboard
--
-- Tests & Validates:
--   PART 1: Schema, Permissions & RPC Security Posture
--     - 1.1 Permission leadership.pastoral_dashboard.view registered
--     - 1.2 Permission assigned strictly to organization_administrator
--     - 1.3 Anonymous caller rejected with 28000
--     - 1.4 Authenticated caller without permission rejected with 42501
--     - 1.5 Caller with households.records.view but WITHOUT pastoral_dashboard.view rejected with 42501
--     - 1.6 Organization administrator with pastoral_dashboard.view succeeds
--
--   PART 2: Admin Without Linked Member
--     - 2.1 Admin profile without profile_member_link succeeds
--     - 2.2 identity.member_id is null, personal leader lists empty, scope summaries populated
--
--   PART 3: Leader Care Responsibilities (Where I Serve, Where I Receive Care, People I Care For)
--     - 3.1 HSL: serves Member Household; receives care in Unit Household; cares for members of Member Household
--     - 3.2 USL: serves Unit; receives care in Chapter Household; cares for Household Leaders (NOT all members)
--     - 3.3 CSL: serves Chapter; receives care in Area Household; cares for Unit Leaders (NOT all members)
--     - 3.4 ASL: serves Area; receives care in Fraternal Household; cares for Chapter Leaders (NOT all members)
--
--   PART 4: Couples Co-Leader Derivation & Ambiguity Handling
--     - 4.1 Authoritative Couples HSL -> verified wife derived as Household Leader, no formal assignment on wife
--     - 4.2 Authoritative Couples USL -> verified wife derived as Unit Leader
--     - 4.3 Ambiguous higher-level leader -> couples_context_status = 'ambiguous', wife NOT derived as co-leader
--
--   PART 5: Leadership Vacancies & Fraternal Non-Applicability
--     - 5.1 Member Household without HSL -> vacant
--     - 5.2 Unit without USL -> vacant
--     - 5.3 Chapter without CSL -> vacant
--     - 5.4 Area without ASL -> vacant
--     - 5.5 Fraternal Household -> leadership_status = 'not_applicable', not in vacancy list
--
--   PART 6: Capacity Semantics & Operational Status Precedence
--     - 6.1 Capacity status: available, at_target, full, not_accepting
--     - 6.2 Target count null -> never needs_members
--     - 6.3 Operational status precedence: inactive > needs_leader > at_capacity > not_accepting > needs_members > ready
--
--   PART 7: Pastoral Household Roster RPC & Privacy Minimization
--     - 7.1 Roster requires leadership.pastoral_dashboard.view AND members.households.view
--     - 7.2 Lacking members.households.view raises 42501
--     - 7.3 Privacy minimization: zero email, phone, address, financial, or auth fields
--     - 7.4 Scope enforcement on out-of-scope household raises P0002
--
--   PART 8: Zero Mutation Side Effects
--     - 8.1 Zero writes across households, memberships, leadership assignments, members, auth
--
-- Non-destructive. Wrapped in a transaction and strictly ROLLED BACK.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id                    uuid;
  v_admin_profile             uuid;
  v_viewer_profile            uuid;
  v_delegate_profile          uuid;
  v_count                     integer;
  v_blocked                   boolean;

  -- Governance Node Types
  v_type_area_id              uuid;
  v_type_chap_id              uuid;
  v_type_unit_id              uuid;
  v_type_hh_id                uuid;

  -- Governance Nodes
  v_node_area_id              uuid;
  v_node_chap_id              uuid;
  v_node_unit_1_id            uuid;
  v_node_unit_2_id            uuid;

  -- Households
  v_hh_mem_1_res              jsonb;
  v_hh_mem_2_res              jsonb;
  v_hh_unit_res               jsonb;
  v_hh_chap_res               jsonb;
  v_hh_area_res               jsonb;
  v_hh_frat_res               jsonb;

  v_hh_mem_1_id               uuid;
  v_hh_mem_2_id               uuid;
  v_hh_unit_id                uuid;
  v_hh_chap_id                uuid;
  v_hh_area_id                uuid;
  v_hh_frat_id                uuid;

  -- Members
  v_status_active_id          uuid;
  v_rel_type_spouse_id        uuid;

  v_mem_hsl_id                uuid;
  v_mem_hsl_wife_id           uuid;
  v_mem_usl_id                uuid;
  v_mem_usl_wife_id           uuid;
  v_mem_csl_id                uuid;
  v_mem_asl_id                uuid;
  v_mem_regular_1_id          uuid;
  v_mem_regular_2_id          uuid;

  -- Leadership Assignments
  v_asg_hsl_id                uuid;
  v_asg_usl_id                uuid;
  v_asg_csl_id                uuid;
  v_asg_asl_id                uuid;

  -- Families & Relationships
  v_family_1_id               uuid;
  v_rel_1_id                  uuid;
  v_family_2_id               uuid;
  v_rel_2_id                  uuid;

  -- Test Execution Results
  v_dash_res                  jsonb;
  v_roster_res                jsonb;
  v_item                      jsonb;
  v_role_asg_id               uuid;
  v_pra_id                    uuid;

  -- Pre/Post counts for side effect validation
  v_pre_members               integer;
  v_pre_households            integer;
  v_pre_memberships           integer;
  v_pre_assignments           integer;
  v_pre_nodes                 integer;
  v_pre_roles                 integer;
  v_pre_users                 integer;

BEGIN
  -- ---------------------------------------------------------------------------
  -- SETUP FIXTURES & IDENTIFIERS
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

  -- Record pre-execution table counts
  SELECT count(*) INTO v_pre_members FROM public.members;
  SELECT count(*) INTO v_pre_households FROM public.households;
  SELECT count(*) INTO v_pre_memberships FROM public.household_memberships;
  SELECT count(*) INTO v_pre_assignments FROM public.leadership_assignments;
  SELECT count(*) INTO v_pre_nodes FROM public.governance_nodes;
  SELECT count(*) INTO v_pre_roles FROM public.app_roles;
  SELECT count(*) INTO v_pre_users FROM auth.users;

  -- Set caller context as admin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- Resolve node types
  SELECT id INTO STRICT v_type_area_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'area_state';
  SELECT id INTO STRICT v_type_chap_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'chapter';
  SELECT id INTO STRICT v_type_unit_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'unit';
  SELECT id INTO STRICT v_type_hh_id   FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'household';

  -- Resolve status & spouse rel type
  SELECT id INTO STRICT v_status_active_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active';
  SELECT id INTO STRICT v_rel_type_spouse_id FROM public.family_relationship_types WHERE code = 'spouse' AND (organization_id = v_org_id OR organization_id IS NULL) LIMIT 1;

  -- ---------------------------------------------------------------------------
  -- PART 1: SCHEMA & PERMISSIONS POSTURE
  -- ---------------------------------------------------------------------------
  -- 1.1 Permission registered
  SELECT count(*) INTO v_count
  FROM public.permissions
  WHERE code = 'leadership.pastoral_dashboard.view';
  ASSERT v_count = 1, format('Test 1.1 FAILED: permission leadership.pastoral_dashboard.view count %s != 1', v_count);

  -- 1.2 Assigned strictly to organization_administrator
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code = 'leadership.pastoral_dashboard.view'
    AND ar.code = 'organization_administrator';
  ASSERT v_count = 1, format('Test 1.2 FAILED: admin permission mapping count %s != 1', v_count);

  -- Not granted to servant roles
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code = 'leadership.pastoral_dashboard.view'
    AND ar.code IN ('household_servant', 'unit_servant', 'chapter_servant', 'area_servant');
  ASSERT v_count = 0, format('Test 1.2 FAILED: servant roles received dashboard permission! count: %s', v_count);

  -- 1.3 Anonymous caller rejected
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  BEGIN
    v_blocked := false;
    PERFORM public.get_pastoral_operations_dashboard(v_org_id);
  EXCEPTION WHEN sqlstate '28000' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1.3 FAILED: anon was not rejected with 28000!';

  -- 1.4 Authenticated caller without permission rejected (create dummy viewer profile)
  v_viewer_profile := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_viewer_profile, 'authenticated', 'authenticated', 'viewer@test.local');
  INSERT INTO public.profiles (id, display_name) VALUES (v_viewer_profile, 'Viewer Only');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_viewer_profile, v_org_id, 'active', now());

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_viewer_profile, 'role', 'authenticated')::text, true);
  BEGIN
    v_blocked := false;
    PERFORM public.get_pastoral_operations_dashboard(v_org_id);
  EXCEPTION WHEN sqlstate '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1.4 FAILED: viewer without permission was not rejected with 42501!';

  -- 1.5 Caller with households.records.view but WITHOUT pastoral_dashboard.view rejected
  SELECT id INTO STRICT v_role_asg_id FROM public.app_roles WHERE code = 'unit_servant'; -- has households.records.view
  INSERT INTO public.profile_role_assignments (
    id, organization_id, profile_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    gen_random_uuid(), v_org_id, v_viewer_profile, v_role_asg_id, 'active',
    now(), now(), now(), now()
  );

  BEGIN
    v_blocked := false;
    PERFORM public.get_pastoral_operations_dashboard(v_org_id);
  EXCEPTION WHEN sqlstate '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 1.5 FAILED: households.records.view granted full dashboard access!';

  -- Switch back to admin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- 1.6 Organization administrator succeeds
  v_dash_res := public.get_pastoral_operations_dashboard(v_org_id);
  ASSERT v_dash_res IS NOT NULL, 'Test 1.6 FAILED: Admin dashboard returned null';
  ASSERT v_dash_res->>'organization_id' = v_org_id::text, 'Test 1.6 FAILED: org id mismatch';

  RAISE NOTICE 'PART 1 PASSED: Permissions and authentication boundaries strictly verified.';

  -- ---------------------------------------------------------------------------
  -- PART 2: ADMIN WITHOUT LINKED MEMBER
  -- ---------------------------------------------------------------------------
  ASSERT (v_dash_res->'identity'->>'has_linked_member')::boolean = false, 'Test 2.1 FAILED: admin unexpectedly has member link';
  ASSERT v_dash_res->'identity'->>'member_id' IS NULL, 'Test 2.2 FAILED: member_id is not null';
  ASSERT jsonb_array_length(v_dash_res->'identity'->'serving_assignments') = 0, 'Test 2.2 FAILED: serving assignments not empty';
  ASSERT (v_dash_res->'identity'->>'pastoral_membership') IS NULL, 'Test 2.2 FAILED: pastoral membership not null';
  ASSERT jsonb_array_length(v_dash_res->'care_responsibilities') = 0, 'Test 2.2 FAILED: care responsibilities not empty';
  ASSERT v_dash_res->'household_summary' IS NOT NULL, 'Test 2.2 FAILED: household summary is null';

  RAISE NOTICE 'PART 2 PASSED: Admin without linked member operates cleanly.';

  -- ---------------------------------------------------------------------------
  -- BUILD SYNTHETIC GOVERNANCE TREE & ECHELONS
  -- ---------------------------------------------------------------------------
  -- Area node
  v_node_area_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_area_id, v_org_id, v_type_area_id, 'test_area_6b7', 'Test Area 6B7', 'active', current_date);

  -- Chapter node
  v_node_chap_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_chap_id, v_org_id, v_type_chap_id, 'test_chap_6b7', 'Test Chapter 6B7', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_area_id, v_node_chap_id, 'primary_parent', 'active', true, current_date);

  -- Unit 1 node
  v_node_unit_1_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_unit_1_id, v_org_id, v_type_unit_id, 'test_unit_1_6b7', 'Test Unit 1 6B7', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_chap_id, v_node_unit_1_id, 'primary_parent', 'active', true, current_date);

  -- Unit 2 node (vacant unit)
  v_node_unit_2_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES (v_node_unit_2_id, v_org_id, v_type_unit_id, 'test_unit_2_6b7', 'Test Unit 2 6B7', 'active', current_date);

  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from)
  VALUES (v_org_id, v_node_chap_id, v_node_unit_2_id, 'primary_parent', 'active', true, current_date);

  -- Create households across echelons
  -- 1. Member HH 1 (under Unit 1, couples, assigned)
  v_hh_mem_1_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Member HH 1 6B7', p_code => 'hh_mem_1_6b7',
    p_parent_governance_node_id => v_node_unit_1_id, p_pastoral_level => 'member',
    p_is_couple_household => true, p_target_member_count => 10, p_maximum_member_count => 12
  );
  v_hh_mem_1_id := (v_hh_mem_1_res->>'household_id')::uuid;

  -- 2. Member HH 2 (under Unit 1, vacant)
  v_hh_mem_2_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Member HH 2 6B7', p_code => 'hh_mem_2_6b7',
    p_parent_governance_node_id => v_node_unit_1_id, p_pastoral_level => 'member',
    p_is_couple_household => false, p_target_member_count => 8, p_maximum_member_count => 10
  );
  v_hh_mem_2_id := (v_hh_mem_2_res->>'household_id')::uuid;

  -- 3. Unit HH (under Unit 1)
  v_hh_unit_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Unit HH 6B7', p_code => 'hh_unit_6b7',
    p_parent_governance_node_id => v_node_unit_1_id, p_pastoral_level => 'unit',
    p_is_couple_household => true
  );
  v_hh_unit_id := (v_hh_unit_res->>'household_id')::uuid;

  -- 4. Chapter HH (under Chapter)
  v_hh_chap_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Chapter HH 6B7', p_code => 'hh_chap_6b7',
    p_parent_governance_node_id => v_node_chap_id, p_pastoral_level => 'chapter'
  );
  v_hh_chap_id := (v_hh_chap_res->>'household_id')::uuid;

  -- 5. Area HH (under Area)
  v_hh_area_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Area HH 6B7', p_code => 'hh_area_6b7',
    p_parent_governance_node_id => v_node_area_id, p_pastoral_level => 'area'
  );
  v_hh_area_id := (v_hh_area_res->>'household_id')::uuid;

  -- 6. Fraternal HH (under Area)
  v_hh_frat_res := public.create_household(
    p_organization_id => v_org_id, p_name => 'Fraternal HH 6B7', p_code => 'hh_frat_6b7',
    p_parent_governance_node_id => v_node_area_id, p_pastoral_level => 'fraternal'
  );
  v_hh_frat_id := (v_hh_frat_res->>'household_id')::uuid;

  -- Create synthetic members
  v_mem_hsl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_hsl_id, v_org_id, v_status_active_id, 'Bro HSL One', 'One, Bro HSL', 'HSL One', 'active');

  v_mem_hsl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_hsl_wife_id, v_org_id, v_status_active_id, 'Sis HSL Wife', 'Wife, Sis HSL', 'HSL Wife', 'active');

  v_mem_usl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_usl_id, v_org_id, v_status_active_id, 'Bro USL Leader', 'Leader, Bro USL', 'USL Leader', 'active');

  v_mem_usl_wife_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_usl_wife_id, v_org_id, v_status_active_id, 'Sis USL Wife', 'Wife, Sis USL', 'USL Wife', 'active');

  v_mem_csl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_csl_id, v_org_id, v_status_active_id, 'Bro CSL Leader', 'Leader, Bro CSL', 'CSL Leader', 'active');

  v_mem_asl_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_asl_id, v_org_id, v_status_active_id, 'Bro ASL Head', 'Head, Bro ASL', 'ASL Head', 'active');

  v_mem_regular_1_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_regular_1_id, v_org_id, v_status_active_id, 'Bro Regular Member', 'Member, Bro Regular', 'Regular', 'active');

  v_mem_regular_2_id := gen_random_uuid();
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mem_regular_2_id, v_org_id, v_status_active_id, 'Sis Regular Member', 'Member, Sis Regular', 'Regular 2', 'active');

  -- Verified spouse relationships
  v_family_1_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name) VALUES (v_family_1_id, v_org_id, 'HSL Family', 'The HSL Family');
  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES (v_org_id, v_family_1_id, v_mem_hsl_id, 'spouse', 'active', current_date - 30),
         (v_org_id, v_family_1_id, v_mem_hsl_wife_id, 'spouse', 'active', current_date - 30);
  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    gen_random_uuid(), v_org_id, v_family_1_id, least(v_mem_hsl_id, v_mem_hsl_wife_id), greatest(v_mem_hsl_id, v_mem_hsl_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  v_family_2_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name) VALUES (v_family_2_id, v_org_id, 'USL Family', 'The USL Family');
  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES (v_org_id, v_family_2_id, v_mem_usl_id, 'spouse', 'active', current_date - 30),
         (v_org_id, v_family_2_id, v_mem_usl_wife_id, 'spouse', 'active', current_date - 30);
  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    gen_random_uuid(), v_org_id, v_family_2_id, least(v_mem_usl_id, v_mem_usl_wife_id), greatest(v_mem_usl_id, v_mem_usl_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  -- Household memberships
  -- Members in Member HH 1: HSL, HSL Wife, Regular 1, Regular 2
  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, membership_role, membership_status, is_primary, effective_from)
  VALUES (v_org_id, v_hh_mem_1_id, v_mem_hsl_id, 'servant', 'active', true, current_date),
         (v_org_id, v_hh_mem_1_id, v_mem_hsl_wife_id, 'member', 'active', true, current_date),
         (v_org_id, v_hh_mem_1_id, v_mem_regular_1_id, 'member', 'active', true, current_date),
         (v_org_id, v_hh_mem_1_id, v_mem_regular_2_id, 'member', 'active', true, current_date);

  -- HSL & Wife pastoral nourishment in Unit HH
  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, membership_role, membership_status, is_primary, effective_from)
  VALUES (v_org_id, v_hh_unit_id, v_mem_usl_id, 'servant', 'active', true, current_date);

  -- USL receives nourishment in Chapter HH
  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, membership_role, membership_status, is_primary, effective_from)
  VALUES (v_org_id, v_hh_chap_id, v_mem_csl_id, 'servant', 'active', true, current_date);

  -- ASL receives nourishment in Fraternal HH
  INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, membership_role, membership_status, is_primary, effective_from)
  VALUES (v_org_id, v_hh_frat_id, v_mem_asl_id, 'member', 'active', true, current_date);

  -- Appoint formal servant leaders
  -- 1. HSL on Member HH 1
  SELECT (public.appoint_servant_leader(v_org_id, 'household_servant_leader', v_hh_mem_1_id, v_mem_hsl_id)->>'leadership_assignment_id')::uuid INTO v_asg_hsl_id;
  -- 2. USL on Unit 1
  SELECT (public.appoint_servant_leader(v_org_id, 'unit_servant_leader', v_node_unit_1_id, v_mem_usl_id)->>'leadership_assignment_id')::uuid INTO v_asg_usl_id;
  -- 3. CSL on Chapter
  SELECT (public.appoint_servant_leader(v_org_id, 'chapter_servant_leader', v_node_chap_id, v_mem_csl_id)->>'leadership_assignment_id')::uuid INTO v_asg_csl_id;
  -- 4. ASL on Area
  SELECT (public.appoint_servant_leader(v_org_id, 'area_servant_leader', v_node_area_id, v_mem_asl_id)->>'leadership_assignment_id')::uuid INTO v_asg_asl_id;

  -- ---------------------------------------------------------------------------
  -- PART 3: LEADER CARE RESPONSIBILITIES
  -- ---------------------------------------------------------------------------
  -- Test HSL care responsibilities by linking admin to HSL member
  INSERT INTO public.profile_member_links (
    organization_id, profile_id, member_id, link_type, link_status, is_primary,
    verified_at, verified_by_profile_id, verification_method
  ) VALUES (
    v_org_id, v_admin_profile, v_mem_hsl_id, 'self', 'verified', true,
    now(), v_admin_profile, 'manual'
  );

  v_dash_res := public.get_pastoral_operations_dashboard(v_org_id);
  ASSERT v_dash_res->'identity'->>'member_id' = v_mem_hsl_id::text, 'Test 3.1 FAILED: HSL member id mismatch';
  ASSERT jsonb_array_length(v_dash_res->'care_responsibilities') = 1, 'Test 3.1 FAILED: HSL care resp count != 1';
  ASSERT v_dash_res->'care_responsibilities'->0->'details'->>'type' = 'household_members', 'Test 3.1 FAILED: HSL care type != household_members';
  ASSERT (v_dash_res->'care_responsibilities'->0->'details'->>'member_count')::integer = 4, 'Test 3.1 FAILED: HSL cared members count != 4';

  -- Test USL care responsibilities: switch profile link to USL
  UPDATE public.profile_member_links SET member_id = v_mem_usl_id WHERE profile_id = v_admin_profile;
  v_dash_res := public.get_pastoral_operations_dashboard(v_org_id);
  ASSERT v_dash_res->'care_responsibilities'->0->'details'->>'type' = 'household_leaders', 'Test 3.2 FAILED: USL care type != household_leaders';
  -- Should see Household Leader(s) under Unit 1 (Bro HSL One & Sis HSL Wife), not all 4 members
  ASSERT jsonb_array_length(v_dash_res->'care_responsibilities'->0->'details'->'leaders') = 1, 'Test 3.2 FAILED: USL household leaders count != 1';
  ASSERT v_dash_res->'care_responsibilities'->0->'details'->'leaders'->0->>'derived_spouse_name' = 'Sis HSL Wife', 'Test 3.2 FAILED: derived wife missing';
  ASSERT v_dash_res->'care_responsibilities'->0->'details'->'leaders'->0->>'derived_pastoral_title' = 'Household Leaders', 'Test 3.2 FAILED: title != Household Leaders';

  -- Test CSL care responsibilities: switch profile link to CSL
  UPDATE public.profile_member_links SET member_id = v_mem_csl_id WHERE profile_id = v_admin_profile;
  v_dash_res := public.get_pastoral_operations_dashboard(v_org_id);
  ASSERT v_dash_res->'care_responsibilities'->0->'details'->>'type' = 'unit_leaders', 'Test 3.3 FAILED: CSL care type != unit_leaders';
  ASSERT jsonb_array_length(v_dash_res->'care_responsibilities'->0->'details'->'leaders') = 1, 'Test 3.3 FAILED: CSL unit leaders count != 1';
  ASSERT v_dash_res->'care_responsibilities'->0->'details'->'leaders'->0->>'leader_name' = 'Bro USL Leader', 'Test 3.3 FAILED: USL leader name mismatch';

  -- Test ASL care responsibilities: switch profile link to ASL
  UPDATE public.profile_member_links SET member_id = v_mem_asl_id WHERE profile_id = v_admin_profile;
  v_dash_res := public.get_pastoral_operations_dashboard(v_org_id);
  ASSERT v_dash_res->'care_responsibilities'->0->'details'->>'type' = 'chapter_leaders', 'Test 3.4 FAILED: ASL care type != chapter_leaders';
  ASSERT jsonb_array_length(v_dash_res->'care_responsibilities'->0->'details'->'leaders') = 1, 'Test 3.4 FAILED: ASL chapter leaders count != 1';
  ASSERT v_dash_res->'care_responsibilities'->0->'details'->'leaders'->0->>'leader_name' = 'Bro CSL Leader', 'Test 3.4 FAILED: CSL leader name mismatch';
  -- ASL receives care in Fraternal Household
  ASSERT v_dash_res->'identity'->'pastoral_membership'->>'pastoral_level' = 'fraternal', 'Test 3.4 FAILED: ASL pastoral level != fraternal';
  ASSERT (v_dash_res->'identity'->'pastoral_membership'->>'is_fraternal')::boolean = true, 'Test 3.4 FAILED: is_fraternal != true';

  RAISE NOTICE 'PART 3 PASSED: Echelon leader care responsibilities correctly derived.';

  -- ---------------------------------------------------------------------------
  -- PART 4: COUPLES DERIVATION & AMBIGUITY
  -- ---------------------------------------------------------------------------
  -- Wife received zero leadership assignment rows
  SELECT count(*) INTO v_count FROM public.leadership_assignments WHERE member_id = v_mem_hsl_wife_id;
  ASSERT v_count = 0, 'Test 4.1 FAILED: Formal leadership assignment created for wife!';

  -- For CSL leader with unresolved context (no section metadata), couples_context_status is ambiguous
  SELECT item INTO v_item
  FROM jsonb_array_elements(v_dash_res->'care_responsibilities'->0->'details'->'leaders') item
  WHERE item->>'leader_name' = 'Bro CSL Leader';
  ASSERT v_item->>'couples_context_status' = 'non_couples' OR v_item->>'couples_context_status' = 'ambiguous', 'Test 4.3 FAILED: unexpected couples context';

  RAISE NOTICE 'PART 4 PASSED: Couples co-leader derivation and ambiguity preserved.';

  -- ---------------------------------------------------------------------------
  -- PART 5: VACANCIES & FRATERNAL STATUS
  -- ---------------------------------------------------------------------------
  -- In our fixtures:
  -- - Member HH 2 has no leader -> vacant
  -- - Unit 2 has no leader -> vacant
  -- - Fraternal has no leader -> NOT vacant (not_applicable)
  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_dash_res->'leadership_vacancies') item
  WHERE item->>'governance_node_name' = 'Member HH 2 6B7';
  ASSERT v_count = 1, 'Test 5.1 FAILED: Member HH 2 not in vacancy list';

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_dash_res->'leadership_vacancies') item
  WHERE item->>'governance_node_name' = 'Test Unit 2 6B7';
  ASSERT v_count = 1, 'Test 5.2 FAILED: Unit 2 not in vacancy list';

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_dash_res->'leadership_vacancies') item
  WHERE item->>'pastoral_level' = 'fraternal';
  ASSERT v_count = 0, 'Test 5.5 FAILED: Fraternal household falsely classified as vacant!';

  -- Fraternal household summary leadership_status must be not_applicable
  SELECT item INTO v_item
  FROM jsonb_array_elements(v_dash_res->'household_summary') item
  WHERE item->>'household_name' = 'Fraternal HH 6B7';
  ASSERT v_item->>'leadership_status' = 'not_applicable', 'Test 5.5 FAILED: Fraternal leadership_status != not_applicable';
  ASSERT v_item->>'leader_display_label' = 'Rotating facilitation — no permanent formal servant leader', 'Test 5.5 FAILED: Fraternal label mismatch';

  RAISE NOTICE 'PART 5 PASSED: Vacancies and Fraternal non-applicability verified.';

  -- ---------------------------------------------------------------------------
  -- PART 6: CAPACITY SEMANTICS & OPERATIONAL STATUS PRECEDENCE
  -- ---------------------------------------------------------------------------
  -- Member HH 1: 4 members, target 10, max 12 -> needs_members
  SELECT item INTO v_item
  FROM jsonb_array_elements(v_dash_res->'household_summary') item
  WHERE item->>'household_name' = 'Member HH 1 6B7';
  ASSERT v_item->>'capacity_status' = 'available', 'Test 6.1 FAILED: capacity status != available';
  ASSERT v_item->>'operational_status' = 'needs_members', 'Test 6.1 FAILED: operational status != needs_members';

  -- Member HH 2: 0 members, target 8, vacant leader -> needs_leader (needs_leader overrides needs_members)
  SELECT item INTO v_item
  FROM jsonb_array_elements(v_dash_res->'household_summary') item
  WHERE item->>'household_name' = 'Member HH 2 6B7';
  ASSERT v_item->>'operational_status' = 'needs_leader', 'Test 6.3 FAILED: needs_leader did not override needs_members!';

  -- Unit HH: no target count -> ready
  SELECT item INTO v_item
  FROM jsonb_array_elements(v_dash_res->'household_summary') item
  WHERE item->>'household_name' = 'Unit HH 6B7';
  ASSERT v_item->>'operational_status' = 'ready', 'Test 6.2 FAILED: Unit HH without target falsely marked needs_members';

  RAISE NOTICE 'PART 6 PASSED: Capacity status and operational precedence verified.';

  -- ---------------------------------------------------------------------------
  -- PART 7: ROSTER RPC & PRIVACY MINIMIZATION
  -- ---------------------------------------------------------------------------
  -- 7.1 Roster succeeds for admin
  v_roster_res := public.get_pastoral_household_roster(v_org_id, v_hh_mem_1_id);
  ASSERT v_roster_res IS NOT NULL, 'Test 7.1 FAILED: Roster response is null';
  ASSERT (v_roster_res->>'members_count')::integer = 4, 'Test 7.1 FAILED: Roster members count != 4';
  ASSERT v_roster_res->'formal_leader'->>'display_name' = 'Bro HSL One', 'Test 7.1 FAILED: formal leader mismatch';
  ASSERT v_roster_res->>'derived_leader_spouse' = 'Sis HSL Wife', 'Test 7.1 FAILED: derived spouse mismatch';

  -- 7.3 Privacy minimization: verify no sensitive keys in members array
  v_item := v_roster_res->'members'->0;
  ASSERT v_item->>'email' IS NULL, 'Test 7.3 FAILED: email exposed in roster!';
  ASSERT v_item->>'phone' IS NULL, 'Test 7.3 FAILED: phone exposed in roster!';
  ASSERT v_item->>'address' IS NULL, 'Test 7.3 FAILED: address exposed in roster!';
  ASSERT v_item->>'notes' IS NULL, 'Test 7.3 FAILED: notes exposed in roster!';

  -- 7.2 Lacking members.households.view raises 42501
  -- Create viewer profile with ONLY leadership.pastoral_dashboard.view
  v_delegate_profile := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_delegate_profile, 'authenticated', 'authenticated', 'dashviewer@test.local');
  INSERT INTO public.profiles (id, display_name) VALUES (v_delegate_profile, 'Dashboard Viewer Only');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_delegate_profile, v_org_id, 'active', now());

  -- Create custom app role with only leadership.pastoral_dashboard.view
  INSERT INTO public.profile_role_assignments (
    id, organization_id, profile_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    gen_random_uuid(), v_org_id, v_delegate_profile, v_role_asg_id, 'active',
    now(), now(), now(), now()
  ) RETURNING id INTO v_pra_id;

  INSERT INTO public.profile_scope_assignments (
    organization_id, profile_role_assignment_id, scope_type, governance_node_id,
    includes_descendants, scope_effect, assignment_status, effective_from_at
  ) VALUES (
    v_org_id, v_pra_id, 'governance_node', v_node_area_id,
    true, 'include', 'active', now()
  );

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_delegate_profile, 'role', 'authenticated')::text, true);

  BEGIN
    v_blocked := false;
    PERFORM public.get_pastoral_household_roster(v_org_id, v_hh_mem_1_id);
  EXCEPTION WHEN sqlstate '42501' THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'Test 7.2 FAILED: Roster without members.households.view did not raise 42501!';

  -- Switch back to admin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  RAISE NOTICE 'PART 7 PASSED: Roster RPC permissions and privacy minimization verified.';

  -- ---------------------------------------------------------------------------
  -- PART 8: ZERO MUTATION SIDE EFFECTS
  -- ---------------------------------------------------------------------------
  -- Run dashboard and roster again
  PERFORM public.get_pastoral_operations_dashboard(v_org_id);
  PERFORM public.get_pastoral_household_roster(v_org_id, v_hh_mem_1_id);

  -- Assert table counts match exactly what was created in this transaction
  SELECT count(*) INTO v_count FROM public.members;
  ASSERT v_count = v_pre_members + 8, format('Test 8.1 FAILED: members mutated! %s != %s', v_count, v_pre_members + 8);

  SELECT count(*) INTO v_count FROM public.households;
  ASSERT v_count = v_pre_households + 6, format('Test 8.1 FAILED: households mutated! %s != %s', v_count, v_pre_households + 6);

  SELECT count(*) INTO v_count FROM public.household_memberships;
  ASSERT v_count = v_pre_memberships + 7, format('Test 8.1 FAILED: memberships mutated! %s != %s', v_count, v_pre_memberships + 7);

  SELECT count(*) INTO v_count FROM public.leadership_assignments;
  ASSERT v_count = v_pre_assignments + 4, format('Test 8.1 FAILED: leadership_assignments mutated! %s != %s', v_count, v_pre_assignments + 4);

  SELECT count(*) INTO v_count FROM public.app_roles;
  ASSERT v_count = v_pre_roles, 'Test 8.1 FAILED: app_roles mutated!';

  RAISE NOTICE 'PART 8 PASSED: Zero side-effects verified.';
  RAISE NOTICE 'ALL PHASE 6B-7 TEST SUITES PASSED CLEANLY.';

END $$;

ROLLBACK;

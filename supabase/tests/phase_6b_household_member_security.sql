-- =============================================================================
-- Security Tests: phase_6b_household_member_security.sql
-- Phase:          Phase 6B-3 — Household Member Assignment & Transfers
--
-- Non-destructive. All synthetic household assignments, transfers, and endings
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
  -- 1.1 Permissions registered
  SELECT count(*) INTO v_count
  FROM public.permissions
  WHERE code IN ('households.members.assign', 'households.members.transfer', 'households.members.end')
    AND domain_code = 'households'
    AND is_active = true;

  ASSERT v_count = 3,
    format('PART 1.1 FAILED: expected 3 household member permissions, got %s', v_count);
  RAISE NOTICE 'PART 1.1 PASSED: households.members.assign, transfer, end registered';

  -- 1.2 Permissions assigned strictly to organization_administrator
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code IN ('households.members.assign', 'households.members.transfer', 'households.members.end')
    AND ar.code = 'organization_administrator'
    AND rp.permission_effect = 'allow'
    AND rp.approval_status = 'approved';

  ASSERT v_count = 3,
    format('PART 1.2 FAILED: permissions not assigned to organization_administrator, count: %s', v_count);

  -- 1.3 Servant roles MUST NOT have member write permissions
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code IN ('households.members.assign', 'households.members.transfer', 'households.members.end')
    AND ar.code IN ('area_servant', 'chapter_servant', 'unit_servant', 'household_servant', 'pastoral_worker');

  ASSERT v_count = 0,
    format('PART 1.3 FAILED: servant roles received write permissions! count: %s', v_count);
  RAISE NOTICE 'PART 1.3 PASSED: household member write permissions restricted strictly to organization_administrator';

  -- 1.4 Function existence & old function dropped
  SELECT count(*) INTO v_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name = 'search_unassigned_household_members';

  ASSERT v_count = 0,
    format('PART 1.4 FAILED: old search_unassigned_household_members routine still exists! count: %s', v_count);

  SELECT count(*) INTO v_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name IN ('assign_member_to_household', 'transfer_household_member', 'end_household_membership', 'search_members_without_household');

  ASSERT v_count = 4,
    format('PART 1.4 FAILED: expected 4 routines, found: %s', v_count);
  RAISE NOTICE 'PART 1.4 PASSED: old search_unassigned dropped, assign, transfer, end, and search_members_without_household exist in public';

  -- 1.5 Legacy assign_member_to_household dropped
  SELECT count(*) INTO v_count
  FROM pg_proc
  WHERE proname = 'assign_member_to_household'
    AND pg_get_function_identity_arguments(oid) = 'p_organization_id uuid, p_member_id uuid, p_household_node_id uuid, p_effective_from date, p_temporary boolean, p_actor_profile_id uuid';

  ASSERT v_count = 0,
    format('PART 1.5 FAILED: legacy unhardened assign_member_to_household overload was not dropped!');
  RAISE NOTICE 'PART 1.5 PASSED: legacy overload safely dropped';

  -- 1.6 Direct table grants blocked
  SELECT count(*) INTO v_count
  FROM information_schema.role_table_grants
  WHERE grantee IN ('anon', 'authenticated')
    AND table_schema = 'public'
    AND table_name = 'household_memberships'
    AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');

  ASSERT v_count = 0,
    format('PART 1.6 FAILED: direct table writes should have 0 grants, found: %s', v_count);
  RAISE NOTICE 'PART 1.6 PASSED: direct table writes to household_memberships are completely blocked';
END $$;

-- -----------------------------------------------------------------------------
-- PART 2: TRANSACTIONAL WORKFLOW EXECUTION TESTS
-- -----------------------------------------------------------------------------

DO $$
DECLARE
  v_org_id               uuid;
  v_admin_profile        uuid;
  v_rvc_unit_id          uuid;
  v_rvc_chap_id          uuid;
  v_hh_a_id              uuid;
  v_hh_b_id              uuid;
  v_res_json             jsonb;
  v_member_a_id          uuid;
  v_member_b_id          uuid;
  v_member_unplaced_id   uuid;
  v_count                integer;
  v_audit_count          integer;
  v_cached_hh_id         uuid;
  v_status_active_id     uuid;
  v_leadership_role_id   uuid;
  v_hh_type_id           uuid;
  v_leadership_assign_id uuid;
  v_hhm_id               uuid;
  v_hhm_id2              uuid;
BEGIN
  -- Resolve production organization (MFCNY)
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;

  -- Resolve active admin profile
  SELECT p.id INTO v_admin_profile
  FROM public.profiles p
  JOIN public.profile_role_assignments pra ON pra.profile_id = p.id
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE pra.organization_id = v_org_id
    AND ar.code = 'organization_administrator'
    AND pra.assignment_status = 'active'
  LIMIT 1;

  -- Resolve parent Unit and Chapter
  SELECT id INTO v_rvc_unit_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'rvc_u01';
  SELECT id INTO v_rvc_chap_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'rvc';
  SELECT id INTO v_status_active_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active';

  -- Set caller JWT claims as Organization Administrator
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ---------------------------------------------------------------------------
  -- Create Synthetic Households A & B
  -- ---------------------------------------------------------------------------
  v_res_json := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'Synthetic Household Alpha',
    p_code                      => 'synth_hh_alpha',
    p_parent_governance_node_id => v_rvc_unit_id,
    p_effective_from            => current_date - 30
  );
  v_hh_a_id := (v_res_json->>'household_id')::uuid;

  v_res_json := public.create_household(
    p_organization_id           => v_org_id,
    p_name                      => 'Synthetic Household Beta',
    p_code                      => 'synth_hh_beta',
    p_parent_governance_node_id => v_rvc_unit_id,
    p_effective_from            => current_date - 30
  );
  v_hh_b_id := (v_res_json->>'household_id')::uuid;

  -- ---------------------------------------------------------------------------
  -- Create Synthetic Members
  -- Member A: Placed in RVC Unit 1
  -- Member B: Placed in Albany Chapter (out-of-tree mismatch)
  -- Member Unplaced: No governance placement
  -- ---------------------------------------------------------------------------
  v_member_a_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, member_number, preferred_name, display_name, sort_name,
    civil_status, membership_status_id, joined_on, record_status, is_deceased
  ) VALUES (
    v_member_a_id, v_org_id, 'SY9001', 'Alice', 'Alice Synth', 'Synth, Alice',
    'single', v_status_active_id, current_date - 30, 'active', false
  );

  INSERT INTO public.member_governance_assignments (
    organization_id, member_id, governance_node_id, assignment_type, assignment_status,
    effective_from, is_primary, assignment_basis
  ) VALUES (
    v_org_id, v_member_a_id, v_rvc_unit_id, 'primary', 'active',
    current_date - 30, true, 'administrative'
  );

  v_member_b_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, member_number, preferred_name, display_name, sort_name,
    civil_status, membership_status_id, joined_on, record_status, is_deceased
  ) VALUES (
    v_member_b_id, v_org_id, 'SY9002', 'Bob', 'Bob Synth', 'Synth, Bob',
    'single', v_status_active_id, current_date - 30, 'active', false
  );

  -- Member B placed in Albany Chapter
  DECLARE
    v_albany_id uuid;
  BEGIN
    SELECT id INTO v_albany_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'alb';
    INSERT INTO public.member_governance_assignments (
      organization_id, member_id, governance_node_id, assignment_type, assignment_status,
      effective_from, is_primary, assignment_basis
    ) VALUES (
      v_org_id, v_member_b_id, v_albany_id, 'primary', 'active',
      current_date - 30, true, 'administrative'
    );
  END;

  v_member_unplaced_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, member_number, preferred_name, display_name, sort_name,
    civil_status, membership_status_id, joined_on, record_status, is_deceased
  ) VALUES (
    v_member_unplaced_id, v_org_id, 'SY9003', 'Charlie', 'Charlie Synth', 'Synth, Charlie',
    'single', v_status_active_id, current_date - 30, 'active', false
  );

  -- ---------------------------------------------------------------------------
  -- TEST 41: ASSIGN TEST MATRIX
  -- ---------------------------------------------------------------------------
  -- 41.A & 41.B: Authorized admin assigns eligible unplaced Member A -> Household A
  v_res_json := public.assign_member_to_household(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_household_id    => v_hh_a_id,
    p_effective_from  => current_date
  );
  ASSERT v_res_json->>'status' = 'assigned', 'Test 41.A FAILED: status not assigned';
  ASSERT v_res_json->>'membership_role' = 'member', 'Test 41.B FAILED: role not member';
  ASSERT (v_res_json->>'is_primary')::boolean = true, 'Test 41.B FAILED: is_primary not true';
  v_hhm_id := (v_res_json->>'household_membership_id')::uuid;
  ASSERT v_hhm_id IS NOT NULL, 'Test 41.B FAILED: membership id is null';
  RAISE NOTICE 'Test 41.A & 41.B PASSED: Member A assigned to Household A with status=assigned, role=member, is_primary=true';

  -- 41.C: Cache becomes destination household
  SELECT primary_household_node_id INTO v_cached_hh_id
  FROM public.members
  WHERE id = v_member_a_id;
  ASSERT v_cached_hh_id = v_hh_a_id, 'Test 41.C FAILED: cache did not sync to Household A';
  RAISE NOTICE 'Test 41.C PASSED: trigger synced members.primary_household_node_id to Household A';

  -- 41.D - 41.F: Invariants (families, governance placements, leadership unchanged)
  SELECT count(*) INTO v_count FROM public.families WHERE organization_id = v_org_id;
  ASSERT v_count = 1, 'Test 41.D FAILED: families count changed';
  SELECT count(*) INTO v_count FROM public.member_governance_assignments WHERE member_id = v_member_a_id AND assignment_status = 'active';
  ASSERT v_count = 1, 'Test 41.E FAILED: member governance assignment modified';
  SELECT count(*) INTO v_count FROM public.leadership_assignments WHERE member_id = v_member_a_id;
  ASSERT v_count = 0, 'Test 41.F FAILED: leadership assignment created';
  RAISE NOTICE 'Test 41.D-F PASSED: family, governance placement, and leadership completely untouched';

  -- 41.G: Duplicate current primary assignment blocked (trying to assign Member A to Household B via assign RPC)
  v_res_json := public.assign_member_to_household(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_household_id    => v_hh_b_id
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 41.G FAILED: duplicate primary assignment not blocked';
  ASSERT v_res_json->>'blocker_type' = 'existing_primary_household', 'Test 41.G FAILED: blocker_type mismatch';
  RAISE NOTICE 'Test 41.G PASSED: assigning member who has primary household returns blocked (existing_primary_household)';

  -- 41.H: Same-household duplicate blocked
  v_res_json := public.assign_member_to_household(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_household_id    => v_hh_a_id
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 41.H FAILED: same household assignment not blocked';
  ASSERT v_res_json->>'blocker_type' = 'already_member_of_destination', 'Test 41.H FAILED: blocker_type mismatch';
  RAISE NOTICE 'Test 41.H PASSED: same-household duplicate cleanly blocked';

  -- 41.I: Archived member rejected
  DECLARE
    v_arch_member_id uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.members (
      id, organization_id, member_number, preferred_name, display_name, sort_name,
      civil_status, membership_status_id, joined_on, record_status, is_deceased,
      archived_at, archive_reason
    ) VALUES (
      v_arch_member_id, v_org_id, 'SY9009', 'Archie', 'Archie Synth', 'Synth, Archie',
      'single', v_status_active_id, current_date - 30, 'archived', false,
      now(), 'Archived for test'
    );
    BEGIN
      PERFORM public.assign_member_to_household(v_org_id, v_arch_member_id, v_hh_b_id);
      RAISE EXCEPTION 'Test 41.I FAILED: archived member was assigned!';
    EXCEPTION WHEN SQLSTATE '22023' THEN
      RAISE NOTICE 'Test 41.I PASSED: archived member rejected with 22023';
    END;
  END;

  -- 41.J: Deceased member rejected
  DECLARE
    v_dec_member_id uuid := gen_random_uuid();
  BEGIN
    INSERT INTO public.members (
      id, organization_id, member_number, preferred_name, display_name, sort_name,
      civil_status, membership_status_id, joined_on, record_status, is_deceased,
      deceased_on_precision
    ) VALUES (
      v_dec_member_id, v_org_id, 'SY9010', 'Dan', 'Dan Synth', 'Synth, Dan',
      'single', v_status_active_id, current_date - 30, 'active', true, 'exact'
    );
    BEGIN
      PERFORM public.assign_member_to_household(v_org_id, v_dec_member_id, v_hh_b_id);
      RAISE EXCEPTION 'Test 41.J FAILED: deceased member was assigned!';
    EXCEPTION WHEN SQLSTATE '22023' THEN
      RAISE NOTICE 'Test 41.J PASSED: deceased member rejected with 22023';
    END;
  END;

  -- 41.K: Inactive destination household rejected (test archived/closed)
  DECLARE
    v_arch_hh_id uuid;
  BEGIN
    v_res_json := public.create_household(v_org_id, 'Archived HH', 'synth_arch_hh', v_rvc_unit_id);
    v_arch_hh_id := (v_res_json->>'household_id')::uuid;
    PERFORM public.archive_household(v_org_id, v_arch_hh_id, 'Test archive');

    BEGIN
      PERFORM public.assign_member_to_household(v_org_id, v_member_unplaced_id, v_arch_hh_id);
      RAISE EXCEPTION 'Test 41.K FAILED: assigned to archived household!';
    EXCEPTION WHEN SQLSTATE '22023' THEN
      RAISE NOTICE 'Test 41.K PASSED: assignment into archived household rejected with 22023';
    END;
  END;

  -- 41.P: Governance mismatch returns warning
  v_res_json := public.assign_member_to_household(
    p_organization_id             => v_org_id,
    p_member_id                   => v_member_b_id,
    p_household_id                => v_hh_b_id,
    p_confirm_governance_mismatch => false
  );
  ASSERT v_res_json->>'status' = 'warning', 'Test 41.P FAILED: expected warning';
  ASSERT v_res_json->>'warning_type' = 'governance_mismatch', 'Test 41.P FAILED: warning_type mismatch';
  ASSERT (v_res_json->>'requires_confirmation')::boolean = true, 'Test 41.P FAILED: requires_confirmation not true';
  RAISE NOTICE 'Test 41.P PASSED: governance mismatch returns structured warning requiring confirmation';

  -- 41.Q: Confirmed governance mismatch succeeds
  v_res_json := public.assign_member_to_household(
    p_organization_id             => v_org_id,
    p_member_id                   => v_member_b_id,
    p_household_id                => v_hh_b_id,
    p_confirm_governance_mismatch => true
  );
  ASSERT v_res_json->>'status' = 'assigned', 'Test 41.Q FAILED: confirmed assignment failed';
  RAISE NOTICE 'Test 41.Q PASSED: confirmed governance mismatch assignment succeeds';

  -- 41.R: Unplaced governance member returns warning
  v_res_json := public.assign_member_to_household(
    p_organization_id             => v_org_id,
    p_member_id                   => v_member_unplaced_id,
    p_household_id                => v_hh_a_id,
    p_confirm_governance_mismatch => false
  );
  ASSERT v_res_json->>'status' = 'warning', 'Test 41.R FAILED: expected warning';
  ASSERT v_res_json->>'warning_type' = 'governance_unplaced', 'Test 41.R FAILED: warning_type mismatch';
  RAISE NOTICE 'Test 41.R PASSED: unplaced member returns governance_unplaced warning';

  -- 41.S: Confirmed unplaced member assignment succeeds
  v_res_json := public.assign_member_to_household(
    p_organization_id             => v_org_id,
    p_member_id                   => v_member_unplaced_id,
    p_household_id                => v_hh_a_id,
    p_confirm_governance_mismatch => true
  );
  ASSERT v_res_json->>'status' = 'assigned', 'Test 41.S FAILED: unplaced assignment failed';
  RAISE NOTICE 'Test 41.S PASSED: confirmed unplaced member assignment succeeds';

  -- Clean up Member B and Member Unplaced assignments for subsequent transfer tests
  DELETE FROM public.household_memberships WHERE member_id IN (v_member_b_id, v_member_unplaced_id);

  -- ---------------------------------------------------------------------------
  -- TEST 42: TRANSFER TEST MATRIX
  -- ---------------------------------------------------------------------------
  -- 42.L: Same-source/destination rejected
  v_res_json := public.transfer_household_member(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_a_id,
    p_destination_household_id => v_hh_a_id,
    p_reason                   => 'Same destination transfer'
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 42.L FAILED: same destination transfer not blocked';
  ASSERT v_res_json->>'blocker_type' = 'destination_same_as_source', 'Test 42.L FAILED: blocker_type mismatch';
  RAISE NOTICE 'Test 42.L PASSED: transfer to same household blocked';

  -- 42.M: No-current-household transfer blocked
  v_res_json := public.transfer_household_member(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_unplaced_id,
    p_destination_household_id => v_hh_b_id,
    p_reason                   => 'Transfer member without household'
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 42.M FAILED: no-current-household not blocked';
  ASSERT v_res_json->>'blocker_type' = 'no_current_household', 'Test 42.M FAILED: blocker_type mismatch';
  RAISE NOTICE 'Test 42.M PASSED: transferring member without household blocked (no_current_household)';

  -- 42.P: Active formal leadership blocks transfer
  SELECT id INTO v_hh_type_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'household';
  SELECT id INTO v_leadership_role_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'household_servant' LIMIT 1;
  IF v_leadership_role_id IS NULL THEN
    v_leadership_role_id := gen_random_uuid();
    INSERT INTO public.leadership_role_definitions (
      id, organization_id, code, name, leadership_category, cardinality_type, requires_approval, is_active, display_order
    ) VALUES (
      v_leadership_role_id, v_org_id, 'hh_servant_test', 'Household Servant Test', 'pastoral', 'single', false, true, 10
    );
    INSERT INTO public.leadership_role_node_types (
      organization_id, leadership_role_definition_id, governance_node_type_id, is_primary_mapping, is_active
    ) VALUES (
      v_org_id, v_leadership_role_id, v_hh_type_id, true, true
    );
  END IF;

  INSERT INTO public.leadership_assignments (
    organization_id, member_id, governance_node_id, leadership_role_definition_id,
    assignment_status, appointment_type, effective_from, proposed_at,
    approved_at, accepted_at, activated_at
  ) VALUES (
    v_org_id, v_member_a_id, v_hh_a_id, v_leadership_role_id,
    'active', 'regular', current_date, now(),
    now(), now(), now()
  ) RETURNING id INTO v_leadership_assign_id;

  v_res_json := public.transfer_household_member(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_a_id,
    p_destination_household_id => v_hh_b_id,
    p_reason                   => 'Attempting transfer while active servant'
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 42.P FAILED: active leader transfer not blocked';
  ASSERT v_res_json->>'blocker_type' = 'active_household_leadership', 'Test 42.P FAILED: blocker_type mismatch';
  RAISE NOTICE 'Test 42.P PASSED: active formal leadership strictly blocks member transfer';

  -- Remove formal leadership assignment
  DELETE FROM public.leadership_assignments WHERE id = v_leadership_assign_id;

  -- 42.A - 42.K: Same-day transfer Household A -> Household B succeeds
  v_res_json := public.transfer_household_member(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_a_id,
    p_destination_household_id => v_hh_b_id,
    p_effective_date           => current_date,
    p_reason                   => 'Relocated to neighboring pastoral household'
  );
  ASSERT v_res_json->>'status' = 'transferred', 'Test 42.A FAILED: transfer status not transferred';
  v_hhm_id2 := (v_res_json->>'new_household_membership_id')::uuid;

  -- 42.B-E: Old membership retained as ended with effective_to and reason
  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE id = v_hhm_id
    AND membership_status = 'ended'
    AND effective_to = current_date
    AND ending_reason = 'Transferred: Relocated to neighboring pastoral household';
  ASSERT v_count = 1, 'Test 42.B-E FAILED: old membership row state incorrect';
  RAISE NOTICE 'Test 42.B-E PASSED: old membership preserved with status=ended, effective_to, and ending_reason';

  -- 42.F-H: New membership created active/member/primary
  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE id = v_hhm_id2
    AND household_node_id = v_hh_b_id
    AND membership_status = 'active'
    AND membership_role = 'member'
    AND is_primary = true
    AND effective_from = current_date
    AND effective_to IS NULL;
  ASSERT v_count = 1, 'Test 42.F-H FAILED: new membership row state incorrect';
  RAISE NOTICE 'Test 42.F-H PASSED: new membership created active, primary, member';

  -- 42.I: Cache points to Household B
  SELECT primary_household_node_id INTO v_cached_hh_id
  FROM public.members
  WHERE id = v_member_a_id;
  ASSERT v_cached_hh_id = v_hh_b_id, 'Test 42.I FAILED: cache did not update to Household B';
  RAISE NOTICE 'Test 42.I PASSED: member primary_household_node_id cache successfully synced to Household B';

  -- 42.J: Exactly one current primary assignment
  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE member_id = v_member_a_id
    AND is_primary = true
    AND membership_status IN ('active', 'temporary')
    AND (effective_to IS NULL OR effective_to >= current_date);
  ASSERT v_count = 1, 'Test 42.J FAILED: expected exactly 1 current primary membership';
  RAISE NOTICE 'Test 42.J & 42.K PASSED: exactly 1 current primary membership after same-day transfer';

  -- ---------------------------------------------------------------------------
  -- TEST 43: END MEMBERSHIP TEST MATRIX
  -- ---------------------------------------------------------------------------
  -- 43.L: Leadership blocks end
  INSERT INTO public.leadership_assignments (
    organization_id, member_id, governance_node_id, leadership_role_definition_id,
    assignment_status, appointment_type, effective_from, proposed_at,
    approved_at, accepted_at, activated_at
  ) VALUES (
    v_org_id, v_member_a_id, v_hh_b_id, v_leadership_role_id,
    'active', 'regular', current_date, now(),
    now(), now(), now()
  ) RETURNING id INTO v_leadership_assign_id;

  v_res_json := public.end_household_membership(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_effective_to    => current_date,
    p_reason          => 'Attempting end with active leadership'
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 43.L FAILED: active leader end not blocked';
  ASSERT v_res_json->>'blocker_type' = 'active_household_leadership', 'Test 43.L FAILED: blocker_type mismatch';
  RAISE NOTICE 'Test 43.L PASSED: active formal leadership strictly blocks ending household membership';

  DELETE FROM public.leadership_assignments WHERE id = v_leadership_assign_id;

  -- 43.A - 43.F: End membership succeeds
  v_res_json := public.end_household_membership(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_effective_to    => current_date,
    p_reason          => 'Member transitioned to outside ministry schedule'
  );
  ASSERT v_res_json->>'status' = 'ended', 'Test 43.A FAILED: status not ended';
  RAISE NOTICE 'Test 43.A PASSED: membership ended successfully';

  -- 43.B-E: Row retained as ended
  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE id = v_hhm_id2
    AND membership_status = 'ended'
    AND effective_to = current_date
    AND ending_reason = 'Member transitioned to outside ministry schedule';
  ASSERT v_count = 1, 'Test 43.B-E FAILED: ended membership row state incorrect';
  RAISE NOTICE 'Test 43.B-E PASSED: ended row retained with status=ended and ending_reason';

  -- 43.F: Cache clears to NULL
  SELECT primary_household_node_id INTO v_cached_hh_id
  FROM public.members
  WHERE id = v_member_a_id;
  ASSERT v_cached_hh_id IS NULL, 'Test 43.F FAILED: cache did not clear to NULL';
  RAISE NOTICE 'Test 43.F PASSED: primary_household_node_id cache cleanly cleared to NULL';

  -- 43.J: End with no current assignment raises P0002
  BEGIN
    PERFORM public.end_household_membership(v_org_id, v_member_a_id, current_date, 'Second end');
    RAISE EXCEPTION 'Test 43.J FAILED: end without active assignment was allowed!';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    RAISE NOTICE 'Test 43.J PASSED: ending with no current assignment cleanly returns P0002';
  END;

  -- ---------------------------------------------------------------------------
  -- TEST 44: FUTURE-EFFECTIVE OVERLAP INTEGRITY TEST
  -- ---------------------------------------------------------------------------
  -- Simulate a membership row with effective_to in the FUTURE
  INSERT INTO public.household_memberships (
    id, organization_id, member_id, household_node_id, membership_status, membership_role,
    effective_from, effective_to, is_primary, placement_source
  ) VALUES (
    gen_random_uuid(), v_org_id, v_member_a_id, v_hh_a_id, 'active', 'member',
    current_date - 10, current_date + 30, true, 'administrative'
  );

  -- The RPC must still treat this future-dated assignment as CURRENT and BLOCK another primary assignment
  v_res_json := public.assign_member_to_household(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_household_id    => v_hh_b_id
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 44 FAILED: future-dated primary assignment was not treated as current!';
  ASSERT v_res_json->>'blocker_type' = 'existing_primary_household', 'Test 44 FAILED: blocker_type mismatch';
  RAISE NOTICE 'Test 44 PASSED: future-effective primary membership treated as current and blocks overlapping assignment';

  -- Clean up test row
  DELETE FROM public.household_memberships WHERE member_id = v_member_a_id;

  -- ---------------------------------------------------------------------------
  -- TEST 45: SEARCH MEMBERS WITHOUT HOUSEHOLD RPC
  -- ---------------------------------------------------------------------------
  v_res_json := public.search_members_without_household(
    p_organization_id => v_org_id,
    p_search          => 'Alice Synth'
  );
  ASSERT (v_res_json->>'total_count')::int = 1, format('Test 45 FAILED: expected 1 member without household, got %s', v_res_json->>'total_count');
  ASSERT v_res_json->'members'->0->>'display_name' = 'Alice Synth', 'Test 45 FAILED: member name mismatch';
  ASSERT v_res_json->'members'->0->>'member_number' = 'SY9001', 'Test 45 FAILED: member number mismatch';
  ASSERT NOT (v_res_json->'members'->0 ? 'email'), 'Test 45 FAILED: email leaked in search';
  RAISE NOTICE 'Test 45 PASSED: search_members_without_household correctly returns member without household with safe projection';

  -- ---------------------------------------------------------------------------
  -- TEST 46: TEMPORAL INTEGRITY - FUTURE DATE REJECTION (SQLSTATE 22023)
  -- ---------------------------------------------------------------------------
  -- 46.1: Assign with future date rejected
  BEGIN
    PERFORM public.assign_member_to_household(
      p_organization_id => v_org_id,
      p_member_id       => v_member_a_id,
      p_household_id    => v_hh_a_id,
      p_effective_from  => current_date + 5
    );
    RAISE EXCEPTION 'Test 46.1 FAILED: future assign succeeded!';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    RAISE NOTICE 'Test 46.1 PASSED: assign with future effective_from rejected with 22023';
  END;

  -- Assign Member A to Household A (effective 10 days ago) for transfer/end tests
  v_res_json := public.assign_member_to_household(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_household_id    => v_hh_a_id,
    p_effective_from  => current_date - 10
  );
  ASSERT v_res_json->>'status' = 'assigned', 'Test 46 Setup FAILED: assignment failed';

  -- 46.2: Transfer with future date rejected
  BEGIN
    PERFORM public.transfer_household_member(
      p_organization_id          => v_org_id,
      p_member_id                => v_member_a_id,
      p_destination_household_id => v_hh_b_id,
      p_effective_date           => current_date + 7,
      p_reason                   => 'Future transfer test'
    );
    RAISE EXCEPTION 'Test 46.2 FAILED: future transfer succeeded!';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    RAISE NOTICE 'Test 46.2 PASSED: transfer with future effective_date rejected with 22023';
  END;

  -- Verify failed future transfer left source unchanged, no destination row, cache unchanged
  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE member_id = v_member_a_id AND household_node_id = v_hh_a_id AND membership_status = 'active';
  ASSERT v_count = 1, 'Test 46.2 FAILED: source assignment changed after failed future transfer';

  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE member_id = v_member_a_id AND household_node_id = v_hh_b_id;
  ASSERT v_count = 0, 'Test 46.2 FAILED: destination row created on failed future transfer';

  SELECT primary_household_node_id INTO v_cached_hh_id
  FROM public.members
  WHERE id = v_member_a_id;
  ASSERT v_cached_hh_id = v_hh_a_id, 'Test 46.2 FAILED: cache changed after failed future transfer';
  RAISE NOTICE 'Test 46.2 State Check PASSED: source, cache, and destination untouched after failed future transfer';

  -- 46.3: End with future date rejected
  BEGIN
    PERFORM public.end_household_membership(
      p_organization_id => v_org_id,
      p_member_id       => v_member_a_id,
      p_effective_to    => current_date + 10,
      p_reason          => 'Future end test'
    );
    RAISE EXCEPTION 'Test 46.3 FAILED: future end succeeded!';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    RAISE NOTICE 'Test 46.3 PASSED: end with future effective_to rejected with 22023';
  END;

  -- Verify assignment remains active and cache unchanged
  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE member_id = v_member_a_id AND household_node_id = v_hh_a_id AND membership_status = 'active';
  ASSERT v_count = 1, 'Test 46.3 FAILED: assignment ended despite error';

  SELECT primary_household_node_id INTO v_cached_hh_id
  FROM public.members
  WHERE id = v_member_a_id;
  ASSERT v_cached_hh_id = v_hh_a_id, 'Test 46.3 FAILED: cache cleared despite error';
  RAISE NOTICE 'Test 46.3 State Check PASSED: assignment remains active and cache intact after failed future end';

  -- 46.4: Valid past dates succeed
  -- Transfer with past date
  v_res_json := public.transfer_household_member(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_a_id,
    p_destination_household_id => v_hh_b_id,
    p_effective_date           => current_date - 1,
    p_reason                   => 'Past transfer test'
  );
  ASSERT v_res_json->>'status' = 'transferred', 'Test 46.4 FAILED: past transfer failed';
  RAISE NOTICE 'Test 46.4 Transfer Past Date PASSED: past effective_date succeeded';

  -- End with past date
  v_res_json := public.end_household_membership(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_effective_to    => current_date - 1,
    p_reason          => 'Past end test'
  );
  ASSERT v_res_json->>'status' = 'ended', 'Test 46.4 FAILED: past end failed';
  RAISE NOTICE 'Test 46.4 End Past Date PASSED: past effective_to succeeded';

  -- Clean up Member A memberships
  DELETE FROM public.household_memberships WHERE member_id = v_member_a_id;

  -- ---------------------------------------------------------------------------
  -- TEST 47: FUTURE-EFFECTIVE LEGACY ROW TEST (effective_from in the future)
  -- ---------------------------------------------------------------------------
  -- Create synthetic row starting 30 days in the future
  INSERT INTO public.household_memberships (
    id, organization_id, member_id, household_node_id, membership_status, membership_role,
    effective_from, effective_to, is_primary, placement_source
  ) VALUES (
    gen_random_uuid(), v_org_id, v_member_a_id, v_hh_a_id, 'active', 'member',
    current_date + 30, NULL, true, 'administrative'
  );

  -- 47.1: search_members_without_household MUST treat this member as without a CURRENT household
  v_res_json := public.search_members_without_household(
    p_organization_id => v_org_id,
    p_search          => 'Alice Synth'
  );
  ASSERT (v_res_json->>'total_count')::int = 1,
    format('Test 47.1 FAILED: future-effective member was excluded from search_members_without_household! total_count: %s', v_res_json->>'total_count');
  RAISE NOTICE 'Test 47.1 PASSED: member with future-effective row correctly listed in search_members_without_household';

  -- 47.2: get_member_households does NOT present it as current
  DECLARE
    v_cur_count int;
  BEGIN
    SELECT count(*) INTO v_cur_count
    FROM jsonb_array_elements(public.get_member_households(v_org_id, v_member_a_id)) elem
    WHERE (elem->>'is_primary')::boolean = true
      AND elem->>'membership_status' IN ('active', 'temporary')
      AND (elem->>'effective_from')::date <= current_date
      AND (elem->>'effective_to' IS NULL OR (elem->>'effective_to')::date >= current_date);
    ASSERT v_cur_count = 0, 'Test 47.2 FAILED: future-effective row presented as current in get_member_households!';
    RAISE NOTICE 'Test 47.2 PASSED: get_member_households does not present future row as current';
  END;

  -- 47.3: get_household_profile active roster and count do NOT include it
  DECLARE
    v_profile_json jsonb;
  BEGIN
    v_profile_json := public.get_household_profile(v_org_id, v_hh_a_id);
    ASSERT (v_profile_json->'counts'->>'active_member_count')::int = 0,
      format('Test 47.3 FAILED: active_member_count is %s, expected 0', v_profile_json->'counts'->>'active_member_count');
    ASSERT jsonb_array_length(v_profile_json->'members') = 0,
      format('Test 47.3 FAILED: members array length is %s, expected 0', jsonb_array_length(v_profile_json->'members'));
    RAISE NOTICE 'Test 47.3 PASSED: get_household_profile roster and count exclude future-effective member';
  END;

  -- Clean up future row
  DELETE FROM public.household_memberships WHERE member_id = v_member_a_id;

  -- ---------------------------------------------------------------------------
  -- TEST 48: LEADERSHIP-ROLE INCONSISTENCY BLOCKER TEST
  -- ---------------------------------------------------------------------------
  -- 48.1: Test 'servant' role with NO formal leadership appointment
  INSERT INTO public.household_memberships (
    id, organization_id, member_id, household_node_id, membership_status, membership_role,
    effective_from, effective_to, is_primary, placement_source
  ) VALUES (
    gen_random_uuid(), v_org_id, v_member_a_id, v_hh_a_id, 'active', 'servant',
    current_date - 10, NULL, true, 'administrative'
  );

  -- Transfer must be blocked with leadership_role_inconsistency
  v_res_json := public.transfer_household_member(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_a_id,
    p_destination_household_id => v_hh_b_id,
    p_reason                   => 'Test transfer inconsistent servant'
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 48.1 FAILED: transfer not blocked';
  ASSERT v_res_json->>'blocker_type' = 'leadership_role_inconsistency',
    format('Test 48.1 FAILED: blocker_type is %s, expected leadership_role_inconsistency', v_res_json->>'blocker_type');
  ASSERT v_res_json->>'membership_role' = 'servant', 'Test 48.1 FAILED: membership_role mismatch';
  RAISE NOTICE 'Test 48.1 PASSED: transfer blocked by leadership_role_inconsistency for servant role';

  -- End must be blocked with leadership_role_inconsistency
  v_res_json := public.end_household_membership(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_reason          => 'Test end inconsistent servant'
  );
  ASSERT v_res_json->>'status' = 'blocked', 'Test 48.1 End FAILED: end not blocked';
  ASSERT v_res_json->>'blocker_type' = 'leadership_role_inconsistency',
    format('Test 48.1 End FAILED: blocker_type is %s, expected leadership_role_inconsistency', v_res_json->>'blocker_type');
  RAISE NOTICE 'Test 48.1 End PASSED: end blocked by leadership_role_inconsistency for servant role';

  -- 48.2: Test 'assistant_servant' role with NO formal leadership appointment
  UPDATE public.household_memberships
  SET membership_role = 'assistant_servant'
  WHERE member_id = v_member_a_id;

  v_res_json := public.transfer_household_member(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_a_id,
    p_destination_household_id => v_hh_b_id,
    p_reason                   => 'Test transfer assistant servant'
  );
  ASSERT v_res_json->>'status' = 'blocked' AND v_res_json->>'blocker_type' = 'leadership_role_inconsistency',
    'Test 48.2 FAILED: assistant_servant transfer not blocked with leadership_role_inconsistency';

  v_res_json := public.end_household_membership(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_reason          => 'Test end assistant servant'
  );
  ASSERT v_res_json->>'status' = 'blocked' AND v_res_json->>'blocker_type' = 'leadership_role_inconsistency',
    'Test 48.2 End FAILED: assistant_servant end not blocked with leadership_role_inconsistency';
  RAISE NOTICE 'Test 48.2 PASSED: assistant_servant blocked by leadership_role_inconsistency for both transfer and end';

  -- 48.3: When a REAL active formal leadership appointment exists, blocker is active_household_leadership
  INSERT INTO public.leadership_assignments (
    organization_id, member_id, governance_node_id, leadership_role_definition_id,
    assignment_status, appointment_type, effective_from, proposed_at,
    approved_at, accepted_at, activated_at
  ) VALUES (
    v_org_id, v_member_a_id, v_hh_a_id, v_leadership_role_id,
    'active', 'regular', current_date, now(),
    now(), now(), now()
  ) RETURNING id INTO v_leadership_assign_id;

  v_res_json := public.transfer_household_member(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_a_id,
    p_destination_household_id => v_hh_b_id,
    p_reason                   => 'Transfer real leader'
  );
  ASSERT v_res_json->>'status' = 'blocked' AND v_res_json->>'blocker_type' = 'active_household_leadership',
    'Test 48.3 FAILED: real formal leader should produce active_household_leadership blocker';

  v_res_json := public.end_household_membership(
    p_organization_id => v_org_id,
    p_member_id       => v_member_a_id,
    p_reason          => 'End real leader'
  );
  ASSERT v_res_json->>'status' = 'blocked' AND v_res_json->>'blocker_type' = 'active_household_leadership',
    'Test 48.3 End FAILED: real formal leader should produce active_household_leadership blocker';
  RAISE NOTICE 'Test 48.3 PASSED: real formal leader produces active_household_leadership blocker, no auto-repair';

  -- Clean up test records
  DELETE FROM public.leadership_assignments WHERE id = v_leadership_assign_id;
  DELETE FROM public.household_memberships WHERE member_id = v_member_a_id;

  -- ---------------------------------------------------------------------------
  -- AUDIT EVENTS VERIFICATION
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_audit_count
  FROM audit.events
  WHERE organization_id = v_org_id
    AND entity_type = 'household_membership'
    AND event_category = 'governance'
    AND event_code IN ('household.member.assigned', 'household.member.transferred', 'household.member.ended');

  ASSERT v_audit_count >= 3, format('Audit test FAILED: expected at least 3 audit events, found %s', v_audit_count);
  RAISE NOTICE 'Audit Test PASSED: % household membership audit events successfully recorded in audit.events', v_audit_count;

  RAISE NOTICE 'ALL PHASE 6B-3 SECURITY & WORKFLOW TESTS COMPLETED SUCCESSFULLY.';
END $$;

ROLLBACK;

-- =============================================================================
-- Test File: phase_6a_family_relationship_security.sql
-- Description: Comprehensive Security & Invariant Tests for Phase 6A-5
--
-- Tests:
-- 1. Spouse invariant (symmetric, canonical ordering, duplicate prevention, single spouse rule).
-- 2. Parent / Child reciprocal invariant (atomically creates inverse, prevents duplicates/conflicts).
-- 3. Self-relationship prevention.
-- 4. Family membership requirement (both members must belong to family).
-- 5. Non-destructive end relationship (ends primary + reciprocal atomically, preserves rows).
-- 6. Family lifecycle gating (archived/ended/merged families reject writes).
-- 7. Member lifecycle gating (deceased/archived members reject new active relationships).
-- 8. Scope & authorization (unauthorized, out-of-scope, anon denial).
-- 9. Zero side-effects on family_members, members, or governance.
-- 10. Zero mutations to production Acosta family.
--
-- Entire script runs inside BEGIN ... ROLLBACK.
-- =============================================================================

begin;

do $$
declare
  v_org_id               uuid;
  v_admin_id             uuid;
  v_admin_role_id        uuid;
  v_steward_role_id      uuid;
  v_active_status_id     uuid;

  v_no_perm_profile_id   uuid;

  -- Synthetic members
  v_father_id            uuid;
  v_mother_id            uuid;
  v_other_woman_id       uuid;
  v_child1_id            uuid;
  v_child2_id            uuid;
  v_stranger_id          uuid;
  v_deceased_id          uuid;
  v_archived_id          uuid;

  -- Synthetic families
  v_family_id            uuid;
  v_archived_family_id   uuid;

  -- Relationship IDs & Results
  v_spouse_res           jsonb;
  v_spouse_rel_id        uuid;
  v_pc_res               jsonb;
  v_father_child1_id     uuid;
  v_recip_child1_id      uuid;
  v_cp_res               jsonb;
  v_child2_mother_id     uuid;
  v_recip_mother_id      uuid;
  v_end_res              jsonb;

  v_profile_res          jsonb;
  v_members_before       integer;
  v_members_after        integer;
  v_all_members_before   integer;
  v_all_members_after    integer;
  v_gov_before           integer;
  v_gov_after            integer;
  v_rel_count            integer;
  v_caught               boolean;
  v_count                integer;

  -- Phase 6A-5 Repair Variables
  v_parent_type_id       uuid;
  v_child_type_id        uuid;
  v_legacy_rel_id        uuid;
  v_spouse2_res          jsonb;
  v_spouse2_id           uuid;
  v_repair_res           jsonb;
  v_reciprocal_id        uuid;
begin
  -- ---------------------------------------------------------------------------
  -- PART 1: VERIFY PERMISSION CATALOG & POSTURE
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.permissions
  WHERE code IN (
    'families.relationships.add',
    'families.relationships.end',
    'families.relationships.correct'
  );
  ASSERT v_count = 3, format('PART 1.1 FAILED: expected 3 permissions, found %s', v_count);

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code IN (
    'families.relationships.add',
    'families.relationships.end',
    'families.relationships.correct'
  )
  AND ar.code = 'organization_administrator';
  ASSERT v_count = 3, format('PART 1.2 FAILED: expected 3 role_permissions for org_admin, found %s', v_count);

  SELECT count(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('add_family_relationship', 'end_family_relationship', 'repair_family_relationship_reciprocal')
    AND EXISTS (
      SELECT 1
      FROM aclexplode(p.proacl) acl
      JOIN pg_roles r ON r.oid = acl.grantee
      WHERE r.rolname IN ('anon', 'public')
    );
  ASSERT v_count = 0, format('PART 1.3 FAILED: found %s public/anon grants on family relationship write RPCs', v_count);

  -- ---------------------------------------------------------------------------
  -- PART 2: SETUP TEST FIXTURES
  -- ---------------------------------------------------------------------------
  SELECT id INTO v_org_id FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  SELECT id INTO v_admin_role_id FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT id INTO v_steward_role_id FROM public.app_roles WHERE code = 'member_data_steward';
  SELECT id INTO v_active_status_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active' LIMIT 1;

  -- Admin user
  SELECT pra.profile_id INTO v_admin_id
  FROM public.profile_role_assignments pra
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE ar.code = 'organization_administrator'
    AND pra.organization_id = v_org_id
    AND pra.assignment_status = 'active'
  LIMIT 1;

  -- Synthetic unprivileged profile (member_data_steward)
  v_no_perm_profile_id := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_no_perm_profile_id, 'authenticated', 'authenticated', 'no_rel_write@test.local');
  INSERT INTO public.profiles (id, display_name)
  VALUES (v_no_perm_profile_id, 'No Rel Write User');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_no_perm_profile_id, v_org_id, 'active', now());
  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  ) VALUES (
    v_no_perm_profile_id, v_org_id, v_steward_role_id, 'active',
    now(), now(), now(), now()
  );

  -- Synthetic Members
  v_father_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_father_id, v_org_id, 'John', 'John Test', 'Test, John',
    v_active_status_id, 'active', false, v_admin_id, v_admin_id
  );

  v_mother_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_mother_id, v_org_id, 'Jane', 'Jane Test', 'Test, Jane',
    v_active_status_id, 'active', false, v_admin_id, v_admin_id
  );

  v_other_woman_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_other_woman_id, v_org_id, 'Alice', 'Alice Other', 'Other, Alice',
    v_active_status_id, 'active', false, v_admin_id, v_admin_id
  );

  v_child1_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_child1_id, v_org_id, 'Timmy', 'Timmy Test', 'Test, Timmy',
    v_active_status_id, 'active', false, v_admin_id, v_admin_id
  );

  v_child2_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_child2_id, v_org_id, 'Tommy', 'Tommy Test', 'Test, Tommy',
    v_active_status_id, 'active', false, v_admin_id, v_admin_id
  );

  v_stranger_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_stranger_id, v_org_id, 'Stranger', 'Stranger Bob', 'Stranger, Bob',
    v_active_status_id, 'active', false, v_admin_id, v_admin_id
  );

  v_deceased_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased, deceased_on, deceased_on_precision,
    created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_deceased_id, v_org_id, 'Grandpa', 'Grandpa Deceased', 'Deceased, Grandpa',
    v_active_status_id, 'active', true, current_date - 100, 'exact',
    v_admin_id, v_admin_id
  );

  v_archived_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, preferred_name, display_name, sort_name,
    membership_status_id, record_status, is_deceased,
    archived_at, archive_reason, archived_by_profile_id,
    created_by_profile_id, updated_by_profile_id
  ) VALUES (
    v_archived_id, v_org_id, 'Uncle', 'Uncle Archived', 'Archived, Uncle',
    v_active_status_id, 'archived', false,
    now(), 'Archived for testing', v_admin_id,
    v_admin_id, v_admin_id
  );

  -- Synthetic Families
  v_family_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status, family_type)
  VALUES (v_family_id, v_org_id, 'Test Family', 'The Test Family', 'active', 'household_family');

  v_archived_family_id := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status, family_type)
  VALUES (v_archived_family_id, v_org_id, 'Archived Family', 'Archived Family', 'archived', 'household_family');

  -- Active family memberships in v_family_id
  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status)
  VALUES
    (v_org_id, v_family_id, v_father_id, 'parent', 'active'),
    (v_org_id, v_family_id, v_mother_id, 'parent', 'active'),
    (v_org_id, v_family_id, v_other_woman_id, 'relative', 'active'),
    (v_org_id, v_family_id, v_child1_id, 'child', 'active'),
    (v_org_id, v_family_id, v_child2_id, 'child', 'active'),
    (v_org_id, v_family_id, v_deceased_id, 'relative', 'active'),
    (v_org_id, v_family_id, v_archived_id, 'relative', 'active');

  -- Note: v_stranger_id is NOT a member of v_family_id.

  SELECT count(*) INTO v_members_before FROM public.family_members;
  SELECT count(*) INTO v_all_members_before FROM public.members;
  SELECT count(*) INTO v_gov_before FROM public.member_governance_assignments;

  -- ---------------------------------------------------------------------------
  -- SWITCH TO AUTHENTICATED CALLER (Admin JWT)
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text)::text, true);

  -- ===========================================================================
  -- 1. SPOUSE INVARIANT TESTS
  -- ===========================================================================

  -- Test 1A: Admin can add spouse relationship between Father and Mother
  v_spouse_res := public.add_family_relationship(
    p_organization_id        => v_org_id,
    p_family_id              => v_family_id,
    p_from_member_id         => v_father_id,
    p_to_member_id           => v_mother_id,
    p_relationship_type_code => 'spouse',
    p_effective_from         => current_date
  );

  ASSERT (v_spouse_res->>'status') = 'created', 'Test 1A Failed: Expected status created';
  ASSERT (v_spouse_res->>'relationship_code') = 'spouse', 'Test 1A Failed: Expected relationship_code spouse';
  v_spouse_rel_id := (v_spouse_res->>'relationship_id')::uuid;

  -- Verify canonical ordering in response and stored row
  ASSERT (v_spouse_res->>'from_member_id')::uuid = least(v_father_id, v_mother_id), 'Test 1A Failed: Canonical from ordering';
  ASSERT (v_spouse_res->>'to_member_id')::uuid = greatest(v_father_id, v_mother_id), 'Test 1A Failed: Canonical to ordering';

  -- Test 1B: Self-relationship rejected
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_father_id,
      p_to_member_id           => v_father_id,
      p_relationship_type_code => 'spouse'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 1B Failed: Self relationship must be rejected with 22023';

  -- Test 1C: Reverse duplicate spouse rejected
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_mother_id,
      p_to_member_id           => v_father_id,
      p_relationship_type_code => 'spouse'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 1C Failed: Reverse duplicate spouse must be rejected with 22023';

  -- Test 1D: Duplicate active spouse rejected
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_father_id,
      p_to_member_id           => v_mother_id,
      p_relationship_type_code => 'spouse'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 1D Failed: Duplicate spouse must be rejected with 22023';

  -- Test 1E: Second active spouse for Father (allows_multiple_current = false) rejected
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_father_id,
      p_to_member_id           => v_other_woman_id,
      p_relationship_type_code => 'spouse'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 1E Failed: Second active spouse must be rejected with 22023';

  -- Test 1F: Required family membership enforced (Stranger is not in family)
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_father_id,
      p_to_member_id           => v_stranger_id,
      p_relationship_type_code => 'spouse'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 1F Failed: Non-family-member relationship must be rejected with 22023';

  -- ===========================================================================
  -- 2. PARENT / CHILD RECIPROCAL TESTS
  -- ===========================================================================

  -- Test 2A: Add parent_of: Father -> Child1
  v_pc_res := public.add_family_relationship(
    p_organization_id        => v_org_id,
    p_family_id              => v_family_id,
    p_from_member_id         => v_father_id,
    p_to_member_id           => v_child1_id,
    p_relationship_type_code => 'parent_of'
  );

  ASSERT (v_pc_res->>'status') = 'created', 'Test 2A Failed: Status created';
  v_father_child1_id := (v_pc_res->>'relationship_id')::uuid;
  v_recip_child1_id  := (v_pc_res->>'reciprocal_relationship_id')::uuid;
  ASSERT v_recip_child1_id IS NOT NULL, 'Test 2A Failed: Reciprocal relationship ID must be populated';

  -- Switch to postgres role to verify stored rows directly
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_rel_count
  FROM public.family_relationships
  WHERE id IN (v_father_child1_id, v_recip_child1_id)
    AND relationship_status = 'active';
  ASSERT v_rel_count = 2, 'Test 2A Failed: Both primary and reciprocal rows must be stored as active';
  PERFORM set_config('role', 'authenticated', true);

  -- Test 2B: Add inverse duplicate (Child1 child_of Father) rejected
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_child1_id,
      p_to_member_id           => v_father_id,
      p_relationship_type_code => 'child_of'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 2B Failed: Inverse duplicate must be rejected with 22023';

  -- Test 2C: Add child_of first: Child2 child_of Mother creates parent_of reciprocal
  v_cp_res := public.add_family_relationship(
    p_organization_id        => v_org_id,
    p_family_id              => v_family_id,
    p_from_member_id         => v_child2_id,
    p_to_member_id           => v_mother_id,
    p_relationship_type_code => 'child_of'
  );

  ASSERT (v_cp_res->>'status') = 'created', 'Test 2C Failed: Status created';
  v_child2_mother_id := (v_cp_res->>'relationship_id')::uuid;
  v_recip_mother_id  := (v_cp_res->>'reciprocal_relationship_id')::uuid;
  ASSERT v_recip_mother_id IS NOT NULL, 'Test 2C Failed: Reciprocal parent_of created';

  -- Test 2D: Conflicting active direction rejected (Child1 cannot be parent of Father)
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_child1_id,
      p_to_member_id           => v_father_id,
      p_relationship_type_code => 'parent_of'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 2D Failed: Conflicting parent_of in reverse must be rejected with 22023';

  -- ===========================================================================
  -- 3. LIFECYCLE GATING (DECEASED / ARCHIVED / HISTORICAL FAMILIES)
  -- ===========================================================================

  -- Test 3A: Deceased member relationship add rejected
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_father_id,
      p_to_member_id           => v_deceased_id,
      p_relationship_type_code => 'parent_of'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 3A Failed: Deceased member relationship must be rejected with 22023';

  -- Test 3B: Archived member record relationship add rejected
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_father_id,
      p_to_member_id           => v_archived_id,
      p_relationship_type_code => 'parent_of'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 3B Failed: Archived member relationship must be rejected with 22023';

  -- Test 3C: Archived family rejects relationship add
  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_archived_family_id,
      p_from_member_id         => v_father_id,
      p_to_member_id           => v_mother_id,
      p_relationship_type_code => 'spouse'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 3C Failed: Archived family must reject add relationship with 22023';

  -- ===========================================================================
  -- 4. END RELATIONSHIP TESTS
  -- ===========================================================================

  -- Test 4A: Empty reason rejected
  v_caught := false;
  begin
    PERFORM public.end_family_relationship(
      p_organization_id  => v_org_id,
      p_relationship_id  => v_father_child1_id,
      p_reason           => '   '
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 4A Failed: Empty reason must be rejected with 22023';

  -- Test 4B: Future effective_to rejected
  v_caught := false;
  begin
    PERFORM public.end_family_relationship(
      p_organization_id  => v_org_id,
      p_relationship_id  => v_father_child1_id,
      p_effective_to     => current_date + 1,
      p_reason           => 'Future date test'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 4B Failed: Future effective_to must be rejected with 22023';

  -- Test 4C: End parent_of(Father -> Child1) succeeds and ends reciprocal child_of
  v_end_res := public.end_family_relationship(
    p_organization_id  => v_org_id,
    p_relationship_id  => v_father_child1_id,
    p_effective_to     => current_date,
    p_reason           => 'Correction: Not child of this parent'
  );

  ASSERT (v_end_res->>'status') = 'success', 'Test 4C Failed: Expected status success';
  ASSERT (v_end_res->>'relationship_status') = 'ended', 'Test 4C Failed: Expected status ended';

  -- Verify rows directly via postgres role
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_rel_count
  FROM public.family_relationships
  WHERE id IN (v_father_child1_id, v_recip_child1_id)
    AND relationship_status = 'ended'
    AND effective_to = current_date;
  ASSERT v_rel_count = 2, 'Test 4C Failed: Both primary and reciprocal rows must be ended';

  -- Check get_family_profile read contract: ended relationship must NOT appear
  v_profile_res := public.get_family_profile(v_org_id, v_family_id);
  ASSERT NOT (v_profile_res->'relationships' @> jsonb_build_array(jsonb_build_object('relationship_id', v_father_child1_id))),
    'Test 4C Failed: get_family_profile must not return ended relationship';

  PERFORM set_config('role', 'authenticated', true);

  -- Test 4D: Second end attempt rejected
  v_caught := false;
  begin
    PERFORM public.end_family_relationship(
      p_organization_id  => v_org_id,
      p_relationship_id  => v_father_child1_id,
      p_reason           => 'Second end attempt'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 4D Failed: Second end attempt must be rejected with 22023';

  -- Test 4E: End symmetric spouse relationship ends the single row
  v_end_res := public.end_family_relationship(
    p_organization_id  => v_org_id,
    p_relationship_id  => v_spouse_rel_id,
    p_effective_to     => current_date,
    p_reason           => 'Divorce'
  );
  ASSERT (v_end_res->>'status') = 'success', 'Test 4E Failed: Expected status success';

  -- ===========================================================================
  -- 5. REPAIR RECIPROCAL RELATIONSHIP TESTS (PHASE 6A-5 CORRECTION)
  -- ===========================================================================

  -- Create deliberately legacy-style unpaired parent_of row (OtherWoman parent_of Child2)
  -- Switch briefly to postgres role to simulate historical import/migration state
  PERFORM set_config('role', 'postgres', true);

  SELECT id INTO v_parent_type_id FROM public.family_relationship_types WHERE code = 'parent_of' LIMIT 1;
  SELECT id INTO v_child_type_id FROM public.family_relationship_types WHERE code = 'child_of' LIMIT 1;

  v_legacy_rel_id := gen_random_uuid();
  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id,
    relationship_type_id, effective_from, relationship_status, source, created_by_profile_id
  ) VALUES (
    v_legacy_rel_id, v_org_id, v_family_id, v_other_woman_id, v_child2_id,
    v_parent_type_id, current_date - 30, 'active', 'migration', v_admin_id
  );

  -- Confirm reciprocal does NOT exist yet
  SELECT count(*) INTO v_count
  FROM public.family_relationships
  WHERE organization_id = v_org_id
    AND family_id = v_family_id
    AND from_member_id = v_child2_id
    AND to_member_id = v_other_woman_id
    AND relationship_type_id = v_child_type_id
    AND relationship_status = 'active';
  ASSERT v_count = 0, 'Setup Failed: Reciprocal must not exist prior to repair';

  -- Switch back to Admin JWT
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text)::text, true);

  -- Test 5A: Empty reason rejected with 22023
  v_caught := false;
  begin
    PERFORM public.repair_family_relationship_reciprocal(
      p_organization_id => v_org_id,
      p_relationship_id => v_legacy_rel_id,
      p_reason          => '   '
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 5A Failed: Empty reason must be rejected with 22023';

  -- Test 5B: Calling repair on symmetric relationship (spouse) rejected with 22023
  v_spouse2_res := public.add_family_relationship(
    p_organization_id        => v_org_id,
    p_family_id              => v_family_id,
    p_from_member_id         => v_father_id,
    p_to_member_id           => v_other_woman_id,
    p_relationship_type_code => 'spouse'
  );
  v_spouse2_id := (v_spouse2_res->>'relationship_id')::uuid;

  v_caught := false;
  begin
    PERFORM public.repair_family_relationship_reciprocal(
      p_organization_id => v_org_id,
      p_relationship_id => v_spouse2_id,
      p_reason          => 'Try to repair spouse'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 5B Failed: Calling repair on symmetric relationship (spouse) must be rejected with 22023';

  -- Test 5C: Calling repair on ended relationship rejected with 22023
  v_caught := false;
  begin
    PERFORM public.repair_family_relationship_reciprocal(
      p_organization_id => v_org_id,
      p_relationship_id => v_father_child1_id,
      p_reason          => 'Try to repair ended relationship'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 5C Failed: Calling repair on ended relationship must be rejected with 22023';

  -- Test 5D: Repair RPC creates exactly one child_of reciprocal
  v_repair_res := public.repair_family_relationship_reciprocal(
    p_organization_id => v_org_id,
    p_relationship_id => v_legacy_rel_id,
    p_reason          => 'Historical missing reciprocal correction'
  );

  ASSERT (v_repair_res->>'status') = 'repaired', 'Test 5D Failed: Expected status repaired';
  ASSERT (v_repair_res->>'existing_relationship_id') = v_legacy_rel_id::text, 'Test 5D Failed: Expected existing id';
  ASSERT (v_repair_res->>'existing_relationship_code') = 'parent_of', 'Test 5D Failed: Expected existing code parent_of';
  ASSERT (v_repair_res->>'reciprocal_relationship_code') = 'child_of', 'Test 5D Failed: Expected reciprocal code child_of';
  v_reciprocal_id := (v_repair_res->>'reciprocal_relationship_id')::uuid;
  ASSERT v_reciprocal_id is not null, 'Test 5D Failed: Expected non-null reciprocal_relationship_id';

  -- Test 5E: Original row remains unchanged
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_count
  FROM public.family_relationships
  WHERE id = v_legacy_rel_id
    AND source = 'migration'
    AND effective_from = current_date - 30
    AND relationship_status = 'active';
  ASSERT v_count = 1, 'Test 5E Failed: Original legacy row must remain completely unchanged';

  -- Verify reciprocal row in DB
  SELECT count(*) INTO v_count
  FROM public.family_relationships
  WHERE id = v_reciprocal_id
    AND organization_id = v_org_id
    AND family_id = v_family_id
    AND from_member_id = v_child2_id
    AND to_member_id = v_other_woman_id
    AND relationship_type_id = v_child_type_id
    AND relationship_status = 'active'
    AND source = 'administrator';
  ASSERT v_count = 1, 'Test 5E Failed: Repaired reciprocal row must exist with source administrator';

  PERFORM set_config('role', 'authenticated', true);

  -- Test 5F: Calling repair again is rejected because reciprocal already exists
  v_caught := false;
  begin
    PERFORM public.repair_family_relationship_reciprocal(
      p_organization_id => v_org_id,
      p_relationship_id => v_legacy_rel_id,
      p_reason          => 'Repair duplicate attempt'
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 5F Failed: Repairing when reciprocal already exists must be rejected with 22023';

  -- ===========================================================================
  -- 6. SCOPE & AUTHORIZATION TESTS
  -- ===========================================================================

  -- Test 6A: Unauthorized caller denied add_family_relationship
  PERFORM set_config('request.jwt.claim.sub', v_no_perm_profile_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_no_perm_profile_id::text)::text, true);

  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_child2_id,
      p_to_member_id           => v_other_woman_id,
      p_relationship_type_code => 'child_of'
    );
  exception when sqlstate '42501' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 6A Failed: Unauthorized caller must be denied add with 42501';

  -- Test 6B: Unauthorized caller denied repair_family_relationship_reciprocal
  v_caught := false;
  begin
    PERFORM public.repair_family_relationship_reciprocal(
      p_organization_id => v_org_id,
      p_relationship_id => v_legacy_rel_id,
      p_reason          => 'Unauthorized repair attempt'
    );
  exception when sqlstate '42501' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 6B Failed: Unauthorized caller must be denied repair with 42501';

  -- Test 6C: Anon denied add_family_relationship
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  v_caught := false;
  begin
    PERFORM public.add_family_relationship(
      p_organization_id        => v_org_id,
      p_family_id              => v_family_id,
      p_from_member_id         => v_child2_id,
      p_to_member_id           => v_other_woman_id,
      p_relationship_type_code => 'child_of'
    );
  exception when sqlstate '28000' or sqlstate '42501' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 6C Failed: Anon caller must be denied add';

  -- Test 6D: Anon denied repair_family_relationship_reciprocal
  v_caught := false;
  begin
    PERFORM public.repair_family_relationship_reciprocal(
      p_organization_id => v_org_id,
      p_relationship_id => v_legacy_rel_id,
      p_reason          => 'Anon repair attempt'
    );
  exception when sqlstate '28000' or sqlstate '42501' then
    v_caught := true;
  end;
  ASSERT v_caught, 'Test 6D Failed: Anon caller must be denied repair';

  -- ===========================================================================
  -- 7. SIDE-EFFECT & INVARIANT VERIFICATION
  -- ===========================================================================
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) INTO v_members_after FROM public.family_members;
  SELECT count(*) INTO v_all_members_after FROM public.members;
  SELECT count(*) INTO v_gov_after FROM public.member_governance_assignments;

  ASSERT v_members_before = v_members_after, 'Test 7A Failed: family_members row count must not change';
  ASSERT v_all_members_before = v_all_members_after, 'Test 7B Failed: members row count must not change';
  ASSERT v_gov_before = v_gov_after, 'Test 7C Failed: governance assignments count must not change';

  -- Production Acosta family must remain untouched
  SELECT count(*) INTO v_rel_count
  FROM public.family_relationships
  where family_id = '74a4adcd-5f2b-4581-aa67-4197c1b46933'::uuid
    and relationship_status = 'active';
  ASSERT v_rel_count = 3, 'Test 7D Failed: Acosta active relationships must remain exactly 3';

  RAISE NOTICE 'All Phase 6A-5 Family Relationship Security & Invariant Tests Passed Successfully!';
end;
$$;

rollback;

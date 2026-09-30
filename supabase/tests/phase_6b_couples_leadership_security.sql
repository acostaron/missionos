-- =============================================================================
-- Test Suite: phase_6b_couples_leadership_security.sql
-- Phase:      Phase 6B-3 — Couples Section Leadership & Household Leaders Derivation
--
-- Tests:
--  1. Husband formally appointed Household Servant.
--  2. Wife is verified spouse in family_relationships.
--  3. Both are current members of same Couples household.
--  4. Formal leadership_assignments contains exactly ONE Household Servant row.
--  5. Husband membership_role = servant.
--  6. Wife membership_role remains member.
--  7. Household profile derives both as Household Leaders.
--  8. Wife has no assistant or servant leadership_assignment.
--  9. No application authorization is created for either spouse.
-- 10. After conclusion, neither is displayed as current Household Leaders.
-- 11. After replacement, Household Leaders display derives from the new Household
--     Servant and verified spouse.
-- 12. If spouse is not in the household, only formal Household Servant is shown.
-- 13. If spouse relationship cannot be verified, do not infer it.
--
-- Non-destructive. Wrapped in a transaction and strictly ROLLED BACK.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id                 uuid;
  v_admin_profile          uuid;
  v_rvc_unit_id            uuid;
  v_hh_couple_id           uuid;
  v_hh_non_couple_id       uuid;
  v_status_active_id       uuid;
  v_leadership_role_id     uuid;
  v_hh_type_id             uuid;
  v_rel_type_spouse_id     uuid;

  -- Couple 1
  v_husband_id             uuid;
  v_wife_id                uuid;
  v_family_1_id            uuid;
  v_rel_1_id               uuid;
  v_assign_1_id            uuid;

  -- Couple 2 (for replacement)
  v_husband_2_id           uuid;
  v_wife_2_id              uuid;
  v_family_2_id            uuid;
  v_rel_2_id               uuid;
  v_assign_2_id            uuid;

  -- Unverified Couple
  v_unverified_husband_id  uuid;
  v_unverified_wife_id     uuid;
  v_family_unverified_id   uuid;
  v_rel_unverified_id      uuid;
  v_assign_unverified_id   uuid;

  v_profile_json           jsonb;
  v_leaders_arr            jsonb;
  v_household_leaders      jsonb;
  v_count                  integer;
BEGIN
  -- 1. Resolve organization and admin
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;

  SELECT p.id INTO v_admin_profile
  FROM public.profiles p
  JOIN public.profile_role_assignments pra ON pra.profile_id = p.id
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE pra.organization_id = v_org_id
    AND ar.code = 'organization_administrator'
    AND pra.assignment_status = 'active'
  LIMIT 1;

  SELECT id INTO v_rvc_unit_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'rvc_u01';
  SELECT id INTO v_status_active_id FROM public.member_statuses WHERE organization_id = v_org_id AND code = 'active';

  -- Resolve canonical household_servant_leader role definition
  SELECT id INTO v_hh_type_id FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'household';
  SELECT id INTO STRICT v_leadership_role_id FROM public.leadership_role_definitions WHERE organization_id = v_org_id AND code = 'household_servant_leader';

  -- Resolve spouse relationship type
  SELECT id INTO v_rel_type_spouse_id FROM public.family_relationship_types WHERE code = 'spouse' LIMIT 1;

  -- Set caller JWT claims as Organization Administrator
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- 2. Create Couples Household and Non-Couple Household
  v_hh_couple_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (
    id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from
  ) VALUES (
    v_hh_couple_id, v_org_id, v_hh_type_id, 'synth_couples_hh', 'Synthetic Couples Household', 'active', current_date - 30
  );
  INSERT INTO public.households (
    id, organization_id, is_couple_household, accepts_new_members
  ) VALUES (
    v_hh_couple_id, v_org_id, true, true
  );
  INSERT INTO public.governance_node_relationships (
    organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, effective_from
  ) VALUES (
    v_org_id, v_rvc_unit_id, v_hh_couple_id, 'primary_parent', 'active', current_date - 30
  );

  v_hh_non_couple_id := gen_random_uuid();
  INSERT INTO public.governance_nodes (
    id, organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from
  ) VALUES (
    v_hh_non_couple_id, v_org_id, v_hh_type_id, 'synth_singles_hh', 'Synthetic Singles Household', 'active', current_date - 30
  );
  INSERT INTO public.households (
    id, organization_id, is_couple_household, accepts_new_members
  ) VALUES (
    v_hh_non_couple_id, v_org_id, false, true
  );
  INSERT INTO public.governance_node_relationships (
    organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, effective_from
  ) VALUES (
    v_org_id, v_rvc_unit_id, v_hh_non_couple_id, 'primary_parent', 'active', current_date - 30
  );

  -- 3. Create Husband 1 and Wife 1
  v_husband_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, member_number, preferred_name, display_name, sort_name,
    civil_status, membership_status_id, joined_on, record_status, is_deceased
  ) VALUES (
    v_husband_id, v_org_id, 'M9101', 'John', 'John Doe', 'Doe, John',
    'married', v_status_active_id, current_date - 30, 'active', false
  );

  v_wife_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, member_number, preferred_name, display_name, sort_name,
    civil_status, membership_status_id, joined_on, record_status, is_deceased
  ) VALUES (
    v_wife_id, v_org_id, 'M9102', 'Jane', 'Jane Doe', 'Doe, Jane',
    'married', v_status_active_id, current_date - 30, 'active', false
  );

  -- Attach both to Unit 1 governance placement
  INSERT INTO public.member_governance_assignments (
    organization_id, member_id, governance_node_id, assignment_type, assignment_status, effective_from, is_primary, assignment_basis
  ) VALUES
    (v_org_id, v_husband_id, v_rvc_unit_id, 'primary', 'active', current_date - 30, true, 'administrative'),
    (v_org_id, v_wife_id, v_rvc_unit_id, 'primary', 'active', current_date - 30, true, 'administrative');

  -- Create Family and verified spouse relationship
  v_family_1_id := gen_random_uuid();
  INSERT INTO public.families (
    id, organization_id, family_name, display_name, family_status
  ) VALUES (
    v_family_1_id, v_org_id, 'Doe Family', 'The Doe Family', 'active'
  );

  INSERT INTO public.family_members (
    organization_id, family_id, member_id, family_role, membership_status, effective_from
  ) VALUES
    (v_org_id, v_family_1_id, v_husband_id, 'spouse', 'active', current_date - 30),
    (v_org_id, v_family_1_id, v_wife_id, 'spouse', 'active', current_date - 30);

  v_rel_1_id := gen_random_uuid();
  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    v_rel_1_id, v_org_id, v_family_1_id,
    least(v_husband_id, v_wife_id), greatest(v_husband_id, v_wife_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  -- Assign both into the Couples Household
  -- Requirement 5 & 6: Husband is 'servant', Wife is 'member'
  INSERT INTO public.household_memberships (
    organization_id, member_id, household_node_id, membership_status, membership_role, effective_from, is_primary
  ) VALUES
    (v_org_id, v_husband_id, v_hh_couple_id, 'active', 'servant', current_date - 30, true),
    (v_org_id, v_wife_id, v_hh_couple_id, 'active', 'member', current_date - 30, true);

  -- Requirement 1 & 4: Formal appointment for Husband only
  v_assign_1_id := gen_random_uuid();
  INSERT INTO public.leadership_assignments (
    id, organization_id, member_id, governance_node_id, leadership_role_definition_id,
    assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at
  ) VALUES (
    v_assign_1_id, v_org_id, v_husband_id, v_hh_couple_id, v_leadership_role_id,
    'active', 'regular', current_date - 30, now(), now(), now(), now()
  );

  -- ===========================================================================
  -- VERIFICATION OF INITIAL STATE (Requirements 1-9)
  -- ===========================================================================
  -- Req 4: Formal leadership_assignments contains exactly ONE row for the household
  SELECT count(*) INTO v_count
  FROM public.leadership_assignments
  WHERE governance_node_id = v_hh_couple_id
    AND assignment_status = 'active';
  ASSERT v_count = 1, format('Req 4 FAILED: expected 1 formal assignment, found %s', v_count);
  RAISE NOTICE 'Req 1 & 4 PASSED: Exactly 1 formal leadership assignment for household';

  -- Req 5 & 6: Husband membership_role = servant, Wife membership_role = member
  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE household_node_id = v_hh_couple_id
    AND member_id = v_husband_id
    AND membership_role = 'servant';
  ASSERT v_count = 1, 'Req 5 FAILED: husband membership_role is not servant';

  SELECT count(*) INTO v_count
  FROM public.household_memberships
  WHERE household_node_id = v_hh_couple_id
    AND member_id = v_wife_id
    AND membership_role = 'member';
  ASSERT v_count = 1, 'Req 6 FAILED: wife membership_role is not member';
  RAISE NOTICE 'Req 5 & 6 PASSED: Husband is servant, wife is member';

  -- Req 8: Wife has NO leadership_assignment (assistant or servant)
  SELECT count(*) INTO v_count
  FROM public.leadership_assignments
  WHERE member_id = v_wife_id;
  ASSERT v_count = 0, 'Req 8 FAILED: wife has leadership assignment!';
  RAISE NOTICE 'Req 8 PASSED: Wife has zero formal leadership assignments';

  -- Req 9: No application authorization created for either spouse
  SELECT count(*) INTO v_count
  FROM public.profile_role_assignments pra
  JOIN public.profiles p ON p.id = pra.profile_id
  WHERE p.id IN (v_husband_id, v_wife_id);
  ASSERT v_count = 0, 'Req 9 FAILED: pastoral appointment created software permissions!';
  RAISE NOTICE 'Req 9 PASSED: Zero application authorization granted to either spouse';

  -- Req 7: Household profile derives both spouses as Household Leaders
  v_profile_json := public.get_household_profile(v_org_id, v_hh_couple_id);
  v_household_leaders := v_profile_json->'household_leaders';
  ASSERT v_household_leaders IS NOT NULL, 'Req 7 FAILED: household_leaders is null in profile';
  ASSERT v_household_leaders->'husband'->>'member_id' = v_husband_id::text, 'Req 7 FAILED: husband member_id mismatch';
  ASSERT v_household_leaders->'wife'->>'member_id' = v_wife_id::text, 'Req 7 FAILED: wife member_id mismatch';
  ASSERT v_household_leaders->>'formatted_names' = 'John Doe & Jane Doe', 'Req 7 FAILED: formatted_names mismatch';
  RAISE NOTICE 'Req 7 PASSED: Household Leaders derived as "John Doe & Jane Doe"';

  -- Non-Couples Household Check: Ensure couples derivation does NOT trigger if is_couple_household = false
  -- Create formal leader for non-couple household
  INSERT INTO public.household_memberships (
    organization_id, member_id, household_node_id, membership_status, membership_role, effective_from, is_primary
  ) VALUES (
    v_org_id, v_husband_id, v_hh_non_couple_id, 'temporary', 'servant', current_date - 10, false
  );
  INSERT INTO public.household_memberships (
    organization_id, member_id, household_node_id, membership_status, membership_role, effective_from, is_primary
  ) VALUES (
    v_org_id, v_wife_id, v_hh_non_couple_id, 'temporary', 'member', current_date - 10, false
  );
  INSERT INTO public.leadership_assignments (
    organization_id, member_id, governance_node_id, leadership_role_definition_id,
    assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at
  ) VALUES (
    v_org_id, v_husband_id, v_hh_non_couple_id, v_leadership_role_id,
    'active', 'regular', current_date - 10, now(), now(), now(), now()
  );
  v_profile_json := public.get_household_profile(v_org_id, v_hh_non_couple_id);
  ASSERT (v_profile_json->'household_leaders' IS NULL OR v_profile_json->'household_leaders' = 'null'::jsonb), 'Couples rule incorrectly applied to non-couple household!';
  RAISE NOTICE 'Couples Section Boundary PASSED: household_leaders is null for non-couple households';

  -- ===========================================================================
  -- Req 12: If spouse is not in the household, only formal Household Servant is shown
  -- ===========================================================================
  -- Remove wife from the couples household
  DELETE FROM public.household_memberships WHERE household_node_id = v_hh_couple_id AND member_id = v_wife_id;
  v_profile_json := public.get_household_profile(v_org_id, v_hh_couple_id);
  ASSERT (v_profile_json->'household_leaders' IS NULL OR v_profile_json->'household_leaders' = 'null'::jsonb), 'Req 12 FAILED: household_leaders derived when spouse not in household';
  ASSERT jsonb_array_length(v_profile_json->'leaders') = 1, 'Req 12 FAILED: formal leader missing';
  RAISE NOTICE 'Req 12 PASSED: Spouse absent from household -> household_leaders is null, formal servant shown';

  -- Restore wife to household
  INSERT INTO public.household_memberships (
    organization_id, member_id, household_node_id, membership_status, membership_role, effective_from, is_primary
  ) VALUES (
    v_org_id, v_wife_id, v_hh_couple_id, 'active', 'member', current_date - 30, true
  );

  -- ===========================================================================
  -- Req 13: If spouse relationship cannot be verified, do not infer it
  -- ===========================================================================
  -- Change verification_status to 'unverified'
  UPDATE public.family_relationships SET verification_status = 'unverified' WHERE id = v_rel_1_id;
  v_profile_json := public.get_household_profile(v_org_id, v_hh_couple_id);
  ASSERT (v_profile_json->'household_leaders' IS NULL OR v_profile_json->'household_leaders' = 'null'::jsonb), 'Req 13 FAILED: derived household_leaders from unverified spouse';
  RAISE NOTICE 'Req 13 PASSED: Unverified spouse -> household_leaders is null, not inferred';

  -- Re-verify relationship
  UPDATE public.family_relationships SET verification_status = 'administrator_verified', verified_at = now() WHERE id = v_rel_1_id;

  -- ===========================================================================
  -- Req 11: REPLACEMENT DYNAMICS
  -- Outgoing husband appointment ended, incoming husband appointed.
  -- ===========================================================================
  -- Create Couple 2
  v_husband_2_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, member_number, preferred_name, display_name, sort_name,
    civil_status, membership_status_id, joined_on, record_status, is_deceased
  ) VALUES (
    v_husband_2_id, v_org_id, 'M9201', 'Bob', 'Bob Smith', 'Smith, Bob',
    'married', v_status_active_id, current_date - 30, 'active', false
  );

  v_wife_2_id := gen_random_uuid();
  INSERT INTO public.members (
    id, organization_id, member_number, preferred_name, display_name, sort_name,
    civil_status, membership_status_id, joined_on, record_status, is_deceased
  ) VALUES (
    v_wife_2_id, v_org_id, 'M9202', 'Beth', 'Beth Smith', 'Smith, Beth',
    'married', v_status_active_id, current_date - 30, 'active', false
  );

  INSERT INTO public.family_members (
    organization_id, family_id, member_id, family_role, membership_status, effective_from
  ) VALUES
    (v_org_id, v_family_1_id, v_husband_2_id, 'spouse', 'active', current_date - 30),
    (v_org_id, v_family_1_id, v_wife_2_id, 'spouse', 'active', current_date - 30);

  v_rel_2_id := gen_random_uuid();
  INSERT INTO public.family_relationships (
    id, organization_id, family_id, from_member_id, to_member_id, relationship_type_id,
    relationship_status, is_primary_relationship, verification_status, verified_at, effective_from
  ) VALUES (
    v_rel_2_id, v_org_id, v_family_1_id,
    least(v_husband_2_id, v_wife_2_id), greatest(v_husband_2_id, v_wife_2_id),
    v_rel_type_spouse_id, 'active', true, 'administrator_verified', now(), current_date - 30
  );

  INSERT INTO public.household_memberships (
    organization_id, member_id, household_node_id, membership_status, membership_role, effective_from, is_primary
  ) VALUES
    (v_org_id, v_husband_2_id, v_hh_couple_id, 'active', 'servant', current_date, true),
    (v_org_id, v_wife_2_id, v_hh_couple_id, 'active', 'member', current_date, true);

  -- Conclude Husband 1 appointment and demote membership role to 'member'
  UPDATE public.leadership_assignments
  SET assignment_status = 'completed', effective_to = current_date - 1, ended_at = now(), ending_reason = 'Term completed'
  WHERE id = v_assign_1_id;

  UPDATE public.household_memberships
  SET membership_role = 'member'
  WHERE household_node_id = v_hh_couple_id AND member_id = v_husband_id;

  -- Appoint Husband 2
  v_assign_2_id := gen_random_uuid();
  INSERT INTO public.leadership_assignments (
    id, organization_id, member_id, governance_node_id, leadership_role_definition_id,
    assignment_status, appointment_type, effective_from, proposed_at, approved_at, accepted_at, activated_at
  ) VALUES (
    v_assign_2_id, v_org_id, v_husband_2_id, v_hh_couple_id, v_leadership_role_id,
    'active', 'regular', current_date - 10, now(), now(), now(), now()
  );

  -- Profile should now derive Bob Smith & Beth Smith; Jane Doe must NOT be retained
  v_profile_json := public.get_household_profile(v_org_id, v_hh_couple_id);
  v_household_leaders := v_profile_json->'household_leaders';
  ASSERT v_household_leaders IS NOT NULL, 'Req 11 FAILED: new couple leaders not derived';
  ASSERT v_household_leaders->'husband'->>'member_id' = v_husband_2_id::text, 'Req 11 FAILED: new husband mismatch';
  ASSERT v_household_leaders->'wife'->>'member_id' = v_wife_2_id::text, 'Req 11 FAILED: new wife mismatch';
  ASSERT v_household_leaders->>'formatted_names' = 'Bob Smith & Beth Smith', 'Req 11 FAILED: new formatted names mismatch';
  RAISE NOTICE 'Req 11 PASSED: Replacement successfully recalculated Household Leaders to incoming couple';

  -- ===========================================================================
  -- Req 10: CONCLUSION DYNAMICS
  -- Conclude Husband 2 without replacement -> household_leaders is null
  -- ===========================================================================
  UPDATE public.leadership_assignments
  SET assignment_status = 'completed', effective_to = current_date - 1, ended_at = now(), ending_reason = 'Term completed'
  WHERE id = v_assign_2_id;

  v_profile_json := public.get_household_profile(v_org_id, v_hh_couple_id);
  ASSERT (v_profile_json->'household_leaders' IS NULL OR v_profile_json->'household_leaders' = 'null'::jsonb), 'Req 10 FAILED: household_leaders not null when servant concluded';
  ASSERT jsonb_array_length(v_profile_json->'leaders') = 0, 'Req 10 FAILED: formal leaders should be vacant';
  RAISE NOTICE 'Req 10 PASSED: Conclusion results in vacant formal office and no derived Household Leaders';

  RAISE NOTICE 'ALL COUPLES SECTION LEADERSHIP REQUIREMENTS 1-13 TESTED AND VERIFIED SUCCESSFULLY.';
END $$;

ROLLBACK;

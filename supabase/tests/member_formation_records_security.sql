-- =============================================================================
-- Test File: supabase/tests/member_formation_records_security.sql
-- Purpose:   Comprehensive security, authorization, and behavior test suite for
--            Stage 3A Pass 3A-4 Member Formation Records and Transcripts.
-- =============================================================================

-- =============================================================================
-- PART 1: STATIC POSTURE CHECKS (RLS, Browser Policies, Functions, Privileges)
-- =============================================================================

DO $$
DECLARE
  v_count integer;
BEGIN
  -- 1.1 RLS enabled on all 5 formation tables
  SELECT count(*) INTO v_count
  FROM pg_tables
  WHERE schemaname = 'public'
    AND tablename IN (
      'formation_programs',
      'formation_talks',
      'formation_program_requirements',
      'member_formation_program_records',
      'member_formation_talk_records'
    )
    AND rowsecurity = true;
  ASSERT v_count = 5, format('PART 1.1 FAILED: expected 5 tables with RLS enabled, found %s', v_count);
  RAISE NOTICE 'PART 1.1 PASSED: All 5 formation tables have RLS enabled';

  -- 1.2 Zero browser/table policies on formation tables (default-deny)
  SELECT count(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN (
      'formation_programs',
      'formation_talks',
      'formation_program_requirements',
      'member_formation_program_records',
      'member_formation_talk_records'
    );
  ASSERT v_count = 0, format('PART 1.2 FAILED: expected 0 table policies, found %s', v_count);
  RAISE NOTICE 'PART 1.2 PASSED: 0 table policies on all formation tables (RPC-only access)';

  -- 1.3 RPC signatures exist
  SELECT count(*) INTO v_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name IN (
      'record_member_formation_program',
      'record_member_formation_talk',
      'void_member_formation_program_record',
      'void_member_formation_talk_record',
      'get_member_formation_transcript',
      'get_my_formation_transcript'
    );
  ASSERT v_count = 6, format('PART 1.3 FAILED: expected 6 RPCs, found %s', v_count);
  RAISE NOTICE 'PART 1.3 PASSED: All 6 member formation RPCs exist';

  -- 1.4 Hardened search_path on all RPCs
  SELECT count(*) INTO v_count
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname IN (
      'record_member_formation_program',
      'record_member_formation_talk',
      'void_member_formation_program_record',
      'void_member_formation_talk_record',
      'get_member_formation_transcript',
      'get_my_formation_transcript'
    )
    AND p.prosecdef = true
    AND p.proconfig::text LIKE '%search_path=pg_catalog, public, private, auth%';
  ASSERT v_count = 6, format('PART 1.4 FAILED: expected 6 hardened definer RPCs, found %s', v_count);
  RAISE NOTICE 'PART 1.4 PASSED: All 6 RPCs are SECURITY DEFINER with hardened search_path';

  -- 1.5 Execution privileges: anon/public revoked, authenticated granted
  SELECT count(*) INTO v_count
  FROM information_schema.routine_privileges
  WHERE routine_schema = 'public'
    AND routine_name IN (
      'record_member_formation_program',
      'record_member_formation_talk',
      'void_member_formation_program_record',
      'void_member_formation_talk_record',
      'get_member_formation_transcript',
      'get_my_formation_transcript'
    )
    AND grantee IN ('anon', 'PUBLIC');
  ASSERT v_count = 0, format('PART 1.5 FAILED: expected 0 public/anon execute grants, found %s', v_count);
  RAISE NOTICE 'PART 1.5 PASSED: Execution strictly revoked from public/anon';
END $$;


-- =============================================================================
-- PART 2: BEHAVIORAL & SECURITY TESTS (A THROUGH T in a ROLLED-BACK TRANSACTION)
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id              uuid;
  v_org_b               uuid := gen_random_uuid();
  v_admin_role_id       uuid;
  v_member_role_id      uuid;
  v_sec_servant_role_id uuid;

  -- Synthetic Actors
  v_admin_user          uuid := gen_random_uuid();
  v_noperm_user         uuid := gen_random_uuid();
  v_sec_a_leader        uuid := gen_random_uuid();
  v_sec_b_leader        uuid := gen_random_uuid();
  v_self_user           uuid := gen_random_uuid();
  v_unlinked_user       uuid := gen_random_uuid();
  v_noperm_linked_user  uuid := gen_random_uuid();

  -- Governance Nodes
  v_section_a_id        uuid := gen_random_uuid();
  v_section_b_id        uuid := gen_random_uuid();
  v_sec_type_id         uuid;

  -- Synthetic Members
  v_member_a_id         uuid := gen_random_uuid();
  v_member_b_id         uuid := gen_random_uuid();

  -- Programs & Talks
  v_prog_cr_id          uuid;
  v_prog_cls_id         uuid;
  v_prog_retired_id     uuid := gen_random_uuid();
  v_talk_cr_1_id        uuid;
  v_talk_cr_2_id        uuid;
  v_talk_other_id       uuid;

  -- Results
  v_res                 jsonb;
  v_rec_id              uuid;
  v_rec2_id             uuid;
  v_talk_rec_id         uuid;
  v_attempt             integer;
  v_passed              boolean;
  v_count               integer;
  v_prog_status         text;
  v_active_status_id    uuid;
  v_verified_by_id      uuid;
  v_actor_profile_id    uuid;
BEGIN
  -- ---------------------------------------------------------------------------
  -- Fixtures Setup
  -- ---------------------------------------------------------------------------
  SELECT id INTO v_org_id FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  SELECT id INTO v_admin_role_id FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT id INTO v_member_role_id FROM public.app_roles WHERE code = 'member';
  SELECT id INTO v_sec_servant_role_id FROM public.app_roles WHERE code = 'chapter_servant_leader_access';
  SELECT id INTO v_sec_type_id FROM public.governance_node_types WHERE code = 'section' LIMIT 1;
  SELECT id INTO v_active_status_id FROM public.member_statuses WHERE code = 'active' LIMIT 1;

  -- Fetch real seeded programs and talks
  SELECT id INTO v_prog_cr_id FROM public.formation_programs WHERE code = 'CR' LIMIT 1;
  SELECT id INTO v_prog_cls_id FROM public.formation_programs WHERE code = 'CLS' LIMIT 1;

  SELECT id INTO v_talk_cr_1_id FROM public.formation_talks WHERE program_id = v_prog_cr_id AND sequence_order = 1 LIMIT 1;
  SELECT id INTO v_talk_cr_2_id FROM public.formation_talks WHERE program_id = v_prog_cr_id AND sequence_order = 2 LIMIT 1;
  SELECT id INTO v_talk_other_id FROM public.formation_talks WHERE program_id <> v_prog_cr_id LIMIT 1;

  -- Create synthetic sections
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, name, code, lifecycle_status, effective_from) VALUES
    (v_section_a_id, v_org_id, v_sec_type_id, 'Synthetic Section A', 'syn_sec_a', 'active', current_date),
    (v_section_b_id, v_org_id, v_sec_type_id, 'Synthetic Section B', 'syn_sec_b', 'active', current_date);

  -- Create synthetic members
  INSERT INTO public.members (id, organization_id, display_name, preferred_name, sort_name, primary_section_node_id, membership_status_id) VALUES
    (v_member_a_id, v_org_id, 'Synthetic Member A', 'Synth A', 'A, Synth', v_section_a_id, v_active_status_id),
    (v_member_b_id, v_org_id, 'Synthetic Member B', 'Synth B', 'B, Synth', v_section_b_id, v_active_status_id),
    ('c0000000-0000-0000-0000-000000000001', v_org_id, 'Empty Member', 'Empty', 'Member, Empty', v_section_a_id, v_active_status_id);

  -- Create synthetic auth users & profiles
  INSERT INTO auth.users (id, aud, role, email) VALUES
    (v_admin_user,         'authenticated', 'authenticated', 'admin_user@test.local'),
    (v_noperm_user,        'authenticated', 'authenticated', 'noperm_user@test.local'),
    (v_sec_a_leader,       'authenticated', 'authenticated', 'sec_a_leader@test.local'),
    (v_sec_b_leader,       'authenticated', 'authenticated', 'sec_b_leader@test.local'),
    (v_self_user,          'authenticated', 'authenticated', 'self_user@test.local'),
    (v_unlinked_user,      'authenticated', 'authenticated', 'unlinked_user@test.local'),
    (v_noperm_linked_user, 'authenticated', 'authenticated', 'noperm_linked@test.local');

  INSERT INTO public.profiles (id, display_name) VALUES
    (v_admin_user,         'Admin User'),
    (v_noperm_user,        'NoPerm User'),
    (v_sec_a_leader,       'Section A Leader'),
    (v_sec_b_leader,       'Section B Leader'),
    (v_self_user,          'Self User'),
    (v_unlinked_user,      'Unlinked User'),
    (v_noperm_linked_user, 'NoPerm Linked User');

  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  SELECT p, v_org_id, 'active', now()
  FROM unnest(ARRAY[v_admin_user, v_noperm_user, v_sec_a_leader, v_sec_b_leader, v_self_user, v_unlinked_user, v_noperm_linked_user]) p;

  -- Role assignments
  -- Admin
  INSERT INTO public.profile_role_assignments (
    id, profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  )
  VALUES ('a0000000-0000-0000-0000-000000000000', v_admin_user, v_org_id, v_admin_role_id, 'active', now(), now(), now(), now());

  INSERT INTO public.profile_scope_assignments (
    profile_role_assignment_id, organization_id, scope_type, scope_effect, includes_descendants, assignment_status, effective_from_at, assigned_at
  )
  VALUES ('a0000000-0000-0000-0000-000000000000', v_org_id, 'organization', 'include', true, 'active', now(), now());

  -- Section A Leader: chapter_servant_leader_access scoped to Section A
  INSERT INTO public.profile_role_assignments (
    id, profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  )
  VALUES ('a0000000-0000-0000-0000-000000000001', v_sec_a_leader, v_org_id, v_sec_servant_role_id, 'active', now(), now(), now(), now());

  INSERT INTO public.profile_scope_assignments (
    profile_role_assignment_id, organization_id, scope_type, scope_effect, section_node_id, includes_descendants, assignment_status, effective_from_at, assigned_at
  )
  VALUES ('a0000000-0000-0000-0000-000000000001', v_org_id, 'section', 'include', v_section_a_id, true, 'active', now(), now());

  -- Section B Leader: chapter_servant_leader_access scoped to Section B
  INSERT INTO public.profile_role_assignments (
    id, profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  )
  VALUES ('a0000000-0000-0000-0000-000000000002', v_sec_b_leader, v_org_id, v_sec_servant_role_id, 'active', now(), now(), now(), now());

  INSERT INTO public.profile_scope_assignments (
    profile_role_assignment_id, organization_id, scope_type, scope_effect, section_node_id, includes_descendants, assignment_status, effective_from_at, assigned_at
  )
  VALUES ('a0000000-0000-0000-0000-000000000002', v_org_id, 'section', 'include', v_section_b_id, true, 'active', now(), now());

  -- Self User: member role and verified self link to Member A
  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  )
  VALUES (v_self_user, v_org_id, v_member_role_id, 'active', now(), now(), now(), now());

  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verification_method, verified_at, verified_by_profile_id, verification_summary)
  VALUES (v_self_user, v_org_id, v_member_a_id, 'self', 'verified', true, 'admin_verified', now(), v_admin_user, 'synthetic self link');

  -- Unlinked User: member role (has members.self_service.view) but NO member link
  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  )
  VALUES (v_unlinked_user, v_org_id, v_member_role_id, 'active', now(), now(), now(), now());

  -- NoPerm Linked User: NO roles assigned, but verified self link to Member B
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verification_method, verified_at, verified_by_profile_id, verification_summary)
  VALUES (v_noperm_linked_user, v_org_id, v_member_b_id, 'self', 'verified', true, 'admin_verified', now(), v_admin_user, 'synthetic self link B');

  -- Synthetic Retired Curriculum Program
  INSERT INTO public.formation_programs (id, organization_id, code, title, edition, program_category, program_type, is_active)
  VALUES (v_prog_retired_id, v_org_id, 'RETIRED-ED1', 'Retired Program Edition 1', '1995', 'pastoral_formation', 'course', false);


  -- ---------------------------------------------------------------------------
  -- TEST A: Organization Administrator records historical program completion
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_user, 'role', 'authenticated')::text, true);

  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_member_a_id,
    p_program_id => v_prog_cr_id,
    p_status => 'completed',
    p_completed_date => '2023-04-15'::date,
    p_date_precision => 'exact_date',
    p_verification_method => 'leader_attestation',
    p_source_reference => 'Cert-2023-001'
  );

  ASSERT (v_res->>'status') = 'completed', 'TEST A FAILED: status not completed';
  ASSERT (v_res->>'date_precision') = 'exact_date', 'TEST A FAILED: date precision mismatch';
  ASSERT (v_res->>'completed_date') = '2023-04-15', 'TEST A FAILED: completed date mismatch';
  ASSERT (v_res->>'attempt_number')::integer = 1, 'TEST A FAILED: attempt number != 1';
  v_rec_id := (v_res->>'id')::uuid;
  RAISE NOTICE 'TEST A PASSED: Admin recorded historical completion with exact_date';


  -- ---------------------------------------------------------------------------
  -- TEST B: User without formation.records.record denied
  -- ---------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_noperm_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_noperm_user, 'role', 'authenticated')::text, true);

  v_passed := false;
  BEGIN
    PERFORM public.record_member_formation_program(
      p_organization_id => v_org_id,
      p_member_id => v_member_a_id,
      p_program_id => v_prog_cr_id,
      p_status => 'completed',
      p_completed_date => '2023-04-15'::date,
      p_date_precision => 'exact_date'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST B FAILED: user without permission was not denied (42501)';
  RAISE NOTICE 'TEST B PASSED: User without formation.records.record denied';


  -- ---------------------------------------------------------------------------
  -- TEST C: Cross-organization program write denied
  -- ---------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_admin_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_user, 'role', 'authenticated')::text, true);

  v_passed := false;
  BEGIN
    PERFORM public.record_member_formation_program(
      p_organization_id => v_org_b,
      p_member_id => v_member_a_id,
      p_program_id => v_prog_cr_id,
      p_status => 'completed',
      p_completed_date => '2023-04-15'::date,
      p_date_precision => 'exact_date'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST C FAILED: cross-org write was not denied';
  RAISE NOTICE 'TEST C PASSED: Cross-organization write denied';


  -- ---------------------------------------------------------------------------
  -- TEST D: Valid year-only historical completion accepted with no fake date
  -- ---------------------------------------------------------------------------
  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_member_b_id,
    p_program_id => v_prog_cr_id,
    p_status => 'completed',
    p_completed_year => 2015::smallint,
    p_completed_month => null,
    p_completed_date => null,
    p_date_precision => 'year_only',
    p_verification_method => 'historical_backfill'
  );

  ASSERT (v_res->>'date_precision') = 'year_only', 'TEST D FAILED: precision mismatch';
  ASSERT (v_res->>'completed_year')::integer = 2015, 'TEST D FAILED: year mismatch';
  ASSERT v_res->>'completed_date' IS NULL, 'TEST D FAILED: completed_date must be null';
  ASSERT v_res->>'completed_month' IS NULL, 'TEST D FAILED: completed_month must be null';
  RAISE NOTICE 'TEST D PASSED: Valid year-only historical completion accepted with no fake date';


  -- ---------------------------------------------------------------------------
  -- TEST E: Invalid date precision rejected
  -- ---------------------------------------------------------------------------
  v_passed := false;
  BEGIN
    PERFORM public.record_member_formation_program(
      p_organization_id => v_org_id,
      p_member_id => v_member_b_id,
      p_program_id => v_prog_cls_id,
      p_status => 'completed',
      p_completed_year => 2015::smallint,
      p_completed_date => '2015-01-01'::date, -- contradiction with year_only
      p_date_precision => 'year_only'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST E FAILED: invalid date precision combination was not rejected';
  RAISE NOTICE 'TEST E PASSED: Invalid date precision combination rejected (22023)';


  -- ---------------------------------------------------------------------------
  -- TEST F: Repeated program attempt gets next attempt number
  -- ---------------------------------------------------------------------------
  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_member_a_id,
    p_program_id => v_prog_cr_id,
    p_status => 'completed',
    p_completed_date => '2024-05-20'::date,
    p_date_precision => 'exact_date',
    p_verification_method => 'leader_attestation'
  );

  ASSERT (v_res->>'attempt_number')::integer = 2, 'TEST F FAILED: repeat attempt number != 2';
  v_rec2_id := (v_res->>'id')::uuid;
  RAISE NOTICE 'TEST F PASSED: Repeated program attempt allocated attempt_number = 2';


  -- ---------------------------------------------------------------------------
  -- TEST G: Talk participation recorded against correct parent attempt
  -- ---------------------------------------------------------------------------
  v_res := public.record_member_formation_talk(
    p_organization_id => v_org_id,
    p_program_record_id => v_rec_id,
    p_talk_id => v_talk_cr_1_id,
    p_session_status => 'attended',
    p_attended_date => '2023-04-10'::date,
    p_notes => 'Attended live session'
  );

  ASSERT (v_res->>'session_status') = 'attended', 'TEST G FAILED: session status mismatch';
  ASSERT (v_res->>'talk_id')::uuid = v_talk_cr_1_id, 'TEST G FAILED: talk id mismatch';
  ASSERT (v_res->>'program_record_id')::uuid = v_rec_id, 'TEST G FAILED: parent record id mismatch';
  v_talk_rec_id := (v_res->>'id')::uuid;
  RAISE NOTICE 'TEST G PASSED: Talk participation recorded against parent attempt';


  -- ---------------------------------------------------------------------------
  -- TEST H: Talk from wrong program rejected
  -- ---------------------------------------------------------------------------
  v_passed := false;
  BEGIN
    PERFORM public.record_member_formation_talk(
      p_organization_id => v_org_id,
      p_program_record_id => v_rec_id,
      p_talk_id => v_talk_other_id, -- talk from another program
      p_session_status => 'attended'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22023' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST H FAILED: talk from wrong program not rejected';
  RAISE NOTICE 'TEST H PASSED: Talk from wrong program rejected (22023)';


  -- ---------------------------------------------------------------------------
  -- TEST I: Duplicate active talk result rejected
  -- ---------------------------------------------------------------------------
  v_passed := false;
  BEGIN
    PERFORM public.record_member_formation_talk(
      p_organization_id => v_org_id,
      p_program_record_id => v_rec_id,
      p_talk_id => v_talk_cr_1_id, -- already recorded in TEST G
      p_session_status => 'attended'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '23505' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST I FAILED: duplicate active talk result not rejected';
  RAISE NOTICE 'TEST I PASSED: Duplicate active talk result rejected (23505)';


  -- ---------------------------------------------------------------------------
  -- TEST J: formation.records.correct required for program void
  -- ---------------------------------------------------------------------------
  -- Section leader has formation.records.view but NOT formation.records.correct
  PERFORM set_config('request.jwt.claim.sub', v_sec_a_leader::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sec_a_leader, 'role', 'authenticated')::text, true);

  v_passed := false;
  BEGIN
    PERFORM public.void_member_formation_program_record(
      p_organization_id => v_org_id,
      p_record_id => v_rec2_id,
      p_void_reason => 'Unauthorized attempt to void'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST J FAILED: user without records.correct was able to void program record';
  RAISE NOTICE 'TEST J PASSED: formation.records.correct required for program void';


  -- ---------------------------------------------------------------------------
  -- TEST K: formation.records.correct required for talk void
  -- ---------------------------------------------------------------------------
  v_passed := false;
  BEGIN
    PERFORM public.void_member_formation_talk_record(
      p_organization_id => v_org_id,
      p_talk_record_id => v_talk_rec_id,
      p_void_reason => 'Unauthorized attempt to void talk'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST K FAILED: user without records.correct was able to void talk record';
  RAISE NOTICE 'TEST K PASSED: formation.records.correct required for talk void';


  -- ---------------------------------------------------------------------------
  -- TEST L: Pastoral reader within scope can retrieve transcript
  -- ---------------------------------------------------------------------------
  -- Section A Leader can view Member A (placed in Section A)
  v_res := public.get_member_formation_transcript(
    p_organization_id => v_org_id,
    p_member_id => v_member_a_id
  );

  ASSERT (v_res->'member'->>'id')::uuid = v_member_a_id, 'TEST L FAILED: member id mismatch';
  ASSERT jsonb_array_length(v_res->'programs') = 2, 'TEST L FAILED: expected 2 programs in transcript';
  RAISE NOTICE 'TEST L PASSED: In-scope pastoral reader retrieved transcript';


  -- ---------------------------------------------------------------------------
  -- TEST M: Cross-subtree reader denied
  -- ---------------------------------------------------------------------------
  -- Section B Leader tries to read Member A (placed in Section A)
  PERFORM set_config('request.jwt.claim.sub', v_sec_b_leader::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sec_b_leader, 'role', 'authenticated')::text, true);

  v_passed := false;
  BEGIN
    PERFORM public.get_member_formation_transcript(
      p_organization_id => v_org_id,
      p_member_id => v_member_a_id
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST M FAILED: cross-subtree reader was not denied (42501)';
  RAISE NOTICE 'TEST M PASSED: Cross-subtree reader denied';


  -- ---------------------------------------------------------------------------
  -- TEST N: Self transcript authorization matrix (Section 12)
  -- ---------------------------------------------------------------------------
  -- Matrix A: permission + valid self-link -> succeeds
  PERFORM set_config('request.jwt.claim.sub', v_self_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_self_user, 'role', 'authenticated')::text, true);

  v_res := public.get_my_formation_transcript(v_org_id);
  ASSERT (v_res->'member'->>'id')::uuid = v_member_a_id, 'TEST N (Matrix A) FAILED: self transcript did not resolve Member A';
  ASSERT jsonb_array_length(v_res->'programs') = 2, 'TEST N (Matrix A) FAILED: self programs count != 2';
  RAISE NOTICE 'TEST N (Matrix A) PASSED: Self transcript resolved member with permission + verified link';

  -- Matrix B: permission but NO valid self-link -> denied with P0002
  PERFORM set_config('request.jwt.claim.sub', v_unlinked_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_unlinked_user, 'role', 'authenticated')::text, true);

  v_passed := false;
  BEGIN
    PERFORM public.get_my_formation_transcript(v_org_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0002' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST N (Matrix B) FAILED: unlinked user with permission was not denied (P0002)';
  RAISE NOTICE 'TEST N (Matrix B) PASSED: Permission without valid self-link denied (P0002)';

  -- Matrix C: valid self-link but NO members.self_service.view -> denied with 42501
  PERFORM set_config('request.jwt.claim.sub', v_noperm_linked_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_noperm_linked_user, 'role', 'authenticated')::text, true);

  v_passed := false;
  BEGIN
    PERFORM public.get_my_formation_transcript(v_org_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST N (Matrix C) FAILED: linked user without permission was not denied (42501)';
  RAISE NOTICE 'TEST N (Matrix C) PASSED: Verified self-link without permission denied (42501)';

  -- Matrix D: neither permission nor self-link -> denied
  PERFORM set_config('request.jwt.claim.sub', v_noperm_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_noperm_user, 'role', 'authenticated')::text, true);

  v_passed := false;
  BEGIN
    PERFORM public.get_my_formation_transcript(v_org_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE IN ('42501', 'P0002') THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST N (Matrix D) FAILED: user without permission or link was not denied';
  RAISE NOTICE 'TEST N (Matrix D) PASSED: Neither permission nor self-link denied';


  -- ---------------------------------------------------------------------------
  -- TEST O: Self transcript cannot view any other member (no member_id input)
  -- ---------------------------------------------------------------------------
  -- get_my_formation_transcript has no p_member_id argument by contract (validated in Part 1)
  -- And caller with only member role cannot call get_member_formation_transcript
  v_passed := false;
  BEGIN
    PERFORM public.get_member_formation_transcript(
      p_organization_id => v_org_id,
      p_member_id => v_member_b_id
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST O FAILED: plain member was able to call get_member_formation_transcript for other member';
  RAISE NOTICE 'TEST O PASSED: Plain member cannot view any other member';


  -- ---------------------------------------------------------------------------
  -- TEST P: Unauthenticated caller denied
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  v_passed := false;
  BEGIN
    PERFORM public.get_my_formation_transcript();
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '28000' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST P FAILED: unauthenticated caller not denied with 28000';
  RAISE NOTICE 'TEST P PASSED: Unauthenticated caller denied (28000)';


  -- ---------------------------------------------------------------------------
  -- TEST Q: Direct table INSERT/UPDATE/DELETE denied by RLS
  -- ---------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_admin_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_user, 'role', 'authenticated')::text, true);

  v_passed := false;
  BEGIN
    INSERT INTO public.member_formation_program_records (
      organization_id, member_id, program_id, status, recorded_by_profile_id
    ) VALUES (
      v_org_id, v_member_a_id, v_prog_cr_id, 'completed', v_admin_user
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST Q FAILED: direct INSERT was not blocked by RLS default-deny';
  RAISE NOTICE 'TEST Q PASSED: Direct table INSERT denied by RLS';


  -- ---------------------------------------------------------------------------
  -- TEST R: Program-only course returns no-talk progress safely
  -- ---------------------------------------------------------------------------
  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_member_a_id,
    p_program_id => v_prog_cls_id, -- CLS has 0 talks
    p_status => 'completed',
    p_completed_date => '2023-10-10'::date,
    p_date_precision => 'exact_date'
  );

  v_res := public.get_member_formation_transcript(v_org_id, v_member_a_id);

  -- Inspect CLS entry progress
  SELECT elem->'progress' INTO v_res
  FROM jsonb_array_elements(v_res->'programs') elem
  WHERE (elem->>'code') = 'CLS';

  ASSERT (v_res->>'total_talks')::integer = 0, 'TEST R FAILED: total talks != 0 for CLS';
  ASSERT (v_res->>'progress_status') = 'not_applicable', 'TEST R FAILED: progress_status != not_applicable';
  ASSERT v_res->>'progress_percent' IS NULL, 'TEST R FAILED: progress_percent must be null';
  RAISE NOTICE 'TEST R PASSED: Program-only course returns not_applicable progress with null percent';


  -- ---------------------------------------------------------------------------
  -- TEST S: Retired curriculum history remains visible
  -- ---------------------------------------------------------------------------
  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_member_a_id,
    p_program_id => v_prog_retired_id, -- is_active = false
    p_status => 'completed',
    p_completed_year => 1998::smallint,
    p_date_precision => 'year_only'
  );

  v_res := public.get_member_formation_transcript(v_org_id, v_member_a_id);

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_res->'programs') elem
  WHERE (elem->>'code') = 'RETIRED-ED1';

  ASSERT v_count = 1, 'TEST S FAILED: retired program completion not found in transcript';
  RAISE NOTICE 'TEST S PASSED: Historical record against retired curriculum remains visible';


  -- ---------------------------------------------------------------------------
  -- TEST T: Empty transcript is valid
  -- ---------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_admin_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_user, 'role', 'authenticated')::text, true);

  v_res := public.get_member_formation_transcript(v_org_id, 'c0000000-0000-0000-0000-000000000001');
  ASSERT (v_res->'member'->>'id')::uuid = 'c0000000-0000-0000-0000-000000000001', 'TEST T FAILED: member id mismatch';
  ASSERT jsonb_array_length(v_res->'programs') = 0, 'TEST T FAILED: expected 0 programs for empty transcript';
  RAISE NOTICE 'TEST T PASSED: Empty transcript is valid with empty programs array';


  -- ---------------------------------------------------------------------------
  -- TEST: Void Program Cascades to Child Talks Atomically
  -- ---------------------------------------------------------------------------
  v_res := public.void_member_formation_program_record(
    p_organization_id => v_org_id,
    p_record_id => v_rec_id,
    p_void_reason => 'Administrative correction test'
  );

  ASSERT (v_res->>'record_status') = 'voided', 'VOID TEST FAILED: program record_status != voided';
  ASSERT (v_res->>'cascade_voided_talk_count')::integer >= 1, 'VOID TEST FAILED: talk cascade count < 1';

  -- Verify talk is voided (switch to postgres to bypass RLS/privilege deny)
  PERFORM set_config('role', 'postgres', true);
  SELECT record_status INTO v_prog_status
  FROM public.member_formation_talk_records
  WHERE id = v_talk_rec_id;
  ASSERT v_prog_status = 'voided', 'VOID TEST FAILED: child talk record status != voided';

  -- Verify voided record excluded from active transcript
  PERFORM set_config('role', 'authenticated', true);
  v_res := public.get_member_formation_transcript(v_org_id, v_member_a_id);
  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_res->'programs') elem
  WHERE (elem->>'record_id')::uuid = v_rec_id;
  ASSERT v_count = 0, 'VOID TEST FAILED: voided program record still in active transcript';
  RAISE NOTICE 'VOID TEST PASSED: Program void atomically cascades to child talks and excludes from active transcript';


  -- ---------------------------------------------------------------------------
  -- TEST V: Verifier Provenance Reconciliation (Rule B)
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_user, 'role', 'authenticated')::text, true);

  -- V.1: Leader attestation sets verifier = caller and verified_at is populated
  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_member_b_id,
    p_program_id => v_prog_cr_id,
    p_status => 'completed',
    p_completed_date => '2024-01-10'::date,
    p_date_precision => 'exact_date',
    p_verification_method => 'leader_attestation'
  );
  ASSERT (v_res->>'verified_at') IS NOT NULL, 'TEST V.1 FAILED: verified_at is null for leader_attestation';

  PERFORM set_config('role', 'postgres', true);
  SELECT verified_by_profile_id, recorded_by_profile_id INTO v_verified_by_id, v_actor_profile_id
  FROM public.member_formation_program_records
  WHERE id = (v_res->>'id')::uuid;
  ASSERT v_verified_by_id = v_admin_user, 'TEST V.1 FAILED: verified_by_profile_id != caller';
  ASSERT v_actor_profile_id = v_admin_user, 'TEST V.1 FAILED: recorded_by_profile_id != caller';
  RAISE NOTICE 'TEST V.1 PASSED: Leader attestation sets verifier = caller';

  -- V.2: Historical backfill sets verifier = null and verified_at = null
  PERFORM set_config('role', 'authenticated', true);
  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_member_b_id,
    p_program_id => v_prog_cr_id,
    p_status => 'completed',
    p_completed_year => 2012::smallint,
    p_date_precision => 'year_only',
    p_verification_method => 'historical_backfill',
    p_source_reference => 'Cert-2012'
  );
  ASSERT v_res->>'verified_at' IS NULL, 'TEST V.2 FAILED: verified_at is not null for historical_backfill';

  PERFORM set_config('role', 'postgres', true);
  SELECT verified_by_profile_id, recorded_by_profile_id INTO v_verified_by_id, v_actor_profile_id
  FROM public.member_formation_program_records
  WHERE id = (v_res->>'id')::uuid;
  ASSERT v_verified_by_id IS NULL, 'TEST V.2 FAILED: verified_by_profile_id must be null for backfill';
  ASSERT v_actor_profile_id = v_admin_user, 'TEST V.2 FAILED: recorded_by_profile_id != caller';
  RAISE NOTICE 'TEST V.2 PASSED: Historical backfill verifier is null without fabricated profile attribution';

  -- V.3: Pastoral waiver sets verifier = caller and verified_at is populated
  PERFORM set_config('role', 'authenticated', true);
  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_member_b_id,
    p_program_id => v_prog_cls_id,
    p_status => 'waived',
    p_date_precision => 'unknown',
    p_verification_method => 'pastoral_waiver',
    p_verification_notes => 'Waived due to equivalent prerequisite'
  );
  ASSERT (v_res->>'verified_at') IS NOT NULL, 'TEST V.3 FAILED: verified_at is null for pastoral_waiver';

  PERFORM set_config('role', 'postgres', true);
  SELECT verified_by_profile_id, recorded_by_profile_id INTO v_verified_by_id, v_actor_profile_id
  FROM public.member_formation_program_records
  WHERE id = (v_res->>'id')::uuid;
  ASSERT v_verified_by_id = v_admin_user, 'TEST V.3 FAILED: verified_by_profile_id != caller for waiver';
  ASSERT v_actor_profile_id = v_admin_user, 'TEST V.3 FAILED: recorded_by_profile_id != caller for waiver';
  RAISE NOTICE 'TEST V.3 PASSED: Pastoral waiver sets verifier = caller';

  -- V.4: Arbitrary unrelated profile cannot be attributed as verifier via browser parameter spoofing
  -- Old 12-parameter signature with p_verified_by_profile_id was dropped in Migration 99
  PERFORM set_config('role', 'authenticated', true);
  v_passed := false;
  BEGIN
    EXECUTE 'SELECT public.record_member_formation_program($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)'
    USING v_org_id, v_member_b_id, v_prog_cls_id, 'completed', current_date, null, null, 'exact_date', 'leader_attestation', null, null, v_noperm_user;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42883' THEN
      v_passed := true;
    END IF;
  END;
  ASSERT v_passed, 'TEST V.4 FAILED: old 12-argument spoofable signature still exists';
  RAISE NOTICE 'TEST V.4 PASSED: Spoofed verifier parameter rejected (signature dropped)';

  -- V.5: Audit event records caller as actor
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_count
  FROM audit.events
  WHERE event_code = 'formation.program_record.recorded'
    AND actor_profile_id = v_admin_user
    AND entity_id = (v_res->>'id')::uuid;
  ASSERT v_count = 1, 'TEST V.5 FAILED: audit event actor != authenticated caller';
  RAISE NOTICE 'TEST V.5 PASSED: Audit event actor remains authentic caller';

END $$;

ROLLBACK;

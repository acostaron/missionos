-- =============================================================================
-- Test Suite: phase_6b_household_meetings_attendance_security.sql
-- Phase:      Phase 6B-8 — Household Meetings, Attendance & Pastoral Follow-up
--
-- Tests & Validates:
--   PART 1: Schema & Permission Registration
--     - 1.1 households.meetings.view registered
--     - 1.2 households.meetings.manage registered
--     - 1.3 households.attendance.record registered
--     - 1.4 All three assigned to organization_administrator
--     - 1.5 Tables household_meetings and household_meeting_attendance exist
--     - 1.6 Check constraint on household_meetings.meeting_status
--
--   PART 2: RPC Security – Anonymous Rejection (28000)
--     - 2.1 create_household_meeting → 28000
--     - 2.2 cancel_household_meeting → 28000
--     - 2.3 complete_household_meeting → 28000
--     - 2.4 record_household_meeting_attendance → 28000
--     - 2.5 get_household_meeting_history → 28000
--     - 2.6 get_household_meeting_detail → 28000
--
--   PART 3: RPC Security – Authenticated Without Permission (42501)
--     - 3.1 create_household_meeting → 42501
--     - 3.2 get_household_meeting_history → 42501
--     - 3.3 record_household_meeting_attendance → 42501
--
--   PART 4: Happy Path
--     - 4.1 Admin creates a meeting → meeting_id returned, status=scheduled
--     - 4.2 Admin completes the meeting → status=completed
--     - 4.3 Admin records attendance for 2 members → rows_inserted=2
--     - 4.4 get_household_meeting_history returns the meeting
--     - 4.5 get_household_meeting_detail returns expected_roster + recorded_attendance
--
--   PART 5: Historical Roster Semantics
--     - 5.1 Member who left before meeting_date NOT in expected_roster
--     - 5.2 Member who joined after meeting_date NOT in expected_roster
--     - 5.3 Active members spanning meeting_date ARE in expected_roster
--
--   PART 6: Cancellation Guards
--     - 6.1 Cancel scheduled meeting → status=cancelled
--     - 6.2 Complete cancelled meeting → 23514
--     - 6.3 Record attendance on cancelled meeting → 23514
--
--   PART 7: Future-date Guards
--     - 7.1 Complete future meeting → 23514
--     - 7.2 Record attendance for future meeting → 23514
--
--   PART 8: Scope Enforcement (P0002)
--     - 8.1 create_household_meeting for unknown household → P0002
--     - 8.2 get_household_meeting_history for unknown household → P0002
--
--   PART 9: Attendance Correction Tracking
--     - 9.1 Re-submit with changed status → rows_updated↑ has_correction=true
--     - 9.2 Re-submit with same status → rows_updated↑ has_correction=false
--
--   PART 10: Privacy – Zero PII Leakage
--     - 10.1 detail result has no email/phone/address/date_of_birth fields
--     - 10.2 history meeting rows have no email/phone/date_of_birth fields
--
--   PART 11: Zero Mutation Side Effects on Read RPCs
--     - 11.1 get_household_meeting_history causes no writes
--     - 11.2 get_household_meeting_detail causes no writes
--
-- Non-destructive. Wrapped in a transaction and strictly ROLLED BACK.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  -- Org & profiles (resolved from seeded data)
  v_org_id              uuid;
  v_admin_profile       uuid;
  v_viewer_profile      uuid;

  -- Governance
  v_type_unit_id        uuid;
  v_node_unit_id        uuid;
  v_household_id        uuid;

  -- Members
  v_member_1_id         uuid;
  v_member_2_id         uuid;
  v_member_past_id      uuid;   -- left before meeting date
  v_member_future_id    uuid;   -- joined after meeting date

  -- Meetings
  v_meeting_res         jsonb;
  v_meeting_id          uuid;
  v_cancel_meeting_id   uuid;
  v_future_meeting_id   uuid;

  -- Results
  v_history_res         jsonb;
  v_detail_res          jsonb;
  v_attend_res          jsonb;

  -- Test helpers
  v_count               integer;
  v_blocked             boolean;
  v_past_date           date := current_date - 7;
  v_future_date         date := current_date + 5;

  v_hh_node_type_id     uuid;
  v_unit_node_id        uuid;
BEGIN

  -- ======================================================================
  -- SCAFFOLD: Resolve seeded org and admin
  -- ======================================================================

  SELECT id INTO STRICT v_org_id FROM public.organizations LIMIT 1;

  SELECT p.id INTO STRICT v_admin_profile
  FROM public.profiles p
  JOIN public.profile_role_assignments pra ON pra.profile_id = p.id
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE pra.organization_id = v_org_id
    AND ar.code = 'organization_administrator'
    AND pra.assignment_status = 'active'
  LIMIT 1;

  -- Create a viewer profile (no admin role)
  v_viewer_profile := gen_random_uuid();
  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_viewer_profile, 'authenticated', 'authenticated', 'viewer_6b8@test.local');
  INSERT INTO public.profiles (id, display_name) VALUES (v_viewer_profile, 'Viewer 6B8');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_viewer_profile, v_org_id, 'active', now());

  -- Set admin context
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ======================================================================
  -- SCAFFOLD: Governance nodes, household, members
  -- ======================================================================

  -- Resolve or create a unit-type governance node type
  SELECT id INTO v_type_unit_id
  FROM public.governance_node_types
  WHERE organization_id = v_org_id AND code = 'unit' LIMIT 1;

  IF v_type_unit_id IS NULL THEN
    INSERT INTO public.governance_node_types (organization_id, code, name, level, allows_households)
    VALUES (v_org_id, 'unit_6b8', 'Unit 6B8', 2, true) RETURNING id INTO v_type_unit_id;
  END IF;

  -- Create a unit governance node
  INSERT INTO public.governance_nodes (
    organization_id, governance_node_type_id, code, name,
    lifecycle_status, effective_from, metadata
  )
  VALUES (
    v_org_id, v_type_unit_id,
    'test_unit_6b8_' || floor(random()*999999)::text,
    'Test Unit 6B8',
    'active', current_date - 365, '{}'
  ) RETURNING id INTO v_unit_node_id;

  -- Create the household via the public RPC
  v_meeting_res := public.create_household(
    p_organization_id            => v_org_id,
    p_name                       => 'Test HH 6B8',
    p_code                       => 'hh_6b8_' || floor(random()*999999)::text,
    p_parent_governance_node_id  => v_unit_node_id,
    p_household_category         => 'pastoral',
    p_effective_from             => current_date - 365,
    p_meeting_frequency          => 'weekly',
    p_meeting_day_of_week        => 5::smallint,
    p_meeting_start_time         => '19:00'::time,
    p_meeting_timezone_name      => 'America/New_York',
    p_pastoral_level             => 'member'
  );
  v_household_id := (v_meeting_res->>'household_id')::uuid;

  -- Create 4 members
  DECLARE
    v_m1 jsonb; v_m2 jsonb; v_mp jsonb; v_mf jsonb;
  BEGIN
    v_m1 := public.create_member(p_organization_id => v_org_id, p_given_names => 'Alice', p_family_name => 'Smith', p_governance_node_id => v_unit_node_id, p_joined_on => v_past_date - 90);
    v_member_1_id := (v_m1->>'member_id')::uuid;

    v_m2 := public.create_member(p_organization_id => v_org_id, p_given_names => 'Bob', p_family_name => 'Jones', p_governance_node_id => v_unit_node_id, p_joined_on => v_past_date - 90);
    v_member_2_id := (v_m2->>'member_id')::uuid;

    v_mp := public.create_member(p_organization_id => v_org_id, p_given_names => 'Carol', p_family_name => 'Past', p_governance_node_id => v_unit_node_id, p_joined_on => v_past_date - 90);
    v_member_past_id := (v_mp->>'member_id')::uuid;

    v_mf := public.create_member(p_organization_id => v_org_id, p_given_names => 'Dave', p_family_name => 'Future', p_governance_node_id => v_unit_node_id, p_joined_on => v_past_date - 1);
    v_member_future_id := (v_mf->>'member_id')::uuid;
  END;

  -- Assign member_1 and member_2 (active spanning the meeting date)
  PERFORM public.assign_member_to_household(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_1_id,
    p_household_id             => v_household_id,
    p_effective_from           => v_past_date - 30,
    p_confirm_governance_mismatch => true
  );
  PERFORM public.assign_member_to_household(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_2_id,
    p_household_id             => v_household_id,
    p_effective_from           => v_past_date - 30,
    p_confirm_governance_mismatch => true
  );

  -- Assign past member but end their membership 3 days before meeting
  PERFORM public.assign_member_to_household(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_past_id,
    p_household_id             => v_household_id,
    p_effective_from           => v_past_date - 60,
    p_confirm_governance_mismatch => true
  );
  UPDATE public.household_memberships
  SET membership_status = 'ended', effective_to = (v_past_date - 3)
  WHERE member_id = v_member_past_id
    AND household_node_id = v_household_id
    AND membership_status = 'active';

  -- Assign future member starting 2 days after meeting
  PERFORM public.assign_member_to_household(
    p_organization_id          => v_org_id,
    p_member_id                => v_member_future_id,
    p_household_id             => v_household_id,
    p_effective_from           => v_past_date + 2,
    p_confirm_governance_mismatch => true
  );

  -- ======================================================================
  -- PART 1: Schema & Permission Registration
  -- ======================================================================

  SELECT count(*) INTO v_count FROM public.permissions WHERE code = 'households.meetings.view';
  ASSERT v_count = 1, 'FAIL 1.1: households.meetings.view not registered';

  SELECT count(*) INTO v_count FROM public.permissions WHERE code = 'households.meetings.manage';
  ASSERT v_count = 1, 'FAIL 1.2: households.meetings.manage not registered';

  SELECT count(*) INTO v_count FROM public.permissions WHERE code = 'households.attendance.record';
  ASSERT v_count = 1, 'FAIL 1.3: households.attendance.record not registered';

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE p.code IN ('households.meetings.view','households.meetings.manage','households.attendance.record')
    AND ar.code = 'organization_administrator'
    AND rp.permission_effect = 'allow';
  ASSERT v_count >= 3, format('FAIL 1.4: expected >=3 admin grants, got %s', v_count);

  SELECT count(*) INTO v_count FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name IN ('household_meetings','household_meeting_attendance');
  ASSERT v_count = 2, 'FAIL 1.5: both tables must exist';

  SELECT count(*) INTO v_count FROM information_schema.table_constraints
  WHERE table_schema = 'public' AND table_name = 'household_meetings'
    AND constraint_type = 'CHECK' AND constraint_name = 'ck_household_meetings__status';
  ASSERT v_count = 1, 'FAIL 1.6: ck_household_meetings__status constraint missing';

  RAISE NOTICE 'PART 1 PASSED.';

  -- ======================================================================
  -- PART 2: Anonymous Rejection (28000)
  -- ======================================================================

  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);

  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_household_id, current_date - 1);
  EXCEPTION WHEN sqlstate '28000' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 2.1: create_household_meeting must reject anon (28000)';

  v_blocked := false;
  BEGIN
    PERFORM public.cancel_household_meeting(v_org_id, gen_random_uuid());
  EXCEPTION WHEN sqlstate '28000' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 2.2: cancel_household_meeting must reject anon (28000)';

  v_blocked := false;
  BEGIN
    PERFORM public.complete_household_meeting(v_org_id, gen_random_uuid());
  EXCEPTION WHEN sqlstate '28000' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 2.3: complete_household_meeting must reject anon (28000)';

  v_blocked := false;
  BEGIN
    PERFORM public.record_household_meeting_attendance(v_org_id, gen_random_uuid(), '[]'::jsonb);
  EXCEPTION WHEN sqlstate '28000' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 2.4: record_household_meeting_attendance must reject anon (28000)';

  v_blocked := false;
  BEGIN
    PERFORM public.get_household_meeting_history(v_org_id, v_household_id);
  EXCEPTION WHEN sqlstate '28000' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 2.5: get_household_meeting_history must reject anon (28000)';

  v_blocked := false;
  BEGIN
    PERFORM public.get_household_meeting_detail(v_org_id, gen_random_uuid());
  EXCEPTION WHEN sqlstate '28000' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 2.6: get_household_meeting_detail must reject anon (28000)';

  RAISE NOTICE 'PART 2 PASSED.';

  -- ======================================================================
  -- PART 3: Authenticated Without Permission (42501)
  -- ======================================================================

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_viewer_profile, 'role', 'authenticated')::text, true);

  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, v_household_id, current_date - 1);
  EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 3.1: create_household_meeting must reject unpermissioned user (42501)';

  v_blocked := false;
  BEGIN
    PERFORM public.get_household_meeting_history(v_org_id, v_household_id);
  EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 3.2: get_household_meeting_history must reject unpermissioned user (42501)';

  v_blocked := false;
  BEGIN
    PERFORM public.record_household_meeting_attendance(v_org_id, gen_random_uuid(), '[]'::jsonb);
  EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 3.3: record_household_meeting_attendance must reject unpermissioned user (42501)';

  RAISE NOTICE 'PART 3 PASSED.';

  -- Switch back to admin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ======================================================================
  -- PART 4: Happy Path
  -- ======================================================================

  -- 4.1 Create meeting (past date)
  v_meeting_res := public.create_household_meeting(
    p_organization_id       => v_org_id,
    p_household_id          => v_household_id,
    p_meeting_date          => v_past_date,
    p_meeting_type          => 'regular_household',
    p_location_type         => 'in_person',
    p_location_text         => '123 Church St',
    p_facilitator_member_id => v_member_1_id
  );
  v_meeting_id := (v_meeting_res->>'household_meeting_id')::uuid;
  ASSERT v_meeting_id IS NOT NULL, 'FAIL 4.1: create_household_meeting must return meeting_id';
  ASSERT (v_meeting_res->>'meeting_status') = 'scheduled', 'FAIL 4.1: new meeting must have status=scheduled';

  -- 4.2 Complete the meeting (NOTE 020200: p_notes_summary is reserved/unused, must be NULL)
  v_meeting_res := public.complete_household_meeting(
    p_organization_id => v_org_id,
    p_meeting_id      => v_meeting_id
  );
  ASSERT (v_meeting_res->>'meeting_status') = 'completed', 'FAIL 4.2: complete_household_meeting must return status=completed';


  -- 4.3 Record attendance for 2 members
  v_attend_res := public.record_household_meeting_attendance(
    p_organization_id => v_org_id,
    p_meeting_id      => v_meeting_id,
    p_attendance      => format('[{"member_id":"%s","attendance_status":"present"},{"member_id":"%s","attendance_status":"absent"}]',
                                v_member_1_id, v_member_2_id)::jsonb
  );
  ASSERT (v_attend_res->>'rows_inserted')::integer = 2, format('FAIL 4.3: expected 2 rows_inserted, got %s', v_attend_res->>'rows_inserted');

  -- 4.4 History contains the meeting
  v_history_res := public.get_household_meeting_history(v_org_id, v_household_id);
  ASSERT (v_history_res->>'total_count')::integer >= 1, 'FAIL 4.4: history must have at least 1 meeting';
  ASSERT jsonb_array_length(v_history_res->'meetings') >= 1, 'FAIL 4.4: meetings array must be non-empty';

  -- 4.5 Detail contains expected_roster and recorded_attendance
  v_detail_res := public.get_household_meeting_detail(v_org_id, v_meeting_id);
  ASSERT (v_detail_res->>'household_meeting_id') IS NOT NULL, 'FAIL 4.5: detail must include household_meeting_id';
  ASSERT jsonb_typeof(v_detail_res->'expected_roster') = 'array', 'FAIL 4.5: expected_roster must be an array';
  ASSERT jsonb_typeof(v_detail_res->'recorded_attendance') = 'array', 'FAIL 4.5: recorded_attendance must be an array';
  ASSERT jsonb_array_length(v_detail_res->'recorded_attendance') = 2, 'FAIL 4.5: recorded_attendance must have 2 rows';

  RAISE NOTICE 'PART 4 PASSED.';

  -- ======================================================================
  -- PART 5: Historical Roster Semantics
  -- ======================================================================

  -- 5.1 Past member (left before meeting) must NOT appear
  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_detail_res->'expected_roster') r
  WHERE (r->>'member_id')::uuid = v_member_past_id;
  ASSERT v_count = 0, 'FAIL 5.1: member who left before meeting_date must not be in expected_roster';

  -- 5.2 Future member (joined after meeting) must NOT appear
  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_detail_res->'expected_roster') r
  WHERE (r->>'member_id')::uuid = v_member_future_id;
  ASSERT v_count = 0, 'FAIL 5.2: member who joined after meeting_date must not be in expected_roster';

  -- 5.3 Active members spanning meeting date must appear
  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_detail_res->'expected_roster') r
  WHERE (r->>'member_id')::uuid IN (v_member_1_id, v_member_2_id);
  ASSERT v_count = 2, format('FAIL 5.3: both active members must be in expected_roster, found %s', v_count);

  RAISE NOTICE 'PART 5 PASSED.';

  -- ======================================================================
  -- PART 6: Cancellation Guards
  -- ======================================================================

  -- 6.1 Cancel a fresh scheduled meeting
  v_meeting_res := public.create_household_meeting(
    p_organization_id => v_org_id,
    p_household_id    => v_household_id,
    p_meeting_date    => v_past_date - 14
  );
  v_cancel_meeting_id := (v_meeting_res->>'household_meeting_id')::uuid;

  v_meeting_res := public.cancel_household_meeting(v_org_id, v_cancel_meeting_id, 'Weather');
  ASSERT (v_meeting_res->>'meeting_status') = 'cancelled', 'FAIL 6.1: cancelled meeting must have status=cancelled';

  -- 6.2 Cannot complete a cancelled meeting
  v_blocked := false;
  BEGIN
    PERFORM public.complete_household_meeting(v_org_id, v_cancel_meeting_id);
  EXCEPTION WHEN sqlstate '23514' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 6.2: completing a cancelled meeting must raise 23514';

  -- 6.3 Cannot record attendance on cancelled meeting
  v_blocked := false;
  BEGIN
    PERFORM public.record_household_meeting_attendance(
      v_org_id, v_cancel_meeting_id,
      format('[{"member_id":"%s","attendance_status":"present"}]', v_member_1_id)::jsonb
    );
  EXCEPTION WHEN sqlstate '23514' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 6.3: attendance on cancelled meeting must raise 23514';

  RAISE NOTICE 'PART 6 PASSED.';

  -- ======================================================================
  -- PART 7: Future-date Guards
  -- ======================================================================

  v_meeting_res := public.create_household_meeting(
    p_organization_id => v_org_id,
    p_household_id    => v_household_id,
    p_meeting_date    => v_future_date
  );
  v_future_meeting_id := (v_meeting_res->>'household_meeting_id')::uuid;

  -- 7.1 Cannot complete a future meeting
  v_blocked := false;
  BEGIN
    PERFORM public.complete_household_meeting(v_org_id, v_future_meeting_id);
  EXCEPTION WHEN sqlstate '23514' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 7.1: completing a future meeting must raise 23514';

  -- 7.2 Cannot record attendance for a future meeting
  v_blocked := false;
  BEGIN
    PERFORM public.record_household_meeting_attendance(
      v_org_id, v_future_meeting_id,
      format('[{"member_id":"%s","attendance_status":"present"}]', v_member_1_id)::jsonb
    );
  EXCEPTION WHEN sqlstate '23514' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 7.2: attendance on future meeting must raise 23514';

  RAISE NOTICE 'PART 7 PASSED.';

  -- ======================================================================
  -- PART 8: Scope Enforcement (P0002)
  -- ======================================================================

  -- 8.1 Unknown household → P0002 on create
  v_blocked := false;
  BEGIN
    PERFORM public.create_household_meeting(v_org_id, gen_random_uuid(), current_date - 1);
  EXCEPTION WHEN sqlstate 'P0002' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 8.1: create with unknown household_id must raise P0002';

  -- 8.2 Unknown household → P0002 on history
  v_blocked := false;
  BEGIN
    PERFORM public.get_household_meeting_history(v_org_id, gen_random_uuid());
  EXCEPTION WHEN sqlstate 'P0002' THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAIL 8.2: history for unknown household must raise P0002';

  RAISE NOTICE 'PART 8 PASSED.';

  -- ======================================================================
  -- PART 9: Attendance Correction Tracking
  -- ======================================================================

  -- 9.1 Re-submit with CHANGED status → has_correction=true
  v_attend_res := public.record_household_meeting_attendance(
    p_organization_id => v_org_id,
    p_meeting_id      => v_meeting_id,
    p_attendance      => format('[{"member_id":"%s","attendance_status":"excused"}]', v_member_2_id)::jsonb
  );
  ASSERT (v_attend_res->>'rows_updated')::integer = 1, 'FAIL 9.1: re-submit with changed status must increment rows_updated';
  ASSERT (v_attend_res->>'has_correction')::boolean = true, 'FAIL 9.1: changed status must set has_correction=true';

  -- 9.2 Re-submit with SAME status → has_correction=false
  v_attend_res := public.record_household_meeting_attendance(
    p_organization_id => v_org_id,
    p_meeting_id      => v_meeting_id,
    p_attendance      => format('[{"member_id":"%s","attendance_status":"present"}]', v_member_1_id)::jsonb
  );
  ASSERT (v_attend_res->>'rows_updated')::integer = 1, 'FAIL 9.2: re-submit with same status must increment rows_updated';
  ASSERT (v_attend_res->>'has_correction')::boolean = false, 'FAIL 9.2: same status must NOT set has_correction=true';

  RAISE NOTICE 'PART 9 PASSED.';

  -- ======================================================================
  -- PART 10: Privacy – Zero PII Leakage
  -- ======================================================================

  -- 10.1 Detail result must not expose PII fields
  ASSERT NOT (v_detail_res ? 'email'),         'FAIL 10.1: detail must not include email';
  ASSERT NOT (v_detail_res ? 'phone'),          'FAIL 10.1: detail must not include phone';
  ASSERT NOT (v_detail_res ? 'address'),        'FAIL 10.1: detail must not include address';
  ASSERT NOT (v_detail_res ? 'date_of_birth'),  'FAIL 10.1: detail must not include date_of_birth';
  ASSERT NOT (v_detail_res ? 'given_names'),    'FAIL 10.1: detail must not include given_names';
  ASSERT NOT (v_detail_res ? 'family_name'),    'FAIL 10.1: detail must not include family_name';

  -- 10.2 History meeting rows must not expose PII
  DECLARE v_first_meeting jsonb;
  BEGIN
    v_first_meeting := (v_history_res->'meetings')->0;
    ASSERT NOT (v_first_meeting ? 'email'),        'FAIL 10.2: history meeting must not include email';
    ASSERT NOT (v_first_meeting ? 'phone'),         'FAIL 10.2: history meeting must not include phone';
    ASSERT NOT (v_first_meeting ? 'date_of_birth'), 'FAIL 10.2: history meeting must not include date_of_birth';
  END;

  RAISE NOTICE 'PART 10 PASSED.';

  -- ======================================================================
  -- PART 11: Zero Mutation Side Effects on Read RPCs
  -- ======================================================================

  DECLARE
    v_meetings_before integer;
    v_meetings_after  integer;
    v_att_before      integer;
    v_att_after       integer;
  BEGIN
    SELECT count(*) INTO v_meetings_before FROM public.household_meetings WHERE household_node_id = v_household_id;
    PERFORM public.get_household_meeting_history(v_org_id, v_household_id);
    SELECT count(*) INTO v_meetings_after FROM public.household_meetings WHERE household_node_id = v_household_id;
    ASSERT v_meetings_before = v_meetings_after, 'FAIL 11.1: get_household_meeting_history must not mutate rows';

    SELECT count(*) INTO v_att_before FROM public.household_meeting_attendance WHERE household_meeting_id = v_meeting_id;
    PERFORM public.get_household_meeting_detail(v_org_id, v_meeting_id);
    SELECT count(*) INTO v_att_after FROM public.household_meeting_attendance WHERE household_meeting_id = v_meeting_id;
    ASSERT v_att_before = v_att_after, 'FAIL 11.2: get_household_meeting_detail must not mutate rows';
  END;

  RAISE NOTICE 'PART 11 PASSED.';

  -- ======================================================================
  -- PART 12: Household Meeting Cadence & Operational Status
  -- ======================================================================
  DECLARE
    v_cad_res      jsonb;
    v_cad_mtg_id   uuid;
    v_cad_sch_id   uuid;
  BEGIN
    -- Clean up any existing meetings for v_household_id to start from clean state
    DELETE FROM public.household_meeting_attendance
    WHERE household_meeting_id IN (
      SELECT id FROM public.household_meetings WHERE household_node_id = v_household_id
    );
    DELETE FROM public.household_meetings WHERE household_node_id = v_household_id;

    -- Ensure stable roster (only member 1 and member 2) across all test dates
    DELETE FROM public.household_memberships
    WHERE household_node_id = v_household_id
      AND member_id IN (v_member_past_id, v_member_future_id);

    UPDATE public.household_memberships
    SET effective_from = (current_date - interval '1 year')::date
    WHERE household_node_id = v_household_id;

    -- 12.1 NULL frequency => not_configured
    UPDATE public.households SET meeting_frequency = null WHERE id = v_household_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'not_configured', 'FAIL 12.1: NULL frequency must be not_configured';
    ASSERT v_cad_res->>'expected_next_meeting_date' IS NULL, 'FAIL 12.1: expected_next_meeting_date must be null';

    -- 12.2 seasonal => not_configured, never overdue
    UPDATE public.households SET meeting_frequency = 'seasonal' WHERE id = v_household_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'not_configured', 'FAIL 12.2: seasonal must be not_configured';

    -- 12.3 variable => not_configured, never overdue
    UPDATE public.households SET meeting_frequency = 'variable' WHERE id = v_household_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'not_configured', 'FAIL 12.3: variable must be not_configured';

    -- 12.4 weekly with no meetings => no_meeting_history
    UPDATE public.households SET meeting_frequency = 'weekly' WHERE id = v_household_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'no_meeting_history', 'FAIL 12.4: 0 meetings must be no_meeting_history';
    ASSERT v_cad_res->>'last_completed_meeting_date' IS NULL, 'FAIL 12.4: last_completed_meeting_date must be null';

    -- 12.5 weekly: last completed 8 days ago => overdue
    INSERT INTO public.household_meetings (
      organization_id, household_node_id, meeting_date, meeting_status, meeting_type
    ) VALUES (
      v_org_id, v_household_id, current_date - 8, 'completed', 'regular_household'
    ) RETURNING id INTO v_cad_mtg_id;

    -- Record attendance for all 2 active members so attendance is complete
    INSERT INTO public.household_meeting_attendance (
      organization_id, household_meeting_id, member_id, attendance_status
    ) VALUES
      (v_org_id, v_cad_mtg_id, v_member_1_id, 'present'),
      (v_org_id, v_cad_mtg_id, v_member_2_id, 'present');

    UPDATE public.household_meetings SET attendance_recorded_at = now() WHERE id = v_cad_mtg_id;

    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'overdue', format('FAIL 12.5: expected overdue, got %s', v_cad_res->>'meeting_operational_status');
    ASSERT (v_cad_res->>'days_since_last_completed_meeting')::integer = 8, 'FAIL 12.5: days_since must be 8';
    ASSERT (v_cad_res->>'expected_next_meeting_date')::date = current_date - 1, 'FAIL 12.5: expected_next must be current_date - 1';

    -- 12.6 weekly: last completed 3 days ago => current
    UPDATE public.household_meetings SET meeting_date = current_date - 3 WHERE id = v_cad_mtg_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'current', format('FAIL 12.6: expected current, got %s', v_cad_res->>'meeting_operational_status');
    ASSERT (v_cad_res->>'days_since_last_completed_meeting')::integer = 3, 'FAIL 12.6: days_since must be 3';
    ASSERT (v_cad_res->>'expected_next_meeting_date')::date = current_date + 4, 'FAIL 12.6: expected_next must be current_date + 4';

    -- 12.7 biweekly: 15 days ago => overdue
    UPDATE public.households SET meeting_frequency = 'biweekly' WHERE id = v_household_id;
    UPDATE public.household_meetings SET meeting_date = current_date - 15 WHERE id = v_cad_mtg_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'overdue', format('FAIL 12.7: expected overdue for biweekly 15d, got %s', v_cad_res->>'meeting_operational_status');
    ASSERT (v_cad_res->>'expected_next_meeting_date')::date = current_date - 1, 'FAIL 12.7: expected_next must be current_date - 1';

    -- 12.8 monthly: proper calendar-month arithmetic
    UPDATE public.households SET meeting_frequency = 'monthly' WHERE id = v_household_id;
    -- (current_date - 1 month - 1 day) => overdue
    UPDATE public.household_meetings SET meeting_date = (current_date - interval '1 month' - interval '1 day')::date WHERE id = v_cad_mtg_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'overdue', format('FAIL 12.8: expected overdue for monthly, got %s', v_cad_res->>'meeting_operational_status');
    ASSERT (v_cad_res->>'expected_next_meeting_date')::date = current_date - 1, 'FAIL 12.8: expected_next must be current_date - 1';

    -- (current_date - 10 days) => current
    UPDATE public.household_meetings SET meeting_date = current_date - 10 WHERE id = v_cad_mtg_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'current', format('FAIL 12.8b: expected current for monthly 10d, got %s', v_cad_res->>'meeting_operational_status');

    -- 12.9 quarterly: proper +3 month arithmetic
    UPDATE public.households SET meeting_frequency = 'quarterly' WHERE id = v_household_id;
    -- (current_date - 3 months - 1 day) => overdue
    UPDATE public.household_meetings SET meeting_date = (current_date - interval '3 months' - interval '1 day')::date WHERE id = v_cad_mtg_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'overdue', format('FAIL 12.9: expected overdue for quarterly, got %s', v_cad_res->>'meeting_operational_status');
    ASSERT (v_cad_res->>'expected_next_meeting_date')::date = current_date - 1, 'FAIL 12.9: expected_next must be current_date - 1';

    -- (current_date - 1 month) => current
    UPDATE public.household_meetings SET meeting_date = (current_date - interval '1 month')::date WHERE id = v_cad_mtg_id;
    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'current', format('FAIL 12.9b: expected current for quarterly 1mo, got %s', v_cad_res->>'meeting_operational_status');

    -- 12.10 future scheduled meeting takes appropriate precedence
    -- Set to weekly, completed 20 days ago (would be overdue)
    UPDATE public.households SET meeting_frequency = 'weekly' WHERE id = v_household_id;
    UPDATE public.household_meetings SET meeting_date = current_date - 20 WHERE id = v_cad_mtg_id;
    -- Insert future scheduled meeting
    INSERT INTO public.household_meetings (
      organization_id, household_node_id, meeting_date, meeting_status, meeting_type
    ) VALUES (
      v_org_id, v_household_id, current_date + 4, 'scheduled', 'regular_household'
    ) RETURNING id INTO v_cad_sch_id;

    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'scheduled', format('FAIL 12.10: expected scheduled precedence, got %s', v_cad_res->>'meeting_operational_status');
    ASSERT (v_cad_res->>'next_scheduled_meeting_date')::date = current_date + 4, 'FAIL 12.10: next_scheduled must match';

    -- 12.11 attendance-pending takes appropriate precedence
    -- Remove attendance for the completed meeting
    DELETE FROM public.household_meeting_attendance WHERE household_meeting_id = v_cad_mtg_id;
    UPDATE public.household_meetings SET attendance_recorded_at = null WHERE id = v_cad_mtg_id;

    v_cad_res := public.get_household_meeting_cadence(v_org_id, v_household_id);
    ASSERT v_cad_res->>'meeting_operational_status' = 'attendance_pending', format('FAIL 12.11: expected attendance_pending precedence, got %s', v_cad_res->>'meeting_operational_status');

    -- 12.12 get_household_meeting_history returns cadence fields
    v_history_res := public.get_household_meeting_history(v_org_id, v_household_id);
    ASSERT v_history_res ? 'cadence', 'FAIL 12.12: history must include cadence object';
    ASSERT v_history_res ? 'meeting_operational_status', 'FAIL 12.12: history must include meeting_operational_status';
    ASSERT v_history_res->>'meeting_operational_status' = 'attendance_pending', 'FAIL 12.12: history status must match';

    -- 12.13 get_pastoral_operations_dashboard reflects real cadence
    DECLARE
      v_dash_res jsonb;
      v_ops_summary jsonb;
    BEGIN
      v_dash_res := public.get_pastoral_operations_dashboard(v_org_id);
      ASSERT v_dash_res ? 'meeting_operations_summary', 'FAIL 12.13: dashboard must include meeting_operations_summary';
      v_ops_summary := v_dash_res->'meeting_operations_summary';
      ASSERT (v_ops_summary->>'attendance_pending')::integer >= 1, 'FAIL 12.13: attendance_pending count must be >= 1';
      ASSERT (v_ops_summary->>'upcoming_meetings')::integer >= 1, 'FAIL 12.13: upcoming_meetings count must be >= 1';
    END;

  END;

  RAISE NOTICE 'PART 12 PASSED.';

  RAISE NOTICE '===== Phase 6B-8 security tests: ALL 12 PARTS PASSED =====';

END;
$$;

ROLLBACK;

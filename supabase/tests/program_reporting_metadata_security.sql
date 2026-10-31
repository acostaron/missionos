-- =============================================================================
-- Test Suite: Pass 9.48 — Program Reporting Metadata & Readiness
-- All mutations executed within a rolled-back transaction.
-- =============================================================================

begin;

create temp table test_results (test_name text, status text, details text);
grant all on test_results to public, authenticated, anon;

do $$
declare
  v_org_id             uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_admin_profile      uuid := '821fb09c-8396-4549-b120-5674f3cc566a'; -- Ron Acosta (org admin)
  v_member_profile     uuid := 'f614188a-51bf-4aea-9fbd-de6f1f49f863'; -- Alan Ybay (non-admin)
  v_fake_org_id        uuid := '11111111-2222-3333-4444-555555555555';

  v_res                jsonb;
  v_run_id_a           uuid;
  v_run_id_b           uuid;
  v_session_event_id   uuid;
  v_part_id            uuid;
  v_read_res           jsonb;
  v_list_res           jsonb;
  v_quarterly_res      jsonb;
  v_caught             boolean;
  v_long_text          text;
  v_db_include         boolean;
  v_db_priority        text;
  v_db_highlight       text;
  v_rows_affected      integer;
begin
  -- Set context to Organization Administrator
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ---------------------------------------------------------------------------
  -- Test A: Authorized manager creates Program with default reporting metadata
  -- ---------------------------------------------------------------------------
  v_res := public.create_program_run(
    p_organization_id => v_org_id,
    p_program_code => 'youth_camp',
    p_title => 'Test Youth Camp Defaults 2026',
    p_session_count => 1,
    p_chapter_code => null,
    p_section_codes => array['sec_youth']::text[],
    p_description => 'Test youth camp with default reporting fields'
  );
  v_run_id_a := (v_res->'run'->>'id')::uuid;

  if (v_res->'run'->>'include_in_quarterly_report')::boolean <> false then
    raise exception 'Test A failed: expected include_in_quarterly_report false, got %', v_res->'run'->>'include_in_quarterly_report';
  end if;
  if v_res->'run'->>'report_priority' <> 'routine' then
    raise exception 'Test A failed: expected report_priority routine, got %', v_res->'run'->>'report_priority';
  end if;
  if v_res->'run'->>'report_highlight' is not null then
    raise exception 'Test A failed: report_highlight should be null';
  end if;

  insert into test_results values ('Test A', 'PASSED', 'Program run created with default reporting metadata');

  -- ---------------------------------------------------------------------------
  -- Test B: Authorized manager creates reportable Ministry Activity
  -- ---------------------------------------------------------------------------
  v_res := public.create_program_run(
    p_organization_id => v_org_id,
    p_program_code => 'cls',
    p_title => 'NYC Fall CLS 2026',
    p_session_count => 6,
    p_chapter_code => 'nyc',
    p_section_codes => array['sec_couples']::text[],
    p_description => 'Christian Life Seminar for NYC Couples',
    p_include_in_quarterly_report => true,
    p_report_priority => 'ministry_activity',
    p_report_highlight => 'Initial CLS session batch with strong attendance'
  );
  v_run_id_b := (v_res->'run'->>'id')::uuid;

  if (v_res->'run'->>'include_in_quarterly_report')::boolean <> true then
    raise exception 'Test B failed: expected include_in_quarterly_report true';
  end if;
  if v_res->'run'->>'report_priority' <> 'ministry_activity' then
    raise exception 'Test B failed: expected report_priority ministry_activity, got %', v_res->'run'->>'report_priority';
  end if;
  if v_res->'run'->>'report_highlight' <> 'Initial CLS session batch with strong attendance' then
    raise exception 'Test B failed: unexpected report_highlight %', v_res->'run'->>'report_highlight';
  end if;

  insert into test_results values ('Test B', 'PASSED', 'Reportable Ministry Activity Program created successfully');

  -- ---------------------------------------------------------------------------
  -- Test C: Authorized manager updates to Major Highlight
  -- ---------------------------------------------------------------------------
  v_res := public.update_program_run(
    p_organization_id => v_org_id,
    p_run_id => v_run_id_b,
    p_title => 'NYC Fall CLS 2026 - Major Edition',
    p_description => 'Updated description',
    p_include_in_quarterly_report => true,
    p_report_priority => 'major_highlight',
    p_report_highlight => 'Major ministry highlight: 100% completion of foundational courses'
  );

  if (v_res->'run'->>'include_in_quarterly_report')::boolean <> true then
    raise exception 'Test C failed: expected include_in_quarterly_report true';
  end if;
  if v_res->'run'->>'report_priority' <> 'major_highlight' then
    raise exception 'Test C failed: expected report_priority major_highlight, got %', v_res->'run'->>'report_priority';
  end if;
  if v_res->'run'->>'report_highlight' <> 'Major ministry highlight: 100% completion of foundational courses' then
    raise exception 'Test C failed: unexpected report_highlight %', v_res->'run'->>'report_highlight';
  end if;

  insert into test_results values ('Test C', 'PASSED', 'Program updated to Major Highlight successfully');

  -- ---------------------------------------------------------------------------
  -- Test D: Reporting defaults persist correctly
  -- ---------------------------------------------------------------------------
  v_res := public.get_program_run(v_org_id, v_run_id_a);

  if (v_res->'run'->>'include_in_quarterly_report')::boolean <> false
     or v_res->'run'->>'report_priority' <> 'routine'
     or v_res->'run'->>'report_highlight' is not null then
    raise exception 'Test D failed: values do not match defaults (% % %)',
      v_res->'run'->>'include_in_quarterly_report',
      v_res->'run'->>'report_priority',
      v_res->'run'->>'report_highlight';
  end if;

  insert into test_results values ('Test D', 'PASSED', 'Reporting defaults verified via manager RPC');

  -- ---------------------------------------------------------------------------
  -- Test E: report_highlight max length enforced (2000 chars)
  -- ---------------------------------------------------------------------------
  v_long_text := repeat('A', 2005);
  v_caught := false;
  begin
    perform public.update_program_run(
      p_organization_id => v_org_id,
      p_run_id => v_run_id_b,
      p_title => 'NYC Fall CLS 2026 - Major Edition',
      p_report_highlight => v_long_text
    );
  exception when sqlstate '22023' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test E failed: overlength report_highlight was not rejected';
  end if;

  insert into test_results values ('Test E', 'PASSED', 'report_highlight max length (2000) properly enforced with 22023');

  -- ---------------------------------------------------------------------------
  -- Test F: Ordinary member cannot write reporting metadata
  -- ---------------------------------------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_member_profile, 'role', 'authenticated')::text, true);

  v_caught := false;
  begin
    perform public.create_program_run(
      p_organization_id => v_org_id,
      p_program_code => 'youth_camp',
      p_title => 'Unauthorized Member Camp',
      p_section_codes => array['sec_youth']::text[],
      p_include_in_quarterly_report => true
    );
  exception when sqlstate '42501' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test F (create) failed: ordinary member create was not rejected';
  end if;

  v_caught := false;
  begin
    perform public.update_program_run(
      p_organization_id => v_org_id,
      p_run_id => v_run_id_a,
      p_title => 'Hacked Program Title',
      p_include_in_quarterly_report => true
    );
  exception when sqlstate '42501' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test F (update) failed: ordinary member update was not rejected';
  end if;

  insert into test_results values ('Test F', 'PASSED', 'Ordinary member write rejected with 42501');

  -- ---------------------------------------------------------------------------
  -- Test G: Anon cannot write
  -- ---------------------------------------------------------------------------
  set local role anon;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);

  v_caught := false;
  begin
    perform public.create_program_run(
      p_organization_id => v_org_id,
      p_program_code => 'youth_camp',
      p_title => 'Anon Camp',
      p_section_codes => array['sec_youth']::text[]
    );
  exception when sqlstate '28000' or sqlstate '42501' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test G failed: anon write was not rejected';
  end if;

  insert into test_results values ('Test G', 'PASSED', 'Anon write rejected');

  -- ---------------------------------------------------------------------------
  -- Test H: Cross-org write denied
  -- ---------------------------------------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  v_caught := false;
  begin
    perform public.create_program_run(
      p_organization_id => v_fake_org_id,
      p_program_code => 'youth_camp',
      p_title => 'Cross-Org Camp',
      p_section_codes => array['sec_youth']::text[]
    );
  exception when sqlstate '42501' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test H failed: cross-org write was not rejected';
  end if;

  insert into test_results values ('Test H', 'PASSED', 'Cross-org write denied with 42501');

  -- ---------------------------------------------------------------------------
  -- Test I: Direct table writes remain denied
  -- ---------------------------------------------------------------------------
  v_caught := false;
  begin
    update public.program_runs
    set include_in_quarterly_report = true
    where id = v_run_id_a;
    get diagnostics v_rows_affected = row_count;
    if v_rows_affected = 0 then
      v_caught := true; -- RLS blocked row modification
    end if;
  exception when sqlstate '42501' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test I failed: direct table write was not blocked by RLS';
  end if;

  insert into test_results values ('Test I', 'PASSED', 'Direct table writes properly blocked by RLS (0 rows affected or 42501)');

  -- ---------------------------------------------------------------------------
  -- Test J: Manager read returns unmasked reporting metadata
  -- ---------------------------------------------------------------------------
  -- Update Program A with reportable metadata as Admin
  perform public.update_program_run(
    p_organization_id => v_org_id,
    p_run_id => v_run_id_a,
    p_title => 'Test Youth Camp Defaults 2026',
    p_include_in_quarterly_report => true,
    p_report_priority => 'ministry_activity',
    p_report_highlight => 'Youth Camp spiritual renewal outcome'
  );

  v_read_res := public.get_program_run(v_org_id, v_run_id_a);
  if (v_read_res->'run'->>'include_in_quarterly_report')::boolean <> true then
    raise exception 'Test J failed: manager read should see include_in_quarterly_report true';
  end if;
  if v_read_res->'run'->>'report_priority' <> 'ministry_activity' then
    raise exception 'Test J failed: manager read should see ministry_activity';
  end if;
  if v_read_res->'run'->>'report_highlight' is null then
    raise exception 'Test J failed: manager read should see unmasked report_highlight';
  end if;

  insert into test_results values ('Test J', 'PASSED', 'Manager read returns full unmasked reporting metadata');

  -- ---------------------------------------------------------------------------
  -- Test K: Ordinary participant/non-manager read masks/omits reporting metadata
  -- ---------------------------------------------------------------------------
  -- Alan Ybay is Chapter Servant of NYC, NOT manager of Youth Camp (sec_youth).
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_member_profile, 'role', 'authenticated')::text, true);

  v_read_res := public.get_program_run(v_org_id, v_run_id_a);
  if v_read_res->'run'->>'include_in_quarterly_report' is not null then
    raise exception 'Test K (detail) failed: non-manager received unmasked include_in_quarterly_report %', v_read_res->'run'->>'include_in_quarterly_report';
  end if;
  if v_read_res->'run'->>'report_priority' is not null then
    raise exception 'Test K (detail) failed: non-manager received unmasked report_priority %', v_read_res->'run'->>'report_priority';
  end if;
  if v_read_res->'run'->>'report_highlight' is not null then
    raise exception 'Test K (detail) failed: non-manager received unmasked report_highlight %', v_read_res->'run'->>'report_highlight';
  end if;

  v_list_res := public.list_program_runs(v_org_id, true);
  if exists (
    select 1
    from jsonb_array_elements(v_list_res->'runs') r
    where (r->>'id')::uuid = v_run_id_a
      and (r->>'include_in_quarterly_report' is not null
           or r->>'report_priority' is not null
           or r->>'report_highlight' is not null)
  ) then
    raise exception 'Test K (list) failed: non-manager received unmasked reporting fields in list_program_runs';
  end if;

  -- Pure member without events.view denied from reading program runs
  perform set_config('request.jwt.claims', json_build_object('sub', '0c7cf29f-6185-44eb-8b64-08ab783d7e06'::uuid, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin
    perform public.get_program_run(v_org_id, v_run_id_a);
  exception when sqlstate '42501' then
    v_caught := true;
  end;
  if not v_caught then
    raise exception 'Test K (unauthorized read) failed: pure member was able to call get_program_run';
  end if;

  insert into test_results values ('Test K', 'PASSED', 'Ordinary member read properly masks internal reporting metadata to NULL');

  -- ---------------------------------------------------------------------------
  -- Test L: Reporting-readiness query returns only included Programs
  -- ---------------------------------------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- Ensure Program A has include_in_quarterly_report = false
  perform public.update_program_run(
    p_organization_id => v_org_id,
    p_run_id => v_run_id_a,
    p_title => 'Test Youth Camp Defaults 2026',
    p_include_in_quarterly_report => false
  );

  v_quarterly_res := public.list_program_runs(
    p_organization_id => v_org_id,
    p_include_closed => true,
    p_from => null,
    p_to => null,
    p_quarterly_only => true
  );

  if not exists (
    select 1
    from jsonb_array_elements(v_quarterly_res->'runs') r
    where (r->>'id')::uuid = v_run_id_b
  ) then
    raise exception 'Test L failed: reportable program B was not returned in quarterly query';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_quarterly_res->'runs') r
    where (r->>'id')::uuid = v_run_id_a
  ) then
    raise exception 'Test L failed: non-reportable program A was returned in quarterly query';
  end if;

  insert into test_results values ('Test L', 'PASSED', 'Reporting-readiness query returned only reportable Programs');

  -- ---------------------------------------------------------------------------
  -- Test M: Participant counts reconcile with authoritative participant records
  -- ---------------------------------------------------------------------------
  v_res := public.add_program_participant(
    p_organization_id => v_org_id,
    p_run_id => v_run_id_b,
    p_first_name => 'Maria',
    p_last_name => 'Santos',
    p_email => 'maria.santos@example.com'
  );
  v_part_id := (v_res->>'participant_id')::uuid;

  v_read_res := public.get_program_run(v_org_id, v_run_id_b);
  if (v_read_res->'run'->>'participant_count')::int <> 1 then
    raise exception 'Test M failed: expected participant_count 1, got %', v_read_res->'run'->>'participant_count';
  end if;

  insert into test_results values ('Test M', 'PASSED', 'Participant count reconciles with authoritative participant records');

  -- ---------------------------------------------------------------------------
  -- Test N: Completion/graduation count is NULL (not 0, not fabricated)
  -- ---------------------------------------------------------------------------
  if v_read_res->'run'->>'graduate_count' is not null then
    raise exception 'Test N failed: graduate_count should be null where no authoritative completion state exists, got %', v_read_res->'run'->>'graduate_count';
  end if;

  insert into test_results values ('Test N', 'PASSED', 'graduate_count is strictly NULL where no authoritative completion state exists');

  -- ---------------------------------------------------------------------------
  -- Test O: Attendance recording works and 100% attendance does NOT fabricate graduation
  -- ---------------------------------------------------------------------------
  -- Add a single session for Program A (youth camp, session_count = 1)
  v_res := public.add_program_session(
    p_organization_id => v_org_id,
    p_run_id => v_run_id_a,
    p_session_number => 1,
    p_starts_at => now() - interval '2 hours',
    p_ends_at => now() - interval '1 hour',
    p_location_text => 'St. Patrick Camp Grounds'
  );
  v_session_event_id := (v_res->'event'->>'id')::uuid;

  -- Add participant to Program A
  v_res := public.add_program_participant(
    p_organization_id => v_org_id,
    p_run_id => v_run_id_a,
    p_first_name => 'Joseph',
    p_last_name => 'Reyes',
    p_email => 'joseph.reyes@example.com'
  );
  v_part_id := (v_res->>'participant_id')::uuid;

  -- Record attendance for session 1 (100% attendance: 1 of 1 sessions)
  perform public.set_program_participant_attendance(
    p_organization_id => v_org_id,
    p_event_id => v_session_event_id,
    p_participant_ids => array[v_part_id],
    p_present => true
  );

  -- Inspect Program A detail
  v_read_res := public.get_program_run(v_org_id, v_run_id_a);

  -- 1. Attendance metrics preserved:
  if (v_read_res->'participants'->0->>'attended_count')::int <> 1 then
    raise exception 'Test O failed: attended_count should be 1';
  end if;
  if (v_read_res->'participants'->0->'attended_sessions') <> '[1]'::jsonb then
    raise exception 'Test O failed: attended_sessions should be [1]';
  end if;

  -- 2. Participant does NOT automatically become a graduate despite 100% attendance:
  if v_read_res->'participants'->0->>'graduated' is not null then
    raise exception 'Test O failed: participant graduated should be null (not inferred from attendance)';
  end if;

  -- 3. Run graduate_count remains NULL:
  if v_read_res->'run'->>'graduate_count' is not null then
    raise exception 'Test O failed: run graduate_count should be null';
  end if;

  insert into test_results values ('Test O', 'PASSED', 'Attendance metrics preserved; 100% attendance does NOT infer graduation; graduated remains NULL');

  -- ---------------------------------------------------------------------------
  -- Test P: Single-session camp does not receive graduation semantics
  -- ---------------------------------------------------------------------------
  if (v_read_res->'run'->>'session_count')::int <> 1
     or v_read_res->'run'->>'graduate_count' is not null then
    raise exception 'Test P failed: camp with 1 session should have graduate_count as null';
  end if;

  insert into test_results values ('Test P', 'PASSED', 'Single-session camp does not receive artificial graduation semantics');

end;
$$;

select * from test_results order by test_name;

rollback;

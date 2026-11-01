-- =============================================================================
-- Test Suite: Pass 9.51 - CLS / LCS / Formation reporting integration
-- All mutations roll back. No Storage binaries are written.
-- =============================================================================

begin;

create temp table test_results (test_name text, status text, details text);
grant all on test_results to public, authenticated, anon;

do $$
declare
  v_org_id          uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_admin_profile   uuid := '821fb09c-8396-4549-b120-5674f3cc566a'; -- org admin (reports.census.view)
  v_pure_profile    uuid := '0c7cf29f-6185-44eb-8b64-08ab783d7e06'; -- ordinary member
  v_fake_org_id     uuid := '11111111-2222-3333-4444-555555555555';

  v_m1 uuid; v_m2 uuid; v_m3 uuid;
  v_talk_id uuid;
  v_run_id uuid; v_run_out_id uuid; v_run_cancel_id uuid; v_run_noinc_id uuid; v_camp_id uuid;
  v_s1 uuid; v_s2 uuid;
  v_p1 uuid; v_p2 uuid; v_p3 uuid;
  v_fevent uuid; v_fevent_cancel uuid; v_assembly uuid;
  v_res jsonb; v_items jsonb; v_row jsonb;
  v_caught boolean;
  v_path text;
  v_cnt integer;
begin
  select id into v_talk_id from public.formation_talks where is_active order by sequence_order limit 1;
  select jsonb_agg(q.id) into strict v_items from (select m.id from public.members m
    where m.organization_id = v_org_id order by m.member_number limit 3) q;
  v_m1 := (v_items->>0)::uuid; v_m2 := (v_items->>1)::uuid; v_m3 := (v_items->>2)::uuid;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ---------------- Fixtures ----------------
  -- Included CLS, 2 sessions in Q4 2026
  v_res := public.create_program_run(p_organization_id => v_org_id, p_program_code => 'cls',
    p_title => 'Pass 9.51 Test CLS', p_session_count => 6, p_chapter_code => 'alb', p_section_codes => array['sec_couples']::text[],
    p_include_in_quarterly_report => true, p_report_priority => 'major_highlight',
    p_report_highlight => 'Twelve couples began the CLS journey.');
  v_run_id := (v_res->'run'->>'id')::uuid;
  v_res := public.add_program_session(p_organization_id => v_org_id, p_run_id => v_run_id, p_session_number => 1,
    p_starts_at => '2026-09-05 09:00:00-04', p_location_text => 'St. Mary Parish Hall');
  v_s1 := (v_res->'event'->>'id')::uuid;
  v_res := public.add_program_session(p_organization_id => v_org_id, p_run_id => v_run_id, p_session_number => 2,
    p_starts_at => '2026-09-12 09:00:00-04', p_location_text => 'Other Hall');
  v_s2 := (v_res->'event'->>'id')::uuid;

  -- Participants: 3 registered, then 1 withdrawn
  v_p1 := (public.add_program_participant(v_org_id, v_run_id, v_m1, null, null, null, null, null, null)->'participant'->>'id')::uuid;
  v_p2 := (public.add_program_participant(v_org_id, v_run_id, null, 'Guest', 'Alpha', '555-0100', 'guest@example.com', null, 'private note')->'participant'->>'id')::uuid;
  v_p3 := (public.add_program_participant(v_org_id, v_run_id, null, 'Guest', 'Beta', null, null, null, null)->'participant'->>'id')::uuid;
  if v_p1 is null or v_p2 is null or v_p3 is null then
    reset role;
    select id into v_p1 from public.program_participants where program_run_id = v_run_id and member_id = v_m1;
    select id into v_p2 from public.program_participants where program_run_id = v_run_id and last_name = 'Alpha';
    select id into v_p3 from public.program_participants where program_run_id = v_run_id and last_name = 'Beta';
    set local role authenticated;
  end if;

  -- Attendance: p1 attends both sessions (100%), p2 attends session 1, withdrawn p3 attends session 1
  perform public.set_program_participant_attendance(v_org_id, v_s1, array[v_p1, v_p2, v_p3], true);
  perform public.set_program_participant_attendance(v_org_id, v_s2, array[v_p1], true);
  -- withdraw p3 after attendance was recorded
  perform public.set_program_participant_status(v_org_id, v_p3, 'withdrawn');

  -- Speakers / service team: program-level + session-level
  perform public.save_activity_speaker(p_organization_id => v_org_id, p_program_run_id => v_run_id,
    p_external_name => 'Fr. Program Speaker', p_speaker_role => 'speaker', p_topic_title => 'Opening');
  perform public.save_activity_speaker(p_organization_id => v_org_id, p_event_id => v_s1,
    p_member_id => v_m2, p_speaker_role => 'speaker', p_topic_title => 'God''s Love');
  perform public.save_activity_service_assignment(p_organization_id => v_org_id, p_program_run_id => v_run_id,
    p_member_id => v_m3, p_role_code => 'facilitator');
  perform public.save_activity_service_assignment(p_organization_id => v_org_id, p_event_id => v_s2,
    p_external_name => 'Volunteer Greeter', p_role_code => 'hospitality');

  -- Photos: program-level selected, session selected, session not selected (metadata rows only)
  foreach v_path in array array[
    v_org_id::text || '/programs/' || v_run_id::text || '/' || gen_random_uuid()::text || '.jpg',
    v_org_id::text || '/events/' || v_s1::text || '/' || gen_random_uuid()::text || '.jpg',
    v_org_id::text || '/events/' || v_s2::text || '/' || gen_random_uuid()::text || '.jpg'] loop
    reset role;
    insert into public.activity_photos (id, organization_id, event_id, program_run_id, storage_bucket, storage_path,
      mime_type, file_size_bytes, caption, include_in_quarterly_report, uploaded_by_profile_id)
    values (split_part(split_part(v_path, '/', 4), '.', 1)::uuid, v_org_id,
      case when v_path like '%/events/%' then split_part(v_path, '/', 3)::uuid end,
      case when v_path like '%/programs/%' then v_run_id end,
      'activity-photos', v_path, 'image/jpeg', 1000, 'Test photo',
      v_path not like '%/events/' || v_s2::text || '/%', v_admin_profile);
    set local role authenticated;
  end loop;

  -- Out-of-period CLS (Q3), cancelled CLS, non-included CLS, included youth camp (not CLS)
  v_run_out_id := (public.create_program_run(p_organization_id => v_org_id, p_program_code => 'cls',
    p_title => 'Pass 9.51 Q2 CLS', p_session_count => 6, p_chapter_code => 'alb', p_section_codes => array['sec_couples']::text[], p_include_in_quarterly_report => true)->'run'->>'id')::uuid;
  perform public.add_program_session(p_organization_id => v_org_id, p_run_id => v_run_out_id, p_session_number => 1,
    p_starts_at => '2026-05-02 09:00:00-04');
  v_run_cancel_id := (public.create_program_run(p_organization_id => v_org_id, p_program_code => 'cls',
    p_title => 'Pass 9.51 Cancelled CLS', p_session_count => 6, p_chapter_code => 'alb', p_section_codes => array['sec_couples']::text[], p_include_in_quarterly_report => true)->'run'->>'id')::uuid;
  perform public.add_program_session(p_organization_id => v_org_id, p_run_id => v_run_cancel_id, p_session_number => 1,
    p_starts_at => '2026-09-19 09:00:00-04');
  perform public.set_program_run_status(v_org_id, v_run_cancel_id, 'cancelled', 'Test cancel');
  v_run_noinc_id := (public.create_program_run(p_organization_id => v_org_id, p_program_code => 'cls',
    p_title => 'Pass 9.51 Not Included CLS', p_session_count => 6, p_chapter_code => 'alb', p_section_codes => array['sec_couples']::text[])->'run'->>'id')::uuid;
  perform public.add_program_session(p_organization_id => v_org_id, p_run_id => v_run_noinc_id, p_session_number => 1,
    p_starts_at => '2026-09-20 09:00:00-04');
  v_camp_id := (public.create_program_run(p_organization_id => v_org_id, p_program_code => 'youth_camp',
    p_title => 'Pass 9.51 Camp', p_session_count => 1, p_section_codes => array['sec_youth']::text[], p_include_in_quarterly_report => true)->'run'->>'id')::uuid;
  perform public.add_program_session(p_organization_id => v_org_id, p_run_id => v_camp_id, p_session_number => 1,
    p_starts_at => '2026-09-21 09:00:00-04');

  -- Formal formation Event (conducted), cancelled formation Event, included non-formation assembly
  v_fevent := (public.create_event(p_organization_id => v_org_id, p_event_type => 'formation_talk', p_title => 'Pass 9.51 Formation Talk',
    p_starts_at => '2026-09-26 19:00:00-04', p_location_text => 'Chapter Center', p_formation_talk_id => v_talk_id,
    p_include_in_quarterly_report => true, p_report_priority => 'ministry_activity')->'event'->>'id')::uuid;
  perform public.set_event_attendance(v_org_id, v_fevent, array[v_m1, v_m2], true, 'tick');
  perform public.save_activity_speaker(p_organization_id => v_org_id, p_event_id => v_fevent,
    p_external_name => 'Formation Facilitator', p_speaker_role => 'speaker');
  v_fevent_cancel := (public.create_event(p_organization_id => v_org_id, p_event_type => 'formation_talk', p_title => 'Pass 9.51 Cancelled Formation',
    p_starts_at => '2026-09-27 19:00:00-04', p_formation_talk_id => v_talk_id, p_include_in_quarterly_report => true)->'event'->>'id')::uuid;
  perform public.set_event_status(v_org_id, v_fevent_cancel, 'cancelled', 'Test cancel');
  v_assembly := (public.create_event(p_organization_id => v_org_id, p_event_type => 'assembly', p_title => 'Pass 9.51 Assembly',
    p_starts_at => '2026-09-28 19:00:00-04', p_include_in_quarterly_report => true)->'event'->>'id')::uuid;

  -- ---------------- Read ----------------
  v_res := public.list_quarterly_formation_reporting_items(v_org_id, '2026-07-01', '2026-09-30', true);
  v_items := v_res->'items';
  select x into v_row from jsonb_array_elements(v_items) x where x->>'source_id' = v_run_id::text;

  -- A
  if v_row is null or v_row->>'source_kind' <> 'cls' then raise exception 'A failed: %', v_items; end if;
  insert into test_results values ('A', 'PASSED', 'Reporting user reads included CLS as source_kind=cls');

  -- B
  if (v_row->>'participant_count')::int <> 2 then raise exception 'B failed: %', v_row->>'participant_count'; end if;
  insert into test_results values ('B', 'PASSED', 'participant_count = 2 registered (withdrawn excluded; team/speakers not counted)');

  -- C
  if (v_row->'attendance_summary'->>'sessions_scheduled')::int <> 2
     or (v_row->'attendance_summary'->>'attendance_instances')::int <> 3
     or (v_row->'attendance_summary'->>'participants_with_attendance')::int <> 2
     or (v_row->>'attendance_count')::int <> 2 then
    raise exception 'C failed: %', v_row->'attendance_summary';
  end if;
  insert into test_results values ('C', 'PASSED', 'sessions=2, instances=3, participants_with_attendance=2 (withdrawn excluded)');

  -- D
  if v_row->'completion_count' <> 'null'::jsonb or (v_row->>'completion_data_available')::boolean then
    raise exception 'D failed'; end if;
  insert into test_results values ('D', 'PASSED', 'completion_count NULL, completion_data_available=false');

  -- E (p1 attended 100% of sessions)
  if v_row->'completion_count' <> 'null'::jsonb then raise exception 'E failed'; end if;
  insert into test_results values ('E', 'PASSED', '100% attendance participant does not produce a graduate/completion count');

  -- F
  if v_row->>'location' <> 'St. Mary Parish Hall' then raise exception 'F failed: %', v_row->>'location'; end if;
  insert into test_results values ('F', 'PASSED', 'Venue = first session location by session number');

  -- G
  if jsonb_array_length(v_row->'speakers') <> 2 or jsonb_array_length(v_row->'service_team') <> 2 then
    raise exception 'G failed: % / %', v_row->'speakers', v_row->'service_team'; end if;
  insert into test_results values ('G', 'PASSED', 'Program + session speakers (2) and service team (2) aggregated from Pass 9.49 tables');

  -- H
  if jsonb_array_length(v_row->'selected_photos') <> 2 then raise exception 'H failed: %', v_row->'selected_photos'; end if;
  insert into test_results values ('H', 'PASSED', 'Only selected Program + session photos (2 of 3) returned from Pass 9.50 table');

  -- I / J
  -- Pass 9.51 correction (128000): LCS is now the explicit program type 'lcs'.
  if not (v_res->>'lcs_source_available')::boolean
     or exists (select 1 from jsonb_array_elements(v_items) x where x->>'source_kind' = 'lcs') then
    raise exception 'I/J failed'; end if;
  insert into test_results values ('I', 'PASSED', 'LCS source = explicit program_code lcs; no LCS fixture here so zero LCS rows (no title inference)');
  insert into test_results values ('J', 'PASSED', 'No LCS participant count fabricated for non-LCS activities');
  -- K
  select x into v_row from jsonb_array_elements(v_items) x where x->>'source_id' = v_fevent::text;
  if v_row is null or v_row->>'source_kind' <> 'formation' or v_row->>'formation_talk_title' is null
     or (v_row->>'attendance_count')::int <> 2 or v_row->'participant_count' <> 'null'::jsonb
     or v_row->'completion_count' <> 'null'::jsonb or v_row->>'location' <> 'Chapter Center'
     or jsonb_array_length(v_row->'speakers') <> 1 then
    raise exception 'K failed: %', v_row; end if;
  insert into test_results values ('K', 'PASSED', 'Conducted formation Event returned with curriculum labels, attendance=2, participants/completion NULL');

  -- L
  if (select count(*) from jsonb_array_elements(v_items) x where x->>'source_kind' = 'formation') <> 1 then
    raise exception 'L failed'; end if;
  insert into test_results values ('L', 'PASSED', 'Curriculum rows (formation_programs/talks) are not reported as conducted activities');

  -- M
  if exists (select 1 from jsonb_array_elements(v_items) x where x->>'source_table' not in ('program_runs', 'events')) then
    raise exception 'M failed'; end if;
  insert into test_results values ('M', 'PASSED', 'Member formation progress rows never appear as ministry activities');

  -- N
  if exists (select 1 from jsonb_array_elements(v_items) x where x->>'source_id' = v_run_out_id::text) then raise exception 'N failed (Q2 in Q3)'; end if;
  v_res := public.list_quarterly_formation_reporting_items(v_org_id, '2026-04-01', '2026-06-30', true);
  if not exists (select 1 from jsonb_array_elements(v_res->'items') x where x->>'source_id' = v_run_out_id::text)
     or exists (select 1 from jsonb_array_elements(v_res->'items') x where x->>'source_id' = v_run_id::text) then
    raise exception 'N failed (Q3)'; end if;
  insert into test_results values ('N', 'PASSED', 'Period filter by NY-local start date (Q2 vs Q3)');

  -- O
  if exists (select 1 from jsonb_array_elements(v_items) x where x->>'source_id' = v_run_noinc_id::text) then raise exception 'O failed'; end if;
  v_res := public.list_quarterly_formation_reporting_items(v_org_id, '2026-07-01', '2026-09-30', false);
  if not exists (select 1 from jsonb_array_elements(v_res->'items') x where x->>'source_id' = v_run_noinc_id::text) then
    raise exception 'O failed (preview)'; end if;
  insert into test_results values ('O', 'PASSED', 'Included-only by default; preview mode returns non-included too');

  -- U
  if exists (select 1 from jsonb_array_elements(v_res->'items') x
             where x->>'source_id' in (v_run_cancel_id::text, v_fevent_cancel::text)) then raise exception 'U failed'; end if;
  insert into test_results values ('U', 'PASSED', 'Cancelled CLS and cancelled formation Event excluded (even in preview)');

  -- T (+ non-CLS programs / non-formation events)
  if exists (select 1 from jsonb_array_elements(v_res->'items') x
             where x->>'source_id' in (v_camp_id::text, v_assembly::text)) then raise exception 'T failed'; end if;
  insert into test_results values ('T', 'PASSED', 'Household topics, camps and ordinary assemblies are not formal formation rows');

  -- V
  select x into v_row from jsonb_array_elements(v_items) x where x->>'source_id' = v_run_id::text;
  if v_row->>'report_priority' <> 'major_highlight' or v_row->>'report_highlight' <> 'Twelve couples began the CLS journey.'
     or not (v_row->>'include_in_quarterly_report')::boolean then raise exception 'V failed'; end if;
  insert into test_results values ('V', 'PASSED', 'Report priority / highlight preserved');

  -- W
  if (select count(*) from jsonb_array_elements(v_items) x where x->>'source_id' = v_run_id::text) <> 1 then raise exception 'W failed'; end if;
  insert into test_results values ('W', 'PASSED', 'One row per CLS despite multiple sessions');

  -- X
  if (select count(distinct x->>'speaker_id') from jsonb_array_elements(v_row->'speakers') x) <> jsonb_array_length(v_row->'speakers')
     or (select count(distinct x->>'assignment_id') from jsonb_array_elements(v_row->'service_team') x) <> jsonb_array_length(v_row->'service_team')
     or (select count(distinct x->>'photo_id') from jsonb_array_elements(v_row->'selected_photos') x) <> jsonb_array_length(v_row->'selected_photos') then
    raise exception 'X failed'; end if;
  insert into test_results values ('X', 'PASSED', 'No duplicate speakers / service team / photos from aggregation');

  -- S
  if v_items::text ~* '(guest@example\.com|555-0100|private note|"email"|"phone"|"notes"|original_filename|uploaded_by|file_size)' then
    raise exception 'S failed'; end if;
  insert into test_results values ('S', 'PASSED', 'No emails, phones, notes, or photo audit fields in reporting output');

  -- R
  v_caught := false;
  begin perform public.list_quarterly_formation_reporting_items(v_fake_org_id, '2026-07-01', '2026-09-30');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'R failed'; end if;
  insert into test_results values ('R', 'PASSED', 'Cross-org read denied');

  -- P
  perform set_config('request.jwt.claims', json_build_object('sub', v_pure_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.list_quarterly_formation_reporting_items(v_org_id, '2026-07-01', '2026-09-30');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'P failed'; end if;
  insert into test_results values ('P', 'PASSED', 'Ordinary member denied organization-wide reporting read');

  -- Q
  reset role;
  set local role anon;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_caught := false;
  begin perform public.list_quarterly_formation_reporting_items(v_org_id, '2026-07-01', '2026-09-30');
  exception when insufficient_privilege or sqlstate '28000' then v_caught := true; end;
  if not v_caught then raise exception 'Q failed'; end if;
  insert into test_results values ('Q', 'PASSED', 'anon denied');
  reset role;
end;
$$;

select test_name, status, details from test_results order by test_name;

rollback;

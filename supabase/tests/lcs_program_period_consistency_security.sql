-- =============================================================================
-- Test Suite: Pass 9.51 correction — LCS Program type + Program period consistency
-- All mutations roll back. No Storage binaries are written.
-- =============================================================================

begin;

create temp table test_results (test_name text, status text, details text);
grant all on test_results to public, authenticated, anon;

do $$
declare
  v_org_id        uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_admin_profile uuid := '821fb09c-8396-4549-b120-5674f3cc566a';
  v_pure_profile  uuid := '0c7cf29f-6185-44eb-8b64-08ab783d7e06';
  v_fake_org_id   uuid := '11111111-2222-3333-4444-555555555555';

  v_m1 uuid; v_m2 uuid; v_talk_id uuid; v_ids jsonb;
  v_lcs uuid; v_lcs_s1 uuid; v_lp1 uuid; v_lp2 uuid; v_lp3 uuid;
  v_xq uuid; v_xq_s1 uuid; v_xq_s2 uuid;
  v_ev uuid; v_fev uuid;
  v_ph_lcs uuid := gen_random_uuid(); v_ph_lcs_s uuid := gen_random_uuid();
  v_ph_q3s uuid := gen_random_uuid(); v_ph_ev uuid := gen_random_uuid(); v_ph_fev uuid := gen_random_uuid();
  v_res jsonb; v_row jsonb; v_photos jsonb;
  v_caught boolean;
begin
  select id into v_talk_id from public.formation_talks where is_active order by sequence_order limit 1;
  select jsonb_agg(q.id) into v_ids from (select m.id from public.members m where m.organization_id = v_org_id order by m.member_number limit 2) q;
  v_m1 := (v_ids->>0)::uuid; v_m2 := (v_ids->>1)::uuid;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- A / B / C. LCS with no chapter, no section, 1 session (not 6/9)
  v_res := public.create_program_run(p_organization_id => v_org_id, p_program_code => 'lcs',
    p_title => 'Pass 9.51 LCS St. Joseph Parish', p_session_count => 1,
    p_include_in_quarterly_report => true, p_report_priority => 'major_highlight',
    p_report_highlight => 'Parish mission with 3 parishioners.');
  v_lcs := (v_res->'run'->>'id')::uuid;
  if v_lcs is null or v_res->'run'->>'program_code' <> 'lcs' then raise exception 'A failed: %', v_res; end if;
  insert into test_results values ('A', 'PASSED', 'Org manager created an LCS Program (program_code=lcs)');
  if v_res->'run'->>'chapter_name' is not null then raise exception 'B failed'; end if;
  insert into test_results values ('B', 'PASSED', 'LCS exists without Chapter or Section');
  if (v_res->'run'->>'session_count')::int <> 1 then raise exception 'C failed'; end if;
  insert into test_results values ('C', 'PASSED', 'LCS accepts 1 session (CLS 6/9 rule not inherited)');

  v_lcs_s1 := (public.add_program_session(p_organization_id => v_org_id, p_run_id => v_lcs, p_session_number => 1,
    p_starts_at => '2026-09-12 09:00:00-04', p_ends_at => '2026-09-12 17:00:00-04',
    p_location_text => 'St. Joseph Parish Hall')->'event'->>'id')::uuid;

  -- Participants: 1 member + 2 external parishioners; one external later withdrawn
  perform public.add_program_participant(v_org_id, v_lcs, v_m1, null, null, null, null, null, null);
  perform public.add_program_participant(v_org_id, v_lcs, null, 'Parish', 'One', '555-0111', 'p1@example.com', null, 'note');
  perform public.add_program_participant(v_org_id, v_lcs, null, 'Parish', 'Two', null, null, null, null);
  reset role;
  select id into v_lp1 from public.program_participants where program_run_id = v_lcs and member_id = v_m1;
  select id into v_lp2 from public.program_participants where program_run_id = v_lcs and last_name = 'One';
  select id into v_lp3 from public.program_participants where program_run_id = v_lcs and last_name = 'Two';
  set local role authenticated;
  perform public.set_program_participant_attendance(v_org_id, v_lcs_s1, array[v_lp1, v_lp2, v_lp3], true);
  perform public.set_program_participant_status(v_org_id, v_lp3, 'withdrawn');

  perform public.save_activity_speaker(p_organization_id => v_org_id, p_program_run_id => v_lcs,
    p_external_name => 'Fr. Parish Priest', p_speaker_role => 'speaker');
  perform public.save_activity_speaker(p_organization_id => v_org_id, p_event_id => v_lcs_s1,
    p_member_id => v_m2, p_speaker_role => 'speaker', p_topic_title => 'New Life in Christ');
  perform public.save_activity_service_assignment(p_organization_id => v_org_id, p_program_run_id => v_lcs,
    p_member_id => v_m1, p_role_code => 'coordinator');
  perform public.save_activity_service_assignment(p_organization_id => v_org_id, p_event_id => v_lcs_s1,
    p_external_name => 'Parish Volunteer', p_role_code => 'hospitality');

  -- Cross-quarter Program: starts Q2, later session in Q3
  v_xq := (public.create_program_run(p_organization_id => v_org_id, p_program_code => 'other_program',
    p_title => 'Pass 9.51 Cross-Quarter Program', p_session_count => 2, p_include_in_quarterly_report => true)->'run'->>'id')::uuid;
  v_xq_s1 := (public.add_program_session(p_organization_id => v_org_id, p_run_id => v_xq, p_session_number => 1,
    p_starts_at => '2026-06-27 09:00:00-04')->'event'->>'id')::uuid;
  v_xq_s2 := (public.add_program_session(p_organization_id => v_org_id, p_run_id => v_xq, p_session_number => 2,
    p_starts_at => '2026-07-11 09:00:00-04')->'event'->>'id')::uuid;

  -- Standalone event + formation event in Q3
  v_ev := (public.create_event(p_organization_id => v_org_id, p_event_type => 'assembly', p_title => 'Pass 9.51 Q3 Assembly',
    p_starts_at => '2026-08-15 19:00:00-04', p_include_in_quarterly_report => true)->'event'->>'id')::uuid;
  v_fev := (public.create_event(p_organization_id => v_org_id, p_event_type => 'formation_talk', p_title => 'Pass 9.51 Q3 Formation',
    p_starts_at => '2026-08-22 19:00:00-04', p_formation_talk_id => v_talk_id, p_include_in_quarterly_report => true)->'event'->>'id')::uuid;

  -- Selected photo metadata rows
  reset role;
  insert into public.activity_photos (id, organization_id, event_id, program_run_id, storage_bucket, storage_path,
    mime_type, file_size_bytes, include_in_quarterly_report, uploaded_by_profile_id) values
    (v_ph_lcs,   v_org_id, null,     v_lcs, 'activity-photos', v_org_id||'/programs/'||v_lcs||'/'||v_ph_lcs||'.jpg',     'image/jpeg', 1000, true, v_admin_profile),
    (v_ph_lcs_s, v_org_id, v_lcs_s1, null,  'activity-photos', v_org_id||'/events/'||v_lcs_s1||'/'||v_ph_lcs_s||'.jpg', 'image/jpeg', 1000, true, v_admin_profile),
    (v_ph_q3s,   v_org_id, v_xq_s2,  null,  'activity-photos', v_org_id||'/events/'||v_xq_s2||'/'||v_ph_q3s||'.jpg',    'image/jpeg', 1000, true, v_admin_profile),
    (v_ph_ev,    v_org_id, v_ev,     null,  'activity-photos', v_org_id||'/events/'||v_ev||'/'||v_ph_ev||'.jpg',         'image/jpeg', 1000, true, v_admin_profile),
    (v_ph_fev,   v_org_id, v_fev,    null,  'activity-photos', v_org_id||'/events/'||v_fev||'/'||v_ph_fev||'.jpg',       'image/jpeg', 1000, true, v_admin_profile);
  set local role authenticated;

  -- D..J. LCS reporting row (Q3)
  v_res := public.list_quarterly_formation_reporting_items(v_org_id, '2026-07-01', '2026-09-30', true);
  select x into v_row from jsonb_array_elements(v_res->'items') x where x->>'source_id' = v_lcs::text;
  if v_row is null or v_row->>'source_kind' <> 'lcs' or not (v_res->>'lcs_source_available')::boolean then raise exception 'D failed: %', v_res; end if;
  insert into test_results values ('D', 'PASSED', 'LCS reporting row source_kind=lcs (explicit program type, no title parsing)');
  if v_row->>'activity_start_date' <> '2026-09-12' or v_row->>'activity_end_date' <> '2026-09-12'
     or v_row->>'location' <> 'St. Joseph Parish Hall' then raise exception 'E failed: %', v_row; end if;
  insert into test_results values ('E', 'PASSED', 'LCS date 2026-09-12 and venue from session location');
  if (v_row->>'participant_count')::int <> 2 or not (v_row->>'participant_count_is_authoritative')::boolean
     or (v_row->'attendance_summary'->>'participants_with_attendance')::int <> 2 then raise exception 'F failed: %', v_row; end if;
  insert into test_results values ('F', 'PASSED', 'LCS participant_count=2 registered (member + external; withdrawn excluded)');
  if v_row->'completion_count' <> 'null'::jsonb or (v_row->>'completion_data_available')::boolean then raise exception 'G failed'; end if;
  insert into test_results values ('G', 'PASSED', 'LCS completion NULL / not available despite full attendance');
  if jsonb_array_length(v_row->'speakers') <> 2 then raise exception 'H failed'; end if;
  insert into test_results values ('H', 'PASSED', 'LCS Program + session speakers aggregated (2)');
  if jsonb_array_length(v_row->'service_team') <> 2 then raise exception 'I failed'; end if;
  insert into test_results values ('I', 'PASSED', 'LCS Program + session service team aggregated (2)');
  if jsonb_array_length(v_row->'selected_photos') <> 2 then raise exception 'J failed'; end if;
  insert into test_results values ('J', 'PASSED', 'LCS Program + session selected photos aggregated (2)');
  if v_res::text ~* '(p1@example\.com|555-0111)' then raise exception 'privacy failed'; end if;

  -- O. Cross-quarter Program belongs only to Q2 (formation reporting + Program list rule)
  v_photos := public.list_report_activity_photos(v_org_id, '2026-04-01', '2026-06-30');
  if not exists (select 1 from jsonb_array_elements(v_photos) x where x->>'activity_id' = v_xq::text) then raise exception 'O failed (Q2)'; end if;
  insert into test_results values ('O', 'PASSED', 'Program starting Q2 (later session Q3) is reported in Q2');

  -- P. Q3-session photo is reported with the Program in Q2
  if not exists (select 1 from jsonb_array_elements(v_photos) x where x->>'id' = v_ph_q3s::text
                 and x->>'activity_kind' = 'program' and x->>'activity_id' = v_xq::text) then raise exception 'P failed: %', v_photos; end if;
  insert into test_results values ('P', 'PASSED', 'Photo on Q3 session belongs to Q2 with its parent Program');

  -- Q. Not in Q3
  v_photos := public.list_report_activity_photos(v_org_id, '2026-07-01', '2026-09-30');
  if exists (select 1 from jsonb_array_elements(v_photos) x where x->>'activity_id' = v_xq::text or x->>'id' = v_ph_q3s::text) then raise exception 'Q failed'; end if;
  insert into test_results values ('Q', 'PASSED', 'Cross-quarter Program/photo absent from Q3');

  -- R. Standalone Event photo uses Event date
  if not exists (select 1 from jsonb_array_elements(v_photos) x where x->>'id' = v_ph_ev::text and x->>'activity_kind' = 'event') then raise exception 'R failed'; end if;
  insert into test_results values ('R', 'PASSED', 'Standalone Event photo in Q3 by Event date');

  -- S. Formation Event photo uses Event date
  if not exists (select 1 from jsonb_array_elements(v_photos) x where x->>'id' = v_ph_fev::text and x->>'activity_type' = 'formation_talk') then raise exception 'S failed'; end if;
  insert into test_results values ('S', 'PASSED', 'Formation Event photo in Q3 by Event date');

  -- M. CLS rules unchanged
  v_caught := false;
  begin perform public.create_program_run(p_organization_id => v_org_id, p_program_code => 'cls', p_title => 'No chapter CLS',
          p_session_count => 6, p_section_codes => array['sec_couples']::text[]);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'M failed (chapter)'; end if;
  v_caught := false;
  begin perform public.create_program_run(p_organization_id => v_org_id, p_program_code => 'cls', p_title => 'Bad session CLS',
          p_session_count => 3, p_chapter_code => 'alb', p_section_codes => array['sec_couples']::text[]);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'M failed (sessions)'; end if;
  perform public.create_program_run(p_organization_id => v_org_id, p_program_code => 'cls', p_title => 'Valid CLS',
          p_session_count => 9, p_chapter_code => 'alb', p_section_codes => array['sec_couples']::text[]);
  insert into test_results values ('M', 'PASSED', 'CLS still requires chapter + 6/9 sessions; valid CLS still created');

  -- N. Camp rules unchanged
  v_caught := false;
  begin perform public.create_program_run(p_organization_id => v_org_id, p_program_code => 'youth_camp', p_title => 'Bad Camp',
          p_section_codes => array['sec_couples']::text[]);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'N failed'; end if;
  perform public.create_program_run(p_organization_id => v_org_id, p_program_code => 'youth_camp', p_title => 'Good Camp',
          p_section_codes => array['sec_youth']::text[]);
  insert into test_results values ('N', 'PASSED', 'Youth Camp still requires one Youth section');

  -- L. Cross-org
  v_caught := false;
  begin perform public.list_quarterly_formation_reporting_items(v_fake_org_id, '2026-07-01', '2026-09-30');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'L failed'; end if;
  insert into test_results values ('L', 'PASSED', 'Cross-org reporting read denied');

  -- K. Ordinary member
  perform set_config('request.jwt.claims', json_build_object('sub', v_pure_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.list_quarterly_formation_reporting_items(v_org_id, '2026-07-01', '2026-09-30');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'K failed'; end if;
  v_caught := false;
  begin perform public.create_program_run(p_organization_id => v_org_id, p_program_code => 'lcs', p_title => 'Unauthorized LCS');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'K failed (create)'; end if;
  insert into test_results values ('K', 'PASSED', 'Ordinary member denied reporting read and LCS creation');
  reset role;
end;
$$;

select test_name, status, details from test_results order by test_name;

rollback;

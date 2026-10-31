-- =============================================================================
-- Test Suite: Pass 9.49 — Structured Speakers + Service Teams (Events & Programs)
-- All mutations executed within a rolled-back transaction.
-- =============================================================================

begin;

create temp table test_results (test_name text, status text, details text);
grant all on test_results to public, authenticated, anon;

do $$
declare
  v_org_id          uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_admin_profile   uuid := '821fb09c-8396-4549-b120-5674f3cc566a'; -- Ron Acosta (org admin)
  v_member_profile  uuid := 'f614188a-51bf-4aea-9fbd-de6f1f49f863'; -- Alan Ybay (events.view, not manager of mfc_ny / youth)
  v_pure_profile    uuid := '0c7cf29f-6185-44eb-8b64-08ab783d7e06'; -- ordinary member, no events.view
  v_fake_org_id     uuid := '11111111-2222-3333-4444-555555555555';

  v_member_a        uuid;
  v_member_b        uuid;
  v_event_id        uuid;
  v_run_id          uuid;
  v_session_id      uuid;
  v_res             jsonb;
  v_sp_internal     uuid;
  v_sp_external     uuid;
  v_svc_internal    uuid;
  v_svc_external    uuid;
  v_psp_session     uuid;
  v_caught          boolean;
  v_rows            integer;
  v_count           integer;
begin
  -- Pick two active members (as table owner, before role switch)
  select id into v_member_a from public.members
  where organization_id = v_org_id and record_status = 'active' and archived_at is null
  order by sort_name limit 1;
  select id into v_member_b from public.members
  where organization_id = v_org_id and record_status = 'active' and archived_at is null and id <> v_member_a
  order by sort_name limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- Fixtures: standalone event + program with one session
  v_res := public.create_event(
    p_organization_id => v_org_id, p_event_type => 'assembly', p_title => 'Pass 9.49 Test Assembly',
    p_starts_at => '2026-11-25 19:00:00-05', p_ends_at => '2026-11-25 21:00:00-05',
    p_audience_code => 'mfc_ny', p_include_in_quarterly_report => true, p_report_priority => 'ministry_activity');
  v_event_id := (v_res->'event'->>'id')::uuid;

  v_res := public.create_program_run(
    p_organization_id => v_org_id, p_program_code => 'youth_camp', p_title => 'Pass 9.49 Test Youth Camp',
    p_session_count => 2, p_section_codes => array['sec_youth']::text[]);
  v_run_id := (v_res->'run'->>'id')::uuid;
  v_res := public.add_program_session(
    p_organization_id => v_org_id, p_run_id => v_run_id, p_session_number => 1,
    p_starts_at => '2026-11-28 09:00:00-05', p_ends_at => '2026-11-28 12:00:00-05');
  v_session_id := (v_res->'event'->>'id')::uuid;

  -- A. Event manager adds internal speaker
  v_res := public.save_activity_speaker(
    p_organization_id => v_org_id, p_event_id => v_event_id, p_member_id => v_member_a,
    p_speaker_role => 'speaker', p_topic_title => 'Family as Domestic Church', p_notes => 'manager-only note');
  v_sp_internal := (v_res->'speaker'->>'id')::uuid;
  if v_res->'speaker'->>'person_type' <> 'member' then raise exception 'A failed'; end if;
  insert into test_results values ('A', 'PASSED', 'Event manager added internal speaker');

  -- B + Q. External speaker without member_id
  v_res := public.save_activity_speaker(
    p_organization_id => v_org_id, p_event_id => v_event_id, p_external_name => 'Benny',
    p_external_title => 'Fr.', p_external_organization => 'St. Mary Star of the Sea Parish',
    p_speaker_role => 'exhortation');
  v_sp_external := (v_res->'speaker'->>'id')::uuid;
  if v_res->'speaker'->>'display_name' <> 'Fr. Benny'
     or v_res->'speaker'->>'external_organization' <> 'St. Mary Star of the Sea Parish'
     or v_res->'speaker'->>'member_id' is not null then
    raise exception 'B failed: %', v_res;
  end if;
  insert into test_results values ('B', 'PASSED', 'External speaker added; display "Fr. Benny", org separate');
  insert into test_results values ('Q', 'PASSED', 'External speaker works without member_id');

  -- C. Edit + remove speaker
  v_res := public.save_activity_speaker(
    p_organization_id => v_org_id, p_speaker_id => v_sp_external, p_external_name => 'Benny',
    p_external_title => 'Fr.', p_speaker_role => 'speaker', p_topic_title => 'Updated Topic');
  if v_res->'speaker'->>'topic_title' <> 'Updated Topic' or v_res->'speaker'->>'speaker_role' <> 'speaker' then
    raise exception 'C (edit) failed';
  end if;
  v_res := public.save_activity_speaker(
    p_organization_id => v_org_id, p_event_id => v_event_id, p_external_name => 'Temp Person', p_speaker_role => 'panelist');
  perform public.remove_activity_speaker(v_org_id, (v_res->'speaker'->>'id')::uuid);
  if exists (select 1 from public.get_activity_team(v_org_id, v_event_id, null) t,
                    jsonb_array_elements(t->'speakers') s where s->>'external_name' = 'Temp Person') then
    raise exception 'C (remove) failed';
  end if;
  insert into test_results values ('C', 'PASSED', 'Speaker edited and removed');

  -- D. Internal service-team member; legit multiple roles
  v_res := public.save_activity_service_assignment(
    p_organization_id => v_org_id, p_event_id => v_event_id, p_member_id => v_member_b, p_role_code => 'worship_leader');
  v_svc_internal := (v_res->'assignment'->>'id')::uuid;
  perform public.save_activity_service_assignment(
    p_organization_id => v_org_id, p_event_id => v_event_id, p_member_id => v_member_b, p_role_code => 'emcee');
  insert into test_results values ('D', 'PASSED', 'Internal service member assigned (Worship Leader + Emcee allowed)');

  -- E. External volunteer
  v_res := public.save_activity_service_assignment(
    p_organization_id => v_org_id, p_event_id => v_event_id, p_external_name => 'Parish Volunteer',
    p_role_code => 'other', p_role_label => 'Sacristan');
  v_svc_external := (v_res->'assignment'->>'id')::uuid;
  if v_res->'assignment'->>'role_label' <> 'Sacristan' then raise exception 'E failed'; end if;
  insert into test_results values ('E', 'PASSED', 'External volunteer assigned with custom Other label');

  -- F. Program manager: internal speaker (program-level)
  perform public.save_activity_speaker(
    p_organization_id => v_org_id, p_program_run_id => v_run_id, p_member_id => v_member_a, p_speaker_role => 'trainer');
  insert into test_results values ('F', 'PASSED', 'Program manager added internal program-level speaker');

  -- G. Program manager: external speaker on a specific session
  v_res := public.save_activity_speaker(
    p_organization_id => v_org_id, p_event_id => v_session_id, p_external_name => 'Benny', p_external_title => 'Fr.',
    p_speaker_role => 'speaker', p_topic_title => 'God''s Love', p_session_label => 'Talk 1');
  v_psp_session := (v_res->'speaker'->>'id')::uuid;
  if (v_res->'speaker'->>'program_run_id')::uuid <> v_run_id or (v_res->'speaker'->>'session_number')::int <> 1 then
    raise exception 'G failed: %', v_res;
  end if;
  insert into test_results values ('G', 'PASSED', 'Session speaker resolves to Program + Session 1');

  -- H. Program service team
  perform public.save_activity_service_assignment(
    p_organization_id => v_org_id, p_program_run_id => v_run_id, p_member_id => v_member_b, p_role_code => 'coordinator');
  insert into test_results values ('H', 'PASSED', 'Program service-team member assigned');

  -- W. Duplicate prevention
  v_caught := false;
  begin
    perform public.save_activity_speaker(
      p_organization_id => v_org_id, p_event_id => v_event_id, p_member_id => v_member_a, p_speaker_role => 'speaker');
  exception when sqlstate '23505' then v_caught := true; end;
  if not v_caught then raise exception 'W (speaker) failed'; end if;
  v_caught := false;
  begin
    perform public.save_activity_service_assignment(
      p_organization_id => v_org_id, p_event_id => v_event_id, p_member_id => v_member_b, p_role_code => 'worship_leader');
  exception when sqlstate '23505' then v_caught := true; end;
  if not v_caught then raise exception 'W (service) failed'; end if;
  insert into test_results values ('W', 'PASSED', 'Duplicate same-person/same-role rejected (23505); multi-role allowed');

  -- R. Neither identity
  v_caught := false;
  begin
    perform public.save_activity_speaker(p_organization_id => v_org_id, p_event_id => v_event_id, p_speaker_role => 'speaker');
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'R failed'; end if;
  insert into test_results values ('R', 'PASSED', 'Neither member_id nor external_name rejected');

  -- S. Both identities
  v_caught := false;
  begin
    perform public.save_activity_speaker(
      p_organization_id => v_org_id, p_event_id => v_event_id, p_member_id => v_member_a,
      p_external_name => 'Someone', p_speaker_role => 'other');
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'S failed'; end if;
  insert into test_results values ('S', 'PASSED', 'Both member_id and external_name rejected (XOR)');

  -- T. Report-ready event read
  v_res := public.get_activity_team(v_org_id, v_event_id, null);
  if jsonb_array_length(v_res->'speakers') <> 2 or jsonb_array_length(v_res->'service_team') <> 3
     or not (v_res->'speakers'->0 ? 'display_name' and v_res->'speakers'->0 ? 'person_type'
             and v_res->'speakers'->0 ? 'external_title' and v_res->'speakers'->0 ? 'external_organization'
             and v_res->'speakers'->0 ? 'topic_title' and v_res->'speakers'->0 ? 'session_label'
             and v_res->'speakers'->0 ? 'speaker_role')
     or not (v_res->'service_team'->0 ? 'role_label' and v_res->'service_team'->0 ? 'person_type') then
    raise exception 'T failed: %', v_res;
  end if;
  insert into test_results values ('T', 'PASSED', 'Event read returns 2 speakers / 3 service entries with report fields');

  -- U. Report-ready program read (aggregates program-level + session)
  v_res := public.get_activity_team(v_org_id, null, v_run_id);
  if jsonb_array_length(v_res->'speakers') <> 2 or jsonb_array_length(v_res->'service_team') <> 1
     or not exists (select 1 from jsonb_array_elements(v_res->'speakers') s
                    where (s->>'session_number')::int = 1 and s->>'display_name' = 'Fr. Benny') then
    raise exception 'U failed: %', v_res;
  end if;
  insert into test_results values ('U', 'PASSED', 'Program read aggregates program-level + Session 1 speaker');

  -- P. Browser cannot supply actor: created_by = server-derived admin profile
  reset role;
  select count(*) into v_count from public.activity_speakers
  where id in (v_sp_internal, v_sp_external, v_psp_session) and created_by_profile_id = v_admin_profile;
  if v_count <> 3 then raise exception 'P failed'; end if;
  insert into test_results values ('P', 'PASSED', 'No actor parameter exists; created_by derived from session profile');
  set local role authenticated;

  -- I/J/K/L + V. Ordinary member (Alan: events.view, not manager)
  perform set_config('request.jwt.claims', json_build_object('sub', v_member_profile, 'role', 'authenticated')::text, true);

  v_res := public.get_activity_team(v_org_id, v_event_id, null);
  if (v_res->>'can_manage')::boolean
     or exists (select 1 from jsonb_array_elements(v_res->'speakers') s where s->>'notes' is not null or s->>'created_at' is not null) then
    raise exception 'V failed: %', v_res;
  end if;
  insert into test_results values ('V', 'PASSED', 'Non-manager read: names/roles visible, notes + audit fields NULL');

  v_caught := false;
  begin
    perform public.save_activity_speaker(p_organization_id => v_org_id, p_event_id => v_event_id, p_external_name => 'Hacker', p_speaker_role => 'speaker');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'I (add) failed'; end if;
  v_caught := false;
  begin
    perform public.remove_activity_speaker(v_org_id, v_sp_internal);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'I (remove) failed'; end if;
  insert into test_results values ('I', 'PASSED', 'Ordinary member cannot add/remove Event speakers');

  v_caught := false;
  begin
    perform public.save_activity_service_assignment(p_organization_id => v_org_id, p_event_id => v_event_id, p_external_name => 'Hacker', p_role_code => 'food');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'J failed'; end if;
  insert into test_results values ('J', 'PASSED', 'Ordinary member cannot modify Event service team');

  v_caught := false;
  begin
    perform public.save_activity_speaker(p_organization_id => v_org_id, p_program_run_id => v_run_id, p_external_name => 'Hacker', p_speaker_role => 'speaker');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'K failed'; end if;
  insert into test_results values ('K', 'PASSED', 'Ordinary member cannot modify Program speakers');

  v_caught := false;
  begin
    perform public.save_activity_service_assignment(p_organization_id => v_org_id, p_program_run_id => v_run_id, p_external_name => 'Hacker', p_role_code => 'food');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'L (program) failed'; end if;
  v_caught := false;
  begin
    perform public.save_activity_service_assignment(p_organization_id => v_org_id, p_event_id => v_session_id, p_external_name => 'Hacker', p_role_code => 'food');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'L (session) failed'; end if;
  insert into test_results values ('L', 'PASSED', 'Ordinary member cannot modify Program/session service team');

  -- Pure member without events.view cannot read
  perform set_config('request.jwt.claims', json_build_object('sub', v_pure_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin
    perform public.get_activity_team(v_org_id, null, v_run_id);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'V (pure read) failed'; end if;

  -- O. Direct table writes blocked
  v_caught := false;
  begin
    insert into public.activity_speakers (organization_id, event_id, external_name, created_by_profile_id)
    values (v_org_id, v_event_id, 'Direct', v_pure_profile);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'O (insert) failed'; end if;
  v_caught := false;
  begin
    update public.activity_service_assignments set role_code = 'food' where id = v_svc_internal;
    get diagnostics v_rows = row_count;
    if v_rows = 0 then v_caught := true; end if;
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'O (update) failed'; end if;
  v_caught := false;
  begin
    delete from public.activity_speakers where id = v_sp_internal;
    get diagnostics v_rows = row_count;
    if v_rows = 0 then v_caught := true; end if;
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'O (delete) failed'; end if;
  v_caught := false;
  begin
    perform 1 from public.activity_speakers limit 1;
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'O (select) failed'; end if;
  insert into test_results values ('O', 'PASSED', 'Direct SELECT/INSERT/UPDATE/DELETE denied (42501)');

  -- N. Cross-org
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin
    perform public.save_activity_speaker(p_organization_id => v_fake_org_id, p_event_id => v_event_id, p_external_name => 'X', p_speaker_role => 'speaker');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'N (write) failed'; end if;
  v_caught := false;
  begin
    perform public.get_activity_team(v_fake_org_id, v_event_id, null);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'N (read) failed'; end if;
  insert into test_results values ('N', 'PASSED', 'Cross-org read/write denied (42501)');

  -- M. Anon
  set local role anon;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_caught := false;
  begin
    perform public.save_activity_speaker(p_organization_id => v_org_id, p_event_id => v_event_id, p_external_name => 'Anon', p_speaker_role => 'speaker');
  exception when sqlstate '42501' or sqlstate '28000' then v_caught := true; end;
  if not v_caught then raise exception 'M (write) failed'; end if;
  v_caught := false;
  begin
    perform public.get_activity_team(v_org_id, v_event_id, null);
  exception when sqlstate '42501' or sqlstate '28000' then v_caught := true; end;
  if not v_caught then raise exception 'M (read) failed'; end if;
  insert into test_results values ('M', 'PASSED', 'Anon read/write denied');
end;
$$;

select * from test_results order by test_name;

rollback;

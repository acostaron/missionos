-- =============================================================================
-- Test Suite: Pass 9.52 - Quarterly National Report generator
-- All mutations roll back. No Storage binaries are written.
-- =============================================================================

begin;

create temp table test_results (test_name text, status text, details text);
grant all on test_results to public, authenticated, anon;

do $$
declare
  v_org_id        uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_admin_profile uuid := '821fb09c-8396-4549-b120-5674f3cc566a';
  v_alan_profile  uuid := 'f614188a-51bf-4aea-9fbd-de6f1f49f863'; -- chapter_servant_leader_access, no report perms
  v_pure_profile  uuid := '0c7cf29f-6185-44eb-8b64-08ab783d7e06';
  v_fake_org_id   uuid := '11111111-2222-3333-4444-555555555555';
  v_csla_role     uuid;

  v_period uuid; v_period_empty uuid;
  v_m1 uuid; v_m2 uuid; v_talk_id uuid; v_ids jsonb;
  v_ev uuid; v_ev_noreport uuid; v_prog uuid; v_prog_s1 uuid; v_prog_s2 uuid;
  v_cls uuid; v_cls_s1 uuid; v_lcs uuid; v_lcs_s1 uuid; v_fev uuid; v_ev2 uuid;
  v_ph_ev uuid := gen_random_uuid(); v_ph_ev_unsel uuid := gen_random_uuid(); v_ph_prog_s uuid := gen_random_uuid();
  v_res jsonb; v_doc jsonb; v_snap jsonb; v_row jsonb;
  v_caught boolean; v_cnt integer; v_audit_before integer;
begin
  select id into v_talk_id from public.formation_talks where is_active order by sequence_order limit 1;
  select jsonb_agg(q.id) into v_ids from (select m.id from public.members m where m.organization_id = v_org_id order by m.member_number limit 2) q;
  v_m1 := (v_ids->>0)::uuid; v_m2 := (v_ids->>1)::uuid;
  select a.app_role_id into v_csla_role from public.profile_role_assignments a join public.app_roles r on r.id = a.app_role_id
   where a.profile_id = v_alan_profile and r.code = 'chapter_servant_leader_access' and a.assignment_status = 'active' limit 1;
  select count(*) into v_audit_before from audit.events where event_code like 'quarterly_report.%';

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ---------------- Fixtures (2026 Q3) ----------------
  perform public.create_draft_reporting_period(v_org_id, 2026, 3);
  perform public.create_draft_reporting_period(v_org_id, 2026, 2);
  reset role;
  select id into v_period from public.ministry_reporting_periods where organization_id = v_org_id and period_year = 2026 and period_quarter = 3;
  select id into v_period_empty from public.ministry_reporting_periods where organization_id = v_org_id and period_year = 2026 and period_quarter = 2;
  -- create_draft_reporting_period auto-captures census; remove Q3's so the census gate can be tested
  delete from public.ministry_census_snapshots where reporting_period_id = v_period;
  set local role authenticated;

  v_ev := (public.create_event(p_organization_id => v_org_id, p_event_type => 'assembly', p_title => 'Pass 9.52 Area Assembly',
    p_starts_at => '2026-08-15 19:00:00-04', p_location_text => 'Queens Center', p_include_in_quarterly_report => true,
    p_report_priority => 'major_highlight', p_report_highlight => 'Original reviewed highlight')->'event'->>'id')::uuid;
  v_ev_noreport := (public.create_event(p_organization_id => v_org_id, p_event_type => 'assembly', p_title => 'Pass 9.52 Not Reportable',
    p_starts_at => '2026-08-16 19:00:00-04')->'event'->>'id')::uuid;
  perform public.save_activity_speaker(p_organization_id => v_org_id, p_event_id => v_ev, p_external_name => 'Bishop Guest', p_speaker_role => 'speaker', p_topic_title => 'Mission');
  perform public.save_activity_service_assignment(p_organization_id => v_org_id, p_event_id => v_ev, p_member_id => v_m1, p_role_code => 'emcee');

  v_prog := (public.create_program_run(p_organization_id => v_org_id, p_program_code => 'other_program', p_title => 'Pass 9.52 Retreat',
    p_session_count => 2, p_include_in_quarterly_report => true, p_report_priority => 'ministry_activity')->'run'->>'id')::uuid;
  v_prog_s1 := (public.add_program_session(p_organization_id => v_org_id, p_run_id => v_prog, p_session_number => 1, p_starts_at => '2026-09-05 09:00:00-04', p_location_text => 'Retreat House')->'event'->>'id')::uuid;
  v_prog_s2 := (public.add_program_session(p_organization_id => v_org_id, p_run_id => v_prog, p_session_number => 2, p_starts_at => '2026-09-06 09:00:00-04')->'event'->>'id')::uuid;

  v_cls := (public.create_program_run(p_organization_id => v_org_id, p_program_code => 'cls', p_title => 'Pass 9.52 CLS',
    p_session_count => 6, p_chapter_code => 'alb', p_section_codes => array['sec_couples']::text[], p_include_in_quarterly_report => true)->'run'->>'id')::uuid;
  v_cls_s1 := (public.add_program_session(p_organization_id => v_org_id, p_run_id => v_cls, p_session_number => 1, p_starts_at => '2026-07-11 09:00:00-04', p_location_text => 'Albany Parish')->'event'->>'id')::uuid;
  perform public.add_program_participant(v_org_id, v_cls, null, 'Cls', 'Guest', null, null, null, null);

  v_lcs := (public.create_program_run(p_organization_id => v_org_id, p_program_code => 'lcs', p_title => 'Pass 9.52 LCS',
    p_session_count => 1, p_include_in_quarterly_report => true)->'run'->>'id')::uuid;
  v_lcs_s1 := (public.add_program_session(p_organization_id => v_org_id, p_run_id => v_lcs, p_session_number => 1, p_starts_at => '2026-07-18 09:00:00-04', p_location_text => 'St. Joseph Parish')->'event'->>'id')::uuid;
  perform public.add_program_participant(v_org_id, v_lcs, null, 'Lcs', 'One', null, null, null, null);
  perform public.add_program_participant(v_org_id, v_lcs, null, 'Lcs', 'Two', null, null, null, null);

  v_fev := (public.create_event(p_organization_id => v_org_id, p_event_type => 'formation_talk', p_title => 'Pass 9.52 Formation',
    p_starts_at => '2026-08-22 19:00:00-04', p_formation_talk_id => v_talk_id, p_include_in_quarterly_report => true)->'event'->>'id')::uuid;

  reset role;
  insert into public.activity_photos (id, organization_id, event_id, program_run_id, storage_bucket, storage_path,
    mime_type, file_size_bytes, caption, include_in_quarterly_report, report_sort_order, uploaded_by_profile_id) values
    (v_ph_ev,       v_org_id, v_ev,      null, 'activity-photos', v_org_id||'/events/'||v_ev||'/'||v_ph_ev||'.jpg', 'image/jpeg', 1000, 'Assembly worship', true, 1, v_admin_profile),
    (v_ph_ev_unsel, v_org_id, v_ev,      null, 'activity-photos', v_org_id||'/events/'||v_ev||'/'||v_ph_ev_unsel||'.jpg', 'image/jpeg', 1000, 'Not selected', false, 0, v_admin_profile),
    (v_ph_prog_s,   v_org_id, v_prog_s2, null, 'activity-photos', v_org_id||'/events/'||v_prog_s2||'/'||v_ph_prog_s||'.jpg', 'image/jpeg', 1000, 'Retreat day 2', true, 1, v_admin_profile);
  set local role authenticated;

  -- A. Preview (live)
  v_res := public.get_quarterly_report_preview(v_period);
  v_doc := v_res->'document';
  if v_res->>'document_source' <> 'live_preview' or v_doc->'header'->>'period_label' <> '2026 Q3' then raise exception 'A failed: %', v_res; end if;
  insert into test_results values ('A', 'PASSED', 'Report viewer previews 2026 Q3 (live builder)');

  -- AD. Period filtering: Q2 activity absent (none created) and Q3 items present
  if not exists (select 1 from jsonb_array_elements(v_doc->'major_highlights') x where x->>'source_id' = v_ev::text) then raise exception 'AD failed'; end if;
  insert into test_results values ('AD', 'PASSED', 'Q3 items present in Q3 report');

  -- AF. Empty Q2
  v_res := public.get_quarterly_report_preview(v_period_empty);
  if jsonb_array_length(v_res->'document'->'formation_items') <> 0 or jsonb_array_length(v_res->'document'->'major_highlights') <> 0
     or jsonb_array_length(v_res->'document'->'other_activities') <> 0 then
    raise exception 'AF failed: %', v_res; end if;
  insert into test_results values ('AF', 'PASSED', 'Empty quarter builds cleanly (empty activity/formation sections)');

  -- U / T / V / W / X / Q / R / S / Y / AE on the draft document
  if exists (select 1 from jsonb_array_elements(v_doc->'major_highlights' || v_doc->'other_activities') x where x->>'source_id' = v_ev_noreport::text) then raise exception 'U failed'; end if;
  insert into test_results values ('U', 'PASSED', 'Non-reportable Event excluded');
  select x into v_row from jsonb_array_elements(v_doc->'major_highlights') x where x->>'source_id' = v_ev::text;
  if jsonb_array_length(v_row->'selected_photos') <> 1 or v_row->'selected_photos'->0->>'photo_id' <> v_ph_ev::text then raise exception 'S/T failed'; end if;
  insert into test_results values ('S', 'PASSED', 'Selected photo included with caption/order/stable path');
  insert into test_results values ('T', 'PASSED', 'Unselected photo excluded');
  if v_row->'speakers'->0->>'name' <> 'Bishop Guest' or v_row->'speakers'->0->>'topic_title' <> 'Mission' then raise exception 'Q failed'; end if;
  insert into test_results values ('Q', 'PASSED', 'Speaker name/role/topic included');
  if jsonb_array_length(v_row->'service_team') <> 1 or v_row->'service_team'->0->>'role_code' <> 'emcee' then raise exception 'R failed'; end if;
  insert into test_results values ('R', 'PASSED', 'Service team name/role included');
  if exists (select 1 from jsonb_array_elements(v_doc->'major_highlights' || v_doc->'other_activities') x
             where x->>'source_id' in (v_prog_s1::text, v_prog_s2::text, v_cls_s1::text, v_lcs_s1::text))
     or (select count(*) from jsonb_array_elements(v_doc->'other_activities') x where x->>'source_id' = v_prog::text) <> 1 then raise exception 'V failed'; end if;
  select x into v_row from jsonb_array_elements(v_doc->'other_activities') x where x->>'source_id' = v_prog::text;
  if jsonb_array_length(v_row->'selected_photos') <> 1 then raise exception 'V (session photo) failed'; end if;
  insert into test_results values ('V', 'PASSED', 'Program appears once; its sessions never appear as Events; session photo rolls up to Program');
  if exists (select 1 from jsonb_array_elements(v_doc->'major_highlights' || v_doc->'other_activities') x where x->>'source_id' in (v_cls::text, v_lcs::text)) then raise exception 'W failed'; end if;
  insert into test_results values ('W', 'PASSED', 'CLS/LCS appear only in the CLS/LCS/Formation section');
  if exists (select 1 from jsonb_array_elements(v_doc->'major_highlights' || v_doc->'other_activities') x where x->>'source_id' = v_fev::text)
     or not exists (select 1 from jsonb_array_elements(v_doc->'formation_items') x where x->>'source_id' = v_fev::text) then raise exception 'X failed'; end if;
  insert into test_results values ('X', 'PASSED', 'Formation Event appears only in Formation section');
  if exists (select 1 from jsonb_array_elements(v_doc->'formation_items') x where x->'completion_count' <> 'null'::jsonb) then raise exception 'Y failed'; end if;
  insert into test_results values ('Y', 'PASSED', 'Completion stays NULL (not 0)');
  if (v_doc->'summary'->>'reportable_events')::int <> 1 or (v_doc->'summary'->>'reportable_programs')::int <> 1
     or (v_doc->'summary'->>'cls_count')::int <> 1 or (v_doc->'summary'->>'lcs_count')::int <> 1 or (v_doc->'summary'->>'formation_count')::int <> 1
     or (v_doc->'summary'->>'cls_registered_participants')::int <> 1 or (v_doc->'summary'->>'lcs_registered_participants')::int <> 2
     or (v_doc->'summary'->>'selected_photos')::int <> 2 or (v_doc->'summary'->>'speaker_assignments')::int <> 1
     or (v_doc->'summary'->>'service_team_assignments')::int <> 1
     or v_doc->'summary'->'known_completions' <> 'null'::jsonb or (v_doc->'summary'->>'completion_unavailable_activities')::int <> 3 then
    raise exception 'AE failed: %', v_doc->'summary'; end if;
  insert into test_results values ('AE', 'PASSED', 'Summary counts correct; unknown completions not summed as zero');

  -- B / C / D
  perform set_config('request.jwt.claims', json_build_object('sub', v_pure_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.get_quarterly_report_preview(v_period); exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'B failed'; end if;
  insert into test_results values ('B', 'PASSED', 'Ordinary member denied');

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.list_quarterly_reports(v_fake_org_id); exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'D failed'; end if;
  insert into test_results values ('D', 'PASSED', 'Cross-org denied');

  -- E / F / G with temporary grants to chapter_servant_leader_access (rolled back)
  perform set_config('request.jwt.claims', json_build_object('sub', v_alan_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.get_quarterly_report_preview(v_period); exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'G0 failed: manager without reporting permission'; end if;
  reset role;
  insert into public.role_permissions (organization_id, app_role_id, permission_id, permission_effect, effective_from_at, approval_status, approved_at)
  select v_org_id, v_csla_role, p.id, 'allow', now() - interval '1 minute', 'approved', now() from public.permissions p where p.code = 'reports.quarterly.view';
  set local role authenticated;
  perform public.get_quarterly_report_preview(v_period);
  v_caught := false;
  begin perform public.refresh_quarterly_report_draft(v_period); exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'E failed'; end if;
  insert into test_results values ('E', 'PASSED', 'View-only user can preview but not refresh (operational leader w/o report perms denied)');
  reset role;
  insert into public.role_permissions (organization_id, app_role_id, permission_id, permission_effect, effective_from_at, approval_status, approved_at)
  select v_org_id, v_csla_role, p.id, 'allow', now() - interval '1 minute', 'approved', now() from public.permissions p where p.code = 'reports.quarterly.manage';
  set local role authenticated;
  v_res := public.refresh_quarterly_report_draft(v_period);
  if v_res->>'document_source' <> 'stored_draft' or v_res->'report'->>'status' <> 'draft' then raise exception 'F failed'; end if;
  insert into test_results values ('F', 'PASSED', 'Manager refreshed draft (stored)');

  -- I. Census gates: the frozen review document must contain the approved census
  v_caught := false;
  begin perform public.submit_quarterly_report_for_review(v_period); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'I failed (submit without snapshot)'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);
  perform public.capture_quarterly_census_snapshot(v_period);
  perform set_config('request.jwt.claims', json_build_object('sub', v_alan_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.submit_quarterly_report_for_review(v_period); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'I failed (submit with unapproved census)'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);
  perform public.set_reporting_period_status(v_period, 'review');
  perform public.set_reporting_period_status(v_period, 'approved');
  perform set_config('request.jwt.claims', json_build_object('sub', v_alan_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.submit_quarterly_report_for_review(v_period); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'I failed (stale draft without census)'; end if;
  insert into test_results values ('I', 'PASSED', 'Review/approval blocked without census snapshot, without approved census, and with a stale draft lacking the census');

  perform public.refresh_quarterly_report_draft(v_period);
  perform public.submit_quarterly_report_for_review(v_period);
  v_caught := false;
  begin perform public.approve_quarterly_report(v_period); exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'G failed'; end if;
  insert into test_results values ('G', 'PASSED', 'Manager without approve permission cannot approve');

  -- AC / AB workflow (admin)
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.refresh_quarterly_report_draft(v_period); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'AC failed (refresh in review)'; end if;
  v_caught := false;
  begin perform public.submit_quarterly_report_for_review(v_period); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'AC failed (submit twice)'; end if;
  v_caught := false;
  begin perform public.get_quarterly_report_snapshot(v_period); exception when sqlstate 'P0002' then v_caught := true; end;
  if not v_caught then raise exception 'AC failed (snapshot before approval)'; end if;
  perform public.return_quarterly_report_to_draft(v_period);
  v_caught := false;
  begin perform public.approve_quarterly_report(v_period); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'AC failed (approve from draft)'; end if;
  insert into test_results values ('AC', 'PASSED', 'Refresh-in-review, double submit, approve-from-draft, snapshot-before-approval rejected');
  perform public.refresh_quarterly_report_draft(v_period);
  v_res := public.submit_quarterly_report_for_review(v_period);
  if v_res->'report'->>'status' <> 'review' or v_res->>'document_source' <> 'review_draft' then raise exception 'AB failed'; end if;
  insert into test_results values ('AB', 'PASSED', 'Draft -> Review -> Draft -> Review workflow valid');

  -- AI / AN. Frozen review document survives source mutation
  reset role;
  select draft_document into v_doc from public.ministry_quarterly_reports where reporting_period_id = v_period;
  update public.events set report_highlight = 'CHANGED AFTER REVIEW', title = 'Pass 9.52 Changed In Review' where id = v_ev;
  update public.activity_photos set include_in_quarterly_report = false where id = v_ph_prog_s;
  insert into public.activity_photos (id, organization_id, event_id, storage_bucket, storage_path, mime_type, file_size_bytes, caption,
    include_in_quarterly_report, report_sort_order, uploaded_by_profile_id)
  values (gen_random_uuid(), v_org_id, v_ev, 'activity-photos', v_org_id||'/events/'||v_ev||'/late.jpg', 'image/jpeg', 1000, 'LATE PHOTO', true, 2, v_admin_profile);
  set local role authenticated;
  perform public.add_program_participant(v_org_id, v_lcs, null, 'Late', 'Participant', null, null, null, null);
  v_res := public.get_quarterly_report_preview(v_period);
  if v_res->'document' <> v_doc or v_res->>'document_source' <> 'review_draft'
     or not ((v_res->'document')::text like '%Original reviewed highlight%')
     or (v_res->'document')::text like '%CHANGED AFTER REVIEW%' or (v_res->'document')::text like '%LATE PHOTO%'
     or (v_res->'document'->'summary'->>'lcs_registered_participants')::int <> 2 then
    raise exception 'AI failed'; end if;
  insert into test_results values ('AI', 'PASSED', 'Review document unchanged after source edits (highlight, title, photos, participants)');
  perform public.record_quarterly_report_export(v_period, 'pdf');
  insert into test_results values ('AN', 'PASSED', 'Review read/export source is the frozen review document (document_source=review_draft)');
  reset role;
  v_caught := false;
  begin update public.ministry_quarterly_reports set draft_document = draft_document || '{"x":1}' where reporting_period_id = v_period;
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'AI failed (privileged review mutation)'; end if;
  set local role authenticated;

  -- H / AJ / AK. Approval copies the exact frozen review document
  v_res := public.approve_quarterly_report(v_period);
  if v_res->'report'->>'status' <> 'approved' or v_res->>'document_source' <> 'approved_snapshot' then raise exception 'H failed'; end if;
  insert into test_results values ('H', 'PASSED', 'Approver approved the report');
  reset role;
  if (select (approved_document - 'approval') <> draft_document or draft_document <> v_doc
        from public.ministry_quarterly_reports where reporting_period_id = v_period) then raise exception 'AJ failed'; end if;
  set local role authenticated;
  insert into test_results values ('AJ', 'PASSED', 'approved_document minus approval block equals frozen review document exactly');
  v_snap := (public.get_quarterly_report_snapshot(v_period))->'document';
  if v_snap::text like '%CHANGED AFTER REVIEW%' or v_snap::text like '%LATE PHOTO%' or v_snap::text like '%Changed In Review%'
     or not (v_snap::text like '%Original reviewed highlight%') then raise exception 'AK failed'; end if;
  insert into test_results values ('AK', 'PASSED', 'Approved report excludes source edits made after Review');
  if v_snap->'approval'->>'approved_by_profile_id' <> v_admin_profile::text then raise exception 'J failed'; end if;
  insert into test_results values ('J', 'PASSED', 'Approved snapshot created with approval metadata');
  reset role;
  if (v_snap->'census'->>'total_active_members')::int <> (select total_active_members from public.ministry_census_snapshots where reporting_period_id = v_period)
     or jsonb_array_length(v_snap->'census'->'sections') <> (select count(*) from public.ministry_census_snapshot_rows r join public.ministry_census_snapshots s on s.id = r.snapshot_id where s.reporting_period_id = v_period) then
    raise exception 'K failed'; end if;
  set local role authenticated;
  insert into test_results values ('K', 'PASSED', 'Snapshot stores census totals and section rows from census snapshot');
  if not exists (select 1 from jsonb_array_elements(v_snap->'major_highlights') x where x->>'source_id' = v_ev::text) then raise exception 'L failed'; end if;
  insert into test_results values ('L', 'PASSED', 'Snapshot stores reportable Event');
  if not exists (select 1 from jsonb_array_elements(v_snap->'other_activities') x where x->>'source_id' = v_prog::text) then raise exception 'M failed'; end if;
  insert into test_results values ('M', 'PASSED', 'Snapshot stores reportable Program');
  if not exists (select 1 from jsonb_array_elements(v_snap->'formation_items') x where x->>'source_id' = v_cls::text and x->>'source_kind' = 'cls') then raise exception 'N failed'; end if;
  insert into test_results values ('N', 'PASSED', 'Snapshot stores CLS');
  if not exists (select 1 from jsonb_array_elements(v_snap->'formation_items') x where x->>'source_id' = v_lcs::text and x->>'source_kind' = 'lcs') then raise exception 'O failed'; end if;
  insert into test_results values ('O', 'PASSED', 'Snapshot stores LCS');
  if not exists (select 1 from jsonb_array_elements(v_snap->'formation_items') x where x->>'source_id' = v_fev::text and x->>'source_kind' = 'formation') then raise exception 'P failed'; end if;
  insert into test_results values ('P', 'PASSED', 'Snapshot stores Formation');
  if (v_snap->>'schema_version')::int <> 1 then raise exception 'AG failed'; end if;
  insert into test_results values ('AG', 'PASSED', 'schema_version = 1');

  -- Z. Source changes after approval do not alter the snapshot
  reset role;
  update public.events set report_highlight = 'CHANGED AFTER APPROVAL', title = 'Pass 9.52 Renamed' where id = v_ev;
  update public.activity_photos set include_in_quarterly_report = false where id = v_ph_ev;
  set local role authenticated;
  v_res := public.get_quarterly_report_snapshot(v_period);
  if v_res->'document' <> v_snap or (v_res->'document')::text like '%CHANGED AFTER APPROVAL%' then raise exception 'Z failed'; end if;
  v_caught := false;
  begin perform public.refresh_quarterly_report_draft(v_period); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'Z failed (refresh approved)'; end if;
  insert into test_results values ('Z', 'PASSED', 'Approved snapshot unchanged after source edits; approved report cannot be refreshed');

  -- AA. Direct writes denied; trigger blocks privileged edits of approved rows
  v_caught := false;
  begin update public.ministry_quarterly_reports set status = 'draft' where reporting_period_id = v_period;
  exception when insufficient_privilege then v_caught := true; end;
  if not v_caught then raise exception 'AA failed (authenticated update)'; end if;
  v_caught := false;
  begin insert into public.ministry_quarterly_reports (organization_id, reporting_period_id) values (v_org_id, v_period_empty);
  exception when insufficient_privilege then v_caught := true; end;
  if not v_caught then raise exception 'AA failed (authenticated insert)'; end if;
  reset role;
  v_caught := false;
  begin update public.ministry_quarterly_reports set approved_document = '{}'::jsonb where reporting_period_id = v_period;
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'AA failed (trigger)'; end if;
  insert into test_results values ('AA', 'PASSED', 'Direct table writes denied; approved row frozen even for privileged roles');

  -- AM. Approval without a frozen review document rejected (Q2)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.approve_quarterly_report(v_period_empty); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'AM failed (no report row)'; end if;
  perform public.set_reporting_period_status(v_period_empty, 'review');
  perform public.set_reporting_period_status(v_period_empty, 'approved');
  v_ev2 := (public.create_event(p_organization_id => v_org_id, p_event_type => 'assembly', p_title => 'Pass 9.52 Q2 Event',
    p_starts_at => '2026-05-10 19:00:00-04', p_include_in_quarterly_report => true, p_report_highlight => 'Version A')->'event'->>'id')::uuid;
  perform public.refresh_quarterly_report_draft(v_period_empty);
  v_caught := false;
  begin perform public.approve_quarterly_report(v_period_empty); exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'AM failed (draft only)'; end if;
  reset role;
  v_caught := false;
  begin update public.ministry_quarterly_reports set status = 'approved', approved_document = '{"forged":true}'::jsonb,
          approved_at = now(), approved_by_profile_id = v_admin_profile where reporting_period_id = v_period_empty;
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'AM failed (privileged forge)'; end if;
  insert into test_results values ('AM', 'PASSED', 'Approval rejected without a frozen review document; forged approved_document blocked by trigger');

  -- AL. Return to Draft lets refreshed source changes into a new Review
  set local role authenticated;
  perform public.submit_quarterly_report_for_review(v_period_empty);
  perform public.return_quarterly_report_to_draft(v_period_empty);
  reset role;
  update public.events set report_highlight = 'Version B' where id = v_ev2;
  set local role authenticated;
  v_res := public.get_quarterly_report_preview(v_period_empty);
  if not ((v_res->'document')::text like '%Version A%') then raise exception 'AL failed (draft changed before refresh)'; end if;
  perform public.refresh_quarterly_report_draft(v_period_empty);
  v_res := public.submit_quarterly_report_for_review(v_period_empty);
  if not ((v_res->'document')::text like '%Version B%') or (v_res->'document')::text like '%Version A%' then raise exception 'AL failed (review)'; end if;
  v_res := public.approve_quarterly_report(v_period_empty);
  if not ((v_res->'document')::text like '%Version B%') or (v_res->'document')::text like '%Version A%' then raise exception 'AL failed (approved)'; end if;
  reset role;
  insert into test_results values ('AL', 'PASSED', 'Review A -> Draft -> source B -> refresh -> Review B -> Approved B');

  -- AH. Audit
  set local role authenticated;
  perform public.record_quarterly_report_export(v_period, 'pdf');
  perform public.record_quarterly_report_export(v_period, 'xlsx');
  reset role;
  select count(*) into v_cnt from audit.events where event_code like 'quarterly_report.%';
  if v_cnt - v_audit_before < 8
     or not exists (select 1 from audit.events where event_code = 'quarterly_report.approved')
     or not exists (select 1 from audit.events where event_code = 'quarterly_report.exported_pdf')
     or not exists (select 1 from audit.events where event_code = 'quarterly_report.exported_excel') then
    raise exception 'AH failed: %', v_cnt - v_audit_before; end if;
  insert into test_results values ('AH', 'PASSED', 'Audit: draft refreshed, submitted, returned, approved, PDF + Excel exports');

  -- C. anon
  set local role anon;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_caught := false;
  begin perform public.get_quarterly_report_preview(v_period); exception when insufficient_privilege or sqlstate '28000' then v_caught := true; end;
  if not v_caught then raise exception 'C failed'; end if;
  insert into test_results values ('C', 'PASSED', 'anon denied');
  reset role;
end;
$$;

select test_name, status, details from test_results order by length(test_name), test_name;

rollback;

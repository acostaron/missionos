-- =============================================================================
-- Test Suite: Pass 9.50 — Event + Program Photos
-- All mutations (including storage.objects metadata rows) roll back.
-- No binary objects are written to the bucket.
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

  v_event_id   uuid;
  v_event2_id  uuid;
  v_run_id     uuid;
  v_session_id uuid;
  v_res        jsonb;
  v_path_e     text;
  v_path_p     text;
  v_path_s     text;
  v_path_bad   text;
  v_photo_e    uuid;
  v_photo_p    uuid;
  v_photo_s    uuid;
  v_caught     boolean;
  v_rows       integer;
  v_uploader   uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- Fixtures
  v_res := public.create_event(
    p_organization_id => v_org_id, p_event_type => 'assembly', p_title => 'Pass 9.50 Test Assembly',
    p_starts_at => '2026-11-25 19:00:00-05', p_audience_code => 'mfc_ny',
    p_include_in_quarterly_report => true, p_report_priority => 'ministry_activity');
  v_event_id := (v_res->'event'->>'id')::uuid;
  v_res := public.create_event(
    p_organization_id => v_org_id, p_event_type => 'assembly', p_title => 'Pass 9.50 Non-reportable',
    p_starts_at => '2026-11-26 19:00:00-05', p_audience_code => 'mfc_ny');
  v_event2_id := (v_res->'event'->>'id')::uuid;
  v_res := public.create_program_run(
    p_organization_id => v_org_id, p_program_code => 'youth_camp', p_title => 'Pass 9.50 Test Camp',
    p_session_count => 2, p_section_codes => array['sec_youth']::text[], p_include_in_quarterly_report => true);
  v_run_id := (v_res->'run'->>'id')::uuid;
  v_res := public.add_program_session(
    p_organization_id => v_org_id, p_run_id => v_run_id, p_session_number => 1,
    p_starts_at => '2026-11-28 09:00:00-05');
  v_session_id := (v_res->'event'->>'id')::uuid;

  -- A. Event manager initiates + finalizes
  v_res := public.create_activity_photo_upload(v_org_id, v_event_id, null, 'image/jpeg', 2000000);
  v_path_e := v_res->>'storage_path';
  if v_path_e not like v_org_id::text || '/events/' || v_event_id::text || '/%.jpg' then raise exception 'A path: %', v_path_e; end if;
  if not public.can_write_activity_photo(v_path_e) then raise exception 'A storage write check failed'; end if;
  reset role;
  insert into storage.objects (bucket_id, name, metadata) values ('activity-photos', v_path_e, '{"mimetype":"image/jpeg","size":2000000}');
  set local role authenticated;
  v_res := public.finalize_activity_photo(v_org_id, v_path_e, 'IMG_1.jpg', 'Couples praying together during the assembly');
  v_photo_e := (v_res->'photo'->>'id')::uuid;
  insert into test_results values ('A', 'PASSED', 'Event manager initiated upload, storage write allowed, metadata finalized');

  -- B. Program manager (program-level)
  v_res := public.create_activity_photo_upload(v_org_id, null, v_run_id, 'image/png', 500000);
  v_path_p := v_res->>'storage_path';
  reset role;
  insert into storage.objects (bucket_id, name, metadata) values ('activity-photos', v_path_p, '{"mimetype":"image/png","size":500000}');
  set local role authenticated;
  v_res := public.finalize_activity_photo(v_org_id, v_path_p, null, 'Youth camp group photo', null, true);
  v_photo_p := (v_res->'photo'->>'id')::uuid;
  insert into test_results values ('B', 'PASSED', 'Program-level photo finalized (selected for report)');

  -- C. Session event photo
  v_res := public.create_activity_photo_upload(v_org_id, v_session_id, null, 'image/webp', 300000);
  v_path_s := v_res->>'storage_path';
  reset role;
  insert into storage.objects (bucket_id, name, metadata) values ('activity-photos', v_path_s, '{"mimetype":"image/webp","size":300000}');
  set local role authenticated;
  v_res := public.finalize_activity_photo(v_org_id, v_path_s, null, 'Session 1 worship');
  v_photo_s := (v_res->'photo'->>'id')::uuid;
  if (v_res->'photo'->>'program_run_id')::uuid <> v_run_id or (v_res->'photo'->>'session_number')::int <> 1 then
    raise exception 'C failed: %', v_res;
  end if;
  insert into test_results values ('C', 'PASSED', 'Session photo stored on session event, resolves to Program + Session 1');

  -- I. Actor server-derived
  reset role;
  select uploaded_by_profile_id into v_uploader from public.activity_photos where id = v_photo_e;
  if v_uploader <> v_admin_profile then raise exception 'I failed'; end if;
  set local role authenticated;
  insert into test_results values ('I', 'PASSED', 'uploaded_by = session profile; no actor parameter exists');

  -- J. MIME
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, v_event_id, null, 'image/svg+xml', 1000);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'J (request) failed'; end if;
  -- object whose stored MIME mismatches is rejected at finalize
  v_path_bad := v_org_id::text || '/events/' || v_event_id::text || '/' || gen_random_uuid()::text || '.jpg';
  reset role;
  insert into storage.objects (bucket_id, name, metadata) values ('activity-photos', v_path_bad, '{"mimetype":"text/html","size":100}');
  set local role authenticated;
  v_caught := false;
  begin perform public.finalize_activity_photo(v_org_id, v_path_bad);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'J (finalize) failed'; end if;
  insert into test_results values ('J', 'PASSED', 'SVG request rejected; stored non-image MIME rejected at finalize');

  -- K. Size
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, v_event_id, null, 'image/jpeg', 10485761);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'K (request) failed'; end if;
  v_path_bad := v_org_id::text || '/events/' || v_event_id::text || '/' || gen_random_uuid()::text || '.jpg';
  reset role;
  insert into storage.objects (bucket_id, name, metadata) values ('activity-photos', v_path_bad, '{"mimetype":"image/jpeg","size":20000000}');
  set local role authenticated;
  v_caught := false;
  begin perform public.finalize_activity_photo(v_org_id, v_path_bad);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'K (finalize) failed'; end if;
  insert into test_results values ('K', 'PASSED', '>10 MB rejected at request and at finalize (server-side size)');

  -- L / M. Target validation
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, null, null, 'image/jpeg', 1000);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'L failed'; end if;
  insert into test_results values ('L', 'PASSED', 'Neither Event nor Program rejected');
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, v_event_id, v_run_id, 'image/jpeg', 1000);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'M failed'; end if;
  insert into test_results values ('M', 'PASSED', 'Both Event and Program rejected');

  -- N. Caption update
  v_res := public.update_activity_photo(v_org_id, v_photo_e, p_caption => 'Updated caption');
  if v_res->'photo'->>'caption' <> 'Updated caption' then raise exception 'N failed'; end if;
  insert into test_results values ('N', 'PASSED', 'Caption updated');

  -- O. Caption max length
  v_caught := false;
  begin perform public.update_activity_photo(v_org_id, v_photo_e, p_caption => repeat('x', 501));
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'O failed'; end if;
  insert into test_results values ('O', 'PASSED', 'Caption > 500 chars rejected');

  -- P / Q. Report selection + order
  v_res := public.update_activity_photo(v_org_id, v_photo_e, p_include_in_quarterly_report => true, p_report_sort_order => 7);
  if (v_res->'photo'->>'include_in_quarterly_report')::boolean is not true then raise exception 'P failed'; end if;
  insert into test_results values ('P', 'PASSED', 'Quarterly inclusion toggled on');
  reset role;
  if (select report_sort_order from public.activity_photos where id = v_photo_e) <> 7 then raise exception 'Q failed'; end if;
  set local role authenticated;
  insert into test_results values ('Q', 'PASSED', 'report_sort_order persisted (7)');

  -- U. Program aggregation
  v_res := public.get_activity_photos(v_org_id, null, v_run_id);
  if (v_res->>'total_count')::int <> 2
     or not exists (select 1 from jsonb_array_elements(v_res->'photos') x where (x->>'session_number')::int = 1 and (x->>'event_id')::uuid = v_session_id)
     or not exists (select 1 from jsonb_array_elements(v_res->'photos') x where x->>'event_id' is null and (x->>'program_run_id')::uuid = v_run_id) then
    raise exception 'U failed: %', v_res;
  end if;
  insert into test_results values ('U', 'PASSED', 'Program read = program-level + session photo (2, no duplicates)');

  -- V. Report-ready read (activity AND photo selected)
  perform public.update_activity_photo(v_org_id, v_photo_s, p_include_in_quarterly_report => false);
  v_res := public.list_report_activity_photos(v_org_id, '2026-10-01', '2026-12-31');
  if not exists (select 1 from jsonb_array_elements(v_res) x where (x->>'id')::uuid = v_photo_e and x->>'activity_title' = 'Pass 9.50 Test Assembly')
     or not exists (select 1 from jsonb_array_elements(v_res) x where (x->>'id')::uuid = v_photo_p and x->>'activity_kind' = 'program')
     or exists (select 1 from jsonb_array_elements(v_res) x where (x->>'id')::uuid = v_photo_s) then
    raise exception 'V failed: %', v_res;
  end if;
  insert into test_results values ('V', 'PASSED', 'Report read returns only selected photos of reportable activities');

  -- R. Delete authorization (manager deletes; record gone; read check fails)
  v_res := public.delete_activity_photo(v_org_id, v_photo_s);
  if v_res->>'storage_path' <> v_path_s then raise exception 'R failed'; end if;
  if public.can_read_activity_photo(v_path_s) then raise exception 'R (deleted path still readable)'; end if;
  insert into test_results values ('R', 'PASSED', 'Manager delete returns path; deleted photo no longer resolves for reads');

  -- W. Cancelled activity: no new uploads; existing photos remain readable
  perform public.set_event_status(v_org_id, v_event_id, 'cancelled', 'Pass 9.50 test cancel');
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, v_event_id, null, 'image/jpeg', 1000);
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'W failed'; end if;
  if (public.get_activity_photos(v_org_id, v_event_id, null)->>'total_count')::int <> 1 then raise exception 'W (read) failed'; end if;
  perform public.set_event_status(v_org_id, v_event_id, 'scheduled', null);
  insert into test_results values ('W', 'PASSED', 'Cancelled event rejects new photos; existing photos preserved/readable');

  -- S / T. Ordinary viewer (Alan)
  perform set_config('request.jwt.claims', json_build_object('sub', v_member_profile, 'role', 'authenticated')::text, true);
  v_res := public.get_activity_photos(v_org_id, v_event_id, null);
  if jsonb_array_length(v_res->'photos') <> 1 or v_res->'photos'->0->>'caption' is null then raise exception 'S failed'; end if;
  if not public.can_read_activity_photo(v_path_e) then raise exception 'S (storage read) failed'; end if;
  insert into test_results values ('S', 'PASSED', 'Viewer reads photo + caption; storage read allowed');
  if (v_res->>'can_manage')::boolean or v_res->>'selected_count' is not null
     or v_res->'photos'->0->>'include_in_quarterly_report' is not null
     or v_res->'photos'->0->>'uploaded_by_name' is not null
     or v_res->'photos'->0->>'uploaded_at' is not null
     or v_res->'photos'->0->>'original_filename' is not null then
    raise exception 'T failed: %', v_res;
  end if;
  insert into test_results values ('T', 'PASSED', 'Report flags, filename, size, uploader masked for viewer');

  -- D / E. Ordinary member cannot upload
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, v_event_id, null, 'image/jpeg', 1000);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught or public.can_write_activity_photo(v_path_e) then raise exception 'D failed'; end if;
  v_caught := false;
  begin perform public.finalize_activity_photo(v_org_id, v_path_bad);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'D (finalize) failed'; end if;
  v_caught := false;
  begin perform public.update_activity_photo(v_org_id, v_photo_e, p_caption => 'hack');
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'D (update) failed'; end if;
  v_caught := false;
  begin perform public.delete_activity_photo(v_org_id, v_photo_e);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'D (delete) failed'; end if;
  insert into test_results values ('D', 'PASSED', 'Ordinary member denied Event upload/finalize/update/delete + storage write');
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, null, v_run_id, 'image/jpeg', 1000);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught or public.can_write_activity_photo(v_path_p) then raise exception 'E failed'; end if;
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, v_session_id, null, 'image/jpeg', 1000);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'E (session) failed'; end if;
  insert into test_results values ('E', 'PASSED', 'Ordinary member denied Program/session upload + storage write');

  -- Arbitrary / malformed path writes denied
  if public.can_write_activity_photo('x/y/z.jpg')
     or public.can_write_activity_photo(v_org_id::text || '/events/' || v_event_id::text || '/../evil.html') then
    raise exception 'storage path validation failed';
  end if;

  -- Pure member: no read
  perform set_config('request.jwt.claims', json_build_object('sub', v_pure_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.get_activity_photos(v_org_id, null, v_run_id);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught or public.can_read_activity_photo(v_path_p) then raise exception 'S (pure) failed'; end if;

  -- H. Direct table writes
  v_caught := false;
  begin
    insert into public.activity_photos (id, organization_id, event_id, storage_path, mime_type, file_size_bytes, uploaded_by_profile_id)
    values (gen_random_uuid(), v_org_id, v_event_id, 'direct/path/x.jpg', 'image/jpeg', 1, v_pure_profile);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'H (insert) failed'; end if;
  v_caught := false;
  begin
    update public.activity_photos set include_in_quarterly_report = true where id = v_photo_e;
    get diagnostics v_rows = row_count; if v_rows = 0 then v_caught := true; end if;
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'H (update) failed'; end if;
  v_caught := false;
  begin
    delete from public.activity_photos where id = v_photo_e;
    get diagnostics v_rows = row_count; if v_rows = 0 then v_caught := true; end if;
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'H (delete) failed'; end if;
  insert into test_results values ('H', 'PASSED', 'Direct INSERT/UPDATE/DELETE on activity_photos denied');

  -- G. Cross-org
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_fake_org_id, v_event_id, null, 'image/jpeg', 1000);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'G (request) failed'; end if;
  v_caught := false;
  begin perform public.get_activity_photos(v_fake_org_id, v_event_id, null);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'G (read) failed'; end if;
  if public.can_write_activity_photo(v_fake_org_id::text || '/events/' || v_event_id::text || '/' || gen_random_uuid()::text || '.jpg') then
    raise exception 'G (storage) failed';
  end if;
  v_caught := false;
  begin perform public.finalize_activity_photo(v_org_id, replace(v_path_bad, v_org_id::text, v_fake_org_id::text));
  exception when sqlstate '22023' then v_caught := true; end;
  if not v_caught then raise exception 'G (finalize) failed'; end if;
  insert into test_results values ('G', 'PASSED', 'Cross-org request/read/storage path/finalize denied');

  -- F. Anon
  set local role anon;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_caught := false;
  begin perform public.create_activity_photo_upload(v_org_id, v_event_id, null, 'image/jpeg', 1000);
  exception when sqlstate '42501' or sqlstate '28000' then v_caught := true; end;
  if not v_caught then raise exception 'F (upload) failed'; end if;
  v_caught := false;
  begin perform public.get_activity_photos(v_org_id, v_event_id, null);
  exception when sqlstate '42501' or sqlstate '28000' then v_caught := true; end;
  if not v_caught then raise exception 'F (read) failed'; end if;
  v_caught := false;
  begin perform public.can_read_activity_photo(v_path_e);
  exception when sqlstate '42501' then v_caught := true; end;
  if not v_caught then raise exception 'F (storage helper) failed'; end if;
  insert into test_results values ('F', 'PASSED', 'Anon denied upload, read, and storage helpers');
end;
$$;

select * from test_results order by test_name;

rollback;

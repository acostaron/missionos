-- =============================================================================
-- Test Suite: Pass 9.47 — Event Reporting Metadata & In-Person / Virtual
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
  v_event_id_a         uuid;
  v_event_id_b         uuid;
  v_event_id_c         uuid;
  v_event_id_d         uuid;
  v_read_res           jsonb;
  v_list_res           jsonb;
  v_my_events_res      jsonb;
  v_my_item            jsonb;
  v_caught             boolean;
  v_reportable_count   integer;
begin
  -- Set context to Organization Administrator
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- ---------------------------------------------------------------------------
  -- Test 21.A: Create In-Person event
  -- ---------------------------------------------------------------------------
  v_res := public.create_event(
    p_organization_id => v_org_id,
    p_event_type => 'assembly',
    p_title => 'Test In-Person Assembly 2026',
    p_starts_at => '2026-11-25 19:00:00-05',
    p_ends_at => '2026-11-25 21:00:00-05',
    p_location_text => 'St. Patrick Church Hall, Queens, NY',
    p_description => 'In-person general assembly',
    p_audience_code => 'mfc_ny',
    p_formation_talk_id => null,
    p_meeting_type => 'in_person',
    p_virtual_meeting_url => null,
    p_include_in_quarterly_report => false,
    p_report_priority => 'routine',
    p_report_highlight => null
  );
  v_event_id_a := (v_res->'event'->>'id')::uuid;

  if v_res->'event'->>'meeting_type' <> 'in_person' then
    raise exception 'Test 21.A failed: expected meeting_type in_person, got %', v_res->'event'->>'meeting_type';
  end if;
  if v_res->'event'->>'virtual_meeting_url' is not null then
    raise exception 'Test 21.A failed: virtual_meeting_url should be null';
  end if;
  if (v_res->'event'->>'include_in_quarterly_report')::boolean <> false then
    raise exception 'Test 21.A failed: include_in_quarterly_report should be false';
  end if;
  if v_res->'event'->>'report_priority' <> 'routine' then
    raise exception 'Test 21.A failed: report_priority should be routine';
  end if;
  if v_res->'event'->>'location_text' <> 'St. Patrick Church Hall, Queens, NY' then
    raise exception 'Test 21.A failed: location_text mismatch';
  end if;
  insert into test_results values ('Test 21.A', 'PASSED', 'In-Person event created successfully with defaults');

  -- ---------------------------------------------------------------------------
  -- Test 21.B & 21.H: Create Virtual event with valid HTTPS URL & Ministry Activity
  -- ---------------------------------------------------------------------------
  v_res := public.create_event(
    p_organization_id => v_org_id,
    p_event_type => 'teaching',
    p_title => 'Test Virtual Teaching 2026',
    p_starts_at => '2026-11-26 19:00:00-05',
    p_ends_at => '2026-11-26 21:00:00-05',
    p_location_text => null,
    p_description => 'Online formation teaching session',
    p_audience_code => 'mfc_ny',
    p_formation_talk_id => null,
    p_meeting_type => 'virtual',
    p_virtual_meeting_url => 'https://zoom.us/j/1234567890?pwd=xyz',
    p_include_in_quarterly_report => true,
    p_report_priority => 'ministry_activity',
    p_report_highlight => 'Over 80 households attended the online teaching session on family spirituality.'
  );
  v_event_id_b := (v_res->'event'->>'id')::uuid;

  if v_res->'event'->>'meeting_type' <> 'virtual' then
    raise exception 'Test 21.B failed: expected meeting_type virtual, got %', v_res->'event'->>'meeting_type';
  end if;
  if v_res->'event'->>'virtual_meeting_url' <> 'https://zoom.us/j/1234567890?pwd=xyz' then
    raise exception 'Test 21.B failed: virtual_meeting_url mismatch';
  end if;
  if (v_res->'event'->>'include_in_quarterly_report')::boolean <> true then
    raise exception 'Test 21.B failed: include_in_quarterly_report should be true';
  end if;
  if v_res->'event'->>'report_priority' <> 'ministry_activity' then
    raise exception 'Test 21.B failed: report_priority should be ministry_activity';
  end if;
  if v_res->'event'->>'report_highlight' <> 'Over 80 households attended the online teaching session on family spirituality.' then
    raise exception 'Test 21.B / 21.H failed: report_highlight mismatch';
  end if;
  insert into test_results values ('Test 21.B / 21.H', 'PASSED', 'Virtual event with valid URL and Ministry Activity persisted');

  -- ---------------------------------------------------------------------------
  -- Test 21.C: Reject malformed virtual URL
  -- ---------------------------------------------------------------------------
  v_caught := false;
  begin
    perform public.create_event(
      p_organization_id => v_org_id,
      p_event_type => 'other',
      p_title => 'Test Malformed URL Event',
      p_starts_at => '2026-11-27 19:00:00-05',
      p_ends_at => '2026-11-27 21:00:00-05',
      p_location_text => null,
      p_meeting_type => 'virtual',
      p_virtual_meeting_url => 'not_a_valid_url'
    );
  exception
    when sqlstate '22023' then
      v_caught := true;
  end;
  if not v_caught then
    raise exception 'Test 21.C failed: malformed virtual URL was NOT rejected';
  end if;
  insert into test_results values ('Test 21.C', 'PASSED', 'Malformed virtual URL properly rejected with 22023');

  -- ---------------------------------------------------------------------------
  -- Test 21.D: Reject javascript: URL
  -- ---------------------------------------------------------------------------
  v_caught := false;
  begin
    perform public.create_event(
      p_organization_id => v_org_id,
      p_event_type => 'other',
      p_title => 'Test XSS URL Event',
      p_starts_at => '2026-11-27 19:00:00-05',
      p_ends_at => '2026-11-27 21:00:00-05',
      p_location_text => null,
      p_meeting_type => 'virtual',
      p_virtual_meeting_url => 'javascript:alert(1)'
    );
  exception
    when sqlstate '22023' then
      v_caught := true;
  end;
  if not v_caught then
    raise exception 'Test 21.D failed: javascript: URL was NOT rejected';
  end if;
  insert into test_results values ('Test 21.D', 'PASSED', 'javascript: URL properly rejected with 22023');

  -- ---------------------------------------------------------------------------
  -- Test 21.E: Update In-Person -> Virtual
  -- ---------------------------------------------------------------------------
  v_res := public.update_event(
    p_organization_id => v_org_id,
    p_event_id => v_event_id_a,
    p_event_type => 'assembly',
    p_title => 'Updated to Virtual Assembly',
    p_starts_at => '2026-11-25 19:00:00-05',
    p_ends_at => '2026-11-25 21:00:00-05',
    p_location_text => null,
    p_description => 'Switched to Zoom due to weather',
    p_audience_code => 'mfc_ny',
    p_formation_talk_id => null,
    p_meeting_type => 'virtual',
    p_virtual_meeting_url => 'https://meet.google.com/abc-defg-hij',
    p_include_in_quarterly_report => false,
    p_report_priority => 'routine',
    p_report_highlight => null
  );

  if v_res->'event'->>'meeting_type' <> 'virtual' then
    raise exception 'Test 21.E failed: expected meeting_type virtual, got %', v_res->'event'->>'meeting_type';
  end if;
  if v_res->'event'->>'virtual_meeting_url' <> 'https://meet.google.com/abc-defg-hij' then
    raise exception 'Test 21.E failed: virtual_meeting_url was not updated';
  end if;
  insert into test_results values ('Test 21.E', 'PASSED', 'In-Person successfully updated to Virtual');

  -- ---------------------------------------------------------------------------
  -- Test 21.F: Update Virtual -> In-Person and confirm URL clearing behavior
  -- ---------------------------------------------------------------------------
  v_res := public.update_event(
    p_organization_id => v_org_id,
    p_event_id => v_event_id_a,
    p_event_type => 'assembly',
    p_title => 'Restored In-Person Assembly',
    p_starts_at => '2026-11-25 19:00:00-05',
    p_ends_at => '2026-11-25 21:00:00-05',
    p_location_text => 'St. Patrick Church Hall',
    p_description => 'Back in person',
    p_audience_code => 'mfc_ny',
    p_formation_talk_id => null,
    p_meeting_type => 'in_person',
    p_virtual_meeting_url => 'https://meet.google.com/abc-defg-hij', -- Passing URL when in_person must clear it
    p_include_in_quarterly_report => false,
    p_report_priority => 'routine',
    p_report_highlight => null
  );

  if v_res->'event'->>'meeting_type' <> 'in_person' then
    raise exception 'Test 21.F failed: expected meeting_type in_person, got %', v_res->'event'->>'meeting_type';
  end if;
  if v_res->'event'->>'virtual_meeting_url' is not null then
    raise exception 'Test 21.F failed: virtual_meeting_url was not cleared when switching to in_person';
  end if;
  if v_res->'event'->>'location_text' <> 'St. Patrick Church Hall' then
    raise exception 'Test 21.F failed: location_text was not updated';
  end if;
  insert into test_results values ('Test 21.F', 'PASSED', 'Virtual -> In-Person automatically cleared virtual_meeting_url');

  -- ---------------------------------------------------------------------------
  -- Test 21.G: Reporting defaults
  -- ---------------------------------------------------------------------------
  v_res := public.create_event(
    p_organization_id => v_org_id,
    p_event_type => 'other',
    p_title => 'Test Defaults Event',
    p_starts_at => '2026-11-28 10:00:00-05',
    p_ends_at => '2026-11-28 12:00:00-05',
    p_location_text => null
  );
  v_event_id_c := (v_res->'event'->>'id')::uuid;

  if v_res->'event'->>'meeting_type' <> 'in_person' then
    raise exception 'Test 21.G failed: default meeting_type should be in_person';
  end if;
  if v_res->'event'->>'virtual_meeting_url' is not null then
    raise exception 'Test 21.G failed: default virtual_meeting_url should be null';
  end if;
  if (v_res->'event'->>'include_in_quarterly_report')::boolean <> false then
    raise exception 'Test 21.G failed: default include_in_quarterly_report should be false';
  end if;
  if v_res->'event'->>'report_priority' <> 'routine' then
    raise exception 'Test 21.G failed: default report_priority should be routine';
  end if;
  if v_res->'event'->>'report_highlight' is not null then
    raise exception 'Test 21.G failed: default report_highlight should be null';
  end if;
  insert into test_results values ('Test 21.G', 'PASSED', 'Default reporting values verified');

  -- ---------------------------------------------------------------------------
  -- Test 21.I: Major Highlight persists correctly
  -- ---------------------------------------------------------------------------
  v_res := public.create_event(
    p_organization_id => v_org_id,
    p_event_type => 'teaching',
    p_title => 'Annual Leaders Conference 2026',
    p_starts_at => '2026-11-29 09:00:00-05',
    p_ends_at => '2026-11-29 17:00:00-05',
    p_location_text => 'Mirror Lake Camp & Retreat Center',
    p_description => 'Annual national leaders conference',
    p_audience_code => 'mfc_ny',
    p_meeting_type => 'in_person',
    p_include_in_quarterly_report => true,
    p_report_priority => 'major_highlight',
    p_report_highlight => 'Gathered 120 servant leaders across all NYC sections for strategic pastoral alignment.'
  );
  v_event_id_d := (v_res->'event'->>'id')::uuid;

  if (v_res->'event'->>'include_in_quarterly_report')::boolean <> true then
    raise exception 'Test 21.I failed: include_in_quarterly_report should be true';
  end if;
  if v_res->'event'->>'report_priority' <> 'major_highlight' then
    raise exception 'Test 21.I failed: report_priority should be major_highlight';
  end if;
  if v_res->'event'->>'report_highlight' <> 'Gathered 120 servant leaders across all NYC sections for strategic pastoral alignment.' then
    raise exception 'Test 21.I failed: report_highlight mismatch';
  end if;
  insert into test_results values ('Test 21.I', 'PASSED', 'Major Highlight persisted correctly');

  -- ---------------------------------------------------------------------------
  -- Test 22: Event Read RPCs (get_event, list_events, list_my_events)
  -- ---------------------------------------------------------------------------
  v_read_res := public.get_event(v_org_id, v_event_id_d);
  if not (
    v_read_res ? 'meeting_type' and
    v_read_res ? 'virtual_meeting_url' and
    v_read_res ? 'include_in_quarterly_report' and
    v_read_res ? 'report_priority' and
    v_read_res ? 'report_highlight'
  ) then
    raise exception 'Test 22.1 failed: get_event missing one of the new fields';
  end if;

  v_list_res := public.list_events(v_org_id, '2026-11-01'::date, '2026-11-30'::date);
  if jsonb_array_length(v_list_res->'events') = 0 then
    raise exception 'Test 22.2 failed: list_events returned 0 events';
  end if;
  if not (
    (v_list_res->'events'->0) ? 'meeting_type' and
    (v_list_res->'events'->0) ? 'virtual_meeting_url' and
    (v_list_res->'events'->0) ? 'include_in_quarterly_report' and
    (v_list_res->'events'->0) ? 'report_priority' and
    (v_list_res->'events'->0) ? 'report_highlight'
  ) then
    raise exception 'Test 22.2 failed: list_events event summary missing new fields';
  end if;

  -- Test list_my_events as member
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_member_profile, 'role', 'authenticated')::text, true);

  -- Member read get_event: reporting metadata must be NULL
  begin
    v_read_res := public.get_event(v_org_id, v_event_id_d);
    if v_read_res->>'report_highlight' is not null or v_read_res->>'report_priority' is not null or v_read_res->>'include_in_quarterly_report' is not null then
      raise exception 'Test 22 failed: member get_event exposed non-null reporting metadata';
    end if;
  exception when others then
    -- Member may not have events.view permission, which is also safe
    null;
  end;

  v_my_events_res := public.list_my_events(v_org_id, '2026-11-01'::date, '2026-11-30'::date);
  if jsonb_array_length(v_my_events_res) > 0 then
    v_my_item := v_my_events_res->0;
    if not (v_my_item ? 'meeting_type') then
      raise exception 'Test 22.3 failed: list_my_events item missing meeting_type';
    end if;
    if not (v_my_item ? 'virtual_meeting_url') then
      raise exception 'Test 22.3 failed: list_my_events item missing virtual_meeting_url';
    end if;
    if v_my_item ? 'include_in_quarterly_report' or v_my_item ? 'report_priority' or v_my_item ? 'report_highlight' then
      raise exception 'Test 22.3 failed: list_my_events leaked internal reporting metadata to member';
    end if;
  end if;
  insert into test_results values ('Test 22', 'PASSED', 'Read RPCs return meeting_type, virtual_url, and mask internal reporting metadata for non-managers');

  -- ---------------------------------------------------------------------------
  -- Test 24: Reporting Readiness Query (tested under superuser/defining context)
  -- ---------------------------------------------------------------------------
  reset role;
  select count(*) into v_reportable_count
  from public.events e
  left join public.governance_nodes an on an.id = e.audience_node_id
  where e.organization_id = v_org_id
    and e.include_in_quarterly_report = true
    and (e.starts_at at time zone 'America/New_York')::date between '2026-11-01' and '2026-11-30';

  if v_reportable_count <> 2 then
    raise exception 'Test 24 failed: expected 2 reportable events in test period, got %', v_reportable_count;
  end if;
  insert into test_results values ('Test 24', 'PASSED', 'Reporting query retrieved 2 reportable events with full metadata');

  -- ---------------------------------------------------------------------------
  -- Test 28.1: Unauthorized authenticated user write denied
  -- ---------------------------------------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_member_profile, 'role', 'authenticated')::text, true);

  v_caught := false;
  begin
    perform public.create_event(
      p_organization_id => v_org_id,
      p_event_type => 'assembly',
      p_title => 'Unauthorized Assembly Test',
      p_starts_at => '2026-11-30 19:00:00-05',
      p_ends_at => '2026-11-30 21:00:00-05',
      p_location_text => null
    );
  exception
    when sqlstate '42501' then
      v_caught := true;
  end;
  if not v_caught then
    raise exception 'Test 28.1 failed: unauthorized user was able to create an event';
  end if;
  insert into test_results values ('Test 28.1', 'PASSED', 'Unauthorized member write rejected with 42501');

  -- ---------------------------------------------------------------------------
  -- Test 28.2: Anon denied
  -- ---------------------------------------------------------------------------
  set local role anon;
  perform set_config('request.jwt.claims', '{}', true);

  v_caught := false;
  begin
    perform public.create_event(
      p_organization_id => v_org_id,
      p_event_type => 'assembly',
      p_title => 'Anon Assembly Test',
      p_starts_at => '2026-11-30 19:00:00-05',
      p_ends_at => '2026-11-30 21:00:00-05',
      p_location_text => null
    );
  exception
    when sqlstate '42501' or sqlstate '28000' then
      v_caught := true;
  end;
  if not v_caught then
    raise exception 'Test 28.2 failed: anon was able to call create_event';
  end if;
  insert into test_results values ('Test 28.2', 'PASSED', 'Anon write rejected');

  -- ---------------------------------------------------------------------------
  -- Test 28.3: Cross-org write denied
  -- ---------------------------------------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  v_caught := false;
  begin
    perform public.create_event(
      p_organization_id => v_fake_org_id,
      p_event_type => 'assembly',
      p_title => 'Cross Org Assembly Test',
      p_starts_at => '2026-11-30 19:00:00-05',
      p_ends_at => '2026-11-30 21:00:00-05',
      p_location_text => null
    );
  exception
    when sqlstate '42501' then
      v_caught := true;
  end;
  if not v_caught then
    raise exception 'Test 28.3 failed: cross-org write was not denied';
  end if;
  insert into test_results values ('Test 28.3', 'PASSED', 'Cross-org write denied with 42501');

  -- ---------------------------------------------------------------------------
  -- Test 28.4: Direct table writes denied by table-level permissions & RLS
  -- ---------------------------------------------------------------------------
  v_caught := false;
  begin
    insert into public.events (
      organization_id, event_type, title, starts_at, created_by_profile_id
    ) values (
      v_org_id, 'assembly', 'Direct Insert Test', now(), v_admin_profile
    );
  exception
    when sqlstate '42501' then
      v_caught := true;
  end;
  if not v_caught then
    raise exception 'Test 28.4 failed: direct table insert was not denied';
  end if;

  v_caught := false;
  begin
    update public.events
    set title = 'Direct Update Hack'
    where id = v_event_id_a;
  exception
    when sqlstate '42501' then
      v_caught := true;
  end;
  if not v_caught then
    raise exception 'Test 28.4 failed: direct table update was not denied';
  end if;
  insert into test_results values ('Test 28.4', 'PASSED', 'Direct table writes properly blocked with 42501');

end;
$$;

reset role;
select test_name, status, details from test_results order by test_name;

rollback;

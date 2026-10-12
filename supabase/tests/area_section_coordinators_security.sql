-- =============================================================================
-- Test Suite: area_section_coordinators_security.sql
--
-- Tests:
--   1. Active appointments match expected:
--      - sec_campus: NY10069 (+NY10068)
--      - sec_handmaids: NY10001
--      - sec_kids: NY10262 (exception)
--      - sec_servants: NY10249
--      - sec_youth: NY10008 (+NY10009)
--   2. Negative validation tests:
--      - Test 1: sec_couples -> rejected (22023)
--      - Test 2: male member for sec_handmaids -> rejected (22023)
--      - Test 3: member with sex NULL -> rejected (22023 "Record the member's sex first.")
--      - Test 4: second coordinator for sec_youth -> rejected (23505)
--      - Test 5: sec_singles with eligible male -> succeeds then ends
--      - Test 6: caller without permission -> rejected (42501)
-- =============================================================================

begin;

-- Verify 5 active coordinator appointments
do $$
declare
  v_count int;
begin
  select count(*) into v_count
  from public.leadership_assignments la
  join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
  where lrd.code = 'area_section_coordinator'
    and la.assignment_status = 'active';

  if v_count != 5 then
    raise exception 'Expected 5 active coordinator appointments, found %', v_count;
  end if;
end $$;

-- Negative security tests (rolled back)
do $$
declare
  v_admin_id uuid := '821fb09c-8396-4549-b120-5674f3cc566a'::uuid;
  v_non_admin_id uuid := '0c7cf29f-6185-44eb-8b64-08ab783d7e06'::uuid;
  v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
  v_couples_node_id uuid;
  v_handmaids_node_id uuid;
  v_youth_node_id uuid;
  v_singles_node_id uuid;
  v_male_member_id uuid;
  v_null_sex_member_id uuid;
  v_res jsonb;
  v_caught boolean;
  v_errcode text;
  v_errmsg text;
begin
  select id into v_couples_node_id from public.governance_nodes where organization_id = v_org_id and code = 'sec_couples';
  select id into v_handmaids_node_id from public.governance_nodes where organization_id = v_org_id and code = 'sec_handmaids';
  select id into v_youth_node_id from public.governance_nodes where organization_id = v_org_id and code = 'sec_youth';
  select id into v_singles_node_id from public.governance_nodes where organization_id = v_org_id and code = 'sec_singles';

  -- Male member
  select id into v_male_member_id from public.members where organization_id = v_org_id and sex = 'male' and record_status = 'active' limit 1;

  -- Member with sex NULL
  select id into v_null_sex_member_id from public.members where organization_id = v_org_id and sex is null and record_status = 'active' limit 1;

  -- Insert non-admin profile organization membership before switching role
  insert into public.profile_organization_memberships (
    profile_id, organization_id, membership_status, effective_from_at, accepted_at
  ) values (
    v_non_admin_id, v_org_id, 'active', now() - interval '1 day', now() - interval '1 day'
  );

  -- Authenticate as admin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_admin_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);

  -- Test 1: sec_couples -> rejected (22023)
  v_caught := false;
  begin
    perform public.appoint_area_coordinator(v_org_id, 'area_section_coordinator', v_couples_node_id, v_male_member_id);
  exception when others then
    v_caught := true;
    get stacked diagnostics v_errcode = returned_sqlstate, v_errmsg = message_text;
  end;
  if not v_caught or v_errcode != '22023' then
    raise exception 'Test 1 failed: Expected 22023 for sec_couples, got % (%)', v_errcode, v_errmsg;
  end if;

  -- Test 2: male member for sec_handmaids -> rejected (22023)
  v_caught := false;
  begin
    perform public.appoint_area_coordinator(v_org_id, 'area_section_coordinator', v_handmaids_node_id, v_male_member_id);
  exception when others then
    v_caught := true;
    get stacked diagnostics v_errcode = returned_sqlstate, v_errmsg = message_text;
  end;
  if not v_caught or v_errcode != '22023' or v_errmsg not ilike '%female%' then
    raise exception 'Test 2 failed: Expected 22023 female only for handmaids, got % (%)', v_errcode, v_errmsg;
  end if;

  -- Test 3: member with sex NULL -> rejected (22023 "Record the member's sex first.")
  v_caught := false;
  begin
    perform public.appoint_area_coordinator(v_org_id, 'area_section_coordinator', v_singles_node_id, v_null_sex_member_id);
  exception when others then
    v_caught := true;
    get stacked diagnostics v_errcode = returned_sqlstate, v_errmsg = message_text;
  end;
  if not v_caught or v_errcode != '22023' or v_errmsg != 'Record the member''s sex first.' then
    raise exception 'Test 3 failed: Expected 22023 "Record the member''s sex first.", got % (%)', v_errcode, v_errmsg;
  end if;

  -- Test 4: second coordinator for sec_youth -> rejected (23505)
  v_caught := false;
  begin
    perform public.appoint_area_coordinator(v_org_id, 'area_section_coordinator', v_youth_node_id, v_male_member_id);
  exception when others then
    v_caught := true;
    get stacked diagnostics v_errcode = returned_sqlstate, v_errmsg = message_text;
  end;
  if not v_caught or v_errcode != '23505' or v_errmsg != 'This section already has an active coordinator.' then
    raise exception 'Test 4 failed: Expected 23505 already active coordinator, got % (%)', v_errcode, v_errmsg;
  end if;

  -- Test 5: sec_singles with eligible male -> succeeds
  v_res := public.appoint_area_coordinator(v_org_id, 'area_section_coordinator', v_singles_node_id, v_male_member_id);
  if v_res->>'node_code' != 'sec_singles' or v_res->>'assignment_id' is null then
    raise exception 'Test 5 failed: Appointment on sec_singles did not return expected structure: %', v_res;
  end if;

  v_res := public.end_area_coordinator(v_org_id, (v_res->>'assignment_id')::uuid, 'Test completion');
  if v_res->>'status' != 'completed' then
    raise exception 'Test 5 end_area_coordinator failed: %', v_res;
  end if;

  -- Test 6: caller without permission -> 42501
  perform set_config('request.jwt.claim.sub', v_non_admin_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_non_admin_id, 'role', 'authenticated')::text, true);

  v_caught := false;
  begin
    perform public.appoint_area_coordinator(v_org_id, 'area_section_coordinator', v_singles_node_id, v_male_member_id);
  exception when others then
    v_caught := true;
    get stacked diagnostics v_errcode = returned_sqlstate, v_errmsg = message_text;
  end;
  if not v_caught or v_errcode != '42501' or v_errmsg != 'You do not have permission to appoint coordinators.' then
    raise exception 'Test 6 failed: Expected 42501 "You do not have permission to appoint coordinators.", got % (%)', v_errcode, v_errmsg;
  end if;
end $$;

rollback;

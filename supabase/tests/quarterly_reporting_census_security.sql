-- =============================================================================
-- Test Suite: Pass 9.46 / 9.46W — Quarterly Reporting & Census Snapshot Security & Logic
-- All mutations executed within a rolled-back transaction.
-- =============================================================================

begin;

do $$
declare
  v_org_id             uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_admin_profile      uuid := '821fb09c-8396-4549-b120-5674f3cc566a'; -- Ron Acosta (org admin)
  v_member_profile     uuid := 'f614188a-51bf-4aea-9fbd-de6f1f49f863'; -- Alan Ybay (non-admin leader)
  v_fake_org_id        uuid := '11111111-2222-3333-4444-555555555555';
  v_test_role_profile  uuid := 'f614188a-51bf-4aea-9fbd-de6f1f49f863';
  v_preview            jsonb;
  v_period_res         jsonb;
  v_period_id          uuid;
  v_snapshot_res       jsonb;
  v_status_res         jsonb;
  v_approved_res       jsonb;
  v_sec_row            record;
  v_sum_sec            integer := 0;
  v_test_member_id     uuid;
  v_snapshot_before    integer;
  v_snapshot_after     integer;
  v_caught             boolean;
  v_active_status_id   uuid;
  v_role_id            uuid;
  v_test_roles         text[] := array['area_servant', 'chapter_servant', 'section_coordinator', 'unit_servant', 'pastoral_worker', 'member'];
  v_curr_role          text;
begin
  raise notice '=== Starting Pass 9.46 / 9.46W Test Suite ===';

  select id into v_active_status_id from public.member_statuses where code = 'active';

  -- ---------------------------------------------------------------------------
  -- 1. Check Admin Permissions via private.effective_permission_state (as superuser)
  -- ---------------------------------------------------------------------------
  if private.effective_permission_state(v_admin_profile, v_org_id, 'reports.census.view', now()) <> 'allow' then
    raise exception 'Admin permission check failed: reports.census.view is not allow';
  end if;
  if private.effective_permission_state(v_admin_profile, v_org_id, 'reports.census.manage', now()) <> 'allow' then
    raise exception 'Admin permission check failed: reports.census.manage is not allow';
  end if;
  if private.effective_permission_state(v_admin_profile, v_org_id, 'reports.census.approve', now()) <> 'allow' then
    raise exception 'Admin permission check failed: reports.census.approve is not allow';
  end if;
  raise notice 'Admin permissions check PASSED: view, manage, approve all allow';

  -- ---------------------------------------------------------------------------
  -- 2. Organization Administrator Access & Census Calculation Tests
  -- ---------------------------------------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- Test A: Preview census totals
  v_preview := public.get_quarterly_census_preview(v_org_id, 2026, 3);
  raise notice 'Preview Q3 total_active: %, uncategorized: %',
    v_preview->>'total_active_members', v_preview->>'uncategorized_active_members';

  if (v_preview->>'total_active_members')::integer <> 309 then
    raise exception 'Test A failed: expected total active 309, got %', v_preview->>'total_active_members';
  end if;

  -- Test B: Section totals reconcile to active-member total
  v_sum_sec := 0;
  for v_sec_row in (
    select (value->>'current_count')::integer as cnt
    from jsonb_array_elements(v_preview->'sections')
  ) loop
    v_sum_sec := v_sum_sec + v_sec_row.cnt;
  end loop;

  if (v_sum_sec + (v_preview->>'uncategorized_active_members')::integer) <> (v_preview->>'total_active_members')::integer then
    raise exception 'Test B failed: reconciliation failure: sum_sec % + uncategorized % <> total %',
      v_sum_sec, v_preview->>'uncategorized_active_members', v_preview->>'total_active_members';
  end if;
  raise notice 'Test A & B PASSED: reconciled % sections + % uncategorized = % total',
    v_sum_sec, v_preview->>'uncategorized_active_members', v_preview->>'total_active_members';

  -- Test C: Uncategorized count explicit
  if not (v_preview ? 'uncategorized_active_members') then
    raise exception 'Test C failed: uncategorized_active_members key missing';
  end if;
  if (v_preview->>'uncategorized_active_members')::integer <> 0 then
    raise exception 'Test C failed: expected 0 uncategorized, got %', v_preview->>'uncategorized_active_members';
  end if;
  raise notice 'Test C PASSED: uncategorized_active_members is %', v_preview->>'uncategorized_active_members';

  -- Test E: Authorized report manager/admin can create draft period
  v_period_res := public.create_draft_reporting_period(v_org_id, 2026, 3, 'Q3 2026 Draft Test');
  v_period_id := (v_period_res->'period'->>'id')::uuid;

  if v_period_id is null or v_period_res->'period'->>'status' <> 'draft' then
    raise exception 'Test E failed: draft period not created properly: %', v_period_res;
  end if;
  if (v_period_res->'snapshot'->>'total_active_members')::integer <> 309 then
    raise exception 'Test E failed: initial snapshot total expected 309, got %',
      v_period_res->'snapshot'->>'total_active_members';
  end if;
  raise notice 'Test E PASSED: created draft period % with initial snapshot', v_period_id;

  -- Test F: Authorized user can capture draft snapshot
  v_snapshot_res := public.capture_quarterly_census_snapshot(v_period_id);
  if (v_snapshot_res->'snapshot'->>'total_active_members')::integer <> 309 then
    raise exception 'Test F failed: captured snapshot total expected 309, got %',
      v_snapshot_res->'snapshot'->>'total_active_members';
  end if;
  raise notice 'Test F PASSED: captured draft snapshot successfully';

  -- Test G: Draft snapshot can be refreshed
  v_snapshot_res := public.capture_quarterly_census_snapshot(v_period_id);
  if (v_snapshot_res->'snapshot'->>'total_active_members')::integer <> 309 then
    raise exception 'Test G failed: refreshed snapshot total expected 309, got %',
      v_snapshot_res->'snapshot'->>'total_active_members';
  end if;
  raise notice 'Test G PASSED: draft snapshot refreshed successfully';

  -- Test H: Review status prevents silent refresh as designed
  v_status_res := public.set_reporting_period_status(v_period_id, 'review');
  if v_status_res->'period'->>'status' <> 'review' then
    raise exception 'Test H failed: period status not moved to review';
  end if;

  v_caught := false;
  begin
    perform public.capture_quarterly_census_snapshot(v_period_id);
  exception when others then
    v_caught := true;
    raise notice 'Caught expected error refreshing in review status: %', sqlerrm;
  end;

  if not v_caught then
    raise exception 'Test H failed: snapshot refreshed while in review status!';
  end if;
  raise notice 'Test H PASSED: review status prevented refresh';

  -- Test I: Approved status freezes snapshot
  v_approved_res := public.set_reporting_period_status(v_period_id, 'approved');
  if v_approved_res->'period'->>'status' <> 'approved' then
    raise exception 'Test I failed: period status not moved to approved';
  end if;
  if v_approved_res->'period'->>'approved_at' is null then
    raise exception 'Test I failed: approved_at not recorded';
  end if;

  -- Attempt to refresh approved snapshot -> must fail
  v_caught := false;
  begin
    perform public.capture_quarterly_census_snapshot(v_period_id);
  exception when others then
    v_caught := true;
    raise notice 'Caught expected error refreshing approved period: %', sqlerrm;
  end;

  if not v_caught then
    raise exception 'Test I failed: snapshot refreshed on approved period!';
  end if;

  -- Attempt to return approved period to draft -> must fail
  v_caught := false;
  begin
    perform public.set_reporting_period_status(v_period_id, 'draft');
  exception when others then
    v_caught := true;
    raise notice 'Caught expected error returning approved period to draft: %', sqlerrm;
  end;

  if not v_caught then
    raise exception 'Test I failed: approved period returned to draft!';
  end if;
  raise notice 'Test I PASSED: approved status successfully froze snapshot';

  -- Test J: Approved snapshot remains unchanged after synthetic membership change
  v_snapshot_before := (v_approved_res->'snapshot'->>'total_active_members')::integer;

  -- Temporarily switch to postgres role to insert synthetic test member
  reset role;

  insert into public.members (
    organization_id,
    display_name,
    sort_name,
    preferred_name,
    record_status,
    membership_status_id,
    primary_section_node_id
  )
  values (
    v_org_id,
    'Synthetic Tester',
    'Tester, Synthetic',
    'Synthetic',
    'active',
    v_active_status_id,
    '5064d66e-f217-42e3-9594-fa56843c453d' -- MFC Couples
  )
  returning id into v_test_member_id;

  -- Switch back to authenticated admin
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  -- Verify live preview increased to 310
  v_preview := public.get_quarterly_census_preview(v_org_id, 2026, 3);
  if (v_preview->>'total_active_members')::integer <> 310 then
    raise exception 'Test J failed: live preview expected 310, got %', v_preview->>'total_active_members';
  end if;

  -- Verify frozen approved report remains 309
  v_snapshot_res := public.get_reporting_period(v_period_id);
  v_snapshot_after := (v_snapshot_res->'snapshot'->>'total_active_members')::integer;

  if v_snapshot_after <> v_snapshot_before then
    raise exception 'Test J failed: approved snapshot changed from % to %',
      v_snapshot_before, v_snapshot_after;
  end if;
  raise notice 'Test J PASSED: approved snapshot remained frozen at % while live count moved to %',
    v_snapshot_after, v_preview->>'total_active_members';

  -- ---------------------------------------------------------------------------
  -- 3. Authorization Closure Tests (Pass 9.46W)
  -- ---------------------------------------------------------------------------
  reset role;

  -- Clean up existing scope/role assignments on test profile for clean role tests
  delete from public.profile_scope_assignments
  where profile_role_assignment_id in (
    select id from public.profile_role_assignments where profile_id = v_test_role_profile
  );
  delete from public.profile_role_assignments where profile_id = v_test_role_profile;

  -- Test each non-admin role individually
  foreach v_curr_role in array v_test_roles loop
    select id into v_role_id from public.app_roles where code = v_curr_role;

    if v_role_id is not null then
      delete from public.profile_scope_assignments
      where profile_role_assignment_id in (
        select id from public.profile_role_assignments where profile_id = v_test_role_profile
      );
      delete from public.profile_role_assignments where profile_id = v_test_role_profile;

      insert into public.profile_role_assignments (
        profile_id,
        app_role_id,
        organization_id,
        assignment_status,
        effective_from_at,
        activated_at,
        approved_at
      )
      values (
        v_test_role_profile,
        v_role_id,
        v_org_id,
        'active',
        now(),
        now(),
        now()
      );

      -- Verify effective permission is 'none' / not allow
      if private.effective_permission_state(v_test_role_profile, v_org_id, 'reports.census.view', now()) = 'allow' then
        raise exception 'Pass 9.46W authorization failure: role % has reports.census.view allow!', v_curr_role;
      end if;

      -- Impersonate this user under authenticated role
      set local role authenticated;
      perform set_config('request.jwt.claims', json_build_object('sub', v_test_role_profile, 'role', 'authenticated')::text, true);

      -- Assert get_quarterly_census_preview is denied with 42501
      v_caught := false;
      begin
        perform public.get_quarterly_census_preview(v_org_id, 2026, 3);
      exception when sqlstate '42501' then
        v_caught := true;
      end;
      if not v_caught then
        raise exception 'Pass 9.46W authorization failure: role % was able to run get_quarterly_census_preview!', v_curr_role;
      end if;

      -- Assert list_reporting_periods is denied with 42501
      v_caught := false;
      begin
        perform public.list_reporting_periods(v_org_id);
      exception when sqlstate '42501' then
        v_caught := true;
      end;
      if not v_caught then
        raise exception 'Pass 9.46W authorization failure: role % was able to run list_reporting_periods!', v_curr_role;
      end if;

      -- Assert get_reporting_period is denied with 42501
      v_caught := false;
      begin
        perform public.get_reporting_period(v_period_id);
      exception when sqlstate '42501' then
        v_caught := true;
      end;
      if not v_caught then
        raise exception 'Pass 9.46W authorization failure: role % was able to run get_reporting_period!', v_curr_role;
      end if;

      raise notice 'Pass 9.46W: Role % successfully denied organization-wide census view (42501)', v_curr_role;
      reset role;
    end if;
  end loop;

  -- ---------------------------------------------------------------------------
  -- Test K: Anon denied
  -- ---------------------------------------------------------------------------
  set local role anon;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);

  v_caught := false;
  begin
    perform public.get_quarterly_census_preview(v_org_id, 2026, 3);
  exception when sqlstate '28000' or sqlstate '42501' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test K failed: anon accessed get_quarterly_census_preview!';
  end if;
  raise notice 'Test K PASSED: anon denied access with 28000';

  -- ---------------------------------------------------------------------------
  -- Test L: Cross-org access denied
  -- ---------------------------------------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_profile, 'role', 'authenticated')::text, true);

  v_caught := false;
  begin
    perform public.get_quarterly_census_preview(v_fake_org_id, 2026, 3);
  exception when sqlstate '42501' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test L failed: cross-org access allowed!';
  end if;
  raise notice 'Test L PASSED: cross-org access denied with 42501';

  -- ---------------------------------------------------------------------------
  -- Test M: Direct table writes denied to ordinary authenticated users
  -- ---------------------------------------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_member_profile, 'role', 'authenticated')::text, true);

  v_caught := false;
  begin
    insert into public.ministry_reporting_periods (
      organization_id, report_type, period_year, period_quarter, period_start, period_end, status
    )
    values (
      v_org_id, 'quarterly_national', 2026, 4, '2026-10-01', '2026-12-31', 'draft'
    );
  exception when sqlstate '42501' then
    v_caught := true;
  end;

  if not v_caught then
    raise exception 'Test M failed: direct table insert succeeded for authenticated user!';
  end if;
  raise notice 'Test M PASSED: direct table writes denied to authenticated users with 42501';

  raise notice '=== ALL PASS 9.46 / 9.46W DATABASE TESTS PASSED! ===';
end;
$$;

rollback;

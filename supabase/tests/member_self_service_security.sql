-- =============================================================================
-- Security Tests: member_self_service_security.sql
-- Feature:        Member Self-Service Foundation
--                 (members.self_service.view, get_my_member_context,
--                  get_my_member_profile)
--
-- Non-destructive. All synthetic fixtures are created inside a transaction
-- and strictly ROLLED BACK.
-- =============================================================================

-- =============================================================================
-- PART 1: STATIC POSTURE (permission, role mapping, ACLs)
-- =============================================================================

DO $$
DECLARE
  v_count integer;
BEGIN
  -- 1.1 Permission registered
  SELECT count(*) INTO v_count FROM public.permissions
  WHERE code = 'members.self_service.view' AND domain_code = 'members'
    AND action_code = 'view' AND is_active;
  ASSERT v_count = 1, format('PART 1.1 FAILED: permission count %s', v_count);
  RAISE NOTICE 'PART 1.1 PASSED: members.self_service.view registered';

  -- 1.2 Mapped to the system member role
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'members.self_service.view' AND ar.code = 'member'
    AND rp.permission_effect = 'allow' AND rp.approval_status = 'approved';
  ASSERT v_count = 1, format('PART 1.2 FAILED: member role mapping count %s', v_count);
  RAISE NOTICE 'PART 1.2 PASSED: permission mapped to member role';

  -- 1.3 Member role gained ONLY the self-service permission (test I)
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE ar.code = 'member';
  ASSERT v_count = 1, format('PART 1.3 FAILED: member role has %s permission rows (expected 1)', v_count);

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE ar.code = 'member'
    AND p.code IN ('members.records.view', 'members.households.view',
                   'leadership.pastoral_dashboard.view', 'households.records.view');
  ASSERT v_count = 0, 'PART 1.3 FAILED: member role gained a broad permission';
  RAISE NOTICE 'PART 1.3 PASSED: member role has only members.self_service.view';

  -- 1.4 Self-service permission is NOT granted to any other role (narrow)
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'members.self_service.view' AND ar.code <> 'member';
  ASSERT v_count = 0, format('PART 1.4 FAILED: granted to %s other role rows', v_count);
  RAISE NOTICE 'PART 1.4 PASSED: no other role holds members.self_service.view';

  -- 1.5 RPCs exist, no p_member_id parameter (test C)
  SELECT count(*) INTO v_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name IN ('get_my_member_context', 'get_my_member_profile');
  ASSERT v_count = 2, format('PART 1.5 FAILED: expected 2 RPCs, found %s', v_count);

  SELECT count(*) INTO v_count
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname IN ('get_my_member_context', 'get_my_member_profile')
    AND (pg_get_function_identity_arguments(p.oid) <> 'p_organization_id uuid');
  ASSERT v_count = 0, 'PART 1.5 FAILED: an RPC accepts more than p_organization_id';
  RAISE NOTICE 'PART 1.5 PASSED: RPCs accept only p_organization_id (no member_id input)';

  -- 1.6 ACLs (test G)
  ASSERT NOT has_function_privilege('anon', 'public.get_my_member_context(uuid)', 'EXECUTE'),
    'PART 1.6 FAILED: anon can execute get_my_member_context';
  ASSERT NOT has_function_privilege('anon', 'public.get_my_member_profile(uuid)', 'EXECUTE'),
    'PART 1.6 FAILED: anon can execute get_my_member_profile';
  ASSERT has_function_privilege('authenticated', 'public.get_my_member_context(uuid)', 'EXECUTE'),
    'PART 1.6 FAILED: authenticated cannot execute get_my_member_context';
  ASSERT has_function_privilege('authenticated', 'public.get_my_member_profile(uuid)', 'EXECUTE'),
    'PART 1.6 FAILED: authenticated cannot execute get_my_member_profile';

  SELECT count(*) INTO v_count
  FROM information_schema.routine_privileges
  WHERE routine_schema = 'public'
    AND routine_name IN ('get_my_member_context', 'get_my_member_profile')
    AND grantee = 'PUBLIC';
  ASSERT v_count = 0, 'PART 1.6 FAILED: PUBLIC holds EXECUTE';

  ASSERT NOT has_function_privilege('authenticated', 'private.assert_member_self_service(uuid)', 'EXECUTE'),
    'PART 1.6 FAILED: authenticated can execute private.assert_member_self_service';
  ASSERT NOT has_function_privilege('authenticated', 'private.build_member_self_context(uuid, uuid)', 'EXECUTE'),
    'PART 1.6 FAILED: authenticated can execute private.build_member_self_context';
  RAISE NOTICE 'PART 1.6 PASSED: no PUBLIC/anon; private helpers not callable by API roles';

  -- 1.7 Hardened search_path
  SELECT count(*) INTO v_count
  FROM pg_proc p
  WHERE ((p.pronamespace = 'public'::regnamespace
          AND p.proname IN ('get_my_member_context', 'get_my_member_profile'))
      OR (p.pronamespace = 'private'::regnamespace
          AND p.proname IN ('assert_member_self_service', 'build_member_self_context')))
    AND p.prosecdef
    AND p.proconfig::text LIKE '%search_path=pg_catalog, public, private, auth%';
  ASSERT v_count = 4, format('PART 1.7 FAILED: hardened definer count %s (expected 4)', v_count);
  RAISE NOTICE 'PART 1.7 PASSED: SECURITY DEFINER with hardened search_path';
END $$;

-- =============================================================================
-- PART 2: BEHAVIOUR (BEGIN ... ROLLBACK)
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_org_id        uuid;
  v_org_b         uuid := gen_random_uuid();
  v_member_role   uuid;
  v_admin_role    uuid;
  v_admin_id      uuid;
  v_member_id     uuid := '99235c89-3ea9-4866-af00-1ec5932cd410';
  v_unit_node_id  uuid := 'dcc74b6b-ee5e-41cd-a836-b939c143060c';
  v_hh_type_id    uuid := '9e686cf6-b4fc-4eb0-b25c-0029f0147967';
  v_hh_id         uuid := 'a0000000-0000-0000-0000-0000000000f1';
  v_self          uuid := gen_random_uuid();  -- plain member, linked
  v_unlinked      uuid := gen_random_uuid();  -- member role, no link
  v_noperm        uuid := gen_random_uuid();  -- linked, no member role
  v_res           jsonb;
  v_code          text;
  v_count         integer;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  SELECT id INTO v_member_role FROM public.app_roles WHERE code = 'member';
  SELECT id INTO v_admin_role  FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT pra.profile_id INTO v_admin_id
  FROM public.profile_role_assignments pra
  WHERE pra.app_role_id = v_admin_role AND pra.organization_id = v_org_id
    AND pra.assignment_status = 'active' LIMIT 1;

  -- ---------------------------------------------------------------------
  -- Synthetic profiles
  -- ---------------------------------------------------------------------
  INSERT INTO auth.users (id, aud, role, email) VALUES
    (v_self,     'authenticated', 'authenticated', 'self_member@test.local'),
    (v_unlinked, 'authenticated', 'authenticated', 'unlinked_member@test.local'),
    (v_noperm,   'authenticated', 'authenticated', 'noperm_member@test.local');
  INSERT INTO public.profiles (id, display_name) VALUES
    (v_self, 'Self Member'), (v_unlinked, 'Unlinked Member'), (v_noperm, 'NoPerm Member');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  SELECT p, v_org_id, 'active', now() FROM unnest(ARRAY[v_self, v_unlinked, v_noperm]) p;

  -- member role only for self + unlinked (system role: organization_id may be null)
  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status,
    proposed_at, approved_at, activated_at, effective_from_at
  )
  SELECT p, v_org_id, v_member_role, 'active', now(), now(), now(), now()
  FROM unnest(ARRAY[v_self, v_unlinked]) p;

  -- verified self links for self + noperm
  INSERT INTO public.profile_member_links (
    profile_id, organization_id, member_id, link_type, link_status,
    is_primary, verification_method, verified_at, verified_by_profile_id, verification_summary
  )
  SELECT p, v_org_id, v_member_id, 'self', 'verified', true, 'admin_verified', now(), v_admin_id, 'synthetic test link'
  FROM unnest(ARRAY[v_self]) p;

  -- noperm links to a different member so the unique member link stays valid
  INSERT INTO public.profile_member_links (
    profile_id, organization_id, member_id, link_type, link_status,
    is_primary, verification_method, verified_at, verified_by_profile_id, verification_summary
  )
  SELECT v_noperm, v_org_id, m.id, 'self', 'verified', true, 'admin_verified', now(), v_admin_id, 'synthetic test link'
  FROM public.members m
  WHERE m.organization_id = v_org_id AND m.id <> v_member_id AND m.archived_at IS NULL
  LIMIT 1;

  -- ---------------------------------------------------------------------
  -- Test A/B (no household): linked member reads own context + profile
  -- ---------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_self::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_self, 'role', 'authenticated')::text, true);

  v_res := public.get_my_member_context(v_org_id);
  ASSERT (v_res->'member'->>'member_id')::uuid = v_member_id,
    'Test A FAILED: context did not return own member';
  ASSERT v_res->'household' = 'null'::jsonb,
    'Test A FAILED: expected null household when none exists';
  ASSERT v_res->'organizational_context' ? 'unit',
    'Test A FAILED: organizational_context missing keys';
  RAISE NOTICE 'Test A PASSED: plain member reads own context (no household => null)';

  v_res := public.get_my_member_profile(v_org_id);
  ASSERT (v_res->'member'->>'member_id')::uuid = v_member_id,
    'Test B FAILED: profile did not return own member';
  ASSERT v_res ? 'contact' AND v_res ? 'details',
    'Test B FAILED: profile payload missing contact/details';
  RAISE NOTICE 'Test B PASSED: plain member reads own profile';

  -- ---------------------------------------------------------------------
  -- Payload privacy: no roles/permissions/scopes/audit keys
  -- ---------------------------------------------------------------------
  ASSERT NOT (v_res ? 'roles' OR v_res ? 'permissions' OR v_res ? 'scopes'
              OR v_res ? 'audit' OR v_res ? 'access_grants'),
    'Privacy FAILED: sensitive key present in profile payload';
  RAISE NOTICE 'Privacy PASSED: no roles/permissions/scopes/audit in payload';

  -- ---------------------------------------------------------------------
  -- Household context (synthetic household inside the transaction)
  -- ---------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, name, code, lifecycle_status, effective_from)
  VALUES (v_hh_id, v_org_id, v_hh_type_id, 'Synthetic Self-Service Household', 'ss_synth_hh', 'active', current_date);
  INSERT INTO public.households (id, organization_id, household_category, meeting_frequency, meeting_day_of_week, meeting_start_time, meeting_timezone_name, meeting_location_type, target_member_count, maximum_member_count, accepts_new_members)
  VALUES (v_hh_id, v_org_id, 'pastoral', 'weekly', 5, '19:30:00'::time, 'America/New_York', 'residence', 8, 12, true);
  INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, is_primary, relationship_status, effective_from)
  VALUES (v_org_id, v_unit_node_id, v_hh_id, 'primary_parent', true, 'active', current_date);
  INSERT INTO public.household_memberships (organization_id, member_id, household_node_id, membership_status, membership_role, is_primary, effective_from)
  VALUES (v_org_id, v_member_id, v_hh_id, 'active', 'member', true, current_date);

  PERFORM set_config('role', 'authenticated', true);
  v_res := public.get_my_member_context(v_org_id);
  ASSERT v_res->'household'->>'household_name' = 'Synthetic Self-Service Household',
    'Test A2 FAILED: household not returned';
  ASSERT v_res->'organizational_context'->>'unit' IS NOT NULL,
    'Test A2 FAILED: unit ancestry not derived';
  ASSERT NOT (v_res->'household' ? 'household_code'),
    'Test A2 FAILED: unexpected household_code in payload';
  RAISE NOTICE 'Test A2 PASSED: own household and unit ancestry returned';

  -- ---------------------------------------------------------------------
  -- Test C: cannot request another member (extra arg is not accepted)
  -- ---------------------------------------------------------------------
  BEGIN
    EXECUTE format('SELECT public.get_my_member_context(%L::uuid, %L::uuid)', v_org_id, gen_random_uuid());
    RAISE EXCEPTION 'Test C FAILED: RPC accepted a second (member) argument';
  EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'Test C PASSED: no member_id parameter exists';
  END;

  -- ---------------------------------------------------------------------
  -- Test D: another organization
  -- ---------------------------------------------------------------------
  BEGIN
    PERFORM public.get_my_member_context(v_org_b);
    RAISE EXCEPTION 'Test D FAILED: other-org call succeeded';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'Test D PASSED: other organization denied (42501)';
  END;

  -- ---------------------------------------------------------------------
  -- Test E: member role but no verified link
  -- ---------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_unlinked::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_unlinked, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.get_my_member_context(v_org_id);
    RAISE EXCEPTION 'Test E FAILED: unlinked profile succeeded';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    RAISE NOTICE 'Test E PASSED: unlinked profile denied (P0002)';
  END;
  BEGIN
    PERFORM public.get_my_member_profile(v_org_id);
    RAISE EXCEPTION 'Test E2 FAILED: unlinked profile succeeded on profile';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    RAISE NOTICE 'Test E2 PASSED: unlinked profile denied on profile RPC';
  END;

  -- Linked but WITHOUT the self-service permission
  PERFORM set_config('request.jwt.claim.sub', v_noperm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_noperm, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.get_my_member_context(v_org_id);
    RAISE EXCEPTION 'Test E3 FAILED: caller without permission succeeded';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'Test E3 PASSED: linked caller without permission denied (42501)';
  END;

  -- ---------------------------------------------------------------------
  -- Test F: unauthenticated
  -- ---------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    PERFORM public.get_my_member_context(v_org_id);
    RAISE EXCEPTION 'Test F FAILED: unauthenticated call succeeded';
  EXCEPTION WHEN SQLSTATE '28000' THEN
    RAISE NOTICE 'Test F PASSED: unauthenticated denied (28000)';
  END;

  -- ---------------------------------------------------------------------
  -- Test I/J: plain member still cannot use the broad existing RPCs
  -- ---------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_self::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_self, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.get_member_households(v_org_id, v_member_id);
    RAISE EXCEPTION 'Test I FAILED: plain member could call get_member_households';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'Test I PASSED: get_member_households still denied for plain member';
  END;
  BEGIN
    PERFORM public.get_member_profile(v_org_id, v_member_id);
    RAISE EXCEPTION 'Test I2 FAILED: plain member could call get_member_profile';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'Test I2 PASSED: get_member_profile still denied for plain member';
  END;
  PERFORM set_config('role', 'postgres', true);
  ASSERT private.has_permission('members.records.view', v_org_id) = false
     AND private.has_permission('members.households.view', v_org_id) = false,
    'Test I3 FAILED: plain member holds a broad permission';
  RAISE NOTICE 'Test I3 PASSED: plain member holds neither broad permission';

  -- ---------------------------------------------------------------------
  -- Test H/J: admin behaviour unchanged
  -- ---------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);
  v_res := public.get_member_households(v_org_id, v_member_id);
  ASSERT jsonb_array_length(v_res) = 1, 'Test H FAILED: admin get_member_households changed';
  v_res := public.get_pastoral_operations_dashboard(v_org_id, NULL);
  ASSERT v_res ? 'meeting_operations_summary', 'Test H FAILED: admin dashboard changed';
  PERFORM set_config('role', 'postgres', true);
  ASSERT private.can_access_member('members.records.view', v_org_id, v_member_id),
    'Test J FAILED: can_access_member changed for admin';
  RAISE NOTICE 'Test H/J PASSED: admin APIs and can_access_member unchanged';

  PERFORM set_config('role', 'authenticated', true);
  -- Admin with no self link is denied by self-service (no implicit identity)
  BEGIN
    PERFORM public.get_my_member_context(v_org_id);
    RAISE EXCEPTION 'Test H2 FAILED: admin without link/permission succeeded';
  EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE 'P0002' THEN
    RAISE NOTICE 'Test H2 PASSED: self-service never impersonates by role';
  END;
END $$;

ROLLBACK;

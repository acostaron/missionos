-- =============================================================================
-- Security Tests: member_account_linking_security.sql
-- Feature:        Member account linking + role provisioning
--                 (members.account_links.manage, link_member_account,
--                  unlink_member_account, get_member_account_link_drift)
-- Non-destructive. All synthetic fixtures are inside a transaction and
-- strictly ROLLED BACK.
-- =============================================================================

-- PART 1: STATIC POSTURE
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.permissions
  WHERE code = 'members.account_links.manage' AND domain_code = 'members'
    AND action_code = 'manage' AND scope_type = 'organization' AND is_active;
  ASSERT v_count = 1, 'PART 1.1 FAILED: permission not registered';

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'members.account_links.manage' AND ar.code = 'organization_administrator'
    AND rp.permission_effect = 'allow' AND rp.approval_status = 'approved';
  ASSERT v_count = 1, 'PART 1.2 FAILED: org admin mapping missing';

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'members.account_links.manage' AND ar.code <> 'organization_administrator';
  ASSERT v_count = 0, 'PART 1.3 FAILED: permission granted to another role';

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'security.profile_member_links.manage' AND ar.code = 'organization_administrator';
  ASSERT v_count = 0, 'PART 1.4 FAILED: org admin gained broad security permission';

  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  WHERE ar.code = 'member';
  ASSERT v_count = 1, 'PART 1.5 FAILED: member role permission set changed';
  RAISE NOTICE 'PART 1.1-1.5 PASSED: permission + mappings';

  ASSERT has_function_privilege('authenticated', 'public.link_member_account(uuid,uuid,uuid,text,text)', 'EXECUTE'), 'ACL: authenticated link';
  ASSERT has_function_privilege('authenticated', 'public.unlink_member_account(uuid,uuid,text)', 'EXECUTE'), 'ACL: authenticated unlink';
  ASSERT has_function_privilege('authenticated', 'public.get_member_account_link_drift(uuid)', 'EXECUTE'), 'ACL: authenticated drift';
  ASSERT NOT has_function_privilege('anon', 'public.link_member_account(uuid,uuid,uuid,text,text)', 'EXECUTE'), 'ACL: anon link';
  ASSERT NOT has_function_privilege('anon', 'public.unlink_member_account(uuid,uuid,text)', 'EXECUTE'), 'ACL: anon unlink';
  ASSERT NOT has_function_privilege('anon', 'public.get_member_account_link_drift(uuid)', 'EXECUTE'), 'ACL: anon drift';
  ASSERT NOT has_function_privilege('authenticated', 'private.provision_member_access(uuid,uuid,uuid,text,text,uuid)', 'EXECUTE'), 'ACL: authenticated provision';
  ASSERT NOT has_function_privilege('authenticated', 'private.can_manage_member_account_links(uuid)', 'EXECUTE'), 'ACL: authenticated helper';
  ASSERT NOT has_function_privilege('authenticated', 'public.verify_profile_member_link(uuid,uuid,uuid,text,text,uuid)', 'EXECUTE'), 'ACL: authenticated verify helper exposed';

  -- No actor/role/permission/status inputs on browser RPCs
  SELECT count(*) INTO v_count FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname IN ('link_member_account','unlink_member_account','get_member_account_link_drift')
    AND (pg_get_function_identity_arguments(p.oid) ~* 'actor|role_id|permission|verified_at|status');
  ASSERT v_count = 0, 'PART 1.7 FAILED: RPC accepts a forbidden input';
  RAISE NOTICE 'PART 1.6-1.7 PASSED: ACLs + inputs';
END $$;

-- PART 2: BEHAVIOUR
BEGIN;

DO $$
DECLARE
  v_org     uuid;
  v_org_b   uuid := gen_random_uuid();
  v_r_admin uuid; v_r_member uuid; v_r_sec uuid; v_r_leader uuid;
  v_status  uuid;
  v_status_b uuid := gen_random_uuid();
  v_adm uuid := gen_random_uuid();
  v_sec uuid := gen_random_uuid();
  v_plain uuid := gen_random_uuid();
  v_lead uuid := gen_random_uuid();
  v_t1 uuid := gen_random_uuid();
  v_t2 uuid := gen_random_uuid();
  v_t3 uuid := gen_random_uuid();
  v_t4 uuid := gen_random_uuid();
  v_t5 uuid := gen_random_uuid();
  v_nomem uuid := gen_random_uuid();
  v_m1 uuid := gen_random_uuid(); v_m2 uuid := gen_random_uuid();
  v_m3 uuid := gen_random_uuid(); v_m4 uuid := gen_random_uuid();
  v_march uuid := gen_random_uuid();
  v_mret uuid := gen_random_uuid(); v_msurv uuid := gen_random_uuid();
  v_mb uuid := gen_random_uuid();
  v_req uuid := gen_random_uuid();
  v_res jsonb; v_res2 jsonb;
  v_n integer;
  v_code text;
  v_ok boolean;
  v_loop uuid;
BEGIN
  SELECT id INTO v_org FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  SELECT id INTO v_r_admin  FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT id INTO v_r_member FROM public.app_roles WHERE code = 'member';
  SELECT id INTO v_r_sec    FROM public.app_roles WHERE code = 'security_administrator';
  SELECT id INTO v_r_leader FROM public.app_roles WHERE code = 'unit_servant_leader_access';
  SELECT membership_status_id INTO v_status FROM public.members WHERE organization_id = v_org LIMIT 1;

  INSERT INTO public.organizations (id, code, name, organization_type, lifecycle_status, effective_from)
  VALUES (v_org_b, 'zz_test_b', 'Test Org B', 'ministry', 'active', current_date);

  INSERT INTO public.member_statuses (id, organization_id, code, name, status_category, is_active_membership)
  VALUES (v_status_b, v_org_b, 'active', 'Active', 'active', true);

  INSERT INTO auth.users (id, aud, role, email)
  SELECT p, 'authenticated', 'authenticated', p::text || '@test.local'
  FROM unnest(ARRAY[v_adm, v_sec, v_plain, v_lead, v_t1, v_t2, v_t3, v_t4, v_t5, v_nomem]) p;
  INSERT INTO public.profiles (id, display_name)
  SELECT p, 'Test ' || left(p::text, 6)
  FROM unnest(ARRAY[v_adm, v_sec, v_plain, v_lead, v_t1, v_t2, v_t3, v_t4, v_t5, v_nomem]) p;

  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  SELECT p, v_org, 'active', now()
  FROM unnest(ARRAY[v_adm, v_sec, v_plain, v_lead, v_t1, v_t2, v_t3, v_t4, v_t5]) p;
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  SELECT p, v_org_b, 'active', now() FROM unnest(ARRAY[v_adm, v_t1]) p;

  INSERT INTO public.profile_role_assignments (profile_id, organization_id, app_role_id, assignment_status, proposed_at, approved_at, activated_at, effective_from_at)
  VALUES
    (v_adm,   v_org,   v_r_admin,  'active', now(), now(), now(), now()),
    (v_sec,   v_org,   v_r_sec,    'active', now(), now(), now(), now()),
    (v_plain, v_org,   v_r_member, 'active', now(), now(), now(), now()),
    (v_lead,  v_org,   v_r_leader, 'active', now(), now(), now(), now()),
    (v_t1,    v_org,   v_r_leader, 'active', now(), now(), now(), now()),
    (v_t5,    v_org,   v_r_member, 'active', now(), now(), now(), now());
  -- Org B: admin-org-A holds the org admin role in B too
  INSERT INTO public.profile_role_assignments (profile_id, organization_id, app_role_id, assignment_status, proposed_at, approved_at, activated_at, effective_from_at)
  VALUES (v_adm, v_org_b, v_r_admin, 'active', now(), now(), now(), now());

  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES
    (v_m1, v_org, v_status, 'Link One', 'One, Link', 'One', 'active'),
    (v_m2, v_org, v_status, 'Link Two', 'Two, Link', 'Two', 'active'),
    (v_m3, v_org, v_status, 'Link Three', 'Three, Link', 'Three', 'active'),
    (v_m4, v_org, v_status, 'Link Four', 'Four, Link', 'Four', 'active'),
    (v_mret, v_org, v_status, 'Retired Dup', 'Dup, Retired', 'Dup', 'active'),
    (v_msurv, v_org, v_status, 'Survivor Dup', 'Dup, Survivor', 'Dup', 'active');
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status, archived_at, archive_reason)
  VALUES (v_march, v_org, v_status, 'Archived One', 'One, Archived', 'Arch', 'archived', now(), 'test');
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_mb, v_org_b, v_status_b, 'Org B Member', 'B, Org', 'B', 'active');

  INSERT INTO public.member_merge_requests (id, organization_id, survivor_member_id, retiring_member_id, request_status)
  VALUES (v_req, v_org, v_msurv, v_mret, 'completed');
  INSERT INTO public.member_merge_history (organization_id, member_merge_request_id, survivor_member_id, retired_member_id)
  VALUES (v_org, v_req, v_msurv, v_mret);

  -- -------- 1/2: admin links t1 -> m1 --------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  v_res := public.link_member_account(v_org, v_t1, v_m1, 'in_person', 'met at office');
  ASSERT (v_res->>'member_id')::uuid = v_m1 AND v_res->>'link_status' = 'verified'
     AND v_res->>'member_access_status' = 'active', 'Test 1 FAILED: bad result';
  RAISE NOTICE 'Test 1 PASSED: narrow-permission admin can link';

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_n FROM public.profile_member_links
  WHERE profile_id = v_t1 AND organization_id = v_org AND member_id = v_m1
    AND link_type = 'self' AND link_status = 'verified' AND is_primary AND ended_at IS NULL
    AND verification_method = 'in_person';
  ASSERT v_n = 1, 'Test 2 FAILED: verified primary self link missing';
  SELECT count(*) INTO v_n FROM public.profile_role_assignments
  WHERE profile_id = v_t1 AND organization_id = v_org AND app_role_id = v_r_member
    AND assignment_status = 'active' AND source_type = 'organization_membership';
  ASSERT v_n = 1, 'Test 2 FAILED: active member role missing';
  RAISE NOTICE 'Test 2 PASSED: link + active member role created';

  SELECT count(*) INTO v_n FROM public.profile_member_links
  WHERE profile_id = v_t1 AND organization_id = v_org
    AND verification_method = 'in_person' AND verification_summary = 'met at office'
    AND verified_by_profile_id = v_adm AND verified_at IS NOT NULL;
  ASSERT v_n = 1, 'Test A/B/E FAILED: new link evidence/actor wrong';
  RAISE NOTICE 'Test A/B/E PASSED: new link stores supplied method/summary and admin actor';

  -- -------- 3: member gets self-service only --------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_t1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_t1, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claim.sub', v_t1::text, true);
  ASSERT private.has_permission('members.self_service.view', v_org), 'Test 3 FAILED: no self-service';
  ASSERT NOT private.has_permission('members.account_links.manage', v_org), 'Test 3 FAILED: linking authority leaked';
  ASSERT NOT private.has_permission('security.profile_member_links.manage', v_org), 'Test 3 FAILED: broad security leaked';
  PERFORM set_config('role', 'authenticated', true);
  v_res2 := public.get_my_member_context(v_org);
  ASSERT (v_res2->'member'->>'member_id')::uuid = v_m1, 'Test 3 FAILED: self context';
  RAISE NOTICE 'Test 3 PASSED: member role gives self-service only';

  -- -------- 4: idempotent --------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  v_res2 := public.link_member_account(v_org, v_t1, v_m1, 'government_id', 'changed evidence');
  ASSERT v_res2->>'link_id' = v_res->>'link_id', 'Test 4 FAILED: link id changed';
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_n FROM public.profile_member_links
  WHERE id = (v_res->>'link_id')::uuid AND verification_method = 'in_person'
    AND verification_summary = 'met at office';
  ASSERT v_n = 1, 'Test G FAILED: repeat call rewrote original verification evidence';
  RAISE NOTICE 'Test F/G PASSED: repeat preserves original verification evidence';
  SELECT count(*) INTO v_n FROM public.profile_member_links WHERE profile_id = v_t1 AND organization_id = v_org;
  ASSERT v_n = 1, 'Test 4 FAILED: duplicate links';
  SELECT count(*) INTO v_n FROM public.profile_role_assignments
  WHERE profile_id = v_t1 AND organization_id = v_org AND app_role_id = v_r_member AND assignment_status = 'active';
  ASSERT v_n = 1, 'Test 4 FAILED: duplicate member roles';
  RAISE NOTICE 'Test 4 PASSED: idempotent';

  -- -------- C/D: promotion of proposed / under_review links --------
  DECLARE
    v_p6 uuid := gen_random_uuid(); v_p7 uuid := gen_random_uuid();
    v_m5 uuid := gen_random_uuid(); v_m6 uuid := gen_random_uuid();
  BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_p6, 'authenticated', 'authenticated', v_p6::text || '@test.local'),
           (v_p7, 'authenticated', 'authenticated', v_p7::text || '@test.local');
    INSERT INTO public.profiles (id, display_name) VALUES (v_p6, 'Promo Six'), (v_p7, 'Promo Seven');
    INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
    VALUES (v_p6, v_org, 'active', now()), (v_p7, v_org, 'active', now());
    INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
    VALUES (v_m5, v_org, v_status, 'Promo Five', 'Five, Promo', 'Five', 'active'),
           (v_m6, v_org, v_status, 'Promo Six M', 'Six, Promo', 'Six', 'active');
    INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary)
    VALUES (v_p6, v_org, v_m5, 'self', 'proposed', false),
           (v_p7, v_org, v_m6, 'self', 'under_review', false);

    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    PERFORM public.link_member_account(v_org, v_p6, v_m5, 'government_id', 'Verified against parish/member records');
    PERFORM public.link_member_account(v_org, v_p7, v_m6, 'government_id', 'Verified against parish/member records');
    PERFORM set_config('role', 'postgres', true);

    SELECT count(*) INTO v_n FROM public.profile_member_links
    WHERE profile_id IN (v_p6, v_p7) AND organization_id = v_org
      AND link_status = 'verified' AND is_primary AND ended_at IS NULL
      AND verification_method = 'government_id'
      AND verification_summary = 'Verified against parish/member records'
      AND verified_by_profile_id = v_adm AND verified_at IS NOT NULL;
    ASSERT v_n = 2, format('Test C/D FAILED: promoted links with correct evidence = %s', v_n);
    SELECT count(*) INTO v_n FROM public.profile_member_links WHERE profile_id IN (v_p6, v_p7);
    ASSERT v_n = 2, 'Test C/D FAILED: promotion created duplicate links';
    SELECT count(*) INTO v_n FROM public.profile_role_assignments
    WHERE profile_id IN (v_p6, v_p7) AND app_role_id = v_r_member AND assignment_status = 'active';
    ASSERT v_n = 2, 'Test C/D FAILED: member roles not active after promotion';
    RAISE NOTICE 'Test C/D PASSED: proposed and under_review promoted with supplied evidence';
  END;

  -- -------- 5/6/7: denied callers --------
  FOREACH v_loop IN ARRAY ARRAY[v_t3, v_plain, v_lead] LOOP
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_loop::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_loop, 'role', 'authenticated')::text, true);
    v_code := NULL;
    BEGIN
      PERFORM public.link_member_account(v_org, v_t2, v_m2, 'x');
    EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
    ASSERT v_code = '42501', format('Test 5-7 FAILED: caller %s got %s', v_loop, v_code);
    v_code := NULL;
    BEGIN
      PERFORM public.unlink_member_account(v_org, v_t1, 'x');
    EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
    ASSERT v_code = '42501', 'Test 5-7 FAILED: unlink not denied';
    v_code := NULL;
    BEGIN
      PERFORM * FROM public.get_member_account_link_drift(v_org);
    EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
    ASSERT v_code = '42501', 'Test 5-7 FAILED: drift not denied';
  END LOOP;
  RAISE NOTICE 'Test 5/6/7 PASSED: no-permission, plain member, servant-leader denied';

  -- -------- 8: anon --------
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_code := NULL;
  BEGIN
    PERFORM public.link_member_account(v_org, v_t2, v_m2, 'x');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = '42501', 'Test 8 FAILED: anon not denied';
  RAISE NOTICE 'Test 8 PASSED: anon denied';

  -- -------- 9..14 as admin --------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  -- 9 cross-org: adm cannot link a member of org B inside org A, nor use unknown org
  v_code := NULL;
  BEGIN
    PERFORM public.link_member_account(v_org, v_t2, v_mb, 'x');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = 'P0002', format('Test 9 FAILED: org-B member in org A got %s', v_code);
  v_code := NULL;
  BEGIN
    PERFORM public.link_member_account(gen_random_uuid(), v_t2, v_m2, 'x');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = '42501', 'Test 9 FAILED: unknown org not denied';
  RAISE NOTICE 'Test 9 PASSED: cross-organization linking denied';

  -- 10 no org membership
  v_code := NULL;
  BEGIN
    PERFORM public.link_member_account(v_org, v_nomem, v_m2, 'x');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = '23514', format('Test 10 FAILED: got %s', v_code);
  RAISE NOTICE 'Test 10 PASSED: profile without org membership denied';

  -- 11 archived
  v_code := NULL;
  BEGIN
    PERFORM public.link_member_account(v_org, v_t2, v_march, 'x');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = '23514', format('Test 11 FAILED: got %s', v_code);
  RAISE NOTICE 'Test 11 PASSED: archived member not linkable';

  -- 12 merged -> canonical
  v_res := public.link_member_account(v_org, v_t2, v_mret, 'in_person');
  ASSERT (v_res->>'member_id')::uuid = v_msurv, 'Test 12 FAILED: not canonical survivor';
  RAISE NOTICE 'Test 12 PASSED: merged member resolves to survivor';

  -- 13 second primary member for same profile
  v_code := NULL;
  BEGIN
    PERFORM public.link_member_account(v_org, v_t1, v_m2, 'x');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = '23505', format('Test 13 FAILED: got %s', v_code);
  RAISE NOTICE 'Test 13 PASSED: second member for same profile rejected';

  -- 14 second account for same member
  v_code := NULL;
  BEGIN
    PERFORM public.link_member_account(v_org, v_t3, v_m1, 'x');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = '23505', format('Test 14 FAILED: got %s', v_code);
  RAISE NOTICE 'Test 14 PASSED: second account for same member rejected';

  -- 15/16: org B link for t1, then unlink in A
  PERFORM public.link_member_account(v_org_b, v_t1, v_mb, 'in_person');

  -- Single-transaction artifact: backdate so ended-period checks (to > from) hold
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.profile_organization_memberships SET effective_from_at = now() - interval '2 hours'
  WHERE profile_id = v_t1;
  UPDATE public.profile_role_assignments SET effective_from_at = now() - interval '1 hour'
  WHERE app_role_id = v_r_member AND profile_id IN (v_t1, v_t3);
  UPDATE public.profile_member_links SET verified_at = now() - interval '1 hour'
  WHERE profile_id IN (v_t1, v_t3);
  PERFORM set_config('role', 'authenticated', true);

  v_code := NULL;
  BEGIN
    PERFORM public.unlink_member_account(v_org, v_t1, '  ');
  EXCEPTION WHEN OTHERS THEN v_code := SQLSTATE; END;
  ASSERT v_code = '22023', 'Test 15 FAILED: empty reason accepted';

  v_res := public.unlink_member_account(v_org, v_t1, 'left the community');
  ASSERT (v_res->>'link_ended')::boolean AND (v_res->>'member_roles_ended')::int = 1, 'Test 15 FAILED: result';

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_n FROM public.profile_member_links
  WHERE profile_id = v_t1 AND organization_id = v_org AND link_status = 'verified' AND ended_at IS NULL;
  ASSERT v_n = 0, 'Test 15 FAILED: link still active';
  SELECT count(*) INTO v_n FROM public.profile_role_assignments
  WHERE profile_id = v_t1 AND organization_id = v_org AND app_role_id = v_r_member AND assignment_status = 'active';
  ASSERT v_n = 0, 'Test 15 FAILED: member role still active';
  SELECT count(*) INTO v_n FROM public.profile_role_assignments
  WHERE profile_id = v_t1 AND organization_id = v_org AND app_role_id = v_r_leader AND assignment_status = 'active';
  ASSERT v_n = 1, 'Test 15 FAILED: unrelated role was ended';
  RAISE NOTICE 'Test 15 PASSED: unlink ends link + member role, preserves other roles';

  SELECT count(*) INTO v_n FROM public.profile_member_links
  WHERE profile_id = v_t1 AND organization_id = v_org_b AND link_status = 'verified' AND ended_at IS NULL;
  ASSERT v_n = 1, 'Test 16 FAILED: org B link affected';
  SELECT count(*) INTO v_n FROM public.profile_role_assignments
  WHERE profile_id = v_t1 AND organization_id = v_org_b AND app_role_id = v_r_member AND assignment_status = 'active';
  ASSERT v_n = 1, 'Test 16 FAILED: org B member role affected';
  RAISE NOTICE 'Test 16 PASSED: org A unlink leaves org B untouched';

  -- repeat unlink is safe
  PERFORM set_config('role', 'authenticated', true);
  v_res := public.unlink_member_account(v_org, v_t1, 'again');
  ASSERT NOT (v_res->>'link_ended')::boolean AND (v_res->>'member_roles_ended')::int = 0, 'Repeat unlink FAILED';
  RAISE NOTICE 'Repeat unlink PASSED: idempotent';

  -- security admin may also link
  PERFORM set_config('request.jwt.claim.sub', v_sec::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
  v_res := public.link_member_account(v_org, v_t3, v_m3, 'in_person');
  ASSERT (v_res->>'member_access_status') = 'active', 'Security admin link FAILED';
  RAISE NOTICE 'Security-admin path PASSED';

  -- 17 admin without personal link remains valid
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  PERFORM * FROM public.get_member_account_link_drift(v_org);
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_n FROM public.profile_member_links WHERE profile_id = v_adm;
  ASSERT v_n = 0, 'Test 17 FAILED: admin unexpectedly linked';
  RAISE NOTICE 'Test 17 PASSED: admin without member link remains valid';

  -- 20 drift
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary,
    verification_method, verified_at, verified_by_profile_id, verification_summary)
  VALUES (v_t4, v_org, v_m4, 'self', 'verified', true, 'admin_verified', now(), v_adm, 'synthetic');
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_n FROM public.get_member_account_link_drift(v_org) d
  WHERE d.drift_type = 'link_without_role' AND d.profile_id = v_t4;
  ASSERT v_n = 1, 'Test 20 FAILED: link-without-role not detected';
  SELECT count(*) INTO v_n FROM public.get_member_account_link_drift(v_org) d
  WHERE d.drift_type = 'role_without_link' AND d.profile_id = v_t5;
  ASSERT v_n = 1, 'Test 20 FAILED: role-without-link not detected';
  SELECT count(*) INTO v_n FROM public.get_member_account_link_drift(v_org) d
  WHERE d.profile_id IN (v_t3, v_t2);
  ASSERT v_n = 0, 'Test 20 FAILED: healthy accounts flagged';
  RAISE NOTICE 'Test 20 PASSED: drift detection';

  PERFORM set_config('role', 'postgres', true);
END $$;

ROLLBACK;

-- Fixtures rolled back
DO $$
BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM public.organizations WHERE code = 'zz_test_b'),
    'CLEANUP FAILED: test org leaked';
  RAISE NOTICE 'ALL MEMBER ACCOUNT LINKING TESTS PASSED';
END $$;

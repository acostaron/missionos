-- =============================================================================
-- Security Tests: member_account_invitation_acceptance_security.sql
-- Feature:        Member account invitation acceptance lifecycle
--                 (accept_member_account_invitation,
--                  get_member_account_invitation_details)
-- Non-destructive. All synthetic fixtures are inside a transaction and
-- strictly ROLLED BACK.
-- =============================================================================

-- =============================================================================
-- PART 1: STATIC POSTURE & PERMISSION CHECKS
-- =============================================================================
DO $$
BEGIN
  -- 1.1 Function execution ACLs
  ASSERT has_function_privilege('authenticated', 'public.accept_member_account_invitation(uuid)', 'EXECUTE'),
    'ACL 1.1: authenticated accept allowed';
  ASSERT NOT has_function_privilege('anon', 'public.accept_member_account_invitation(uuid)', 'EXECUTE'),
    'ACL 1.2: anon accept denied';
  ASSERT has_function_privilege('service_role', 'public.accept_member_account_invitation(uuid)', 'EXECUTE'),
    'ACL 1.3: service_role accept allowed';

  ASSERT has_function_privilege('authenticated', 'public.get_member_account_invitation_details(uuid)', 'EXECUTE'),
    'ACL 1.4: authenticated get details allowed';
  ASSERT NOT has_function_privilege('anon', 'public.get_member_account_invitation_details(uuid)', 'EXECUTE'),
    'ACL 1.5: anon get details denied';

  RAISE NOTICE 'PART 1 PASSED: Function privileges and ACLs verified';
END $$;

-- =============================================================================
-- PART 2: BEHAVIOURAL & LIFECYCLE TESTS (ROLLED BACK)
-- =============================================================================
BEGIN;

DO $$
DECLARE
  v_org       uuid;
  v_org_b     uuid := gen_random_uuid();
  v_r_admin   uuid;
  v_r_member  uuid;
  v_status    uuid;
  v_status_b  uuid := gen_random_uuid();

  -- Admin & verifier
  v_adm       uuid := gen_random_uuid();

  -- Target Users
  v_user1      uuid := gen_random_uuid(); -- new invited user (status sent, profile pending)
  v_user2      uuid := gen_random_uuid(); -- existing auth user (status existing_account_invitation_pending)
  v_user3      uuid := gen_random_uuid(); -- wrong user
  v_user_bad   uuid := gen_random_uuid(); -- suspended/disabled user
  v_user_exp   uuid := gen_random_uuid(); -- expired user
  v_user_canc  uuid := gen_random_uuid(); -- cancelled user
  v_user_fail  uuid := gen_random_uuid(); -- failed user
  v_user_arch  uuid := gen_random_uuid(); -- arch user
  v_user_merge uuid := gen_random_uuid(); -- merge user
  v_user_multi uuid := gen_random_uuid(); -- multi-org user

  -- Members in Org A
  v_m1        uuid := gen_random_uuid();
  v_m2        uuid := gen_random_uuid();
  v_m_bad     uuid := gen_random_uuid();
  v_m_exp     uuid := gen_random_uuid();
  v_m_canc    uuid := gen_random_uuid();
  v_m_fail    uuid := gen_random_uuid();
  v_m_arch    uuid := gen_random_uuid();
  v_m_merge_s uuid := gen_random_uuid();
  v_m_merge_t uuid := gen_random_uuid();

  -- Member in Org B
  v_m_org_b   uuid := gen_random_uuid();

  -- Invitations
  v_inv1      uuid;
  v_inv2      uuid;
  v_inv_exp   uuid;
  v_inv_canc  uuid;
  v_inv_fail  uuid;
  v_inv_bad   uuid;
  v_inv_arch  uuid;
  v_inv_merge uuid;
  v_inv_b     uuid;
  v_req_id    uuid;
  v_user_broken uuid := gen_random_uuid();
  v_m_broken    uuid := gen_random_uuid();
  v_inv_broken  uuid;
  v_verifier    uuid;
  v_actor       uuid;
  v_err_code    text;
  v_err_msg     text;
  v_status_after text;

  v_res       jsonb;
  v_err       boolean;
  v_count     integer;
BEGIN
  -- Resolve master records
  SELECT id INTO v_org FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  SELECT id INTO v_r_admin  FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT id INTO v_r_member FROM public.app_roles WHERE code = 'member';
  SELECT membership_status_id INTO v_status FROM public.members WHERE organization_id = v_org LIMIT 1;

  -- Create synthetic Org B
  INSERT INTO public.organizations (id, code, name, organization_type, lifecycle_status, effective_from)
  VALUES (v_org_b, 'zz_test_b', 'Test Org B', 'ministry', 'active', current_date);

  INSERT INTO public.member_statuses (id, organization_id, code, name, status_category, is_active_membership)
  VALUES (v_status_b, v_org_b, 'active', 'Active', 'active', true);

  -- Create Admin Profile
  INSERT INTO auth.users (id, email, email_confirmed_at, role, aud)
  VALUES (v_adm, 'inv_admin@test.local', now(), 'authenticated', 'authenticated');

  INSERT INTO public.profiles (id, display_name, account_status, is_platform_administrator)
  VALUES (v_adm, 'Inv Admin', 'active', false);

  INSERT INTO public.profile_organization_memberships (
    profile_id, organization_id, membership_status, is_default,
    effective_from_at, invited_at, invited_by_profile_id, accepted_at,
    created_by_profile_id
  ) VALUES (
    v_adm, v_org, 'active', true,
    now(), now(), v_adm, now(),
    v_adm
  );

  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status, source_type,
    proposed_at, approved_at, activated_at, effective_from_at, updated_by_profile_id
  ) VALUES (
    v_adm, v_org, v_r_admin, 'active', 'manual',
    now(), now(), now(), now(), v_adm
  );

  -- Create Target Auth Users & Profiles
  INSERT INTO auth.users (id, email, email_confirmed_at, role, aud)
  VALUES (v_user1, 'target1@test.local', now(), 'authenticated', 'authenticated'),
         (v_user2, 'target2@test.local', now(), 'authenticated', 'authenticated'),
         (v_user3, 'target3@test.local', now(), 'authenticated', 'authenticated'),
         (v_user_bad, 'bad@test.local', now(), 'authenticated', 'authenticated'),
         (v_user_exp, 'exp@test.local', now(), 'authenticated', 'authenticated'),
         (v_user_canc, 'canc@test.local', now(), 'authenticated', 'authenticated'),
         (v_user_fail, 'fail@test.local', now(), 'authenticated', 'authenticated'),
         (v_user_arch, 'arch@test.local', now(), 'authenticated', 'authenticated'),
         (v_user_merge, 'merge@test.local', now(), 'authenticated', 'authenticated'),
         (v_user_multi, 'multi@test.local', now(), 'authenticated', 'authenticated');

  INSERT INTO public.profiles (id, display_name, account_status, is_platform_administrator)
  VALUES (v_user1, 'Target One', 'pending', false),
         (v_user2, 'Target Two', 'active', false),
         (v_user3, 'Target Three', 'active', false),
         (v_user_bad, 'Target Bad', 'suspended', false),
         (v_user_exp, 'Target Exp', 'pending', false),
         (v_user_canc, 'Target Canc', 'pending', false),
         (v_user_fail, 'Target Fail', 'pending', false),
         (v_user_arch, 'Target Arch', 'pending', false),
         (v_user_merge, 'Target Merge', 'pending', false),
         (v_user_multi, 'Target Multi', 'active', false);

  -- Target Members
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_m1, v_org, v_status, 'Member One', 'One, Member', 'Member One', 'active'),
         (v_m2, v_org, v_status, 'Member Two', 'Two, Member', 'Member Two', 'active'),
         (v_m_bad, v_org, v_status, 'Member Bad', 'Bad, Member', 'Member Bad', 'active'),
         (v_m_exp, v_org, v_status, 'Member Exp', 'Exp, Member', 'Member Exp', 'active'),
         (v_m_canc, v_org, v_status, 'Member Canc', 'Canc, Member', 'Member Canc', 'active'),
         (v_m_fail, v_org, v_status, 'Member Fail', 'Fail, Member', 'Member Fail', 'active'),
         (v_m_arch, v_org, v_status, 'Member Arch', 'Arch, Member', 'Member Arch', 'active'),
         (v_m_merge_s, v_org, v_status, 'Member Source', 'Source, Member', 'Member Source', 'active'),
         (v_m_merge_t, v_org, v_status, 'Member Target', 'Target, Member', 'Member Target', 'active'),
         (v_m_org_b, v_org_b, v_status_b, 'Member Org B', 'Org B, Member', 'Member Org B', 'active');

  UPDATE public.members SET archived_at = now() WHERE id = v_m_arch;

  -- Merge source member into target member
  INSERT INTO public.member_merge_requests (
    id, organization_id, survivor_member_id, retiring_member_id,
    request_status, requested_at, approved_at, executed_at,
    requested_by_profile_id, approved_by_profile_id, executed_by_profile_id
  ) VALUES (
    gen_random_uuid(), v_org, v_m_merge_t, v_m_merge_s,
    'completed', now(), now(), now(),
    v_adm, v_adm, v_adm
  ) RETURNING id INTO v_req_id;

  INSERT INTO public.member_merge_history (
    organization_id, member_merge_request_id, survivor_member_id, retired_member_id,
    merged_at, merged_by_profile_id
  ) VALUES (
    v_org, v_req_id, v_m_merge_t, v_m_merge_s,
    now(), v_adm
  );

  -- Invitations setup
  -- Inv 1: Sent invitation for User 1 / Member 1
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m1, 'target1@test.local', 'target1@test.local',
    v_user1, v_user1, 'sent',
    v_adm, now()
  ) RETURNING id INTO v_inv1;

  INSERT INTO public.profile_organization_memberships (
    profile_id, organization_id, membership_status, is_default,
    effective_from_at, invited_at, invited_by_profile_id, accepted_at,
    created_by_profile_id
  ) VALUES (
    v_user1, v_org, 'invited', true,
    now(), now(), v_adm, null,
    v_adm
  );

  -- Inv 2: Existing account pending for User 2 / Member 2
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m2, 'target2@test.local', 'target2@test.local',
    v_user2, v_user2, 'existing_account_invitation_pending',
    v_adm, now()
  ) RETURNING id INTO v_inv2;

  INSERT INTO public.profile_organization_memberships (
    profile_id, organization_id, membership_status, is_default,
    effective_from_at, invited_at, invited_by_profile_id, accepted_at,
    created_by_profile_id
  ) VALUES (
    v_user2, v_org, 'invited', true,
    now(), now(), v_adm, null,
    v_adm
  );

  -- Expired invitation
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status, expires_at,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m_exp, 'exp@test.local', 'exp@test.local',
    v_user_exp, v_user_exp, 'sent', now() - interval '1 day',
    v_adm, now() - interval '8 days'
  ) RETURNING id INTO v_inv_exp;

  -- Cancelled invitation
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m_canc, 'canc@test.local', 'canc@test.local',
    v_user_canc, v_user_canc, 'cancelled',
    v_adm, now()
  ) RETURNING id INTO v_inv_canc;

  -- Failed invitation
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m_fail, 'fail@test.local', 'fail@test.local',
    v_user_fail, v_user_fail, 'failed',
    v_adm, now()
  ) RETURNING id INTO v_inv_fail;

  -- Suspended profile invitation
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m_bad, 'bad@test.local', 'bad@test.local',
    v_user_bad, v_user_bad, 'sent',
    v_adm, now()
  ) RETURNING id INTO v_inv_bad;

  -- Archived member invitation
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m_arch, 'arch@test.local', 'arch@test.local',
    v_user_arch, v_user_arch, 'sent',
    v_adm, now()
  ) RETURNING id INTO v_inv_arch;

  -- Merged member invitation
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m_merge_s, 'merge@test.local', 'merge@test.local',
    v_user_merge, v_user_merge, 'sent',
    v_adm, now()
  ) RETURNING id INTO v_inv_merge;

  -- Multi-org setup for v_user_multi in Org B
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org_b, v_m_org_b, 'multi@test.local', 'multi@test.local',
    v_user_multi, v_user_multi, 'sent',
    v_adm, now()
  ) RETURNING id INTO v_inv_b;

  INSERT INTO public.profile_organization_memberships (
    profile_id, organization_id, membership_status, is_default,
    effective_from_at, invited_at, invited_by_profile_id, accepted_at,
    created_by_profile_id
  ) VALUES (
    v_user_multi, v_org_b, 'invited', true,
    now(), now(), v_adm, null,
    v_adm
  );

  -- -------------------------------------------------------------------------
  -- TEST 2.1: Anon cannot accept
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', null, true);
  PERFORM set_config('request.jwt.claims', null, true);

  v_err := false;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv1);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;
  ASSERT v_err, 'TEST 2.1 FAILED: anon should be rejected';
  RAISE NOTICE 'TEST 2.1 PASSED: anon cannot accept';

  -- -------------------------------------------------------------------------
  -- TEST 2.2: Wrong authenticated profile cannot accept another profile's invitation
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user3::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user3, 'role', 'authenticated')::text, true);

  v_err := false;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv1);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;
  ASSERT v_err, 'TEST 2.2 FAILED: wrong user should not accept another user invitation';
  RAISE NOTICE 'TEST 2.2 PASSED: wrong user rejected';

  -- -------------------------------------------------------------------------
  -- TEST 2.3: Cross-org substitution impossible (user cannot accept org B invite with org A context or vice versa)
  -- -------------------------------------------------------------------------
  v_err := false;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv_b);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;
  ASSERT v_err, 'TEST 2.3 FAILED: user cannot accept invitation belonging to different user in org B';
  RAISE NOTICE 'TEST 2.3 PASSED: cross-org substitution impossible';

  -- -------------------------------------------------------------------------
  -- TEST 2.4 - 2.15: Sent invitation accepted by bound profile (User 1)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user1, 'role', 'authenticated')::text, true);

  v_res := public.accept_member_account_invitation(v_inv1);
  ASSERT v_res->>'status' = 'accepted', 'TEST 2.4 FAILED: acceptance status should be accepted';

  -- Switch to postgres role to inspect underlying tables
  PERFORM set_config('role', 'postgres', true);

  -- TEST 2.6: Profile activated pending -> active
  SELECT count(*) INTO v_count FROM public.profiles WHERE id = v_user1 AND account_status = 'active';
  ASSERT v_count = 1, 'TEST 2.6 FAILED: profile should be active';

  -- TEST 2.7 & 2.8: Invited membership -> active & accepted_at set
  SELECT count(*) INTO v_count FROM public.profile_organization_memberships
  WHERE profile_id = v_user1 AND organization_id = v_org
    AND membership_status = 'active' AND accepted_at IS NOT NULL;
  ASSERT v_count = 1, 'TEST 2.7/2.8 FAILED: membership not active with accepted_at';

  -- TEST 2.9 & 2.10: Verified primary self-link created & points to invitation.member_id
  SELECT count(*) INTO v_count FROM public.profile_member_links
  WHERE profile_id = v_user1 AND organization_id = v_org AND member_id = v_m1
    AND link_type = 'self' AND link_status = 'verified' AND is_primary AND ended_at IS NULL;
  ASSERT v_count = 1, 'TEST 2.9/2.10 FAILED: verified primary self-link missing';

  -- Provenance verification: verified_by_profile_id preserved as inviting admin (Requirement A)
  -- And must NOT be the accepting member merely because they accepted (Requirement B)
  SELECT verified_by_profile_id INTO v_verifier FROM public.profile_member_links
  WHERE profile_id = v_user1 AND organization_id = v_org AND member_id = v_m1;
  ASSERT v_verifier = v_adm, 'TEST 2.9.1 FAILED: verified_by_profile_id should preserve admin provenance';
  ASSERT v_verifier <> v_user1, 'TEST 2.9.2 FAILED: verified_by_profile_id must NOT be the accepting member';

  -- TEST 2.11 & 2.12: Active member role provisioned with only self-service permission
  SELECT count(*) INTO v_count FROM public.profile_role_assignments
  WHERE profile_id = v_user1 AND organization_id = v_org AND app_role_id = v_r_member
    AND assignment_status = 'active';
  ASSERT v_count = 1, 'TEST 2.11 FAILED: active member role assignment missing';

  -- Invariant: member role still has only self-service permissions
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE rp.app_role_id = v_r_member AND p.code <> 'members.self_service.view';
  ASSERT v_count = 0, 'TEST 2.12 FAILED: member role has unauthorized permissions';

  -- TEST 2.13 & 2.14: Invitation status becomes accepted & accepted_at set
  SELECT count(*) INTO v_count FROM public.member_account_invitations
  WHERE id = v_inv1 AND invitation_status = 'accepted' AND accepted_at IS NOT NULL;
  ASSERT v_count = 1, 'TEST 2.13/2.14 FAILED: invitation status not accepted';

  -- TEST 2.15: Audit event written (members.account.accepted)
  -- Requirement D: actor_profile_id = accepting member (and distinct from verifier)
  SELECT actor_profile_id INTO v_actor FROM audit.events
  WHERE organization_id = v_org AND event_code = 'members.account.accepted'
    AND entity_id = v_inv1;
  ASSERT v_actor = v_user1, 'TEST 2.15 FAILED: audit event members.account.accepted missing or actor mismatch';
  ASSERT v_actor <> v_verifier, 'TEST 2.15.1 FAILED: audit actor and verifier must be distinct entities';

  RAISE NOTICE 'TEST 2.4-2.15 PASSED: Sent invitation lifecycle fully verified';

  -- -------------------------------------------------------------------------
  -- TEST 2.16: Idempotent repeat acceptance returns already_accepted
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user1, 'role', 'authenticated')::text, true);

  v_res := public.accept_member_account_invitation(v_inv1);
  ASSERT v_res->>'status' = 'already_accepted', 'TEST 2.16 FAILED: repeat acceptance should return already_accepted';
  RAISE NOTICE 'TEST 2.16 PASSED: Duplicate/repeat acceptance is idempotent';

  -- -------------------------------------------------------------------------
  -- TEST 2.17: Existing account invitation pending accepted (User 2)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user2::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user2, 'role', 'authenticated')::text, true);

  v_res := public.accept_member_account_invitation(v_inv2);
  ASSERT v_res->>'status' = 'accepted', 'TEST 2.17 FAILED: existing account pending should accept';

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_count FROM public.profile_member_links
  WHERE profile_id = v_user2 AND organization_id = v_org AND member_id = v_m2
    AND link_status = 'verified' AND is_primary;
  ASSERT v_count = 1, 'TEST 2.17.1 FAILED: self link for user 2 missing';
  RAISE NOTICE 'TEST 2.17 PASSED: Existing auth user invitation accepted cleanly';

  -- -------------------------------------------------------------------------
  -- TEST 2.18: Expired invitation rejected
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_exp::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_exp, 'role', 'authenticated')::text, true);

  v_err := false;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv_exp);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;
  ASSERT v_err, 'TEST 2.18 FAILED: expired invitation should be rejected';
  RAISE NOTICE 'TEST 2.18 PASSED: Expired invitation rejected';

  -- -------------------------------------------------------------------------
  -- TEST 2.19: Cancelled invitation rejected
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_canc::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_canc, 'role', 'authenticated')::text, true);

  v_err := false;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv_canc);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;
  ASSERT v_err, 'TEST 2.19 FAILED: cancelled invitation should be rejected';
  RAISE NOTICE 'TEST 2.19 PASSED: Cancelled invitation rejected';

  -- -------------------------------------------------------------------------
  -- TEST 2.20: Failed invitation rejected
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_fail::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_fail, 'role', 'authenticated')::text, true);

  v_err := false;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv_fail);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;
  ASSERT v_err, 'TEST 2.20 FAILED: failed invitation should be rejected';
  RAISE NOTICE 'TEST 2.20 PASSED: Failed invitation rejected';

  -- -------------------------------------------------------------------------
  -- TEST 2.21: Suspended/disabled/closed profile rejected
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_bad::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_bad, 'role', 'authenticated')::text, true);

  v_err := false;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv_bad);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;
  ASSERT v_err, 'TEST 2.21 FAILED: suspended profile should be rejected';
  RAISE NOTICE 'TEST 2.21 PASSED: Suspended profile rejected';

  -- -------------------------------------------------------------------------
  -- TEST 2.22: Archived member rejected
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_arch::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_arch, 'role', 'authenticated')::text, true);

  v_err := false;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv_arch);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;
  ASSERT v_err, 'TEST 2.22 FAILED: archived member invitation should be rejected';
  RAISE NOTICE 'TEST 2.22 PASSED: Archived member rejected';

  -- -------------------------------------------------------------------------
  -- TEST 2.23: Merged member resolves to canonical target member
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_merge::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_merge, 'role', 'authenticated')::text, true);

  v_res := public.accept_member_account_invitation(v_inv_merge);
  ASSERT (v_res->>'member_id')::uuid = v_m_merge_t, 'TEST 2.23 FAILED: merged member should resolve to canonical member target';
  RAISE NOTICE 'TEST 2.23 PASSED: Merged member canonical resolution verified';

  -- -------------------------------------------------------------------------
  -- TEST 2.24: Multi-org acceptance affects only target org
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_multi::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_multi, 'role', 'authenticated')::text, true);

  v_res := public.accept_member_account_invitation(v_inv_b);
  ASSERT v_res->>'status' = 'accepted', 'TEST 2.24 FAILED: multi org acceptance failed';

  -- Switch to postgres to inspect memberships
  PERFORM set_config('role', 'postgres', true);

  -- Org B membership active
  SELECT count(*) INTO v_count FROM public.profile_organization_memberships
  WHERE profile_id = v_user_multi AND organization_id = v_org_b AND membership_status = 'active';
  ASSERT v_count = 1, 'TEST 2.24.1 FAILED: Org B membership should be active';

  -- Org A membership untouched (0 rows)
  SELECT count(*) INTO v_count FROM public.profile_organization_memberships
  WHERE profile_id = v_user_multi AND organization_id = v_org;
  ASSERT v_count = 0, 'TEST 2.24.2 FAILED: Org A should have no rows for user multi';
  RAISE NOTICE 'TEST 2.24 PASSED: Multi-org acceptance affects only target org';

  -- -------------------------------------------------------------------------
  -- TEST 2.25: get_member_account_invitation_details helper query
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_multi::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_multi, 'role', 'authenticated')::text, true);

  v_res := public.get_member_account_invitation_details(v_inv_b);
  ASSERT v_res->>'status' = 'accepted', 'TEST 2.25.1 FAILED: details status should be accepted';
  ASSERT v_res->>'can_accept' = 'false', 'TEST 2.25.2 FAILED: already accepted cannot accept again';
  RAISE NOTICE 'TEST 2.25 PASSED: get_member_account_invitation_details verified';

  -- -------------------------------------------------------------------------
  -- TEST 2.26: Missing administrative verification provenance rejects acceptance (Requirement C & E)
  -- -------------------------------------------------------------------------
  -- Synthesize an invitation where invited_by_profile_id is null in a safe rolled-back state
  PERFORM set_config('role', 'postgres', true);
  EXECUTE 'ALTER TABLE public.member_account_invitations ALTER COLUMN invited_by_profile_id DROP NOT NULL';

  INSERT INTO auth.users (id, email, email_confirmed_at, role, aud)
  VALUES (v_user_broken, 'broken@test.local', now(), 'authenticated', 'authenticated');

  INSERT INTO public.profiles (id, display_name, account_status, is_platform_administrator)
  VALUES (v_user_broken, 'Broken Prov', 'pending', false);

  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_m_broken, v_org, v_status, 'Member Broken', 'Broken, Member', 'Member Broken', 'active');

  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status,
    invited_by_profile_id, invited_at
  ) VALUES (
    v_org, v_m_broken, 'broken@test.local', 'broken@test.local',
    v_user_broken, v_user_broken, 'sent',
    null, now()
  ) RETURNING id INTO v_inv_broken;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_broken::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_broken, 'role', 'authenticated')::text, true);

  v_err := false;
  v_err_code := null;
  BEGIN
    PERFORM public.accept_member_account_invitation(v_inv_broken);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
    GET STACKED DIAGNOSTICS v_err_code = RETURNED_SQLSTATE, v_err_msg = MESSAGE_TEXT;
  END;

  ASSERT v_err, 'TEST 2.26.1 FAILED: acceptance without administrative verifier must be rejected';
  ASSERT v_err_code = '23514', 'TEST 2.26.2 FAILED: expected error 23514 for missing administrative provenance, got ' || coalesce(v_err_code, 'none');

  -- Verify Requirement E: invitation remains pending if acceptance transaction fails
  PERFORM set_config('role', 'postgres', true);
  SELECT invitation_status INTO v_status_after FROM public.member_account_invitations WHERE id = v_inv_broken;
  ASSERT v_status_after = 'sent', 'TEST 2.26.3 FAILED: invitation must remain in sent status after failed transaction, got: ' || coalesce(v_status_after, 'null');

  -- Verify no self-link was created
  SELECT count(*) INTO v_count FROM public.profile_member_links WHERE profile_id = v_user_broken;
  ASSERT v_count = 0, 'TEST 2.26.4 FAILED: no link should exist after rejected acceptance';

  -- Clean up synthetic test row before restoring constraint
  DELETE FROM public.member_account_invitations WHERE id = v_inv_broken;

  -- Restore NOT NULL constraint before block ends (though whole transaction rolls back anyway)
  EXECUTE 'ALTER TABLE public.member_account_invitations ALTER COLUMN invited_by_profile_id SET NOT NULL';

  RAISE NOTICE 'TEST 2.26 PASSED: Missing administrative provenance rejected (23514) and invitation remains pending';

  RAISE NOTICE 'ALL INVITATION ACCEPTANCE SECURITY TESTS PASSED SUCCESSFULLY';
END $$;

ROLLBACK;

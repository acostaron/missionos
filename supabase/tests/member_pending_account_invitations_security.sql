-- =============================================================================
-- Security Tests: member_pending_account_invitations_security.sql
-- Feature:        get_my_pending_account_invitations RPC
-- Non-destructive. All synthetic fixtures are inside a transaction and ROLLED BACK.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART 1: Function Execution ACLs
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  ASSERT has_function_privilege('authenticated', 'public.get_my_pending_account_invitations()', 'EXECUTE'),
    'ACL 1.1: authenticated must have execute privilege on get_my_pending_account_invitations';
  ASSERT NOT has_function_privilege('anon', 'public.get_my_pending_account_invitations()', 'EXECUTE'),
    'ACL 1.2: anon must NOT have execute privilege on get_my_pending_account_invitations';
  RAISE NOTICE 'PART 1 PASSED: ACL privileges verified';
END $$;

-- ---------------------------------------------------------------------------
-- PART 2: Functional Security & Lifecycle Scenarios
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_org_a uuid;
  v_org_b uuid;
  v_status_a uuid;
  v_status_b uuid;
  v_inviter uuid := gen_random_uuid();
  v_user_1 uuid := gen_random_uuid();
  v_user_2 uuid := gen_random_uuid();
  v_member_a uuid;
  v_member_b uuid;
  v_member_other uuid;
  v_inv_pending uuid;
  v_inv_sent uuid;
  v_inv_accepted uuid;
  v_inv_cancelled uuid;
  v_inv_failed uuid;
  v_inv_expired uuid;
  v_inv_user2 uuid;
  v_res jsonb;
  v_inv_item jsonb;
  v_err_occurred boolean := false;
BEGIN
  -- Setup Organizations
  SELECT id INTO v_org_a FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  IF v_org_a IS NULL THEN
    INSERT INTO public.organizations (code, name, organization_type, lifecycle_status, effective_from)
    VALUES ('org_a', 'Test Organization A', 'ministry', 'active', current_date)
    RETURNING id INTO v_org_a;
  END IF;

  INSERT INTO public.organizations (code, name, organization_type, lifecycle_status, effective_from)
  VALUES ('org_b_test', 'Test Organization B', 'ministry', 'active', current_date)
  RETURNING id INTO v_org_b;

  INSERT INTO public.member_statuses (organization_id, code, name, status_category, is_active_membership, is_active)
  VALUES (v_org_b, 'active', 'Active Member', 'active', true, true)
  RETURNING id INTO v_status_b;

  SELECT id INTO v_status_a FROM public.member_statuses WHERE organization_id = v_org_a LIMIT 1;

  -- Setup Auth Users
  INSERT INTO auth.users (id, aud, role, email)
  VALUES
    (v_inviter, 'authenticated', 'authenticated', 'inviter@invite-test.local'),
    (v_user_1, 'authenticated', 'authenticated', 'user1@invite-test.local'),
    (v_user_2, 'authenticated', 'authenticated', 'user2@invite-test.local');

  -- Setup Profiles
  INSERT INTO public.profiles (id, display_name, account_status)
  VALUES
    (v_inviter, 'Admin Inviter', 'active'),
    (v_user_1, 'User One', 'active'),
    (v_user_2, 'User Two', 'active');

  -- Setup Members in Orgs
  INSERT INTO public.members (organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_org_a, v_status_a, 'User One Member A', 'One, User', 'User1', 'active')
  RETURNING id INTO v_member_a;

  INSERT INTO public.members (organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_org_b, v_status_b, 'User One Member B', 'One, User', 'User1', 'active')
  RETURNING id INTO v_member_b;

  INSERT INTO public.members (organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_org_a, v_status_a, 'User Two Member', 'Two, User', 'User2', 'active')
  RETURNING id INTO v_member_other;

  -- -------------------------------------------------------------------------
  -- SCENARIO 2.1: Anonymous / Unauthenticated access is denied
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', null, true);
  PERFORM set_config('request.jwt.claims', null, true);

  v_err_occurred := false;
  BEGIN
    PERFORM public.get_my_pending_account_invitations();
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.1 FAILED: Anon call must be rejected';

  -- -------------------------------------------------------------------------
  -- SCENARIO 2.2: Authenticated user with no invitations returns empty array
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_1, 'role', 'authenticated')::text, true);

  v_res := public.get_my_pending_account_invitations();
  ASSERT v_res ? 'invitations', 'TEST 2.2.1 FAILED: Expected invitations key';
  ASSERT jsonb_array_length(v_res->'invitations') = 0, 'TEST 2.2.2 FAILED: Expected empty invitations array';

  -- -------------------------------------------------------------------------
  -- SCENARIO 2.3: Single pending existing-account invitation is returned
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status, invited_by_profile_id,
    invited_at, expires_at
  )
  VALUES (
    v_org_a, v_member_a, 'user1@invite-test.local', 'user1@invite-test.local',
    v_user_1, v_user_1, 'existing_account_invitation_pending', v_inviter,
    now() - interval '2 days', now() + interval '5 days'
  )
  RETURNING id INTO v_inv_pending;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_1, 'role', 'authenticated')::text, true);

  v_res := public.get_my_pending_account_invitations();
  ASSERT jsonb_array_length(v_res->'invitations') = 1, 'TEST 2.3.1 FAILED: Expected 1 invitation';
  v_inv_item := v_res->'invitations'->0;
  ASSERT (v_inv_item->>'invitation_id')::uuid = v_inv_pending, 'TEST 2.3.2 FAILED: Incorrect invitation_id';
  ASSERT (v_inv_item->>'organization_id')::uuid = v_org_a, 'TEST 2.3.3 FAILED: Incorrect organization_id';
  ASSERT v_inv_item->>'invitation_status' = 'existing_account_invitation_pending', 'TEST 2.3.4 FAILED: Incorrect invitation_status';

  -- -------------------------------------------------------------------------
  -- SCENARIO 2.4: Cross-org invitations belonging to same profile are returned
  --               (including 'sent' and 'existing_account_invitation_pending')
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status, invited_by_profile_id,
    invited_at, expires_at
  )
  VALUES (
    v_org_b, v_member_b, 'user1@invite-test.local', 'user1@invite-test.local',
    v_user_1, v_user_1, 'sent', v_inviter,
    now() - interval '1 day', now() + interval '6 days'
  )
  RETURNING id INTO v_inv_sent;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_1, 'role', 'authenticated')::text, true);

  v_res := public.get_my_pending_account_invitations();
  ASSERT jsonb_array_length(v_res->'invitations') = 2, 'TEST 2.4.1 FAILED: Expected 2 cross-org invitations';
  -- Verify sorting: oldest first (invited_at asc)
  ASSERT (v_res->'invitations'->0->>'invitation_id')::uuid = v_inv_pending, 'TEST 2.4.2 FAILED: Expected oldest invitation first';
  ASSERT (v_res->'invitations'->1->>'invitation_id')::uuid = v_inv_sent, 'TEST 2.4.3 FAILED: Expected newer invitation second';

  -- -------------------------------------------------------------------------
  -- SCENARIO 2.5: Security & Minimal Payload: No sensitive internals leaked
  -- -------------------------------------------------------------------------
  ASSERT NOT (v_inv_item ? 'member_id'), 'TEST 2.5.1 FAILED: member_id must NOT be exposed';
  ASSERT NOT (v_inv_item ? 'auth_user_id'), 'TEST 2.5.2 FAILED: auth_user_id must NOT be exposed';
  ASSERT NOT (v_inv_item ? 'profile_id'), 'TEST 2.5.3 FAILED: profile_id must NOT be exposed';
  ASSERT NOT (v_inv_item ? 'invited_by_profile_id'), 'TEST 2.5.4 FAILED: invited_by_profile_id must NOT be exposed';
  ASSERT NOT (v_inv_item ? 'failure_reason'), 'TEST 2.5.5 FAILED: failure_reason must NOT be exposed';

  -- -------------------------------------------------------------------------
  -- SCENARIO 2.6: Tenant isolation / Other user cannot see User 1's invitations
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_2::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_2, 'role', 'authenticated')::text, true);

  v_res := public.get_my_pending_account_invitations();
  ASSERT jsonb_array_length(v_res->'invitations') = 0, 'TEST 2.6.1 FAILED: User 2 must see 0 invitations';

  -- -------------------------------------------------------------------------
  -- SCENARIO 2.7: Exclusions: accepted, cancelled, failed, expired
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  -- Accepted
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status, invited_by_profile_id,
    invited_at, accepted_at
  )
  VALUES (
    v_org_a, v_member_other, 'user1@invite-test.local', 'user1@invite-test.local',
    v_user_1, v_user_1, 'accepted', v_inviter, now() - interval '3 days', now()
  );

  -- Cancelled
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status, invited_by_profile_id,
    invited_at, cancelled_at
  )
  VALUES (
    v_org_a, v_member_other, 'user1@invite-test.local', 'user1@invite-test.local',
    v_user_1, v_user_1, 'cancelled', v_inviter, now() - interval '3 days', now()
  );

  -- Failed
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status, invited_by_profile_id,
    invited_at, failure_reason
  )
  VALUES (
    v_org_a, v_member_other, 'user1@invite-test.local', 'user1@invite-test.local',
    v_user_1, v_user_1, 'failed', v_inviter, now() - interval '3 days', 'error'
  );

  -- Expired (invitation_status = 'expired')
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status, invited_by_profile_id,
    invited_at, expires_at
  )
  VALUES (
    v_org_a, v_member_other, 'user1@invite-test.local', 'user1@invite-test.local',
    v_user_1, v_user_1, 'expired', v_inviter, now() - interval '10 days', now() - interval '1 day'
  );

  -- Past expiration date on an otherwise pending invitation (in org_b with unique email)
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    auth_user_id, profile_id, invitation_status, invited_by_profile_id,
    invited_at, expires_at
  )
  VALUES (
    v_org_b, v_member_other, 'user1_past@invite-test.local', 'user1_past@invite-test.local',
    v_user_1, v_user_1, 'sent', v_inviter, now() - interval '10 days', now() - interval '1 day'
  );

  -- Re-query as User 1: count should STILL be exactly 2 (the valid pending and sent)
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_user_1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_1, 'role', 'authenticated')::text, true);

  v_res := public.get_my_pending_account_invitations();
  ASSERT jsonb_array_length(v_res->'invitations') = 2, 'TEST 2.7.1 FAILED: Excluded statuses must not be returned';

  RAISE NOTICE 'PART 2 PASSED: All functional security tests succeeded';
END $$;

ROLLBACK;

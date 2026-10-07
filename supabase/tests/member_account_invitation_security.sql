-- =============================================================================
-- Security Tests: member_account_invitation_security.sql
-- Feature:        Member account invitation backend foundation
--                 (members.accounts.provision, member_account_invitations,
--                  prepare_member_account_invitation,
--                  finalize_member_account_invitation,
--                  lookup_auth_user_for_invitation,
--                  record_member_account_invitation_failure)
-- Non-destructive. All synthetic fixtures are inside a transaction and
-- strictly ROLLED BACK.
-- =============================================================================

-- =============================================================================
-- PART 1: STATIC POSTURE & PERMISSION CHECKS
-- =============================================================================
DO $$
DECLARE
  v_count integer;
BEGIN
  -- 1.1 Permission is registered
  SELECT count(*) INTO v_count FROM public.permissions
  WHERE code = 'members.accounts.provision' AND domain_code = 'members'
    AND action_code = 'provision' AND scope_type = 'organization' AND is_active;
  ASSERT v_count = 1, 'PART 1.1 FAILED: permission members.accounts.provision not registered';

  -- 1.2 Granted to organization_administrator
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'members.accounts.provision' AND ar.code = 'organization_administrator'
    AND rp.permission_effect = 'allow' AND rp.approval_status = 'approved';
  ASSERT v_count = 1, 'PART 1.2 FAILED: org admin mapping missing';

  -- 1.3 Not granted to member role
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'members.accounts.provision' AND ar.code = 'member';
  ASSERT v_count = 0, 'PART 1.3 FAILED: permission granted to member role';

  -- 1.4 Not granted to servant leader roles
  SELECT count(*) INTO v_count
  FROM public.role_permissions rp
  JOIN public.app_roles ar ON ar.id = rp.app_role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE p.code = 'members.accounts.provision'
    AND ar.code IN (
      'household_servant_leader_access',
      'unit_servant_leader_access',
      'chapter_servant_leader_access',
      'area_servant_leader_access'
    );
  ASSERT v_count = 0, 'PART 1.4 FAILED: permission granted to servant leader roles';

  -- 1.5 Function execution ACLs
  ASSERT has_function_privilege('authenticated', 'public.prepare_member_account_invitation(uuid,uuid,text,boolean)', 'EXECUTE'),
    'ACL 1.5.1: authenticated prepare';
  ASSERT NOT has_function_privilege('anon', 'public.prepare_member_account_invitation(uuid,uuid,text,boolean)', 'EXECUTE'),
    'ACL 1.5.2: anon prepare denied';

  ASSERT NOT has_function_privilege('authenticated', 'public.finalize_member_account_invitation(uuid,uuid,uuid,text,uuid,text)', 'EXECUTE'),
    'ACL 1.5.3: authenticated finalize denied';
  ASSERT NOT has_function_privilege('anon', 'public.finalize_member_account_invitation(uuid,uuid,uuid,text,uuid,text)', 'EXECUTE'),
    'ACL 1.5.4: anon finalize denied';
  ASSERT has_function_privilege('service_role', 'public.finalize_member_account_invitation(uuid,uuid,uuid,text,uuid,text)', 'EXECUTE'),
    'ACL 1.5.5: service_role finalize allowed';

  ASSERT NOT has_function_privilege('authenticated', 'public.lookup_auth_user_for_invitation(uuid,text)', 'EXECUTE'),
    'ACL 1.5.6: authenticated lookup denied';
  ASSERT NOT has_function_privilege('anon', 'public.lookup_auth_user_for_invitation(uuid,text)', 'EXECUTE'),
    'ACL 1.5.7: anon lookup denied';
  ASSERT has_function_privilege('service_role', 'public.lookup_auth_user_for_invitation(uuid,text)', 'EXECUTE'),
    'ACL 1.5.8: service_role lookup allowed';

  ASSERT NOT has_function_privilege('authenticated', 'public.record_member_account_invitation_failure(uuid,uuid,text,uuid,text)', 'EXECUTE'),
    'ACL 1.5.9: authenticated failure helper denied';
  ASSERT NOT has_function_privilege('anon', 'public.record_member_account_invitation_failure(uuid,uuid,text,uuid,text)', 'EXECUTE'),
    'ACL 1.5.10: anon failure helper denied';
  ASSERT has_function_privilege('service_role', 'public.record_member_account_invitation_failure(uuid,uuid,text,uuid,text)', 'EXECUTE'),
    'ACL 1.5.11: service_role failure helper allowed';

  ASSERT NOT has_function_privilege('authenticated', 'private.can_provision_member_accounts(uuid)', 'EXECUTE'),
    'ACL 1.5.12: private helper hidden';

  RAISE NOTICE 'PART 1 PASSED: Static posture, permissions and ACLs verified';
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
  v_r_leader  uuid;
  v_status    uuid;
  v_status_b  uuid := gen_random_uuid();

  -- Actors
  v_adm       uuid := gen_random_uuid();
  v_adm_b     uuid := gen_random_uuid();
  v_plain     uuid := gen_random_uuid();
  v_lead      uuid := gen_random_uuid();

  -- Target Auth / Profiles
  v_target1   uuid := gen_random_uuid();
  v_linked_p  uuid := gen_random_uuid();

  -- Target Members in Org A
  v_m_active  uuid := gen_random_uuid();
  v_m_arch    uuid := gen_random_uuid();
  v_m_dec     uuid := gen_random_uuid();
  v_m_linked  uuid := gen_random_uuid();
  v_m_shared1 uuid := gen_random_uuid();
  v_m_shared2 uuid := gen_random_uuid();

  -- Target Member in Org B
  v_m_org_b   uuid := gen_random_uuid();

  v_res       jsonb;
  v_inv_id    uuid;
  v_err_occurred boolean;
  v_count     integer;
BEGIN
  -- Resolve existing master records
  SELECT id INTO v_org FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  SELECT id INTO v_r_admin  FROM public.app_roles WHERE code = 'organization_administrator';
  SELECT id INTO v_r_member FROM public.app_roles WHERE code = 'member';
  SELECT id INTO v_r_leader FROM public.app_roles WHERE code = 'unit_servant_leader_access';
  SELECT membership_status_id INTO v_status FROM public.members WHERE organization_id = v_org LIMIT 1;

  -- Create synthetic Org B
  INSERT INTO public.organizations (id, code, name, organization_type, lifecycle_status, effective_from)
  VALUES (v_org_b, 'zz_test_b', 'Test Org B', 'ministry', 'active', current_date);

  INSERT INTO public.member_statuses (id, organization_id, code, name, status_category, is_active_membership)
  VALUES (v_status_b, v_org_b, 'active', 'Active', 'active', true);

  -- Create auth users
  INSERT INTO auth.users (id, aud, role, email)
  SELECT p, 'authenticated', 'authenticated', p::text || '@test.local'
  FROM unnest(ARRAY[v_adm, v_adm_b, v_plain, v_lead, v_linked_p]) p;

  INSERT INTO auth.users (id, aud, role, email)
  VALUES (v_target1, 'authenticated', 'authenticated', 'candidate@missionos.local');

  -- Create caller profiles
  INSERT INTO public.profiles (id, display_name, account_status)
  VALUES
    (v_adm, 'Admin User', 'active'),
    (v_adm_b, 'Admin Org B', 'active'),
    (v_plain, 'Plain Member', 'active'),
    (v_lead, 'Unit Leader', 'active'),
    (v_linked_p, 'Already Linked Profile', 'active');

  -- Organization memberships for actors
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES
    (v_adm, v_org, 'active', now()),
    (v_adm_b, v_org_b, 'active', now()),
    (v_plain, v_org, 'active', now()),
    (v_lead, v_org, 'active', now()),
    (v_linked_p, v_org, 'active', now());

  -- Role assignments for actors
  INSERT INTO public.profile_role_assignments (profile_id, organization_id, app_role_id, assignment_status, proposed_at, approved_at, activated_at, effective_from_at)
  VALUES
    (v_adm, v_org, v_r_admin, 'active', now(), now(), now(), now()),
    (v_adm_b, v_org_b, v_r_admin, 'active', now(), now(), now(), now()),
    (v_plain, v_org, v_r_member, 'active', now(), now(), now(), now()),
    (v_lead, v_org, v_r_leader, 'active', now(), now(), now(), now());

  -- Target members
  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES
    (v_m_active, v_org, v_status, 'Active Candidate', 'Candidate, Active', 'Active', 'active'),
    (v_m_linked, v_org, v_status, 'Linked Member', 'Member, Linked', 'Linked', 'active'),
    (v_m_shared1, v_org, v_status, 'Shared Person 1', 'Person 1, Shared', 'Shared1', 'active'),
    (v_m_shared2, v_org, v_status, 'Shared Person 2', 'Person 2, Shared', 'Shared2', 'active'),
    (v_m_org_b, v_org_b, v_status_b, 'Org B Member', 'Member, Org B', 'OrgB', 'active');

  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status, archived_at, archive_reason)
  VALUES
    (v_m_arch, v_org, v_status, 'Archived Candidate', 'Candidate, Archived', 'Archived', 'archived', now(), 'testing');

  INSERT INTO public.members (id, organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status, is_deceased, deceased_on, deceased_on_precision)
  VALUES
    (v_m_dec, v_org, v_status, 'Deceased Candidate', 'Candidate, Deceased', 'Deceased', 'active', true, current_date - 10, 'exact');

  -- Pre-link v_m_linked to v_linked_p
  INSERT INTO public.profile_member_links (
    id, profile_id, organization_id, member_id, link_type, link_status,
    is_primary, verification_method, verified_at, verified_by_profile_id
  )
  VALUES (
    gen_random_uuid(), v_linked_p, v_org, v_m_linked, 'self', 'verified',
    true, 'admin_verified', now(), v_adm
  );

  -- Emails: shared email fixture
  INSERT INTO public.member_emails (
    organization_id, member_id, email_address, normalized_email, is_shared
  )
  VALUES
    (v_org, v_m_shared1, 'shared@missionos.local', 'shared@missionos.local', true),
    (v_org, v_m_shared2, 'multi@missionos.local', 'multi@missionos.local', false),
    (v_org, v_m_active, 'multi@missionos.local', 'multi@missionos.local', false);

  -- ---------------------------------------------------------------------------
  -- TEST 2.1: Unauthorized preflight denied (member role)
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_plain::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_plain, 'role', 'authenticated')::text, true);

  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_active, 'active@missionos.local');
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.1 FAILED: member role should be denied preflight';
  RAISE NOTICE 'TEST 2.1 PASSED: member role denied preflight';

  -- ---------------------------------------------------------------------------
  -- TEST 2.2: Unauthorized preflight denied (servant leader role)
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_lead::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_lead, 'role', 'authenticated')::text, true);

  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_active, 'active@missionos.local');
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.2 FAILED: servant leader should be denied preflight';
  RAISE NOTICE 'TEST 2.2 PASSED: servant leader denied preflight';

  -- ---------------------------------------------------------------------------
  -- TEST 2.3: Cross-organization preflight denied
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm_b::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm_b, 'role', 'authenticated')::text, true);

  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_active, 'active@missionos.local');
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.3 FAILED: cross-org admin should be denied preflight';
  RAISE NOTICE 'TEST 2.3 PASSED: cross-org preflight denied';

  -- Switch to authorized Org A Administrator
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  -- ---------------------------------------------------------------------------
  -- TEST 2.4: Cross-organization member rejected
  -- ---------------------------------------------------------------------------
  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_org_b, 'orgb@missionos.local');
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.4 FAILED: cross-org member should be rejected';
  RAISE NOTICE 'TEST 2.4 PASSED: cross-org member rejected';

  -- ---------------------------------------------------------------------------
  -- TEST 2.5: Archived member denied
  -- ---------------------------------------------------------------------------
  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_arch, 'arch@missionos.local');
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.5 FAILED: archived member should be rejected';
  RAISE NOTICE 'TEST 2.5 PASSED: archived member rejected';

  -- ---------------------------------------------------------------------------
  -- TEST 2.6: Deceased member denied
  -- ---------------------------------------------------------------------------
  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_dec, 'dec@missionos.local');
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.6 FAILED: deceased member should be rejected';
  RAISE NOTICE 'TEST 2.6 PASSED: deceased member rejected';

  -- ---------------------------------------------------------------------------
  -- TEST 2.7: Already-linked member denied
  -- ---------------------------------------------------------------------------
  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_linked, 'linked@missionos.local');
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.7 FAILED: already-linked member should be rejected';
  RAISE NOTICE 'TEST 2.7 PASSED: already-linked member rejected';

  -- ---------------------------------------------------------------------------
  -- TEST 2.8: Shared email behavior
  -- ---------------------------------------------------------------------------
  -- Unacknowledged shared email -> structured warning requirement
  v_res := public.prepare_member_account_invitation(v_org, v_m_shared1, 'shared@missionos.local', false);
  ASSERT (v_res->>'eligible')::boolean = false, 'TEST 2.8.1 FAILED: shared email should not be silently eligible';
  ASSERT v_res->>'status' = 'requires_shared_acknowledgment', 'TEST 2.8.2 FAILED: missing status requires_shared_acknowledgment';

  -- Acknowledged shared email -> passes with warning flag
  v_res := public.prepare_member_account_invitation(v_org, v_m_shared1, 'shared@missionos.local', true);
  ASSERT (v_res->>'eligible')::boolean = true, 'TEST 2.8.3 FAILED: acknowledged shared email should be eligible';
  ASSERT (v_res->>'is_shared_email')::boolean = true, 'TEST 2.8.4 FAILED: is_shared_email flag missing';

  -- Unacknowledged multi-member email -> structured warning requirement
  v_res := public.prepare_member_account_invitation(v_org, v_m_shared2, 'multi@missionos.local', false);
  ASSERT (v_res->>'eligible')::boolean = false, 'TEST 2.8.5 FAILED: multi-member email should not be silently eligible';
  ASSERT v_res->>'status' = 'requires_shared_acknowledgment', 'TEST 2.8.6 FAILED: missing status requires_shared_acknowledgment';
  RAISE NOTICE 'TEST 2.8 PASSED: shared email behavior matches contract';

  -- ---------------------------------------------------------------------------
  -- TEST 2.9: Preflight succeeds for eligible active member
  -- ---------------------------------------------------------------------------
  v_res := public.prepare_member_account_invitation(v_org, v_m_active, 'candidate@missionos.local', false);
  ASSERT (v_res->>'eligible')::boolean = true, 'TEST 2.9.1 FAILED: active candidate should be eligible';
  ASSERT v_res->>'status' = 'eligible', 'TEST 2.9.2 FAILED: status should be eligible';
  ASSERT (v_res->>'member_id')::uuid = v_m_active, 'TEST 2.9.3 FAILED: wrong member_id returned';
  RAISE NOTICE 'TEST 2.9 PASSED: preflight succeeds for eligible active member';

  -- ---------------------------------------------------------------------------
  -- TEST 2.10: Finalization (service_role context) creates:
  --   - profile pending
  --   - org membership invited
  --   - accepted_at null
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);

  v_res := public.finalize_member_account_invitation(
    v_org,
    v_m_active,
    v_target1,
    'candidate@missionos.local',
    v_adm,
    'sent'
  );
  v_inv_id := (v_res->>'invitation_id')::uuid;
  ASSERT v_inv_id IS NOT NULL, 'TEST 2.10.1 FAILED: invitation_id null';
  ASSERT v_res->>'status' = 'sent', 'TEST 2.10.2 FAILED: invitation status not sent';

  -- Invariant checks on profile:
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_count
  FROM public.profiles
  WHERE id = v_target1 AND account_status = 'pending';
  ASSERT v_count = 1, 'TEST 2.10.3 FAILED: profile pending not created';

  -- Invariant checks on organization membership:
  SELECT count(*) INTO v_count
  FROM public.profile_organization_memberships
  WHERE profile_id = v_target1 AND organization_id = v_org
    AND membership_status = 'invited' AND accepted_at IS NULL
    AND invited_at IS NOT NULL AND invited_by_profile_id = v_adm;
  ASSERT v_count = 1, 'TEST 2.10.4 FAILED: invited organization membership not created';

  -- Invariant checks on member_account_invitations:
  SELECT count(*) INTO v_count
  FROM public.member_account_invitations
  WHERE id = v_inv_id AND organization_id = v_org AND member_id = v_m_active
    AND normalized_email = 'candidate@missionos.local' AND auth_user_id = v_target1
    AND invitation_status = 'sent' AND accepted_at IS NULL;
  ASSERT v_count = 1, 'TEST 2.10.5 FAILED: invitation record mismatch';

  -- Invariant check on audit event:
  SELECT count(*) INTO v_count
  FROM audit.events
  WHERE organization_id = v_org AND event_code = 'members.account.invited'
    AND entity_id = v_m_active AND actor_profile_id = v_adm;
  ASSERT v_count >= 1, 'TEST 2.10.6 FAILED: audit event members.account.invited not written';
  RAISE NOTICE 'TEST 2.10 PASSED: finalization created profile, invited membership, and invitation state';

  -- ---------------------------------------------------------------------------
  -- TEST 2.11: CRITICAL INVARIANTS:
  --   NO verified profile_member_link exists
  --   NO member app role provisioned
  -- ---------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM public.profile_member_links
  WHERE profile_id = v_target1;
  ASSERT v_count = 0, 'TEST 2.11.1 FAILED: verified profile_member_link MUST NOT exist after invitation';

  SELECT count(*) INTO v_count
  FROM public.profile_role_assignments
  WHERE profile_id = v_target1;
  ASSERT v_count = 0, 'TEST 2.11.2 FAILED: member role MUST NOT be provisioned after invitation';
  RAISE NOTICE 'TEST 2.11 PASSED: no verified self-link and no member role provisioned';

  -- ---------------------------------------------------------------------------
  -- TEST 2.12: Finalization is idempotent
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);

  v_res := public.finalize_member_account_invitation(
    v_org,
    v_m_active,
    v_target1,
    'candidate@missionos.local',
    v_adm,
    'sent'
  );
  ASSERT (v_res->>'invitation_id')::uuid = v_inv_id, 'TEST 2.12.1 FAILED: invitation_id changed on repeat';

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_count FROM public.member_account_invitations WHERE organization_id = v_org AND member_id = v_m_active;
  ASSERT v_count = 1, 'TEST 2.12.2 FAILED: duplicate invitation records created';
  SELECT count(*) INTO v_count FROM public.profile_organization_memberships WHERE profile_id = v_target1 AND organization_id = v_org;
  ASSERT v_count = 1, 'TEST 2.12.3 FAILED: duplicate org membership created';
  RAISE NOTICE 'TEST 2.12 PASSED: finalization is idempotent';

  -- ---------------------------------------------------------------------------
  -- TEST 2.13: Duplicate invitation prevented in preflight
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  -- Member already has active invitation
  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_active, 'different@missionos.local');
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.13.1 FAILED: preflight should reject member with active invitation';

  -- Email already in active invitation for another member
  v_err_occurred := false;
  BEGIN
    PERFORM public.prepare_member_account_invitation(v_org, v_m_shared1, 'candidate@missionos.local', true);
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.13.2 FAILED: preflight should reject conflicting email in active invitation';
  RAISE NOTICE 'TEST 2.13 PASSED: duplicate active invitations prevented';

  -- ---------------------------------------------------------------------------
  -- TEST 2.14: Lookup helper & Usable Account Classification
  -- ---------------------------------------------------------------------------
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);

  -- 2.14.1: Confirmed candidate user
  PERFORM set_config('role', 'postgres', true);
  UPDATE auth.users SET email_confirmed_at = now() WHERE id = v_target1;
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  v_res := public.lookup_auth_user_for_invitation(v_org, 'candidate@missionos.local');
  ASSERT (v_res->>'user_exists')::boolean = true, 'TEST 2.14.1 FAILED: lookup user_exists false';
  ASSERT (v_res->>'auth_user_id')::uuid = v_target1, 'TEST 2.14.2 FAILED: wrong auth_user_id';
  ASSERT (v_res->>'is_usable')::boolean = true, 'TEST 2.14.3 FAILED: confirmed user should be usable';
  ASSERT (v_res->>'organization_membership_status') = 'invited', 'TEST 2.14.4 FAILED: membership status not invited';
  ASSERT (v_res->>'is_linked_to_member')::boolean = false, 'TEST 2.14.5 FAILED: is_linked_to_member should be false';

  -- 2.14.2: Unconfirmed user is unusable
  PERFORM set_config('role', 'postgres', true);
  UPDATE auth.users SET email_confirmed_at = null WHERE id = v_target1;
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  v_res := public.lookup_auth_user_for_invitation(v_org, 'candidate@missionos.local');
  ASSERT (v_res->>'is_usable')::boolean = false, 'TEST 2.14.6 FAILED: unconfirmed user should not be usable';
  ASSERT v_res->>'unusable_reason' = 'Auth user email is unconfirmed', 'TEST 2.14.7 FAILED: wrong unconfirmed reason';

  -- 2.14.3: Banned user is unusable
  PERFORM set_config('role', 'postgres', true);
  UPDATE auth.users SET email_confirmed_at = now(), banned_until = now() + interval '1 day' WHERE id = v_target1;
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  v_res := public.lookup_auth_user_for_invitation(v_org, 'candidate@missionos.local');
  ASSERT (v_res->>'is_usable')::boolean = false, 'TEST 2.14.8 FAILED: banned user should not be usable';
  ASSERT v_res->>'unusable_reason' = 'Auth user is currently banned', 'TEST 2.14.9 FAILED: wrong banned reason';

  -- Reset target user state
  PERFORM set_config('role', 'postgres', true);
  UPDATE auth.users SET banned_until = null WHERE id = v_target1;
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);

  -- 2.14.4: Lookup on already linked user
  v_res := public.lookup_auth_user_for_invitation(v_org, v_linked_p::text || '@test.local');
  ASSERT (v_res->>'is_linked_to_member')::boolean = true, 'TEST 2.14.10 FAILED: should be linked to member';
  ASSERT (v_res->>'linked_member_id')::uuid = v_m_linked, 'TEST 2.14.11 FAILED: wrong linked member id';
  RAISE NOTICE 'TEST 2.14 PASSED: lookup_auth_user_for_invitation and usable classification verified';

  -- ---------------------------------------------------------------------------
  -- TEST 2.15: Failure helper & FK clearance for safe compensation
  -- ---------------------------------------------------------------------------
  v_res := public.record_member_account_invitation_failure(
    v_org,
    v_m_active,
    'candidate@missionos.local',
    v_adm,
    'Synthetic failure test'
  );
  ASSERT v_res->>'status' = 'failed', 'TEST 2.15.1 FAILED: failure helper did not return failed status';

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_count
  FROM public.member_account_invitations
  WHERE id = v_inv_id AND invitation_status = 'failed'
    AND failure_reason = 'Synthetic failure test'
    AND auth_user_id IS NULL AND profile_id IS NULL;
  ASSERT v_count = 1, 'TEST 2.15.2 FAILED: invitation status not transitioned to failed or FKs not cleared';
  RAISE NOTICE 'TEST 2.15 PASSED: record_member_account_invitation_failure and FK safety verified';

  -- ---------------------------------------------------------------------------
  -- TEST 2.16: Case 2 Existing Auth User with Active Usable Account
  -- ---------------------------------------------------------------------------
  DECLARE
    v_target2 uuid := gen_random_uuid();
    v_inv_id2 uuid;
  BEGIN
    PERFORM set_config('role', 'postgres', true);
    INSERT INTO auth.users (id, aud, role, email, email_confirmed_at)
    VALUES (v_target2, 'authenticated', 'authenticated', 'existing@missionos.local', now());

    INSERT INTO public.profiles (id, display_name, account_status)
    VALUES (v_target2, 'Existing Usable User', 'active');

    PERFORM set_config('role', 'service_role', true);
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);

    v_res := public.finalize_member_account_invitation(
      v_org,
      v_m_shared1,
      v_target2,
      'existing@missionos.local',
      v_adm,
      'existing_account_invitation_pending'
    );
    v_inv_id2 := (v_res->>'invitation_id')::uuid;
    ASSERT v_res->>'status' = 'existing_account_invitation_pending', 'TEST 2.16.1 FAILED: status should be existing_account_invitation_pending';

    -- Verify membership is invited and accepted_at is NULL
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) INTO v_count
    FROM public.profile_organization_memberships
    WHERE profile_id = v_target2 AND organization_id = v_org
      AND membership_status = 'invited' AND accepted_at IS NULL;
    ASSERT v_count = 1, 'TEST 2.16.2 FAILED: membership not invited or accepted_at not null';

    -- Critical invariants: NO verified link and NO member role
    SELECT count(*) INTO v_count FROM public.profile_member_links WHERE profile_id = v_target2;
    ASSERT v_count = 0, 'TEST 2.16.3 FAILED: profile_member_link must not exist for existing user invite';

    SELECT count(*) INTO v_count FROM public.profile_role_assignments WHERE profile_id = v_target2;
    ASSERT v_count = 0, 'TEST 2.16.4 FAILED: member role must not exist for existing user invite';

    -- Active invitation prevents duplicate in preflight
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_err_occurred := false;
    BEGIN
      PERFORM public.prepare_member_account_invitation(v_org, v_m_shared1, 'another@missionos.local', true);
    EXCEPTION WHEN OTHERS THEN
      v_err_occurred := true;
    END;
    ASSERT v_err_occurred, 'TEST 2.16.5 FAILED: member with existing_account_invitation_pending must reject duplicate preflight';

    RAISE NOTICE 'TEST 2.16 PASSED: Case 2 existing user invitation, status and invariants verified';
  END;

  -- ---------------------------------------------------------------------------
  -- TEST 2.17: Row Level Security on member_account_invitations
  -- ---------------------------------------------------------------------------
  -- Admin can see invitations
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_count FROM public.member_account_invitations WHERE id = v_inv_id;
  ASSERT v_count = 1, 'TEST 2.17.1 FAILED: admin cannot see invitation';

  -- Plain member cannot see invitations
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_plain::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_plain, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_count FROM public.member_account_invitations WHERE id = v_inv_id;
  ASSERT v_count = 0, 'TEST 2.17.2 FAILED: plain member should not see invitation';

  -- Target user can see own invitation
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.member_account_invitations SET profile_id = v_target1 WHERE id = v_inv_id;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_target1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_target1, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_count FROM public.member_account_invitations WHERE id = v_inv_id;
  ASSERT v_count = 1, 'TEST 2.17.3 FAILED: target profile should see own invitation';
  RAISE NOTICE 'TEST 2.17 PASSED: RLS on member_account_invitations verified';

  RAISE NOTICE 'ALL INVITATION SECURITY TESTS PASSED SUCCESSFULLY';
END $$;

ROLLBACK;


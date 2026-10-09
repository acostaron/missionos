-- =============================================================================
-- Security Tests: member_account_status_read_security.sql
-- Feature:        get_member_account_status RPC
-- Non-destructive. All synthetic fixtures are inside a transaction and ROLLED BACK.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART 1: Function Execution ACLs
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  ASSERT has_function_privilege('authenticated', 'public.get_member_account_status(uuid,uuid)', 'EXECUTE'),
    'ACL 1.1: authenticated must have execute privilege on get_member_account_status';
  ASSERT NOT has_function_privilege('anon', 'public.get_member_account_status(uuid,uuid)', 'EXECUTE'),
    'ACL 1.2: anon must NOT have execute privilege on get_member_account_status';
  RAISE NOTICE 'PART 1 PASSED: ACL privileges verified';
END $$;

-- ---------------------------------------------------------------------------
-- PART 2: Functional Security & Account State Scenarios
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_status uuid;
  v_adm uuid := gen_random_uuid();
  v_plain uuid := gen_random_uuid();
  v_m_active uuid;
  v_m_archived uuid;
  v_m_deceased uuid;
  v_target_profile uuid := gen_random_uuid();
  v_res jsonb;
  v_err_occurred boolean := false;
  v_role_id uuid;
  v_link_id uuid;
  v_inv_id uuid;
BEGIN
  -- Use existing organization
  SELECT id INTO v_org FROM public.organizations WHERE code = 'mfcny' LIMIT 1;
  IF v_org IS NULL THEN
    INSERT INTO public.organizations (code, name, organization_type, lifecycle_status, effective_from)
    VALUES ('zz_ast', 'Account Status Test Org', 'ministry', 'active', current_date)
    RETURNING id INTO v_org;
  END IF;

  SELECT id INTO v_status FROM public.member_statuses WHERE organization_id = v_org LIMIT 1;

  -- Setup auth users
  INSERT INTO auth.users (id, aud, role, email)
  VALUES
    (v_adm, 'authenticated', 'authenticated', 'admin@status.local'),
    (v_plain, 'authenticated', 'authenticated', 'plain@status.local'),
    (v_target_profile, 'authenticated', 'authenticated', 'target@status.local');

  -- Setup profiles
  INSERT INTO public.profiles (id, display_name, account_status)
  VALUES
    (v_adm, 'Admin Profile', 'active'),
    (v_plain, 'Plain Profile', 'active'),
    (v_target_profile, 'Target Profile', 'active');

  -- Organization memberships
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES
    (v_adm, v_org, 'active', now()),
    (v_plain, v_org, 'active', now());

  -- Grant organization_administrator to v_adm
  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status, proposed_at, approved_at, activated_at, effective_from_at
  )
  SELECT v_adm, v_org, ar.id, 'active', now(), now(), now(), now()
  FROM public.app_roles ar
  WHERE ar.code = 'organization_administrator' AND ar.is_system_role;

  -- Create active member
  INSERT INTO public.members (organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status)
  VALUES (v_org, v_status, 'Active Member', 'Member, Active', 'Active', 'active')
  RETURNING id INTO v_m_active;

  -- Add email for active member
  INSERT INTO public.member_emails (
    organization_id, member_id, email_address, normalized_email, email_type, is_primary, is_shared
  )
  VALUES (v_org, v_m_active, 'active.member@status.local', 'active.member@status.local', 'personal', true, false);

  -- Create archived member
  INSERT INTO public.members (organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status, archived_at, archive_reason)
  VALUES (v_org, v_status, 'Archived Member', 'Member, Archived', 'Archived', 'archived', now(), 'testing')
  RETURNING id INTO v_m_archived;

  -- Create deceased member
  INSERT INTO public.members (organization_id, membership_status_id, display_name, sort_name, preferred_name, record_status, is_deceased, deceased_on, deceased_on_precision)
  VALUES (v_org, v_status, 'Deceased Member', 'Member, Deceased', 'Deceased', 'active', true, current_date - 10, 'exact')
  RETURNING id INTO v_m_deceased;

  -- -------------------------------------------------------------------------
  -- TEST 2.1: Plain user is rejected (42501)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_plain::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_plain, 'role', 'authenticated')::text, true);

  v_err_occurred := false;
  BEGIN
    PERFORM public.get_member_account_status(v_org, v_m_active);
  EXCEPTION WHEN OTHERS THEN
    v_err_occurred := true;
  END;
  ASSERT v_err_occurred, 'TEST 2.1 FAILED: Plain user without permission should be rejected';

  -- -------------------------------------------------------------------------
  -- TEST 2.2: Admin user succeeds - state 'none' with suggested emails
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  v_res := public.get_member_account_status(v_org, v_m_active);
  ASSERT v_res->>'account_state' = 'none', 'TEST 2.2.1 FAILED: Expected state none';
  ASSERT jsonb_array_length(v_res->'suggested_emails') = 1, 'TEST 2.2.2 FAILED: Expected 1 suggested email';
  ASSERT (v_res->'suggested_emails'->0->>'is_shared')::boolean = false, 'TEST 2.2.3 FAILED: Expected individual email';

  -- -------------------------------------------------------------------------
  -- TEST 2.3: Ineligible members return state 'unavailable'
  -- -------------------------------------------------------------------------
  v_res := public.get_member_account_status(v_org, v_m_archived);
  ASSERT v_res->>'account_state' = 'unavailable', 'TEST 2.3.1 FAILED: Archived member should be unavailable';

  v_res := public.get_member_account_status(v_org, v_m_deceased);
  ASSERT v_res->>'account_state' = 'unavailable', 'TEST 2.3.2 FAILED: Deceased member should be unavailable';

  -- -------------------------------------------------------------------------
  -- TEST 2.4: State 'invitation_pending'
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.member_account_invitations (
    organization_id, member_id, email, normalized_email,
    invitation_status, invited_by_profile_id, invited_at
  )
  VALUES (
    v_org, v_m_active, 'active.member@status.local', 'active.member@status.local',
    'sent', v_adm, now()
  )
  RETURNING id INTO v_inv_id;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  v_res := public.get_member_account_status(v_org, v_m_active);
  ASSERT v_res->>'account_state' = 'invitation_pending', 'TEST 2.4.1 FAILED: Expected state invitation_pending';
  ASSERT v_res->>'invitation_status' = 'sent', 'TEST 2.4.2 FAILED: Expected status sent';
  ASSERT v_res->>'email' = 'active.member@status.local', 'TEST 2.4.3 FAILED: Expected target email';

  -- -------------------------------------------------------------------------
  -- TEST 2.5: State 'active' when linked and active member role present
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  -- Update invitation to accepted
  UPDATE public.member_account_invitations
  SET invitation_status = 'accepted', accepted_at = now(), profile_id = v_target_profile
  WHERE id = v_inv_id;

  -- Add active membership for target
  INSERT INTO public.profile_organization_memberships (
    profile_id, organization_id, membership_status, accepted_at
  )
  VALUES (v_target_profile, v_org, 'active', now());

  -- Add verified self link
  INSERT INTO public.profile_member_links (
    organization_id, member_id, profile_id, link_type, link_status, is_primary, verification_method, verified_at, verified_by_profile_id
  )
  VALUES (
    v_org, v_m_active, v_target_profile, 'self', 'verified', true, 'admin_verified', now(), v_adm
  )
  RETURNING id INTO v_link_id;

  -- Add active member role
  SELECT ar.id INTO v_role_id
  FROM public.app_roles ar
  WHERE ar.code = 'member' AND ar.is_system_role AND ar.organization_id IS NULL;

  INSERT INTO public.profile_role_assignments (
    profile_id, organization_id, app_role_id, assignment_status, proposed_at, approved_at, activated_at, effective_from_at
  )
  VALUES (v_target_profile, v_org, v_role_id, 'active', now(), now(), now(), now());

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  v_res := public.get_member_account_status(v_org, v_m_active);
  ASSERT v_res->>'account_state' = 'active', 'TEST 2.5.1 FAILED: Expected state active';
  ASSERT v_res->>'email' = 'target@status.local', 'TEST 2.5.2 FAILED: Expected target email';
  ASSERT v_res->>'linked_at' IS NOT NULL, 'TEST 2.5.3 FAILED: linked_at should not be null';

  -- -------------------------------------------------------------------------
  -- TEST 2.6: State 'needs_review' when drift occurs (e.g. member archived while linked)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.members SET record_status = 'archived', archived_at = now() WHERE id = v_m_active;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  v_res := public.get_member_account_status(v_org, v_m_active);
  ASSERT v_res->>'account_state' = 'needs_review', 'TEST 2.6.1 FAILED: Drift should result in needs_review';

  RAISE NOTICE 'PART 2 PASSED: All functional status scenarios verified';
END $$;

ROLLBACK;

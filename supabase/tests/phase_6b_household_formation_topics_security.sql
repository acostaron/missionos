-- =============================================================================
-- Test Suite: phase_6b_household_formation_topics_security.sql
-- Phase:      Phase 6B-10B — Household Formation Security Tests
--
-- Objective:
--   Validate the Household Formation domain (formation_topics,
--   household_topic_assignments and the formation RPCs) for:
--   - Admin workflow (create topic, assign, reschedule, complete, skip, cancel)
--   - Delegated HSL/USL/CSL/ASL read vs. write scope (Phase 6B-9 double-lock)
--   - Leadership without delegated access / delegated access without leadership
--   - Verified spouse and Fraternal facilitator receive no write authority
--   - Meeting linkage rules, attendance independence, member-level independence
--   - Factual status logic, repeat topics, history/pagination, plan ordering
--   - Privacy (no PII / free text / resolution_notes), RPC ACLs
--   - Inactive household behavior (admin cleanup only; delegated denied)
--   - Dashboard formation_operations_summary and profile formation_summary
--
-- All fixtures are transactional (BEGIN ... ROLLBACK). No persistent data.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Transaction-local helpers
-- -----------------------------------------------------------------------------

CREATE TEMP TABLE t_fx (key text PRIMARY KEY, id uuid);
CREATE TEMP TABLE t_checks (n serial PRIMARY KEY, label text NOT NULL);

CREATE FUNCTION pg_temp.fx(k text) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM pg_temp.t_fx WHERE key = k;
$$;

CREATE FUNCTION pg_temp.setfx(k text, v uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO pg_temp.t_fx (key, id) VALUES (k, v);
$$;

CREATE FUNCTION pg_temp.ok(p_cond boolean, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS NOT TRUE THEN
    RAISE EXCEPTION 'CHECK FAILED: %', p_label;
  END IF;
  INSERT INTO pg_temp.t_checks (label) VALUES (p_label);
END;
$$;

CREATE FUNCTION pg_temp.act_as(k text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', pg_temp.fx(k), 'role', 'authenticated')::text, true);
$$;

CREATE FUNCTION pg_temp.mk_node(
  p_key text, p_type text, p_name text, p_parent text DEFAULT NULL,
  p_level text DEFAULT NULL, p_status text DEFAULT 'active'
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id  uuid := gen_random_uuid();
  v_org uuid := pg_temp.fx('org');
BEGIN
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  SELECT v_id, v_org, gnt.id, 'tfx_' || p_key || '_' || floor(random() * 999999)::text, p_name, p_status
  FROM public.governance_node_types gnt
  WHERE gnt.code = p_type AND gnt.organization_id = v_org;

  IF p_parent IS NOT NULL THEN
    INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary)
    VALUES (v_org, pg_temp.fx(p_parent), v_id, 'primary_parent', 'active', true);
  END IF;

  IF p_level IS NOT NULL THEN
    INSERT INTO public.households (id, organization_id, pastoral_level, household_category, meeting_frequency)
    VALUES (v_id, v_org, p_level, 'pastoral', 'weekly');
  END IF;

  INSERT INTO pg_temp.t_fx (key, id) VALUES (p_key, v_id);
  RETURN v_id;
END;
$$;

CREATE FUNCTION pg_temp.mk_person(
  p_key text, p_given text, p_family text, p_gov_node_key text,
  p_hh_key text DEFAULT NULL, p_leader boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_org    uuid := pg_temp.fx('org');
  v_admin  uuid := pg_temp.fx('admin');
  v_member uuid;
  v_prof   uuid := gen_random_uuid();
BEGIN
  v_member := (public.create_member(
    p_organization_id => v_org, p_given_names => p_given, p_family_name => p_family,
    p_governance_node_id => pg_temp.fx(p_gov_node_key)))->>'member_id';

  INSERT INTO pg_temp.t_fx (key, id) VALUES (p_key || '_member', v_member);

  IF p_hh_key IS NOT NULL THEN
    IF p_leader THEN
      INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, is_primary, membership_status, membership_role, effective_from)
      VALUES (v_org, pg_temp.fx(p_hh_key), v_member, true, 'active', 'servant', current_date - 30);
    ELSE
      INSERT INTO public.household_memberships (organization_id, household_node_id, member_id, is_primary, membership_status, effective_from)
      VALUES (v_org, pg_temp.fx(p_hh_key), v_member, true, 'active', current_date - 30);
    END IF;
  END IF;

  INSERT INTO auth.users (id, aud, role, email) VALUES (v_prof, 'authenticated', 'authenticated', p_key || '@fxtest.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_prof, p_given || ' ' || p_family || ' Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_prof, v_org, 'active', now());
  INSERT INTO public.profile_member_links (profile_id, organization_id, member_id, link_type, link_status, is_primary, verified_at, verified_by_profile_id, verification_method)
  VALUES (v_prof, v_org, v_member, 'self', 'verified', true, now(), v_admin, 'administrative');
  INSERT INTO pg_temp.t_fx (key, id) VALUES (p_key || '_profile', v_prof);
END;
$$;

CREATE FUNCTION pg_temp.mk_assign(
  p_key text, p_hh text, p_topic text, p_date date DEFAULT NULL, p_seq integer DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  r := public.assign_household_topic(pg_temp.fx('org'), pg_temp.fx(p_hh), pg_temp.fx(p_topic), p_date, p_seq);
  INSERT INTO pg_temp.t_fx (key, id) VALUES (p_key, (r->>'assignment_id')::uuid);
  RETURN r;
END;
$$;

CREATE FUNCTION pg_temp.mk_meeting(
  p_key text, p_hh text, p_off integer DEFAULT -1, p_mode text DEFAULT 'completed'
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  r     jsonb;
  v_id  uuid;
  v_org uuid := pg_temp.fx('org');
BEGIN
  r := public.create_household_meeting(v_org, pg_temp.fx(p_hh), current_date + p_off, 'regular_household');
  v_id := (r->>'household_meeting_id')::uuid;
  IF p_mode = 'completed' THEN
    PERFORM public.complete_household_meeting(v_org, v_id);
  ELSIF p_mode = 'cancelled' THEN
    PERFORM public.cancel_household_meeting(v_org, v_id, 'fixture');
  END IF;
  INSERT INTO pg_temp.t_fx (key, id) VALUES (p_key, v_id);
  RETURN v_id;
END;
$$;

-- Error-capturing wrappers: return 'OK' or the SQLSTATE
CREATE FUNCTION pg_temp.e_assign(p_hh text, p_topic text, p_date date DEFAULT NULL, p_seq integer DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.assign_household_topic(pg_temp.fx('org'), pg_temp.fx(p_hh), pg_temp.fx(p_topic), p_date, p_seq);
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END;
$$;

CREATE FUNCTION pg_temp.e_resched(p_assign text, p_date date) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.reschedule_household_topic(pg_temp.fx('org'), pg_temp.fx(p_assign), p_date);
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END;
$$;

CREATE FUNCTION pg_temp.e_complete(p_assign text, p_meeting text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.complete_household_topic(pg_temp.fx('org'), pg_temp.fx(p_assign), pg_temp.fx(p_meeting));
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END;
$$;

CREATE FUNCTION pg_temp.e_skip(p_assign text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.skip_household_topic(pg_temp.fx('org'), pg_temp.fx(p_assign), 'not_applicable');
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END;
$$;

CREATE FUNCTION pg_temp.e_cancel(p_assign text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.cancel_household_topic_assignment(pg_temp.fx('org'), pg_temp.fx(p_assign), 'schedule_change');
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END;
$$;

CREATE FUNCTION pg_temp.e_plan(p_hh text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.get_household_formation_plan(pg_temp.fx('org'), pg_temp.fx(p_hh));
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END;
$$;

CREATE FUNCTION pg_temp.e_hist(p_hh text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.get_household_topic_history(pg_temp.fx('org'), pg_temp.fx(p_hh));
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END;
$$;

-- -----------------------------------------------------------------------------
-- FIXTURES
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org    uuid;
  v_admin  uuid;
  v_res    jsonb;
  v_pra    uuid := gen_random_uuid();
  v_role   uuid;
  v_stale  uuid := gen_random_uuid();
  v_frt    uuid;
  v_fam    uuid;
BEGIN
  SELECT id INTO STRICT v_org FROM public.organizations ORDER BY created_at LIMIT 1;

  SELECT p.id INTO STRICT v_admin
  FROM public.profiles p
  JOIN public.profile_role_assignments pra ON pra.profile_id = p.id
  JOIN public.app_roles ar ON ar.id = pra.app_role_id
  WHERE pra.organization_id = v_org
    AND ar.code = 'organization_administrator'
    AND pra.assignment_status = 'active'
  LIMIT 1;

  PERFORM pg_temp.setfx('org', v_org);
  PERFORM pg_temp.setfx('admin', v_admin);
  PERFORM pg_temp.act_as('admin');

  -- Governance tree: Area -> Chapters 1/2 -> Units 1/2 (under Chapter 1)
  PERFORM pg_temp.mk_node('area', 'area_state', 'Fx Area North');
  PERFORM pg_temp.mk_node('c1', 'chapter', 'Fx Chapter One', 'area');
  PERFORM pg_temp.mk_node('c2', 'chapter', 'Fx Chapter Two (Sibling)', 'area');
  PERFORM pg_temp.mk_node('u1', 'unit', 'Fx Unit One', 'c1');
  PERFORM pg_temp.mk_node('u2', 'unit', 'Fx Unit Two (Sibling)', 'c1');

  -- Households
  PERFORM pg_temp.mk_node('hha', 'household', 'Fx Member HH A', 'u1', 'member');
  PERFORM pg_temp.mk_node('hhb', 'household', 'Fx Member HH B (Sibling Unit)', 'u2', 'member');
  PERFORM pg_temp.mk_node('hhn', 'household', 'Fx Member HH N (no access)', 'u1', 'member');
  PERFORM pg_temp.mk_node('hst', 'household', 'Fx Member HH Status', 'u1', 'member');
  PERFORM pg_temp.mk_node('hhr', 'household', 'Fx Member HH Report', 'u1', 'member');
  PERFORM pg_temp.mk_node('hi',  'household', 'Fx Member HH Inactive-Admin', 'u1', 'member');
  PERFORM pg_temp.mk_node('hu',  'household', 'Fx Unit 1 Household', 'u1', 'unit');
  PERFORM pg_temp.mk_node('hu2', 'household', 'Fx Unit 2 Household (Sibling)', 'u2', 'unit');
  PERFORM pg_temp.mk_node('hc',  'household', 'Fx Chapter 1 Household', 'c1', 'chapter');
  PERFORM pg_temp.mk_node('hc2', 'household', 'Fx Chapter 2 Household (Sibling)', 'c2', 'chapter');
  PERFORM pg_temp.mk_node('har', 'household', 'Fx Area Household', 'area', 'area');
  PERFORM pg_temp.mk_node('hf',  'household', 'Fx Area Fraternal Household', 'area', 'fraternal');

  -- People (members + profiles)
  PERFORM pg_temp.mk_person('hsl',    'Hsl',    'Fx', 'u1',   'hha', true);
  PERFORM pg_temp.mk_person('spouse', 'Spouse', 'Fx', 'u1',   'hha', true);
  PERFORM pg_temp.mk_person('na',     'Noaccess', 'Fx', 'u1', 'hhn', true);
  PERFORM pg_temp.mk_person('usl',    'Usl',    'Fx', 'u1');
  PERFORM pg_temp.mk_person('csl',    'Csl',    'Fx', 'c1');
  PERFORM pg_temp.mk_person('asl',    'Asl',    'Fx', 'area');
  PERFORM pg_temp.mk_person('fac',    'Facil',  'Fx', 'area');
  PERFORM pg_temp.mk_person('r1',     'Roster', 'One', 'u1', 'hha');
  PERFORM pg_temp.mk_person('r2',     'Roster', 'Two', 'u1', 'hha');

  -- Profile with a delegated role/scope but NO leadership assignment
  INSERT INTO auth.users (id, aud, role, email) VALUES (v_stale, 'authenticated', 'authenticated', 'stale@fxtest.local');
  INSERT INTO public.profiles (id, display_name, account_status) VALUES (v_stale, 'Stale Profile', 'active');
  INSERT INTO public.profile_organization_memberships (profile_id, organization_id, membership_status, accepted_at)
  VALUES (v_stale, v_org, 'active', now());
  PERFORM pg_temp.setfx('stale_profile', v_stale);

  SELECT id INTO STRICT v_role FROM public.app_roles WHERE code = 'household_servant_leader_access';
  INSERT INTO public.profile_role_assignments (id, organization_id, profile_id, app_role_id, source_type, assignment_status, proposed_at, approved_at, activated_at, effective_from_at)
  VALUES (v_pra, v_org, v_stale, v_role, 'manual', 'active', now(), now(), now(), now());
  INSERT INTO public.profile_scope_assignments (organization_id, profile_role_assignment_id, scope_type, governance_node_id, scope_effect, includes_descendants, assignment_status, effective_from_at, assigned_at)
  VALUES (v_org, v_pra, 'governance_node', pg_temp.fx('hha'), 'include', false, 'active', now(), now());

  -- Verified spouse relationship: HSL <-> Spouse
  SELECT id INTO STRICT v_frt FROM public.family_relationship_types WHERE code = 'spouse' LIMIT 1;
  v_fam := gen_random_uuid();
  INSERT INTO public.families (id, organization_id, family_name, display_name, family_status)
  VALUES (v_fam, v_org, 'FxFormation Family', 'The FxFormation Family', 'active');
  INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status, effective_from)
  VALUES (v_org, v_fam, pg_temp.fx('hsl_member'), 'spouse', 'active', current_date - 30),
         (v_org, v_fam, pg_temp.fx('spouse_member'), 'spouse', 'active', current_date - 30);
  INSERT INTO public.family_relationships (organization_id, family_id, from_member_id, to_member_id, relationship_type_id, relationship_status, is_primary_relationship, verification_status, verified_at, effective_from)
  VALUES (v_org, v_fam, least(pg_temp.fx('hsl_member'), pg_temp.fx('spouse_member')), greatest(pg_temp.fx('hsl_member'), pg_temp.fx('spouse_member')), v_frt, 'active', true, 'administrator_verified', now(), current_date - 30);

  -- Formal leadership appointments
  v_res := public.appoint_servant_leader(v_org, 'household_servant_leader', pg_temp.fx('hha'), pg_temp.fx('hsl_member'), current_date - 10, 'Initial appointment');
  PERFORM pg_temp.setfx('la_hsl', (v_res->>'leadership_assignment_id')::uuid);
  v_res := public.appoint_servant_leader(v_org, 'household_servant_leader', pg_temp.fx('hhn'), pg_temp.fx('na_member'), current_date - 10, 'Initial appointment');
  PERFORM pg_temp.setfx('la_na', (v_res->>'leadership_assignment_id')::uuid);
  v_res := public.appoint_servant_leader(v_org, 'unit_servant_leader', pg_temp.fx('u1'), pg_temp.fx('usl_member'), current_date - 10, 'Initial appointment');
  PERFORM pg_temp.setfx('la_usl', (v_res->>'leadership_assignment_id')::uuid);
  v_res := public.appoint_servant_leader(v_org, 'chapter_servant_leader', pg_temp.fx('c1'), pg_temp.fx('csl_member'), current_date - 10, 'Initial appointment');
  PERFORM pg_temp.setfx('la_csl', (v_res->>'leadership_assignment_id')::uuid);
  v_res := public.appoint_servant_leader(v_org, 'area_servant_leader', pg_temp.fx('area'), pg_temp.fx('asl_member'), current_date - 10, 'Initial appointment');
  PERFORM pg_temp.setfx('la_asl', (v_res->>'leadership_assignment_id')::uuid);

  -- Delegated access grants (NOT for 'na': formal leadership only)
  PERFORM public.grant_servant_leader_access(v_org, pg_temp.fx('la_hsl'), pg_temp.fx('hsl_profile'));
  PERFORM public.grant_servant_leader_access(v_org, pg_temp.fx('la_usl'), pg_temp.fx('usl_profile'));
  PERFORM public.grant_servant_leader_access(v_org, pg_temp.fx('la_csl'), pg_temp.fx('csl_profile'));
  PERFORM public.grant_servant_leader_access(v_org, pg_temp.fx('la_asl'), pg_temp.fx('asl_profile'));

  -- Organization-specific formation topics (created later by the admin workflow test)
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST A: ADMIN WORKFLOW (sections 2, 17-18 partial)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid := pg_temp.fx('org');
  r     jsonb;
BEGIN
  PERFORM pg_temp.act_as('admin');

  -- A.1 Create org-specific topics
  r := public.create_formation_topic(v_org, 'Fx Topic Alpha', 'household_topic');
  PERFORM pg_temp.setfx('t_a', (r->>'id')::uuid);
  r := public.create_formation_topic(v_org, 'Fx Topic Beta', 'scripture_reflection');
  PERFORM pg_temp.setfx('t_b', (r->>'id')::uuid);
  r := public.create_formation_topic(v_org, 'Fx Topic Gamma', 'special_topic');
  PERFORM pg_temp.setfx('t_c', (r->>'id')::uuid);
  PERFORM pg_temp.ok(
    (SELECT count(*) FROM public.formation_topics WHERE id = pg_temp.fx('t_a') AND organization_id = v_org) = 1,
    'A.1 admin creates an organization-specific formation topic');

  -- A.2 Assign
  r := pg_temp.mk_assign('a_adm_1', 'hha', 't_a', current_date + 7, 1);
  PERFORM pg_temp.ok(r->>'assignment_status' = 'planned', 'A.2 admin assigns a topic to a household (planned)');

  -- A.3 Reschedule
  r := public.reschedule_household_topic(v_org, pg_temp.fx('a_adm_1'), current_date + 8);
  PERFORM pg_temp.ok((r->>'planned_for_date')::date = current_date + 8 AND r->>'assignment_status' = 'planned',
    'A.3 admin reschedules a planned assignment');

  -- A.4 Complete with a completed meeting
  PERFORM pg_temp.mk_meeting('m_adm', 'hha', -1);
  r := public.complete_household_topic(v_org, pg_temp.fx('a_adm_1'), pg_temp.fx('m_adm'));
  PERFORM pg_temp.ok(r->>'assignment_status' = 'completed'
    AND (r->>'completed_household_meeting_id')::uuid = pg_temp.fx('m_adm'),
    'A.4 admin completes an assignment with a completed meeting');

  -- A.5 Skip
  PERFORM pg_temp.mk_assign('a_adm_2', 'hha', 't_b', current_date + 9, 2);
  r := public.skip_household_topic(v_org, pg_temp.fx('a_adm_2'), 'not_applicable');
  PERFORM pg_temp.ok(r->>'assignment_status' = 'skipped', 'A.5 admin skips a planned assignment');

  -- A.6 Cancel
  PERFORM pg_temp.mk_assign('a_adm_3', 'hha', 't_c', current_date + 10, 3);
  r := public.cancel_household_topic_assignment(v_org, pg_temp.fx('a_adm_3'), 'schedule_change');
  PERFORM pg_temp.ok(r->>'assignment_status' = 'cancelled', 'A.6 admin cancels a planned assignment');

  -- A.7 Plan / history / profile / dashboard reads
  r := public.get_household_formation_plan(v_org, pg_temp.fx('hha'));
  PERFORM pg_temp.ok(r ? 'formation_status' AND r ? 'planned_count', 'A.7 admin reads formation plan');
  r := public.get_household_topic_history(v_org, pg_temp.fx('hha'));
  PERFORM pg_temp.ok((r->>'total_count')::integer >= 3, 'A.8 admin reads topic history');
  r := public.get_household_profile(v_org, pg_temp.fx('hha'));
  PERFORM pg_temp.ok(r ? 'formation_summary', 'A.9 admin reads household profile formation_summary');
  r := public.get_pastoral_operations_dashboard(v_org);
  PERFORM pg_temp.ok(r ? 'formation_operations_summary', 'A.10 admin reads dashboard formation_operations_summary');

  -- Admin-created planned assignments used by the denial tests below
  PERFORM pg_temp.mk_assign('a_hhb', 'hhb', 't_a', current_date + 20);
  PERFORM pg_temp.mk_assign('a_hhn', 'hhn', 't_a', current_date + 20);
  PERFORM pg_temp.mk_assign('a_hha_sub', 'hha', 't_b', current_date + 21);
  PERFORM pg_temp.mk_assign('a_hu', 'hu', 't_a', current_date + 20);
  PERFORM pg_temp.mk_assign('a_hu2', 'hu2', 't_a', current_date + 20);
  PERFORM pg_temp.mk_assign('a_hc', 'hc', 't_a', current_date + 20);
  PERFORM pg_temp.mk_assign('a_hc2', 'hc2', 't_a', current_date + 20);
  PERFORM pg_temp.mk_assign('a_har', 'har', 't_a', current_date + 20);
  PERFORM pg_temp.mk_assign('a_hf', 'hf', 't_a', current_date + 20);
  PERFORM pg_temp.mk_meeting('m_hhb', 'hhb', -1);
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST B: HSL ACCESS (section 3)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid := pg_temp.fx('org');
  r     jsonb;
BEGIN
  PERFORM pg_temp.act_as('hsl_profile');

  PERFORM pg_temp.ok(pg_temp.e_plan('hha') = 'OK', 'B.1 HSL reads own household formation plan');
  PERFORM pg_temp.ok(pg_temp.e_hist('hha') = 'OK', 'B.2 HSL reads own household topic history');
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_a', current_date + 30) = 'OK', 'B.3 HSL assigns a topic to own household');

  r := pg_temp.mk_assign('a_hsl_1', 'hha', 't_b', current_date + 31);
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hsl_1', current_date + 32) = 'OK', 'B.4 HSL reschedules own household assignment');

  PERFORM pg_temp.mk_meeting('m_hsl', 'hha', -2);
  PERFORM pg_temp.ok(pg_temp.e_complete('a_hsl_1', 'm_hsl') = 'OK', 'B.5 HSL completes own household assignment');

  PERFORM pg_temp.ok(pg_temp.e_plan('hhb') = 'P0002', 'B.6 HSL cannot read household B plan (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_hist('hhb') = 'P0002', 'B.7 HSL cannot read household B history (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_assign('hhb', 't_a') = 'P0002', 'B.8 HSL cannot assign to household B (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hhb', current_date + 40) = 'P0002', 'B.9 HSL cannot reschedule household B assignment (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_hhb', 'm_hhb') = 'P0002', 'B.10 HSL cannot complete household B assignment (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hhb') = 'P0002', 'B.11 HSL cannot skip household B assignment (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hhb') = 'P0002', 'B.12 HSL cannot cancel household B assignment (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_plan('hu') = 'P0002', 'B.13 HSL cannot read the Unit Household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_assign('hu', 't_a') = 'P0002', 'B.14 HSL cannot manage the Unit Household (P0002)');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST C/D/E: LEADERSHIP WITHOUT ACCESS, ACCESS WITHOUT LEADERSHIP, SPOUSE
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  -- C: formal HSL assignment, NO delegated access
  PERFORM pg_temp.act_as('na_profile');
  PERFORM pg_temp.ok(pg_temp.e_assign('hhn', 't_a') = '42501', 'C.1 formal leadership alone cannot assign (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hhn', current_date + 40) = '42501', 'C.2 formal leadership alone cannot reschedule (42501)');
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hhn') = '42501', 'C.3 formal leadership alone cannot skip (42501)');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hhn') = '42501', 'C.4 formal leadership alone cannot cancel (42501)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_hhn', 'm_adm') = '42501', 'C.5 formal leadership alone cannot complete (42501)');
  PERFORM pg_temp.ok(pg_temp.e_plan('hhn') = '42501', 'C.6 formal leadership alone cannot read the plan (42501)');

  -- D: delegated role + scope, but NO current leadership assignment
  PERFORM pg_temp.act_as('stale_profile');
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_a') = '42501', 'D.1 delegated role without leadership cannot assign (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hha_sub', current_date + 40) = '42501', 'D.2 delegated role without leadership cannot reschedule (42501)');
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hha_sub') = '42501', 'D.3 delegated role without leadership cannot skip (42501)');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hha_sub') = '42501', 'D.4 delegated role without leadership cannot cancel (42501)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_hha_sub', 'm_adm') = '42501', 'D.5 delegated role without leadership cannot complete (42501)');

  -- E: verified spouse of the formal HSL
  PERFORM pg_temp.act_as('spouse_profile');
  PERFORM pg_temp.ok(
    EXISTS (SELECT 1 FROM public.family_relationships fr
            WHERE ((fr.from_member_id = pg_temp.fx('hsl_member') AND fr.to_member_id = pg_temp.fx('spouse_member'))
               OR (fr.from_member_id = pg_temp.fx('spouse_member') AND fr.to_member_id = pg_temp.fx('hsl_member')))
              AND fr.verification_status = 'administrator_verified'),
    'E.0 verified spouse relationship exists');
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_a') = '42501', 'E.1 derived spouse cannot assign (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hha_sub', current_date + 40) = '42501', 'E.2 derived spouse cannot reschedule (42501)');
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hha_sub') = '42501', 'E.3 derived spouse cannot skip (42501)');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hha_sub') = '42501', 'E.4 derived spouse cannot cancel (42501)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_hha_sub', 'm_adm') = '42501', 'E.5 derived spouse cannot complete (42501)');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST F: USL (section 7)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM pg_temp.act_as('usl_profile');

  -- READ within the Unit subtree
  PERFORM pg_temp.ok(pg_temp.e_plan('hu') = 'OK', 'F.1 USL reads Unit Household plan');
  PERFORM pg_temp.ok(pg_temp.e_plan('hha') = 'OK', 'F.2 USL reads subordinate Member Household plan');
  PERFORM pg_temp.ok(pg_temp.e_hist('hha') = 'OK', 'F.3 USL reads subordinate Member Household history');

  -- WRITE for the Unit Household
  PERFORM pg_temp.mk_assign('a_usl_1', 'hu', 't_b', current_date + 50);
  PERFORM pg_temp.ok(pg_temp.e_resched('a_usl_1', current_date + 51) = 'OK', 'F.4 USL reschedules Unit Household assignment');
  PERFORM pg_temp.mk_meeting('m_usl', 'hu', -1);
  PERFORM pg_temp.ok(pg_temp.e_complete('a_usl_1', 'm_usl') = 'OK', 'F.5 USL completes Unit Household assignment');
  PERFORM pg_temp.mk_assign('a_usl_2', 'hu', 't_c', current_date + 52);
  PERFORM pg_temp.ok(pg_temp.e_skip('a_usl_2') = 'OK', 'F.6 USL skips Unit Household assignment');
  PERFORM pg_temp.mk_assign('a_usl_3', 'hu', 't_c', current_date + 53);
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_usl_3') = 'OK', 'F.7 USL cancels Unit Household assignment');

  -- DENY: subordinate Member Household writes (oversight is read-only)
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_a') = '42501', 'F.8 USL cannot assign to subordinate Member Household (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hha_sub', current_date + 60) = '42501', 'F.9 USL cannot reschedule subordinate assignment (42501)');
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hha_sub') = '42501', 'F.10 USL cannot skip subordinate assignment (42501)');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hha_sub') = '42501', 'F.11 USL cannot cancel subordinate assignment (42501)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_hha_sub', 'm_adm') = '42501', 'F.12 USL cannot complete subordinate assignment (42501)');

  -- DENY: sibling Unit subtree
  PERFORM pg_temp.ok(pg_temp.e_plan('hu2') = 'P0002', 'F.13 USL cannot read sibling Unit Household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_plan('hhb') = 'P0002', 'F.14 USL cannot read sibling Unit Member Household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_assign('hu2', 't_a') = 'P0002', 'F.15 USL cannot assign in sibling Unit (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hu2', current_date + 60) = 'P0002', 'F.16 USL cannot reschedule sibling Unit assignment (P0002)');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST G: CSL (section 8)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM pg_temp.act_as('csl_profile');

  PERFORM pg_temp.ok(pg_temp.e_plan('hc') = 'OK' AND pg_temp.e_plan('hu') = 'OK' AND pg_temp.e_plan('hha') = 'OK',
    'G.1 CSL reads Chapter subtree');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hc', current_date + 61) = 'OK', 'G.2 CSL reschedules Chapter Household assignment');
  PERFORM pg_temp.ok(pg_temp.e_assign('hc', 't_b', current_date + 62) = 'OK', 'G.3 CSL assigns to Chapter Household');

  PERFORM pg_temp.ok(pg_temp.e_assign('hu', 't_a') = '42501', 'G.4 CSL cannot assign to subordinate Unit Household (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hu', current_date + 63) = '42501', 'G.5 CSL cannot reschedule subordinate Unit assignment (42501)');
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_a') = '42501', 'G.6 CSL cannot assign to subordinate Member Household (42501)');
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hha_sub') = '42501', 'G.7 CSL cannot skip subordinate Member assignment (42501)');

  PERFORM pg_temp.ok(pg_temp.e_plan('hc2') = 'P0002', 'G.8 CSL cannot read sibling Chapter Household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_assign('hc2', 't_a') = 'P0002', 'G.9 CSL cannot assign in sibling Chapter (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hc2', current_date + 63) = 'P0002', 'G.10 CSL cannot reschedule sibling Chapter assignment (P0002)');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST H: ASL (section 9) + TEST I: FRATERNAL (section 10)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM pg_temp.act_as('asl_profile');

  PERFORM pg_temp.ok(pg_temp.e_plan('har') = 'OK' AND pg_temp.e_plan('hc') = 'OK' AND pg_temp.e_plan('hu') = 'OK' AND pg_temp.e_plan('hha') = 'OK',
    'H.1 ASL reads Area subtree');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_har', current_date + 64) = 'OK', 'H.2 ASL reschedules Area Household assignment');
  PERFORM pg_temp.ok(pg_temp.e_assign('har', 't_b', current_date + 65) = 'OK', 'H.3 ASL assigns to Area Household');

  PERFORM pg_temp.ok(pg_temp.e_assign('hc', 't_a') = '42501', 'H.4 ASL cannot assign to subordinate Chapter Household (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hc', current_date + 66) = '42501', 'H.5 ASL cannot reschedule subordinate Chapter assignment (42501)');
  PERFORM pg_temp.ok(pg_temp.e_assign('hu', 't_a') = '42501', 'H.6 ASL cannot assign to subordinate Unit Household (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hu', current_date + 66) = '42501', 'H.7 ASL cannot reschedule subordinate Unit assignment (42501)');
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_a') = '42501', 'H.8 ASL cannot assign to subordinate Member Household (42501)');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hha_sub') = '42501', 'H.9 ASL cannot cancel subordinate Member assignment (42501)');

  -- FRATERNAL: not delegated; facilitator and even the Area leader are denied
  PERFORM pg_temp.ok(pg_temp.e_assign('hf', 't_a') = '42501', 'I.1 ASL cannot manage Fraternal formation (admin-managed) (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hf', current_date + 66) = '42501', 'I.2 ASL cannot reschedule Fraternal assignment (42501)');

  PERFORM pg_temp.act_as('fac_profile');
  PERFORM pg_temp.ok(pg_temp.e_assign('hf', 't_a') = '42501', 'I.3 Fraternal facilitator cannot assign (42501)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hf', current_date + 66) = '42501', 'I.4 Fraternal facilitator cannot reschedule (42501)');
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hf') = '42501', 'I.5 Fraternal facilitator cannot skip (42501)');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hf') = '42501', 'I.6 Fraternal facilitator cannot cancel (42501)');

  PERFORM pg_temp.act_as('admin');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hf', current_date + 67) = 'OK', 'I.7 organization administrator manages Fraternal formation');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST J: MEETING LINKAGE (section 11) + K: ATTENDANCE INDEPENDENCE (12)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org   uuid := pg_temp.fx('org');
  v_org2  uuid := gen_random_uuid();
  v_node2 uuid := gen_random_uuid();
  v_m2    uuid := gen_random_uuid();
  r       jsonb;
  v_before text;
  v_after  text;
  v_cnt_b  bigint;
  v_cnt_a  bigint;
BEGIN
  PERFORM pg_temp.act_as('admin');

  -- Fixture meetings on household A
  PERFORM pg_temp.mk_meeting('m_sched', 'hha', -3, 'scheduled');
  PERFORM pg_temp.mk_meeting('m_canc', 'hha', -4, 'cancelled');
  PERFORM pg_temp.mk_meeting('m_ok', 'hha', -5, 'completed');

  -- Fixture meeting in ANOTHER ORGANIZATION
  INSERT INTO public.organizations (id, code, name) VALUES (v_org2, 'tfx_org2_' || floor(random() * 999999)::text, 'Fx Other Organization');
  INSERT INTO public.governance_node_types (organization_id, code, name, hierarchy_rank, detail_table_name, requires_detail_record, allows_children, allows_member_assignment, allows_leadership_assignment, is_household_type)
  SELECT v_org2, code, name, hierarchy_rank, detail_table_name, requires_detail_record, allows_children, allows_member_assignment, allows_leadership_assignment, is_household_type
  FROM public.governance_node_types WHERE code = 'household' AND organization_id = v_org;
  INSERT INTO public.governance_nodes (id, organization_id, governance_node_type_id, code, name, lifecycle_status)
  SELECT v_node2, v_org2, gnt.id, 'tfx_o2hh_' || floor(random() * 999999)::text, 'Fx Other Org HH', 'active'
  FROM public.governance_node_types gnt WHERE gnt.code = 'household' AND gnt.organization_id = v_org2;
  INSERT INTO public.households (id, organization_id, pastoral_level, household_category, meeting_frequency)
  VALUES (v_node2, v_org2, 'member', 'pastoral', 'weekly');
  INSERT INTO public.household_meetings (id, organization_id, household_node_id, meeting_date, meeting_status)
  VALUES (v_m2, v_org2, v_node2, current_date - 1, 'completed');
  PERFORM pg_temp.setfx('m_org2', v_m2);

  -- Assignments to test against
  PERFORM pg_temp.mk_assign('a_j1', 'hha', 't_a', current_date + 70);
  PERFORM pg_temp.mk_assign('a_j2', 'hha', 't_a', current_date + 71);
  PERFORM pg_temp.mk_assign('a_j3', 'hha', 't_a', current_date + 72);
  PERFORM pg_temp.mk_assign('a_j4', 'hha', 't_a', current_date + 73);
  PERFORM pg_temp.mk_assign('a_j5', 'hha', 't_a', current_date + 74);

  -- REJECTS
  PERFORM pg_temp.ok(pg_temp.e_complete('a_j1', 'm_sched') = '22023', 'J.1 scheduled meeting rejected as completion evidence (22023)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_j1', 'm_canc') = '22023', 'J.2 cancelled meeting rejected (22023)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_j1', 'm_hhb') = '22023', 'J.3 meeting from another household rejected (22023)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_j1', 'm_org2') = 'P0002', 'J.4 meeting from another organization rejected (P0002)');
  PERFORM pg_temp.ok(
    (SELECT assignment_status FROM public.household_topic_assignments WHERE id = pg_temp.fx('a_j1')) = 'planned',
    'J.5 rejected completions leave the assignment planned');

  -- ACCEPT (with attendance independence snapshot)
  PERFORM pg_temp.mk_meeting('m_att', 'hha', -6, 'scheduled');
  PERFORM public.record_household_meeting_attendance(v_org, pg_temp.fx('m_att'), jsonb_build_array(
    jsonb_build_object('member_id', pg_temp.fx('r1_member'), 'attendance_status', 'present'),
    jsonb_build_object('member_id', pg_temp.fx('r2_member'), 'attendance_status', 'excused')));
  PERFORM public.complete_household_meeting(v_org, pg_temp.fx('m_att'));

  SELECT count(*), COALESCE(md5(string_agg(a.id::text || a.attendance_status || a.updated_at::text, ',' ORDER BY a.id)), '')
  INTO v_cnt_b, v_before
  FROM public.household_meeting_attendance a;

  r := public.complete_household_topic(v_org, pg_temp.fx('a_j2'), pg_temp.fx('m_att'));
  PERFORM pg_temp.ok(r->>'assignment_status' = 'completed', 'J.6 completed meeting in same org and household accepted');

  SELECT count(*), COALESCE(md5(string_agg(a.id::text || a.attendance_status || a.updated_at::text, ',' ORDER BY a.id)), '')
  INTO v_cnt_a, v_after
  FROM public.household_meeting_attendance a;

  PERFORM pg_temp.ok(v_cnt_b = 2 AND v_cnt_a = v_cnt_b AND v_before = v_after,
    'K.1 topic completion does not create, alter or delete household_meeting_attendance rows');

  -- Already completed / skipped / cancelled assignments
  PERFORM pg_temp.ok(pg_temp.e_complete('a_j2', 'm_ok') = '22023', 'J.7 already completed assignment rejected (22023)');
  PERFORM public.skip_household_topic(v_org, pg_temp.fx('a_j3'), 'not_applicable');
  PERFORM public.cancel_household_topic_assignment(v_org, pg_temp.fx('a_j4'), 'other');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_j3', 'm_ok') = '22023', 'J.8 skipped assignment rejected (22023)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_j4', 'm_ok') = '22023', 'J.9 cancelled assignment rejected (22023)');
  PERFORM pg_temp.ok(
    (SELECT completed_household_meeting_id FROM public.household_topic_assignments WHERE id = pg_temp.fx('a_j2')) = pg_temp.fx('m_att'),
    'J.10 completed assignment retains its meeting linkage');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_j5', 'm_ok') = 'OK', 'J.11 a second planned assignment can use another completed meeting');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST L: MEMBER FORMATION INDEPENDENCE (section 13)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_before text;
  v_after  text;
BEGIN
  PERFORM pg_temp.act_as('admin');

  -- No member-level formation completion structure exists in Phase 6B-10
  PERFORM pg_temp.ok(
    (SELECT array_agg(table_name::text ORDER BY table_name) FROM information_schema.tables
     WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
       AND table_name ~* '(formation|completion|progress)')
    = ARRAY['formation_topics']::text[],
    'L.1 only formation_topics matches formation/completion/progress tables (no member-level completion table)');
  PERFORM pg_temp.ok(
    NOT EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name IN ('formation_topics', 'household_topic_assignments')
                  AND column_name IN ('member_id', 'profile_member_id')),
    'L.2 Phase 6B-10 tables carry no member_id (household-level only)');

  -- Completion leaves household memberships and member rows untouched
  SELECT md5(string_agg(hm.id::text || hm.membership_status, ',' ORDER BY hm.id)) INTO v_before
  FROM public.household_memberships hm WHERE hm.household_node_id = pg_temp.fx('hha');

  PERFORM pg_temp.mk_assign('a_l1', 'hha', 't_b', current_date + 80);
  PERFORM public.complete_household_topic(pg_temp.fx('org'), pg_temp.fx('a_l1'), pg_temp.fx('m_ok'));

  SELECT md5(string_agg(hm.id::text || hm.membership_status, ',' ORDER BY hm.id)) INTO v_after
  FROM public.household_memberships hm WHERE hm.household_node_id = pg_temp.fx('hha');
  PERFORM pg_temp.ok(v_before = v_after, 'L.3 topic completion does not change household member records');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST M: STATUS LOGIC (section 14)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid := pg_temp.fx('org');
BEGIN
  PERFORM pg_temp.act_as('admin');

  PERFORM pg_temp.ok(private.compute_household_formation_status(pg_temp.fx('hst')) = 'no_plan', 'M.1 no assignments => no_plan');

  PERFORM pg_temp.mk_assign('a_st_null', 'hst', 't_a', NULL);
  PERFORM pg_temp.ok(private.compute_household_formation_status(pg_temp.fx('hst')) = 'planned', 'M.2 planned with null date => not overdue (planned)');

  PERFORM pg_temp.mk_assign('a_st_future', 'hst', 't_b', current_date + 5);
  PERFORM pg_temp.ok(private.compute_household_formation_status(pg_temp.fx('hst')) = 'planned', 'M.3 planned with future date => planned');

  PERFORM pg_temp.mk_assign('a_st_today', 'hst', 't_c', current_date);
  PERFORM pg_temp.ok(private.compute_household_formation_status(pg_temp.fx('hst')) = 'topic_due', 'M.4 planned for today => topic_due');

  PERFORM pg_temp.mk_assign('a_st_past', 'hst', 't_a', current_date - 1);
  PERFORM pg_temp.ok(private.compute_household_formation_status(pg_temp.fx('hst')) = 'topic_overdue', 'M.5 planned with past date => topic_overdue');
  PERFORM pg_temp.ok(
    public.get_household_formation_plan(v_org, pg_temp.fx('hst'))->>'formation_status' = 'topic_overdue',
    'M.6 plan RPC reports the same factual status');

  PERFORM public.cancel_household_topic_assignment(v_org, pg_temp.fx('a_st_past'), 'schedule_change');
  PERFORM public.cancel_household_topic_assignment(v_org, pg_temp.fx('a_st_today'), 'schedule_change');
  PERFORM public.cancel_household_topic_assignment(v_org, pg_temp.fx('a_st_future'), 'schedule_change');
  PERFORM public.cancel_household_topic_assignment(v_org, pg_temp.fx('a_st_null'), 'schedule_change');
  PERFORM pg_temp.ok(private.compute_household_formation_status(pg_temp.fx('hst')) = 'no_plan', 'M.7 only cancelled assignments => no_plan (not overdue)');

  PERFORM pg_temp.mk_assign('a_st_done', 'hst', 't_a', current_date - 2);
  PERFORM pg_temp.mk_meeting('m_hst', 'hst', -1);
  PERFORM public.complete_household_topic(v_org, pg_temp.fx('a_st_done'), pg_temp.fx('m_hst'));
  PERFORM pg_temp.ok(private.compute_household_formation_status(pg_temp.fx('hst')) = 'up_to_date', 'M.8 completed assignment => not overdue (up_to_date)');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST N: REPEAT TOPIC HISTORY (section 15)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid := pg_temp.fx('org');
BEGIN
  PERFORM pg_temp.act_as('admin');

  PERFORM pg_temp.mk_assign('a_rep_1', 'hha', 't_c', current_date - 20);
  PERFORM pg_temp.mk_assign('a_rep_2', 'hha', 't_c', current_date - 10);
  PERFORM pg_temp.mk_meeting('m_rep_1', 'hha', -7);
  PERFORM pg_temp.mk_meeting('m_rep_2', 'hha', -8);
  PERFORM public.complete_household_topic(v_org, pg_temp.fx('a_rep_1'), pg_temp.fx('m_rep_1'));
  PERFORM public.complete_household_topic(v_org, pg_temp.fx('a_rep_2'), pg_temp.fx('m_rep_2'));

  PERFORM pg_temp.ok(
    (SELECT count(*) FROM public.household_topic_assignments
     WHERE household_node_id = pg_temp.fx('hha') AND topic_id = pg_temp.fx('t_c') AND assignment_status = 'completed') = 2,
    'N.1 the same topic is completed twice historically on different dates');
  PERFORM pg_temp.ok(
    (SELECT count(*) FROM jsonb_array_elements(public.get_household_topic_history(v_org, pg_temp.fx('hha'), 100, 0)->'history') h
     WHERE (h->>'topic_id')::uuid = pg_temp.fx('t_c') AND h->>'assignment_status' = 'completed') = 2,
    'N.2 history lists both completions of the repeated topic');
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_c', current_date + 90) = 'OK', 'N.3 the topic can be assigned again after completion');
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_c', current_date + 90) = '23505', 'N.4 identical planned topic and date is rejected (23505)');
  PERFORM pg_temp.ok(pg_temp.e_assign('hha', 't_c', current_date + 91) = 'OK', 'N.5 same topic on a different planned date is allowed');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST O/P: HISTORY + PAGINATION (16), PLAN (17)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org   uuid := pg_temp.fx('org');
  r       jsonb;
  h       jsonb;
  v_ids   text;
  v_page  text := '';
  v_key   text;
  v_i     integer;
BEGIN
  PERFORM pg_temp.act_as('admin');

  -- Household "hhr": 3 planned, 1 completed, 1 skipped, 1 cancelled
  PERFORM pg_temp.mk_assign('a_r_p3', 'hhr', 't_a', current_date + 3);
  PERFORM pg_temp.mk_assign('a_r_p1', 'hhr', 't_b', current_date + 1);
  PERFORM pg_temp.mk_assign('a_r_pn', 'hhr', 't_c', NULL);
  PERFORM pg_temp.mk_assign('a_r_c',  'hhr', 't_a', current_date - 5);
  PERFORM pg_temp.mk_assign('a_r_s',  'hhr', 't_b', current_date - 4);
  PERFORM pg_temp.mk_assign('a_r_x',  'hhr', 't_c', current_date - 3);
  PERFORM pg_temp.mk_meeting('m_hhr', 'hhr', -1);
  PERFORM public.complete_household_topic(v_org, pg_temp.fx('a_r_c'), pg_temp.fx('m_hhr'));
  PERFORM public.skip_household_topic(v_org, pg_temp.fx('a_r_s'), 'topic_replaced');
  PERFORM public.cancel_household_topic_assignment(v_org, pg_temp.fx('a_r_x'), 'other');

  h := public.get_household_topic_history(v_org, pg_temp.fx('hhr'), 100, 0);
  PERFORM pg_temp.ok((h->>'total_count')::integer = 6 AND jsonb_array_length(h->'history') = 6, 'O.1 history returns all 6 assignments');

  -- Required fields on every item
  PERFORM pg_temp.ok(
    NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(h->'history') i
      WHERE NOT (i ? 'assignment_id' AND i ? 'topic_id' AND i ? 'topic_title' AND i ? 'planned_for_date'
                 AND i ? 'assignment_status' AND i ? 'completed_at' AND i ? 'completed_household_meeting_id'
                 AND i ? 'meeting_date')),
    'O.2 history items expose assignment, topic, planned date, status, completion date and meeting linkage');

  -- Ordering: planned (latest date first), completed, skipped, cancelled
  PERFORM pg_temp.ok(
    (SELECT string_agg(i->>'assignment_status', ',' ORDER BY ord) FROM jsonb_array_elements(h->'history') WITH ORDINALITY t(i, ord))
      = 'planned,planned,planned,completed,skipped,cancelled',
    'O.3 history ordering is planned, completed, skipped, cancelled');
  PERFORM pg_temp.ok(
    (h->'history'->0->>'planned_for_date')::date = current_date + 3
    AND (h->'history'->1->>'planned_for_date')::date = current_date + 1
    AND h->'history'->2->>'planned_for_date' IS NULL,
    'O.4 planned items are ordered by planned date descending, undated last');
  PERFORM pg_temp.ok(
    (h->'history'->3->>'completed_household_meeting_id')::uuid = pg_temp.fx('m_hhr')
    AND h->'history'->3->>'meeting_date' IS NOT NULL
    AND h->'history'->3->>'completed_at' IS NOT NULL,
    'O.5 completed item carries completion date and meeting linkage');

  -- Pagination
  v_ids := (SELECT string_agg(i->>'assignment_id', ',' ORDER BY ord) FROM jsonb_array_elements(h->'history') WITH ORDINALITY t(i, ord));
  FOR v_i IN 0..2 LOOP
    r := public.get_household_topic_history(v_org, pg_temp.fx('hhr'), 2, v_i * 2);
    PERFORM pg_temp.ok(jsonb_array_length(r->'history') = 2 AND (r->>'total_count')::integer = 6
      AND (r->>'limit')::integer = 2 AND (r->>'offset')::integer = v_i * 2,
      'O.6.' || v_i || ' pagination page ' || v_i || ' returns 2 items with total_count 6');
    v_page := v_page || CASE WHEN v_page = '' THEN '' ELSE ',' END ||
      (SELECT string_agg(i->>'assignment_id', ',' ORDER BY ord) FROM jsonb_array_elements(r->'history') WITH ORDINALITY t(i, ord));
  END LOOP;
  PERFORM pg_temp.ok(v_page = v_ids, 'O.7 concatenated pages equal the full ordered history');
  r := public.get_household_topic_history(v_org, pg_temp.fx('hhr'), 2, 6);
  PERFORM pg_temp.ok(jsonb_array_length(r->'history') = 0 AND (r->>'total_count')::integer = 6, 'O.8 offset beyond total returns an empty page');
  r := public.get_household_topic_history(v_org, pg_temp.fx('hhr'), 1000, -5);
  PERFORM pg_temp.ok((r->>'limit')::integer = 100 AND (r->>'offset')::integer = 0, 'O.9 limit is clamped to 100 and negative offset to 0');
  r := public.get_household_topic_history(v_org, pg_temp.fx('hhr'), 0, 0);
  PERFORM pg_temp.ok((r->>'limit')::integer = 1 AND jsonb_array_length(r->'history') = 1, 'O.10 limit 0 is clamped to 1');

  -- PLAN (before adding more planned items)
  r := public.get_household_formation_plan(v_org, pg_temp.fx('hhr'));
  PERFORM pg_temp.ok(r ? 'next_topic' AND r ? 'upcoming_topics' AND r ? 'last_completed_topic'
    AND r ? 'planned_count' AND r ? 'completed_count' AND r ? 'formation_status',
    'P.1 plan exposes next_topic, upcoming_topics, last_completed_topic, counts and status');
  PERFORM pg_temp.ok((r->>'planned_count')::integer = 3 AND (r->>'completed_count')::integer = 1, 'P.2 plan counts are planned 3 / completed 1');
  PERFORM pg_temp.ok((r->'next_topic'->>'assignment_id')::uuid = pg_temp.fx('a_r_p1'), 'P.3 next_topic is the earliest planned date');
  PERFORM pg_temp.ok(
    (SELECT string_agg(i->>'assignment_id', ',' ORDER BY ord) FROM jsonb_array_elements(r->'upcoming_topics') WITH ORDINALITY t(i, ord))
    = pg_temp.fx('a_r_p1')::text || ',' || pg_temp.fx('a_r_p3')::text || ',' || pg_temp.fx('a_r_pn')::text,
    'P.4 upcoming_topics ordering: date ascending, undated last');
  PERFORM pg_temp.ok((r->'last_completed_topic'->>'assignment_id')::uuid = pg_temp.fx('a_r_c'), 'P.5 last_completed_topic is the completed assignment');
  PERFORM pg_temp.ok(r->>'formation_status' = 'planned', 'P.6 factual formation status is planned');

  -- Determinism: same date ordered by sequence number, limit of 5
  PERFORM pg_temp.mk_assign('a_r_s2', 'hhr', 't_b', current_date + 2, 2);
  PERFORM pg_temp.mk_assign('a_r_s1', 'hhr', 't_c', current_date + 2, 1);
  PERFORM pg_temp.mk_assign('a_r_f1', 'hhr', 't_a', current_date + 30);
  PERFORM pg_temp.mk_assign('a_r_f2', 'hhr', 't_a', current_date + 31);
  r := public.get_household_formation_plan(v_org, pg_temp.fx('hhr'));
  PERFORM pg_temp.ok((r->>'planned_count')::integer = 7 AND jsonb_array_length(r->'upcoming_topics') = 5,
    'P.7 plan counts 7 planned and limits upcoming_topics to 5');
  PERFORM pg_temp.ok(
    (SELECT string_agg(i->>'assignment_id', ',' ORDER BY ord) FROM jsonb_array_elements(r->'upcoming_topics') WITH ORDINALITY t(i, ord))
    = concat_ws(',', pg_temp.fx('a_r_p1'), pg_temp.fx('a_r_s1'), pg_temp.fx('a_r_s2'), pg_temp.fx('a_r_p3'), pg_temp.fx('a_r_f1')),
    'P.8 upcoming_topics ordering is deterministic (date, sequence number, ...)');
  PERFORM pg_temp.ok(
    r->'upcoming_topics' = public.get_household_formation_plan(v_org, pg_temp.fx('hhr'))->'upcoming_topics',
    'P.9 repeated plan reads return identical ordering');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST Q: PRIVACY (section 18)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org    uuid := pg_temp.fx('org');
  v_texts  text[] := ARRAY[]::text[];
  v_t      text;
  v_re     text := '"[a-z_]*(email|phone|address|medical|finance|note|auth|password|token)[a-z_]*":';
BEGIN
  PERFORM pg_temp.act_as('admin');

  v_texts := v_texts || public.get_household_formation_plan(v_org, pg_temp.fx('hhr'))::text;
  v_texts := v_texts || public.get_household_topic_history(v_org, pg_temp.fx('hhr'), 100, 0)::text;
  v_texts := v_texts || public.search_formation_topics(v_org)::text;
  v_texts := v_texts || (public.get_household_profile(v_org, pg_temp.fx('hha'))->'formation_summary')::text;
  v_texts := v_texts || pg_temp.mk_assign('a_q1', 'hhr', 't_a', current_date + 99)::text;
  v_texts := v_texts || public.reschedule_household_topic(v_org, pg_temp.fx('a_q1'), current_date + 98)::text;
  v_texts := v_texts || public.skip_household_topic(v_org, pg_temp.fx('a_q1'), 'other')::text;
  v_texts := v_texts || public.create_formation_topic(v_org, 'Fx Topic Delta', 'other')::text;

  FOREACH v_t IN ARRAY v_texts LOOP
    PERFORM pg_temp.ok(v_t !~* v_re, 'Q.1 formation API payload exposes no email/phone/address/medical/finance/notes/auth keys');
    PERFORM pg_temp.ok(v_t NOT LIKE '%@fxtest.local%', 'Q.2 formation API payload exposes no member email values');
  END LOOP;

  PERFORM pg_temp.ok(
    NOT EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'household_topic_assignments' AND column_name = 'resolution_notes'),
    'Q.3 resolution_notes column no longer exists');
  PERFORM pg_temp.ok(
    NOT EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name IN ('household_topic_assignments', 'formation_topics')
                  AND column_name ~* '(note|comment|narrative|remark)'),
    'Q.4 no free-text notes/comment columns on formation tables');
  PERFORM pg_temp.ok(
    NOT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('reschedule_household_topic', 'skip_household_topic', 'cancel_household_topic_assignment',
                          'assign_household_topic', 'complete_household_topic')
        AND pg_get_function_arguments(p.oid) ~ '(p_notes|p_comment|p_reason(?!_code))'),
    'Q.5 formation write RPCs accept no free-text notes/reason parameters');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST R: RPC ACLS (section 19)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_fn  text;
  v_oid oid;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.search_formation_topics(uuid,text,text,text,integer,integer)',
    'public.create_formation_topic(uuid,text,text,text,text,text,text,text,integer,text,integer)',
    'public.assign_household_topic(uuid,uuid,uuid,date,integer)',
    'public.reschedule_household_topic(uuid,uuid,date)',
    'public.complete_household_topic(uuid,uuid,uuid)',
    'public.skip_household_topic(uuid,uuid,text)',
    'public.cancel_household_topic_assignment(uuid,uuid,text)',
    'public.get_household_topic_history(uuid,uuid,integer,integer)',
    'public.get_household_formation_plan(uuid,uuid)'
  ] LOOP
    v_oid := v_fn::regprocedure::oid;
    PERFORM pg_temp.ok(
      (SELECT proacl IS NOT NULL FROM pg_proc WHERE oid = v_oid)
      AND NOT EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = v_oid AND a.grantee = 0),
      'R.1 ' || v_fn || ' has no PUBLIC execute');
    PERFORM pg_temp.ok(NOT has_function_privilege('anon', v_oid, 'EXECUTE'), 'R.2 ' || v_fn || ' is not executable by anon');
    PERFORM pg_temp.ok(has_function_privilege('authenticated', v_oid, 'EXECUTE'), 'R.3 ' || v_fn || ' is executable by authenticated');
    PERFORM pg_temp.ok(has_function_privilege('service_role', v_oid, 'EXECUTE'), 'R.4 ' || v_fn || ' is executable by service_role');
  END LOOP;

  PERFORM pg_temp.ok(
    NOT has_function_privilege('authenticated', 'private.assert_formation_manage_prereqs(uuid)'::regprocedure, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'private.assert_formation_household_write(uuid,uuid,uuid,boolean)'::regprocedure, 'EXECUTE')
    AND NOT has_function_privilege('anon', 'private.assert_formation_manage_prereqs(uuid)'::regprocedure, 'EXECUTE'),
    'R.5 private authorization helpers are not executable by authenticated or anon');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST S: ADMIN INACTIVE CLEANUP (section 20) + T: DELEGATED INACTIVE (21)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid := pg_temp.fx('org');
BEGIN
  PERFORM pg_temp.act_as('admin');

  -- Admin-side fixtures on "hi" (created while active)
  PERFORM pg_temp.mk_assign('a_hi_skip', 'hi', 't_a', current_date + 100);
  PERFORM pg_temp.mk_assign('a_hi_cancel', 'hi', 't_b', current_date + 101);
  PERFORM pg_temp.mk_assign('a_hi_res', 'hi', 't_c', current_date + 102);
  PERFORM pg_temp.mk_assign('a_hi_comp', 'hi', 't_a', current_date + 103);
  PERFORM pg_temp.mk_meeting('m_hi', 'hi', -1);

  -- Delegated-side fixtures on the Unit Household "hu" (USL has direct responsibility)
  PERFORM pg_temp.mk_assign('a_hu_res', 'hu', 't_b', current_date + 110);
  PERFORM pg_temp.mk_assign('a_hu_skip', 'hu', 't_c', current_date + 111);
  PERFORM pg_temp.mk_assign('a_hu_cancel', 'hu', 't_c', current_date + 112);
  PERFORM pg_temp.mk_assign('a_hu_comp', 'hu', 't_b', current_date + 113);

  UPDATE public.governance_nodes SET lifecycle_status = 'temporarily_inactive' WHERE id = pg_temp.fx('hi');
  UPDATE public.governance_nodes SET lifecycle_status = 'temporarily_inactive' WHERE id = pg_temp.fx('hu');

  -- S: organization administrator
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hi_skip') = 'OK', 'S.1 admin can skip a planned assignment on an inactive household');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hi_cancel') = 'OK', 'S.2 admin can cancel a planned assignment on an inactive household');
  PERFORM pg_temp.ok(pg_temp.e_assign('hi', 't_a', current_date + 120) = 'P0002', 'S.3 admin cannot assign on an inactive household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hi_res', current_date + 121) = 'P0002', 'S.4 admin cannot reschedule on an inactive household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_hi_comp', 'm_hi') = 'P0002', 'S.5 admin cannot complete on an inactive household (P0002)');
  PERFORM pg_temp.ok(
    (SELECT assignment_status FROM public.household_topic_assignments WHERE id = pg_temp.fx('a_hi_skip')) = 'skipped'
    AND (SELECT assignment_status FROM public.household_topic_assignments WHERE id = pg_temp.fx('a_hi_cancel')) = 'cancelled'
    AND (SELECT assignment_status FROM public.household_topic_assignments WHERE id = pg_temp.fx('a_hi_res')) = 'planned',
    'S.6 admin cleanup changed only the skipped/cancelled assignments');

  -- T: delegated servant leader (USL on the now-inactive Unit Household)
  PERFORM pg_temp.act_as('usl_profile');
  PERFORM pg_temp.ok(pg_temp.e_assign('hu', 't_a', current_date + 130) = 'P0002', 'T.1 delegated leader cannot assign on an inactive household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_resched('a_hu_res', current_date + 131) = 'P0002', 'T.2 delegated leader cannot reschedule on an inactive household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_complete('a_hu_comp', 'm_usl') = 'P0002', 'T.3 delegated leader cannot complete on an inactive household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_skip('a_hu_skip') = 'P0002', 'T.4 delegated leader cannot skip on an inactive household (P0002)');
  PERFORM pg_temp.ok(pg_temp.e_cancel('a_hu_cancel') = 'P0002', 'T.5 delegated leader cannot cancel on an inactive household (P0002)');
  PERFORM pg_temp.ok(
    (SELECT count(*) FROM public.household_topic_assignments
     WHERE id IN (pg_temp.fx('a_hu_res'), pg_temp.fx('a_hu_skip'), pg_temp.fx('a_hu_cancel'), pg_temp.fx('a_hu_comp'))
       AND assignment_status = 'planned') = 4,
    'T.6 delegated attempts on the inactive household changed nothing');
END;
$$;

-- -----------------------------------------------------------------------------
-- TEST U/V: DASHBOARD (section 22) + PROFILE (section 23)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid := pg_temp.fx('org');
  d     jsonb;
  f     jsonb;
  p     jsonb;
  v_k   text;
BEGIN
  PERFORM pg_temp.act_as('admin');

  d := public.get_pastoral_operations_dashboard(v_org);
  PERFORM pg_temp.ok(d ? 'household_summary' AND d ? 'meeting_operations_summary'
    AND d ? 'formation_operations_summary' AND d ? 'placement_review_summary',
    'U.1 dashboard returns household, meeting, formation and placement summaries');
  f := d->'formation_operations_summary';
  FOREACH v_k IN ARRAY ARRAY['households_with_no_plan', 'topics_planned', 'topics_completed_this_month', 'topics_due', 'topics_overdue'] LOOP
    PERFORM pg_temp.ok(jsonb_typeof(f->v_k) = 'number', 'U.2 formation_operations_summary.' || v_k || ' is numeric');
  END LOOP;
  PERFORM pg_temp.ok((f->>'topics_planned')::integer >= 1 AND (f->>'topics_completed_this_month')::integer >= 1,
    'U.3 dashboard formation counts reflect fixture assignments');

  p := public.get_household_profile(v_org, pg_temp.fx('hha'))->'formation_summary';
  PERFORM pg_temp.ok(p ? 'formation_status' AND p ? 'next_topic' AND p ? 'last_completed_topic'
    AND p ? 'planned_topics_count' AND p ? 'completed_topics_count',
    'V.1 admin profile returns formation_summary with all required fields');
  PERFORM pg_temp.ok((p->>'completed_topics_count')::integer >= 1, 'V.2 profile formation counts reflect fixtures');

  PERFORM pg_temp.act_as('hsl_profile');
  p := public.get_household_profile(v_org, pg_temp.fx('hha'))->'formation_summary';
  PERFORM pg_temp.ok(p ? 'formation_status', 'V.3 delegated HSL profile returns formation_summary');
END;
$$;

-- -----------------------------------------------------------------------------
-- RESULT
-- -----------------------------------------------------------------------------
SELECT count(*) AS formation_checks_passed, 'ALL PASSED' AS result FROM t_checks;

ROLLBACK;

-- =============================================================================
-- Migration: 20261002040000_phase_6b_household_meeting_cadence.sql
-- Phase:     Phase 6B-8 — Household Meetings, Attendance & Pastoral Follow-up
-- Purpose:   Formalizes factual household meeting cadence and overdue tracking:
--            - Implements private.get_household_meeting_cadence(org_id, node_id)
--            - Implements public.get_household_meeting_cadence(org_id, hh_id)
--            - Extends public.get_household_meeting_history with cadence fields
--            - Extends public.get_pastoral_operations_dashboard household_summary
--              with meeting_operational_status and cadence metadata
--            - Recalculates meeting_operations_summary.households_overdue from
--              the set-based cadence logic
--
-- Cadence rules:
--   - weekly:     expected next date = last completed + 7 days
--   - biweekly:   expected next date = last completed + 14 days
--   - monthly:    expected next date = last completed + 1 month (calendar month)
--   - quarterly:  expected next date = last completed + 3 months (calendar quarter)
--   - seasonal, variable, NULL: not_configured, never inferred overdue
--
-- Precedence for meeting_operational_status:
--   1. attendance_pending: completed meeting exists with incomplete attendance
--   2. scheduled: future/today scheduled meeting exists (meeting_date >= current_date)
--   3. not_configured: meeting_frequency is NULL or not in ('weekly','biweekly','monthly','quarterly')
--   4. no_meeting_history: structured frequency configured, but 0 completed meetings
--   5. overdue: expected_next_meeting_date < current_date
--   6. current: expected_next_meeting_date >= current_date
--
-- Frozen migrations (DO NOT EDIT):
--   20261002000000 — original 38 statements
--   20261002010000 — 3 statements, record_status correction
--   20261002020000 — 29 statements, notes_summary restriction + dashboard extension
--   20261002030000 — 2 statements, fix get_member_follow_up_signals ORDER BY
-- =============================================================================

-- =============================================================================
-- SECTION 1: private.get_household_meeting_cadence
-- =============================================================================

create or replace function private.get_household_meeting_cadence(
  p_organization_id   uuid,
  p_household_node_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_frequency         text;
  v_last_completed    date;
  v_next_scheduled    date;
  v_expected_next     date;
  v_days_since_last   integer;
  v_has_pending_att   boolean := false;
  v_status            text;
begin
  select meeting_frequency into v_frequency
  from public.households
  where id = p_household_node_id
    and organization_id = p_organization_id;

  select
    max(meeting_date) filter (where meeting_status = 'completed'),
    min(meeting_date) filter (where meeting_status = 'scheduled' and meeting_date >= current_date),
    bool_or(
      meeting_status = 'completed'
      and not (
        private.compute_attendance_summary(
          id,
          p_organization_id,
          meeting_date,
          p_household_node_id
        )->>'attendance_complete'
      )::boolean
    )
  into v_last_completed, v_next_scheduled, v_has_pending_att
  from public.household_meetings
  where household_node_id = p_household_node_id
    and organization_id = p_organization_id;

  if v_last_completed is not null then
    v_days_since_last := current_date - v_last_completed;
    case v_frequency
      when 'weekly'    then v_expected_next := (v_last_completed + interval '7 days')::date;
      when 'biweekly'  then v_expected_next := (v_last_completed + interval '14 days')::date;
      when 'monthly'   then v_expected_next := (v_last_completed + interval '1 month')::date;
      when 'quarterly' then v_expected_next := (v_last_completed + interval '3 months')::date;
      else v_expected_next := null;
    end case;
  else
    v_days_since_last := null;
    v_expected_next   := null;
  end if;

  -- Status precedence determination:
  -- 1. attendance_pending takes precedence
  -- 2. scheduled takes precedence
  -- 3. not_configured (seasonal, variable, NULL, or unrecognized)
  -- 4. no_meeting_history (structured frequency, but 0 completed meetings)
  -- 5. overdue (expected_next < current_date)
  -- 6. current (expected_next >= current_date)
  if coalesce(v_has_pending_att, false) then
    v_status := 'attendance_pending';
  elsif v_next_scheduled is not null then
    v_status := 'scheduled';
  elsif v_frequency is null or v_frequency not in ('weekly', 'biweekly', 'monthly', 'quarterly') then
    v_status := 'not_configured';
  elsif v_last_completed is null then
    v_status := 'no_meeting_history';
  elsif v_expected_next < current_date then
    v_status := 'overdue';
  else
    v_status := 'current';
  end if;

  return jsonb_build_object(
    'last_completed_meeting_date',       v_last_completed,
    'next_scheduled_meeting_date',       v_next_scheduled,
    'expected_next_meeting_date',        v_expected_next,
    'days_since_last_completed_meeting', v_days_since_last,
    'meeting_frequency',                 v_frequency,
    'meeting_operational_status',        v_status
  );
end;
$$;

comment on function private.get_household_meeting_cadence(uuid, uuid) is
  'Computes factual meeting cadence and operational status for a household based on meeting frequency and meeting records.';

revoke all on function private.get_household_meeting_cadence(uuid, uuid) from public, anon;
grant execute on function private.get_household_meeting_cadence(uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 2: public.get_household_meeting_cadence (RPC)
-- =============================================================================

create or replace function public.get_household_meeting_cadence(
  p_organization_id  uuid,
  p_household_id     uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household meetings.';
  end if;

  if not exists (
    select 1 from public.governance_nodes
    where id = p_household_id and organization_id = p_organization_id
  ) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  return private.get_household_meeting_cadence(p_organization_id, p_household_id);
end;
$$;

comment on function public.get_household_meeting_cadence(uuid, uuid) is
  'Public RPC returning meeting cadence and operational status for an authorized household.';

revoke all on function public.get_household_meeting_cadence(uuid, uuid) from public, anon;
grant execute on function public.get_household_meeting_cadence(uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 3: public.get_household_meeting_history (Enhanced with cadence)
-- =============================================================================

create or replace function public.get_household_meeting_history(
  p_organization_id  uuid,
  p_household_id     uuid,
  p_limit            integer default 20,
  p_offset           integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_household   public.governance_nodes%rowtype;
  v_total_count integer;
  v_meetings    jsonb;
  v_cadence     jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household meetings.';
  end if;

  select * into v_household
  from public.governance_nodes
  where id = p_household_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  p_limit  := least(greatest(coalesce(p_limit, 20), 1), 100);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  select count(*) into v_total_count
  from public.household_meetings
  where household_node_id = p_household_id
    and organization_id   = p_organization_id;

  select coalesce(jsonb_agg(m_row order by (m_row->>'meeting_date') desc), '[]'::jsonb)
  into v_meetings
  from (
    select jsonb_build_object(
      'household_meeting_id',     hm.id,
      'meeting_date',             hm.meeting_date,
      'meeting_status',           hm.meeting_status,
      'meeting_type',             hm.meeting_type,
      'location_type',            hm.location_type,
      'location_text',            hm.location_text,
      'facilitator_member_id',    hm.facilitator_member_id,
      'facilitator_display_name', fac_mn.full_name,
      'host_member_id',           hm.host_member_id,
      'host_display_name',        host_mn.full_name,
      'attendance_recorded_at',   hm.attendance_recorded_at,
      'attendance_summary',       private.compute_attendance_summary(
                                    hm.id, p_organization_id, hm.meeting_date, p_household_id
                                  ),
      'scheduled_start_at',       hm.scheduled_start_at,
      'scheduled_end_at',         hm.scheduled_end_at,
      'created_at',               hm.created_at
    ) as m_row
    from public.household_meetings hm
    left join (
      select member_id, full_name from public.member_names
      where is_primary = true and effective_to is null
    ) fac_mn on fac_mn.member_id = hm.facilitator_member_id
    left join (
      select member_id, full_name from public.member_names
      where is_primary = true and effective_to is null
    ) host_mn on host_mn.member_id = hm.host_member_id
    where hm.household_node_id = p_household_id
      and hm.organization_id   = p_organization_id
    order by hm.meeting_date desc
    limit p_limit
    offset p_offset
  ) sub;

  -- Compute cadence summary for this household
  v_cadence := private.get_household_meeting_cadence(p_organization_id, p_household_id);

  return jsonb_build_object(
    'household_id',                      p_household_id,
    'household_name',                    v_household.name,
    'total_count',                       v_total_count,
    'limit',                             p_limit,
    'offset',                            p_offset,
    'meetings',                          v_meetings,
    'cadence',                           v_cadence,
    'last_completed_meeting_date',       v_cadence->>'last_completed_meeting_date',
    'next_scheduled_meeting_date',       v_cadence->>'next_scheduled_meeting_date',
    'expected_next_meeting_date',        v_cadence->>'expected_next_meeting_date',
    'days_since_last_completed_meeting', (v_cadence->>'days_since_last_completed_meeting')::integer,
    'meeting_frequency',                 v_cadence->>'meeting_frequency',
    'meeting_operational_status',        v_cadence->>'meeting_operational_status'
  );
end;
$$;

comment on function public.get_household_meeting_history(uuid, uuid, integer, integer) is
  'Returns paginated meeting history and factual meeting cadence for an authorized household.';

revoke execute on function public.get_household_meeting_history(uuid, uuid, integer, integer) from public, anon;
grant  execute on function public.get_household_meeting_history(uuid, uuid, integer, integer) to authenticated, service_role;

-- =============================================================================
-- SECTION 4: public.get_pastoral_operations_dashboard (Enhanced with real cadence)
-- =============================================================================

create or replace function public.get_pastoral_operations_dashboard(
  p_organization_id    uuid,
  p_governance_node_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id             uuid;
  v_caller_member_id       uuid;
  v_caller_display_name    text;
  v_can_review_placement   boolean;
  v_can_view_leadership    boolean;
  v_can_view_roster        boolean;
  v_target_scope_node_id   uuid;
  v_identity_json          jsonb;
  v_serving_assignments    jsonb := '[]'::jsonb;
  v_pastoral_membership    jsonb := null;
  v_care_responsibilities  jsonb := '[]'::jsonb;
  v_households_summary     jsonb := '[]'::jsonb;
  v_leadership_vacancies   jsonb := '[]'::jsonb;
  v_capacity_summary       jsonb;
  v_operational_summary    jsonb;
  v_placement_summary      jsonb;
  v_unassigned_count       integer := 0;
  v_meeting_ops_summary    jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Dedicated Dashboard Permission check
  if not private.has_permission('leadership.pastoral_dashboard.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view the pastoral operations dashboard.';
  end if;

  -- 4. Scope verification if specific node supplied
  if p_governance_node_id is not null then
    if not private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, p_governance_node_id) then
      raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
    end if;
    v_target_scope_node_id := p_governance_node_id;
  end if;

  -- 5. Sub-domain permission checks for safe field filtering
  v_can_review_placement := private.has_permission('leadership.pastoral_placement.review', p_organization_id);
  v_can_view_leadership  := private.has_permission('governance.leadership.view', p_organization_id);
  v_can_view_roster      := private.has_permission('members.households.view', p_organization_id);

  -- 6. Resolve caller profile and member link (if exists)
  select pml.member_id, coalesce(m.display_name, p.display_name)
  into v_caller_member_id, v_caller_display_name
  from public.profiles p
  left join public.profile_member_links pml
    on pml.profile_id = p.id
   and pml.organization_id = p_organization_id
   and pml.is_primary = true
   and pml.link_type = 'self'
   and pml.link_status = 'verified'
   and pml.ended_at is null
  left join public.members m
    on m.id = pml.member_id
   and m.organization_id = p_organization_id
  where p.id = v_profile_id;

  if v_caller_display_name is null then
    select display_name into v_caller_display_name from public.profiles where id = v_profile_id;
  end if;

  -- 7. If linked to member, resolve Where I Serve (active formal servant roles)
  if v_caller_member_id is not null then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', la.id,
        'role_code',                lrd.code,
        'role_name',                lrd.name,
        'governance_node_id',       la.governance_node_id,
        'governance_node_name',     gn.name,
        'pastoral_level',           h.pastoral_level,
        'effective_from',           la.effective_from,
        'effective_to',             la.effective_to
      ) order by la.effective_from desc
    ), '[]'::jsonb)
    into v_serving_assignments
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join public.governance_nodes gn on gn.id = la.governance_node_id
    left join public.households h on h.id = la.governance_node_id
    where la.organization_id = p_organization_id
      and la.member_id = v_caller_member_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader');

    -- Where I Receive Pastoral Care (current primary household)
    select jsonb_build_object(
      'household_id',            h.id,
      'household_name',          gn.name,
      'pastoral_level',          h.pastoral_level,
      'scope_node_id',           p_rel.parent_node_id,
      'scope_node_name',         pn.name,
      'membership_role',         hm.membership_role,
      'effective_from',          hm.effective_from,
      'meeting_frequency',       h.meeting_frequency,
      'meeting_day_of_week',     h.meeting_day_of_week,
      'meeting_start_time',      to_char(h.meeting_start_time, 'HH24:MI:SS'),
      'meeting_timezone_name',   h.meeting_timezone_name,
      'is_fraternal',            (h.pastoral_level = 'fraternal')
    )
    into v_pastoral_membership
    from public.household_memberships hm
    join public.households h on h.id = hm.household_node_id
    join public.governance_nodes gn on gn.id = h.id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn on pn.id = p_rel.parent_node_id
    where hm.organization_id = p_organization_id
      and hm.member_id = v_caller_member_id
      and hm.is_primary = true
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    limit 1;
  end if;

  -- 8. Build Identity Block
  v_identity_json := jsonb_build_object(
    'profile_id',                          v_profile_id,
    'member_id',                           v_caller_member_id,
    'display_name',                        v_caller_display_name,
    'has_linked_member',                   (v_caller_member_id is not null),
    'serving_assignments',                 v_serving_assignments,
    'pastoral_membership',                 v_pastoral_membership,
    'pastoral_household_placement_needed', (v_caller_member_id is not null and v_pastoral_membership is null and jsonb_array_length(v_serving_assignments) > 0)
  );

  -- 9. Care Responsibilities
  if v_caller_member_id is not null and jsonb_array_length(v_serving_assignments) > 0 then
    with caller_roles as (
      select
        (item->>'leadership_assignment_id')::uuid as assignment_id,
        item->>'role_code' as role_code,
        (item->>'governance_node_id')::uuid as node_id,
        item->>'governance_node_name' as node_name
      from jsonb_array_elements(v_serving_assignments) item
    ),
    hsl_care as (
      select
        cr.assignment_id,
        'household'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'household_members',
          'household_id', cr.node_id,
          'household_name', cr.node_name,
          'member_count', count(hm.id),
          'members', case when v_can_view_roster then coalesce(jsonb_agg(
            jsonb_build_object(
              'member_id', m.id,
              'display_name', m.display_name,
              'member_number', m.member_number,
              'membership_role', hm.membership_role,
              'effective_from', hm.effective_from
            ) order by m.display_name
          ), '[]'::jsonb) else '[]'::jsonb end
        ) as care_payload
      from caller_roles cr
      join public.households h on h.id = cr.node_id and h.pastoral_level = 'member'
      left join public.household_memberships hm
        on hm.household_node_id = cr.node_id
       and hm.organization_id = p_organization_id
       and hm.membership_status in ('active', 'temporary')
       and hm.effective_from <= current_date
       and (hm.effective_to is null or hm.effective_to >= current_date)
      left join public.members m on m.id = hm.member_id
      where cr.role_code = 'household_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    usl_care as (
      select
        cr.assignment_id,
        'unit'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'household_leaders',
          'unit_id', cr.node_id,
          'unit_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'household_id', h.id,
              'household_name', gn.name,
              'is_couple_household', h.is_couple_household,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'has_derived_spouse', (h.is_couple_household and sp.id is not null),
              'derived_spouse_name', case when h.is_couple_household then sp.display_name else null end,
              'derived_pastoral_title', case when h.is_couple_household and sp.id is not null then 'Household Leaders' else 'Household Servant Leader' end
            ) order by gn.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.households h on h.id = gnr.child_node_id and h.pastoral_level = 'member'
      join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = h.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'household_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
      where cr.role_code = 'unit_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    csl_care as (
      select
        cr.assignment_id,
        'chapter'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'unit_leaders',
          'chapter_id', cr.node_id,
          'chapter_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'unit_id', un.id,
              'unit_name', un.name,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'couples_context_status', g_guidance.couples_status,
              'has_derived_spouse', (g_guidance.couples_status = 'couples' and sp.id is not null),
              'derived_spouse_name', case when g_guidance.couples_status = 'couples' then sp.display_name else null end,
              'derived_pastoral_title', case when g_guidance.couples_status = 'couples' and sp.id is not null then 'Unit Leaders' else 'Unit Servant Leader' end
            ) order by un.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.governance_nodes un on un.id = gnr.child_node_id and un.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = un.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'unit_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select
          case
            when exists (
              select 1 from public.governance_nodes sn
              join public.governance_node_types snt on snt.id = sn.governance_node_type_id
              where sn.id = lm.primary_section_node_id and (snt.code = 'couples' or sn.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when lm.primary_section_node_id is not null then 'non_couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and (gnt_mga.code = 'couples' or gn_mga.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and gnt_mga.code in ('singles', 'youth', 'handmaids', 'servants', 'men', 'women')
            ) then 'non_couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = true
            ) then 'couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = false
            ) then 'non_couples'
            when not exists (
              select 1 from public.family_relationships fr_chk
              where (fr_chk.from_member_id = lm.id or fr_chk.to_member_id = lm.id)
                and fr_chk.organization_id = p_organization_id and fr_chk.relationship_status = 'active'
            ) then 'non_couples'
            else 'ambiguous'
          end as couples_status
      ) g_guidance on true
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
      where cr.role_code = 'chapter_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    ),
    asl_care as (
      select
        cr.assignment_id,
        'area'::text as responsibility_level,
        cr.node_id as scope_id,
        cr.node_name as scope_name,
        jsonb_build_object(
          'type', 'chapter_leaders',
          'area_id', cr.node_id,
          'area_name', cr.node_name,
          'leaders', coalesce(jsonb_agg(
            jsonb_build_object(
              'chapter_id', chn.id,
              'chapter_name', chn.name,
              'leader_member_id', lm.id,
              'leader_name', lm.display_name,
              'role_code', lrd.code,
              'effective_from', la.effective_from,
              'couples_context_status', g_guidance.couples_status,
              'has_derived_spouse', (g_guidance.couples_status = 'couples' and sp.id is not null),
              'derived_spouse_name', case when g_guidance.couples_status = 'couples' then sp.display_name else null end,
              'derived_pastoral_title', case when g_guidance.couples_status = 'couples' and sp.id is not null then 'Chapter Leaders' else 'Chapter Servant Leader' end
            ) order by chn.name
          ) filter (where la.id is not null), '[]'::jsonb)
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.governance_nodes chn on chn.id = gnr.child_node_id and chn.lifecycle_status = 'active'
      left join public.leadership_assignments la
        on la.governance_node_id = chn.id
       and la.organization_id = p_organization_id
       and la.assignment_status = 'active'
       and la.effective_from <= current_date
       and (la.effective_to is null or la.effective_to >= current_date)
      left join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'chapter_servant_leader'
      left join public.members lm on lm.id = la.member_id
      left join lateral (
        select
          case
            when exists (
              select 1 from public.governance_nodes sn
              join public.governance_node_types snt on snt.id = sn.governance_node_type_id
              where sn.id = lm.primary_section_node_id and (snt.code = 'couples' or sn.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when lm.primary_section_node_id is not null then 'non_couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and (gnt_mga.code = 'couples' or gn_mga.metadata->>'is_couple_section' = 'true')
            ) then 'couples'
            when exists (
              select 1 from public.member_governance_assignments mga
              join public.governance_nodes gn_mga on gn_mga.id = mga.governance_node_id
              join public.governance_node_types gnt_mga on gnt_mga.id = gn_mga.governance_node_type_id
              where mga.member_id = lm.id and mga.organization_id = p_organization_id
                and mga.assignment_status in ('active', 'verified')
                and gnt_mga.code in ('singles', 'youth', 'handmaids', 'servants', 'men', 'women')
            ) then 'non_couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = true
            ) then 'couples'
            when exists (
              select 1 from public.household_memberships hm_lin
              join public.households h_lin on h_lin.id = hm_lin.household_node_id
              where hm_lin.member_id = lm.id and hm_lin.organization_id = p_organization_id
                and hm_lin.is_primary = true and hm_lin.membership_status in ('active', 'temporary')
                and h_lin.is_couple_household = false
            ) then 'non_couples'
            when not exists (
              select 1 from public.family_relationships fr_chk
              where (fr_chk.from_member_id = lm.id or fr_chk.to_member_id = lm.id)
                and fr_chk.organization_id = p_organization_id and fr_chk.relationship_status = 'active'
            ) then 'non_couples'
            else 'ambiguous'
          end as couples_status
      ) g_guidance on true
      left join lateral (
        select m_sp.id, m_sp.display_name
        from public.family_relationships fr
        join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
        join public.members m_sp on m_sp.id = case when fr.from_member_id = lm.id then fr.to_member_id else fr.from_member_id end
        where fr.organization_id = p_organization_id
          and (fr.from_member_id = lm.id or fr.to_member_id = lm.id)
          and fr.relationship_status = 'active'
          and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
          and (fr.effective_to is null or fr.effective_to >= current_date)
        limit 1
      ) sp on true
      where cr.role_code = 'area_servant_leader'
      group by cr.assignment_id, cr.node_id, cr.node_name
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', assignment_id,
        'responsibility_level',     responsibility_level,
        'scope_id',                 scope_id,
        'scope_name',               scope_name,
        'details',                  care_payload
      )
    ), '[]'::jsonb)
    into v_care_responsibilities
    from (
      select * from hsl_care
      union all
      select * from usl_care
      union all
      select * from csl_care
      union all
      select * from asl_care
    ) u;
  end if;

  -- 10. Households Summary with Cadence Integration
  with scoped_households as (
    select
      h.id as household_id,
      gn.name as household_name,
      h.pastoral_level,
      h.household_category,
      gn.lifecycle_status,
      h.is_couple_household,
      p_rel.parent_node_id as scope_node_id,
      pn.name as scope_node_name,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      count(hm.id) filter (
        where hm.membership_status in ('active', 'temporary')
          and hm.effective_from <= current_date
          and (hm.effective_to is null or hm.effective_to >= current_date)
      ) as member_count
    from public.households h
    join public.governance_nodes gn on gn.id = h.id and gn.organization_id = p_organization_id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn on pn.id = p_rel.parent_node_id
    left join public.household_memberships hm
      on hm.household_node_id = h.id
     and hm.organization_id = p_organization_id
    where h.organization_id = p_organization_id
      and (
        v_target_scope_node_id is null
        or h.id = v_target_scope_node_id
        or p_rel.parent_node_id = v_target_scope_node_id
        or exists (
          select 1 from public.governance_node_relationships anc
          where anc.parent_node_id = v_target_scope_node_id
            and anc.child_node_id = p_rel.parent_node_id
            and anc.organization_id = p_organization_id
            and anc.relationship_status = 'active'
        )
      )
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h.id)
    group by
      h.id, gn.name, h.pastoral_level, h.household_category, gn.lifecycle_status,
      h.is_couple_household, p_rel.parent_node_id, pn.name, h.target_member_count,
      h.maximum_member_count, h.accepts_new_members, h.meeting_frequency,
      h.meeting_day_of_week, h.meeting_start_time
  ),
  household_leaders as (
    select
      sh.household_id,
      case
        when sh.pastoral_level = 'member' then la_hh.id
        when sh.pastoral_level = 'unit' then la_scope.id
        when sh.pastoral_level = 'chapter' then la_scope.id
        when sh.pastoral_level = 'area' then la_scope.id
        else null
      end as leadership_assignment_id,
      case
        when sh.pastoral_level = 'member' then lm_hh.id
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lm_scope.id
        else null
      end as leader_member_id,
      case
        when sh.pastoral_level = 'member' then lm_hh.display_name
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lm_scope.display_name
        else null
      end as leader_name,
      case
        when sh.pastoral_level = 'member' then lrd_hh.code
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lrd_scope.code
        else null
      end as role_code,
      case
        when sh.pastoral_level = 'member' then lrd_hh.name
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lrd_scope.name
        else null
      end as role_name,
      case
        when sh.pastoral_level = 'member' and sh.is_couple_household then sp_hh.display_name
        when sh.pastoral_level in ('unit', 'chapter', 'area') and sh.is_couple_household then sp_scope.display_name
        else null
      end as derived_spouse_name
    from scoped_households sh
    left join public.leadership_assignments la_hh
      on la_hh.governance_node_id = sh.household_id
     and la_hh.organization_id = p_organization_id
     and la_hh.assignment_status = 'active'
     and la_hh.effective_from <= current_date
     and (la_hh.effective_to is null or la_hh.effective_to >= current_date)
    left join public.leadership_role_definitions lrd_hh
      on lrd_hh.id = la_hh.leadership_role_definition_id
     and lrd_hh.code = 'household_servant_leader'
    left join public.members lm_hh on lm_hh.id = la_hh.member_id
    left join lateral (
      select m_sp.id, m_sp.display_name
      from public.family_relationships fr
      join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      join public.members m_sp on m_sp.id = case when fr.from_member_id = lm_hh.id then fr.to_member_id else fr.from_member_id end
      where fr.organization_id = p_organization_id
        and (fr.from_member_id = lm_hh.id or fr.to_member_id = lm_hh.id)
        and fr.relationship_status = 'active'
        and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
        and (fr.effective_to is null or fr.effective_to >= current_date)
      limit 1
    ) sp_hh on true
    left join public.leadership_assignments la_scope
      on la_scope.governance_node_id = sh.scope_node_id
     and la_scope.organization_id = p_organization_id
     and la_scope.assignment_status = 'active'
     and la_scope.effective_from <= current_date
     and (la_scope.effective_to is null or la_scope.effective_to >= current_date)
    left join public.leadership_role_definitions lrd_scope
      on lrd_scope.id = la_scope.leadership_role_definition_id
     and lrd_scope.code in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    left join public.members lm_scope on lm_scope.id = la_scope.member_id
    left join lateral (
      select m_sp.id, m_sp.display_name
      from public.family_relationships fr
      join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      join public.members m_sp on m_sp.id = case when fr.from_member_id = lm_scope.id then fr.to_member_id else fr.from_member_id end
      where fr.organization_id = p_organization_id
        and (fr.from_member_id = lm_scope.id or fr.to_member_id = lm_scope.id)
        and fr.relationship_status = 'active'
        and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
        and (fr.effective_to is null or fr.effective_to >= current_date)
      limit 1
    ) sp_scope on true
  ),
  household_meeting_cadence_agg as (
    select
      hm.household_node_id,
      max(hm.meeting_date) filter (where hm.meeting_status = 'completed') as last_completed_date,
      min(hm.meeting_date) filter (where hm.meeting_status = 'scheduled' and hm.meeting_date >= current_date) as next_scheduled_date,
      bool_or(
        hm.meeting_status = 'completed'
        and not (
          private.compute_attendance_summary(
            hm.id,
            p_organization_id,
            hm.meeting_date,
            hm.household_node_id
          )->>'attendance_complete'
        )::boolean
      ) as has_pending_attendance
    from public.household_meetings hm
    where hm.organization_id = p_organization_id
    group by hm.household_node_id
  ),
  classified_households as (
    select
      sh.*,
      hl.leadership_assignment_id,
      hl.leader_member_id,
      hl.leader_name,
      hl.role_code as leader_role_code,
      hl.role_name as leader_role_name,
      hl.derived_spouse_name,
      case
        when sh.pastoral_level = 'fraternal' then 'not_applicable'
        when hl.leader_member_id is not null then 'assigned'
        else 'vacant'
      end as leadership_status,
      case
        when not sh.accepts_new_members then 'not_accepting'
        when sh.maximum_member_count is not null and sh.member_count >= sh.maximum_member_count then 'full'
        when sh.target_member_count is not null and sh.member_count >= sh.target_member_count then 'at_target'
        else 'available'
      end as capacity_status,
      case
        when sh.pastoral_level = 'fraternal' then 'Rotating facilitation — no permanent formal servant leader'
        when hl.derived_spouse_name is not null then
          case sh.pastoral_level
            when 'member' then 'Household Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'unit' then 'Unit Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'chapter' then 'Chapter Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            when 'area' then 'Area Leaders: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
            else hl.leader_name || ' & ' || hl.derived_spouse_name
          end
        when hl.leader_name is not null then hl.leader_name || ' (' || coalesce(hl.role_name, 'Leader') || ')'
        else 'Vacant'
      end as leader_display_label,
      -- Cadence factual fields
      hmca.last_completed_date as last_completed_meeting_date,
      hmca.next_scheduled_date as next_scheduled_meeting_date,
      case
        when hmca.last_completed_date is null then null
        when sh.meeting_frequency = 'weekly'    then (hmca.last_completed_date + interval '7 days')::date
        when sh.meeting_frequency = 'biweekly'  then (hmca.last_completed_date + interval '14 days')::date
        when sh.meeting_frequency = 'monthly'   then (hmca.last_completed_date + interval '1 month')::date
        when sh.meeting_frequency = 'quarterly' then (hmca.last_completed_date + interval '3 months')::date
        else null
      end as expected_next_meeting_date,
      case
        when hmca.last_completed_date is not null then (current_date - hmca.last_completed_date)
        else null
      end as days_since_last_completed_meeting,
      case
        when coalesce(hmca.has_pending_attendance, false) then 'attendance_pending'
        when hmca.next_scheduled_date is not null then 'scheduled'
        when sh.meeting_frequency is null or sh.meeting_frequency not in ('weekly', 'biweekly', 'monthly', 'quarterly') then 'not_configured'
        when hmca.last_completed_date is null then 'no_meeting_history'
        when (
          case sh.meeting_frequency
            when 'weekly'    then (hmca.last_completed_date + interval '7 days')::date
            when 'biweekly'  then (hmca.last_completed_date + interval '14 days')::date
            when 'monthly'   then (hmca.last_completed_date + interval '1 month')::date
            when 'quarterly' then (hmca.last_completed_date + interval '3 months')::date
          end
        ) < current_date then 'overdue'
        else 'current'
      end as meeting_operational_status
    from scoped_households sh
    join household_leaders hl on hl.household_id = sh.household_id
    left join household_meeting_cadence_agg hmca on hmca.household_node_id = sh.household_id
  ),
  with_operational_status as (
    select
      ch.*,
      case
        when ch.lifecycle_status != 'active' then 'inactive'
        when ch.pastoral_level != 'fraternal' and ch.leadership_status = 'vacant' then 'needs_leader'
        when ch.capacity_status = 'full' then 'at_capacity'
        when ch.capacity_status = 'not_accepting' then 'not_accepting'
        when ch.accepts_new_members and ch.target_member_count is not null and ch.member_count < ch.target_member_count then 'needs_members'
        else 'ready'
      end as operational_status
    from classified_households ch
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'household_id',                      wos.household_id,
      'household_name',                    wos.household_name,
      'pastoral_level',                    wos.pastoral_level,
      'household_category',                wos.household_category,
      'lifecycle_status',                  wos.lifecycle_status,
      'is_couple_household',               wos.is_couple_household,
      'scope_node_id',                     wos.scope_node_id,
      'scope_node_name',                   wos.scope_node_name,
      'formal_leader', case when wos.leader_member_id is not null then jsonb_build_object(
        'leadership_assignment_id', wos.leadership_assignment_id,
        'member_id',                wos.leader_member_id,
        'display_name',             wos.leader_name,
        'role_code',                wos.leader_role_code,
        'role_name',                wos.leader_role_name
      ) else null end,
      'derived_leader_spouse',             wos.derived_spouse_name,
      'leader_display_label',              wos.leader_display_label,
      'member_count',                      wos.member_count,
      'target_member_count',               wos.target_member_count,
      'maximum_member_count',              wos.maximum_member_count,
      'accepts_new_members',               wos.accepts_new_members,
      'capacity_status',                   wos.capacity_status,
      'leadership_status',                 wos.leadership_status,
      'operational_status',                wos.operational_status,
      'meeting_operational_status',        wos.meeting_operational_status,
      'last_completed_meeting_date',       wos.last_completed_meeting_date,
      'next_scheduled_meeting_date',       wos.next_scheduled_meeting_date,
      'expected_next_meeting_date',        wos.expected_next_meeting_date,
      'days_since_last_completed_meeting', wos.days_since_last_completed_meeting,
      'meeting_frequency',                 wos.meeting_frequency,
      'meeting_day_of_week',               wos.meeting_day_of_week,
      'meeting_start_time',                wos.meeting_start_time
    ) order by
      case wos.pastoral_level
        when 'fraternal' then 1
        when 'area' then 2
        when 'chapter' then 3
        when 'unit' then 4
        when 'member' then 5
      end,
      wos.household_name
  ), '[]'::jsonb)
  into v_households_summary
  from with_operational_status wos;

  -- 11. Capacity & Operational Aggregates
  select jsonb_build_object(
    'available',     count(*) filter (where item->>'capacity_status' = 'available'),
    'at_target',     count(*) filter (where item->>'capacity_status' = 'at_target'),
    'full',          count(*) filter (where item->>'capacity_status' = 'full'),
    'not_accepting', count(*) filter (where item->>'capacity_status' = 'not_accepting'),
    'total',         count(*)
  )
  into v_capacity_summary
  from jsonb_array_elements(v_households_summary) item;

  select jsonb_build_object(
    'ready',                     count(*) filter (where item->>'operational_status' = 'ready'),
    'needs_leader',              count(*) filter (where item->>'operational_status' = 'needs_leader'),
    'needs_members',             count(*) filter (where item->>'operational_status' = 'needs_members'),
    'at_capacity',               count(*) filter (where item->>'operational_status' = 'at_capacity'),
    'not_accepting',             count(*) filter (where item->>'operational_status' = 'not_accepting'),
    'placement_review_required', count(*) filter (where item->>'operational_status' = 'placement_review_required'),
    'inactive',                  count(*) filter (where item->>'operational_status' = 'inactive'),
    'total',                     count(*)
  )
  into v_operational_summary
  from jsonb_array_elements(v_households_summary) item;

  -- 12. Leadership Vacancies
  with vacant_nodes as (
    select
      h_vac.id as governance_node_id,
      gn_vac.name as governance_node_name,
      'household_servant_leader'::text as role_code,
      'Household Servant Leader'::text as role_name,
      'member'::text as pastoral_level
    from public.households h_vac
    join public.governance_nodes gn_vac on gn_vac.id = h_vac.id
    where h_vac.organization_id = p_organization_id
      and h_vac.pastoral_level = 'member'
      and gn_vac.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h_vac.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = h_vac.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'household_servant_leader'
      )
    union all
    select
      un.id as governance_node_id,
      un.name as governance_node_name,
      'unit_servant_leader'::text as role_code,
      'Unit Servant Leader'::text as role_name,
      'unit'::text as pastoral_level
    from public.governance_nodes un
    join public.governance_node_types unt on unt.id = un.governance_node_type_id and unt.code = 'unit'
    where un.organization_id = p_organization_id
      and un.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, un.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = un.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'unit_servant_leader'
      )
    union all
    select
      chn.id as governance_node_id,
      chn.name as governance_node_name,
      'chapter_servant_leader'::text as role_code,
      'Chapter Servant Leader'::text as role_name,
      'chapter'::text as pastoral_level
    from public.governance_nodes chn
    join public.governance_node_types chnt on chnt.id = chn.governance_node_type_id and chnt.code = 'chapter'
    where chn.organization_id = p_organization_id
      and chn.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, chn.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = chn.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'chapter_servant_leader'
      )
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'governance_node_id',   vn.governance_node_id,
      'governance_node_name', vn.governance_node_name,
      'role_code',            vn.role_code,
      'role_name',            vn.role_name,
      'pastoral_level',       vn.pastoral_level,
      'vacancy_status',       'vacant'
    ) order by
      case vn.pastoral_level
        when 'chapter' then 1
        when 'unit' then 2
        when 'member' then 3
      end,
      vn.governance_node_name
  ), '[]'::jsonb)
  into v_leadership_vacancies
  from vacant_nodes vn;

  -- 13. Placement Review Summary
  select jsonb_build_object(
    'missing_household',                0,
    'different_level',                  0,
    'no_matching_household_available',  0,
    'manual_review_required',           0,
    'total',                            0,
    'actionable_items',                 '[]'::jsonb
  )
  into v_placement_summary;

  -- 14. Unassigned Members Count
  select count(distinct m.id)
  into v_unassigned_count
  from public.members m
  where m.organization_id = p_organization_id
    and m.membership_status = 'active'
    and not exists (
      select 1
      from public.household_memberships hm
      where hm.member_id = m.id
        and hm.organization_id = p_organization_id
        and hm.is_primary = true
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
    )
    and (
      private.can_access_member('leadership.pastoral_dashboard.view', p_organization_id, m.id)
      or private.can_access_member('households.records.view', p_organization_id, m.id)
    );

  -- 15. Meeting Operations Summary
  -- Scope-aware aggregate of meeting activity in caller's accessible households.
  -- Uses set-based aggregation and exact cadence classification.
  with scoped_meetings as (
    select hm.*
    from public.household_meetings hm
    where hm.organization_id = p_organization_id
      and (
        v_target_scope_node_id is null
        or hm.household_node_id = v_target_scope_node_id
        or exists (
          select 1 from public.governance_node_relationships gnr
          where gnr.parent_node_id = v_target_scope_node_id
            and gnr.child_node_id = hm.household_node_id
            and gnr.organization_id = p_organization_id
            and gnr.relationship_status = 'active'
        )
      )
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, hm.household_node_id)
  )
  select jsonb_build_object(
    'upcoming_meetings', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'scheduled' and meeting_date >= current_date
    ), 0),
    'meetings_this_month', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'completed' and date_trunc('month', meeting_date) = date_trunc('month', current_date)
    ), 0),
    'attendance_pending', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'completed'
        and not (
          private.compute_attendance_summary(
            id,
            p_organization_id,
            meeting_date,
            household_node_id
          )->>'attendance_complete'
        )::boolean
    ), 0),
    'households_without_meeting_history', coalesce((
      select count(*) from jsonb_array_elements(v_households_summary) item
      where item->>'last_completed_meeting_date' is null
    ), 0),
    'households_overdue', coalesce((
      select count(*) from jsonb_array_elements(v_households_summary) item
      where item->>'meeting_operational_status' = 'overdue'
    ), 0),
    'member_follow_up_signals', coalesce((
      select count(distinct hm_fu.member_id)
      from public.household_memberships hm_fu
      join public.households h_fu on h_fu.id = hm_fu.household_node_id
      where hm_fu.organization_id   = p_organization_id
        and hm_fu.is_primary        = true
        and hm_fu.membership_status in ('active', 'temporary')
        and hm_fu.effective_from    <= current_date
        and (hm_fu.effective_to is null or hm_fu.effective_to >= current_date)
        and (
          v_target_scope_node_id is null
          or hm_fu.household_node_id = v_target_scope_node_id
          or exists (
            select 1 from public.governance_node_relationships gnr
            where gnr.parent_node_id = v_target_scope_node_id
              and gnr.child_node_id = hm_fu.household_node_id
              and gnr.organization_id = p_organization_id
              and gnr.relationship_status = 'active'
          )
        )
        and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, hm_fu.household_node_id)
        and (
          private.get_member_follow_up_signals(
            p_organization_id, hm_fu.member_id, hm_fu.household_node_id
          )->>'multiple_recent_absences'
        )::boolean = true
    ), 0)
  )
  into v_meeting_ops_summary;

  -- 16. Return Unified Operational Dashboard Payload
  return jsonb_build_object(
    'organization_id',            p_organization_id,
    'identity',                   v_identity_json,
    'care_responsibilities',      v_care_responsibilities,
    'household_summary',          v_households_summary,
    'leadership_vacancies',       v_leadership_vacancies,
    'capacity_summary',           v_capacity_summary,
    'operational_summary',        v_operational_summary,
    'placement_review_summary',   v_placement_summary,
    'unassigned_members_count',   coalesce(v_unassigned_count, 0),
    'meeting_operations_summary', coalesce(v_meeting_ops_summary, jsonb_build_object(
      'upcoming_meetings',                  0,
      'meetings_this_month',                0,
      'attendance_pending',                 0,
      'households_without_meeting_history', 0,
      'households_overdue',                 0,
      'member_follow_up_signals',           0
    ))
  );
end;
$$;

comment on function public.get_pastoral_operations_dashboard(uuid, uuid) is
  'Unified operational pastoral leadership dashboard extended with real set-based meeting cadence operations.';

revoke all on function public.get_pastoral_operations_dashboard(uuid, uuid) from public, anon;
grant execute on function public.get_pastoral_operations_dashboard(uuid, uuid) to authenticated, service_role;

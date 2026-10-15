-- =============================================================================
-- Migration: 20261010086000_lists_by_last_name.sql
-- MissionOS Pass 9.10 (written by Claude, 2026-10-16)
-- Ron: lists of people are alphabetical by LAST name (sort_name = "Family, Given"); lists about dates keep date order.
-- Changes ORDER BY only — no columns, filters, permissions or results change:
--   * household expected roster (leader attendance + household card attendance / Expected members / host picker)
--   * leader meeting detail: expected roster and recorded attendance
--   * pastoral household roster (role groups kept: servant, assistant, then members — by last name within each)
--   * pastoral dashboard household-member list
--   * family profile members (primary contact and family role kept first, then last name)
--   * program run participants and session roster (non-members: last name, first name)
--   * servant-leader placement reconciliation (status groups kept, then last name)
-- Already by last name before this pass: Members, Members without household, Member logins, Place members,
-- event attendance roster and greeters, household profile members.
-- Every replaced function is guarded: the migration stops if its live body differs from the version it was built from.
-- =============================================================================
do $guard$
declare
  r record;
  v_md5 text;
begin
  for r in select * from (values
    ('private', 'get_household_expected_roster', '41a204a123ee4da7cf64b7967251dcc2'),
    ('public', 'get_household_meeting_detail', 'd629d857f123db7c7bbb4a58dfb26a0e'),
    ('public', 'member_get_household_attendance', '71635d650b8c181e3703c4a7fa86b4c4'),
    ('public', 'member_household_roster', '061d50a5904301aa6511d565adccef5c'),
    ('public', 'get_pastoral_household_roster', 'fd8225ace5b1be6f94ad8468be3bbdba'),
    ('public', 'get_pastoral_operations_dashboard', 'ee8871f9dc2311564b1970b724433136'),
    ('public', 'get_family_profile', 'fbd16ffff5c64e1eb65459bf3edbe717'),
    ('public', 'get_program_run', '22a1b6b1f1334c1756b7794cc12c04dc'),
    ('public', 'get_program_session_roster', 'a64ca9897b87d1a63d3957425deb4546'),
    ('public', 'search_servant_leaders_needing_pastoral_placement', '39af5257f042b77b9e23b495bfb8f86b')
  ) t(sch, fn, expected)
  loop
    select md5(replace(p.prosrc, chr(13), '')) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = r.sch and p.proname = r.fn;
    if v_md5 is distinct from r.expected then
      raise exception 'STOP: %.% differs from the version this migration was built from (md5 %).', r.sch, r.fn, v_md5;
    end if;
  end loop;
end;
$guard$;

-- Sort key for program participants: member sort_name, else "last, first" for non-members.
create or replace function private.program_participant_sort_name(p public.program_participants)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce((select m.sort_name from public.members m where m.id = p.member_id),
                  btrim(coalesce(p.last_name, '') || ', ' || coalesce(p.first_name, ''), ', '))
$$;
revoke all on function private.program_participant_sort_name(public.program_participants) from public, anon, authenticated;

-- private.get_household_expected_roster  (from 20261002020000_phase_6b_household_meetings_attendance_corrections.sql)
create or replace function private.get_household_expected_roster(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_as_of_date        date
)
returns table (
  member_id       uuid,
  display_name    text,
  membership_role text
)
language sql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
  -- PRIMARY HOUSEHOLD RULE (Phase 6B-8 canonical):
  --   A member's expected household attendance is determined by their PRIMARY
  --   household membership (is_primary = true) as of the meeting date.
  --
  --   Same-day transfer semantics:
  --     ended predecessor: membership_status = 'ended' → excluded by status filter
  --     active successor:  membership_status = 'active', effective_from = transfer_date → included
  --
  --   Zero-member household: returns empty set → compute_attendance_summary returns false.
  select
    hm.member_id,
    coalesce(mn.full_name, 'Unknown Member') as display_name,
    hm.membership_role
  from public.household_memberships hm
  join public.members m
    on m.id = hm.member_id
    and m.organization_id = p_organization_id
  left join (
    select mn2.member_id, mn2.full_name
    from public.member_names mn2
    where mn2.is_primary = true
      and mn2.effective_to is null
  ) mn on mn.member_id = hm.member_id
  where hm.household_node_id = p_household_node_id
    and hm.organization_id   = p_organization_id
    and hm.is_primary        = true            -- PRIMARY HOUSEHOLD ONLY
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from    <= p_as_of_date
    and (hm.effective_to is null or hm.effective_to >= p_as_of_date)
  order by lower(m.sort_name), hm.member_id;
$$;

-- public.get_household_meeting_detail  (from 20261002020000_phase_6b_household_meetings_attendance_corrections.sql)
create or replace function public.get_household_meeting_detail(
  p_organization_id  uuid,
  p_meeting_id       uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_meeting     public.household_meetings%rowtype;
  v_household   public.governance_nodes%rowtype;
  v_summary     jsonb;
  v_expected    jsonb;
  v_recorded    jsonb;
  v_fac_name    text;
  v_host_name   text;
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

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.view', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  select * into v_household from public.governance_nodes where id = v_meeting.household_node_id;

  if v_meeting.facilitator_member_id is not null then
    select full_name into v_fac_name
    from public.member_names
    where member_id = v_meeting.facilitator_member_id
      and is_primary = true
      and effective_to is null
    limit 1;
  end if;

  if v_meeting.host_member_id is not null then
    select full_name into v_host_name
    from public.member_names
    where member_id = v_meeting.host_member_id
      and is_primary = true
      and effective_to is null
    limit 1;
  end if;

  v_summary := private.compute_attendance_summary(
    p_meeting_id, p_organization_id, v_meeting.meeting_date, v_meeting.household_node_id
  );

  -- Historical expected roster: primary-household membership as of meeting_date
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'member_id',       r.member_id,
      'display_name',    r.display_name,
      'membership_role', r.membership_role
    ) order by (select lower(sm.sort_name) from public.members sm where sm.id = r.member_id), r.member_id
  ), '[]'::jsonb)
  into v_expected
  from private.get_household_expected_roster(
    p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date
  ) r;

  -- Recorded attendance (privacy-minimized: no PII beyond display_name)
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'member_id',         a.member_id,
      'display_name',      mn.full_name,
      'attendance_status', a.attendance_status,
      'arrival_time',      a.arrival_time,
      'recorded_at',       a.recorded_at
    ) order by (select lower(sm.sort_name) from public.members sm where sm.id = a.member_id), a.member_id
  ), '[]'::jsonb)
  into v_recorded
  from public.household_meeting_attendance a
  left join (
    select member_id, full_name from public.member_names
    where is_primary = true and effective_to is null
  ) mn on mn.member_id = a.member_id
  where a.household_meeting_id = p_meeting_id
    and a.organization_id      = p_organization_id;

  return jsonb_build_object(
    -- Meeting identity (no notes_summary — reserved/unused in Phase 6B-8)
    'household_meeting_id',     v_meeting.id,
    'household_node_id',        v_meeting.household_node_id,
    'household_name',           v_household.name,
    'meeting_date',             v_meeting.meeting_date,
    'meeting_status',           v_meeting.meeting_status,
    'meeting_type',             v_meeting.meeting_type,
    'location_type',            v_meeting.location_type,
    'location_text',            v_meeting.location_text,
    'scheduled_start_at',       v_meeting.scheduled_start_at,
    'scheduled_end_at',         v_meeting.scheduled_end_at,
    'actual_start_at',          v_meeting.actual_start_at,
    'actual_end_at',            v_meeting.actual_end_at,
    'facilitator_member_id',    v_meeting.facilitator_member_id,
    'facilitator_display_name', v_fac_name,
    'host_member_id',           v_meeting.host_member_id,
    'host_display_name',        v_host_name,
    -- notes_summary deliberately OMITTED from return (reserved, potentially hazardous)
    'attendance_recorded_at',   v_meeting.attendance_recorded_at,
    'attendance_summary',       v_summary,
    'expected_roster',          v_expected,
    'recorded_attendance',      v_recorded,
    'created_at',               v_meeting.created_at
  );
end;
$$;

-- public.member_get_household_attendance  (from 20261010085000_household_card_meetings_attendance.sql)
create or replace function public.member_get_household_attendance(p_organization_id uuid, p_meeting_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_meeting public.household_meetings%rowtype;
begin
  select * into v_meeting from public.household_meetings
  where id = p_meeting_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Meeting not found.';
  end if;
  perform private.assert_member_can_manage_household(p_organization_id, v_meeting.household_node_id);

  return jsonb_build_object(
    'household_meeting_id', v_meeting.id,
    'meeting_date',         v_meeting.meeting_date,
    'meeting_status',       v_meeting.meeting_status,
    'summary',              private.household_card_attendance_summary(p_organization_id, v_meeting.id),
    'roster', coalesce((
      select jsonb_agg(jsonb_build_object(
               'member_id',         r.member_id,
               'display_name',      r.display_name,
               'attendance_status', a.attendance_status)
             order by (select lower(sm.sort_name) from public.members sm where sm.id = r.member_id), r.member_id)
      from private.household_card_roster(p_organization_id, v_meeting.household_node_id, v_meeting.meeting_date) r
      left join public.household_meeting_attendance a
        on a.household_meeting_id = v_meeting.id and a.organization_id = p_organization_id
       and a.member_id = r.member_id), '[]'::jsonb));
end;
$$;

-- public.member_household_roster  (from 20261010085000_household_card_meetings_attendance.sql)
create or replace function public.member_household_roster(p_organization_id uuid, p_household_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  perform private.assert_member_can_manage_household(p_organization_id, p_household_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object('member_id', r.member_id, 'display_name', r.display_name)
                     order by (select lower(sm.sort_name) from public.members sm where sm.id = r.member_id), r.member_id)
    from private.household_card_roster(p_organization_id, p_household_id, current_date) r), '[]'::jsonb);
end;
$$;

-- public.get_pastoral_household_roster  (from 20261001010000_phase_6b_pastoral_operations_dashboard.sql)
create or replace function public.get_pastoral_household_roster(
  p_organization_id uuid,
  p_household_id    uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id             uuid;
  v_household              public.households%rowtype;
  v_household_node         public.governance_nodes%rowtype;
  v_parent_node            public.governance_nodes%rowtype;
  v_parent_rel             public.governance_node_relationships%rowtype;
  v_formal_leader          jsonb := null;
  v_derived_spouse_name    text := null;
  v_members_roster         jsonb := '[]'::jsonb;
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
    raise exception using errcode = '42501', message = 'You do not have permission to view the pastoral dashboard.';
  end if;

  -- 4. Roster Permission check
  if not private.has_permission('members.households.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household member rosters.';
  end if;

  -- 5. Scope check on target household (indistinguishable P0002)
  if not private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 6. Load household and governance node
  select * into v_household from public.households where id = p_household_id and organization_id = p_organization_id;
  select * into v_household_node from public.governance_nodes where id = p_household_id and organization_id = p_organization_id;

  if v_household.id is null or v_household_node.id is null then
    raise exception using errcode = 'P0002', message = 'Household record not found.';
  end if;

  -- Load parent scope
  select * into v_parent_rel
  from public.governance_node_relationships
  where child_node_id = p_household_id
    and organization_id = p_organization_id
    and relationship_type = 'primary_parent'
    and relationship_status = 'active'
    and (effective_to is null or effective_to >= current_date)
  limit 1;

  if v_parent_rel.parent_node_id is not null then
    select * into v_parent_node from public.governance_nodes where id = v_parent_rel.parent_node_id;
  end if;

  -- 7. Load leadership context
  if v_household.pastoral_level = 'member' then
    select jsonb_build_object(
      'leadership_assignment_id', la.id,
      'member_id',                m.id,
      'display_name',             m.display_name,
      'role_code',                lrd.code,
      'role_name',                lrd.name,
      'effective_from',           la.effective_from
    )
    into v_formal_leader
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id and lrd.code = 'household_servant_leader'
    join public.members m on m.id = la.member_id
    where la.governance_node_id = p_household_id
      and la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
    limit 1;
  elsif v_household.pastoral_level in ('unit', 'chapter', 'area') and v_parent_rel.parent_node_id is not null then
    select jsonb_build_object(
      'leadership_assignment_id', la.id,
      'member_id',                m.id,
      'display_name',             m.display_name,
      'role_code',                lrd.code,
      'role_name',                lrd.name,
      'effective_from',           la.effective_from
    )
    into v_formal_leader
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
      and lrd.code in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    join public.members m on m.id = la.member_id
    where la.governance_node_id = v_parent_rel.parent_node_id
      and la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
    limit 1;
  end if;

  -- Derived spouse if Couples context
  if v_household.is_couple_household and v_formal_leader is not null and v_household.pastoral_level != 'fraternal' then
    select m_sp.display_name
    into v_derived_spouse_name
    from public.family_relationships fr
    join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
    join public.members m_sp on m_sp.id = case when fr.from_member_id = (v_formal_leader->>'member_id')::uuid then fr.to_member_id else fr.from_member_id end
    where fr.organization_id = p_organization_id
      and (fr.from_member_id = (v_formal_leader->>'member_id')::uuid or fr.to_member_id = (v_formal_leader->>'member_id')::uuid)
      and fr.relationship_status = 'active'
      and fr.verification_status in ('verified', 'administrator_verified', 'member_confirmed')
      and (fr.effective_to is null or fr.effective_to >= current_date)
    limit 1;
  end if;

  -- 8. Build privacy-minimized members roster
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'member_id',         m.id,
      'member_number',     m.member_number,
      'display_name',      m.display_name,
      'membership_id',     hm.id,
      'membership_role',   hm.membership_role,
      'membership_status', hm.membership_status,
      'effective_from',    hm.effective_from,
      'is_primary',        hm.is_primary
    ) order by
      case hm.membership_role
        when 'servant' then 1
        when 'assistant_servant' then 2
        else 3
      end,
      lower(m.sort_name), m.id
  ), '[]'::jsonb)
  into v_members_roster
  from public.household_memberships hm
  join public.members m on m.id = hm.member_id and m.organization_id = p_organization_id
  where hm.household_node_id = p_household_id
    and hm.organization_id = p_organization_id
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= current_date
    and (hm.effective_to is null or hm.effective_to >= current_date)
    and private.can_access_member('members.households.view', p_organization_id, m.id);

  -- 9. Return Roster Payload
  return jsonb_build_object(
    'household_id',            v_household.id,
    'household_name',          v_household_node.name,
    'household_category',      v_household.household_category,
    'pastoral_level',          v_household.pastoral_level,
    'lifecycle_status',        v_household_node.lifecycle_status,
    'is_couple_household',     v_household.is_couple_household,
    'scope_node_id',           v_parent_rel.parent_node_id,
    'scope_node_name',         v_parent_node.name,
    'target_member_count',     v_household.target_member_count,
    'maximum_member_count',    v_household.maximum_member_count,
    'accepts_new_members',     v_household.accepts_new_members,
    'meeting_frequency',       v_household.meeting_frequency,
    'meeting_day_of_week',     v_household.meeting_day_of_week,
    'meeting_start_time',      to_char(v_household.meeting_start_time, 'HH24:MI:SS'),
    'meeting_timezone_name',   v_household.meeting_timezone_name,
    'formal_leader',           v_formal_leader,
    'derived_leader_spouse',   v_derived_spouse_name,
    'is_fraternal',            (v_household.pastoral_level = 'fraternal'),
    'members_count',           jsonb_array_length(v_members_roster),
    'members',                 v_members_roster
  );
end;
$$;

-- public.get_pastoral_operations_dashboard  (from 20261010071000_dashboard_leader_cards_role_match.sql)
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
  v_is_org_admin           boolean;
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
  v_formation_ops_summary  jsonb;
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

  v_is_org_admin := private.is_organization_administrator(v_profile_id, p_organization_id);

  -- 4. NON-ADMIN DOUBLE-LOCK REQUIREMENT
  -- Delegated callers MUST hold an active servant leader access grant AND a current active leadership assignment.
  if not v_is_org_admin then
    if not exists (
      select 1
      from public.servant_leader_access_grants g
      join public.leadership_assignments la on la.id = g.leadership_assignment_id
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
        and g.access_status = 'active'
        and g.effective_from <= current_date
        and (g.effective_to is null or g.effective_to >= current_date)
        and la.organization_id = p_organization_id
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date)
    ) then
      raise exception using errcode = '42501',
        message = 'Active servant leader access grant and current leadership assignment are required.';
    end if;
  end if;

  -- 5. Scope verification if specific node supplied
  if p_governance_node_id is not null then
    if not private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, p_governance_node_id) then
      raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
    end if;
    v_target_scope_node_id := p_governance_node_id;
  end if;

  -- 6. Sub-domain permission checks for safe field filtering
  v_can_review_placement := private.has_permission('leadership.pastoral_placement.review', p_organization_id);
  v_can_view_leadership  := private.has_permission('governance.leadership.view', p_organization_id);
  v_can_view_roster      := private.has_permission('members.households.view', p_organization_id);

  -- 7. Resolve caller profile and member link (if exists)
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

  -- 8. If linked to member, resolve Where I Serve (active formal servant roles)
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

  -- 9. Build Identity Block
  v_identity_json := jsonb_build_object(
    'profile_id',                          v_profile_id,
    'member_id',                           v_caller_member_id,
    'display_name',                        v_caller_display_name,
    'has_linked_member',                   (v_caller_member_id is not null),
    'serving_assignments',                 v_serving_assignments,
    'pastoral_membership',                 v_pastoral_membership,
    'pastoral_household_placement_needed', (v_caller_member_id is not null and v_pastoral_membership is null and jsonb_array_length(v_serving_assignments) > 0)
  );

  -- 10. Care Responsibilities
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
            ) order by lower(m.sort_name), m.id
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
          ) filter (where la.id is not null and lrd.id is not null), '[]'::jsonb)
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
          ) filter (where la.id is not null and lrd.id is not null), '[]'::jsonb)
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
          ) filter (where la.id is not null and lrd.id is not null), '[]'::jsonb)
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
    ),
    -- Pass 8.4C: unit/chapter/area servant leaders also lead the household at their own level
    -- (the unit/chapter/area household whose primary parent is their node): list its members.
    level_hh_care as (
      select
        cr.assignment_id,
        (h.pastoral_level || ' household')::text as responsibility_level,
        h.id as scope_id,
        gn.name as scope_name,
        jsonb_build_object(
          'type', 'household_members',
          'household_id', h.id,
          'household_name', gn.name,
          'member_count', count(hm.id),
          'members', case when v_can_view_roster then coalesce(jsonb_agg(
            jsonb_build_object(
              'member_id', m.id,
              'display_name', m.display_name,
              'member_number', m.member_number,
              'membership_role', hm.membership_role,
              'effective_from', hm.effective_from
            ) order by lower(m.sort_name), m.id
          ) filter (where hm.id is not null), '[]'::jsonb) else '[]'::jsonb end
        ) as care_payload
      from caller_roles cr
      join public.governance_node_relationships gnr
        on gnr.parent_node_id = cr.node_id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      join public.households h
        on h.id = gnr.child_node_id
       and h.pastoral_level = case cr.role_code
                                when 'unit_servant_leader'    then 'unit'
                                when 'chapter_servant_leader' then 'chapter'
                                when 'area_servant_leader'    then 'area'
                              end
      join public.governance_nodes gn on gn.id = h.id and gn.lifecycle_status = 'active'
      left join public.household_memberships hm
        on hm.household_node_id = h.id
       and hm.organization_id = p_organization_id
       and hm.membership_status in ('active', 'temporary')
       and hm.effective_from <= current_date
       and (hm.effective_to is null or hm.effective_to >= current_date)
      left join public.members m on m.id = hm.member_id
      where cr.role_code in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
      group by cr.assignment_id, h.id, gn.name, h.pastoral_level
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
      select * from usl_care  where jsonb_array_length(care_payload->'leaders') > 0
      union all
      select * from csl_care  where jsonb_array_length(care_payload->'leaders') > 0
      union all
      select * from asl_care  where jsonb_array_length(care_payload->'leaders') > 0
      union all
      select * from level_hh_care
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
      'days_since_last_completed_meeting', wos.days_since_last_completed_meeting
    ) order by wos.household_name
  ), '[]'::jsonb)
  into v_households_summary
  from with_operational_status wos;

  -- 11. Capacity Summary
  select jsonb_build_object(
    'available',     count(*) filter (where item->>'capacity_status' = 'available'),
    'at_target',     count(*) filter (where item->>'capacity_status' = 'at_target'),
    'full',          count(*) filter (where item->>'capacity_status' = 'full'),
    'not_accepting', count(*) filter (where item->>'capacity_status' = 'not_accepting'),
    'total',         count(*)
  )
  into v_capacity_summary
  from jsonb_array_elements(v_households_summary) item;

  -- 12. Operational Summary
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

  -- 13. Leadership Vacancies
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
    union all
    select
      arn.id as governance_node_id,
      arn.name as governance_node_name,
      'area_servant_leader'::text as role_code,
      'Area Servant Leader'::text as role_name,
      'area'::text as pastoral_level
    from public.governance_nodes arn
    join public.governance_node_types arnt on arnt.id = arn.governance_node_type_id and arnt.code = 'area_state'
    where arn.organization_id = p_organization_id
      and arn.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, arn.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = arn.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'area_servant_leader'
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

  -- 14. Placement Review Summary Integration
  if v_can_review_placement then
    declare
      v_search_res jsonb;
    begin
      v_search_res := public.search_servant_leaders_needing_pastoral_placement(
        p_organization_id    => p_organization_id,
        p_include_correct    => false,
        p_limit              => 100,
        p_offset             => 0
      );

      select jsonb_build_object(
        'missing_household',               count(*) filter (where item->>'placement_status' = 'missing_household'),
        'different_level',                 count(*) filter (where item->>'placement_status' = 'different_level'),
        'no_matching_household_available', count(*) filter (where item->>'placement_status' = 'no_matching_household_available'),
        'manual_review_required',          count(*) filter (where item->>'placement_status' = 'manual_review_required'),
        'total',                           coalesce(v_search_res->>'total_count', '0')::integer,
        'actionable_items',                v_search_res->'items'
      )
      into v_placement_summary
      from jsonb_array_elements(coalesce(v_search_res->'items', '[]'::jsonb)) item;

      if v_placement_summary is null then
        v_placement_summary := jsonb_build_object(
          'missing_household', 0,
          'different_level', 0,
          'no_matching_household_available', 0,
          'manual_review_required', 0,
          'total', 0,
          'actionable_items', '[]'::jsonb
        );
      end if;
    end;
  else
    v_placement_summary := jsonb_build_object(
      'missing_household', 0,
      'different_level', 0,
      'no_matching_household_available', 0,
      'manual_review_required', 0,
      'total', 0,
      'actionable_items', '[]'::jsonb
    );
  end if;

  -- 15. Unassigned Members Count
  select count(m.id)
  into v_unassigned_count
  from public.members m
  where m.organization_id = p_organization_id
    and m.record_status = 'active'
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

  -- 16. Meeting Operations Summary
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

  -- 17. Formation Operations Summary
  with formation_stats as (
    select
      private.compute_household_formation_status((item->>'household_id')::uuid) as formation_status,
      coalesce((
        select count(*)::integer
        from public.household_topic_assignments a
        where a.household_node_id = (item->>'household_id')::uuid
          and a.assignment_status = 'planned'
      ), 0) as planned_count,
      coalesce((
        select count(*)::integer
        from public.household_topic_assignments a
        where a.household_node_id = (item->>'household_id')::uuid
          and a.assignment_status = 'completed'
          and a.completed_at::date >= date_trunc('month', current_date)::date
          and a.completed_at::date <= (date_trunc('month', current_date) + interval '1 month - 1 day')::date
      ), 0) as completed_this_month_count
    from jsonb_array_elements(v_households_summary) item
  )
  select jsonb_build_object(
    'households_with_no_plan',     count(*) filter (where fs.formation_status = 'no_plan'),
    'topics_planned',              coalesce(sum(fs.planned_count), 0)::integer,
    'topics_completed_this_month', coalesce(sum(fs.completed_this_month_count), 0)::integer,
    'topics_due',                  count(*) filter (where fs.formation_status = 'topic_due'),
    'topics_overdue',              count(*) filter (where fs.formation_status = 'topic_overdue')
  ) into v_formation_ops_summary
  from formation_stats fs;

  -- 18. Return Unified Operational Dashboard Payload
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
    )),
    'formation_operations_summary', coalesce(v_formation_ops_summary, jsonb_build_object(
      'households_with_no_plan', 0,
      'topics_planned', 0,
      'topics_completed_this_month', 0,
      'topics_due', 0,
      'topics_overdue', 0
    ))
  );
end;
$$;

-- public.get_family_profile  (from 20260929010000_phase_6a_family_read_corrections.sql)
create or replace function public.get_family_profile(
  p_organization_id uuid,
  p_family_id       uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id            uuid;
  v_family                public.families%rowtype;
  v_can_see_identifiers   boolean;
  v_can_see_relationships boolean;
  v_members_arr           jsonb;
  v_relationships_arr     jsonb;
begin
  -- Step 1: Canonical caller identity resolution
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: families.records.view permission required
  if not private.has_permission('families.records.view', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to view family records.';
  end if;

  -- Step 4: Relational family unit scope check via union-access rule
  if not private.can_access_family(
    'families.records.view', p_organization_id, p_family_id
  ) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 5: Load family row (secondary organization boundary guard)
  select * into v_family
  from public.families f
  where f.id              = p_family_id
    and f.organization_id = p_organization_id;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 6: Field-level permission flags (org-level)
  v_can_see_identifiers   := private.has_permission(
    'members.identifiers.view', p_organization_id);
  v_can_see_relationships := private.has_permission(
    'families.relationships.view', p_organization_id);

  -- Step 7: Assemble members array for the relational family unit
  -- Out-of-scope members are visible at identity-only level (no contact/demographic PII).
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'family_member_id',   fm.id,
        'member_id',          m.id,
        'member_number',      case
                                when v_can_see_identifiers
                                  then m.member_number
                                else null
                              end,
        'display_name',       m.display_name,
        'preferred_name',     m.preferred_name,
        'family_role',        fm.family_role,
        'is_primary_contact', fm.is_primary_contact,
        'is_dependent',       fm.is_dependent,
        'membership_status',  jsonb_build_object(
                                'code',                 ms.code,
                                'name',                 ms.name,
                                'status_category',      ms.status_category,
                                'is_active_membership', ms.is_active_membership
                              ),
        'record_status',      m.record_status,
        'is_deceased',        m.is_deceased,
        'effective_from',     fm.effective_from,
        'effective_to',       fm.effective_to
      )
      order by
        fm.is_primary_contact desc,
        fm.family_role        asc  nulls last,
        lower(m.sort_name)    asc
    ),
    '[]'::jsonb
  )
  into v_members_arr
  from public.family_members fm
  join public.members m
    on  m.id              = fm.member_id
    and m.organization_id = fm.organization_id
  join public.member_statuses ms
    on  ms.id              = m.membership_status_id
    and ms.organization_id = m.organization_id
  where fm.organization_id   = p_organization_id
    and fm.family_id         = p_family_id
    and fm.membership_status = 'active'
    and (
      fm.effective_to is null
      or fm.effective_to > current_date
    );

  -- Step 8: Assemble relationships array (as stored)
  -- Null when caller lacks families.relationships.view.
  if v_can_see_relationships then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'relationship_id',     fr.id,
          'from_member_id',      fr.from_member_id,
          'to_member_id',        fr.to_member_id,
          'relationship_type',   jsonb_build_object(
                                   'code',         frt.code,
                                   'name',         frt.name,
                                   'inverse_code', frt.inverse_code,
                                   'is_symmetric', frt.is_symmetric,
                                   'category',     frt.relationship_category
                                 ),
          'effective_from',      fr.effective_from,
          'effective_to',        fr.effective_to,
          'relationship_status', fr.relationship_status,
          'verification_status', fr.verification_status,
          'source',              fr.source
        )
        order by frt.display_order asc, fr.created_at asc
      ),
      '[]'::jsonb
    )
    into v_relationships_arr
    from public.family_relationships fr
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
    where fr.organization_id     = p_organization_id
      and fr.family_id           = p_family_id
      and fr.relationship_status = 'active';
  else
    v_relationships_arr := null;
  end if;

  -- Step 9: Return assembled profile
  -- NOTE: primary_parish_id, primary_address_id, and administrative_notes
  -- are intentionally EXCLUDED from this read contract.
  return jsonb_build_object(
    'family', jsonb_build_object(
      'id',                   v_family.id,
      'family_name',          v_family.family_name,
      'display_name',         v_family.display_name,
      'family_type',          v_family.family_type,
      'family_status',        v_family.family_status,
      'formed_on',            v_family.formed_on,
      'ended_on',             v_family.ended_on,
      'directory_visibility', v_family.directory_visibility,
      'created_at',           v_family.created_at,
      'updated_at',           v_family.updated_at
    ),
    'members',       v_members_arr,
    'relationships', v_relationships_arr
  );
end;
$$;

-- public.get_program_run  (from 20261010060000_programs_cls_camps.sql)
create or replace function public.get_program_run(
  p_organization_id uuid,
  p_run_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_run public.program_runs%rowtype;
  v_manage boolean;
  v_scheduled integer;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  select * into v_run from public.program_runs where id = p_run_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  v_manage := private.can_manage_program_run(p_organization_id, p_run_id);
  if not (v_manage or private.has_permission('events.view', p_organization_id)
          or private.is_any_section_coordinator(p_organization_id)) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.view.';
  end if;

  select count(*) into v_scheduled from public.events e
  where e.program_run_id = p_run_id and e.event_status <> 'cancelled';

  return jsonb_build_object(
    'run', private.program_run_json(v_run),
    'sessions', coalesce((
      select jsonb_agg(private.event_summary_json(e) order by e.session_number, e.starts_at)
      from public.events e
      where e.program_run_id = p_run_id and e.event_status <> 'cancelled'
    ), '[]'::jsonb),
    'participants', coalesce((
      select jsonb_agg(x.j order by x.sort_key)
      from (
        select lower(private.program_participant_sort_name(p)) as sort_key,
               jsonb_build_object(
                 'participant_id', p.id,
                 'name', private.program_participant_name(p),
                 'is_member', p.member_id is not null,
                 'member_id', p.member_id,
                 'member_number', (select m.member_number from public.members m where m.id = p.member_id),
                 'participant_status', p.participant_status,
                 'invited_by_name', (select m.display_name from public.members m where m.id = p.invited_by_member_id),
                 'invited_by_member_id', p.invited_by_member_id,
                 'phone', case when v_manage then p.phone end,
                 'email', case when v_manage then p.email end,
                 'notes', case when v_manage then p.notes end,
                 'first_name', case when v_manage then p.first_name end,
                 'last_name', case when v_manage then p.last_name end,
                 'attended_sessions', coalesce((
                   select jsonb_agg(e.session_number order by e.session_number)
                   from public.program_participant_attendance a
                   join public.events e on e.id = a.event_id and e.event_status <> 'cancelled'
                   where a.participant_id = p.id and a.removed_at is null
                 ), '[]'::jsonb),
                 'attended_count', (
                   select count(*)
                   from public.program_participant_attendance a
                   join public.events e on e.id = a.event_id and e.event_status <> 'cancelled'
                   where a.participant_id = p.id and a.removed_at is null
                 ),
                 'graduated', p.participant_status = 'registered'
                              and v_scheduled = v_run.session_count
                              and (select count(*)
                                   from public.program_participant_attendance a
                                   join public.events e on e.id = a.event_id and e.event_status <> 'cancelled'
                                   where a.participant_id = p.id and a.removed_at is null) = v_run.session_count
               ) as j
        from public.program_participants p
        where p.program_run_id = p_run_id
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

-- public.get_program_session_roster  (from 20261010060000_programs_cls_camps.sql)
create or replace function public.get_program_session_roster(
  p_organization_id uuid,
  p_event_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event public.events%rowtype;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id and program_run_id is not null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program session not found.';
  end if;
  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'Access denied: you cannot record attendance for this session.';
  end if;

  return jsonb_build_object(
    'event', private.event_summary_json(v_event),
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
               'participant_id', p.id,
               'name', private.program_participant_name(p),
               'is_member', p.member_id is not null,
               'member_number', (select m.member_number from public.members m where m.id = p.member_id),
               'is_present', exists (select 1 from public.program_participant_attendance a
                                     where a.event_id = p_event_id and a.participant_id = p.id and a.removed_at is null))
             order by lower(private.program_participant_sort_name(p)))
      from public.program_participants p
      where p.program_run_id = v_event.program_run_id and p.participant_status = 'registered'
    ), '[]'::jsonb)
  );
end;
$$;

-- public.search_servant_leaders_needing_pastoral_placement  (from 20261010072000_fraternal_households_may_be_mixed.sql)
create or replace function public.search_servant_leaders_needing_pastoral_placement(
  p_organization_id uuid,
  p_include_correct boolean default false,
  p_limit           integer default 50,
  p_offset          integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_results      jsonb := '[]'::jsonb;
  v_total_count  integer := 0;
  v_limit        integer;
  v_offset       integer;
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

  -- 3. Permission check
  if not private.has_permission('leadership.pastoral_placement.review', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view pastoral placement reviews.';
  end if;

  v_limit  := greatest(1, least(coalesce(p_limit, 50), 100));
  v_offset := greatest(0, coalesce(p_offset, 0));

  -- 4. Set-based evaluation over active canonical servant leader assignments
  with leader_candidates as (
    select
      la.id as leadership_assignment_id,
      lrd.code as role_code,
      lrd.name as role_name,
      m.id as leader_member_id,
      m.display_name as leader_name,
      gn.id as formal_governance_node_id,
      gn.name as formal_governance_node_name,
      h_origin.is_couple_household as origin_is_couple_household,
      -- Recommended level
      case lrd.code
        when 'household_servant_leader' then 'unit'
        when 'unit_servant_leader'      then 'chapter'
        when 'chapter_servant_leader'   then 'area'
        when 'area_servant_leader'      then 'fraternal'
      end as recommended_level,
      -- Recommended scope node
      case lrd.code
        when 'area_servant_leader' then gn.id
        else parent_rel.parent_node_id
      end as recommended_scope_node_id,
      case lrd.code
        when 'area_servant_leader' then gn.name
        else parent_gn.name
      end as recommended_scope_node_name,
      -- Current primary household of leader
      curr_hm.household_node_id as current_hh_id,
      curr_gn.name as current_hh_name,
      curr_h.pastoral_level as current_pastoral_level,
      curr_parent_rel.parent_node_id as current_hh_parent_id,
      -- Spouse context
      sp_rel.spouse_id,
      sp_rel.spouse_name,
      sp_rel.is_verified as spouse_verified,
      sp_curr_hm.household_node_id as spouse_current_hh_id,
      sp_curr_gn.name as spouse_current_hh_name,
      -- Three-state couples context resolution
      case
        -- Household Servant Leader: originating member household is authoritative
        when lrd.code = 'household_servant_leader' then
          case
            when h_origin.is_couple_household is true then 'couples'
            when h_origin.is_couple_household is false then 'non_couples'
            else 'ambiguous'
          end
        -- Higher levels: USL, CSL, ASL
        -- Unmarried leader -> non_couples
        when sp_rel.spouse_id is null then 'non_couples'
        -- Married leader Priority A: primary_section_node_id
        when m.primary_section_node_id is not null and exists (
          select 1 from public.governance_nodes sgn
          where sgn.id = m.primary_section_node_id
            and (sgn.code ilike '%couple%' or sgn.name ilike '%couple%' or coalesce(sgn.metadata->>'is_couple_section', 'false')::boolean = true or coalesce(sgn.metadata->>'section_category', '') = 'couples')
        ) then 'couples'
        when m.primary_section_node_id is not null then 'non_couples'
        -- Married leader Priority B: member_governance_assignments for section
        when exists (
          select 1
          from public.member_governance_assignments mga
          join public.governance_nodes sgn on sgn.id = mga.governance_node_id
          join public.governance_node_types gnt on gnt.id = sgn.governance_node_type_id and gnt.code = 'section'
          where mga.member_id = m.id
            and mga.organization_id = la.organization_id
            and mga.assignment_status = 'active'
            and mga.effective_from <= current_date
            and (mga.effective_to is null or mga.effective_to >= current_date)
            and (sgn.code ilike '%couple%' or sgn.name ilike '%couple%' or coalesce(sgn.metadata->>'is_couple_section', 'false')::boolean = true or coalesce(sgn.metadata->>'section_category', '') = 'couples')
        ) then 'couples'
        when exists (
          select 1
          from public.member_governance_assignments mga
          join public.governance_nodes sgn on sgn.id = mga.governance_node_id
          join public.governance_node_types gnt on gnt.id = sgn.governance_node_type_id and gnt.code = 'section'
          where mga.member_id = m.id
            and mga.organization_id = la.organization_id
            and mga.assignment_status = 'active'
            and mga.effective_from <= current_date
            and (mga.effective_to is null or mga.effective_to >= current_date)
        ) then 'non_couples'
        -- Married leader Priority C: pastoral lineage
        when curr_h.is_couple_household is true then 'couples'
        when curr_h.is_couple_household is false then 'non_couples'
        -- Married leader Priority D: governance node metadata
        when (coalesce(gn.metadata->>'is_couple_section', 'false')::boolean = true
              or coalesce(gn.metadata->>'section_category', '') = 'couples'
              or gn.code ilike '%couple%' or gn.name ilike '%couple%') then 'couples'
        -- Missing evidence -> AMBIGUOUS
        else 'ambiguous'
      end as couples_context_status
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join public.members m on m.id = la.member_id and m.organization_id = la.organization_id
    join public.governance_nodes gn on gn.id = la.governance_node_id and gn.organization_id = la.organization_id
    left join public.households h_origin on h_origin.id = gn.id
    left join public.governance_node_relationships parent_rel
      on parent_rel.child_node_id = gn.id
     and parent_rel.organization_id = la.organization_id
     and parent_rel.relationship_type = 'primary_parent'
     and parent_rel.relationship_status = 'active'
     and parent_rel.effective_from <= current_date
     and (parent_rel.effective_to is null or parent_rel.effective_to >= current_date)
    left join public.governance_nodes parent_gn on parent_gn.id = parent_rel.parent_node_id
    -- Leader's current primary household
    left join public.household_memberships curr_hm
      on curr_hm.member_id = m.id
     and curr_hm.organization_id = la.organization_id
     and curr_hm.is_primary = true
     and curr_hm.membership_status in ('active', 'temporary')
     and curr_hm.effective_from <= current_date
     and (curr_hm.effective_to is null or curr_hm.effective_to >= current_date)
    left join public.governance_nodes curr_gn on curr_gn.id = curr_hm.household_node_id
    left join public.households curr_h on curr_h.id = curr_hm.household_node_id
    left join public.governance_node_relationships curr_parent_rel
      on curr_parent_rel.child_node_id = curr_hm.household_node_id
     and curr_parent_rel.organization_id = la.organization_id
     and curr_parent_rel.relationship_type = 'primary_parent'
     and curr_parent_rel.relationship_status = 'active'
     and curr_parent_rel.effective_from <= current_date
     and (curr_parent_rel.effective_to is null or curr_parent_rel.effective_to >= current_date)
    -- Spouse resolution
    left join lateral (
      select
        case when fr.from_member_id = m.id then fr.to_member_id else fr.from_member_id end as spouse_id,
        sm.display_name as spouse_name,
        (fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')) as is_verified
      from public.family_relationships fr
      join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
      join public.members sm on sm.id = case when fr.from_member_id = m.id then fr.to_member_id else fr.from_member_id end
      where fr.organization_id = la.organization_id
        and fr.relationship_status = 'active'
        and (fr.effective_from is null or fr.effective_from <= current_date)
        and (fr.effective_to is null or fr.effective_to >= current_date)
        and (fr.from_member_id = m.id or fr.to_member_id = m.id)
      order by case when fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified') then 0 else 1 end, fr.created_at desc
      limit 1
    ) sp_rel on true
    -- Spouse's current household
    left join public.household_memberships sp_curr_hm
      on sp_curr_hm.member_id = sp_rel.spouse_id
     and sp_curr_hm.organization_id = la.organization_id
     and sp_curr_hm.is_primary = true
     and sp_curr_hm.membership_status in ('active', 'temporary')
     and sp_curr_hm.effective_from <= current_date
     and (sp_curr_hm.effective_to is null or sp_curr_hm.effective_to >= current_date)
    left join public.governance_nodes sp_curr_gn on sp_curr_gn.id = sp_curr_hm.household_node_id
    where la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
      and private.can_access_governance_node('leadership.pastoral_placement.review', p_organization_id, la.governance_node_id)
      and private.can_access_member('leadership.pastoral_placement.review', p_organization_id, la.member_id)
  ),
  classified as (
    select
      lc.*,
      case
        when lc.couples_context_status = 'couples' then true
        when lc.couples_context_status = 'non_couples' then false
        else null
      end as is_couple_context,
      case
        -- Ambiguous context requires manual review
        when lc.couples_context_status = 'ambiguous' then 'manual_review_required'
        when lc.couples_context_status = 'couples' and (lc.spouse_id is null or not coalesce(lc.spouse_verified, false)) then 'manual_review_required'
        when not exists (
          select 1
          from public.households dh
          join public.governance_nodes dgn on dgn.id = dh.id
          left join public.governance_node_relationships dgnr
            on dgnr.child_node_id = dh.id
           and dgnr.organization_id = p_organization_id
           and dgnr.relationship_type = 'primary_parent'
           and dgnr.relationship_status = 'active'
          where dh.organization_id = p_organization_id
            and dgn.lifecycle_status = 'active'
            and dh.pastoral_level = lc.recommended_level
            and (
              (lc.recommended_level != 'fraternal' and dgnr.parent_node_id = lc.recommended_scope_node_id)
              or (lc.recommended_level = 'fraternal' and coalesce(dgnr.parent_node_id, dgn.id) = lc.recommended_scope_node_id)
            )
            and (
              (lc.couples_context_status = 'couples' and coalesce(dh.is_couple_household, false) = true)
              or (lc.couples_context_status = 'couples' and lc.recommended_level = 'fraternal')  -- Pass 8.4G: fraternal may be mixed
              or (lc.couples_context_status = 'non_couples')
            )
        ) then 'no_matching_household_available'
        when lc.current_hh_id is null then 'missing_household'
        when lc.current_pastoral_level = lc.recommended_level
             and (
               (lc.recommended_level != 'fraternal' and lc.current_hh_parent_id = lc.recommended_scope_node_id)
               or (lc.recommended_level = 'fraternal' and coalesce(lc.current_hh_parent_id, lc.current_hh_id) = lc.recommended_scope_node_id)
             ) then 'correct'
        else 'different_level'
      end as placement_status
    from leader_candidates lc
  )
  select
    count(*),
    coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id',    c.leadership_assignment_id,
        'role_code',                   c.role_code,
        'role_name',                   c.role_name,
        'leader_member_id',            c.leader_member_id,
        'leader_name',                 c.leader_name,
        'governance_node_id',          c.formal_governance_node_id,
        'governance_node_name',        c.formal_governance_node_name,
        'recommended_pastoral_level',  c.recommended_level,
        'recommended_scope_node_id',   c.recommended_scope_node_id,
        'recommended_scope_name',      c.recommended_scope_node_name,
        'current_household_id',        c.current_hh_id,
        'current_household_name',      c.current_hh_name,
        'placement_status',            c.placement_status,
        'couples_context',             c.is_couple_context,
        'couples_context_status',      c.couples_context_status,
        'spouse_name',                 c.spouse_name,
        'spouse_current_household_name', c.spouse_current_hh_name
      ) order by
        case c.placement_status
          when 'manual_review_required'          then 1
          when 'no_matching_household_available' then 2
          when 'missing_household'               then 3
          when 'different_level'                 then 4
          when 'correct'                         then 5
        end,
        (select lower(sm.sort_name) from public.members sm where sm.id = c.leader_member_id), c.leader_member_id
    ), '[]'::jsonb)
  into v_total_count, v_results
  from (
    select *
    from classified
    where (p_include_correct or placement_status != 'correct')
    limit v_limit
    offset v_offset
  ) c;

  return jsonb_build_object(
    'total_count', coalesce(v_total_count, 0),
    'items',       coalesce(v_results, '[]'::jsonb)
  );
end;
$$;

-- =============================================================================
-- Migration: 20260929150000_phase_6b_couples_leadership_clarification.sql
-- Phase:     Phase 6B-3 — Couples Section Leadership & Household Leaders Derivation
--
-- Domain Clarifications for MFC Couples Section:
--   1. The HUSBAND holds the single formal pastoral office:
--      HOUSEHOLD SERVANT (in public.leadership_assignments)
--   2. BOTH SPOUSES together are referred to pastorally as:
--      HOUSEHOLD LEADERS (derived couple presentation)
--   3. The wife is NOT:
--      Assistant Household Servant, Co-Household Servant, or Deputy Household Servant.
--      Do NOT create a second leadership_assignment for the wife.
--      Her household_memberships.membership_role remains 'member' (husband is 'servant').
--   4. Couples Section Rule:
--      Applies specifically to couple households (is_couple_household = true).
--      Resolves active formal household_servant -> resolves verified spouse in
--      family_relationships (symmetric 'spouse' type) -> confirms spouse is also
--      an active member of the same household.
--      If spouse is not in the household, unresolvable, or unverified: pastoral
--      couple is not derived (only formal Household Servant is shown).
--   5. Lifetime & Replacement:
--      Concluding or replacing the formal Household Servant automatically updates
--      or vacates the derived Household Leaders couple.
--
-- Updates:
--   - public.get_household_profile: Adds 'household_leaders' object when
--     is_couple_household = true and servant's verified spouse is an active member.
-- =============================================================================

create or replace function public.get_household_profile(
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
  v_profile_id   uuid;
  v_has_id_perm  boolean;
  v_profile_data jsonb;
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
  if not private.has_permission('households.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household records.';
  end if;

  -- 4. Governance-scoped access check (indistinguishable P0002 to prevent existence leakage)
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Identifier permission for roster member numbers
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Build profile payload
  with household_identity as (
    select
      gn.id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      gn.effective_from,
      gn.effective_to,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      h.meeting_timezone_name,
      h.meeting_location_type,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.language_code,
      h.is_couple_household
    from public.governance_nodes gn
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    where gn.id = p_household_id
      and gn.organization_id = p_organization_id
  ),
  parent_gov as (
    select
      gnr.parent_node_id,
      pgn.name as parent_node_name,
      pgn.code as parent_node_code,
      pgnt.code as parent_node_type
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    join public.governance_node_types pgnt
      on pgnt.id = pgn.governance_node_type_id
     and pgnt.organization_id = pgn.organization_id
    where gnr.child_node_id = p_household_id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
    order by
      case when gnr.relationship_status = 'active' and gnr.effective_from <= current_date and (gnr.effective_to is null or gnr.effective_to >= current_date) then 0 else 1 end,
      gnr.effective_to desc nulls first,
      gnr.effective_from desc,
      gnr.created_at desc
    limit 1
  ),
  active_members as (
    select
      hm.id as household_membership_id,
      m.id as member_id,
      case
        when v_has_id_perm then m.member_number
        else null
      end as member_number,
      m.display_name,
      hm.membership_status,
      hm.membership_role,
      hm.is_primary,
      hm.effective_from,
      hm.effective_to
    from public.household_memberships hm
    join public.members m
      on m.id = hm.member_id
     and m.organization_id = hm.organization_id
    where hm.household_node_id = p_household_id
      and hm.organization_id = p_organization_id
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    order by
      case when hm.membership_role in ('servant', 'leader') then 0 else 1 end,
      m.display_name asc
  ),
  formal_leaders as (
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from public.leadership_assignments la
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where la.governance_node_id = p_household_id
      and la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
    order by coalesce(lrd.display_order, 999) asc, m.display_name asc
  ),
  couple_leaders as (
    select
      servant.member_id as servant_member_id,
      servant.display_name as servant_display_name,
      servant.effective_from as servant_effective_from,
      spouse_mem.member_id as spouse_member_id,
      spouse_mem.display_name as spouse_display_name
    from formal_leaders servant
    join household_identity hi on hi.is_couple_household = true
    -- Look up canonical spouse relationship in family_relationships
    join public.family_relationships fr
      on fr.organization_id = p_organization_id
     and fr.relationship_status = 'active'
     and fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')
     and (fr.effective_from is null or fr.effective_from <= current_date)
     and (fr.effective_to is null or fr.effective_to >= current_date)
     and (fr.from_member_id = servant.member_id or fr.to_member_id = servant.member_id)
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
     and frt.code = 'spouse'
    -- Identify the spouse member id
    cross join lateral (
      values (case when fr.from_member_id = servant.member_id then fr.to_member_id else fr.from_member_id end)
    ) as target_spouse(member_id)
    -- Spouse MUST also be an active member of this same household
    join active_members spouse_mem
      on spouse_mem.member_id = target_spouse.member_id
    where servant.leadership_role_code in ('household_servant', 'H-SERV')
    limit 1
  )
  select jsonb_build_object(
    'household', (
      select jsonb_build_object(
        'id', hi.id,
        'name', hi.name,
        'code', hi.code,
        'lifecycle_status', hi.lifecycle_status,
        'household_category', hi.household_category,
        'effective_from', hi.effective_from,
        'effective_to', hi.effective_to,
        'meeting_frequency', hi.meeting_frequency,
        'meeting_day_of_week', hi.meeting_day_of_week,
        'meeting_start_time', hi.meeting_start_time,
        'meeting_timezone_name', hi.meeting_timezone_name,
        'meeting_location_type', hi.meeting_location_type,
        'target_member_count', hi.target_member_count,
        'maximum_member_count', hi.maximum_member_count,
        'accepts_new_members', hi.accepts_new_members,
        'language_code', hi.language_code,
        'is_couple_household', hi.is_couple_household
      )
      from household_identity hi
    ),
    'parent_governance', (
      select case
        when count(pg.*) = 0 then null
        else jsonb_build_object(
          'parent_node_id',   (array_agg(pg.parent_node_id))[1],
          'parent_node_name', (array_agg(pg.parent_node_name))[1],
          'parent_node_code', (array_agg(pg.parent_node_code))[1],
          'parent_node_type', (array_agg(pg.parent_node_type))[1]
        )
      end
      from parent_gov pg
    ),
    'leaders', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'leadership_assignment_id', fl.leadership_assignment_id,
            'member_id',                fl.member_id,
            'display_name',             fl.display_name,
            'leadership_role_code',     fl.leadership_role_code,
            'leadership_role_name',     fl.leadership_role_name,
            'assignment_status',        fl.assignment_status,
            'effective_from',           fl.effective_from,
            'effective_to',             fl.effective_to
          )
        )
        from formal_leaders fl
      ),
      '[]'::jsonb
    ),
    'household_leaders', (
      select case
        when count(cl.*) = 0 then null
        else jsonb_build_object(
          'husband', jsonb_build_object(
            'member_id',    (array_agg(cl.servant_member_id))[1],
            'display_name', (array_agg(cl.servant_display_name))[1]
          ),
          'wife', jsonb_build_object(
            'member_id',    (array_agg(cl.spouse_member_id))[1],
            'display_name', (array_agg(cl.spouse_display_name))[1]
          ),
          'pastoral_label', 'Household Leaders',
          'formatted_names', (array_agg(cl.servant_display_name))[1] || ' & ' || (array_agg(cl.spouse_display_name))[1],
          'effective_from', (array_agg(cl.servant_effective_from))[1]
        )
      end
      from couple_leaders cl
    ),
    'members', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'household_membership_id', am.household_membership_id,
            'member_id',               am.member_id,
            'member_number',           am.member_number,
            'display_name',            am.display_name,
            'membership_status',       am.membership_status,
            'membership_role',         am.membership_role,
            'is_primary',              am.is_primary,
            'effective_from',          am.effective_from,
            'effective_to',            am.effective_to
          )
        )
        from active_members am
      ),
      '[]'::jsonb
    ),
    'counts', (
      select jsonb_build_object(
        'active_member_count',  (select count(*) from active_members),
        'target_member_count',  hi.target_member_count,
        'maximum_member_count', hi.maximum_member_count,
        'accepts_new_members',  hi.accepts_new_members
      )
      from household_identity hi
    )
  )
  into v_profile_data;

  return v_profile_data;
end;
$$;

comment on function public.get_household_profile(uuid, uuid) is
  'Returns complete household pastoral profile, parent governance context, active members roster, formal leaders, and derived pastoral Household Leaders couple for Couples section households with a verified spouse.';

revoke execute on function public.get_household_profile(uuid, uuid) from public, anon;
grant  execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

-- =============================================================================
-- Migration: 20261001000000_phase_6b_pastoral_placement_couples_context_corrections.sql
-- Phase:     Phase 6B-6 — Pastoral Placement Couples Context Corrections
--
-- Authoritative Domain Model & Corrections:
--   1. Define Three-State Couples Context:
--      Couples context is no longer modeled strictly as boolean true/false.
--      Instead, the context is derived into:
--        - couples_context_status: 'couples' | 'non_couples' | 'ambiguous'
--        - is_couple_context:      true | false | null (null when ambiguous)
--        - couples_context_source: 'originating_household' | 'primary_section' |
--                                  'member_governance_assignment' | 'pastoral_lineage' |
--                                  'unmarried_individual' | 'unresolved'
--      Core Domain Rule: Absence of structural evidence != non-Couples.
--
--   2. Echelon Resolution Ladder:
--      - household_servant_leader:
--          Originating Member Household (households.is_couple_household) is authoritative.
--          true  -> couples / true / 'originating_household'
--          false -> non_couples / false / 'originating_household'
--      - unit_servant_leader / chapter_servant_leader / area_servant_leader:
--          Resolved using authoritative evidence in priority:
--            A. member primary_section_node_id
--            B. member_governance_assignments identifying section membership
--            C. current/pastoral household lineage explicitly establishing Couples context
--            D. other canonical section metadata on governance nodes
--          If married with verified spouse but authoritative evidence is missing:
--            -> 'ambiguous' / null / 'unresolved'
--          If member is unmarried (no active spouse relationship):
--            -> 'non_couples' / false / 'unmarried_individual'
--
--   3. Update public.get_servant_leader_pastoral_placement_guidance:
--      Expose couples_context_status, couples_context_source, and is_couple_context.
--      When status = 'ambiguous', sets placement_status = 'manual_review_required'.
--
--   4. Update public.get_pastoral_placement_review:
--      Exposes couples_context (boolean | null), couples_context_status, and
--      couples_context_source.
--      When context is 'ambiguous', sets workflow_status = 'manual_review_required'
--      and recommended_action = 'review_spouse'. Destination execution is blocked.
--
--   5. Update public.execute_pastoral_placement:
--      Recomputes Couples context at execution time.
--      If couples_context_status = 'ambiguous':
--        Raises controlled error 22023:
--        "Pastoral placement requires review because Couples ministry context cannot be determined authoritatively."
--      Enforces that p_include_verified_spouse = false does NOT bypass an ambiguous context.
--
--   6. Update public.search_servant_leaders_needing_pastoral_placement:
--      Ambiguous higher-level leaders appear in the review queue as
--      'manual_review_required' rather than ordinary individual candidates.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Redefine public.get_servant_leader_pastoral_placement_guidance
-- =============================================================================

create or replace function public.get_servant_leader_pastoral_placement_guidance(
  p_organization_id          uuid,
  p_member_id                uuid,
  p_leadership_assignment_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id                uuid;
  v_member                    public.members%rowtype;
  v_assignment                public.leadership_assignments%rowtype;
  v_role_def                  public.leadership_role_definitions%rowtype;
  v_gov_node                  public.governance_nodes%rowtype;
  v_gov_node_type             public.governance_node_types%rowtype;
  v_current_hh_id             uuid;
  v_current_hh_name           text;
  v_current_hh_parent_id      uuid;
  v_current_pastoral_level    text;
  v_recommended_level         text;
  v_recommended_node_id       uuid;
  v_recommended_node_name     text;
  v_matching_hh_count         integer := 0;
  v_placement_status          text;
  v_is_couple_context         boolean := null;
  v_couples_context_status    text    := 'ambiguous';
  v_couples_context_source    text    := 'unresolved';
  v_spouse_id                 uuid;
  v_spouse_name               text;
  v_spouse_verified           boolean := false;
  v_has_any_spouse            boolean := false;
  v_parent_rel                public.governance_node_relationships%rowtype;
  v_origin_is_couple          boolean;
  v_section_node_id           uuid;
  v_section_is_couple         boolean;
  v_pastoral_lineage_is_couple boolean;
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

  -- 3. Scope check on member using members.households.view or members.records.view
  if not (
    private.can_access_member('members.households.view', p_organization_id, p_member_id)
    or private.can_access_member('members.records.view', p_organization_id, p_member_id)
  ) then
    raise exception using errcode = 'P0002', message = 'Member record not found or not accessible.';
  end if;

  select * into v_member from public.members where id = p_member_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Member record not found.';
  end if;

  -- 4. Resolve leadership assignment
  if p_leadership_assignment_id is not null then
    select *
    into v_assignment
    from public.leadership_assignments la
    where la.id = p_leadership_assignment_id
      and la.organization_id = p_organization_id
      and la.member_id = p_member_id;
  else
    -- Resolve most recent active canonical pastoral assignment
    select la.*
    into v_assignment
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    where la.organization_id = p_organization_id
      and la.member_id = p_member_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
    order by la.effective_from desc
    limit 1;
  end if;

  if v_assignment.id is null then
    return jsonb_build_object(
      'has_formal_role', false,
      'member_id',       p_member_id,
      'message',         'No active canonical servant leader assignment found for this member.'
    );
  end if;

  -- Resolve role definition
  select * into v_role_def from public.leadership_role_definitions where id = v_assignment.leadership_role_definition_id;

  -- Resolve governance node where leader serves
  select * into v_gov_node from public.governance_nodes where id = v_assignment.governance_node_id;
  select * into v_gov_node_type from public.governance_node_types where id = v_gov_node.governance_node_type_id;

  -- 5. Determine recommended pastoral level and parent scope node
  if v_role_def.code = 'household_servant_leader' then
    v_recommended_level := 'unit';
    select gnr.* into v_parent_rel
    from public.governance_node_relationships gnr
    where gnr.child_node_id = v_gov_node.id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and gnr.effective_from <= current_date
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    limit 1;

    v_recommended_node_id := v_parent_rel.parent_node_id;

  elsif v_role_def.code = 'unit_servant_leader' then
    v_recommended_level := 'chapter';
    select gnr.* into v_parent_rel
    from public.governance_node_relationships gnr
    where gnr.child_node_id = v_gov_node.id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and gnr.effective_from <= current_date
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    limit 1;

    v_recommended_node_id := v_parent_rel.parent_node_id;

  elsif v_role_def.code = 'chapter_servant_leader' then
    v_recommended_level := 'area';
    select gnr.* into v_parent_rel
    from public.governance_node_relationships gnr
    where gnr.child_node_id = v_gov_node.id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and gnr.effective_from <= current_date
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    limit 1;

    v_recommended_node_id := v_parent_rel.parent_node_id;

  elsif v_role_def.code = 'area_servant_leader' then
    v_recommended_level := 'fraternal';
    v_recommended_node_id := v_gov_node.id;
  end if;

  if v_recommended_node_id is not null then
    select name into v_recommended_node_name from public.governance_nodes where id = v_recommended_node_id;
  end if;

  -- 6. Evaluate Spouse Relationship Context
  select
    target_spouse.member_id,
    sm.display_name,
    (fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified'))
  into
    v_spouse_id,
    v_spouse_name,
    v_spouse_verified
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id and frt.code = 'spouse'
  cross join lateral (
    values (case when fr.from_member_id = p_member_id then fr.to_member_id else fr.from_member_id end)
  ) as target_spouse(member_id)
  join public.members sm on sm.id = target_spouse.member_id and sm.organization_id = p_organization_id
  where fr.organization_id = p_organization_id
    and fr.relationship_status = 'active'
    and (fr.effective_from is null or fr.effective_from <= current_date)
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id)
  order by
    case when fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified') then 0 else 1 end,
    fr.created_at desc
  limit 1;

  if v_spouse_id is not null then
    v_has_any_spouse := true;
  end if;

  -- 7. Three-State Couples Context Resolution
  if v_role_def.code = 'household_servant_leader' then
    -- Rule: The originating Member Household is authoritative
    select h.is_couple_household
    into v_origin_is_couple
    from public.households h
    where h.id = v_gov_node.id
      and h.organization_id = p_organization_id;

    if v_origin_is_couple is true then
      v_couples_context_status := 'couples';
      v_is_couple_context      := true;
      v_couples_context_source := 'originating_household';
    elsif v_origin_is_couple is false then
      v_couples_context_status := 'non_couples';
      v_is_couple_context      := false;
      v_couples_context_source := 'originating_household';
    else
      v_couples_context_status := 'ambiguous';
      v_is_couple_context      := null;
      v_couples_context_source := 'originating_household';
    end if;

  else
    -- Higher-Level Roles: USL, CSL, ASL
    if not v_has_any_spouse then
      -- Unmarried leader has no spouse; cannot be paired in couples placement
      v_couples_context_status := 'non_couples';
      v_is_couple_context      := false;
      v_couples_context_source := 'unmarried_individual';
    else
      -- Married leader: check authoritative evidence in priority
      -- Priority A: member primary_section_node_id
      if v_member.primary_section_node_id is not null then
        select
          case
            when gn.code ilike '%couple%' or gn.name ilike '%couple%'
                 or coalesce(gn.metadata->>'is_couple_section', 'false')::boolean = true
                 or coalesce(gn.metadata->>'section_category', '') = 'couples' then true
            else false
          end
        into v_section_is_couple
        from public.governance_nodes gn
        where gn.id = v_member.primary_section_node_id
          and gn.organization_id = p_organization_id;

        if v_section_is_couple is true then
          v_couples_context_status := 'couples';
          v_is_couple_context      := true;
          v_couples_context_source := 'primary_section';
        elsif v_section_is_couple is false then
          v_couples_context_status := 'non_couples';
          v_is_couple_context      := false;
          v_couples_context_source := 'primary_section';
        end if;
      end if;

      -- Priority B: member_governance_assignments identifying section membership
      if v_couples_context_status = 'ambiguous' then
        select
          case
            when gn.code ilike '%couple%' or gn.name ilike '%couple%'
                 or coalesce(gn.metadata->>'is_couple_section', 'false')::boolean = true
                 or coalesce(gn.metadata->>'section_category', '') = 'couples' then true
            else false
          end
        into v_section_is_couple
        from public.member_governance_assignments mga
        join public.governance_nodes gn on gn.id = mga.governance_node_id
        join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id
        where mga.member_id = p_member_id
          and mga.organization_id = p_organization_id
          and mga.assignment_status = 'active'
          and mga.effective_from <= current_date
          and (mga.effective_to is null or mga.effective_to >= current_date)
          and gnt.code = 'section'
        order by mga.is_primary desc, mga.effective_from desc
        limit 1;

        if v_section_is_couple is true then
          v_couples_context_status := 'couples';
          v_is_couple_context      := true;
          v_couples_context_source := 'member_governance_assignment';
        elsif v_section_is_couple is false then
          v_couples_context_status := 'non_couples';
          v_is_couple_context      := false;
          v_couples_context_source := 'member_governance_assignment';
        end if;
      end if;

      -- Priority C: current/pastoral household lineage that explicitly establishes Couples context
      if v_couples_context_status = 'ambiguous' then
        select h.is_couple_household
        into v_pastoral_lineage_is_couple
        from public.household_memberships hm
        join public.households h on h.id = hm.household_node_id
        where hm.member_id = p_member_id
          and hm.organization_id = p_organization_id
          and hm.is_primary = true
          and hm.membership_status in ('active', 'temporary')
          and hm.effective_from <= current_date
          and (hm.effective_to is null or hm.effective_to >= current_date)
        limit 1;

        if v_pastoral_lineage_is_couple is true then
          v_couples_context_status := 'couples';
          v_is_couple_context      := true;
          v_couples_context_source := 'pastoral_lineage';
        elsif v_pastoral_lineage_is_couple is false then
          v_couples_context_status := 'non_couples';
          v_is_couple_context      := false;
          v_couples_context_source := 'pastoral_lineage';
        end if;
      end if;

      -- Priority D: canonical section metadata on the governance node where the leader serves
      if v_couples_context_status = 'ambiguous' then
        if coalesce(v_gov_node.metadata->>'is_couple_section', 'false')::boolean = true
           or coalesce(v_gov_node.metadata->>'section_category', '') = 'couples'
           or v_gov_node.code ilike '%couple%' or v_gov_node.name ilike '%couple%' then
          v_couples_context_status := 'couples';
          v_is_couple_context      := true;
          v_couples_context_source := 'governance_node_metadata';
        end if;
      end if;

      -- If married with verified/unverified spouse but evidence is missing or contradictory:
      -- Remain AMBIGUOUS. Do NOT default to non-Couples.
      if v_couples_context_status = 'ambiguous' then
        v_is_couple_context      := null;
        v_couples_context_source := 'unresolved';
      end if;
    end if;
  end if;

  -- 8. Check Current Primary Household of Member
  select
    hm.household_node_id,
    gn.name,
    h.pastoral_level,
    gnr.parent_node_id
  into
    v_current_hh_id,
    v_current_hh_name,
    v_current_pastoral_level,
    v_current_hh_parent_id
  from public.household_memberships hm
  join public.governance_nodes gn on gn.id = hm.household_node_id
  join public.households h on h.id = hm.household_node_id
  left join public.governance_node_relationships gnr
    on gnr.child_node_id = gn.id
   and gnr.organization_id = p_organization_id
   and gnr.relationship_type = 'primary_parent'
   and gnr.relationship_status = 'active'
   and gnr.effective_from <= current_date
   and (gnr.effective_to is null or gnr.effective_to >= current_date)
  where hm.member_id = p_member_id
    and hm.organization_id = p_organization_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= current_date
    and (hm.effective_to is null or hm.effective_to >= current_date)
  limit 1;

  -- 9. Count matching active households available at the recommended level and scope
  if v_recommended_node_id is not null then
    select count(*)
    into v_matching_hh_count
    from public.households h
    join public.governance_nodes gn on gn.id = h.id
    join public.governance_node_relationships gnr
      on gnr.child_node_id = h.id
     and gnr.organization_id = h.organization_id
     and gnr.relationship_type = 'primary_parent'
     and gnr.relationship_status = 'active'
     and gnr.effective_from <= current_date
     and (gnr.effective_to is null or gnr.effective_to >= current_date)
    where h.organization_id = p_organization_id
      and h.pastoral_level = v_recommended_level
      and gn.lifecycle_status = 'active'
      and (
        (v_recommended_level != 'fraternal' and gnr.parent_node_id = v_recommended_node_id)
        or (v_recommended_level = 'fraternal' and coalesce(gnr.parent_node_id, gn.id) = v_recommended_node_id)
      );
  else
    v_matching_hh_count := 0;
  end if;

  -- 10. Determine Placement Status with Strict Precedence
  -- Precedence:
  --   1. Couples context ambiguous -> 'manual_review_required'
  --   2. Required Couples context but spouse unresolved or unverified -> 'manual_review_required'
  --   3. No matching higher-level household in required scope -> 'no_matching_household_available'
  --   4. Matching household exists but member has no current primary household -> 'missing_household'
  --   5. Current primary household exists but pastoral level OR governance scope is wrong -> 'different_level'
  --   6. Current primary household has expected pastoral level AND expected governance scope -> 'correct'
  if v_couples_context_status = 'ambiguous' then
    v_placement_status := 'manual_review_required';
  elsif v_couples_context_status = 'couples' and (not v_has_any_spouse or not v_spouse_verified) then
    v_placement_status := 'manual_review_required';
  elsif v_matching_hh_count = 0 then
    v_placement_status := 'no_matching_household_available';
  elsif v_current_hh_id is null then
    v_placement_status := 'missing_household';
  elsif v_current_pastoral_level = v_recommended_level
        and (
          (v_recommended_level != 'fraternal' and v_current_hh_parent_id = v_recommended_node_id)
          or (v_recommended_level = 'fraternal' and coalesce(v_current_hh_parent_id, v_current_hh_id) = v_recommended_node_id)
        ) then
    v_placement_status := 'correct';
  else
    v_placement_status := 'different_level';
  end if;

  -- Return comprehensive read-only guidance
  return jsonb_build_object(
    'member_id',                     p_member_id,
    'member_name',                   v_member.display_name,
    'has_formal_role',               true,
    'leadership_assignment_id',      v_assignment.id,
    'role_code',                     v_role_def.code,
    'role_name',                     v_role_def.name,
    'governance_node_id',            v_gov_node.id,
    'governance_node_name',          v_gov_node.name,
    'current_primary_household_id',  v_current_hh_id,
    'current_primary_household_name',v_current_hh_name,
    'current_pastoral_level',        v_current_pastoral_level,
    'current_household_parent_id',   v_current_hh_parent_id,
    'recommended_pastoral_level',    v_recommended_level,
    'recommended_scope_node_id',     v_recommended_node_id,
    'recommended_scope_node_name',   v_recommended_node_name,
    'matching_echelon_households_count', v_matching_hh_count,
    'placement_status',              v_placement_status,
    'is_couple_context',             v_is_couple_context,
    'couples_context_status',        v_couples_context_status,
    'couples_context_source',        v_couples_context_source,
    'spouse_context', jsonb_build_object(
      'has_spouse',                  v_has_any_spouse,
      'has_verified_spouse',         v_spouse_verified,
      'spouse_member_id',            v_spouse_id,
      'spouse_name',                 v_spouse_name,
      'evaluation_rule',             'In Couples section, formal servant leader husband and verified wife receive pastoral nourishment together in higher echelon household'
    )
  );
end;
$$;

comment on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) is
  'Read-only RPC returning authoritative pastoral placement recommendation based on formal leadership office and three-state couples context. Zero mutations.';

revoke execute on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) from public, anon;
grant  execute on function public.get_servant_leader_pastoral_placement_guidance(uuid, uuid, uuid) to authenticated, service_role;


-- =============================================================================
-- SECTION 2: Redefine public.get_pastoral_placement_review
-- =============================================================================

create or replace function public.get_pastoral_placement_review(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id                  uuid;
  v_assignment                  public.leadership_assignments%rowtype;
  v_role_def                    public.leadership_role_definitions%rowtype;
  v_gov_node                    public.governance_nodes%rowtype;
  v_leader_member               public.members%rowtype;
  v_recommended_level           text;
  v_recommended_scope_node_id   uuid;
  v_recommended_scope_node_name text;
  v_current_hh_id               uuid;
  v_current_hh_name             text;
  v_current_hh_level            text;
  v_current_hh_scope_node_id    uuid;
  v_guidance                    jsonb;
  v_placement_status            text;
  v_workflow_status             text;
  v_recommended_action          text;
  v_couples_context_status      text;
  v_couples_context_source      text;
  v_is_couple_context           boolean;
  v_has_spouse                  boolean := false;
  v_has_verified_spouse         boolean := false;
  v_spouse_id                   uuid;
  v_spouse_name                 text;
  v_spouse_current_hh_id        uuid;
  v_spouse_current_hh_name      text;
  v_spouse_current_hh_level     text;
  v_spouse_current_hh_scope_id  uuid;
  v_spouse_placement_status     text;
  v_available_destinations      jsonb := '[]'::jsonb;
  v_required_seats              integer := 1;
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
    raise exception using errcode = '42501', message = 'You do not have permission to review pastoral placements.';
  end if;

  -- 4. Load leadership assignment
  select *
  into v_assignment
  from public.leadership_assignments la
  where la.id = p_leadership_assignment_id
    and la.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership assignment not found or not accessible.';
  end if;

  -- 5. Scope check on formal governance node
  if not private.can_access_governance_node('leadership.pastoral_placement.review', p_organization_id, v_assignment.governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Formal governance node not accessible.';
  end if;

  -- 6. Scope check on leader member
  if not (
    private.can_access_member('leadership.pastoral_placement.review', p_organization_id, v_assignment.member_id)
    or private.can_access_member('members.households.view', p_organization_id, v_assignment.member_id)
    or private.can_access_member('members.records.view', p_organization_id, v_assignment.member_id)
  ) then
    raise exception using errcode = 'P0002', message = 'Leader member record not accessible.';
  end if;

  select * into v_leader_member from public.members where id = v_assignment.member_id and organization_id = p_organization_id;
  select * into v_role_def from public.leadership_role_definitions where id = v_assignment.leadership_role_definition_id;
  select * into v_gov_node from public.governance_nodes where id = v_assignment.governance_node_id;

  -- 7. Call placement guidance helper to obtain three-state guidance
  v_guidance := public.get_servant_leader_pastoral_placement_guidance(
    p_organization_id          => p_organization_id,
    p_member_id                => v_assignment.member_id,
    p_leadership_assignment_id => v_assignment.id
  );

  v_recommended_level           := v_guidance->>'recommended_pastoral_level';
  v_recommended_scope_node_id   := (v_guidance->>'recommended_scope_node_id')::uuid;
  v_recommended_scope_node_name := v_guidance->>'recommended_scope_node_name';
  v_current_hh_id               := (v_guidance->>'current_primary_household_id')::uuid;
  v_current_hh_name             := v_guidance->>'current_primary_household_name';
  v_current_hh_level            := v_guidance->>'current_pastoral_level';
  v_current_hh_scope_node_id    := (v_guidance->>'current_household_parent_id')::uuid;
  v_placement_status            := v_guidance->>'placement_status';

  v_couples_context_status      := coalesce(v_guidance->>'couples_context_status', 'ambiguous');
  v_couples_context_source      := coalesce(v_guidance->>'couples_context_source', 'unresolved');
  if v_guidance ? 'is_couple_context' and v_guidance->>'is_couple_context' is not null then
    v_is_couple_context := (v_guidance->>'is_couple_context')::boolean;
  else
    v_is_couple_context := null;
  end if;

  v_has_spouse                  := coalesce((v_guidance->'spouse_context'->>'has_spouse')::boolean, false);
  v_has_verified_spouse         := coalesce((v_guidance->'spouse_context'->>'has_verified_spouse')::boolean, false);
  v_spouse_id                   := (v_guidance->'spouse_context'->>'spouse_member_id')::uuid;
  v_spouse_name                 := v_guidance->'spouse_context'->>'spouse_name';

  -- 8. If spouse exists, evaluate spouse's current primary household
  if v_spouse_id is not null then
    select
      hm.household_node_id,
      gn.name,
      h.pastoral_level,
      gnr.parent_node_id
    into
      v_spouse_current_hh_id,
      v_spouse_current_hh_name,
      v_spouse_current_hh_level,
      v_spouse_current_hh_scope_id
    from public.household_memberships hm
    join public.governance_nodes gn on gn.id = hm.household_node_id
    join public.households h on h.id = hm.household_node_id
    left join public.governance_node_relationships gnr
      on gnr.child_node_id = gn.id
     and gnr.organization_id = p_organization_id
     and gnr.relationship_type = 'primary_parent'
     and gnr.relationship_status = 'active'
     and gnr.effective_from <= current_date
     and (gnr.effective_to is null or gnr.effective_to >= current_date)
    where hm.member_id = v_spouse_id
      and hm.organization_id = p_organization_id
      and hm.is_primary = true
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    limit 1;

    if v_spouse_current_hh_id is null then
      v_spouse_placement_status := 'missing_household';
    elsif v_spouse_current_hh_level = v_recommended_level
          and (
            (v_recommended_level != 'fraternal' and v_spouse_current_hh_scope_id = v_recommended_scope_node_id)
            or (v_recommended_level = 'fraternal' and coalesce(v_spouse_current_hh_scope_id, v_spouse_current_hh_id) = v_recommended_scope_node_id)
          ) then
      v_spouse_placement_status := 'correct';
    else
      v_spouse_placement_status := 'different_level';
    end if;
  else
    v_spouse_placement_status := null;
  end if;

  -- 9. Determine Required Seats for Capacity
  if v_couples_context_status = 'couples' and v_has_verified_spouse then
    v_required_seats := 2;
  else
    v_required_seats := 1;
  end if;

  -- 10. Query Available Destination Households
  -- For ambiguous context or when scope/level is null, destinations are empty or non-executable
  if v_couples_context_status != 'ambiguous' and v_recommended_scope_node_id is not null and v_recommended_level is not null then
    select jsonb_agg(
      jsonb_build_object(
        'household_id',         dest.household_id,
        'household_name',       dest.household_name,
        'pastoral_level',       dest.pastoral_level,
        'scope_node_id',        dest.scope_node_id,
        'scope_node_name',      dest.scope_node_name,
        'is_couple_household',  dest.is_couple_household,
        'current_member_count', dest.current_count,
        'target_member_count',  dest.target_member_count,
        'maximum_member_count', dest.maximum_member_count,
        'accepts_new_members',  dest.accepts_new_members,
        'capacity_status',      dest.capacity_status,
        'is_eligible',          dest.is_eligible
      ) order by dest.household_name
    )
    into v_available_destinations
    from (
      select
        h.id as household_id,
        gn.name as household_name,
        h.pastoral_level,
        coalesce(gnr.parent_node_id, gn.id) as scope_node_id,
        v_recommended_scope_node_name as scope_node_name,
        h.is_couple_household,
        count(hm.id) filter (where hm.is_primary and hm.membership_status in ('active', 'temporary') and (hm.effective_to is null or hm.effective_to >= current_date)) as current_count,
        h.target_member_count,
        h.maximum_member_count,
        h.accepts_new_members,
        case
          when not h.accepts_new_members then 'not_accepting'
          when h.maximum_member_count is not null and (
            count(hm.id) filter (where hm.is_primary and hm.membership_status in ('active', 'temporary') and (hm.effective_to is null or hm.effective_to >= current_date)) + v_required_seats
          ) > h.maximum_member_count then 'full'
          when h.target_member_count is not null and (
            count(hm.id) filter (where hm.is_primary and hm.membership_status in ('active', 'temporary') and (hm.effective_to is null or hm.effective_to >= current_date))
          ) >= h.target_member_count then 'at_target'
          else 'available'
        end as capacity_status,
        case
          when not h.accepts_new_members then false
          when h.maximum_member_count is not null and (
            count(hm.id) filter (where hm.is_primary and hm.membership_status in ('active', 'temporary') and (hm.effective_to is null or hm.effective_to >= current_date)) + v_required_seats
          ) > h.maximum_member_count then false
          else true
        end as is_eligible
      from public.households h
      join public.governance_nodes gn on gn.id = h.id and gn.organization_id = p_organization_id
      left join public.governance_node_relationships gnr
        on gnr.child_node_id = gn.id
       and gnr.organization_id = p_organization_id
       and gnr.relationship_type = 'primary_parent'
       and gnr.relationship_status = 'active'
       and gnr.effective_from <= current_date
       and (gnr.effective_to is null or gnr.effective_to >= current_date)
      left join public.household_memberships hm
        on hm.household_node_id = h.id
       and hm.organization_id = p_organization_id
      where h.organization_id = p_organization_id
        and gn.lifecycle_status = 'active'
        and h.pastoral_level = v_recommended_level
        and (
          (v_recommended_level != 'fraternal' and gnr.parent_node_id = v_recommended_scope_node_id)
          or (v_recommended_level = 'fraternal' and gn.id = h.id and coalesce(gnr.parent_node_id, gn.id) = v_recommended_scope_node_id)
        )
        and (
          (v_couples_context_status = 'couples' and coalesce(h.is_couple_household, false) = true)
          or (v_couples_context_status = 'non_couples')
        )
      group by h.id, gn.name, h.pastoral_level, gnr.parent_node_id, gn.id, h.is_couple_household, h.target_member_count, h.maximum_member_count, h.accepts_new_members
    ) dest;
  end if;

  v_available_destinations := coalesce(v_available_destinations, '[]'::jsonb);

  -- 11. Derive Workflow Status & Recommended Action
  if v_couples_context_status = 'ambiguous' then
    v_workflow_status    := 'manual_review_required';
    v_recommended_action := 'review_spouse';
  elsif v_couples_context_status = 'couples' and (not v_has_spouse or not v_has_verified_spouse) then
    v_workflow_status    := 'blocked_spouse_review';
    v_recommended_action := 'review_spouse';
  elsif v_placement_status = 'correct' and (v_couples_context_status != 'couples' or v_spouse_placement_status = 'correct') then
    v_workflow_status    := 'already_correct';
    v_recommended_action := 'none';
  elsif jsonb_array_length(v_available_destinations) = 0 then
    v_workflow_status    := 'blocked_no_destination';
    v_recommended_action := 'create_destination_household';
  elsif v_current_hh_id is null and (v_couples_context_status != 'couples' or v_spouse_current_hh_id is null) then
    v_workflow_status    := 'ready_to_assign';
    v_recommended_action := 'assign';
  else
    v_workflow_status    := 'ready_to_transfer';
    v_recommended_action := 'transfer';
  end if;

  return jsonb_build_object(
    'leadership_assignment_id',         v_assignment.id,
    'formal_role_code',                 v_role_def.code,
    'formal_role_name',                 v_role_def.name,
    'leader_member_id',                 v_leader_member.id,
    'leader_member_name',               v_leader_member.display_name,
    'formal_governance_node_id',        v_gov_node.id,
    'formal_governance_node_name',      v_gov_node.name,
    'recommended_pastoral_level',       v_recommended_level,
    'recommended_scope_node_id',        v_recommended_scope_node_id,
    'recommended_scope_node_name',      v_recommended_scope_node_name,
    'current_primary_household_id',     v_current_hh_id,
    'current_primary_household_name',   v_current_hh_name,
    'current_primary_pastoral_level',   v_current_hh_level,
    'current_primary_scope_node_id',    v_current_hh_scope_node_id,
    'placement_status',                 v_placement_status,
    'workflow_status',                  v_workflow_status,
    'recommended_action',               v_recommended_action,
    'required_seats',                   v_required_seats,
    'couples_context',                  v_is_couple_context,
    'couples_context_status',           v_couples_context_status,
    'couples_context_source',           v_couples_context_source,
    'spouse_context', jsonb_build_object(
      'has_spouse',                     v_has_spouse,
      'has_verified_spouse',            v_has_verified_spouse,
      'spouse_member_id',               v_spouse_id,
      'spouse_name',                    v_spouse_name
    ),
    'spouse_current_primary_household', jsonb_build_object(
      'household_id',                   v_spouse_current_hh_id,
      'household_name',                 v_spouse_current_hh_name,
      'pastoral_level',                 v_spouse_current_hh_level,
      'scope_node_id',                  v_spouse_current_hh_scope_id
    ),
    'spouse_placement_status',          v_spouse_placement_status,
    'available_destination_households', v_available_destinations
  );
end;
$$;

revoke execute on function public.get_pastoral_placement_review(uuid, uuid) from public, anon;
grant  execute on function public.get_pastoral_placement_review(uuid, uuid) to authenticated, service_role;


-- =============================================================================
-- SECTION 3: Redefine public.execute_pastoral_placement
-- =============================================================================

create or replace function public.execute_pastoral_placement(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid,
  p_destination_household_id uuid,
  p_effective_date           date default current_date,
  p_reason                   text default null,
  p_include_verified_spouse  boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id             uuid;
  v_reason                 text;
  v_effective_date         date;
  v_assignment             public.leadership_assignments%rowtype;
  v_role_def               public.leadership_role_definitions%rowtype;
  v_gov_node               public.governance_nodes%rowtype;
  v_leader_member          public.members%rowtype;
  v_dest_node              public.governance_nodes%rowtype;
  v_dest_household         public.households%rowtype;
  v_dest_parent_id         uuid;
  v_guidance               jsonb;
  v_recommended_level      text;
  v_recommended_scope_id   uuid;
  v_couples_context_status text;
  v_couples_context_source text;
  v_is_couple_context      boolean;
  v_has_verified_spouse    boolean := false;
  v_spouse_id              uuid;
  v_spouse_member          public.members%rowtype;
  v_current_dest_members   integer;
  v_required_seats         integer := 1;
  v_leader_current_hh_id   uuid;
  v_spouse_current_hh_id   uuid;
  v_leader_res             jsonb;
  v_spouse_res             jsonb;
  v_first_lock_id          uuid;
  v_second_lock_id         uuid;
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
  if not private.has_permission('leadership.pastoral_placement.execute', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to execute pastoral placements.';
  end if;

  -- 4. Reason validation
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = '23502', message = 'Placement reason is required.';
  end if;

  -- 5. Temporal rule: p_effective_date must be <= current_date (strictly current_date for execution safety)
  v_effective_date := coalesce(p_effective_date, current_date);
  if v_effective_date > current_date then
    raise exception using errcode = '22023', message = 'Future pastoral placement dates are not supported.';
  end if;

  -- 6. Lock leadership assignment FOR SHARE
  select *
  into v_assignment
  from public.leadership_assignments la
  where la.id = p_leadership_assignment_id
    and la.organization_id = p_organization_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership assignment not found.';
  end if;

  if v_assignment.assignment_status != 'active' then
    raise exception using errcode = '22023', message = 'Cannot place a leader whose assignment is not active.';
  end if;

  select * into v_role_def from public.leadership_role_definitions where id = v_assignment.leadership_role_definition_id;
  select * into v_gov_node from public.governance_nodes where id = v_assignment.governance_node_id;

  -- 7. Scope check on formal governance node
  if not private.can_access_governance_node('leadership.pastoral_placement.execute', p_organization_id, v_assignment.governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Formal governance node not accessible.';
  end if;

  -- 8. Scope check on leader member
  if not private.can_access_member('leadership.pastoral_placement.execute', p_organization_id, v_assignment.member_id) then
    raise exception using errcode = 'P0002', message = 'Leader member record not accessible.';
  end if;

  -- 9. Recompute Guidance at mutation time
  v_guidance := public.get_servant_leader_pastoral_placement_guidance(
    p_organization_id          => p_organization_id,
    p_member_id                => v_assignment.member_id,
    p_leadership_assignment_id => v_assignment.id
  );

  v_recommended_level      := v_guidance->>'recommended_pastoral_level';
  v_recommended_scope_id   := (v_guidance->>'recommended_scope_node_id')::uuid;
  v_couples_context_status := coalesce(v_guidance->>'couples_context_status', 'ambiguous');
  v_couples_context_source := coalesce(v_guidance->>'couples_context_source', 'unresolved');
  if v_guidance ? 'is_couple_context' and v_guidance->>'is_couple_context' is not null then
    v_is_couple_context := (v_guidance->>'is_couple_context')::boolean;
  else
    v_is_couple_context := null;
  end if;
  v_has_verified_spouse    := coalesce((v_guidance->'spouse_context'->>'has_verified_spouse')::boolean, false);
  v_spouse_id              := (v_guidance->'spouse_context'->>'spouse_member_id')::uuid;

  -- Execution Guard: If Couples context is ambiguous, reject immediately
  -- p_include_verified_spouse = false does NOT bypass an ambiguous context.
  if v_couples_context_status = 'ambiguous' then
    raise exception using errcode = '22023',
      message = 'Pastoral placement requires review because Couples ministry context cannot be determined authoritatively.';
  end if;

  -- If Couples context is authoritative and spouse is included, validate spouse access
  if v_couples_context_status = 'couples' and p_include_verified_spouse then
    if not v_has_verified_spouse or v_spouse_id is null then
      raise exception using errcode = '22023',
        message = 'Cannot place leader in Couples context without a verified spouse record. Spouse review required.';
    end if;

    if not private.can_access_member('leadership.pastoral_placement.execute', p_organization_id, v_spouse_id) then
      raise exception using errcode = 'P0002', message = 'Spouse member record not accessible.';
    end if;
  end if;

  -- 10. Scope check on destination household
  if not private.can_access_household('leadership.pastoral_placement.execute', p_organization_id, p_destination_household_id) then
    raise exception using errcode = 'P0002', message = 'Destination household not found or not accessible.';
  end if;

  -- 11. Lock Destination Household and Node FOR UPDATE
  select *
  into v_dest_node
  from public.governance_nodes
  where id = p_destination_household_id
    and organization_id = p_organization_id
  for update;

  if not found or v_dest_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Destination household is not active or accessible.';
  end if;

  select *
  into v_dest_household
  from public.households
  where id = p_destination_household_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'Destination household detail not found.';
  end if;

  -- Verify destination matches recommended pastoral level
  if v_dest_household.pastoral_level != v_recommended_level then
    raise exception using errcode = '22023',
      message = 'Destination pastoral level (' || v_dest_household.pastoral_level || ') does not match recommended level (' || v_recommended_level || ').';
  end if;

  -- Resolve destination parent scope node
  select gnr.parent_node_id
  into v_dest_parent_id
  from public.governance_node_relationships gnr
  where gnr.child_node_id = p_destination_household_id
    and gnr.organization_id = p_organization_id
    and gnr.relationship_type = 'primary_parent'
    and gnr.relationship_status = 'active'
    and gnr.effective_from <= v_effective_date
    and (gnr.effective_to is null or gnr.effective_to >= v_effective_date)
  limit 1;

  if v_recommended_level != 'fraternal' and v_dest_parent_id != v_recommended_scope_id then
    raise exception using errcode = '22023',
      message = 'Destination household belongs to a different governance scope than recommended.';
  elsif v_recommended_level = 'fraternal' and coalesce(v_dest_parent_id, v_dest_node.id) != v_recommended_scope_id then
    raise exception using errcode = '22023',
      message = 'Destination fraternal household belongs to a different Area scope than recommended.';
  end if;

  -- Couples compatibility on destination
  if v_couples_context_status = 'couples' and coalesce(v_dest_household.is_couple_household, false) = false then
    raise exception using errcode = '22023',
      message = 'Destination household is not configured as a Couple household.';
  end if;

  -- 12. Deterministic Member Locking
  if v_couples_context_status = 'couples' and p_include_verified_spouse and v_spouse_id is not null then
    v_first_lock_id  := least(v_assignment.member_id, v_spouse_id);
    v_second_lock_id := greatest(v_assignment.member_id, v_spouse_id);

    perform 1 from public.members where id = v_first_lock_id and organization_id = p_organization_id for update;
    perform 1 from public.members where id = v_second_lock_id and organization_id = p_organization_id for update;
  else
    perform 1 from public.members where id = v_assignment.member_id and organization_id = p_organization_id for update;
  end if;

  select * into v_leader_member from public.members where id = v_assignment.member_id;
  if v_spouse_id is not null then
    select * into v_spouse_member from public.members where id = v_spouse_id;
  end if;

  -- 13. Revalidate Destination Capacity After Locks
  select count(hm.id)
  into v_current_dest_members
  from public.household_memberships hm
  where hm.household_node_id = p_destination_household_id
    and hm.organization_id = p_organization_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= v_effective_date);

  -- Determine seats needed (do not double-count if already in destination)
  v_required_seats := 0;

  select hm.household_node_id into v_leader_current_hh_id
  from public.household_memberships hm
  where hm.member_id = v_assignment.member_id
    and hm.organization_id = p_organization_id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= v_effective_date);

  if v_leader_current_hh_id is distinct from p_destination_household_id then
    v_required_seats := v_required_seats + 1;
  end if;

  if v_couples_context_status = 'couples' and p_include_verified_spouse and v_spouse_id is not null then
    select hm.household_node_id into v_spouse_current_hh_id
    from public.household_memberships hm
    where hm.member_id = v_spouse_id
      and hm.organization_id = p_organization_id
      and hm.is_primary = true
      and hm.membership_status in ('active', 'temporary')
      and (hm.effective_to is null or hm.effective_to >= v_effective_date);

    if v_spouse_current_hh_id is distinct from p_destination_household_id then
      v_required_seats := v_required_seats + 1;
    end if;
  end if;

  -- Capacity check
  if v_required_seats > 0 then
    if not v_dest_household.accepts_new_members then
      raise exception using errcode = '22023', message = 'Destination household does not accept new members.';
    end if;

    if v_dest_household.maximum_member_count is not null
       and (v_current_dest_members + v_required_seats) > v_dest_household.maximum_member_count then
      raise exception using errcode = '22023',
        message = 'Destination household capacity exceeded (current: ' || v_current_dest_members || ', max: ' || v_dest_household.maximum_member_count || ', required seats: ' || v_required_seats || ').';
    end if;
  end if;

  -- 14. Execute Atomic Placement Mutations
  -- A. Leader Placement
  v_leader_res := private.mutate_household_member_placement(
    p_organization_id          => p_organization_id,
    p_member_id                => v_assignment.member_id,
    p_destination_household_id => p_destination_household_id,
    p_effective_date           => v_effective_date,
    p_reason                   => v_reason,
    p_actor_profile_id         => v_profile_id
  );

  -- B. Spouse Placement (if Couples context)
  if v_couples_context_status = 'couples' and p_include_verified_spouse and v_spouse_id is not null then
    v_spouse_res := private.mutate_household_member_placement(
      p_organization_id          => p_organization_id,
      p_member_id                => v_spouse_id,
      p_destination_household_id => p_destination_household_id,
      p_effective_date           => v_effective_date,
      p_reason                   => 'Couples Placement: ' || v_reason,
      p_actor_profile_id         => v_profile_id
    );
  else
    v_spouse_res := null;
  end if;

  -- 15. Record Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'pastoral_placement.executed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'pastoral_placement',
    p_outcome          => 'success',
    p_access_reason    => v_reason,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'leadership_assignment_id',     v_assignment.id,
      'formal_role_code',             v_role_def.code,
      'leader_member_id',             v_assignment.member_id,
      'leader_action',                v_leader_res->>'action',
      'leader_previous_household_id', v_leader_res->>'source_household_id',
      'spouse_member_id',             v_spouse_id,
      'spouse_action',                v_spouse_res->>'action',
      'spouse_previous_household_id', v_spouse_res->>'source_household_id',
      'destination_household_id',     p_destination_household_id,
      'destination_household_name',   v_dest_node.name,
      'effective_date',               v_effective_date,
      'couples_context',              v_is_couple_context,
      'couples_context_status',       v_couples_context_status,
      'couples_context_source',       v_couples_context_source,
      'reason',                       v_reason
    )
  );

  -- 16. Return Structured Execution Result
  return jsonb_build_object(
    'status',                       'completed',
    'leadership_assignment_id',     v_assignment.id,
    'formal_role_code',             v_role_def.code,
    'destination_household_id',     p_destination_household_id,
    'destination_household_name',   v_dest_node.name,
    'effective_date',               v_effective_date,
    'couples_placement',            (v_couples_context_status = 'couples') and (v_spouse_res is not null),
    'leader_result',                v_leader_res,
    'spouse_result',                v_spouse_res,
    'message',                      'Pastoral placement executed successfully.'
  );
end;
$$;

revoke execute on function public.execute_pastoral_placement(uuid, uuid, uuid, date, text, boolean) from public, anon;
grant  execute on function public.execute_pastoral_placement(uuid, uuid, uuid, date, text, boolean) to authenticated, service_role;


-- =============================================================================
-- SECTION 4: Redefine public.search_servant_leaders_needing_pastoral_placement
-- =============================================================================

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
        c.leader_name
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

revoke execute on function public.search_servant_leaders_needing_pastoral_placement(uuid, boolean, integer, integer) from public, anon;
grant  execute on function public.search_servant_leaders_needing_pastoral_placement(uuid, boolean, integer, integer) to authenticated, service_role;

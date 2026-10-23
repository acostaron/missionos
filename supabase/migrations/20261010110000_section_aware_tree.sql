-- =============================================================================
-- Migration: 20261010110000_section_aware_tree.sql
-- MissionOS Pass 9.38A (written by Claude, 2026-10-22) — run after 20261010109000.
-- Ron (2026-10-22) wants chapters to sit under their Section (the Couples chapters will move under Couples in 9.38B;
-- Handmaids chapters already sit under Handmaids; a new Singles chapter will sit under Singles). Three places assumed
-- a chapter's parent is the sub-area:
--   * get_servant_leader_pastoral_placement_guidance: the upper household of a servant leader is now found the same
--     way as in search_servant_leaders_needing_pastoral_placement (Pass 9.21): walk up from the office, skip sections,
--     nearest node with a household of the recommended level directly under it (else the first non-section node).
--     (get_pastoral_placement_review / execute_pastoral_placement use it, so they agree with the search again.)
--   * build_member_self_context (My Profile / My Card): the member's own section first, then the tree.
--   * get_pastoral_operations_dashboard: households at any depth below the chosen node.
-- Guarded: each replaced function must still be its last migration's version.
-- =============================================================================
do $guard$
declare
  r record;
  v_md5 text;
begin
  for r in select * from (values
    ('public', 'get_servant_leader_pastoral_placement_guidance', 'b8ecde6a742d81c2864461b1129e7cb8'),
    ('private', 'build_member_self_context', 'cc14425a0867b357841d42b465161c1d'),
    ('public', 'get_pastoral_operations_dashboard', '004df923d5e496939bcbbf8045e49720')
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

create or replace function private.leader_upper_scope_node(p_organization_id uuid, p_office_node_id uuid, p_level text)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with recursive up as (
    select p.id, pt.code as type_code, 0 as depth
    from public.governance_node_relationships r0
    join public.governance_nodes p on p.id = r0.parent_node_id
    join public.governance_node_types pt on pt.id = p.governance_node_type_id
    where r0.child_node_id = p_office_node_id
      and r0.organization_id = p_organization_id
      and r0.relationship_type = 'primary_parent'
      and r0.relationship_status = 'active'
      and r0.effective_from <= current_date
      and (r0.effective_to is null or r0.effective_to >= current_date)
    union all
    select gp.id, gpt.code, up.depth + 1
    from up
    join public.governance_node_relationships r
      on r.child_node_id = up.id
     and r.organization_id = p_organization_id
     and r.relationship_type = 'primary_parent'
     and r.relationship_status = 'active'
     and r.effective_from <= current_date
     and (r.effective_to is null or r.effective_to >= current_date)
    join public.governance_nodes gp on gp.id = r.parent_node_id
    join public.governance_node_types gpt on gpt.id = gp.governance_node_type_id
    where up.depth < 6
  )
  select up.id
  from up
  where up.type_code <> 'section'
  order by
    (exists (
      select 1
      from public.households xh
      join public.governance_nodes xg on xg.id = xh.id and xg.lifecycle_status = 'active'
      join public.governance_node_relationships xr
        on xr.child_node_id = xh.id
       and xr.relationship_type = 'primary_parent'
       and xr.relationship_status = 'active'
       and (xr.effective_to is null or xr.effective_to >= current_date)
      where xh.organization_id = p_organization_id
        and xr.parent_node_id = up.id
        and xh.pastoral_level = p_level
    )) desc,
    up.depth
  limit 1
$$;
revoke all on function private.leader_upper_scope_node(uuid, uuid, text) from public, anon, authenticated;

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

    v_recommended_node_id := private.leader_upper_scope_node(p_organization_id, v_gov_node.id, v_recommended_level);  -- Pass 9.38A

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

    v_recommended_node_id := private.leader_upper_scope_node(p_organization_id, v_gov_node.id, v_recommended_level);  -- Pass 9.38A

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

    v_recommended_node_id := private.leader_upper_scope_node(p_organization_id, v_gov_node.id, v_recommended_level);  -- Pass 9.38A

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

create or replace function private.build_member_self_context(p_organization_id uuid, p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member     record;
  v_household  jsonb := null;
  v_hh_node_id uuid;
  v_org_ctx    jsonb;
  v_status     text;
begin
  select m.id, m.member_number, m.display_name, m.primary_section_node_id, m.membership_status_id
  into v_member
  from public.members m
  where m.id = p_member_id and m.organization_id = p_organization_id;

  select ms.name into v_status
  from public.member_statuses ms
  where ms.id = v_member.membership_status_id;

  -- Current household (primary first, most recent first)
  select jsonb_build_object(
           'household_id',          gn.id,
           'household_name',        gn.name,
           'pastoral_level',        h.pastoral_level,
           'leader_display_name',   servant.display_name,
           'parent_node_name',      parent.name,
           'meeting_frequency',     h.meeting_frequency,
           'meeting_day_of_week',   h.meeting_day_of_week,
           'meeting_start_time',    h.meeting_start_time,
           'meeting_timezone_name', h.meeting_timezone_name
         ),
         gn.id
  into v_household, v_hh_node_id
  from public.household_memberships hm
  join public.governance_nodes gn
    on gn.id = hm.household_node_id and gn.organization_id = hm.organization_id
  join public.households h
    on h.id = gn.id and h.organization_id = gn.organization_id
  left join lateral (
    select pgn.name
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id and pgn.organization_id = gnr.organization_id
    where gnr.child_node_id = gn.id
      and gnr.organization_id = gn.organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ) parent on true
  left join lateral (
    select m_lead.display_name
    from public.leadership_assignments la
    join public.members m_lead
      on m_lead.id = la.member_id and m_lead.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id and lrd.organization_id = la.organization_id
    where la.governance_node_id = gn.id
      and la.organization_id = gn.organization_id
      and la.assignment_status = 'active'
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'household_servant_leader'
    order by la.effective_from desc
    limit 1
  ) servant on true
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.membership_status = 'active'
    and (hm.effective_to is null or hm.effective_to >= current_date)
  order by hm.is_primary desc, hm.effective_from desc
  limit 1;

  -- Organizational ancestry: walk primary parents up from the household
  -- (or from the member's primary section node for the section level).
  with recursive up as (
    select gn.id, gn.name, gn.governance_node_type_id, 0 as depth
    from public.governance_nodes gn
    where gn.id = v_hh_node_id and gn.organization_id = p_organization_id
    union all
    select pgn.id, pgn.name, pgn.governance_node_type_id, up.depth + 1
    from up
    join public.governance_node_relationships gnr
      on gnr.child_node_id = up.id
     and gnr.organization_id = p_organization_id
     and gnr.relationship_type = 'primary_parent'
     and gnr.relationship_status = 'active'
     and (gnr.effective_to is null or gnr.effective_to >= current_date)
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id and pgn.organization_id = p_organization_id
    where up.depth < 10
  ),
  typed as (
    select u.name, t.code, u.depth
    from up u
    join public.governance_node_types t on t.id = u.governance_node_type_id
  )
  select jsonb_build_object(
    'area',    (select name from typed where code = 'area_state' order by depth limit 1),
    -- Pass 9.38A: the member's own section first (a Youth member in a household under a Couples chapter is Youth)
    'section', coalesce(
                 (select gn.name from public.governance_nodes gn
                  where gn.id = v_member.primary_section_node_id
                    and gn.organization_id = p_organization_id),
                 (select name from typed where code = 'section' order by depth limit 1)
               ),
    'chapter', (select name from typed where code = 'chapter' order by depth limit 1),
    'unit',    (select name from typed where code = 'unit' order by depth limit 1)
  )
  into v_org_ctx;

  return jsonb_build_object(
    'organization_id', p_organization_id,
    'profile', jsonb_build_object(
      'display_name', (select p.display_name from public.profiles p where p.id = private.current_profile_id())
    ),
    'member', jsonb_build_object(
      'member_id',         v_member.id,
      'member_number',     v_member.member_number,
      'display_name',      v_member.display_name,
      'membership_status', v_status
    ),
    'household', v_household,
    'organizational_context', coalesce(v_org_ctx, jsonb_build_object(
      'area', null, 'section', null, 'chapter', null, 'unit', null))
  );
end;
$$;

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
              'has_derived_spouse', (private.in_couples_section(p_organization_id, lm.id) and sp.id is not null),
              'derived_spouse_name', case when private.in_couples_section(p_organization_id, lm.id) then sp.display_name else null end,
              'derived_pastoral_title', case when private.in_couples_section(p_organization_id, lm.id) and sp.id is not null then 'Household Leaders' else 'Household Servant Leader' end
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
        -- Pass 9.38A: any depth below the chosen node (chapters may sit under a section)
        or private.node_is_within(p_rel.parent_node_id, v_target_scope_node_id)
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
        -- Pass 9.26 (Ron, 2026-10-21): Couples-section leaders show with their spouse; no Couple Household flag.
        when sh.pastoral_level = 'member' and private.in_couples_section(p_organization_id, lm_hh.id) then sp_hh.display_name
        when sh.pastoral_level in ('unit', 'chapter', 'area') and lrd_scope.code like '%coordinator%'
          then coalesce(cp_scope.display_name, sp_scope.display_name)
        -- Pass 9.23 (Ron, 2026-10-20): as on the household page (Pass 8.4H), a Unit/Chapter/Area servant leader
        -- who belongs to the Couples section leads with their verified spouse, even in a mixed household.
        when sh.pastoral_level in ('unit', 'chapter', 'area')
             and lrd_scope.code in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
             and (
               exists (
                 select 1
                 from public.governance_nodes sgn
                 where sgn.id = lm_scope.primary_section_node_id
                   and (sgn.code ilike '%couple%' or sgn.name ilike '%couple%'
                        or coalesce(sgn.metadata->>'is_couple_section', 'false')::boolean = true
                        or coalesce(sgn.metadata->>'section_category', '') = 'couples')
               )
               or exists (
                 select 1
                 from public.member_governance_assignments mga
                 join public.governance_nodes sgn on sgn.id = mga.governance_node_id
                 join public.governance_node_types gnt on gnt.id = sgn.governance_node_type_id and gnt.code = 'section'
                 where mga.member_id = lm_scope.id
                   and mga.organization_id = p_organization_id
                   and mga.assignment_status = 'active'
                   and mga.effective_from <= current_date
                   and (mga.effective_to is null or mga.effective_to >= current_date)
                   and (sgn.code ilike '%couple%' or sgn.name ilike '%couple%'
                        or coalesce(sgn.metadata->>'is_couple_section', 'false')::boolean = true
                        or coalesce(sgn.metadata->>'section_category', '') = 'couples')
               )
             )
          then sp_scope.display_name
        else null
      end as derived_spouse_name,
      -- Pass 9.27 (Ron, 2026-10-21): interim appointments are marked on the dashboard.
      coalesce(case when sh.pastoral_level = 'member' then la_hh.metadata->>'is_interim'
                    when sh.pastoral_level in ('unit', 'chapter', 'area') then la_scope.metadata->>'is_interim' end,
               'false') = 'true' as is_interim
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
     and (lrd_scope.code in ('unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
          or lrd_scope.code like '%coordinator%')  -- Pass 9.22: Coordinators lead their Area's household
    left join public.members lm_scope on lm_scope.id = la_scope.member_id
    left join public.members cp_scope
      on cp_scope.id = nullif(la_scope.metadata->>'couple_partner_member_id', '')::uuid
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
        when hl.derived_spouse_name is not null and hl.role_code like '%coordinator%' then
          hl.role_name || 's: ' || hl.leader_name || ' & ' || hl.derived_spouse_name
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
      end || case when hl.is_interim and hl.leader_name is not null then ' (Interim)' else '' end as leader_display_label,
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
      -- Pass 9.23A (Ron, 2026-10-20): MFC New York / FMC New York sit under New York Area. They are led by their
      -- Coordinators or overseen by the Area Servant Leader, never by an Area Servant Leader of their own.
      and not exists (
        select 1
        from public.governance_node_relationships pr
        join public.governance_nodes pn on pn.id = pr.parent_node_id
        join public.governance_node_types pnt on pnt.id = pn.governance_node_type_id and pnt.code = 'area_state'
        where pr.child_node_id = arn.id
          and pr.organization_id = p_organization_id
          and pr.relationship_type = 'primary_parent'
          and pr.relationship_status = 'active'
          and (pr.effective_to is null or pr.effective_to >= current_date)
      )
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

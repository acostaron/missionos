-- =============================================================================
-- Migration: 20261010094000_leader_household_review_and_verified_couples.sql
-- MissionOS Pass 9.21 (written by Claude, 2026-10-20) — run after 20261010093000.
-- Ron (2026-10-20): NY Area (Area Servant) -> MFC NY and FMC NY (their Coordinators) -> Chapters (Couples, Handmaids,
-- Singles, Campus, Youth; Chapter Servants) -> Units -> Households. Chapter Servants belong to the household led by
-- the level above them: MFC chapter servants are in the NY Area household (MFC NY has no Coordinator); FMC chapter
-- servants are in a household led by the FMC Coordinators. Ron decides each upper-household placement himself.
--   * search_servant_leaders_needing_pastoral_placement: skips section nodes and uses the nearest node above the
--     office that has a household of the recommended level; area households, like fraternal ones, may be mixed.
--   * appoint_servant_leader_with_spouse: appointing a couple records the marriage as administrator-verified.
-- Guarded: replaces each function only if it is unchanged from its last migration.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'appoint_servant_leader_with_spouse';
  if v_md5 is distinct from 'ceb7541de720c6578e3f6371a0fc6106' then
    raise exception 'STOP: public.appoint_servant_leader_with_spouse differs from 20261010092000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'search_servant_leaders_needing_pastoral_placement';
  if v_md5 is distinct from '42156182a6b96f8b41cbd7cc8f294c9b' then
    raise exception 'STOP: public.search_servant_leaders_needing_pastoral_placement differs from 20261010086000 (md5 %).', v_md5;
  end if;
end;
$guard$;

create or replace function public.appoint_servant_leader_with_spouse(
  p_organization_id    uuid,
  p_role_code          text,
  p_governance_node_id uuid,
  p_member_id          uuid,
  p_spouse_member_id   uuid default null,
  p_reason             text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor       uuid := private.current_profile_id();
  v_leader      public.members%rowtype;
  v_spouse      public.members%rowtype;
  v_cur_leader  uuid;
  v_cur_spouse  uuid;
  v_family      uuid;
  v_add         uuid;
  v_surname     text;
  v_res         jsonb;
  v_linked      text := 'none';
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if lower(coalesce(p_role_code, '')) not in ('area_servant_leader', 'chapter_servant_leader', 'unit_servant_leader') then
    raise exception using errcode = '22023', message = 'Use this for Area, Chapter or Unit Servant Leaders.';
  end if;
  if not private.has_permission('leadership.servant_leaders.appoint', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to appoint servant leaders.';
  end if;

  if p_spouse_member_id is not null then
    if p_spouse_member_id = p_member_id then
      raise exception using errcode = '22023', message = 'Choose two different people for husband and wife.';
    end if;
    select * into v_leader from public.members where id = p_member_id and organization_id = p_organization_id;
    select * into v_spouse from public.members where id = p_spouse_member_id and organization_id = p_organization_id;
    if v_leader.id is null or v_spouse.id is null then
      raise exception using errcode = 'P0002', message = 'Member not found.';
    end if;
    if v_leader.record_status <> 'active' or v_spouse.record_status <> 'active' then
      raise exception using errcode = '22023', message = 'Both spouses must be active members.';
    end if;

    v_cur_leader := private.active_spouse_of(p_organization_id, p_member_id);
    v_cur_spouse := private.active_spouse_of(p_organization_id, p_spouse_member_id);

    if v_cur_leader = p_spouse_member_id then
      v_linked := 'already_linked';
    elsif v_cur_leader is not null then
      raise exception using errcode = '22023',
        message = format('%s already has a different spouse on record. Correct the family record first.', v_leader.display_name);
    elsif v_cur_spouse is not null then
      raise exception using errcode = '22023',
        message = format('%s already has a different spouse on record. Correct the family record first.', v_spouse.display_name);
    else
      -- 1. a family both already belong to
      select fh.family_id into v_family
      from public.family_members fh
      join public.family_members fw on fw.family_id = fh.family_id and fw.member_id = p_spouse_member_id
       and fw.membership_status = 'active' and (fw.effective_to is null or fw.effective_to > current_date)
      join public.families f on f.id = fh.family_id and f.family_status = 'active'
      where fh.member_id = p_member_id and fh.organization_id = p_organization_id
        and fh.membership_status = 'active' and (fh.effective_to is null or fh.effective_to > current_date)
      limit 1;

      if v_family is null then
        -- 2. the leader's family (add the spouse) or 3. the spouse's family (add the leader)
        select fm.family_id into v_family
        from public.family_members fm join public.families f on f.id = fm.family_id and f.family_status = 'active'
        where fm.member_id = p_member_id and fm.organization_id = p_organization_id
          and fm.membership_status = 'active' and (fm.effective_to is null or fm.effective_to > current_date)
        order by fm.created_at limit 1;
        v_add := p_spouse_member_id;
        if v_family is null then
          select fm.family_id into v_family
          from public.family_members fm join public.families f on f.id = fm.family_id and f.family_status = 'active'
          where fm.member_id = p_spouse_member_id and fm.organization_id = p_organization_id
            and fm.membership_status = 'active' and (fm.effective_to is null or fm.effective_to > current_date)
          order by fm.created_at limit 1;
          v_add := p_member_id;
        end if;

        if v_family is null then
          -- 4. neither has a family record: create "<Surname> Family" and add both
          v_surname := nullif(btrim(split_part(v_leader.sort_name, ',', 1)), '');
          if v_surname is null then
            v_surname := v_leader.display_name;
          end if;
          v_res := public.create_family(p_organization_id, v_surname || ' Family', v_surname, 'married_couple', null, true);
          v_family := (v_res->>'family_id')::uuid;
          if v_family is null then
            raise exception using errcode = '22023', message = 'The family record could not be created.';
          end if;
          perform public.add_family_member(p_organization_id, v_family, p_member_id, 'spouse', true, false, current_date, true);
          perform public.add_family_member(p_organization_id, v_family, p_spouse_member_id, 'spouse', false, false, current_date, true);
          v_linked := 'family_created';
        else
          perform public.add_family_member(p_organization_id, v_family, v_add, 'spouse', false, false, current_date, true);
          v_linked := 'added_to_family';
        end if;
      else
        v_linked := 'same_family';
      end if;

      perform public.add_family_relationship(p_organization_id, v_family, p_member_id, p_spouse_member_id, 'spouse', current_date);
    end if;
  end if;

  -- Pass 9.21 (Ron, 2026-10-20): appointing a couple is the administrator's confirmation of the marriage.
  if p_spouse_member_id is not null then
    update public.family_relationships fr
       set verification_status    = 'administrator_verified',
           verified_at            = clock_timestamp(),
           verified_by_profile_id = v_actor,
           updated_at             = clock_timestamp(),
           updated_by_profile_id  = v_actor
      from public.family_relationship_types t
     where t.id = fr.relationship_type_id and t.code = 'spouse'
       and fr.organization_id = p_organization_id
       and fr.relationship_status = 'active'
       and (fr.effective_to is null or fr.effective_to >= current_date)
       and least(fr.from_member_id, fr.to_member_id) = least(p_member_id, p_spouse_member_id)
       and greatest(fr.from_member_id, fr.to_member_id) = greatest(p_member_id, p_spouse_member_id)
       and fr.verification_status not in ('member_confirmed', 'administrator_verified', 'document_verified');
  end if;

  v_res := public.appoint_servant_leader(p_organization_id, lower(p_role_code), p_governance_node_id, p_member_id,
                                         current_date, nullif(btrim(coalesce(p_reason, '')), ''));
  return v_res || jsonb_build_object('spouse_member_id', p_spouse_member_id, 'spouse_link', v_linked);
end;
$$;

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
        else parent_gn.id
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
    -- Pass 9.21 (Ron, 2026-10-20): the household one level up is found by walking up from the office: sections
    -- (e.g. Handmaids) are skipped, and the nearest node that actually has a household of the recommended level
    -- directly under it is used (MFC chapters -> NY Area household under New York Area, because MFC New York has no
    -- Coordinator; FMC chapters -> the FMC New York household led by the FMC Coordinators). With no such household,
    -- the first non-section node above the office is used, as before. The review only flags; it never moves anyone.
    left join lateral (
      with recursive up as (
        select p.id, p.name, pt.code as type_code, 0 as depth
        from public.governance_nodes p
        join public.governance_node_types pt on pt.id = p.governance_node_type_id
        where p.id = parent_rel.parent_node_id
        union all
        select gp.id, gp.name, gpt.code, up.depth + 1
        from up
        join public.governance_node_relationships r
          on r.child_node_id = up.id
         and r.organization_id = la.organization_id
         and r.relationship_type = 'primary_parent'
         and r.relationship_status = 'active'
         and r.effective_from <= current_date
         and (r.effective_to is null or r.effective_to >= current_date)
        join public.governance_nodes gp on gp.id = r.parent_node_id
        join public.governance_node_types gpt on gpt.id = gp.governance_node_type_id
        where up.depth < 6
      )
      select up.id, up.name
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
          where xh.organization_id = la.organization_id
            and xr.parent_node_id = up.id
            and xh.pastoral_level = case lrd.code
                                      when 'household_servant_leader' then 'unit'
                                      when 'unit_servant_leader'      then 'chapter'
                                      when 'chapter_servant_leader'   then 'area'
                                    end
        )) desc,
        up.depth
      limit 1
    ) parent_gn on true
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
              or (lc.couples_context_status = 'couples' and lc.recommended_level in ('fraternal', 'area'))  -- Pass 8.4G / 9.21: fraternal and area households may be mixed
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

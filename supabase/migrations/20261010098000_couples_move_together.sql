-- =============================================================================
-- Migration: 20261010098000_couples_move_together.sql
-- MissionOS Pass 9.26 (written by Claude, 2026-10-21) — run after 20261010097000.
-- Ron (2026-10-21): drop the "Couple Household" flag — any household may hold couples and singles. Wherever a
-- husband is placed (assign or transfer), his wife goes with him; when either spouse's household membership is
-- ended, the other spouse leaves that household too. A servant leader in the Couples section is shown with their
-- verified spouse as the household's leaders (Couples section only).
--   * new private.in_couples_section, private.move_wife_with_husband;
--   * assign_member_to_household / transfer_household_member / end_household_membership: the old single-person
--     versions move to private.*_one; the public ones call them and then move/end the spouse (all or nothing);
--   * placement review / review destinations / execute placement: no longer require a Couple household;
--   * get_household_profile and the dashboard: couple leaders by Couples section only (no Couple flag).
-- Guarded: changes nothing unless every function is unchanged from its last migration.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'assign_member_to_household';
  if v_md5 is distinct from '577c1d2bae91a5ef35c09c0a0ca80a18' then
    raise exception 'STOP: public.assign_member_to_household differs from 20261010049000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'transfer_household_member';
  if v_md5 is distinct from 'beed09d7e2d52ee875ff28f7c0351458' then
    raise exception 'STOP: public.transfer_household_member differs from 20261010049000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'end_household_membership';
  if v_md5 is distinct from '1fa4c66e04da410bc1dafbe240abbd84' then
    raise exception 'STOP: public.end_household_membership differs from 20260929140000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'search_servant_leaders_needing_pastoral_placement';
  if v_md5 is distinct from '560f0e5ad85c8e869a1fd7fc2925e8ff' then
    raise exception 'STOP: public.search_servant_leaders_needing_pastoral_placement differs from 20261010094000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_pastoral_placement_review';
  if v_md5 is distinct from '6e522504e1cdb33275ad329b86de6ef2' then
    raise exception 'STOP: public.get_pastoral_placement_review differs from 20261010072000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'execute_pastoral_placement';
  if v_md5 is distinct from 'ca5b6c50a73d734a99abfa79993aa736' then
    raise exception 'STOP: public.execute_pastoral_placement differs from 20261010072000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_household_profile'
    and pg_get_function_identity_arguments(p.oid) = 'p_organization_id uuid, p_household_id uuid';
  if v_md5 is distinct from 'efbbc4eacdb23e0241596bc0cb1cc836' then
    raise exception 'STOP: public.get_household_profile differs from 20261010095000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_pastoral_operations_dashboard';
  if v_md5 is distinct from '04904b03d42cb73059331ee1a8b85b96' then
    raise exception 'STOP: public.get_pastoral_operations_dashboard differs from 20261010097000 (md5 %).', v_md5;
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Helper: is the member in the Couples section (primary section or an active section assignment)?
-- -----------------------------------------------------------------------------
create or replace function private.in_couples_section(p_organization_id uuid, p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select exists (
           select 1
           from public.members m
           join public.governance_nodes s on s.id = m.primary_section_node_id
           where m.id = p_member_id and m.organization_id = p_organization_id
             and (s.code ilike '%couple%' or s.name ilike '%couple%'
            or coalesce(s.metadata->>'is_couple_section', 'false')::boolean = true
            or coalesce(s.metadata->>'section_category', '') = 'couples')
         )
      or exists (
           select 1
           from public.member_governance_assignments mga
           join public.governance_nodes s on s.id = mga.governance_node_id
           join public.governance_node_types st on st.id = s.governance_node_type_id and st.code = 'section'
           where mga.member_id = p_member_id and mga.organization_id = p_organization_id
             and mga.assignment_status = 'active'
             and mga.effective_from <= current_date
             and (mga.effective_to is null or mga.effective_to >= current_date)
             and (s.code ilike '%couple%' or s.name ilike '%couple%'
            or coalesce(s.metadata->>'is_couple_section', 'false')::boolean = true
            or coalesce(s.metadata->>'section_category', '') = 'couples')
         )
$$;
revoke all on function private.in_couples_section(uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- The single-person household operations move to private; the public ones below call them and then move the spouse.
-- -----------------------------------------------------------------------------
alter function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) rename to assign_member_to_household_one;
alter function public.assign_member_to_household_one(uuid, uuid, uuid, date, boolean) set schema private;
revoke all on function private.assign_member_to_household_one(uuid, uuid, uuid, date, boolean) from public, anon, authenticated;

alter function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) rename to transfer_household_member_one;
alter function public.transfer_household_member_one(uuid, uuid, uuid, date, text, boolean) set schema private;
revoke all on function private.transfer_household_member_one(uuid, uuid, uuid, date, text, boolean) from public, anon, authenticated;

alter function public.end_household_membership(uuid, uuid, date, text) rename to end_household_membership_one;
alter function public.end_household_membership_one(uuid, uuid, date, text) set schema private;
revoke all on function private.end_household_membership_one(uuid, uuid, date, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Ron (2026-10-21): wherever a husband is placed, his wife goes with him.
-- Husband = the member whose sex is 'male' and who has an active spouse link. The wife is assigned (no household
-- yet) or transferred (other household) to the same household on the same date. If she cannot be moved, nothing
-- is changed and the reason is returned as an error. Moving a wife on her own moves only her.
-- -----------------------------------------------------------------------------
create or replace function private.move_wife_with_husband(
  p_organization_id uuid,
  p_member_id       uuid,
  p_household_id    uuid,
  p_effective_date  date
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_sex  text;
  v_wife public.members%rowtype;
  v_cur  uuid;
  v_res  jsonb;
begin
  select sex into v_sex from public.members where id = p_member_id and organization_id = p_organization_id;
  if lower(coalesce(v_sex, '')) <> 'male' then
    return null;
  end if;
  select * into v_wife from public.members
   where id = private.active_spouse_of(p_organization_id, p_member_id) and organization_id = p_organization_id;
  if v_wife.id is null or v_wife.record_status <> 'active' or coalesce(v_wife.is_deceased, false) then
    return null;
  end if;

  select hm.household_node_id into v_cur
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.member_id = v_wife.id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= p_effective_date
    and (hm.effective_to is null or hm.effective_to >= p_effective_date)
  order by (hm.effective_to is null) desc, hm.effective_from desc
  limit 1;

  if v_cur = p_household_id then
    return jsonb_build_object('member_id', v_wife.id, 'display_name', v_wife.display_name, 'status', 'already_in_household');
  elsif v_cur is null then
    v_res := private.assign_member_to_household_one(p_organization_id, v_wife.id, p_household_id, p_effective_date, true);
    if v_res->>'status' is distinct from 'assigned' then
      raise exception using errcode = '22023',
        message = format('%s could not be placed with her husband: %s Nothing was changed.',
                         v_wife.display_name, coalesce(v_res->>'message', v_res->>'status'));
    end if;
  else
    v_res := private.transfer_household_member_one(p_organization_id, v_wife.id, p_household_id, p_effective_date,
                                                    'Moves with her husband', true);
    if v_res->>'status' is distinct from 'transferred' then
      raise exception using errcode = '22023',
        message = format('%s could not be moved with her husband: %s Nothing was changed.',
                         v_wife.display_name, coalesce(v_res->>'message', v_res->>'status'));
    end if;
  end if;
  return jsonb_build_object('member_id', v_wife.id, 'display_name', v_wife.display_name, 'status', v_res->>'status');
end;
$$;
revoke all on function private.move_wife_with_husband(uuid, uuid, uuid, date) from public, anon, authenticated;

create or replace function public.assign_member_to_household(
  p_organization_id             uuid,
  p_member_id                   uuid,
  p_household_id                uuid,
  p_effective_from              date default current_date,
  p_confirm_governance_mismatch boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_res jsonb;
  v_sp  jsonb;
begin
  v_res := private.assign_member_to_household_one(p_organization_id, p_member_id, p_household_id,
                                                  p_effective_from, p_confirm_governance_mismatch);
  if v_res->>'status' = 'assigned' then
    v_sp := private.move_wife_with_husband(p_organization_id, p_member_id, p_household_id,
                                           coalesce(p_effective_from, current_date));
    if v_sp is not null then
      v_res := v_res || jsonb_build_object('spouse', v_sp);
    end if;
  end if;
  return v_res;
end;
$$;
revoke all on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) from public, anon;
grant execute on function public.assign_member_to_household(uuid, uuid, uuid, date, boolean) to authenticated, service_role;

create or replace function public.transfer_household_member(
  p_organization_id             uuid,
  p_member_id                   uuid,
  p_destination_household_id    uuid,
  p_effective_date              date default current_date,
  p_reason                      text default null,
  p_confirm_governance_mismatch boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_res jsonb;
  v_sp  jsonb;
begin
  v_res := private.transfer_household_member_one(p_organization_id, p_member_id, p_destination_household_id,
                                                 p_effective_date, p_reason, p_confirm_governance_mismatch);
  if v_res->>'status' = 'transferred' then
    v_sp := private.move_wife_with_husband(p_organization_id, p_member_id, p_destination_household_id,
                                           coalesce(p_effective_date, current_date));
    if v_sp is not null then
      v_res := v_res || jsonb_build_object('spouse', v_sp);
    end if;
  end if;
  return v_res;
end;
$$;
revoke all on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) from public, anon;
grant execute on function public.transfer_household_member(uuid, uuid, uuid, date, text, boolean) to authenticated, service_role;

-- Ron (2026-10-21): when a spouse's household membership is ended, the other spouse leaves the same household too
-- (either spouse). If the other spouse cannot be removed, nothing is changed and the reason is returned as an error.
create or replace function public.end_household_membership(
  p_organization_id uuid,
  p_member_id       uuid,
  p_effective_to    date default current_date,
  p_reason          text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_hh     uuid;
  v_res    jsonb;
  v_sp     public.members%rowtype;
  v_sp_hh  uuid;
  v_res2   jsonb;
begin
  select hm.household_node_id into v_hh
  from public.household_memberships hm
  where hm.organization_id = p_organization_id and hm.member_id = p_member_id and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and (hm.effective_to is null or hm.effective_to >= current_date)
  order by (hm.effective_to is null) desc, hm.effective_from desc
  limit 1;

  v_res := private.end_household_membership_one(p_organization_id, p_member_id, p_effective_to, p_reason);

  if v_res->>'status' = 'ended' and v_hh is not null then
    select * into v_sp from public.members
     where id = private.active_spouse_of(p_organization_id, p_member_id) and organization_id = p_organization_id;
    if v_sp.id is not null then
      select hm.household_node_id into v_sp_hh
      from public.household_memberships hm
      where hm.organization_id = p_organization_id and hm.member_id = v_sp.id and hm.is_primary = true
        and hm.membership_status in ('active', 'temporary')
        and (hm.effective_to is null or hm.effective_to >= current_date)
      order by (hm.effective_to is null) desc, hm.effective_from desc
      limit 1;
      if v_sp_hh = v_hh then
        v_res2 := private.end_household_membership_one(p_organization_id, v_sp.id, p_effective_to,
                                                       coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Leaves with spouse'));
        if v_res2->>'status' is distinct from 'ended' then
          raise exception using errcode = '22023',
            message = format('%s could not be removed together with their spouse: %s Nothing was changed.',
                             v_sp.display_name, coalesce(v_res2->>'message', v_res2->>'status'));
        end if;
        v_res := v_res || jsonb_build_object('spouse',
                   jsonb_build_object('member_id', v_sp.id, 'display_name', v_sp.display_name, 'status', 'ended'));
      end if;
    end if;
  end if;
  return v_res;
end;
$$;
revoke all on function public.end_household_membership(uuid, uuid, date, text) from public, anon;
grant execute on function public.end_household_membership(uuid, uuid, date, text) to authenticated, service_role;

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
              (lc.couples_context_status = 'couples')  -- Pass 9.26 (Ron, 2026-10-21): no Couple Household flag needed
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
          (v_couples_context_status = 'couples')  -- Pass 9.26 (Ron, 2026-10-21): no Couple Household flag needed
          or (v_couples_context_status = 'couples' and v_recommended_level = 'fraternal')  -- Pass 8.4G: fraternal may be mixed
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

  -- Couples compatibility on destination: removed in Pass 9.26 (Ron, 2026-10-21) — any household may hold couples.

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

  -- NON-ADMIN DELEGATED SERVANT LEADER DOUBLE-LOCK REQUIREMENT (Phase 6B-9)
  -- Applies to callers operating under delegated servant leader access roles or grants.
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if exists (
      select 1
      from public.profile_role_assignments pra
      join public.app_roles ar on ar.id = pra.app_role_id
      where pra.organization_id = p_organization_id
        and pra.profile_id = v_profile_id
        and pra.assignment_status = 'active'
        and ar.code in (
          'household_servant_leader_access',
          'unit_servant_leader_access',
          'chapter_servant_leader_access',
          'area_servant_leader_access'
        )
    ) or exists (
      select 1
      from public.servant_leader_access_grants g
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
    ) then
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
  end if;

  -- 4. Governance-scoped access check
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Identifier permission for roster member numbers
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Build profile payload with pastoral echelon derivation
  with household_identity as (
    select
      gn.id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      h.pastoral_level,
      case h.pastoral_level
        when 'member'    then 'Member Household'
        when 'unit'      then 'Unit Household'
        when 'chapter'   then 'Chapter Household'
        when 'area'      then 'Area Household'
        when 'fraternal' then 'Fraternal Household'
        else initcap(h.pastoral_level) || ' Household'
      end as pastoral_level_label,
      case h.pastoral_level
        when 'member'    then 'household_servant_leader'
        when 'unit'      then 'unit_servant_leader'
        when 'chapter'   then 'chapter_servant_leader'
        when 'area'      then 'area_servant_leader'
        when 'fraternal' then 'rotating_facilitation'
      end as leadership_source,
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
      m.sort_name,
      m.sex,
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
  ),
  -- Pass 8.3F: each roster member's spouse who is also on this roster (active spouse relationship)
  roster_spouse as (
    select distinct on (am.member_id)
      am.member_id,
      sp.member_id as spouse_member_id,
      sp.sort_name as spouse_sort_name,
      sp.sex       as spouse_sex
    from active_members am
    join public.family_relationships fr
      on fr.organization_id = p_organization_id
     and fr.relationship_status = 'active'
     and (fr.effective_from is null or fr.effective_from <= current_date)
     and (fr.effective_to is null or fr.effective_to >= current_date)
     and (fr.from_member_id = am.member_id or fr.to_member_id = am.member_id)
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
     and frt.code = 'spouse'
    join active_members sp
      on sp.member_id = case when fr.from_member_id = am.member_id then fr.to_member_id else fr.from_member_id end
     and sp.member_id <> am.member_id
    order by am.member_id, sp.member_id
  ),
  -- Pass 8.3F: alphabetical by last name (sort_name = "Family, Given"); spouses kept together,
  -- filed under the husband's last name, husband first
  roster_order as (
    select
      am.*,
      row_number() over (
        order by
          lower(case
            when rs.spouse_member_id is null then am.sort_name
            when am.sex = 'male' then am.sort_name
            when rs.spouse_sex = 'male' then rs.spouse_sort_name
            else least(am.sort_name, rs.spouse_sort_name)
          end),
          least(am.member_id::text, coalesce(rs.spouse_member_id, am.member_id)::text),
          case
            when rs.spouse_member_id is null then 0
            when am.sex = 'male' then 0
            when rs.spouse_sex = 'male' then 1
            when am.sort_name <= rs.spouse_sort_name then 0
            else 1
          end,
          lower(am.sort_name),
          am.member_id
      ) as roster_position
    from active_members am
    left join roster_spouse rs on rs.member_id = am.member_id
  ),
  derived_leaders as (
    -- Member: from household node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    join public.leadership_assignments la
      on la.governance_node_id = hi.id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'member'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'household_servant_leader'

    union all

    -- Unit: from parent Unit node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'unit'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'unit_servant_leader'

    union all

    -- Chapter: from parent Chapter node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'chapter'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'chapter_servant_leader'

    union all

    -- Area: from parent Area node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'area'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'area_servant_leader'
  ),
  couple_leaders as (
    select
      lead.member_id as servant_member_id,
      lead.display_name as servant_display_name,
      lead.effective_from as servant_effective_from,
      spouse_mem.display_name as spouse_display_name,
      spouse_mem.id as spouse_member_id,
      case hi.pastoral_level
        when 'member'  then 'Household Servant Leaders'
        when 'unit'    then 'Unit Servant Leaders'
        when 'chapter' then 'Chapter Servant Leaders'
        when 'area'    then 'Area Servant Leaders'
      end as couple_title
    from derived_leaders lead
    -- Pass 9.26 (Ron, 2026-10-21): a couple leads together when the servant leader belongs to the Couples
    -- section (primary section or active section assignment); the household's Couple flag no longer matters.
    join household_identity hi
      on (
        exists (
          select 1
          from public.members lm
          join public.governance_nodes sgn on sgn.id = lm.primary_section_node_id
          where lm.id = lead.member_id
            and (sgn.code ilike '%couple%' or sgn.name ilike '%couple%'
                 or coalesce(sgn.metadata->>'is_couple_section', 'false')::boolean = true
                 or coalesce(sgn.metadata->>'section_category', '') = 'couples')
        )
        or exists (
          select 1
          from public.member_governance_assignments mga
          join public.governance_nodes sgn on sgn.id = mga.governance_node_id
          join public.governance_node_types gnt on gnt.id = sgn.governance_node_type_id and gnt.code = 'section'
          where mga.member_id = lead.member_id
            and mga.organization_id = p_organization_id
            and mga.assignment_status = 'active'
            and mga.effective_from <= current_date
            and (mga.effective_to is null or mga.effective_to >= current_date)
            and (sgn.code ilike '%couple%' or sgn.name ilike '%couple%'
                 or coalesce(sgn.metadata->>'is_couple_section', 'false')::boolean = true
                 or coalesce(sgn.metadata->>'section_category', '') = 'couples')
        )
      )
    -- Spousal relationship check
    join public.family_relationships fr
      on fr.organization_id = p_organization_id
     and fr.relationship_status = 'active'
     and fr.verification_status in ('member_confirmed', 'administrator_verified', 'document_verified')
     and (fr.effective_from is null or fr.effective_from <= current_date)
     and (fr.effective_to is null or fr.effective_to >= current_date)
     and (fr.from_member_id = lead.member_id or fr.to_member_id = lead.member_id)
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
     and frt.code = 'spouse'
    cross join lateral (
      values (case when fr.from_member_id = lead.member_id then fr.to_member_id else fr.from_member_id end)
    ) as target_spouse(member_id)
    -- Spouse active member check
    join public.members spouse_mem
      on spouse_mem.id = target_spouse.member_id
     and spouse_mem.organization_id = p_organization_id
     and spouse_mem.record_status = 'active'
     and not spouse_mem.is_deceased
    -- For member households: spouse must also be a member of this household
    left join active_members am_spouse
      on am_spouse.member_id = target_spouse.member_id
    where (hi.pastoral_level != 'member' or am_spouse.member_id is not null)
      and hi.pastoral_level in ('member', 'unit', 'chapter', 'area')
    limit 1
  ),
  coordinator_leaders as (
    -- Pass 9.22 (Ron, 2026-10-20): an Area household whose Area has no Area Servant Leader is led by that Area's
    -- Coordinators (FMC NY household -> the FMC New York Coordinators), shown with their partner.
    select
      m.id as member_id,
      m.display_name,
      lrd.name as role_name,
      la.effective_from,
      pm.id as partner_id,
      pm.display_name as partner_name
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
    join public.members m
      on m.id = la.member_id
    left join public.members pm
      on pm.id = coalesce(nullif(la.metadata->>'couple_partner_member_id', '')::uuid,
                          private.active_spouse_of(p_organization_id, m.id))
    where hi.pastoral_level = 'area'
      and lrd.code like '%coordinator%'
      and la.assignment_status = 'active'
      and la.ended_at is null
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and not exists (select 1 from derived_leaders)
    order by la.effective_from desc
    limit 1
  ),
  formation_info as (
    select
      private.compute_household_formation_status(p_household_id) as formation_status,
      (
        select jsonb_build_object(
          'assignment_id',   a.id,
          'topic_id',        ft.id,
          'title',           ft.title,
          'planned_for_date', a.planned_for_date,
          'sequence_number', a.sequence_number
        )
        from public.household_topic_assignments a
        join public.formation_topics ft on ft.id = a.topic_id
        where a.household_node_id = p_household_id
          and a.assignment_status = 'planned'
        order by a.planned_for_date asc nulls last, a.sequence_number asc nulls last, a.created_at asc
        limit 1
      ) as next_topic,
      (
        select jsonb_build_object(
          'assignment_id', a.id,
          'topic_id',      ft.id,
          'title',         ft.title,
          'completed_at',  a.completed_at,
          'meeting_date',  m.meeting_date
        )
        from public.household_topic_assignments a
        join public.formation_topics ft on ft.id = a.topic_id
        left join public.household_meetings m on m.id = a.completed_household_meeting_id
        where a.household_node_id = p_household_id
          and a.assignment_status = 'completed'
        order by a.completed_at desc
        limit 1
      ) as last_completed_topic,
      (
        select count(*)::integer
        from public.household_topic_assignments
        where household_node_id = p_household_id
          and assignment_status = 'planned'
      ) as planned_topics_count,
      (
        select count(*)::integer
        from public.household_topic_assignments
        where household_node_id = p_household_id
          and assignment_status = 'completed'
      ) as completed_topics_count
  )
  select jsonb_build_object(
    'household', (
      select jsonb_build_object(
        'id',                    hi.id,
        'name',                  hi.name,
        'code',                  hi.code,
        'lifecycle_status',      hi.lifecycle_status,
        'household_category',    hi.household_category,
        'pastoral_level',        hi.pastoral_level,
        'pastoral_level_label',  hi.pastoral_level_label,
        'leadership_source',     hi.leadership_source,
        'effective_from',        hi.effective_from,
        'effective_to',          hi.effective_to,
        'meeting_frequency',     hi.meeting_frequency,
        'meeting_day_of_week',   hi.meeting_day_of_week,
        'meeting_start_time',    hi.meeting_start_time,
        'meeting_timezone_name', hi.meeting_timezone_name,
        'meeting_location_type', hi.meeting_location_type,
        'target_member_count',   hi.target_member_count,
        'maximum_member_count',  hi.maximum_member_count,
        'accepts_new_members',   hi.accepts_new_members,
        'language_code',         hi.language_code,
        'is_couple_household',   hi.is_couple_household
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
    'leaders', case
      when (select hi.pastoral_level from household_identity hi) = 'fraternal' then '[]'::jsonb
      else coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'leadership_assignment_id', dl.leadership_assignment_id,
              'member_id',                dl.member_id,
              'display_name',             dl.display_name,
              'leadership_role_code',     dl.leadership_role_code,
              'leadership_role_name',     dl.leadership_role_name,
              'assignment_status',        dl.assignment_status,
              'effective_from',           dl.effective_from,
              'effective_to',             dl.effective_to
            )
          )
          from derived_leaders dl
        ),
        '[]'::jsonb
      )
    end,
    'household_leaders', case
      when (select hi.pastoral_level from household_identity hi) = 'fraternal' then null
      else coalesce((
        select jsonb_build_object(
          'source', 'couple',
          'husband', jsonb_build_object(
            'member_id',    cl.servant_member_id,
            'display_name', cl.servant_display_name
          ),
          'wife', jsonb_build_object(
            'member_id',    cl.spouse_member_id,
            'display_name', cl.spouse_display_name
          ),
          'pastoral_label', cl.couple_title,
          'formatted_names', cl.servant_display_name || ' & ' || cl.spouse_display_name,
          'effective_from', cl.servant_effective_from
        )
        from couple_leaders cl
        limit 1
      ), (
        select jsonb_build_object(
          'source', 'coordinator',
          'husband', jsonb_build_object('member_id', co.member_id, 'display_name', co.display_name),
          'wife', jsonb_build_object('member_id', co.partner_id, 'display_name', co.partner_name),
          'pastoral_label', case when co.partner_id is null then co.role_name else co.role_name || 's' end,
          'formatted_names', co.display_name || coalesce(' & ' || co.partner_name, ''),
          'effective_from', co.effective_from
        )
        from coordinator_leaders co
        limit 1
      ))
    end,
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
          order by am.roster_position
        )
        from roster_order am
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
    ),
    'formation_summary', (
      select jsonb_build_object(
        'formation_status',       fi.formation_status,
        'next_topic',             fi.next_topic,
        'last_completed_topic',   fi.last_completed_topic,
        'planned_topics_count',   fi.planned_topics_count,
        'completed_topics_count', fi.completed_topics_count
      )
      from formation_info fi
    ),
    -- Backwards-compatibility top-level keys
    'household_id',          (select hi.id from household_identity hi),
    'name',                  (select hi.name from household_identity hi),
    'code',                  (select hi.code from household_identity hi),
    'lifecycle_status',      (select hi.lifecycle_status from household_identity hi),
    'household_category',    (select hi.household_category from household_identity hi),
    'pastoral_level',        (select hi.pastoral_level from household_identity hi),
    'pastoral_level_label',  (select hi.pastoral_level_label from household_identity hi),
    'leadership_source',     (select hi.leadership_source from household_identity hi),
    'effective_from',        (select hi.effective_from from household_identity hi),
    'effective_to',          (select hi.effective_to from household_identity hi),
    'meeting_frequency',     (select hi.meeting_frequency from household_identity hi),
    'meeting_day_of_week',   (select hi.meeting_day_of_week from household_identity hi),
    'meeting_start_time',    (select hi.meeting_start_time from household_identity hi),
    'meeting_timezone_name', (select hi.meeting_timezone_name from household_identity hi),
    'meeting_location_type', (select hi.meeting_location_type from household_identity hi),
    'target_member_count',   (select hi.target_member_count from household_identity hi),
    'maximum_member_count',  (select hi.maximum_member_count from household_identity hi),
    'accepts_new_members',   (select hi.accepts_new_members from household_identity hi),
    'language_code',         (select hi.language_code from household_identity hi),
    'is_couple_household',   (select hi.is_couple_household from household_identity hi),
    'parent_node_id',        (select pg.parent_node_id from parent_gov pg),
    'parent_node_name',      (select pg.parent_node_name from parent_gov pg),
    'parent_node_code',      (select pg.parent_node_code from parent_gov pg),
    'parent_node_type',      (select pg.parent_node_type from parent_gov pg),
    'active_member_count',   (select count(*)::integer from active_members)
  ) into v_profile_data;

  return v_profile_data;
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

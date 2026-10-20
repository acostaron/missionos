-- =============================================================================
-- Migration: 20261010092000_servant_leader_offices.sql
-- MissionOS Pass 9.20 (written by Claude, 2026-10-19) — run after 20261010091000.
-- Ron (2026-10-19): manage Area, Chapter and Unit Servant Leaders in the app (Pastoral -> Leaders tab):
-- appoint, link husband and wife in the same step, end an appointment, and grant app access.
-- New functions only; no existing function or table is changed.
--   * private.active_spouse_of(org, member)          -> the member's active spouse (or null)
--   * private.member_has_login(org, member)          -> verified, active login linked to the member
--   * public.list_servant_leader_offices(org)        -> every active Area / Chapter / Unit with its leader
--   * public.appoint_servant_leader_with_spouse(...) -> links the spouse (family record + spouse
--     relationship, created only if missing) and appoints, all in one transaction, through the existing
--     create_family / add_family_member / add_family_relationship / appoint_servant_leader functions
--     (so all their permission checks and audit events still apply).
-- App access keeps using the existing grant_servant_leader_access (one grant per appointment).
-- =============================================================================

create or replace function private.active_spouse_of(p_organization_id uuid, p_member_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select case when fr.from_member_id = p_member_id then fr.to_member_id else fr.from_member_id end
  from public.family_relationships fr
  join public.family_relationship_types t on t.id = fr.relationship_type_id and t.code = 'spouse'
  where fr.organization_id = p_organization_id
    and fr.relationship_status = 'active'
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id)
  order by fr.created_at
  limit 1
$$;
revoke all on function private.active_spouse_of(uuid, uuid) from public, anon, authenticated;

create or replace function private.member_has_login(p_organization_id uuid, p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select exists (
    select 1
    from public.profile_member_links pml
    join public.profiles p on p.id = pml.profile_id and p.account_status = 'active'
    where pml.organization_id = p_organization_id
      and pml.member_id = p_member_id
      and pml.link_type = 'self'
      and pml.link_status = 'verified'
      and pml.is_primary = true
      and pml.ended_at is null)
$$;
revoke all on function private.member_has_login(uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- List: every active Area / Chapter / Unit and its current servant leader
-- -----------------------------------------------------------------------------
create or replace function public.list_servant_leader_offices(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_can_appoint  boolean;
  v_can_conclude boolean;
  v_can_access   boolean;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;
  v_can_appoint  := private.has_permission('leadership.servant_leaders.appoint', p_organization_id);
  v_can_conclude := private.has_permission('leadership.servant_leaders.conclude', p_organization_id);
  v_can_access   := private.has_permission('leadership.delegated_access.manage', p_organization_id);
  if not (v_can_appoint or v_can_conclude or v_can_access) then
    raise exception using errcode = '42501', message = 'Only administrators can manage servant leaders.';
  end if;

  return jsonb_build_object(
    'can_appoint',       v_can_appoint,
    'can_conclude',      v_can_conclude,
    'can_manage_access', v_can_access,
    'offices', coalesce((
      select jsonb_agg(o.office order by o.level_rank, o.parent_name nulls first, o.node_name)
      from (
        select
          case t.code when 'area_state' then 1 when 'chapter' then 2 else 3 end as level_rank,
          n.name as node_name,
          par.name as parent_name,
          jsonb_build_object(
            'node_id',    n.id,
            'node_name',  n.name,
            'node_type',  t.code,
            'role_code',  case t.code when 'area_state' then 'area_servant_leader'
                                      when 'chapter'    then 'chapter_servant_leader'
                                      else 'unit_servant_leader' end,
            'parent_name', par.name,
            'leader', (
              select jsonb_build_object(
                'assignment_id',  la.id,
                'member_id',      m.id,
                'member_number',  m.member_number,
                'display_name',   m.display_name,
                'role_name',      d.name,
                'effective_from', la.effective_from,
                'has_login',      private.member_has_login(p_organization_id, m.id),
                'access_status',  (select g.access_status from public.servant_leader_access_grants g
                                    where g.organization_id = p_organization_id and g.leadership_assignment_id = la.id
                                      and g.access_status = 'active' limit 1),
                'spouse', (select jsonb_build_object('member_id', s.id, 'member_number', s.member_number,
                                                     'display_name', s.display_name)
                             from public.members s
                            where s.id = private.active_spouse_of(p_organization_id, m.id)))
              from public.leadership_assignments la
              join public.leadership_role_definitions d on d.id = la.leadership_role_definition_id
              join public.members m on m.id = la.member_id
              where la.organization_id = p_organization_id
                and la.governance_node_id = n.id
                and d.code in ('area_servant_leader', 'chapter_servant_leader', 'unit_servant_leader')
                and la.assignment_status = 'active'
                and la.ended_at is null
                and la.effective_from <= current_date
                and (la.effective_to is null or la.effective_to >= current_date)
              order by la.effective_from desc
              limit 1)
          ) as office
        from public.governance_nodes n
        join public.governance_node_types t on t.id = n.governance_node_type_id
        left join lateral (
          select pn.name
          from public.governance_node_relationships r
          join public.governance_nodes pn on pn.id = r.parent_node_id
          where r.organization_id = p_organization_id
            and r.child_node_id = n.id
            and r.relationship_type = 'primary_parent'
            and r.relationship_status = 'active'
            and (r.effective_to is null or r.effective_to >= current_date)
          order by r.effective_from desc
          limit 1
        ) par on true
        where n.organization_id = p_organization_id
          and n.lifecycle_status = 'active'
          and t.code in ('area_state', 'chapter', 'unit')
      ) o), '[]'::jsonb));
end;
$$;
revoke all on function public.list_servant_leader_offices(uuid) from public, anon;
grant execute on function public.list_servant_leader_offices(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Appoint, linking the spouse in the same step
-- -----------------------------------------------------------------------------
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

  v_res := public.appoint_servant_leader(p_organization_id, lower(p_role_code), p_governance_node_id, p_member_id,
                                         current_date, nullif(btrim(coalesce(p_reason, '')), ''));
  return v_res || jsonb_build_object('spouse_member_id', p_spouse_member_id, 'spouse_link', v_linked);
end;
$$;
revoke all on function public.appoint_servant_leader_with_spouse(uuid, text, uuid, uuid, uuid, text) from public, anon;
grant execute on function public.appoint_servant_leader_with_spouse(uuid, text, uuid, uuid, uuid, text) to authenticated;

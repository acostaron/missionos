-- =============================================================================
-- Migration: 20261010093000_leaders_show_coordinators.sql
-- MissionOS Pass 9.20A (written by Claude, 2026-10-20) — run after 20261010092000.
-- Ron (2026-10-20): on Pastoral -> Leaders, FMC New York is not vacant — Napoleon & Miriam Rodriguez are the
-- FMC New York Coordinators. MFC New York has no appointed leader on purpose (it exists so FMC New York sits at the
-- same level); New York Area's servant leader oversees both.
-- list_servant_leader_offices now also returns, per office:
--   * coordinator  — an active coordinator appointment on the node (e.g. FMC Coordinator), with partner/spouse;
--   * is_sub_area  — true for an Area placed under another Area.
-- Guarded: replaces the 092 version only if unchanged.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'list_servant_leader_offices';
  if v_md5 is distinct from 'e924fe49d69354d8dcace77749890243' then
    raise exception 'STOP: public.list_servant_leader_offices differs from 20261010092000 (md5 %).', v_md5;
  end if;
end;
$guard$;

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
            -- Pass 9.20A: an Area under another Area (MFC New York, FMC New York) is a sub-area
            'is_sub_area', (t.code = 'area_state' and par.node_type = 'area_state'),
            -- Pass 9.20A: coordinators (e.g. FMC Coordinator) appointed on this node
            'coordinator', (
              select jsonb_build_object(
                'role_name',     d.name,
                'member_number', m.member_number,
                'display_name',  m.display_name,
                'partner', (select jsonb_build_object('member_number', s.member_number, 'display_name', s.display_name)
                              from public.members s
                             where s.id = coalesce(nullif(la.metadata->>'couple_partner_member_id', '')::uuid,
                                                   private.active_spouse_of(p_organization_id, m.id))))
              from public.leadership_assignments la
              join public.leadership_role_definitions d on d.id = la.leadership_role_definition_id
              join public.members m on m.id = la.member_id
              where la.organization_id = p_organization_id
                and la.governance_node_id = n.id
                and d.code like '%coordinator%'
                and la.assignment_status = 'active'
                and la.ended_at is null
                and (la.effective_to is null or la.effective_to >= current_date)
              order by la.effective_from desc
              limit 1),
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
          select pn.name, pt.code as node_type
          from public.governance_node_relationships r
          join public.governance_nodes pn on pn.id = r.parent_node_id
          join public.governance_node_types pt on pt.id = pn.governance_node_type_id
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

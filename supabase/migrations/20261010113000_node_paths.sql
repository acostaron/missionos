-- =============================================================================
-- Migration: 20261010113000_node_paths.sql
-- MissionOS Pass 9.40 (written by Claude, 2026-10-22) — run after 20261010112000.
-- Ron (2026-10-22): on Pastoral Operations (Households, Dashboard, Leaders) group households, leadership vacancies,
-- the household operations table and the leaders by MFC New York / FMC New York, then Section, Chapter and Unit.
--   * public.get_node_paths(org): for every active area / section / chapter / unit and every household, where it sits:
--     area, sub-area (MFC New York, FMC New York; null = New York Area itself), section (from the tree, or a household's
--     chosen section), chapter and unit. Structure names only. Read only; no existing function is replaced.
-- =============================================================================

create or replace function public.get_node_paths(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with recursive nodes as (
    select n.id, t.code as type_code
    from public.governance_nodes n
    join public.governance_node_types t on t.id = n.governance_node_type_id
    where n.organization_id = p_organization_id
      and (n.lifecycle_status = 'active' or t.code = 'household')  -- closed / archived households keep their path
      and t.code in ('area_state', 'section', 'chapter', 'unit', 'household')
      and private.has_organization_access(p_organization_id)
  ),
  up(node_id, anc_id, depth) as (
    select id, id, 0 from nodes
    union all
    select up.node_id, r.parent_node_id, up.depth + 1
    from up
    join public.governance_node_relationships r
      on r.child_node_id = up.anc_id
     and r.relationship_type = 'primary_parent'
     and r.is_primary
     and r.relationship_status = 'active'
     and r.effective_to is null
    where up.depth < 12
  ),
  typed as (
    select up.node_id, up.anc_id, up.depth, a.name, a.code, t.code as type_code,
           (select pt.code
            from public.governance_node_relationships pr
            join public.governance_nodes p on p.id = pr.parent_node_id
            join public.governance_node_types pt on pt.id = p.governance_node_type_id
            where pr.child_node_id = a.id and pr.relationship_type = 'primary_parent' and pr.is_primary
              and pr.relationship_status = 'active' and pr.effective_to is null
            limit 1) as parent_type
    from up
    join public.governance_nodes a on a.id = up.anc_id
    join public.governance_node_types t on t.id = a.governance_node_type_id
  ),
  sub_area as (
    select distinct on (node_id) node_id, anc_id, name, code
    from typed where type_code = 'area_state' and parent_type = 'area_state'
    order by node_id, depth
  ),
  top_area as (
    select distinct on (node_id) node_id, name
    from typed where type_code = 'area_state'
    order by node_id, depth desc
  ),
  sec as (
    select distinct on (node_id) node_id, anc_id, name
    from typed where type_code = 'section'
    order by node_id, depth
  ),
  chap as (
    select distinct on (node_id) node_id, anc_id, name
    from typed where type_code = 'chapter'
    order by node_id, depth
  ),
  un as (
    select distinct on (node_id) node_id, anc_id, name
    from typed where type_code = 'unit'
    order by node_id, depth
  )
  select coalesce(jsonb_object_agg(n.id::text, jsonb_build_object(
           'type', n.type_code,
           'area_name', ta.name,
           'sub_area_id', sa.anc_id, 'sub_area_name', sa.name, 'sub_area_code', sa.code,
           'section_id', coalesce(s.anc_id, h.section_node_id),
           'section_name', coalesce(s.name, hs.name),
           'section_category', sc.section_category,
           'chapter_id', c.anc_id, 'chapter_name', c.name,
           'unit_id', u.anc_id, 'unit_name', u.name)), '{}'::jsonb)
  from nodes n
  left join top_area ta on ta.node_id = n.id
  left join sub_area sa on sa.node_id = n.id
  left join sec s on s.node_id = n.id
  left join public.households h on h.id = n.id and s.node_id is null
  left join public.governance_nodes hs on hs.id = h.section_node_id
  left join public.sections sc on sc.id = coalesce(s.anc_id, h.section_node_id)
  left join chap c on c.node_id = n.id
  left join un u on u.node_id = n.id
$$;
revoke all on function public.get_node_paths(uuid) from public, anon;
grant execute on function public.get_node_paths(uuid) to authenticated;

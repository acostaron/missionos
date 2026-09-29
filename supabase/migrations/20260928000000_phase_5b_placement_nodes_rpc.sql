-- Migration: 20260928000000_phase_5b_placement_nodes_rpc.sql
-- Description: Browser-safe RPC returning active Chapter and Unit governance placement nodes for selection.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_placement_nodes(
    p_organization_id uuid
)
RETURNS TABLE (
    governance_node_id uuid,
    node_code text,
    node_name text,
    node_type_code text,
    parent_governance_node_id uuid,
    parent_node_name text,
    hierarchy_rank integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
declare
    v_actor_profile_id uuid;
begin
    -- 1. Resolve and verify authenticated caller profile
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    -- 2. Verify active organization access
    if not private.has_organization_access(p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: caller does not belong to active organization.';
    end if;

    -- 3. Verify governance structure view permission
    if not private.has_permission('governance.structure.view', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission governance.structure.view.';
    end if;

    -- 4. Return selectable active Chapter and Unit nodes filtered to caller governance scope
    return query
    select
        n.id as governance_node_id,
        n.code as node_code,
        n.name as node_name,
        nt.code as node_type_code,
        case
            -- For unit, parent_governance_node_id is its primary parent chapter
            when nt.code = 'unit' then p_rel.parent_node_id
            -- For chapter, parent is internal (area/state), not a selectable placement parent
            else null
        end as parent_governance_node_id,
        case
            when nt.code = 'unit' then pn.name
            else null
        end as parent_node_name,
        nt.hierarchy_rank::integer as hierarchy_rank
    from public.governance_nodes n
    join public.governance_node_types nt
      on nt.id = n.governance_node_type_id
     and nt.organization_id = n.organization_id
    -- Join parent relationship for units
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = n.id
     and p_rel.organization_id = n.organization_id
     and p_rel.is_primary = true
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn
      on pn.id = p_rel.parent_node_id
     and pn.organization_id = n.organization_id
    where n.organization_id = p_organization_id
      and n.lifecycle_status = 'active'
      and (n.effective_to is null or n.effective_to >= current_date)
      and nt.code in ('chapter', 'unit')
      -- Enforce caller governance scope
      and private.profile_has_governance_scope(v_actor_profile_id, p_organization_id, n.id, now())
    order by
        nt.hierarchy_rank asc,
        coalesce(pn.name, n.name) asc,
        n.name asc;
end;
$$;

REVOKE ALL ON FUNCTION public.get_placement_nodes(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_placement_nodes(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_placement_nodes(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_placement_nodes(uuid) TO service_role;

COMMENT ON FUNCTION public.get_placement_nodes(uuid) IS
'Browser-safe RPC providing active Chapter and Unit nodes for member placement selection, scoped to caller authorization.';

COMMIT;

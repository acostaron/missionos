-- Dry run test for 20260928000000_phase_5b_placement_nodes_rpc.sql
BEGIN;

-- 1. Apply the migration function definition inside transaction
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
            when nt.code = 'unit' then p_rel.parent_node_id
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

DO $$
DECLARE
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
    v_admin_profile_id uuid := '821fb09c-8396-4549-b120-5674f3cc566a';
    v_count integer;
    v_chapter_count integer;
    v_unit_count integer;
    v_area_count integer;
    v_rvc_chapter_id uuid;
    v_unit_parent_count integer;
    r record;
BEGIN
    -- Set authenticated session context to MFCNY administrator
    PERFORM set_config('request.jwt.claims', json_build_object(
        'sub', v_admin_profile_id::text,
        'role', 'authenticated'
    )::text, true);

    -- 2. Call the function
    CREATE TEMP TABLE tmp_nodes ON COMMIT DROP AS
    SELECT * FROM public.get_placement_nodes(v_org_id);

    SELECT count(*) INTO v_count FROM tmp_nodes;
    SELECT count(*) INTO v_chapter_count FROM tmp_nodes WHERE node_type_code = 'chapter';
    SELECT count(*) INTO v_unit_count FROM tmp_nodes WHERE node_type_code = 'unit';
    SELECT count(*) INTO v_area_count FROM tmp_nodes WHERE node_type_code = 'area_state';

    RAISE NOTICE 'Total nodes returned: %, Chapters: %, Units: %, Area/State: %',
        v_count, v_chapter_count, v_unit_count, v_area_count;

    IF v_count <> 6 THEN
        RAISE EXCEPTION 'Dry-run failed: expected 6 total nodes, got %', v_count;
    END IF;
    IF v_chapter_count <> 4 THEN
        RAISE EXCEPTION 'Dry-run failed: expected 4 chapters, got %', v_chapter_count;
    END IF;
    IF v_unit_count <> 2 THEN
        RAISE EXCEPTION 'Dry-run failed: expected 2 units, got %', v_unit_count;
    END IF;
    IF v_area_count <> 0 THEN
        RAISE EXCEPTION 'Dry-run failed: expected 0 area/state, got %', v_area_count;
    END IF;

    -- Verify Rockville Center units resolve to Rockville Center Chapter
    SELECT id INTO v_rvc_chapter_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'rvc';
    SELECT count(*) INTO v_unit_parent_count FROM tmp_nodes WHERE node_type_code = 'unit' AND parent_governance_node_id = v_rvc_chapter_id;

    IF v_unit_parent_count <> 2 THEN
        RAISE EXCEPTION 'Dry-run failed: expected 2 units with Rockville Center chapter parent, got %', v_unit_parent_count;
    END IF;

    -- Verify permissions: anon cannot execute
    IF has_function_privilege('anon', 'public.get_placement_nodes(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Security check failed: anon has EXECUTE on get_placement_nodes';
    END IF;

    -- Verify permissions: authenticated has execute
    IF NOT has_function_privilege('authenticated', 'public.get_placement_nodes(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Security check failed: authenticated lacks EXECUTE on get_placement_nodes';
    END IF;

    RAISE NOTICE '--- DRY RUN VERIFICATION PASSED SUCCESSFULLY ---';
END $$;

ROLLBACK;

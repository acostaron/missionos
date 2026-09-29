DO $$
DECLARE
    v_admin_profile_id uuid := '821fb09c-8396-4549-b120-5674f3cc566a';
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
    r record;
    v_count integer := 0;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object(
        'sub', v_admin_profile_id::text,
        'role', 'authenticated'
    )::text, true);

    FOR r IN SELECT * FROM public.get_placement_nodes(v_org_id) LOOP
        v_count := v_count + 1;
        RAISE NOTICE 'Node %: "%" (code: %, type: %, parent_id: %, parent_name: "%")',
            v_count, r.node_name, r.node_code, r.node_type_code, r.parent_governance_node_id, r.parent_node_name;
    END LOOP;

    IF v_count <> 6 THEN
        RAISE EXCEPTION 'Expected 6 nodes, got %', v_count;
    END IF;
END $$;

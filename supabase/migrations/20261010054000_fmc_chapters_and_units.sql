-- Pass 6.2: FMC New York structure (data only, no function changes).
-- Ministry facts (Ron): FMC has its own chapters, units and households. FMC Couples units mirror the 8 MFC units;
-- FMC Handmaids has its own chapter with units mirroring the MFC units.
--   fmc_nyc  "FMC New York Chapter"   (chapter)  parent fmc_ny                + 8 units fmc_nyc_*
--   fmc_hm   "FMC Handmaids New York Chapter"  (chapter)  parent fmc_ny_sec_handmaids  + 8 units fmc_hm_*
-- Pattern copied from 20261010050000 (Handmaids New York Chapter). No members are moved or placed here.

DO $$
DECLARE
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
    v_type_chapter uuid;
    v_type_unit uuid;
    v_fmc_ny_id uuid;
    v_fmc_sec_hm_id uuid;
    v_today date := CURRENT_DATE;
    v_now timestamptz := clock_timestamp();
    v_count integer;
BEGIN
    SELECT id INTO STRICT v_type_chapter FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'chapter';
    SELECT id INTO STRICT v_type_unit    FROM public.governance_node_types WHERE organization_id = v_org_id AND code = 'unit';
    SELECT id INTO STRICT v_fmc_ny_id     FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'fmc_ny' AND lifecycle_status = 'active';
    SELECT id INTO STRICT v_fmc_sec_hm_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'fmc_ny_sec_handmaids' AND lifecycle_status = 'active';

    -- Pre-guard: none of the new codes may exist yet.
    SELECT count(*) INTO v_count FROM public.governance_nodes
    WHERE organization_id = v_org_id AND (code IN ('fmc_nyc', 'fmc_hm') OR code LIKE 'fmc\_nyc\_%' OR code LIKE 'fmc\_hm\_%');
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Pre-guard failed: % FMC chapter/unit codes already exist', v_count;
    END IF;

    CREATE TEMP TABLE _fmc_nodes (
        code text PRIMARY KEY,
        name text NOT NULL,
        node_type uuid NOT NULL,
        parent_code text NOT NULL,
        ord integer NOT NULL
    ) ON COMMIT DROP;

    INSERT INTO _fmc_nodes (code, name, node_type, parent_code, ord) VALUES
        ('fmc_nyc',                'FMC New York Chapter',            v_type_chapter, 'fmc_ny',               1),
        ('fmc_nyc_nassau',         'FMC Nassau Unit',                 v_type_unit,    'fmc_nyc',              2),
        ('fmc_nyc_suffolk',        'FMC Suffolk Unit',                v_type_unit,    'fmc_nyc',              3),
        ('fmc_nyc_brooklyn',       'FMC Brooklyn Unit',               v_type_unit,    'fmc_nyc',              4),
        ('fmc_nyc_queens',         'FMC Queens Unit',                 v_type_unit,    'fmc_nyc',              5),
        ('fmc_nyc_bronx',          'FMC Bronx Unit',                  v_type_unit,    'fmc_nyc',              6),
        ('fmc_nyc_manhattan',      'FMC Manhattan Unit',              v_type_unit,    'fmc_nyc',              7),
        ('fmc_nyc_staten_island',  'FMC Staten Island Unit',          v_type_unit,    'fmc_nyc',              8),
        ('fmc_nyc_albany',         'FMC Albany Unit',                 v_type_unit,    'fmc_nyc',              9),
        ('fmc_hm',                 'FMC Handmaids New York Chapter',  v_type_chapter, 'fmc_ny_sec_handmaids', 10),
        ('fmc_hm_nassau',          'FMC Handmaids Nassau Unit',       v_type_unit,    'fmc_hm',               11),
        ('fmc_hm_suffolk',         'FMC Handmaids Suffolk Unit',      v_type_unit,    'fmc_hm',               12),
        ('fmc_hm_brooklyn',        'FMC Handmaids Brooklyn Unit',     v_type_unit,    'fmc_hm',               13),
        ('fmc_hm_queens',          'FMC Handmaids Queens Unit',       v_type_unit,    'fmc_hm',               14),
        ('fmc_hm_bronx',           'FMC Handmaids Bronx Unit',        v_type_unit,    'fmc_hm',               15),
        ('fmc_hm_manhattan',       'FMC Handmaids Manhattan Unit',    v_type_unit,    'fmc_hm',               16),
        ('fmc_hm_staten_island',   'FMC Handmaids Staten Island Unit',v_type_unit,    'fmc_hm',               17),
        ('fmc_hm_albany',          'FMC Handmaids Albany Unit',       v_type_unit,    'fmc_hm',               18);

    -- Nodes
    INSERT INTO public.governance_nodes (organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from, created_at, updated_at)
    SELECT v_org_id, s.node_type, s.code, s.name, 'active', v_today, v_now, v_now
    FROM _fmc_nodes s
    ORDER BY s.ord;

    -- Detail rows
    INSERT INTO public.chapters (id, organization_id, chapter_category, created_at, updated_at)
    SELECT gn.id, v_org_id, 'standard', v_now, v_now
    FROM _fmc_nodes s JOIN public.governance_nodes gn ON gn.organization_id = v_org_id AND gn.code = s.code
    WHERE s.node_type = v_type_chapter;

    INSERT INTO public.units (id, organization_id, unit_category, created_at, updated_at)
    SELECT gn.id, v_org_id, 'standard', v_now, v_now
    FROM _fmc_nodes s JOIN public.governance_nodes gn ON gn.organization_id = v_org_id AND gn.code = s.code
    WHERE s.node_type = v_type_unit;

    -- Primary parent relationships, chapters first so units can attach (ordered insert, one row at a time)
    FOR v_count IN SELECT ord FROM _fmc_nodes ORDER BY ord LOOP
        INSERT INTO public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary, effective_from, created_at, updated_at)
        SELECT v_org_id, p.id, c.id, 'primary_parent', 'active', true, v_today, v_now, v_now
        FROM _fmc_nodes s
        JOIN public.governance_nodes c ON c.organization_id = v_org_id AND c.code = s.code
        JOIN public.governance_nodes p ON p.organization_id = v_org_id AND p.code = s.parent_code
        WHERE s.ord = v_count;
    END LOOP;

    -- Guards
    SELECT count(*) INTO v_count
    FROM public.governance_node_relationships r
    JOIN public.governance_nodes c ON c.id = r.child_node_id
    JOIN public.governance_nodes p ON p.id = r.parent_node_id
    WHERE r.organization_id = v_org_id AND r.relationship_type = 'primary_parent' AND r.relationship_status = 'active'
      AND r.is_primary AND r.effective_to IS NULL
      AND ((p.code = 'fmc_ny' AND c.code = 'fmc_nyc')
        OR (p.code = 'fmc_ny_sec_handmaids' AND c.code = 'fmc_hm')
        OR (p.code = 'fmc_nyc' AND c.code LIKE 'fmc\_nyc\_%')
        OR (p.code = 'fmc_hm'  AND c.code LIKE 'fmc\_hm\_%'));
    IF v_count <> 18 THEN
        RAISE EXCEPTION 'Guard failed: expected 18 FMC parent links, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count FROM public.units u JOIN public.governance_nodes gn ON gn.id = u.id
    WHERE gn.organization_id = v_org_id AND (gn.code LIKE 'fmc\_nyc\_%' OR gn.code LIKE 'fmc\_hm\_%');
    IF v_count <> 16 THEN
        RAISE EXCEPTION 'Guard failed: expected 16 FMC unit detail rows, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count FROM public.member_governance_assignments mga
    JOIN public.governance_nodes gn ON gn.id = mga.governance_node_id
    WHERE gn.code IN (SELECT code FROM _fmc_nodes);
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Guard failed: new FMC nodes must have no placements, got %', v_count;
    END IF;

    INSERT INTO audit.events (organization_id, event_code, event_category, entity_type, entity_id, action, outcome, metadata)
    VALUES (
        v_org_id, 'governance.structure_updated', 'governance', 'governance_node', v_fmc_ny_id,
        'create_fmc_chapters_and_units', 'success',
        jsonb_build_object(
            'migration', '20261010054000_fmc_chapters_and_units',
            'chapter_codes', jsonb_build_array('fmc_nyc', 'fmc_hm'),
            'unit_codes', (SELECT jsonb_agg(code ORDER BY ord) FROM _fmc_nodes WHERE node_type = v_type_unit)
        )
    );

    RAISE NOTICE 'Pass 6.2: FMC chapters (2) and units (16) created; guards passed.';
END $$;

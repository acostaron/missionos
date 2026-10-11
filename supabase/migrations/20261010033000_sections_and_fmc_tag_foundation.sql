-- Migration 101: Sections and FMC tag foundation
-- Label: sections_and_fmc_tag_foundation
-- Contiguous timestamp: 20261010033000

DO $$
DECLARE
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
    v_type_section uuid;
    v_node_ny uuid;
    v_today date := CURRENT_DATE;
    v_now timestamptz := clock_timestamp();
    v_sections_created integer := 0;
    v_tag_id uuid;
BEGIN
    ----------------------------------------------------------------------------
    -- RESOLVE TYPE AND PARENT NODE
    ----------------------------------------------------------------------------
    -- Resolve section node type
    SELECT id INTO STRICT v_type_section
    FROM public.governance_node_types
    WHERE organization_id = v_org_id AND code = 'section';

    -- Resolve Area node (ny)
    SELECT id INTO STRICT v_node_ny
    FROM public.governance_nodes
    WHERE organization_id = v_org_id AND code = 'ny';

    ----------------------------------------------------------------------------
    -- A. CREATE 7 SECTION GOVERNANCE NODES + SECTIONS DETAIL ROWS + RELATIONSHIPS
    --    sec_couples    "Couples"   category: couples   supports_couple: true
    --    sec_handmaids  "Handmaids" category: handmaids supports_couple: false
    --    sec_servants   "Servants"  category: servants  supports_couple: false
    --    sec_singles    "Singles"   category: singles   supports_couple: false
    --    sec_campus     "Campus"    category: campus    supports_couple: false
    --    sec_youth      "Youth"     category: youth     supports_couple: false
    --    sec_kids       "Kids"      category: kids      supports_couple: false
    ----------------------------------------------------------------------------
    CREATE TEMP TABLE _sections_staging (
        code text PRIMARY KEY,
        name text NOT NULL,
        category text NOT NULL,
        supports_couple boolean NOT NULL,
        supports_individual boolean NOT NULL
    ) ON COMMIT DROP;

    INSERT INTO _sections_staging (code, name, category, supports_couple, supports_individual) VALUES
        ('sec_couples',   'Couples',   'couples',   true,  true),
        ('sec_handmaids', 'Handmaids', 'handmaids', false, true),
        ('sec_servants',  'Servants',  'servants',  false, true),
        ('sec_singles',   'Singles',   'singles',   false, true),
        ('sec_campus',    'Campus',    'campus',    false, true),
        ('sec_youth',     'Youth',     'youth',     false, true),
        ('sec_kids',      'Kids',      'kids',      false, true);

    -- 1. Insert governance_nodes (idempotent by organization_id + code)
    INSERT INTO public.governance_nodes (
        organization_id,
        governance_node_type_id,
        code,
        name,
        lifecycle_status,
        effective_from,
        created_at,
        updated_at
    )
    SELECT
        v_org_id,
        v_type_section,
        s.code,
        s.name,
        'active',
        v_today,
        v_now,
        v_now
    FROM _sections_staging s
    ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
    DO UPDATE SET
        name = EXCLUDED.name,
        lifecycle_status = 'active',
        updated_at = v_now;

    GET DIAGNOSTICS v_sections_created = ROW_COUNT;

    -- 2. Insert sections detail rows
    INSERT INTO public.sections (
        id,
        organization_id,
        section_category,
        supports_couple_membership,
        supports_individual_membership,
        created_at,
        updated_at
    )
    SELECT
        gn.id,
        v_org_id,
        s.category,
        s.supports_couple,
        s.supports_individual,
        v_now,
        v_now
    FROM _sections_staging s
    JOIN public.governance_nodes gn ON gn.organization_id = v_org_id AND gn.code = s.code
    ON CONFLICT (id) DO UPDATE SET
        section_category = EXCLUDED.section_category,
        supports_couple_membership = EXCLUDED.supports_couple_membership,
        supports_individual_membership = EXCLUDED.supports_individual_membership,
        updated_at = v_now;

    -- 3. Insert governance_node_relationships (Area ny -> section)
    INSERT INTO public.governance_node_relationships (
        organization_id,
        parent_node_id,
        child_node_id,
        relationship_type,
        relationship_status,
        is_primary,
        effective_from,
        created_at,
        updated_at
    )
    SELECT
        v_org_id,
        v_node_ny,
        gn.id,
        'primary_parent',
        'active',
        true,
        v_today,
        v_now,
        v_now
    FROM _sections_staging s
    JOIN public.governance_nodes gn ON gn.organization_id = v_org_id AND gn.code = s.code
    ON CONFLICT (organization_id, child_node_id)
      WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
    DO NOTHING;

    ----------------------------------------------------------------------------
    -- B. CREATE TAG 'fmc'
    --    name: "FMC"
    --    description: "Familias Misioneras de Cristo — Spanish-speaking community"
    --    data_classification_code: 'community' (P2 Community)
    ----------------------------------------------------------------------------
    INSERT INTO public.tags (
        organization_id,
        code,
        name,
        description,
        data_classification_code,
        is_active,
        display_order,
        created_at,
        updated_at
    ) VALUES (
        v_org_id,
        'fmc',
        'FMC',
        'Familias Misioneras de Cristo — Spanish-speaking community',
        'community',
        true,
        1,
        v_now,
        v_now
    )
    ON CONFLICT (organization_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        data_classification_code = EXCLUDED.data_classification_code,
        is_active = true,
        updated_at = v_now
    RETURNING id INTO v_tag_id;

    ----------------------------------------------------------------------------
    -- E. RECORD SUMMARY AUDIT EVENTS
    ----------------------------------------------------------------------------
    INSERT INTO audit.events (
        organization_id,
        event_code,
        event_category,
        entity_type,
        entity_id,
        action,
        outcome,
        metadata
    ) VALUES
    (
        v_org_id,
        'governance.sections_created',
        'governance',
        'governance_node',
        v_org_id,
        'create_sections_foundation',
        'success',
        jsonb_build_object(
            'migration', '20261010033000_sections_and_fmc_tag_foundation',
            'sections_created', v_sections_created,
            'section_codes', jsonb_build_array(
                'sec_couples', 'sec_handmaids', 'sec_servants', 'sec_singles',
                'sec_campus', 'sec_youth', 'sec_kids'
            )
        )
    ),
    (
        v_org_id,
        'tag.created',
        'governance',
        'tag',
        v_org_id,
        'create_fmc_tag',
        'success',
        jsonb_build_object(
            'migration', '20261010033000_sections_and_fmc_tag_foundation',
            'tag_code', 'fmc',
            'tag_name', 'FMC',
            'classification', 'community'
        )
    );

    RAISE NOTICE 'Pass 4.6S migration completed: sections_created=%', v_sections_created;
END $$;

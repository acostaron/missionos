-- Migration 100: Governance structure correction and legacy placement reset
-- Label: governance_structure_correction_and_legacy_placement_reset
-- Contiguous timestamp: 20261010032000

DO $$
DECLARE
    v_households_count integer;
    v_household_memberships_count integer;
    v_active_leadership_count integer;
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
    v_type_unit uuid;
    v_rvc_id uuid;
    v_bq_id uuid;
    v_nyc_id uuid;
    v_alb_id uuid;
    v_today date := CURRENT_DATE;
    v_now timestamptz := clock_timestamp();
    v_units_created integer := 0;
    v_placements_ended integer := 0;
    v_units_retired integer := 0;
BEGIN
    ----------------------------------------------------------------------------
    -- GUARD: Abort if households, household_memberships, or active leadership exist
    ----------------------------------------------------------------------------
    SELECT count(*) INTO v_households_count FROM public.households;
    SELECT count(*) INTO v_household_memberships_count FROM public.household_memberships;
    SELECT count(*) INTO v_active_leadership_count 
    FROM public.leadership_assignments 
    WHERE assignment_status = 'active';

    IF v_households_count > 0 THEN
        RAISE EXCEPTION 'Guard failed: households table is non-empty (count=%)', v_households_count;
    END IF;

    IF v_household_memberships_count > 0 THEN
        RAISE EXCEPTION 'Guard failed: household_memberships table is non-empty (count=%)', v_household_memberships_count;
    END IF;

    IF v_active_leadership_count > 0 THEN
        RAISE EXCEPTION 'Guard failed: active leadership_assignments exist (count=%)', v_active_leadership_count;
    END IF;

    ----------------------------------------------------------------------------
    -- RESOLVE UNIT TYPE AND CHAPTER NODE IDs
    ----------------------------------------------------------------------------
    SELECT id INTO STRICT v_type_unit
    FROM public.governance_node_types
    WHERE organization_id = v_org_id AND code = 'unit';

    SELECT id INTO STRICT v_rvc_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'rvc';
    SELECT id INTO STRICT v_bq_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'bq';
    SELECT id INTO STRICT v_nyc_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'nyc';
    SELECT id INTO STRICT v_alb_id FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'alb';

    ----------------------------------------------------------------------------
    -- A. CREATE 8 UNIT NODES (idempotent by organization_id + code)
    --    rvc_nassau, rvc_suffolk, bq_brooklyn, bq_queens,
    --    nyc_bronx, nyc_manhattan, nyc_staten_island, alb_albany
    ----------------------------------------------------------------------------
    CREATE TEMP TABLE _new_units_staging (
        code text PRIMARY KEY,
        name text NOT NULL,
        parent_id uuid NOT NULL
    ) ON COMMIT DROP;

    INSERT INTO _new_units_staging (code, name, parent_id) VALUES
        ('rvc_nassau', 'Nassau Unit', v_rvc_id),
        ('rvc_suffolk', 'Suffolk Unit', v_rvc_id),
        ('bq_brooklyn', 'Brooklyn Unit', v_bq_id),
        ('bq_queens', 'Queens Unit', v_bq_id),
        ('nyc_bronx', 'Bronx Unit', v_nyc_id),
        ('nyc_manhattan', 'Manhattan Unit', v_nyc_id),
        ('nyc_staten_island', 'Staten Island Unit', v_nyc_id),
        ('alb_albany', 'Albany Unit', v_alb_id);

    -- Insert governance_nodes
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
        v_type_unit,
        s.code,
        s.name,
        'active',
        v_today,
        v_now,
        v_now
    FROM _new_units_staging s
    ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
    DO UPDATE SET
        name = EXCLUDED.name,
        lifecycle_status = 'active',
        updated_at = v_now;

    GET DIAGNOSTICS v_units_created = ROW_COUNT;

    -- Insert units detail records
    INSERT INTO public.units (id, organization_id, created_at, updated_at)
    SELECT gn.id, v_org_id, v_now, v_now
    FROM _new_units_staging s
    JOIN public.governance_nodes gn ON gn.organization_id = v_org_id AND gn.code = s.code
    ON CONFLICT (id) DO NOTHING;

    -- Insert governance_node_relationships (chapter -> unit)
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
        s.parent_id,
        gn.id,
        'primary_parent',
        'active',
        true,
        v_today,
        v_now,
        v_now
    FROM _new_units_staging s
    JOIN public.governance_nodes gn ON gn.organization_id = v_org_id AND gn.code = s.code
    ON CONFLICT (organization_id, child_node_id)
      WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
    DO NOTHING;

    ----------------------------------------------------------------------------
    -- B. END EVERY LEGACY ACTIVE PRIMARY PLACEMENT
    --    effective_to = migration date, ending_reason = 'legacy_import_unverified'
    --    APP placements untouched.
    ----------------------------------------------------------------------------
    WITH ended_placements AS (
        UPDATE public.member_governance_assignments
        SET
            assignment_status = 'ended',
            effective_to = v_today,
            ending_reason = 'legacy_import_unverified',
            updated_at = v_now
        WHERE assignment_basis = 'import'
          AND is_primary = true
          AND assignment_status = 'active'
        RETURNING id
    )
    SELECT count(*) INTO v_placements_ended FROM ended_placements;

    ----------------------------------------------------------------------------
    -- C. RETIRE rvc_u01 AND rvc_u02
    --    Guard: ensure no active placements remain on them
    ----------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM public.member_governance_assignments mga
        JOIN public.governance_nodes gn ON gn.id = mga.governance_node_id
        WHERE gn.code IN ('rvc_u01', 'rvc_u02')
          AND mga.assignment_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Cannot retire rvc_u01/rvc_u02: active placements still exist on them';
    END IF;

    -- End relationships for rvc_u01 and rvc_u02
    UPDATE public.governance_node_relationships
    SET relationship_status = 'ended',
        effective_to = v_today,
        ended_at = v_now,
        ending_reason = 'retired_unverified_legacy_unit',
        updated_at = v_now
    WHERE child_node_id IN (
        SELECT id FROM public.governance_nodes WHERE organization_id = v_org_id AND code IN ('rvc_u01', 'rvc_u02')
    ) AND relationship_status = 'active';

    -- Archive nodes rvc_u01 and rvc_u02
    WITH retired_nodes AS (
        UPDATE public.governance_nodes
        SET lifecycle_status = 'archived',
            effective_to = v_today,
            archived_at = v_now,
            archive_reason = 'retired_unverified_legacy_unit',
            updated_at = v_now
        WHERE organization_id = v_org_id
          AND code IN ('rvc_u01', 'rvc_u02')
          AND lifecycle_status <> 'archived'
        RETURNING id
    )
    SELECT count(*) INTO v_units_retired FROM retired_nodes;

    ----------------------------------------------------------------------------
    -- D. staging.chapter_unit_mapping
    --    Constraint ck_chapter_unit_mapping__mapping_status only permits:
    --    ('pending', 'mapped', 'no_v2_equivalent', 'deferred').
    --    Per requirements rule 2.D, leave unchanged because constraint forbids
    --    'superseded' / 'invalid'.
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- E. AUDIT: Record summary audit events in audit.events
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
        'governance.structure_updated',
        'governance',
        'governance_node',
        v_org_id,
        'create_canonical_units',
        'success',
        jsonb_build_object(
            'migration', '20261010032000_governance_structure_correction_and_legacy_placement_reset',
            'units_created', v_units_created,
            'unit_codes', jsonb_build_array(
                'rvc_nassau', 'rvc_suffolk', 'bq_brooklyn', 'bq_queens',
                'nyc_bronx', 'nyc_manhattan', 'nyc_staten_island', 'alb_albany'
            )
        )
    ),
    (
        v_org_id,
        'governance.placements_reset',
        'governance',
        'member_governance_assignment',
        v_org_id,
        'end_legacy_placements',
        'success',
        jsonb_build_object(
            'migration', '20261010032000_governance_structure_correction_and_legacy_placement_reset',
            'placements_ended', v_placements_ended,
            'ending_reason', 'legacy_import_unverified'
        )
    ),
    (
        v_org_id,
        'governance.units_retired',
        'governance',
        'governance_node',
        v_org_id,
        'retire_placeholder_units',
        'success',
        jsonb_build_object(
            'migration', '20261010032000_governance_structure_correction_and_legacy_placement_reset',
            'units_retired', v_units_retired,
            'unit_codes', jsonb_build_array('rvc_u01', 'rvc_u02')
        )
    );

    RAISE NOTICE 'Pass 4.6A migration completed: units_created=%, placements_ended=%, units_retired=%',
        v_units_created, v_placements_ended, v_units_retired;
END $$;

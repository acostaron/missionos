-- =============================================================================
-- Phase 4.5B Migration I: MFCNY Governance Tree
-- File:    20260904000000_phase_4_5b_governance_tree.sql
-- Phase:   4.5B — Governance Node Mapping & Member Placement Import (tree only)
-- Scope:   MFCNY  organization_id = 22efefb6-2858-4629-ace6-66ea4e20cfdf
--
-- Creates:
--   7  governance_nodes   (1 area_state, 4 chapter, 2 unit)
--   4  chapters           (detail records for each chapter node)
--   2  units              (detail records for each unit node)
--   6  governance_node_relationships  (area→4 chapters, rvc→2 units)
--   6  staging.chapter_unit_mapping  (legacy→canonical ID mapping)
--
-- Does NOT create:
--   member_governance_assignments
--   household nodes / household detail records
--   section nodes / section detail records
--   any contact, family, or relationship data
--   any member cache updates (no placement trigger will fire)
--
-- Idempotency:
--   governance_nodes         ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
--   chapters / units         ON CONFLICT (id)
--   governance_node_relationships  ON CONFLICT partial index ux_governance_node_relationships__current_primary_parent
--   staging.chapter_unit_mapping   ON CONFLICT (source_system, source_node_id)
--
-- Code format note:
--   governance_nodes.code is constrained to ^[a-z][a-z0-9_]*$
--   (lowercase letters, digits, underscores only — no uppercase, no hyphens).
--   Requested codes stored in this file as constraint-compliant forms:
--     NY       → ny
--     BQ       → bq
--     RVC      → rvc
--     NYC      → nyc
--     ALB      → alb
--     RVC-U01  → rvc_u01   (hyphen replaced with underscore)
--     RVC-U02  → rvc_u02   (hyphen replaced with underscore)
--
-- Type resolution:
--   Governance node type IDs are resolved at runtime by authoritative code.
--   They are never hardcoded.
--
-- Live schema confirmed before writing:
--   governance_node_types: area_state rank=30, chapter rank=50, unit rank=60
--   chapters PK (id), FK (organization_id, id) → governance_nodes(organization_id, id)
--   units    PK (id), FK (organization_id, id) → governance_nodes(organization_id, id)
--   governance_node_relationships partial unique: (org, child_node_id)
--     WHERE is_primary AND relationship_status='active' AND effective_to IS NULL
--   staging.chapter_unit_mapping unique: (source_system, source_node_id)
--   private.validate_governance_detail_type() — BEFORE INSERT on chapters, units
-- =============================================================================

DO $$
DECLARE
  -- -------------------------------------------------------------------------
  -- Organization
  -- -------------------------------------------------------------------------
  v_org_id uuid;

  -- -------------------------------------------------------------------------
  -- Governance node type IDs — resolved at runtime by authoritative code.
  -- SELECT INTO STRICT will raise NO_DATA_FOUND if code is missing.
  -- -------------------------------------------------------------------------
  v_type_area_state uuid;
  v_type_chapter    uuid;
  v_type_unit       uuid;

  -- -------------------------------------------------------------------------
  -- Governance node IDs — resolved after idempotent INSERT by stable code.
  -- -------------------------------------------------------------------------
  v_node_ny    uuid;   -- MFC New York Area         (area_state, code: ny)
  v_node_bq    uuid;   -- Brooklyn Queens Chapter   (chapter,    code: bq)
  v_node_rvc   uuid;   -- Rockville Center Chapter  (chapter,    code: rvc)
  v_node_nyc   uuid;   -- New York Chapter          (chapter,    code: nyc)
  v_node_alb   uuid;   -- Albany Chapter            (chapter,    code: alb)
  v_node_ru01  uuid;   -- Rockville Center Unit 1   (unit,       code: rvc_u01)
  v_node_ru02  uuid;   -- Rockville Center Unit 2   (unit,       code: rvc_u02)

BEGIN

  -- ===========================================================================
  -- STEP 0: Resolve governance_node_type IDs by authoritative code
  -- ===========================================================================
  v_org_id := '22efefb6-2858-4629-ace6-66ea4e20cfdf';

  SELECT id
    INTO STRICT v_type_area_state
    FROM public.governance_node_types
   WHERE organization_id = v_org_id
     AND code = 'area_state';

  SELECT id
    INTO STRICT v_type_chapter
    FROM public.governance_node_types
   WHERE organization_id = v_org_id
     AND code = 'chapter';

  SELECT id
    INTO STRICT v_type_unit
    FROM public.governance_node_types
   WHERE organization_id = v_org_id
     AND code = 'unit';

  -- ===========================================================================
  -- STEP 1: Insert governance nodes (idempotent by organization_id + code)
  -- ===========================================================================

  -- Area/State: MFC New York Area
  INSERT INTO public.governance_nodes
    (organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES
    (v_org_id, v_type_area_state, 'ny', 'MFC New York Area', 'active', DATE '2026-09-03')
  ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
  DO NOTHING;

  -- Chapter: Brooklyn Queens Chapter
  INSERT INTO public.governance_nodes
    (organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES
    (v_org_id, v_type_chapter, 'bq', 'Brooklyn Queens Chapter', 'active', DATE '2026-09-03')
  ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
  DO NOTHING;

  -- Chapter: Rockville Center Chapter
  INSERT INTO public.governance_nodes
    (organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES
    (v_org_id, v_type_chapter, 'rvc', 'Rockville Center Chapter', 'active', DATE '2026-09-03')
  ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
  DO NOTHING;

  -- Chapter: New York Chapter
  INSERT INTO public.governance_nodes
    (organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES
    (v_org_id, v_type_chapter, 'nyc', 'New York Chapter', 'active', DATE '2026-09-03')
  ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
  DO NOTHING;

  -- Chapter: Albany Chapter
  INSERT INTO public.governance_nodes
    (organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES
    (v_org_id, v_type_chapter, 'alb', 'Albany Chapter', 'active', DATE '2026-09-03')
  ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
  DO NOTHING;

  -- Unit: Rockville Center Unit 1  (requested code RVC-U01 → constraint form: rvc_u01)
  INSERT INTO public.governance_nodes
    (organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES
    (v_org_id, v_type_unit, 'rvc_u01', 'Rockville Center Unit 1', 'active', DATE '2026-09-03')
  ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
  DO NOTHING;

  -- Unit: Rockville Center Unit 2  (requested code RVC-U02 → constraint form: rvc_u02)
  INSERT INTO public.governance_nodes
    (organization_id, governance_node_type_id, code, name, lifecycle_status, effective_from)
  VALUES
    (v_org_id, v_type_unit, 'rvc_u02', 'Rockville Center Unit 2', 'active', DATE '2026-09-03')
  ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
  DO NOTHING;

  -- ===========================================================================
  -- STEP 2: Resolve node IDs by stable code lookup (after idempotent INSERT)
  --
  -- STRICT ensures we fail fast if any node is missing — which would indicate
  -- the INSERT in Step 1 failed silently.
  -- ===========================================================================

  SELECT id INTO STRICT v_node_ny
    FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'ny';

  SELECT id INTO STRICT v_node_bq
    FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'bq';

  SELECT id INTO STRICT v_node_rvc
    FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'rvc';

  SELECT id INTO STRICT v_node_nyc
    FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'nyc';

  SELECT id INTO STRICT v_node_alb
    FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'alb';

  SELECT id INTO STRICT v_node_ru01
    FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'rvc_u01';

  SELECT id INTO STRICT v_node_ru02
    FROM public.governance_nodes WHERE organization_id = v_org_id AND code = 'rvc_u02';

  -- ===========================================================================
  -- STEP 3: Insert chapter detail records
  --
  -- private.validate_governance_detail_type() fires BEFORE INSERT on chapters.
  -- It verifies:
  --   (a) governance_node with matching (id, organization_id) exists
  --   (b) that node's type has detail_table_name = 'chapters'
  -- The governance_nodes were inserted in Step 1, so both checks pass.
  --
  -- Idempotency: ON CONFLICT (id) DO NOTHING  [pk_chapters: PRIMARY KEY (id)]
  -- ===========================================================================

  INSERT INTO public.chapters (id, organization_id)
  VALUES
    (v_node_bq,  v_org_id),   -- Brooklyn Queens Chapter
    (v_node_rvc, v_org_id),   -- Rockville Center Chapter
    (v_node_nyc, v_org_id),   -- New York Chapter
    (v_node_alb, v_org_id)    -- Albany Chapter
  ON CONFLICT (id)
  DO NOTHING;

  -- ===========================================================================
  -- STEP 4: Insert unit detail records
  --
  -- Same trigger validates these ids reference unit-typed nodes.
  -- Idempotency: ON CONFLICT (id) DO NOTHING  [pk_units: PRIMARY KEY (id)]
  -- ===========================================================================

  INSERT INTO public.units (id, organization_id)
  VALUES
    (v_node_ru01, v_org_id),  -- Rockville Center Unit 1
    (v_node_ru02, v_org_id)   -- Rockville Center Unit 2
  ON CONFLICT (id)
  DO NOTHING;

  -- ===========================================================================
  -- STEP 5: Create governance hierarchy relationships
  --
  -- Relationship type: primary_parent
  --   Trigger validate_governance_relationship() enforces:
  --   parent.hierarchy_rank < child.hierarchy_rank  (numerically lower = higher in tree)
  --   area_state (30) < chapter (50) < unit (60) — satisfies all six relationships.
  --
  -- Idempotency uses partial unique index:
  --   ux_governance_node_relationships__current_primary_parent
  --   ON (organization_id, child_node_id)
  --   WHERE is_primary AND relationship_status='active' AND effective_to IS NULL
  -- ===========================================================================

  -- MFC New York Area → Brooklyn Queens Chapter
  INSERT INTO public.governance_node_relationships
    (organization_id, parent_node_id, child_node_id,
     relationship_type, relationship_status, is_primary, effective_from)
  VALUES
    (v_org_id, v_node_ny, v_node_bq,
     'primary_parent', 'active', true, DATE '2026-09-03')
  ON CONFLICT (organization_id, child_node_id)
    WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
  DO NOTHING;

  -- MFC New York Area → Rockville Center Chapter
  INSERT INTO public.governance_node_relationships
    (organization_id, parent_node_id, child_node_id,
     relationship_type, relationship_status, is_primary, effective_from)
  VALUES
    (v_org_id, v_node_ny, v_node_rvc,
     'primary_parent', 'active', true, DATE '2026-09-03')
  ON CONFLICT (organization_id, child_node_id)
    WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
  DO NOTHING;

  -- MFC New York Area → New York Chapter
  INSERT INTO public.governance_node_relationships
    (organization_id, parent_node_id, child_node_id,
     relationship_type, relationship_status, is_primary, effective_from)
  VALUES
    (v_org_id, v_node_ny, v_node_nyc,
     'primary_parent', 'active', true, DATE '2026-09-03')
  ON CONFLICT (organization_id, child_node_id)
    WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
  DO NOTHING;

  -- MFC New York Area → Albany Chapter
  INSERT INTO public.governance_node_relationships
    (organization_id, parent_node_id, child_node_id,
     relationship_type, relationship_status, is_primary, effective_from)
  VALUES
    (v_org_id, v_node_ny, v_node_alb,
     'primary_parent', 'active', true, DATE '2026-09-03')
  ON CONFLICT (organization_id, child_node_id)
    WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
  DO NOTHING;

  -- Rockville Center Chapter → Rockville Center Unit 1
  INSERT INTO public.governance_node_relationships
    (organization_id, parent_node_id, child_node_id,
     relationship_type, relationship_status, is_primary, effective_from)
  VALUES
    (v_org_id, v_node_rvc, v_node_ru01,
     'primary_parent', 'active', true, DATE '2026-09-03')
  ON CONFLICT (organization_id, child_node_id)
    WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
  DO NOTHING;

  -- Rockville Center Chapter → Rockville Center Unit 2
  INSERT INTO public.governance_node_relationships
    (organization_id, parent_node_id, child_node_id,
     relationship_type, relationship_status, is_primary, effective_from)
  VALUES
    (v_org_id, v_node_rvc, v_node_ru02,
     'primary_parent', 'active', true, DATE '2026-09-03')
  ON CONFLICT (organization_id, child_node_id)
    WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
  DO NOTHING;

  -- ===========================================================================
  -- STEP 6: Populate staging.chapter_unit_mapping
  --
  -- Maps all six legacy source UUIDs to their canonical V2 governance nodes.
  -- Idempotency: UNIQUE (source_system, source_node_id)
  -- ===========================================================================

  INSERT INTO staging.chapter_unit_mapping
    (source_system, source_node_id, source_node_type, source_node_name,
     canonical_governance_node_id, mapping_status, mapped_at)
  VALUES
    ('mfc_legacy',
     '24c53884-cd0e-47b5-82ef-e7f34b0cff8b',
     'chapter', 'Brooklyn Queens Chapter',
     v_node_bq, 'mapped', now()),

    ('mfc_legacy',
     '2938d7f2-4023-413f-99f5-941854d39b40',
     'chapter', 'Rockville Center Chapter',
     v_node_rvc, 'mapped', now()),

    ('mfc_legacy',
     '3973b59a-310a-49a1-8def-fb5bbdab14ad',
     'chapter', 'New York Chapter',
     v_node_nyc, 'mapped', now()),

    ('mfc_legacy',
     '5d93d362-1813-41f6-9d32-d6fb363540f0',
     'chapter', 'Albany Chapter',
     v_node_alb, 'mapped', now()),

    ('mfc_legacy',
     '933c1b31-ae5d-4b11-b9d8-c472a7bd1172',
     'unit', 'Rockville Center Unit 1',
     v_node_ru01, 'mapped', now()),

    ('mfc_legacy',
     'fc50e31f-e237-4b03-91b4-9c01ceb9235e',
     'unit', 'Rockville Center Unit 2',
     v_node_ru02, 'mapped', now())

  ON CONFLICT (source_system, source_node_id)
  DO NOTHING;

END $$;

-- =============================================================================
-- Phase 4.5B Migration J: MFCNY Member Governance Placements
-- File:    20260904010000_phase_4_5b_member_placements.sql
-- Phase:   4.5B — Governance Node Mapping & Member Placement Import (placements)
-- Scope:   MFCNY  organization_id = 22efefb6-2858-4629-ace6-66ea4e20cfdf
--
-- Creates:
--   313  member_governance_assignments  (313 active primary import placements)
--        automatically populates members.primary_governance_node_id via trigger
--
-- Distribution:
--   311  chapter-only members → placed at their mapped chapter node
--     2  unit-assigned members → placed at their mapped unit node (chapter ancestry
--        is inherited through governance_node_relationships; no redundant chapter row)
--     2  unplaced members (both source IDs null) → 0 assignments created
--
-- Does NOT:
--   create governance nodes
--   modify the governance tree
--   write members.primary_governance_node_id directly (trigger handles it)
--   touch contacts, families, sequences, or member identifiers
--
-- Placement selection logic:
--   Unit precedence: COALESCE(source_unit_id, source_chapter_id)
--   Resolved via staging.chapter_unit_mapping (source_system = 'mfc_legacy',
--   mapping_status = 'mapped')
--
-- Assignment parameters:
--   assignment_type   = 'primary'
--   assignment_basis  = 'import'
--   assignment_status = 'active'
--   is_primary        = true
--   effective_from    = DATE '2026-09-03'
--   effective_to      = NULL
--
-- Idempotency:
--   ON CONFLICT on partial unique index:
--   ux_member_governance_assignments__current_primary
--   → (organization_id, member_id)
--      WHERE is_primary AND assignment_status='active' AND effective_to IS NULL
--   → DO NOTHING on conflict (safe to re-run)
--
-- Abort conditions (enforced before any insert):
--   - any source chapter/unit ID that is non-null but has no staged mapping
--   - any canonical_member_id IS NULL for a member that has a source placement ID
--   - any existing active primary assignments (pre-existing conflict detection)
--
-- Cache behavior:
--   private.sync_member_placement_cache() fires AFTER INSERT on
--   member_governance_assignments. It sets members.primary_governance_node_id
--   automatically. Do NOT write that column manually.
--
-- Column type notes (confirmed pre-write):
--   staging.legacy_members.source_chapter_id  → text
--   staging.legacy_members.source_unit_id     → text
--   staging.chapter_unit_mapping.source_node_id → text
--   No cast required for the staging join.
-- =============================================================================

DO $$
DECLARE
  v_org_id             uuid;
  v_missing_mappings   int;
  v_null_canonical     int;
  v_existing_primary   int;
  v_inserted           int;
BEGIN
  v_org_id := '22efefb6-2858-4629-ace6-66ea4e20cfdf';

  -- ===========================================================================
  -- GUARD 1: No canonical_member_id IS NULL for members that have a source
  --          placement ID (chapter or unit).
  -- ===========================================================================
  SELECT COUNT(*)
    INTO v_null_canonical
    FROM staging.legacy_members lm
   WHERE lm.canonical_member_id IS NULL
     AND (lm.source_chapter_id IS NOT NULL OR lm.source_unit_id IS NOT NULL);

  IF v_null_canonical > 0 THEN
    RAISE EXCEPTION
      'ABORT: % legacy member row(s) have a source placement ID but no canonical_member_id. '
      'Resolve these rows in staging before running Migration J.',
      v_null_canonical;
  END IF;

  -- ===========================================================================
  -- GUARD 2: Every non-null source chapter/unit ID has a mapped canonical node.
  -- Checks both unit IDs and chapter IDs separately to give precise error message.
  -- ===========================================================================

  -- Check unit IDs
  SELECT COUNT(*)
    INTO v_missing_mappings
    FROM staging.legacy_members lm
   WHERE lm.canonical_member_id IS NOT NULL
     AND lm.source_unit_id IS NOT NULL
     AND NOT EXISTS (
           SELECT 1
             FROM staging.chapter_unit_mapping m
            WHERE m.source_system  = 'mfc_legacy'
              AND m.source_node_id = lm.source_unit_id
              AND m.mapping_status = 'mapped'
         );

  IF v_missing_mappings > 0 THEN
    RAISE EXCEPTION
      'ABORT: % source_unit_id value(s) have no mapped canonical governance node in '
      'staging.chapter_unit_mapping. Populate the mapping table before running Migration J.',
      v_missing_mappings;
  END IF;

  -- Check chapter IDs (for chapter-only members — unit=null, chapter=non-null)
  SELECT COUNT(*)
    INTO v_missing_mappings
    FROM staging.legacy_members lm
   WHERE lm.canonical_member_id IS NOT NULL
     AND lm.source_unit_id IS NULL
     AND lm.source_chapter_id IS NOT NULL
     AND NOT EXISTS (
           SELECT 1
             FROM staging.chapter_unit_mapping m
            WHERE m.source_system  = 'mfc_legacy'
              AND m.source_node_id = lm.source_chapter_id
              AND m.mapping_status = 'mapped'
         );

  IF v_missing_mappings > 0 THEN
    RAISE EXCEPTION
      'ABORT: % source_chapter_id value(s) have no mapped canonical governance node in '
      'staging.chapter_unit_mapping. Populate the mapping table before running Migration J.',
      v_missing_mappings;
  END IF;

  -- ===========================================================================
  -- GUARD 3: No pre-existing active primary assignments exist for MFCNY.
  --          On a clean first run this must be 0.
  --          On idempotent re-run the ON CONFLICT will handle existing rows;
  --          this guard only fires if we somehow have assignments that are NOT
  --          from this import (unexpected state).
  --
  --          We check for existing active primary assignments whose basis is
  --          NOT 'import' — those would represent a conflict we cannot silently
  --          skip.
  -- ===========================================================================
  SELECT COUNT(*)
    INTO v_existing_primary
    FROM public.member_governance_assignments mga
   WHERE mga.organization_id   = v_org_id
     AND mga.is_primary        = true
     AND mga.assignment_status = 'active'
     AND mga.effective_to      IS NULL
     AND mga.assignment_basis  <> 'import';

  IF v_existing_primary > 0 THEN
    RAISE EXCEPTION
      'ABORT: % active primary assignment(s) with basis != ''import'' already exist for MFCNY. '
      'Investigate before proceeding.',
      v_existing_primary;
  END IF;

  -- ===========================================================================
  -- STEP 1: Insert governance assignments
  --
  -- Selection logic:
  --   COALESCE(source_unit_id, source_chapter_id) gives unit precedence.
  --   Join to staging.chapter_unit_mapping on that value (both columns are text).
  --   Members where both are NULL (unplaced) produce no JOIN match → excluded.
  --   Members where canonical_member_id IS NULL → excluded by WHERE clause.
  --
  -- Idempotency:
  --   Partial unique index ux_member_governance_assignments__current_primary
  --   enforces (organization_id, member_id) uniqueness for active primary rows.
  --   ON CONFLICT ... DO NOTHING is safe; if the row already exists with the
  --   same node and parameters, the re-run is a no-op.
  -- ===========================================================================

  INSERT INTO public.member_governance_assignments
    (organization_id,
     member_id,
     governance_node_id,
     assignment_type,
     assignment_basis,
     assignment_status,
     is_primary,
     effective_from,
     effective_to)
  SELECT
    v_org_id,
    lm.canonical_member_id,
    m.canonical_governance_node_id,
    'primary',
    'import',
    'active',
    true,
    DATE '2026-09-03',
    NULL
  FROM staging.legacy_members lm
  JOIN staging.chapter_unit_mapping m
    ON  m.source_system  = 'mfc_legacy'
    AND m.source_node_id = COALESCE(lm.source_unit_id, lm.source_chapter_id)
    AND m.mapping_status = 'mapped'
  WHERE lm.canonical_member_id IS NOT NULL
  ON CONFLICT (organization_id, member_id)
    WHERE is_primary AND assignment_status = 'active' AND effective_to IS NULL
  DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  RAISE NOTICE 'Migration J: % member_governance_assignment row(s) inserted.', v_inserted;

END $$;

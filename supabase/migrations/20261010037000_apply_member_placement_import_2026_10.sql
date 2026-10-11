-- Migration 105: apply_member_placement_import_2026_10
-- Timestamp: 20261010037000
-- Purpose: Apply member placement import batch mfcny_placement_2026_10

DO $$
DECLARE
    v_total_rows int;
    v_unapplied_rows int;
    v_result jsonb;
BEGIN
    -- Guard: batch has exactly 315 rows and applied_at is null for all
    SELECT count(*), count(*) FILTER (WHERE applied_at IS NULL)
    INTO v_total_rows, v_unapplied_rows
    FROM staging.member_placement_import
    WHERE import_batch_code = 'mfcny_placement_2026_10';

    IF v_total_rows <> 315 THEN
        RAISE EXCEPTION 'Guard failed: expected exactly 315 rows in batch mfcny_placement_2026_10, found %', v_total_rows;
    END IF;

    IF v_unapplied_rows <> 315 THEN
        RAISE EXCEPTION 'Guard failed: expected exactly 315 unapplied rows in batch mfcny_placement_2026_10, found %', v_unapplied_rows;
    END IF;

    -- Apply batch
    SELECT private.apply_member_placement_import('mfcny_placement_2026_10') INTO v_result;

    IF v_result->>'status' <> 'success' THEN
        RAISE EXCEPTION 'Batch application failed with result: %', v_result;
    END IF;
END $$;

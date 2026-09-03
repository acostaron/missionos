-- =============================================================================
-- Migration H: Phase 4.5 — Member Number Sequence Reconciliation
-- File:        20260903070000_phase_4_5_sequence_reconciliation.sql
-- =============================================================================
--
-- PURPOSE
-- -------
-- After the legacy import, the MFCNY member_number sequence still reads
-- current_value = 0. The highest issued number is NY10553. Any new member
-- allocated via the normal sequence flow would incorrectly receive NY00001.
--
-- This migration advances current_value to the highest suffix currently in use
-- so that the next generated number is NY10554.
--
-- SEQUENCE ROW
-- ------------
--   organization_id = 22efefb6-2858-4629-ace6-66ea4e20cfdf
--   sequence_code   = 'member_number'
--   prefix          = 'NY'
--   minimum_digits  = 5
--   current_value   = 0  (before this migration)
--   increment_by    = 1
--   reset_policy    = 'never'
--
-- COMPUTATION
-- -----------
-- The new current_value is computed dynamically as:
--
--   MAX( CAST( SUBSTRING(identifier_value FROM 3) AS bigint ) )
--   FROM public.member_identifiers
--   WHERE organization_id = MFCNY
--     AND identifier_type = 'member_number'
--     AND is_primary      = true
--     AND effective_to    IS NULL
--     AND identifier_value ~ '^NY[0-9]+$'
--
-- Expected result: 10553  (= NY10553, the highest allocated number)
-- Therefore: current_value → 10553, next issued = NY10554
--
-- FORWARD-ONLY / IDEMPOTENCY
-- --------------------------
-- The UPDATE only advances the sequence:
--   SET current_value = GREATEST(current_value, <computed_max>)
-- Re-running after the value is already 10553 produces no change (GREATEST
-- of equal values is a no-op in effect).
-- Running after a higher value was legitimately issued preserves the higher value.
--
-- TABLES WRITTEN
-- --------------
--   public.number_sequences   (UPDATE: current_value for MFCNY member_number)
--
-- TABLES NOT MODIFIED
-- -------------------
--   public.members
--   public.member_names
--   public.member_identifiers   (read-only — no new numbers assigned)
--   public.member_emails
--   public.member_phones
--   public.addresses, public.member_addresses
--   public.families, public.family_members, public.family_relationships
--   All governance node and placement tables
--   staging.*
--
-- UNNUMBERED MEMBERS
-- ------------------
-- The 6 members with norm_member_code IS NULL are NOT assigned numbers here.
-- Number allocation for them is a separate, explicit future action.
-- =============================================================================


DO $$
DECLARE
  v_org_id          uuid    := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_sequence_code   text    := 'member_number';
  v_prefix          text;
  v_min_digits      int;
  v_current_value   bigint;
  v_computed_max    bigint;
  v_new_value       bigint;
BEGIN
  -- -------------------------------------------------------------------------
  -- 1. Read current sequence row
  -- -------------------------------------------------------------------------
  SELECT current_value, prefix, minimum_digits
    INTO v_current_value, v_prefix, v_min_digits
  FROM public.number_sequences
  WHERE organization_id = v_org_id
    AND sequence_code   = v_sequence_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'number_sequences row not found for org=% code=%', v_org_id, v_sequence_code;
  END IF;

  RAISE NOTICE 'Sequence state BEFORE: current_value=%, prefix=%, minimum_digits=%',
    v_current_value, v_prefix, v_min_digits;

  -- -------------------------------------------------------------------------
  -- 2. Compute highest numeric suffix from live canonical member_number IDs
  -- -------------------------------------------------------------------------
  SELECT MAX(CAST(SUBSTRING(identifier_value FROM LENGTH(v_prefix) + 1) AS bigint))
    INTO v_computed_max
  FROM public.member_identifiers
  WHERE organization_id  = v_org_id
    AND identifier_type  = 'member_number'
    AND is_primary       = true
    AND effective_to     IS NULL
    AND identifier_value ~ ('^' || v_prefix || '[0-9]+$');

  IF v_computed_max IS NULL THEN
    RAISE EXCEPTION
      'No matching member_number identifiers found — cannot compute max suffix.';
  END IF;

  RAISE NOTICE 'Computed max suffix from live identifiers: %', v_computed_max;

  -- -------------------------------------------------------------------------
  -- 3. Compute new value: advance only, never decrement
  -- -------------------------------------------------------------------------
  v_new_value := GREATEST(v_current_value, v_computed_max);

  RAISE NOTICE 'Proposed new current_value: % (was: %)', v_new_value, v_current_value;
  RAISE NOTICE 'Next formatted number will be: %s%',
    v_prefix,
    LPAD((v_new_value + 1)::text, v_min_digits, '0');

  -- -------------------------------------------------------------------------
  -- 4. Update sequence (forward-only)
  -- -------------------------------------------------------------------------
  UPDATE public.number_sequences
  SET current_value = v_new_value
  WHERE organization_id = v_org_id
    AND sequence_code   = v_sequence_code
    AND current_value   < v_new_value;   -- no-op if already at or above target

  IF FOUND THEN
    RAISE NOTICE 'Sequence updated: current_value → %', v_new_value;
  ELSE
    RAISE NOTICE 'Sequence already at or above target (%). No change made.', v_new_value;
  END IF;

END;
$$;


-- ---------------------------------------------------------------------------
-- Summary report
-- ---------------------------------------------------------------------------
SELECT
  ns.sequence_code,
  ns.prefix,
  ns.current_value,
  ns.minimum_digits,
  ns.increment_by,
  -- Next number that would be issued
  ns.prefix || LPAD((ns.current_value + ns.increment_by)::text, ns.minimum_digits, '0') AS next_number,
  -- Computed max from live identifiers (for cross-check)
  (SELECT MAX(CAST(SUBSTRING(mi.identifier_value FROM LENGTH(ns.prefix) + 1) AS bigint))
   FROM public.member_identifiers mi
   WHERE mi.organization_id  = ns.organization_id
     AND mi.identifier_type  = 'member_number'
     AND mi.is_primary       = true
     AND mi.effective_to     IS NULL
     AND mi.identifier_value ~ ('^' || ns.prefix || '[0-9]+$')
  ) AS live_max_suffix,
  -- Other table counts: none should have changed
  (SELECT COUNT(*) FROM public.members
   WHERE organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf')                        AS total_members,
  (SELECT COUNT(*) FROM public.member_identifiers
   WHERE organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf'
     AND identifier_type = 'member_number'
     AND is_primary = true AND effective_to IS NULL)                                       AS member_number_identifiers,
  -- 6 unnumbered members: still have no member_number identifier
  (SELECT COUNT(*) FROM staging.legacy_members lm
   WHERE import_batch_id = (SELECT id FROM staging.import_batches WHERE batch_code='mfcny_legacy_2026_09')
     AND norm_member_code IS NULL)                                                         AS unnumbered_staging_rows,
  (SELECT COUNT(*) FROM public.members m
   WHERE m.organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf'
     AND NOT EXISTS (
       SELECT 1 FROM public.member_identifiers mi
       WHERE mi.member_id = m.id AND mi.organization_id = m.organization_id
         AND mi.identifier_type = 'member_number' AND mi.is_primary = true AND mi.effective_to IS NULL
     )
  )                                                                                        AS canonical_members_without_number
FROM public.number_sequences ns
WHERE ns.organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf'
  AND ns.sequence_code   = 'member_number';


-- ---------------------------------------------------------------------------
-- End of Migration H
-- ---------------------------------------------------------------------------
-- After this migration:
--   number_sequences.current_value = 10553
--   Next issued number             = NY10554
--   6 members remain unnumbered    (intentional — separate future action)
--   No member rows, identifiers, contacts, or relationships were modified.
--
-- Phase 4.5 core migrations complete:
--   C: Staging load
--   D: Staging validation
--   E: Canonical member import
--   F: Contact import (emails + phones)
--   G: Family + relationship import
--   H: Sequence reconciliation  ← this migration
-- ---------------------------------------------------------------------------

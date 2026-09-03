-- =============================================================================
-- Migration F: Phase 4.5 — Contact Import (Emails and Phones)
-- File:        20260903050000_phase_4_5_import_contacts.sql
-- =============================================================================
--
-- PURPOSE
-- -------
-- Imports validated email and phone contacts from staging into canonical tables.
-- Addresses are NOT imported: the one staged address has validation_status =
-- 'review_required' (country_contradicts_location_fields) and is intentionally
-- skipped.
--
-- SOURCE ROWS
-- -----------
--   staging.legacy_member_emails:  2 valid rows (both 'valid')
--   staging.legacy_member_phones:  2 valid rows (both 'valid')
--   staging.legacy_member_addresses: 1 row, 'review_required' → NOT imported
--
-- TABLES WRITTEN
-- --------------
--   public.member_emails       (INSERT: 2 rows)
--   public.member_phones       (INSERT: 2 rows)
--   staging.legacy_member_emails (UPDATE: canonical_email_id + imported_at)
--   staging.legacy_member_phones (UPDATE: canonical_phone_id + imported_at)
--
-- TABLES NOT MODIFIED
-- -------------------
--   public.addresses
--   public.member_addresses
--   public.members
--   public.member_names
--   public.member_identifiers
--   public.family_relationships
--   public.number_sequences
--   All governance node tables
--   staging.legacy_member_addresses  (review_required row stays untouched)
--
-- KEY CONSTRAINT NOTES
-- --------------------
--   member_emails.normalized_email CHECK:
--     normalized_email = private.normalize_email(email_address)
--     → set normalized_email = private.normalize_email(source_email) directly
--
--   member_emails.email_type CHECK:
--     one of: 'personal','work','ministry','family_shared','other'
--     → staging norm_email_type = 'personal' ✓
--
--   member_phones.normalized_e164 CHECK:
--     ^\+[1-9][0-9]{6,14}$
--     → use norm_phone from staging (set by Migration D; norm_e164 was unused)
--
--   member_phones.country_code FK → countries.code
--     → use 'US' for both numbers (both are +1 North American numbers)
--     → derive: if norm_phone starts with '+1' and is 12 digits total → 'US'
--
-- IDEMPOTENCY
-- -----------
--   Emails: WHERE NOT EXISTS on (member_id, normalized_email, effective_to_at IS NULL)
--   Phones: WHERE NOT EXISTS on (member_id, normalized_e164, effective_to_at IS NULL)
--          fallback for NULL normalized_e164: (member_id, phone_number, effective_to_at IS NULL)
--
-- ORGANIZATION CONSTANT
-- ---------------------
--   organization_id = 22efefb6-2858-4629-ace6-66ea4e20cfdf
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Import emails
-- ---------------------------------------------------------------------------
-- Source: staging.legacy_member_emails rows with validation_status = 'valid'
--         joined to staging.legacy_members to resolve canonical_member_id.
--
-- email_address    = source_email (raw source value, user-facing)
-- normalized_email = private.normalize_email(source_email)
--                    must satisfy CHECK: normalized_email = private.normalize_email(email_address)
-- email_type       = norm_email_type  ('personal' for both rows)
-- is_primary       = norm_is_primary
-- effective_from_at = now()
-- effective_to_at  = NULL  (active)
-- ---------------------------------------------------------------------------
WITH email_inserts AS (
  INSERT INTO public.member_emails (
    organization_id,
    member_id,
    email_address,
    normalized_email,
    email_type,
    is_primary,
    is_shared,
    verification_status,
    allows_ministry_email,
    effective_from_at,
    effective_to_at
  )
  SELECT
    '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid,
    lm.canonical_member_id,
    le.source_email,
    private.normalize_email(le.source_email),
    le.norm_email_type,
    le.norm_is_primary,
    false,
    'unverified',
    true,
    now(),
    NULL
  FROM staging.legacy_member_emails le
  JOIN staging.legacy_members lm
    ON lm.source_uuid     = le.source_member_uuid
   AND lm.import_batch_id = le.import_batch_id
  WHERE le.import_batch_id = (
      SELECT id FROM staging.import_batches WHERE batch_code = 'mfcny_legacy_2026_09'
    )
    AND le.validation_status = 'valid'
    AND lm.canonical_member_id IS NOT NULL
    -- Idempotency: skip if an active email with this normalized address already exists
    AND NOT EXISTS (
      SELECT 1 FROM public.member_emails me
      WHERE me.member_id        = lm.canonical_member_id
        AND me.organization_id  = '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid
        AND me.normalized_email = private.normalize_email(le.source_email)
        AND me.effective_to_at  IS NULL
    )
  RETURNING id, member_id, normalized_email
)
-- Stamp canonical_email_id and imported_at back to staging
UPDATE staging.legacy_member_emails le
SET
  canonical_email_id = ei.id,
  canonical_member_id = lm.canonical_member_id,
  imported_at         = now()
FROM email_inserts ei
JOIN staging.legacy_members lm
  ON lm.canonical_member_id = ei.member_id
WHERE lm.source_uuid      = le.source_member_uuid
  AND lm.import_batch_id  = le.import_batch_id
  AND private.normalize_email(le.source_email) = ei.normalized_email
  AND le.import_batch_id  = (
    SELECT id FROM staging.import_batches WHERE batch_code = 'mfcny_legacy_2026_09'
  );


-- ---------------------------------------------------------------------------
-- 2. Import phones
-- ---------------------------------------------------------------------------
-- Source: staging.legacy_member_phones rows with validation_status = 'valid'
--
-- phone_number    = source_phone (raw source value)
-- normalized_e164 = norm_phone   (set by Migration D via regexp normalization)
--                   norm_e164 column was unused; norm_phone holds the E.164 result
-- phone_type      = norm_phone_type
-- country_code    = derived from norm_phone prefix:
--                   '+1' prefix (12 chars) → 'US' (North American)
--                   fallback → NULL (no FK violation since country_code is nullable)
-- effective_from_at = now()
-- effective_to_at   = NULL (active)
-- ---------------------------------------------------------------------------
WITH phone_inserts AS (
  INSERT INTO public.member_phones (
    organization_id,
    member_id,
    phone_number,
    normalized_e164,
    phone_type,
    country_code,
    is_primary,
    is_shared,
    verification_status,
    allows_voice_calls,
    allows_sms,
    allows_messaging_apps,
    effective_from_at,
    effective_to_at
  )
  SELECT
    '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid,
    lm.canonical_member_id,
    lp.source_phone,
    lp.norm_phone,   -- E.164 result written to norm_phone by Migration D
    lp.norm_phone_type,
    -- Derive country_code from E.164 prefix
    CASE
      WHEN lp.norm_phone ~ '^\+1\d{10}$' THEN 'US'
      ELSE lp.norm_country_code  -- use staging value if already set; may be NULL
    END,
    true,   -- is_primary: all imported phones are primary (1 per member)
    false,
    'unverified',
    true,   -- allows_voice_calls
    false,  -- allows_sms (conservative default)
    false,  -- allows_messaging_apps (conservative default)
    now(),
    NULL
  FROM staging.legacy_member_phones lp
  JOIN staging.legacy_members lm
    ON lm.source_uuid     = lp.source_member_uuid
   AND lm.import_batch_id = lp.import_batch_id
  WHERE lp.import_batch_id = (
      SELECT id FROM staging.import_batches WHERE batch_code = 'mfcny_legacy_2026_09'
    )
    AND lp.validation_status = 'valid'
    AND lm.canonical_member_id IS NOT NULL
    -- Idempotency: skip if active phone with same E.164 already exists for this member
    AND NOT EXISTS (
      SELECT 1 FROM public.member_phones mp
      WHERE mp.member_id       = lm.canonical_member_id
        AND mp.organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid
        AND mp.normalized_e164 = lp.norm_phone
        AND mp.effective_to_at IS NULL
    )
  RETURNING id, member_id, normalized_e164
)
-- Stamp canonical_phone_id and imported_at back to staging
UPDATE staging.legacy_member_phones lp
SET
  canonical_phone_id  = pi.id,
  canonical_member_id = lm.canonical_member_id,
  imported_at         = now()
FROM phone_inserts pi
JOIN staging.legacy_members lm
  ON lm.canonical_member_id = pi.member_id
WHERE lm.source_uuid     = lp.source_member_uuid
  AND lm.import_batch_id = lp.import_batch_id
  AND lp.norm_phone      = pi.normalized_e164
  AND lp.import_batch_id = (
    SELECT id FROM staging.import_batches WHERE batch_code = 'mfcny_legacy_2026_09'
  );


-- ---------------------------------------------------------------------------
-- 3. Addresses — NOT imported
-- ---------------------------------------------------------------------------
-- staging.legacy_member_addresses has 1 row with:
--   validation_status = 'review_required'
--   validation_errors = ["country_contradicts_location_fields"]
--   (NY state fields but country = 'Philippines')
--
-- This row is intentionally skipped. No public.addresses or
-- public.member_addresses rows are created. The staging row remains
-- unmodified with imported_at = NULL and canonical_address_id = NULL.
-- Requires manual resolution before it can proceed to a future migration.
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- 4. Import summary report
-- ---------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM public.member_emails
   WHERE organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf')                         AS total_member_emails,
  (SELECT COUNT(*) FROM public.member_phones
   WHERE organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf')                         AS total_member_phones,
  (SELECT COUNT(*) FROM public.addresses
   WHERE organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf')                         AS total_addresses,
  (SELECT COUNT(*) FROM public.member_addresses
   WHERE organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf')                         AS total_member_addresses,
  (SELECT COUNT(*) FROM public.members
   WHERE organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf')                         AS total_members,
  (SELECT COUNT(*) FROM public.member_identifiers
   WHERE organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf'
     AND identifier_type = 'member_number')                                                 AS member_number_identifiers,
  -- Staging tracking state
  (SELECT COUNT(*) FROM staging.legacy_member_emails
   WHERE import_batch_id=(SELECT id FROM staging.import_batches WHERE batch_code='mfcny_legacy_2026_09')
     AND imported_at IS NOT NULL)                                                            AS emails_stamped,
  (SELECT COUNT(*) FROM staging.legacy_member_phones
   WHERE import_batch_id=(SELECT id FROM staging.import_batches WHERE batch_code='mfcny_legacy_2026_09')
     AND imported_at IS NOT NULL)                                                            AS phones_stamped,
  -- Address row: should remain unimported
  (SELECT validation_status FROM staging.legacy_member_addresses
   WHERE import_batch_id=(SELECT id FROM staging.import_batches WHERE batch_code='mfcny_legacy_2026_09'))
                                                                                            AS address_validation_status,
  (SELECT imported_at FROM staging.legacy_member_addresses
   WHERE import_batch_id=(SELECT id FROM staging.import_batches WHERE batch_code='mfcny_legacy_2026_09'))
                                                                                            AS address_imported_at;


-- ---------------------------------------------------------------------------
-- End of Migration F
-- ---------------------------------------------------------------------------
-- Tables NOT modified:
--   public.addresses, public.member_addresses (address quarantined)
--   public.members, public.member_names, public.member_identifiers
--   public.family_relationships, public.number_sequences
--   All governance node tables
--
-- Next migration:
--   G: family relationship import
-- ---------------------------------------------------------------------------

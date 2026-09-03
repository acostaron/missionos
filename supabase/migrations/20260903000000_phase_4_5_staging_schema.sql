-- =============================================================================
-- Migration A: Phase 4.5 — Staging Schema
-- File:        20260903_000000_phase_4_5_staging_schema.sql
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates the staging schema and all tables required for the MFCNY legacy
-- member import (Phase 4.5). Staging tables hold raw source data, normalized
-- values, validation results, and canonical member ID mappings.
--
-- DESIGN PRINCIPLES
-- -----------------
-- 1. Forward-only, idempotent (all objects use IF NOT EXISTS).
-- 2. Staging schema is NOT exposed to PostgREST / authenticated browser access.
--    No GRANT is given to the `anon` or `authenticated` roles.
--    Service-role and migration-role access only.
-- 3. No canonical data (public.*) is written by this migration.
-- 4. No number sequences are modified.
-- 5. No governance nodes are created.
-- 6. No authorization or RLS policy changes.
--
-- SCOPE
-- -----
--   staging.import_batches
--   staging.legacy_members
--   staging.legacy_member_emails
--   staging.legacy_member_phones
--   staging.legacy_member_addresses
--   staging.legacy_member_relationships
--   staging.chapter_unit_mapping
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Schema
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS staging;

-- Revoke default PUBLIC privileges on the staging schema.
-- PostgREST and authenticated/anon roles must not be able to access staging.
REVOKE ALL ON SCHEMA staging FROM PUBLIC;
REVOKE ALL ON SCHEMA staging FROM anon;
REVOKE ALL ON SCHEMA staging FROM authenticated;

COMMENT ON SCHEMA staging IS
  'Staging area for legacy member data import (Phase 4.5 and subsequent import passes). '
  'Not exposed to PostgREST or authenticated browser clients. '
  'Service-role / migration-role access only.';


-- ---------------------------------------------------------------------------
-- 1. staging.import_batches
-- ---------------------------------------------------------------------------
-- Tracks each CSV load execution. One batch per import run.
-- Re-running the same batch is idempotent (child tables use ON CONFLICT).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.import_batches (
  id                       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_code               text        NOT NULL UNIQUE,
  -- e.g. 'mfcny_legacy_2026_09'
  source_system            text        NOT NULL DEFAULT 'mfc_legacy',
  organization_id          uuid        NOT NULL,
  description              text,
  status                   text        NOT NULL DEFAULT 'pending'
    CONSTRAINT ck_import_batches__status
      CHECK (status IN (
        'pending',
        'validating',
        'validated',
        'importing',
        'complete',
        'failed'
      )),
  source_row_counts        jsonb       NOT NULL DEFAULT '{}',
  -- e.g. {"members":315,"emails":2,"phones":2,"addresses":1,"relationships":3}
  started_at               timestamptz,
  completed_at             timestamptz,
  imported_by_profile_id   uuid,
  created_at               timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE staging.import_batches IS
  'One row per legacy import execution. Tracks status and source row counts.';


-- ---------------------------------------------------------------------------
-- 2. staging.legacy_members
-- ---------------------------------------------------------------------------
-- One row per source CSV member row (members_rows.csv).
-- Raw source fields are preserved exactly as loaded from CSV.
-- Normalized fields are computed during the validation migration (D).
-- Canonical member ID is populated by the import migration (E).
--
-- IDEMPOTENCY: UNIQUE (import_batch_id, source_uuid)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.legacy_members (
  id                          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  import_batch_id             uuid        NOT NULL
    REFERENCES staging.import_batches(id),
  source_system               text        NOT NULL DEFAULT 'mfc_legacy',
  source_row_id               text        NOT NULL,
  -- 1-based CSV row number, used as stable idempotency key

  -- -------------------------------------------------------------------------
  -- Raw source fields (preserved exactly as read from CSV)
  -- -------------------------------------------------------------------------
  source_uuid                 uuid        NOT NULL,
  source_organization_id      text,
  source_member_code          text,
  source_first_name           text,
  source_last_name            text,
  source_middle_name          text,
  source_preferred_name       text,
  source_date_of_birth        text,
  source_date_joined          text,
  source_member_since         text,
  source_member_status        text,
  source_member_type          text,
  -- 'member' or 'coordinator'; not mapped to auth role
  source_chapter_id           text,       -- deferred; no V2 governance nodes yet
  source_unit_id              text,       -- deferred
  source_wedding_anniversary  text,       -- deferred; no V2 column
  source_formation_level_id   text,       -- deferred
  source_diaspora_id          text,       -- deferred
  source_photo_url            text,       -- deferred; URL cannot be stored as storage path

  -- -------------------------------------------------------------------------
  -- Normalized / computed fields (populated by validation migration D)
  -- -------------------------------------------------------------------------
  norm_given_names            text,
  norm_family_name            text,
  norm_middle_names           text,
  norm_display_name           text,
  norm_sort_name              text,
  norm_preferred_name         text,
  norm_birth_date             date,
  norm_joined_on              date,
  norm_first_contact_on       date,
  norm_membership_status_id   uuid,
  -- Resolved MFCNY member_statuses.id
  norm_member_code            text,
  -- Validated/reformatted code (NY10001 → NY10001; 10550 → NY10550 pending review)
  norm_member_code_status     text
    CONSTRAINT ck_legacy_members__code_status
      CHECK (norm_member_code_status IS NULL OR norm_member_code_status IN (
        'ny_format',       -- matches ^NY[0-9]+$ — valid
        'numeric_only',    -- matches ^[0-9]+$ — review_required, normalized to NY{n} pending approval
        'missing',         -- null/empty in source — left unnumbered
        'unknown_format',  -- does not match either pattern
        'duplicate',       -- duplicate within batch
        'collision'        -- collides with existing member_identifiers
      )),

  -- -------------------------------------------------------------------------
  -- Duplicate / probable-match detection
  -- -------------------------------------------------------------------------
  match_status                text        NOT NULL DEFAULT 'unmatched'
    CONSTRAINT ck_legacy_members__match_status
      CHECK (match_status IN (
        'unmatched',           -- not yet checked
        'matched_existing',    -- auto-detected candidate; requires manual confirmation
        'confirmed_existing',  -- manually confirmed; import reuses canonical_member_id
        'probable_duplicate',  -- probable duplicate within batch; review required
        'new'                  -- clean; import will create a new canonical member
      )),
  matched_canonical_member_id uuid,
  -- populated when match_status = 'matched_existing' or 'confirmed_existing'
  match_confidence            text
    CONSTRAINT ck_legacy_members__match_confidence
      CHECK (match_confidence IS NULL OR match_confidence IN (
        'confirmed',   -- manually confirmed match
        'probable',    -- high-confidence automated match
        'possible'     -- lower-confidence automated match
      )),
  match_notes                 text,

  -- -------------------------------------------------------------------------
  -- Validation
  -- -------------------------------------------------------------------------
  validation_status           text        NOT NULL DEFAULT 'pending'
    CONSTRAINT ck_legacy_members__validation_status
      CHECK (validation_status IN (
        'pending',
        'valid',
        'review_required',
        'rejected'
      )),
  validation_errors           jsonb       NOT NULL DEFAULT '[]',
  -- Array of error code strings, e.g. ["invalid_birth_date","member_code_numeric_only_requires_review"]

  -- -------------------------------------------------------------------------
  -- Import tracking
  -- -------------------------------------------------------------------------
  imported_at                 timestamptz,
  canonical_member_id         uuid,
  -- null until canonical insert confirmed (migration E)
  -- For confirmed_existing rows, set to matched_canonical_member_id.
  -- For new rows, set to the newly generated UUID.

  UNIQUE (import_batch_id, source_uuid)
);

COMMENT ON TABLE staging.legacy_members IS
  'Staging table for members_rows.csv (315 rows). '
  'Raw source fields are preserved; norm_* fields are computed during validation. '
  'match_status controls duplicate/existing-member handling during canonical import. '
  'Idempotent per (import_batch_id, source_uuid).';

COMMENT ON COLUMN staging.legacy_members.source_member_type IS
  'Legacy member type: ''member'' or ''coordinator''. '
  'Coordinator is imported as a standard active member. '
  'This field is NOT mapped to any V2 authorization role or governance assignment.';

COMMENT ON COLUMN staging.legacy_members.norm_member_code_status IS
  'ny_format: passes ^NY[0-9]+$ — promoted to member_number identifier. '
  'numeric_only: matches ^[0-9]+$ — normalized to NY{n} (e.g. NY10550) per Q-R2 decision, '
  'flagged review_required pending approval. '
  'missing: no source code — member is left unnumbered during initial import. '
  'duplicate/collision: rejected.';

COMMENT ON COLUMN staging.legacy_members.matched_canonical_member_id IS
  'For match_status=matched_existing: the probable canonical member ID. '
  'For match_status=confirmed_existing: the confirmed canonical member ID to reuse. '
  'Import migration E reads this value when match_status=confirmed_existing '
  'and skips the canonical member INSERT, instead attaching the legacy identifiers '
  'to the existing member row.';


-- ---------------------------------------------------------------------------
-- 3. staging.legacy_member_emails
-- ---------------------------------------------------------------------------
-- Source: member_emails_rows.csv (2 rows)
-- Source fields: member_id, email
-- IDEMPOTENCY: UNIQUE (import_batch_id, source_row_id)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.legacy_member_emails (
  id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  import_batch_id         uuid        NOT NULL
    REFERENCES staging.import_batches(id),
  source_row_id           text        NOT NULL,
  source_member_uuid      uuid        NOT NULL,
  -- from 'member_id' column
  source_email            text,
  -- raw 'email' field preserved exactly
  norm_email              text,
  -- lowercased + trimmed (pre-normalization)
  norm_email_normalized   text,
  -- result of private.normalize_email(source_email); checked against V2 constraint
  norm_email_type         text        DEFAULT 'personal',
  norm_is_primary         boolean     DEFAULT true,
  validation_status       text        NOT NULL DEFAULT 'pending'
    CONSTRAINT ck_legacy_member_emails__validation_status
      CHECK (validation_status IN ('pending','valid','review_required','rejected')),
  validation_errors       jsonb       NOT NULL DEFAULT '[]',
  imported_at             timestamptz,
  canonical_member_id     uuid,
  canonical_email_id      uuid,
  UNIQUE (import_batch_id, source_row_id)
);

COMMENT ON TABLE staging.legacy_member_emails IS
  'Staging table for member_emails_rows.csv (2 rows). '
  'Source fields: member_id, email. '
  'norm_email_normalized must match private.normalize_email() output '
  'before canonical insert — malformed values are rejected, not silently rewritten.';


-- ---------------------------------------------------------------------------
-- 4. staging.legacy_member_phones
-- ---------------------------------------------------------------------------
-- Source: member_phones_rows.csv (2 rows)
-- IDEMPOTENCY: UNIQUE (import_batch_id, source_row_id)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.legacy_member_phones (
  id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  import_batch_id         uuid        NOT NULL
    REFERENCES staging.import_batches(id),
  source_row_id           text        NOT NULL,
  source_member_uuid      uuid        NOT NULL,
  source_phone            text,
  source_phone_type       text,
  norm_phone              text,
  norm_e164               text,
  -- NULL if E.164 normalization is not possible; non-blocking
  norm_phone_type         text        DEFAULT 'mobile',
  norm_country_code       char(2),
  validation_status       text        NOT NULL DEFAULT 'pending'
    CONSTRAINT ck_legacy_member_phones__validation_status
      CHECK (validation_status IN ('pending','valid','review_required','rejected')),
  validation_errors       jsonb       NOT NULL DEFAULT '[]',
  imported_at             timestamptz,
  canonical_member_id     uuid,
  canonical_phone_id      uuid,
  UNIQUE (import_batch_id, source_row_id)
);

COMMENT ON TABLE staging.legacy_member_phones IS
  'Staging table for member_phones_rows.csv (2 rows). '
  'E.164 normalization failure is review_required (non-blocking), not rejected.';


-- ---------------------------------------------------------------------------
-- 5. staging.legacy_member_addresses
-- ---------------------------------------------------------------------------
-- Source: member_addresses_rows.csv (1 row)
-- Confirmed source fields: member_id, street_address, secondary_address,
--   state_province, and assumed: city, postal_code, country
-- IDEMPOTENCY: UNIQUE (import_batch_id, source_row_id)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.legacy_member_addresses (
  id                          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  import_batch_id             uuid        NOT NULL
    REFERENCES staging.import_batches(id),
  source_row_id               text        NOT NULL,
  source_member_uuid          uuid        NOT NULL,
  source_street_address       text,
  source_secondary_address    text,
  source_city                 text,
  source_state_province       text,
  source_postal_code          text,
  source_country_raw          text,
  -- Raw text country value, e.g. 'Philippines', 'United States'
  norm_country_code           char(2),
  -- ISO 3166-1 alpha-2 resolved from source_country_raw
  validation_status           text        NOT NULL DEFAULT 'pending'
    CONSTRAINT ck_legacy_member_addresses__validation_status
      CHECK (validation_status IN ('pending','valid','review_required','rejected')),
  validation_errors           jsonb       NOT NULL DEFAULT '[]',
  -- Expected error for the 1 known exception: 'country_contradicts_location_fields'
  imported_at                 timestamptz,
  canonical_member_id         uuid,
  canonical_address_id        uuid,
  canonical_member_address_id uuid,
  UNIQUE (import_batch_id, source_row_id)
);

COMMENT ON TABLE staging.legacy_member_addresses IS
  'Staging table for member_addresses_rows.csv (1 row). '
  'The single row has a known data quality exception: state/postal code suggests '
  'New York but country field indicates Philippines. '
  'This row must be flagged with validation_status=review_required and '
  'validation_errors=[''country_contradicts_location_fields''] during migration D. '
  'It must NOT be promoted to canonical addresses without manual correction.';


-- ---------------------------------------------------------------------------
-- 6. staging.legacy_member_relationships
-- ---------------------------------------------------------------------------
-- Source: member_relationships_rows.csv (3 rows)
-- Confirmed source fields: member_id, related_member_id, relationship_type
-- IDEMPOTENCY: UNIQUE (import_batch_id, source_row_id)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.legacy_member_relationships (
  id                          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  import_batch_id             uuid        NOT NULL
    REFERENCES staging.import_batches(id),
  source_row_id               text        NOT NULL,
  source_member_uuid          uuid        NOT NULL,
  -- from 'member_id' field (from_member_id in V2)
  source_related_member_uuid  uuid        NOT NULL,
  -- from 'related_member_id' field (to_member_id in V2)
  source_relationship_type    text,
  -- from 'relationship_type' field: 'child_of', 'parent_of', or 'spouse'
  norm_relationship_type_id   uuid,
  -- resolved from family_relationship_types.id after seed migration B is applied
  validation_status           text        NOT NULL DEFAULT 'pending'
    CONSTRAINT ck_legacy_member_relationships__validation_status
      CHECK (validation_status IN ('pending','valid','review_required','rejected')),
  validation_errors           jsonb       NOT NULL DEFAULT '[]',
  imported_at                 timestamptz,
  canonical_from_member_id    uuid,
  canonical_to_member_id      uuid,
  canonical_relationship_id   uuid,
  UNIQUE (import_batch_id, source_row_id)
);

COMMENT ON TABLE staging.legacy_member_relationships IS
  'Staging table for member_relationships_rows.csv (3 rows). '
  'Source fields: member_id (→ from_member_id), related_member_id (→ to_member_id), '
  'relationship_type (→ family_relationship_types.code). '
  'norm_relationship_type_id is resolved during validation migration D '
  'after migration B has seeded family_relationship_types.';


-- ---------------------------------------------------------------------------
-- 7. staging.chapter_unit_mapping
-- ---------------------------------------------------------------------------
-- Empty during Phase 4.5. Populated manually after V2 governance nodes
-- are created. Used by the deferred placement migration (J).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.chapter_unit_mapping (
  id                           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  source_system                text        NOT NULL DEFAULT 'mfc_legacy',
  source_node_id               text        NOT NULL,
  source_node_type             text        NOT NULL
    CONSTRAINT ck_chapter_unit_mapping__node_type
      CHECK (source_node_type IN ('chapter', 'unit')),
  source_node_name             text,
  canonical_governance_node_id uuid,
  -- filled manually or via a future mapping migration
  mapping_status               text        NOT NULL DEFAULT 'pending'
    CONSTRAINT ck_chapter_unit_mapping__mapping_status
      CHECK (mapping_status IN (
        'pending',
        'mapped',
        'no_v2_equivalent',
        'deferred'
      )),
  mapped_at                    timestamptz,
  mapped_by_profile_id         uuid,
  notes                        text,
  UNIQUE (source_system, source_node_id)
);

COMMENT ON TABLE staging.chapter_unit_mapping IS
  'Maps legacy chapter_id and unit_id values to canonical V2 governance_nodes. '
  'Empty during Phase 4.5 — populated before the placement import migration (J). '
  'No V2 governance nodes exist for MFCNY yet; this table tracks the mapping '
  'work required before any section/household placement can be imported.';


-- ---------------------------------------------------------------------------
-- End of Migration A
-- ---------------------------------------------------------------------------
-- What this migration does NOT do:
--   - No public.* table changes
--   - No GRANT to anon or authenticated roles
--   - No RLS policy changes
--   - No number sequence changes
--   - No canonical member inserts
--   - No governance node creation
-- ---------------------------------------------------------------------------

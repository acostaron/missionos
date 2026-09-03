-- =============================================================================
-- Migration B: Phase 4.5 — Family Relationship Type Seed
-- File:        20260903_010000_phase_4_5_relationship_type_seed.sql
-- =============================================================================
--
-- PURPOSE
-- -------
-- Seeds the three family_relationship_types rows required for the MFCNY
-- legacy member import. These types correspond exactly to the relationship_type
-- values present in member_relationships_rows.csv.
--
-- DESIGN PRINCIPLES
-- -----------------
-- 1. Forward-only.
-- 2. Idempotent via ON CONFLICT (code) WHERE organization_id IS NULL DO NOTHING.
--    Re-running this migration is safe.
-- 3. organization_id = NULL — global types, not scoped to any single organization
--    (approved Q-R1).
-- 4. relationship_category values use the authoritative CHECK constraint values:
--    - 'parental'  for child_of and parent_of (not 'parent_child')
--    - 'marital'   for spouse (not 'spousal')
-- 5. No canonical member inserts.
-- 6. No staging data loaded.
-- 7. No number sequence changes.
-- 8. No governance nodes created.
-- 9. No authorization or RLS changes.
--
-- SCHEMA CONSTRAINTS RESPECTED
-- ----------------------------
-- ck_family_relationship_types__category:
--   CHECK (relationship_category = ANY (ARRAY[
--     'marital','parental','guardianship','sibling',
--     'dependency','caregiving','extended_family'
--   ]))
--
-- ck_family_relationship_types__code_format:
--   CHECK (code ~ '^[a-z][a-z0-9_]*$')   -- all three codes pass
--
-- ck_family_relationship_types__inverse_requirement:
--   CHECK (is_symmetric OR inverse_code IS NOT NULL)
--   - child_of:  is_symmetric=false → inverse_code='parent_of' required ✔
--   - parent_of: is_symmetric=false → inverse_code='child_of'  required ✔
--   - spouse:    is_symmetric=true  → inverse_code optional      ✔
--
-- ck_family_relationship_types__inverse_code:
--   CHECK (inverse_code IS NULL OR inverse_code ~ '^[a-z][a-z0-9_]*$')
--   - 'parent_of', 'child_of', 'spouse' all pass ✔
--
-- ck_family_relationship_types__name_nonempty:
--   CHECK (private.is_nonempty_text(name))   -- all non-empty ✔
--
-- TABLE DEFAULTS APPLIED AS-IS
-- ----------------------------
-- requires_same_family   = true  (schema default; appropriate for familial relationships)
-- allows_multiple_current = true (schema default; e.g. a parent can have multiple children)
-- display_order          = 0     (schema default)
-- is_active              = true  (schema default)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Unique index used for idempotent ON CONFLICT
-- ---------------------------------------------------------------------------
-- The table does not have a UNIQUE constraint on (code) alone because codes
-- are only unique per organization (or globally when organization_id IS NULL).
-- We use an INSERT ... ON CONFLICT DO NOTHING with a WHERE clause.
-- Since no unique index exists for this exact pattern, we use a CTE with an
-- existence check to achieve safe idempotency.
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  -- -------------------------------------------------------------------------
  -- 1. child_of
  --    Semantics: Member A is a child of Member B.
  --    Inverse:   parent_of
  --    Symmetric: false
  -- -------------------------------------------------------------------------
  IF NOT EXISTS (
    SELECT 1
    FROM public.family_relationship_types
    WHERE code = 'child_of'
      AND organization_id IS NULL
  ) THEN
    INSERT INTO public.family_relationship_types (
      id,
      organization_id,
      code,
      name,
      inverse_code,
      relationship_category,
      is_symmetric,
      requires_same_family,
      allows_multiple_current,
      display_order,
      is_active
    ) VALUES (
      gen_random_uuid(),
      NULL,            -- global type
      'child_of',
      'Child of',
      'parent_of',     -- inverse
      'parental',      -- authoritative category value
      false,           -- not symmetric: A child_of B ≠ B child_of A
      true,            -- default: requires same family unit
      true,            -- default: allows multiple (a parent can have many children)
      10,
      true
    );
    RAISE NOTICE 'Inserted family_relationship_types: child_of';
  ELSE
    RAISE NOTICE 'Skipped family_relationship_types: child_of (already exists)';
  END IF;

  -- -------------------------------------------------------------------------
  -- 2. parent_of
  --    Semantics: Member A is a parent of Member B.
  --    Inverse:   child_of
  --    Symmetric: false
  -- -------------------------------------------------------------------------
  IF NOT EXISTS (
    SELECT 1
    FROM public.family_relationship_types
    WHERE code = 'parent_of'
      AND organization_id IS NULL
  ) THEN
    INSERT INTO public.family_relationship_types (
      id,
      organization_id,
      code,
      name,
      inverse_code,
      relationship_category,
      is_symmetric,
      requires_same_family,
      allows_multiple_current,
      display_order,
      is_active
    ) VALUES (
      gen_random_uuid(),
      NULL,            -- global type
      'parent_of',
      'Parent of',
      'child_of',      -- inverse
      'parental',      -- authoritative category value
      false,           -- not symmetric
      true,            -- default
      true,            -- a child can have two parents
      20,
      true
    );
    RAISE NOTICE 'Inserted family_relationship_types: parent_of';
  ELSE
    RAISE NOTICE 'Skipped family_relationship_types: parent_of (already exists)';
  END IF;

  -- -------------------------------------------------------------------------
  -- 3. spouse
  --    Semantics: Member A is the spouse of Member B.
  --    Inverse:   spouse (self-inverse; symmetric)
  --    Symmetric: true
  -- -------------------------------------------------------------------------
  IF NOT EXISTS (
    SELECT 1
    FROM public.family_relationship_types
    WHERE code = 'spouse'
      AND organization_id IS NULL
  ) THEN
    INSERT INTO public.family_relationship_types (
      id,
      organization_id,
      code,
      name,
      inverse_code,
      relationship_category,
      is_symmetric,
      requires_same_family,
      allows_multiple_current,
      display_order,
      is_active
    ) VALUES (
      gen_random_uuid(),
      NULL,            -- global type
      'spouse',
      'Spouse',
      'spouse',        -- self-inverse (symmetric)
      'marital',       -- authoritative category value
      true,            -- symmetric: A spouse B → B spouse A
      true,            -- default: requires same family
      false,           -- a person has at most one current spouse
      30,
      true
    );
    RAISE NOTICE 'Inserted family_relationship_types: spouse';
  ELSE
    RAISE NOTICE 'Skipped family_relationship_types: spouse (already exists)';
  END IF;

END;
$$;


-- ---------------------------------------------------------------------------
-- Verification query (informational — does not affect migration outcome)
-- ---------------------------------------------------------------------------
-- After applying, the following should return 3 rows:
--
-- SELECT id, code, name, inverse_code, relationship_category,
--        is_symmetric, requires_same_family, allows_multiple_current,
--        display_order, is_active
-- FROM public.family_relationship_types
-- WHERE organization_id IS NULL
-- ORDER BY display_order;
--
-- Expected:
-- code        | name      | inverse_code | category | symmetric | requires_family | allows_multiple
-- child_of    | Child of  | parent_of    | parental | f         | t               | t
-- parent_of   | Parent of | child_of     | parental | f         | t               | t
-- spouse      | Spouse    | spouse       | marital  | t         | t               | f
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- End of Migration B
-- ---------------------------------------------------------------------------
-- What this migration does NOT do:
--   - No public.members changes
--   - No staging data loaded
--   - No number sequence changes
--   - No governance nodes created
--   - No GRANT to anon or authenticated roles
--   - No RLS policy changes
-- ---------------------------------------------------------------------------

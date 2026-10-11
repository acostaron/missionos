-- Migration 102: Community labels
-- Label: community_labels
-- Contiguous timestamp: 20261010034000

-- A. Add tag_group column to public.tags
ALTER TABLE public.tags ADD COLUMN IF NOT EXISTS tag_group text NULL;

DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_tags__tag_group'
    ) THEN 
        ALTER TABLE public.tags 
        ADD CONSTRAINT ck_tags__tag_group 
        CHECK (tag_group IS NULL OR tag_group ~ '^[a-z][a-z0-9_]*$'); 
    END IF; 
END $$;

COMMENT ON COLUMN public.tags.tag_group IS 'Logical grouping of tags, e.g. community = cultural/language community labels.';

-- B & C. Upsert tags (idempotent by organization_id + code)
DO $$
DECLARE
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
    v_now timestamptz := clock_timestamp();
    v_tags_upserted integer := 0;
BEGIN
    CREATE TEMP TABLE _community_tags_staging (
        code text PRIMARY KEY,
        name text NOT NULL,
        description text NOT NULL,
        display_order integer NOT NULL
    ) ON COMMIT DROP;

    INSERT INTO _community_tags_staging (code, name, description, display_order) VALUES
        ('fmc',        'FMC',        'Familias Misioneras de Cristo — Spanish-speaking community', 1),
        ('indian',     'Indian',     'Indian community',                                           2),
        ('vietnamese', 'Vietnamese', 'Vietnamese community',                                       3),
        ('chinese',    'Chinese',    'Chinese community',                                          4);

    INSERT INTO public.tags (
        organization_id,
        code,
        name,
        description,
        data_classification_code,
        tag_group,
        is_active,
        display_order,
        created_at,
        updated_at
    )
    SELECT
        v_org_id,
        s.code,
        s.name,
        s.description,
        'internal',
        'community',
        true,
        s.display_order,
        v_now,
        v_now
    FROM _community_tags_staging s
    ON CONFLICT (organization_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        data_classification_code = EXCLUDED.data_classification_code,
        tag_group = EXCLUDED.tag_group,
        is_active = true,
        display_order = EXCLUDED.display_order,
        updated_at = v_now;

    GET DIAGNOSTICS v_tags_upserted = ROW_COUNT;

    -- E. Record summary audit event
    INSERT INTO audit.events (
        organization_id,
        event_code,
        event_category,
        entity_type,
        entity_id,
        action,
        outcome,
        metadata
    ) VALUES (
        v_org_id,
        'tags.community_labels_configured',
        'governance',
        'tag',
        v_org_id,
        'configure_community_labels',
        'success',
        jsonb_build_object(
            'migration', '20261010034000_community_labels',
            'tags_upserted', v_tags_upserted,
            'tag_group', 'community',
            'tag_codes', jsonb_build_array('fmc', 'indian', 'vietnamese', 'chinese'),
            'classification', 'internal'
        )
    );

    RAISE NOTICE 'Pass 4.6S-B migration completed: tags_upserted=%', v_tags_upserted;
END $$;

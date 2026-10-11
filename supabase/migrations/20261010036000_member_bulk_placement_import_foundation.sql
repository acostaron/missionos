-- Migration 104: member_bulk_placement_import_foundation
-- Timestamp: 20261010036000
-- Purpose: Bulk member placement and archive staging foundation

-- =============================================================================
-- A. staging.member_placement_import table
-- =============================================================================
CREATE TABLE IF NOT EXISTS staging.member_placement_import (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    import_batch_code text NOT NULL,
    legacy_member_id uuid NOT NULL,
    action text NOT NULL CHECK (action IN ('place', 'archive')),
    sex text NULL,
    section_code text NULL,
    community_tag_code text NULL,
    chapter_code text NULL,
    unit_code text NULL,
    member_id uuid NULL,
    validation_status text NULL,
    validation_message text NULL,
    applied_at timestamptz NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_member_placement_import__batch_legacy UNIQUE (import_batch_code, legacy_member_id)
);

COMMENT ON TABLE staging.member_placement_import IS
'Staging table for bulk placement, section assignment, sex demographic ingestion, and non-member archival.';

-- Ensure no client access to staging table
REVOKE ALL ON TABLE staging.member_placement_import FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE staging.member_placement_import TO service_role, postgres;

-- =============================================================================
-- B. private.apply_member_placement_import function
-- =============================================================================
CREATE OR REPLACE FUNCTION private.apply_member_placement_import(p_batch_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'private', 'auth'
AS $function$
DECLARE
    v_org_id uuid;
    v_now timestamptz := clock_timestamp();
    v_row record;
    v_member_id uuid;
    v_member public.members%rowtype;
    v_section_node_id uuid;
    v_unit_node_id uuid;
    v_unit_parent_id uuid;
    v_chapter_node_id uuid;
    v_gov_placement_node_id uuid;
    v_tag_id uuid;
    v_paired_member_id uuid;

    v_total_count int := 0;
    v_placed_count int := 0;
    v_archived_count int := 0;
    v_sex_updated_count int := 0;
    v_section_count int := 0;
    v_placement_count int := 0;
    v_tag_count int := 0;
BEGIN
    -- 0. Organization resolution
    SELECT id INTO v_org_id
    FROM public.organizations
    WHERE code = 'mfcny'
    LIMIT 1;

    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'Target organization mfcny not found';
    END IF;

    -- 1. Check batch existence & idempotency
    IF NOT EXISTS (
        SELECT 1 FROM staging.member_placement_import
        WHERE import_batch_code = p_batch_code
    ) THEN
        RAISE EXCEPTION 'Import batch "%" not found in staging.member_placement_import', p_batch_code;
    END IF;

    -- If all rows are already applied, return idempotent success
    IF NOT EXISTS (
        SELECT 1 FROM staging.member_placement_import
        WHERE import_batch_code = p_batch_code
          AND applied_at IS NULL
    ) THEN
        SELECT count(*) INTO v_total_count
        FROM staging.member_placement_import
        WHERE import_batch_code = p_batch_code;

        RETURN jsonb_build_object(
            'status', 'already_applied',
            'batch_code', p_batch_code,
            'total_rows', v_total_count,
            'message', 'Batch has already been applied.'
        );
    END IF;

    -- 2. Validate every unapplied row in the batch first
    FOR v_row IN
        SELECT *
        FROM staging.member_placement_import
        WHERE import_batch_code = p_batch_code
          AND applied_at IS NULL
        ORDER BY id
    LOOP
        v_total_count := v_total_count + 1;

        -- Validate legacy member resolution
        SELECT mi.member_id INTO v_member_id
        FROM public.member_identifiers mi
        WHERE mi.organization_id = v_org_id
          AND mi.identifier_type = 'legacy_member_id'
          AND mi.identifier_value = v_row.legacy_member_id::text
        LIMIT 1;

        IF v_member_id IS NULL THEN
            RAISE EXCEPTION 'Row id %: legacy_member_id % does not resolve to any member',
                v_row.id, v_row.legacy_member_id;
        END IF;

        SELECT * INTO v_member
        FROM public.members
        WHERE id = v_member_id
          AND organization_id = v_org_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Row id %: member % does not exist in organization',
                v_row.id, v_member_id;
        END IF;

        IF v_member.record_status <> 'active' THEN
            RAISE EXCEPTION 'Row id %: member % is not active (current status: %)',
                v_row.id, v_member_id, v_member.record_status;
        END IF;

        -- Validate sex value
        IF v_row.sex IS NOT NULL AND btrim(v_row.sex) <> '' THEN
            IF v_row.sex NOT IN ('male', 'female') THEN
                RAISE EXCEPTION 'Row id %: invalid sex "%" (must be male, female, or empty)',
                    v_row.id, v_row.sex;
            END IF;
        END IF;

        -- Validate place action specifics
        IF v_row.action = 'place' THEN
            -- Section validation
            IF v_row.section_code IS NULL OR v_row.section_code !~ '^sec_' THEN
                RAISE EXCEPTION 'Row id %: place action requires section_code starting with sec_', v_row.id;
            END IF;

            SELECT gn.id INTO v_section_node_id
            FROM public.governance_nodes gn
            JOIN public.governance_node_types gnt
              ON gnt.id = gn.governance_node_type_id
             AND gnt.organization_id = gn.organization_id
            WHERE gn.organization_id = v_org_id
              AND gn.code = v_row.section_code
              AND gn.lifecycle_status = 'active'
              AND gnt.is_section_type = true;

            IF v_section_node_id IS NULL THEN
                RAISE EXCEPTION 'Row id %: section_code "%" not found or not an active section',
                    v_row.id, v_row.section_code;
            END IF;

            -- Community tag validation (if supplied)
            IF v_row.community_tag_code IS NOT NULL AND btrim(v_row.community_tag_code) <> '' THEN
                SELECT t.id INTO v_tag_id
                FROM public.tags t
                WHERE t.organization_id = v_org_id
                  AND t.code = v_row.community_tag_code
                  AND t.tag_group = 'community'
                  AND t.is_active = true;

                IF v_tag_id IS NULL THEN
                    RAISE EXCEPTION 'Row id %: community_tag_code "%" not found or not active community tag',
                        v_row.id, v_row.community_tag_code;
                END IF;
            END IF;

            -- Unit and chapter validation
            IF v_row.unit_code IS NOT NULL AND btrim(v_row.unit_code) <> '' THEN
                SELECT gn.id, gnr.parent_node_id INTO v_unit_node_id, v_unit_parent_id
                FROM public.governance_nodes gn
                JOIN public.governance_node_types gnt
                  ON gnt.id = gn.governance_node_type_id
                 AND gnt.organization_id = gn.organization_id
                LEFT JOIN public.governance_node_relationships gnr
                  ON gnr.child_node_id = gn.id
                 AND gnr.organization_id = gn.organization_id
                 AND gnr.relationship_type = 'primary_parent'
                WHERE gn.organization_id = v_org_id
                  AND gn.code = v_row.unit_code
                  AND gn.lifecycle_status = 'active'
                  AND gnt.code = 'unit';

                IF v_unit_node_id IS NULL THEN
                    RAISE EXCEPTION 'Row id %: unit_code "%" not found or not an active unit',
                        v_row.id, v_row.unit_code;
                END IF;

                IF v_row.chapter_code IS NOT NULL AND btrim(v_row.chapter_code) <> '' THEN
                    SELECT gn.id INTO v_chapter_node_id
                    FROM public.governance_nodes gn
                    JOIN public.governance_node_types gnt
                      ON gnt.id = gn.governance_node_type_id
                     AND gnt.organization_id = gn.organization_id
                    WHERE gn.organization_id = v_org_id
                      AND gn.code = v_row.chapter_code
                      AND gn.lifecycle_status = 'active'
                      AND gnt.code = 'chapter';

                    IF v_chapter_node_id IS NULL THEN
                        RAISE EXCEPTION 'Row id %: chapter_code "%" not found or not an active chapter',
                            v_row.id, v_row.chapter_code;
                    END IF;

                    IF v_unit_parent_id <> v_chapter_node_id THEN
                        RAISE EXCEPTION 'Row id %: unit "%" parent does not match chapter "%"',
                            v_row.id, v_row.unit_code, v_row.chapter_code;
                    END IF;
                END IF;
            ELSIF v_row.chapter_code IS NOT NULL AND btrim(v_row.chapter_code) <> '' THEN
                SELECT gn.id INTO v_chapter_node_id
                FROM public.governance_nodes gn
                JOIN public.governance_node_types gnt
                  ON gnt.id = gn.governance_node_type_id
                 AND gnt.organization_id = gn.organization_id
                WHERE gn.organization_id = v_org_id
                  AND gn.code = v_row.chapter_code
                  AND gn.lifecycle_status = 'active'
                  AND gnt.code = 'chapter';

                IF v_chapter_node_id IS NULL THEN
                    RAISE EXCEPTION 'Row id %: chapter_code "%" not found or not an active chapter',
                        v_row.id, v_row.chapter_code;
                END IF;
            END IF;

        ELSIF v_row.action = 'archive' THEN
            -- Nothing more to validate for archive row
            NULL;
        ELSE
            RAISE EXCEPTION 'Row id %: unsupported action "%"', v_row.id, v_row.action;
        END IF;
    END LOOP;

    -- 3. Execution Phase (All validated, apply atomically)
    FOR v_row IN
        SELECT *
        FROM staging.member_placement_import
        WHERE import_batch_code = p_batch_code
          AND applied_at IS NULL
        ORDER BY id
    LOOP
        -- Resolve member_id
        SELECT mi.member_id INTO v_member_id
        FROM public.member_identifiers mi
        WHERE mi.organization_id = v_org_id
          AND mi.identifier_type = 'legacy_member_id'
          AND mi.identifier_value = v_row.legacy_member_id::text
        LIMIT 1;

        -- Update staging row with member_id
        UPDATE staging.member_placement_import
        SET member_id = v_member_id
        WHERE id = v_row.id;

        IF v_row.action = 'place' THEN
            v_placed_count := v_placed_count + 1;

            -- 3a. Update sex if non-empty and member's sex is NULL
            IF v_row.sex IS NOT NULL AND btrim(v_row.sex) <> '' THEN
                UPDATE public.members
                SET sex = btrim(v_row.sex),
                    updated_at = v_now
                WHERE id = v_member_id
                  AND organization_id = v_org_id
                  AND sex IS NULL;

                IF FOUND THEN
                    v_sex_updated_count := v_sex_updated_count + 1;
                END IF;
            END IF;

            -- 3b. Resolve section node
            SELECT gn.id INTO v_section_node_id
            FROM public.governance_nodes gn
            WHERE gn.organization_id = v_org_id
              AND gn.code = v_row.section_code;

            -- Check for paired spouse if sec_couples
            v_paired_member_id := NULL;
            IF v_row.section_code = 'sec_couples' THEN
                SELECT fr.to_member_id INTO v_paired_member_id
                FROM public.family_relationships fr
                JOIN public.family_relationship_types frt
                  ON frt.id = fr.relationship_type_id
                WHERE fr.organization_id = v_org_id
                  AND fr.from_member_id = v_member_id
                  AND frt.code = 'spouse'
                  AND fr.relationship_status = 'active'
                  AND fr.verification_status = 'verified'
                  AND (fr.effective_to IS NULL OR fr.effective_to >= CURRENT_DATE)
                  AND fr.effective_from <= CURRENT_DATE
                  AND (
                      EXISTS (
                          SELECT 1 FROM staging.member_placement_import s2
                          JOIN public.member_identifiers mi2
                            ON mi2.identifier_value = s2.legacy_member_id::text
                          WHERE s2.import_batch_code = p_batch_code
                            AND mi2.identifier_type = 'legacy_member_id'
                            AND mi2.member_id = fr.to_member_id
                            AND s2.action = 'place'
                            AND s2.section_code = 'sec_couples'
                      )
                      OR EXISTS (
                          SELECT 1 FROM public.section_memberships sm2
                          JOIN public.governance_nodes gn2 ON gn2.id = sm2.section_node_id
                          WHERE sm2.organization_id = v_org_id
                            AND sm2.member_id = fr.to_member_id
                            AND sm2.membership_status = 'active'
                            AND gn2.code = 'sec_couples'
                      )
                  )
                LIMIT 1;
            END IF;

            -- Insert section_membership (triggers sync to members.primary_section_node_id)
            INSERT INTO public.section_memberships (
                organization_id,
                member_id,
                section_node_id,
                membership_status,
                effective_from,
                effective_to,
                is_primary,
                paired_member_id,
                placement_source,
                created_at,
                updated_at
            ) VALUES (
                v_org_id,
                v_member_id,
                v_section_node_id,
                'active',
                CURRENT_DATE,
                NULL,
                true,
                v_paired_member_id,
                'administrative',
                v_now,
                v_now
            );

            v_section_count := v_section_count + 1;

            -- 3c. Governance placement
            v_gov_placement_node_id := NULL;
            IF v_row.unit_code IS NOT NULL AND btrim(v_row.unit_code) <> '' THEN
                SELECT gn.id INTO v_gov_placement_node_id
                FROM public.governance_nodes gn
                WHERE gn.organization_id = v_org_id
                  AND gn.code = v_row.unit_code;
            ELSIF v_row.chapter_code IS NOT NULL AND btrim(v_row.chapter_code) <> '' THEN
                SELECT gn.id INTO v_gov_placement_node_id
                FROM public.governance_nodes gn
                WHERE gn.organization_id = v_org_id
                  AND gn.code = v_row.chapter_code;
            END IF;

            IF v_gov_placement_node_id IS NOT NULL THEN
                INSERT INTO public.member_governance_assignments (
                    organization_id,
                    member_id,
                    governance_node_id,
                    assignment_type,
                    assignment_status,
                    assignment_basis,
                    is_primary,
                    effective_from,
                    effective_to,
                    created_at,
                    updated_at
                ) VALUES (
                    v_org_id,
                    v_member_id,
                    v_gov_placement_node_id,
                    'primary',
                    'active',
                    'administrative',
                    true,
                    CURRENT_DATE,
                    NULL,
                    v_now,
                    v_now
                );

                v_placement_count := v_placement_count + 1;
            END IF;

            -- 3d. Community tag
            IF v_row.community_tag_code IS NOT NULL AND btrim(v_row.community_tag_code) <> '' THEN
                SELECT t.id INTO v_tag_id
                FROM public.tags t
                WHERE t.organization_id = v_org_id
                  AND t.code = v_row.community_tag_code;

                INSERT INTO public.entity_tags (
                    organization_id,
                    tag_id,
                    entity_type,
                    entity_id,
                    assigned_at,
                    assignment_reason,
                    created_at
                ) VALUES (
                    v_org_id,
                    v_tag_id,
                    'member',
                    v_member_id,
                    v_now,
                    'Batch placement import: ' || p_batch_code,
                    v_now
                );

                v_tag_count := v_tag_count + 1;
            END IF;

        ELSIF v_row.action = 'archive' THEN
            v_archived_count := v_archived_count + 1;

            -- Apply Phase 5h archive effects
            UPDATE public.members
            SET record_status          = 'archived',
                archived_at            = v_now,
                archived_by_profile_id = NULL,
                archive_reason         = 'not_an_mfcny_member_or_test_record',
                updated_at             = v_now,
                updated_by_profile_id  = NULL
            WHERE id = v_member_id
              AND organization_id = v_org_id;

            -- End any active section, governance, or household assignments (if any existed)
            UPDATE public.section_memberships
            SET membership_status = 'ended',
                effective_to = CURRENT_DATE,
                ending_reason = 'Member record archived: not_an_mfcny_member_or_test_record',
                updated_at = v_now
            WHERE organization_id = v_org_id
              AND member_id = v_member_id
              AND membership_status = 'active';

            UPDATE public.member_governance_assignments
            SET assignment_status = 'ended',
                effective_to = CURRENT_DATE,
                ending_reason = 'Member record archived: not_an_mfcny_member_or_test_record',
                updated_at = v_now
            WHERE organization_id = v_org_id
              AND member_id = v_member_id
              AND assignment_status = 'active';

            UPDATE public.household_memberships
            SET membership_status = 'ended',
                effective_to = CURRENT_DATE,
                ending_reason = 'Member record archived: not_an_mfcny_member_or_test_record',
                updated_at = v_now
            WHERE organization_id = v_org_id
              AND member_id = v_member_id
              AND membership_status = 'active';
        END IF;

        -- Mark row as applied
        UPDATE staging.member_placement_import
        SET applied_at = v_now,
            validation_status = 'applied',
            validation_message = 'Successfully applied'
        WHERE id = v_row.id;
    END LOOP;

    -- 4. Write summary audit events (one per action type)
    IF v_placed_count > 0 THEN
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
            'member.bulk_placement.imported',
            'member',
            'organization',
            v_org_id,
            'bulk_place_members',
            'success',
            jsonb_build_object(
                'batch_code', p_batch_code,
                'placed_count', v_placed_count,
                'sex_updated_count', v_sex_updated_count,
                'section_memberships_count', v_section_count,
                'governance_assignments_count', v_placement_count,
                'community_tags_count', v_tag_count
            )
        );
    END IF;

    IF v_archived_count > 0 THEN
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
            'member.bulk_archive.imported',
            'member',
            'organization',
            v_org_id,
            'bulk_archive_members',
            'success',
            jsonb_build_object(
                'batch_code', p_batch_code,
                'archived_count', v_archived_count,
                'archive_reason', 'not_an_mfcny_member_or_test_record'
            )
        );
    END IF;

    -- 5. Return summary counts
    RETURN jsonb_build_object(
        'status', 'success',
        'batch_code', p_batch_code,
        'total_rows', v_total_count,
        'placed_count', v_placed_count,
        'archived_count', v_archived_count,
        'sex_updated_count', v_sex_updated_count,
        'section_memberships_count', v_section_count,
        'governance_assignments_count', v_placement_count,
        'community_tags_count', v_tag_count
    );
END;
$function$;

-- Restrict execution to service_role only
REVOKE ALL ON FUNCTION private.apply_member_placement_import(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.apply_member_placement_import(text) TO service_role;

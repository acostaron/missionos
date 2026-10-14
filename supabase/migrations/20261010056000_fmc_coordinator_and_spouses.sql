-- Pass 6.3: record two verified married couples and appoint the FMC Coordinator (data only, no function changes).
-- Ministry facts (Ron, 2026-10-13):
--   * NY10448 Napoleon Rodriguez and NY10453 Miriam Rodriguez are husband and wife, placed at FMC New York;
--     they are the FMC Coordinator.
--   * NY10550 Eduardo Cardona and NY10551 Edna Cardona are married (spouses).
-- Spouse rows follow the pattern of 20261010041000 (administrator_verified, source 'administrator').
-- Couples pairing is set only where both spouses are already active in the same Couples section.
-- Napoleon and Miriam were added in the app without a member number; step 0 attaches their existing numbers
-- (NY10448, NY10453 — Ron, 2026-10-13). Members are then looked up by their primary member_number identifier.

DO $$
DECLARE
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
    v_spouse_type_id uuid;
    v_fmc_ny_id uuid;
    v_rec record;
    v_m1 public.members%rowtype;
    v_m2 public.members%rowtype;
    v_family_id uuid;
    v_count integer;
    v_res jsonb;
    v_assignment_id uuid;
BEGIN
    -- The 'spouse' type is a system row (organization_id may be NULL); prefer an org row if one exists.
    SELECT id INTO STRICT v_spouse_type_id
    FROM public.family_relationship_types
    WHERE code = 'spouse' AND (organization_id = v_org_id OR organization_id IS NULL)
    ORDER BY (organization_id IS NULL)
    LIMIT 1;

    SELECT id INTO STRICT v_fmc_ny_id
    FROM public.governance_nodes
    WHERE organization_id = v_org_id AND code = 'fmc_ny' AND lifecycle_status = 'active';

    ---------------------------------------------------------------------------
    -- 0. Attach the Rodriguezes' existing member numbers (Ron: NY10448 Napoleon, NY10453 Miriam).
    --    Their records were created in the app without a number. Identified by name, FMC New York
    --    placement, and having no member_number identifier yet. The sync trigger fills members.member_number.
    ---------------------------------------------------------------------------
    FOR v_rec IN
        SELECT * FROM (VALUES ('NY10448', '%napoleon%rodriguez%'), ('NY10453', '%miriam%rodriguez%')) AS t(num, name_pattern)
    LOOP
        SELECT count(*) INTO v_count
        FROM public.member_identifiers mi
        WHERE mi.organization_id = v_org_id AND mi.identifier_type = 'member_number'
          AND mi.normalized_value = v_rec.num;
        IF v_count <> 0 THEN
            RAISE EXCEPTION 'Guard failed: member number % is already used (%)', v_rec.num, v_count;
        END IF;

        SELECT count(*) INTO v_count
        FROM public.members m
        WHERE m.organization_id = v_org_id
          AND m.record_status = 'active'
          AND lower(m.display_name) LIKE v_rec.name_pattern
          AND NOT EXISTS (SELECT 1 FROM public.member_identifiers mi
                          WHERE mi.member_id = m.id AND mi.identifier_type = 'member_number')
          AND EXISTS (SELECT 1 FROM public.member_governance_assignments a
                      WHERE a.member_id = m.id AND a.assignment_status = 'active' AND a.is_primary
                        AND a.effective_to IS NULL AND a.governance_node_id = v_fmc_ny_id);
        IF v_count <> 1 THEN
            RAISE EXCEPTION 'Guard failed: expected exactly 1 unnumbered member at FMC New York matching % for %, got %', v_rec.name_pattern, v_rec.num, v_count;
        END IF;

        INSERT INTO public.member_identifiers (
            id, organization_id, member_id, identifier_type, source_system,
            identifier_value, normalized_value, is_primary, verification_status,
            effective_from, created_by_profile_id
        )
        SELECT gen_random_uuid(), v_org_id, m.id, 'member_number', 'missionos',
               v_rec.num, upper(v_rec.num), true, 'unverified',
               current_date, NULL
        FROM public.members m
        WHERE m.organization_id = v_org_id
          AND m.record_status = 'active'
          AND lower(m.display_name) LIKE v_rec.name_pattern
          AND NOT EXISTS (SELECT 1 FROM public.member_identifiers mi
                          WHERE mi.member_id = m.id AND mi.identifier_type = 'member_number')
          AND EXISTS (SELECT 1 FROM public.member_governance_assignments a
                      WHERE a.member_id = m.id AND a.assignment_status = 'active' AND a.is_primary
                        AND a.effective_to IS NULL AND a.governance_node_id = v_fmc_ny_id);

        SELECT count(*) INTO v_count FROM public.members
        WHERE organization_id = v_org_id AND member_number = v_rec.num;
        IF v_count <> 1 THEN
            RAISE EXCEPTION 'Guard failed: members.member_number not synced for % (%)', v_rec.num, v_count;
        END IF;
    END LOOP;

    ---------------------------------------------------------------------------
    -- A. Verified spouse links
    ---------------------------------------------------------------------------
    FOR v_rec IN
        SELECT * FROM (VALUES ('NY10448', 'NY10453'), ('NY10550', 'NY10551')) AS t(n1, n2)
    LOOP
        SELECT m.* INTO v_m1 FROM public.members m
        WHERE m.organization_id = v_org_id
          AND m.id = (SELECT mi.member_id FROM public.member_identifiers mi
                      WHERE mi.organization_id = v_org_id AND mi.identifier_type = 'member_number'
                        AND mi.is_primary = true AND mi.effective_to IS NULL
                        AND mi.normalized_value = upper(v_rec.n1));
        IF NOT FOUND OR v_m1.record_status <> 'active' OR coalesce(v_m1.is_deceased, false) THEN
            RAISE EXCEPTION 'Guard failed: member % not found or not active', v_rec.n1;
        END IF;
        SELECT m.* INTO v_m2 FROM public.members m
        WHERE m.organization_id = v_org_id
          AND m.id = (SELECT mi.member_id FROM public.member_identifiers mi
                      WHERE mi.organization_id = v_org_id AND mi.identifier_type = 'member_number'
                        AND mi.is_primary = true AND mi.effective_to IS NULL
                        AND mi.normalized_value = upper(v_rec.n2));
        IF NOT FOUND OR v_m2.record_status <> 'active' OR coalesce(v_m2.is_deceased, false) THEN
            RAISE EXCEPTION 'Guard failed: member % not found or not active', v_rec.n2;
        END IF;

        -- Stop if either already has any spouse row (nothing is merged or overwritten here)
        SELECT count(*) INTO v_count
        FROM public.family_relationships fr
        WHERE fr.organization_id = v_org_id
          AND fr.relationship_type_id = v_spouse_type_id
          AND (fr.from_member_id IN (v_m1.id, v_m2.id) OR fr.to_member_id IN (v_m1.id, v_m2.id));
        IF v_count <> 0 THEN
            RAISE EXCEPTION 'Guard failed: % or % already has a spouse relationship row (%)', v_rec.n1, v_rec.n2, v_count;
        END IF;

        -- Use an existing active family of either member, else create one (as in 20261010041000)
        v_family_id := NULL;
        SELECT fm.family_id INTO v_family_id
        FROM public.family_members fm
        WHERE fm.organization_id = v_org_id
          AND fm.member_id IN (v_m1.id, v_m2.id)
          AND fm.membership_status = 'active'
        LIMIT 1;

        IF v_family_id IS NULL THEN
            INSERT INTO public.families (organization_id, family_name, display_name, family_type, family_status, directory_visibility)
            VALUES (v_org_id, 'Family ' || v_rec.n1, 'Family ' || v_rec.n1 || '-' || v_rec.n2, 'married_couple', 'active', 'leaders_only')
            RETURNING id INTO v_family_id;
        END IF;

        INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status)
        VALUES (v_org_id, v_family_id, v_m1.id, 'spouse', 'active')
        ON CONFLICT DO NOTHING;
        INSERT INTO public.family_members (organization_id, family_id, member_id, family_role, membership_status)
        VALUES (v_org_id, v_family_id, v_m2.id, 'spouse', 'active')
        ON CONFLICT DO NOTHING;

        INSERT INTO public.family_relationships (
            organization_id, family_id, from_member_id, to_member_id,
            relationship_type_id, relationship_status, is_primary_relationship,
            verification_status, verified_at, source
        ) VALUES (
            v_org_id, v_family_id, least(v_m1.id, v_m2.id), greatest(v_m1.id, v_m2.id),
            v_spouse_type_id, 'active', true,
            'administrator_verified', clock_timestamp(), 'administrator'
        );

        -- Pair in Couples only when both are active in the same Couples section (any sub-area)
        UPDATE public.section_memberships sm1
        SET paired_member_id = CASE WHEN sm1.member_id = v_m1.id THEN v_m2.id ELSE v_m1.id END,
            updated_at = clock_timestamp()
        WHERE sm1.organization_id = v_org_id
          AND sm1.member_id IN (v_m1.id, v_m2.id)
          AND sm1.membership_status = 'active'
          AND sm1.is_primary = true
          AND (sm1.effective_to IS NULL OR sm1.effective_to >= current_date)
          AND private.section_kind(sm1.section_node_id) = 'couples'
          AND EXISTS (
              SELECT 1 FROM public.section_memberships sm2
              WHERE sm2.organization_id = v_org_id
                AND sm2.member_id = CASE WHEN sm1.member_id = v_m1.id THEN v_m2.id ELSE v_m1.id END
                AND sm2.membership_status = 'active'
                AND sm2.is_primary = true
                AND (sm2.effective_to IS NULL OR sm2.effective_to >= current_date)
                AND sm2.section_node_id = sm1.section_node_id
          );
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RAISE NOTICE 'Spouses %/% linked; couples rows paired: %', v_rec.n1, v_rec.n2, v_count;

        PERFORM private.write_audit_event(
            p_organization_id  => v_org_id,
            p_event_code       => 'family.relationship.added',
            p_event_category   => 'member',
            p_actor_profile_id => NULL,
            p_entity_type      => 'family',
            p_entity_id        => v_family_id,
            p_action           => 'create',
            p_outcome          => 'success',
            p_access_reason    => NULL,
            p_correlation_id   => NULL,
            p_metadata         => jsonb_build_object(
                'migration', '20261010056000_fmc_coordinator_and_spouses',
                'relationship_type', 'spouse',
                'verification_status', 'administrator_verified',
                'member_ids', jsonb_build_array(v_m1.id, v_m2.id),
                'couples_rows_paired', v_count
            )
        );
    END LOOP;

    ---------------------------------------------------------------------------
    -- B. FMC Coordinator: Napoleon & Miriam Rodriguez, at FMC New York
    ---------------------------------------------------------------------------
    SELECT count(*) INTO v_count
    FROM public.leadership_assignments la
    JOIN public.leadership_role_definitions lrd ON lrd.id = la.leadership_role_definition_id
    WHERE la.organization_id = v_org_id AND lrd.code = 'fmc_coordinator' AND la.assignment_status = 'active';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Guard failed: an FMC Coordinator is already active (%)', v_count;
    END IF;

    SELECT m.* INTO STRICT v_m1 FROM public.members m
        WHERE m.organization_id = v_org_id
          AND m.id = (SELECT mi.member_id FROM public.member_identifiers mi
                      WHERE mi.organization_id = v_org_id AND mi.identifier_type = 'member_number'
                        AND mi.is_primary = true AND mi.effective_to IS NULL
                        AND mi.normalized_value = upper('NY10448'));
    SELECT m.* INTO STRICT v_m2 FROM public.members m
        WHERE m.organization_id = v_org_id
          AND m.id = (SELECT mi.member_id FROM public.member_identifiers mi
                      WHERE mi.organization_id = v_org_id AND mi.identifier_type = 'member_number'
                        AND mi.is_primary = true AND mi.effective_to IS NULL
                        AND mi.normalized_value = upper('NY10453'));

    v_res := private.appoint_area_coordinator_core(
        v_org_id, 'fmc_coordinator', v_fmc_ny_id, v_m1.id, current_date, NULL, NULL, 'migration'
    );
    v_assignment_id := (v_res->>'assignment_id')::uuid;

    UPDATE public.leadership_assignments
    SET metadata = metadata || jsonb_build_object('couple_partner_member_id', v_m2.id),
        updated_at = clock_timestamp()
    WHERE id = v_assignment_id;

    -- Guards
    SELECT count(*) INTO v_count
    FROM public.leadership_assignments la
    JOIN public.leadership_role_definitions lrd ON lrd.id = la.leadership_role_definition_id
    WHERE la.organization_id = v_org_id AND lrd.code = 'fmc_coordinator' AND la.assignment_status = 'active'
      AND la.governance_node_id = v_fmc_ny_id AND la.member_id = v_m1.id
      AND la.metadata->>'couple_partner_member_id' = v_m2.id::text;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Guard failed: FMC Coordinator assignment not as expected (%)', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM public.family_relationships fr
    JOIN public.member_identifiers a ON a.member_id = fr.from_member_id AND a.identifier_type = 'member_number' AND a.is_primary AND a.effective_to IS NULL
    JOIN public.member_identifiers b ON b.member_id = fr.to_member_id AND b.identifier_type = 'member_number' AND b.is_primary AND b.effective_to IS NULL
    WHERE fr.organization_id = v_org_id
      AND fr.relationship_type_id = v_spouse_type_id
      AND fr.relationship_status = 'active'
      AND fr.verification_status = 'administrator_verified'
      AND (a.normalized_value, b.normalized_value) IN (('NY10448','NY10453'),('NY10453','NY10448'),('NY10550','NY10551'),('NY10551','NY10550'));
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Guard failed: expected 2 verified spouse rows, got %', v_count;
    END IF;

    RAISE NOTICE 'Pass 6.3: 2 spouse links recorded; FMC Coordinator appointed at fmc_ny.';
END $$;

-- Pass 6.0: New York Area becomes the joint governance node; MFC New York and FMC New York are created under it; existing MFC chapters and sections move under MFC New York. Ministry decision recorded in docs/stages/pass-6-0.md.

-- Pass 6.0: an Area (area_state) may be the primary parent of another Area (MFC New York and FMC New York under the joint New York Area). All other levels keep the strict rank rule.
CREATE OR REPLACE FUNCTION private.validate_governance_relationship()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_parent_rank smallint;
  v_child_rank smallint;
  v_parent_status text;
  v_child_status text;
  v_parent_type_code text;
  v_child_type_code text;
begin
  if new.parent_node_id = new.child_node_id then
    raise exception using
      errcode = '23514',
      message = 'A governance node cannot be its own parent.';
  end if;

  select t.hierarchy_rank, n.lifecycle_status, t.code
    into v_parent_rank, v_parent_status, v_parent_type_code
  from public.governance_nodes n
  join public.governance_node_types t
    on t.id = n.governance_node_type_id
   and t.organization_id = n.organization_id
  where n.organization_id = new.organization_id
    and n.id = new.parent_node_id;

  select t.hierarchy_rank, n.lifecycle_status, t.code
    into v_child_rank, v_child_status, v_child_type_code
  from public.governance_nodes n
  join public.governance_node_types t
    on t.id = n.governance_node_type_id
   and t.organization_id = n.organization_id
  where n.organization_id = new.organization_id
    and n.id = new.child_node_id;

  if v_parent_rank is null or v_child_rank is null then
    raise exception using
      errcode = '23503',
      message = 'Parent or child governance node was not found.';
  end if;

  if new.relationship_type = 'primary_parent'
     and v_parent_rank >= v_child_rank
     and not (v_parent_type_code = 'area_state' and v_child_type_code = 'area_state') then
    raise exception using
      errcode = '23514',
      message = 'A primary parent must have a higher governance rank than its child.';
  end if;

  if new.relationship_status = 'active'
     and (
       v_parent_status in ('closed', 'merged', 'archived')
       or v_child_status in ('closed', 'merged', 'archived')
     ) then
    raise exception using
      errcode = '23514',
      message = 'Closed, merged, or archived nodes cannot receive a new active relationship.';
  end if;

  if new.relationship_status = 'active'
     and new.effective_to is null
     and private.would_create_governance_cycle(
       new.organization_id,
       new.parent_node_id,
       new.child_node_id
     ) then
    raise exception using
      errcode = '23514',
      message = 'The relationship would create a governance hierarchy cycle.';
  end if;

  return new;
end;
$function$;

DO $$
DECLARE
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
    v_ny_id uuid := '86f4745b-bfd3-4e71-bb92-549635fbc873'::uuid;
    v_type_area_id uuid;
    v_mfc_ny_id uuid;
    v_fmc_ny_id uuid;
    v_today date := current_date;
    v_now timestamptz := clock_timestamp();
    v_reparented_count integer := 0;
    v_moved_count integer := 0;
    r_rel record;
    r_placement record;
    v_new_assignment_id uuid;

    -- Guard variables
    v_total_primary_before integer;
    v_total_primary_after integer;
    v_ny_placements_after integer;
    v_mfc_ny_children_count integer;
    v_ny_chapter_section_count integer;
BEGIN
    ----------------------------------------------------------------------------
    -- 0. PRE-CHECK / BASELINE
    ----------------------------------------------------------------------------
    SELECT count(*) INTO v_total_primary_before
    FROM public.member_governance_assignments
    WHERE organization_id = v_org_id
      AND is_primary = true
      AND assignment_status = 'active'
      AND (effective_to IS NULL OR effective_to >= v_today);

    ----------------------------------------------------------------------------
    -- 1. RENAME ny NODE
    ----------------------------------------------------------------------------
    SELECT id INTO STRICT v_type_area_id
    FROM public.governance_node_types
    WHERE organization_id = v_org_id AND code = 'area_state';

    UPDATE public.governance_nodes
    SET name = 'New York Area',
        updated_at = v_now
    WHERE id = v_ny_id AND organization_id = v_org_id;

    ----------------------------------------------------------------------------
    -- 2. CREATE mfc_ny AND fmc_ny NODES
    ----------------------------------------------------------------------------
    INSERT INTO public.governance_nodes (
        organization_id,
        governance_node_type_id,
        code,
        name,
        lifecycle_status,
        effective_from,
        created_at,
        updated_at
    ) VALUES (
        v_org_id,
        v_type_area_id,
        'mfc_ny',
        'MFC New York',
        'active',
        v_today,
        v_now,
        v_now
    )
    ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
    DO UPDATE SET
        name = EXCLUDED.name,
        lifecycle_status = 'active',
        updated_at = v_now
    RETURNING id INTO v_mfc_ny_id;

    IF v_mfc_ny_id IS NULL THEN
        SELECT id INTO STRICT v_mfc_ny_id
        FROM public.governance_nodes
        WHERE organization_id = v_org_id AND code = 'mfc_ny';
    END IF;

    INSERT INTO public.governance_nodes (
        organization_id,
        governance_node_type_id,
        code,
        name,
        lifecycle_status,
        effective_from,
        created_at,
        updated_at
    ) VALUES (
        v_org_id,
        v_type_area_id,
        'fmc_ny',
        'FMC New York',
        'active',
        v_today,
        v_now,
        v_now
    )
    ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
    DO UPDATE SET
        name = EXCLUDED.name,
        lifecycle_status = 'active',
        updated_at = v_now
    RETURNING id INTO v_fmc_ny_id;

    IF v_fmc_ny_id IS NULL THEN
        SELECT id INTO STRICT v_fmc_ny_id
        FROM public.governance_nodes
        WHERE organization_id = v_org_id AND code = 'fmc_ny';
    END IF;

    -- Primary relationships: ny -> mfc_ny, ny -> fmc_ny
    INSERT INTO public.governance_node_relationships (
        organization_id,
        parent_node_id,
        child_node_id,
        relationship_type,
        relationship_status,
        is_primary,
        effective_from,
        created_at,
        updated_at
    ) VALUES
    (v_org_id, v_ny_id, v_mfc_ny_id, 'primary_parent', 'active', true, v_today, v_now, v_now),
    (v_org_id, v_ny_id, v_fmc_ny_id, 'primary_parent', 'active', true, v_today, v_now, v_now);

    ----------------------------------------------------------------------------
    -- 3. RE-PARENT 11 CHILDREN FROM ny TO mfc_ny
    ----------------------------------------------------------------------------
    FOR r_rel IN
        SELECT r.id, r.child_node_id, c.code AS child_code
        FROM public.governance_node_relationships r
        JOIN public.governance_nodes c ON c.id = r.child_node_id
        JOIN public.governance_node_types ct ON ct.id = c.governance_node_type_id
        WHERE r.organization_id = v_org_id
          AND r.parent_node_id = v_ny_id
          AND r.relationship_type = 'primary_parent'
          AND r.is_primary = true
          AND r.relationship_status = 'active'
          AND (r.effective_to IS NULL OR r.effective_to >= v_today)
          AND ct.code IN ('chapter', 'section')
    LOOP
        UPDATE public.governance_node_relationships
        SET relationship_status = 'ended',
            effective_to = v_today,
            ended_at = v_now,
            ending_reason = 'Pass 6.0: Area split — moved under MFC New York',
            updated_at = v_now
        WHERE id = r_rel.id;

        INSERT INTO public.governance_node_relationships (
            organization_id,
            parent_node_id,
            child_node_id,
            relationship_type,
            relationship_status,
            is_primary,
            effective_from,
            created_at,
            updated_at
        ) VALUES (
            v_org_id,
            v_mfc_ny_id,
            r_rel.child_node_id,
            'primary_parent',
            'active',
            true,
            v_today,
            v_now,
            v_now
        );

        v_reparented_count := v_reparented_count + 1;
    END LOOP;

    IF v_reparented_count <> 11 THEN
        RAISE EXCEPTION 'Expected 11 re-parented children, got %', v_reparented_count;
    END IF;

    ----------------------------------------------------------------------------
    -- 4. MOVE ACTIVE PRIMARY PLACEMENTS AT ny TO mfc_ny
    ----------------------------------------------------------------------------
    FOR r_placement IN
        SELECT id, member_id, effective_from
        FROM public.member_governance_assignments
        WHERE organization_id = v_org_id
          AND governance_node_id = v_ny_id
          AND is_primary = true
          AND assignment_status = 'active'
          AND (effective_to IS NULL OR effective_to >= v_today)
    LOOP
        UPDATE public.member_governance_assignments
        SET assignment_status = 'ended',
            effective_to = CASE WHEN effective_from = v_today THEN v_today ELSE v_today - 1 END,
            ending_reason = 'Pass 6.0: Area split — moved to MFC New York',
            updated_at = v_now,
            updated_by_profile_id = NULL
        WHERE id = r_placement.id;

        v_new_assignment_id := gen_random_uuid();
        INSERT INTO public.member_governance_assignments (
            id,
            organization_id,
            member_id,
            governance_node_id,
            assignment_type,
            assignment_status,
            effective_from,
            is_primary,
            assignment_basis,
            created_by_profile_id,
            updated_by_profile_id
        ) VALUES (
            v_new_assignment_id,
            v_org_id,
            r_placement.member_id,
            v_mfc_ny_id,
            'primary',
            'active',
            v_today,
            true,
            'administrative',
            NULL,
            NULL
        );

        PERFORM private.write_audit_event(
            p_organization_id  => v_org_id,
            p_event_code       => 'member.placement.changed',
            p_event_category   => 'governance',
            p_actor_profile_id => NULL,
            p_entity_type      => 'member',
            p_entity_id        => r_placement.member_id,
            p_action           => 'transfer',
            p_outcome          => 'success',
            p_metadata         => jsonb_build_object(
                'previous_assignment_id', r_placement.id,
                'previous_governance_node_id', v_ny_id,
                'target_governance_node_id', v_mfc_ny_id,
                'effective_from', v_today,
                'reason', 'Pass 6.0: Area split — moved to MFC New York'
            )
        );

        v_moved_count := v_moved_count + 1;
    END LOOP;

    ----------------------------------------------------------------------------
    -- 5. SUMMARY AUDIT EVENT
    ----------------------------------------------------------------------------
    PERFORM private.write_audit_event(
        p_organization_id  => v_org_id,
        p_event_code       => 'governance.structure_updated',
        p_event_category   => 'governance',
        p_actor_profile_id => NULL,
        p_entity_type      => 'governance_node',
        p_entity_id        => v_mfc_ny_id,
        p_action           => 'update',
        p_outcome          => 'success',
        p_metadata         => jsonb_build_object(
            'joint_area_node', 'ny',
            'created_nodes', jsonb_build_array('mfc_ny', 'fmc_ny'),
            'reparented_children', jsonb_build_array('alb', 'bq', 'nyc', 'rvc', 'sec_couples', 'sec_handmaids', 'sec_servants', 'sec_singles', 'sec_youth', 'sec_kids', 'sec_campus'),
            'placements_moved_count', v_moved_count
        )
    );

    ----------------------------------------------------------------------------
    -- 6. GUARDS
    ----------------------------------------------------------------------------
    -- Guard 1: 0 active placements left at ny
    SELECT count(*) INTO v_ny_placements_after
    FROM public.member_governance_assignments
    WHERE organization_id = v_org_id
      AND governance_node_id = v_ny_id
      AND assignment_status = 'active'
      AND (effective_to IS NULL OR effective_to >= v_today);

    IF v_ny_placements_after <> 0 THEN
        RAISE EXCEPTION 'Guard failed: % active placements still at ny', v_ny_placements_after;
    END IF;

    -- Guard 2: total active primary placements unchanged
    SELECT count(*) INTO v_total_primary_after
    FROM public.member_governance_assignments
    WHERE organization_id = v_org_id
      AND is_primary = true
      AND assignment_status = 'active'
      AND (effective_to IS NULL OR effective_to >= v_today);

    IF v_total_primary_before <> v_total_primary_after THEN
        RAISE EXCEPTION 'Guard failed: total active primary placements changed from % to %',
            v_total_primary_before, v_total_primary_after;
    END IF;

    -- Guard 3: 11 active primary children under mfc_ny
    SELECT count(*) INTO v_mfc_ny_children_count
    FROM public.governance_node_relationships
    WHERE organization_id = v_org_id
      AND parent_node_id = v_mfc_ny_id
      AND is_primary = true
      AND relationship_status = 'active'
      AND (effective_to IS NULL OR effective_to >= v_today);

    IF v_mfc_ny_children_count <> 11 THEN
        RAISE EXCEPTION 'Guard failed: expected 11 active primary children under mfc_ny, got %', v_mfc_ny_children_count;
    END IF;

    -- Guard 4: 0 active chapter/section children under ny
    SELECT count(*) INTO v_ny_chapter_section_count
    FROM public.governance_node_relationships r
    JOIN public.governance_nodes c ON c.id = r.child_node_id
    JOIN public.governance_node_types ct ON ct.id = c.governance_node_type_id
    WHERE r.organization_id = v_org_id
      AND r.parent_node_id = v_ny_id
      AND r.relationship_status = 'active'
      AND (r.effective_to IS NULL OR r.effective_to >= v_today)
      AND ct.code IN ('chapter', 'section');

    IF v_ny_chapter_section_count <> 0 THEN
        RAISE EXCEPTION 'Guard failed: % active chapter/section children still under ny', v_ny_chapter_section_count;
    END IF;

    RAISE NOTICE 'Pass 6.0 migration completed: reparented=%, moved=%', v_reparented_count, v_moved_count;
END $$;

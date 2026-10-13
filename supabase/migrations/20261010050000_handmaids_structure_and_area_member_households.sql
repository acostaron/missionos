-- Pass 5.2: Handmaids chapter (area-wide) with units mirroring the Couples units; allow member-level households under the Area for Singles/Servants/Campus. Ministry decisions recorded in docs/stages/pass-5-2.md.

DO $$
DECLARE
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
    v_type_chapter uuid;
    v_type_unit uuid;
    v_sec_handmaids_id uuid;
    v_hm_ny_id uuid;
    v_today date := CURRENT_DATE;
    v_now timestamptz := clock_timestamp();
    v_units_created integer := 0;
BEGIN
    ----------------------------------------------------------------------------
    -- RESOLVE NODE TYPES AND PARENT SECTION
    ----------------------------------------------------------------------------
    SELECT id INTO STRICT v_type_chapter
    FROM public.governance_node_types
    WHERE organization_id = v_org_id AND code = 'chapter';

    SELECT id INTO STRICT v_type_unit
    FROM public.governance_node_types
    WHERE organization_id = v_org_id AND code = 'unit';

    SELECT id INTO STRICT v_sec_handmaids_id
    FROM public.governance_nodes
    WHERE organization_id = v_org_id AND code = 'sec_handmaids';

    ----------------------------------------------------------------------------
    -- A. CREATE HANDMAIDS CHAPTER (hm_ny)
    --    Parent: sec_handmaids
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
        v_type_chapter,
        'hm_ny',
        'Handmaids New York Chapter',
        'active',
        v_today,
        v_now,
        v_now
    )
    ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
    DO UPDATE SET
        name = EXCLUDED.name,
        lifecycle_status = 'active',
        updated_at = v_now;

    SELECT id INTO STRICT v_hm_ny_id
    FROM public.governance_nodes
    WHERE organization_id = v_org_id AND code = 'hm_ny';

    -- Detail record in public.chapters
    INSERT INTO public.chapters (
        id,
        organization_id,
        chapter_category,
        created_at,
        updated_at
    ) VALUES (
        v_hm_ny_id,
        v_org_id,
        'standard',
        v_now,
        v_now
    )
    ON CONFLICT (id) DO NOTHING;

    -- Primary relationship: sec_handmaids -> hm_ny
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
        v_sec_handmaids_id,
        v_hm_ny_id,
        'primary_parent',
        'active',
        true,
        v_today,
        v_now,
        v_now
    )
    ON CONFLICT (organization_id, child_node_id)
      WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
    DO NOTHING;

    ----------------------------------------------------------------------------
    -- B. CREATE 8 HANDMAIDS UNIT NODES
    --    Parent: hm_ny
    ----------------------------------------------------------------------------
    CREATE TEMP TABLE _hm_units_staging (
        code text PRIMARY KEY,
        name text NOT NULL
    ) ON COMMIT DROP;

    INSERT INTO _hm_units_staging (code, name) VALUES
        ('hm_rvc_nassau', 'Handmaids Nassau Unit'),
        ('hm_rvc_suffolk', 'Handmaids Suffolk Unit'),
        ('hm_bq_brooklyn', 'Handmaids Brooklyn Unit'),
        ('hm_bq_queens', 'Handmaids Queens Unit'),
        ('hm_nyc_bronx', 'Handmaids Bronx Unit'),
        ('hm_nyc_manhattan', 'Handmaids Manhattan Unit'),
        ('hm_nyc_staten_island', 'Handmaids Staten Island Unit'),
        ('hm_alb_albany', 'Handmaids Albany Unit');

    -- Insert governance_nodes
    INSERT INTO public.governance_nodes (
        organization_id,
        governance_node_type_id,
        code,
        name,
        lifecycle_status,
        effective_from,
        created_at,
        updated_at
    )
    SELECT
        v_org_id,
        v_type_unit,
        s.code,
        s.name,
        'active',
        v_today,
        v_now,
        v_now
    FROM _hm_units_staging s
    ON CONFLICT (organization_id, code) WHERE code IS NOT NULL
    DO UPDATE SET
        name = EXCLUDED.name,
        lifecycle_status = 'active',
        updated_at = v_now;

    GET DIAGNOSTICS v_units_created = ROW_COUNT;

    -- Insert units detail records
    INSERT INTO public.units (id, organization_id, unit_category, created_at, updated_at)
    SELECT gn.id, v_org_id, 'standard', v_now, v_now
    FROM _hm_units_staging s
    JOIN public.governance_nodes gn ON gn.organization_id = v_org_id AND gn.code = s.code
    ON CONFLICT (id) DO NOTHING;

    -- Insert governance_node_relationships (hm_ny -> unit)
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
    )
    SELECT
        v_org_id,
        v_hm_ny_id,
        gn.id,
        'primary_parent',
        'active',
        true,
        v_today,
        v_now,
        v_now
    FROM _hm_units_staging s
    JOIN public.governance_nodes gn ON gn.organization_id = v_org_id AND gn.code = s.code
    ON CONFLICT (organization_id, child_node_id)
      WHERE is_primary AND relationship_status = 'active' AND effective_to IS NULL
    DO NOTHING;

    ----------------------------------------------------------------------------
    -- C. AUDIT EVENT (following summary pattern of Migrations 100 & 101)
    ----------------------------------------------------------------------------
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
        'governance.structure_updated',
        'governance',
        'governance_node',
        v_org_id,
        'create_handmaids_structure',
        'success',
        jsonb_build_object(
            'migration', '20261010050000_handmaids_structure_and_area_member_households',
            'chapter_code', 'hm_ny',
            'units_created', v_units_created,
            'unit_codes', jsonb_build_array(
                'hm_rvc_nassau', 'hm_rvc_suffolk', 'hm_bq_brooklyn', 'hm_bq_queens',
                'hm_nyc_bronx', 'hm_nyc_manhattan', 'hm_nyc_staten_island', 'hm_alb_albany'
            )
        )
    );

    RAISE NOTICE 'Pass 5.2 structure migration completed: chapter=hm_ny, units_created=%', v_units_created;
END $$;

-- -----------------------------------------------------------------------------
-- B2. Update public.create_household to allow 'area_state' for 'member' level
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_household(p_organization_id uuid, p_name text, p_code text, p_parent_governance_node_id uuid, p_household_category text DEFAULT 'pastoral'::text, p_effective_from date DEFAULT CURRENT_DATE, p_meeting_frequency text DEFAULT 'weekly'::text, p_meeting_day_of_week smallint DEFAULT NULL::smallint, p_meeting_start_time time without time zone DEFAULT NULL::time without time zone, p_meeting_timezone_name text DEFAULT 'America/New_York'::text, p_meeting_location_type text DEFAULT 'residence'::text, p_meeting_location_text text DEFAULT NULL::text, p_target_member_count integer DEFAULT NULL::integer, p_maximum_member_count integer DEFAULT NULL::integer, p_accepts_new_members boolean DEFAULT true, p_language_code text DEFAULT 'en'::text, p_is_couple_household boolean DEFAULT false, p_pastoral_level text DEFAULT 'member'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_profile_id             uuid;
  v_hh_type_id             uuid;
  v_parent_node            public.governance_nodes%rowtype;
  v_parent_type            public.governance_node_types%rowtype;
  v_new_household_id       uuid;
  v_name                   text;
  v_code                   text;
  v_household_category     text;
  v_pastoral_level         text;
  v_meeting_frequency      text;
  v_meeting_location_type  text;
  v_meeting_timezone_name  text;
  v_language_code          text;
  v_effective_from         date;
  v_unit_count_under_chap  integer;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('households.records.create', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to create household records.';
  end if;

  -- 4. Scope-safe check: Caller must have scope over parent governance node
  if not private.can_access_governance_node('households.records.create', p_organization_id, p_parent_governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Parent governance node not found or not accessible.';
  end if;

  -- 5. Resolve household governance_node_type
  select gnt.id
  into v_hh_type_id
  from public.governance_node_types gnt
  where gnt.organization_id = p_organization_id
    and gnt.code = 'household'
    and gnt.is_household_type = true
    and gnt.requires_detail_record = true;

  if v_hh_type_id is null then
    raise exception using errcode = '22023', message = 'Household governance node type is not configured for this organization.';
  end if;

  -- 6. Validate Pastoral Level
  v_pastoral_level := lower(trim(coalesce(p_pastoral_level, 'member')));
  if v_pastoral_level not in ('member', 'unit', 'chapter', 'area', 'fraternal') then
    raise exception using errcode = '22023',
      message = 'Invalid pastoral level: "' || v_pastoral_level || '". Allowed values: member, unit, chapter, area, fraternal.';
  end if;

  -- 7. Validate Parent Governance Node
  select *
  into v_parent_node
  from public.governance_nodes gn
  where gn.id = p_parent_governance_node_id
    and gn.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Parent governance node not found or not accessible.';
  end if;

  select *
  into v_parent_type
  from public.governance_node_types gnt
  where gnt.id = v_parent_node.governance_node_type_id
    and gnt.organization_id = p_organization_id;

  -- Parent lifecycle check: Parent must be active
  if v_parent_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Cannot attach a household to a parent node that is not active.';
  end if;

  -- Authoritative parent type validation based on pastoral_level
  if v_pastoral_level = 'member' then
    if v_parent_type.code in ('unit', 'area_state') then
      -- Standard placement under Unit
      null;
    elsif v_parent_type.code = 'chapter' then
      -- Chapter allowed ONLY when there are no active Unit nodes under this Chapter
      select count(*)
      into v_unit_count_under_chap
      from public.governance_node_relationships gnr
      join public.governance_nodes un
        on un.id = gnr.child_node_id
       and un.organization_id = gnr.organization_id
      join public.governance_node_types unt
        on unt.id = un.governance_node_type_id
       and unt.organization_id = un.organization_id
      where gnr.organization_id = p_organization_id
        and gnr.parent_node_id = v_parent_node.id
        and gnr.relationship_type = 'primary_parent'
        and gnr.relationship_status = 'active'
        and (gnr.effective_to is null or gnr.effective_to >= current_date)
        and unt.code = 'unit'
        and un.lifecycle_status = 'active';

      if v_unit_count_under_chap > 0 then
        raise exception using errcode = '22023',
          message = 'Member Household cannot be attached directly to Chapter "' || v_parent_node.name || '" because active Unit structures exist. Member households must be attached to a Unit.';
      end if;
    else
      raise exception using errcode = '22023',
        message = 'Member Household must be placed under a Unit, the Area, or a Chapter with no Units. Parent was "' || v_parent_type.code || '".';
    end if;

  elsif v_pastoral_level = 'unit' then
    if v_parent_type.code != 'unit' then
      raise exception using errcode = '22023',
        message = 'Unit Household must be placed under a Unit. Parent was "' || v_parent_type.code || '".';
    end if;

  elsif v_pastoral_level = 'chapter' then
    if v_parent_type.code != 'chapter' then
      raise exception using errcode = '22023',
        message = 'Chapter Household must be placed under a Chapter. Parent was "' || v_parent_type.code || '".';
    end if;

  elsif v_pastoral_level in ('area', 'fraternal') then
    if v_parent_type.code != 'area_state' then
      raise exception using errcode = '22023',
        message = initcap(v_pastoral_level) || ' Household must be placed under an Area/State governance node. Parent was "' || v_parent_type.code || '".';
    end if;
  end if;

  -- 8. Validate Name
  v_name := trim(coalesce(p_name, ''));
  if v_name = '' then
    raise exception using errcode = '23502', message = 'Household name is required.';
  end if;
  if length(v_name) > 200 then
    raise exception using errcode = '22023', message = 'Household name must not exceed 200 characters.';
  end if;

  -- 9. Validate and normalize Code
  v_code := lower(trim(coalesce(p_code, '')));
  if v_code = '' then
    raise exception using errcode = '23502', message = 'Household code is required.';
  end if;
  if not (v_code ~ '^[a-z][a-z0-9_]*$') then
    raise exception using errcode = '22023', message = 'Household code must begin with a letter and contain only lowercase letters, digits, and underscores.';
  end if;
  if length(v_code) > 50 then
    raise exception using errcode = '22023', message = 'Household code must not exceed 50 characters.';
  end if;

  -- Duplicate code check within organization
  if exists (
    select 1
    from public.governance_nodes gn
    where gn.organization_id = p_organization_id
      and gn.code = v_code
  ) then
    raise exception using errcode = '23505', message = 'A governance node with code "' || v_code || '" already exists in this organization.';
  end if;

  -- 10. Validate Configuration Fields
  v_household_category := trim(coalesce(p_household_category, 'pastoral'));
  if v_household_category not in ('pastoral', 'formation', 'mission', 'temporary', 'welcoming', 'other') then
    raise exception using errcode = '22023', message = 'Invalid household category. Allowed values: pastoral, formation, mission, temporary, welcoming, other.';
  end if;

  v_meeting_frequency := trim(coalesce(p_meeting_frequency, 'weekly'));
  if v_meeting_frequency not in ('weekly', 'biweekly', 'monthly', 'quarterly', 'seasonal', 'variable') then
    raise exception using errcode = '22023', message = 'Invalid meeting frequency. Allowed values: weekly, biweekly, monthly, quarterly, seasonal, variable.';
  end if;

  if p_meeting_day_of_week is not null and (p_meeting_day_of_week < 0 or p_meeting_day_of_week > 6) then
    raise exception using errcode = '22023', message = 'Meeting day of week must be between 0 (Sunday) and 6 (Saturday).';
  end if;

  v_meeting_location_type := trim(coalesce(p_meeting_location_type, 'residence'));
  if v_meeting_location_type not in ('residence', 'church', 'parish_hall', 'online', 'hybrid', 'variable', 'other') then
    raise exception using errcode = '22023', message = 'Invalid meeting location type. Allowed values: residence, church, parish_hall, online, hybrid, variable, other.';
  end if;

  v_meeting_timezone_name := trim(coalesce(p_meeting_timezone_name, 'America/New_York'));
  if not exists (select 1 from public.timezones tz where tz.name = v_meeting_timezone_name) then
    raise exception using errcode = '22023', message = 'Invalid meeting timezone name.';
  end if;

  v_language_code := lower(trim(coalesce(p_language_code, 'en')));
  if not exists (select 1 from public.languages l where l.code = v_language_code) then
    raise exception using errcode = '22023', message = 'Invalid language code.';
  end if;

  if p_target_member_count is not null and p_target_member_count <= 0 then
    raise exception using errcode = '22023', message = 'Target member count must be greater than zero.';
  end if;

  if p_maximum_member_count is not null and p_maximum_member_count <= 0 then
    raise exception using errcode = '22023', message = 'Maximum member count must be greater than zero.';
  end if;

  if p_target_member_count is not null and p_maximum_member_count is not null and p_maximum_member_count < p_target_member_count then
    raise exception using errcode = '22023', message = 'Maximum member count cannot be less than target member count.';
  end if;

  v_effective_from := coalesce(p_effective_from, current_date);

  -- 11. Atomic Multi-Table Creation: Step A: governance_nodes
  v_new_household_id := gen_random_uuid();

  insert into public.governance_nodes (
    id,
    organization_id,
    governance_node_type_id,
    code,
    name,
    lifecycle_status,
    effective_from,
    created_by,
    updated_by
  ) values (
    v_new_household_id,
    p_organization_id,
    v_hh_type_id,
    v_code,
    v_name,
    'active',
    v_effective_from,
    v_profile_id,
    v_profile_id
  );

  -- Step B: specialized public.households row
  insert into public.households (
    id,
    organization_id,
    household_category,
    pastoral_level,
    meeting_frequency,
    meeting_day_of_week,
    meeting_start_time,
    meeting_timezone_name,
    meeting_location_type,
    meeting_location_text,
    target_member_count,
    maximum_member_count,
    accepts_new_members,
    language_code,
    is_couple_household,
    created_by,
    updated_by
  ) values (
    v_new_household_id,
    p_organization_id,
    v_household_category,
    v_pastoral_level,
    v_meeting_frequency,
    p_meeting_day_of_week,
    p_meeting_start_time,
    v_meeting_timezone_name,
    v_meeting_location_type,
    nullif(trim(coalesce(p_meeting_location_text, '')), ''),
    p_target_member_count,
    p_maximum_member_count,
    coalesce(p_accepts_new_members, true),
    v_language_code,
    coalesce(p_is_couple_household, false),
    v_profile_id,
    v_profile_id
  );

  -- Step C: parent governance relationship
  insert into public.governance_node_relationships (
    organization_id,
    parent_node_id,
    child_node_id,
    relationship_type,
    relationship_status,
    is_primary,
    effective_from,
    created_by,
    updated_by
  ) values (
    p_organization_id,
    p_parent_governance_node_id,
    v_new_household_id,
    'primary_parent',
    'active',
    true,
    v_effective_from,
    v_profile_id,
    v_profile_id
  );

  -- Step D: Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household',
    p_entity_id        => v_new_household_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_id',              v_new_household_id,
      'name',                      v_name,
      'code',                      v_code,
      'parent_governance_node_id', p_parent_governance_node_id,
      'parent_node_name',          v_parent_node.name,
      'parent_node_type',          v_parent_type.code,
      'household_category',        v_household_category,
      'pastoral_level',            v_pastoral_level,
      'is_couple_household',       coalesce(p_is_couple_household, false)
    )
  );

  -- 12. Return created contract
  return jsonb_build_object(
    'status',                    'created',
    'household_id',              v_new_household_id,
    'name',                      v_name,
    'code',                      v_code,
    'lifecycle_status',          'active',
    'pastoral_level',            v_pastoral_level,
    'parent_governance_node_id', p_parent_governance_node_id
  );
end;
$function$;

GRANT EXECUTE ON FUNCTION public.create_household TO authenticated, service_role;

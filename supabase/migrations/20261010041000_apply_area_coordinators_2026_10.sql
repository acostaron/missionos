-- =============================================================================
-- Migration 109: apply_area_coordinators_2026_10
--
-- Description:
--   Applies section coordinator appointments, spouse/parent relationships,
--   and sex corrections from staging.coordinator_import ('pass_4_6c').
--   Contains zero member-number literals in the migration code.
-- =============================================================================

do $$
declare
  v_org_id uuid;
  v_spouse_type_id uuid;
  v_parent_of_type_id uuid;
  v_child_of_type_id uuid;
  v_rec record;
  v_app_rec record;
  v_family_id uuid;
  v_canon_from uuid;
  v_canon_to uuid;
  v_existing_spouse_id uuid;
  v_existing_spouse_from uuid;
  v_existing_spouse_to uuid;
  v_created_appointments int := 0;
  v_res jsonb;
  v_couples_singles_coordinators int;
  v_fmc_coordinators int;
  v_total_coordinators int;
begin
  -- Resolve organization
  select id into v_org_id from public.organizations where code = 'mfcny' limit 1;
  if v_org_id is null then
    raise exception using errcode = 'P0002', message = 'Organization mfcny not found.';
  end if;

  -- Precondition: staged rows must exist
  if not exists (
    select 1 from staging.coordinator_import
    where import_batch_code = 'pass_4_6c' and applied_at is null
  ) then
    raise exception using errcode = 'P0002', message = 'No unapplied staging rows found for pass_4_6c.';
  end if;

  -- Resolve family relationship types
  select id into v_spouse_type_id from public.family_relationship_types where code = 'spouse';
  select id into v_parent_of_type_id from public.family_relationship_types where code = 'parent_of';
  select id into v_child_of_type_id from public.family_relationship_types where code = 'child_of';

  -- ---------------------------------------------------------------------------
  -- a. set_sex: set members.sex ONLY where currently NULL
  -- ---------------------------------------------------------------------------
  for v_rec in
    select sci.id as stage_id, m.id as member_id, sci.value as new_sex
    from staging.coordinator_import sci
    join public.members m on m.organization_id = v_org_id and m.member_number = sci.member_number
    where sci.import_batch_code = 'pass_4_6c'
      and sci.action = 'set_sex'
      and m.sex is null
  loop
    update public.members
    set sex = v_rec.new_sex,
        updated_at = clock_timestamp()
    where id = v_rec.member_id;

    update staging.coordinator_import
    set applied_at = clock_timestamp()
    where id = v_rec.stage_id;
  end loop;

  -- Mark any set_sex rows where sex was already populated as applied
  update staging.coordinator_import sci
  set applied_at = clock_timestamp()
  from public.members m
  where m.organization_id = v_org_id
    and m.member_number = sci.member_number
    and sci.import_batch_code = 'pass_4_6c'
    and sci.action = 'set_sex'
    and sci.applied_at is null;

  -- ---------------------------------------------------------------------------
  -- b. spouse relationships and section_memberships.paired_member_id
  -- ---------------------------------------------------------------------------
  for v_rec in
    select sci.id as stage_id,
           m1.id as m1_id, m1.member_number as m1_num,
           m2.id as m2_id, m2.member_number as m2_num
    from staging.coordinator_import sci
    join public.members m1 on m1.organization_id = v_org_id and m1.member_number = sci.member_number
    join public.members m2 on m2.organization_id = v_org_id and m2.member_number = sci.related_member_number
    where sci.import_batch_code = 'pass_4_6c'
      and sci.action = 'spouse'
  loop
    v_canon_from := least(v_rec.m1_id, v_rec.m2_id);
    v_canon_to := greatest(v_rec.m1_id, v_rec.m2_id);

    -- Check if an existing spouse row exists linking either member
    select fr.id, fr.from_member_id, fr.to_member_id, fr.family_id
    into v_existing_spouse_id, v_existing_spouse_from, v_existing_spouse_to, v_family_id
    from public.family_relationships fr
    where fr.organization_id = v_org_id
      and fr.relationship_type_id = v_spouse_type_id
      and (fr.from_member_id in (v_rec.m1_id, v_rec.m2_id) or fr.to_member_id in (v_rec.m1_id, v_rec.m2_id))
    limit 1;

    if v_existing_spouse_id is not null then
      if v_existing_spouse_from = v_canon_from and v_existing_spouse_to = v_canon_to then
        -- Exactly links these two -> mark verified
        update public.family_relationships
        set verification_status = 'administrator_verified',
            verified_at = clock_timestamp(),
            source = 'administrator',
            updated_at = clock_timestamp()
        where id = v_existing_spouse_id;
      else
        -- Linked to another member: per addendum, create verified relationship for these two
        insert into public.families (
          organization_id,
          family_name,
          display_name,
          family_type,
          family_status,
          directory_visibility
        ) values (
          v_org_id,
          'Family ' || v_rec.m1_num,
          'Family ' || v_rec.m1_num || '-' || v_rec.m2_num,
          'married_couple',
          'active',
          'leaders_only'
        ) returning id into v_family_id;

        insert into public.family_members (organization_id, family_id, member_id, family_role, membership_status)
        values
          (v_org_id, v_family_id, v_rec.m1_id, 'spouse', 'active'),
          (v_org_id, v_family_id, v_rec.m2_id, 'spouse', 'active');

        insert into public.family_relationships (
          organization_id, family_id, from_member_id, to_member_id,
          relationship_type_id, relationship_status, is_primary_relationship,
          verification_status, verified_at, source
        ) values (
          v_org_id, v_family_id, v_canon_from, v_canon_to,
          v_spouse_type_id, 'active', true,
          'administrator_verified', clock_timestamp(), 'administrator'
        );
      end if;
    else
      -- Check if either member belongs to an active family
      select fm.family_id into v_family_id
      from public.family_members fm
      where fm.organization_id = v_org_id
        and fm.member_id in (v_rec.m1_id, v_rec.m2_id)
        and fm.membership_status = 'active'
      limit 1;

      if v_family_id is null then
        insert into public.families (
          organization_id,
          family_name,
          display_name,
          family_type,
          family_status,
          directory_visibility
        ) values (
          v_org_id,
          'Family ' || v_rec.m1_num,
          'Family ' || v_rec.m1_num || '-' || v_rec.m2_num,
          'married_couple',
          'active',
          'leaders_only'
        ) returning id into v_family_id;
      end if;

      insert into public.family_members (organization_id, family_id, member_id, family_role, membership_status)
      values
        (v_org_id, v_family_id, v_rec.m1_id, 'spouse', 'active')
      on conflict do nothing;

      insert into public.family_members (organization_id, family_id, member_id, family_role, membership_status)
      values
        (v_org_id, v_family_id, v_rec.m2_id, 'spouse', 'active')
      on conflict do nothing;

      insert into public.family_relationships (
        organization_id, family_id, from_member_id, to_member_id,
        relationship_type_id, relationship_status, is_primary_relationship,
        verification_status, verified_at, source
      ) values (
        v_org_id, v_family_id, v_canon_from, v_canon_to,
        v_spouse_type_id, 'active', true,
        'administrator_verified', clock_timestamp(), 'administrator'
      );
    end if;

    -- Set section_memberships.paired_member_id if both are sec_couples
    update public.section_memberships sm1
    set paired_member_id = v_rec.m2_id,
        updated_at = clock_timestamp()
    where sm1.organization_id = v_org_id
      and sm1.member_id = v_rec.m1_id
      and sm1.membership_status = 'active'
      and sm1.section_node_id in (select id from public.governance_nodes where organization_id = v_org_id and code = 'sec_couples')
      and exists (
        select 1 from public.section_memberships sm2
        where sm2.organization_id = v_org_id
          and sm2.member_id = v_rec.m2_id
          and sm2.membership_status = 'active'
          and sm2.section_node_id = sm1.section_node_id
      );

    update public.section_memberships sm2
    set paired_member_id = v_rec.m1_id,
        updated_at = clock_timestamp()
    where sm2.organization_id = v_org_id
      and sm2.member_id = v_rec.m2_id
      and sm2.membership_status = 'active'
      and sm2.section_node_id in (select id from public.governance_nodes where organization_id = v_org_id and code = 'sec_couples')
      and exists (
        select 1 from public.section_memberships sm1
        where sm1.organization_id = v_org_id
          and sm1.member_id = v_rec.m1_id
          and sm1.membership_status = 'active'
          and sm1.section_node_id = sm2.section_node_id
      );

    update staging.coordinator_import
    set applied_at = clock_timestamp()
    where id = v_rec.stage_id;
  end loop;

  -- ---------------------------------------------------------------------------
  -- Parent relationships (Addendum)
  -- ---------------------------------------------------------------------------
  for v_rec in
    select sci.id as stage_id,
           mp.id as parent_id, mp.member_number as parent_num,
           mc.id as child_id, mc.member_number as child_num
    from staging.coordinator_import sci
    join public.members mp on mp.organization_id = v_org_id and mp.member_number = sci.member_number
    join public.members mc on mc.organization_id = v_org_id and mc.member_number = sci.related_member_number
    where sci.import_batch_code = 'pass_4_6c'
      and sci.action = 'parent'
  loop
    select fm.family_id into v_family_id
    from public.family_members fm
    where fm.organization_id = v_org_id
      and fm.member_id = v_rec.parent_id
      and fm.membership_status = 'active'
    limit 1;

    if v_family_id is null then
      raise exception using errcode = 'P0002', message = 'Parent family not found for member in staging row.';
    end if;

    insert into public.family_members (organization_id, family_id, member_id, family_role, membership_status)
    values (v_org_id, v_family_id, v_rec.child_id, 'child', 'active')
    on conflict do nothing;

    insert into public.family_relationships (
      organization_id, family_id, from_member_id, to_member_id,
      relationship_type_id, relationship_status, is_primary_relationship,
      verification_status, verified_at, source
    ) values (
      v_org_id, v_family_id, v_rec.parent_id, v_rec.child_id,
      v_parent_of_type_id, 'active', true,
      'administrator_verified', clock_timestamp(), 'administrator'
    );

    insert into public.family_relationships (
      organization_id, family_id, from_member_id, to_member_id,
      relationship_type_id, relationship_status, is_primary_relationship,
      verification_status, verified_at, source
    ) values (
      v_org_id, v_family_id, v_rec.child_id, v_rec.parent_id,
      v_child_of_type_id, 'active', true,
      'administrator_verified', clock_timestamp(), 'administrator'
    );

    update staging.coordinator_import
    set applied_at = clock_timestamp()
    where id = v_rec.stage_id;
  end loop;

  -- ---------------------------------------------------------------------------
  -- c. appoint & appoint_exception rows
  -- ---------------------------------------------------------------------------
  for v_app_rec in
    select sci.id as stage_id,
           sci.action,
           m.id as member_id,
           gn.id as section_node_id,
           sci.value as section_code,
           case
             when sci.action = 'appoint_exception'
             then 'Approved exception: Singles member serving as Kids Coordinator (confirmed by organization administrator, 2026-10-11)'
             else null
           end as exception_reason
    from staging.coordinator_import sci
    join public.members m on m.organization_id = v_org_id and m.member_number = sci.member_number
    join public.governance_nodes gn on gn.organization_id = v_org_id and gn.code = sci.value
    where sci.import_batch_code = 'pass_4_6c'
      and sci.action in ('appoint', 'appoint_exception')
    order by sci.id
  loop
    v_res := private.appoint_area_coordinator_core(
      p_organization_id  => v_org_id,
      p_role_code        => 'area_section_coordinator',
      p_node_id          => v_app_rec.section_node_id,
      p_member_id        => v_app_rec.member_id,
      p_effective_from   => current_date,
      p_exception_reason => v_app_rec.exception_reason,
      p_actor_profile_id => null,
      p_source           => 'pass_4_6c'
    );

    v_created_appointments := v_created_appointments + 1;

    update staging.coordinator_import
    set applied_at = clock_timestamp()
    where id = v_app_rec.stage_id;
  end loop;

  -- ---------------------------------------------------------------------------
  -- d. Guards
  -- ---------------------------------------------------------------------------
  select count(*) into v_total_coordinators
  from public.leadership_assignments la
  join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
  where la.organization_id = v_org_id
    and lrd.code = 'area_section_coordinator'
    and la.assignment_status = 'active';

  if v_total_coordinators != 5 then
    raise exception using errcode = '23514',
      message = 'Guard failed: expected exactly 5 active area_section_coordinator assignments, found ' || v_total_coordinators;
  end if;

  select count(*) into v_couples_singles_coordinators
  from public.leadership_assignments la
  join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
  join public.governance_nodes gn on gn.id = la.governance_node_id
  where la.organization_id = v_org_id
    and lrd.code = 'area_section_coordinator'
    and la.assignment_status = 'active'
    and gn.code in ('sec_couples', 'sec_singles');

  if v_couples_singles_coordinators != 0 then
    raise exception using errcode = '23514',
      message = 'Guard failed: expected 0 coordinators for sec_couples and sec_singles, found ' || v_couples_singles_coordinators;
  end if;

  select count(*) into v_fmc_coordinators
  from public.leadership_assignments la
  join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
  where la.organization_id = v_org_id
    and lrd.code = 'fmc_coordinator'
    and la.assignment_status = 'active';

  if v_fmc_coordinators != 0 then
    raise exception using errcode = '23514',
      message = 'Guard failed: FMC coordinator should be untouched (0 active), found ' || v_fmc_coordinators;
  end if;

  perform private.write_audit_event(
    p_organization_id  => v_org_id,
    p_event_code       => 'area_section_coordinators.batch_applied',
    p_event_category   => 'governance',
    p_actor_profile_id => null,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => null,
    p_action           => 'batch_appoint',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'batch_code', 'pass_4_6c',
      'appointments_created', v_created_appointments
    )
  );
end $$;

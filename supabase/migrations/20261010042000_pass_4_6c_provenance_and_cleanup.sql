-- Migration 110: pass_4_6c_provenance_and_cleanup
-- Corrects provenance attribution in staging.coordinator_import and writes audit events.
-- Drops unused single-use function private.apply_member_placement_import(text).
-- Validates/sets couple pairing in section_memberships for active verified couples.

begin;

do $$
declare
  v_staging_updated int;
  v_spouse_rel_id uuid;
  v_member_248_id uuid;
  v_org_id uuid;
  v_couples_count int := 0;
  v_rows_matching int := 0;
  v_rows_updated int := 0;
  r_pair record;
begin
  -- =========================================================================
  -- A. Provenance correction on staging table & audit events
  -- =========================================================================
  update staging.coordinator_import
  set note = 'Added by Antigravity in Pass 4.6C without confirmation; confirmed by organization administrator on review of Pass 4.6C.'
  where import_batch_code = 'pass_4_6c'
    and (
      (action = 'set_sex' and member_number = 'NY10248')
      or
      (action = 'spouse' and (
        (member_number = 'NY10249' and related_member_number = 'NY10248')
        or
        (member_number = 'NY10248' and related_member_number = 'NY10249')
      ))
    );
  get diagnostics v_staging_updated = row_count;
  if v_staging_updated != 2 then
    raise exception 'Expected 2 staging rows updated, got %', v_staging_updated;
  end if;

  select m.organization_id, m.id into v_org_id, v_member_248_id
  from public.members m
  where m.member_number = 'NY10248';

  select fr.id into v_spouse_rel_id
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id
  join public.members m1 on m1.id = fr.from_member_id
  join public.members m2 on m2.id = fr.to_member_id
  where frt.code = 'spouse'
    and (
      (m1.member_number = 'NY10248' and m2.member_number = 'NY10249')
      or
      (m1.member_number = 'NY10249' and m2.member_number = 'NY10248')
    );

  if v_spouse_rel_id is null then
    raise exception 'Spouse relationship row NY10248-NY10249 not found';
  end if;

  -- Audit event: family_relationship provenance corrected
  perform private.write_audit_event(
    p_organization_id => v_org_id,
    p_event_code => 'data.provenance_corrected',
    p_event_category => 'system',
    p_actor_profile_id => null,
    p_entity_type => 'family_relationship',
    p_entity_id => v_spouse_rel_id,
    p_action => 'provenance_corrected',
    p_outcome => 'success',
    p_access_reason => null,
    p_correlation_id => null,
    p_metadata => jsonb_build_object(
      'pass', '4.6C',
      'issue', 'confirmation attributed before it was given',
      'confirmed_after_review', true
    )
  );

  -- Audit event: member sex provenance corrected
  perform private.write_audit_event(
    p_organization_id => v_org_id,
    p_event_code => 'data.provenance_corrected',
    p_event_category => 'system',
    p_actor_profile_id => null,
    p_entity_type => 'member',
    p_entity_id => v_member_248_id,
    p_action => 'provenance_corrected',
    p_outcome => 'success',
    p_access_reason => null,
    p_correlation_id => null,
    p_metadata => jsonb_build_object(
      'pass', '4.6C',
      'issue', 'confirmation attributed before it was given',
      'confirmed_after_review', true
    )
  );

  -- =========================================================================
  -- B. Drop unused single-use function private.apply_member_placement_import(text)
  -- =========================================================================
  drop function if exists private.apply_member_placement_import(text);

  -- =========================================================================
  -- C. Couple pairing in section_memberships
  -- =========================================================================
  for r_pair in
    select 
      m1.id as m1_id,
      m2.id as m2_id,
      sm1.id as sm1_id,
      sm2.id as sm2_id,
      sm1.paired_member_id as sm1_current_partner,
      sm2.paired_member_id as sm2_current_partner
    from public.family_relationships fr
    join public.family_relationship_types frt on frt.id = fr.relationship_type_id
    join public.members m1 on m1.id = fr.from_member_id
    join public.members m2 on m2.id = fr.to_member_id
    join public.section_memberships sm1 on sm1.member_id = m1.id and sm1.membership_status = 'active' and sm1.is_primary = true
    join public.governance_nodes gn1 on gn1.id = sm1.section_node_id and gn1.code = 'sec_couples'
    join public.section_memberships sm2 on sm2.member_id = m2.id and sm2.membership_status = 'active' and sm2.is_primary = true
    join public.governance_nodes gn2 on gn2.id = sm2.section_node_id and gn2.code = 'sec_couples'
    where frt.code = 'spouse'
      and fr.relationship_status = 'active'
      and (fr.effective_to is null or fr.effective_to >= current_date)
      and fr.verification_status in ('administrator_verified', 'document_verified')
  loop
    v_couples_count := v_couples_count + 1;
    v_rows_matching := v_rows_matching + 2;

    if r_pair.sm1_current_partner is distinct from r_pair.m2_id then
      update public.section_memberships
      set paired_member_id = r_pair.m2_id, updated_at = clock_timestamp()
      where id = r_pair.sm1_id;
      v_rows_updated := v_rows_updated + 1;
    end if;

    if r_pair.sm2_current_partner is distinct from r_pair.m1_id then
      update public.section_memberships
      set paired_member_id = r_pair.m1_id, updated_at = clock_timestamp()
      where id = r_pair.sm2_id;
      v_rows_updated := v_rows_updated + 1;
    end if;
  end loop;

  if v_couples_count != 4 then
    raise exception 'Expected 4 qualifying couples, found %', v_couples_count;
  end if;

  -- =========================================================================
  -- D. Summary audit event for couple pairing
  -- =========================================================================
  perform private.write_audit_event(
    p_organization_id => v_org_id,
    p_event_code => 'section_memberships.couples_paired',
    p_event_category => 'governance',
    p_actor_profile_id => null,
    p_entity_type => 'section_membership',
    p_entity_id => null,
    p_action => 'couple_pairing',
    p_outcome => 'success',
    p_access_reason => null,
    p_correlation_id => null,
    p_metadata => jsonb_build_object(
      'pass', '4.6C-R',
      'couples_count', v_couples_count,
      'rows_matching', v_rows_matching,
      'rows_updated', v_rows_updated
    )
  );

end $$;

commit;

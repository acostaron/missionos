-- Pass 6.1A-Fix: restore three functions that migration 20261010053000 rewrote beyond the intended change.
-- Each body below is the previous committed definition, verbatim, with ONLY the section-code tests replaced by section-kind tests:
--   private.section_coordinator_eligibility  <- 20261010040000 (+ kind tests)
--   private.appoint_area_coordinator_core    <- 20261010040000 (+ kind tests)
--   public.change_members_section_bulk       <- 20261010047000 (+ kind test)
-- Fixes: coordinator appointment inserting into non-existent columns (assignment_basis, created_by) and dropping the history row;
-- eligibility losing the "Record the member's sex first." rule; bulk section change losing per-member error handling and
-- the response fields the app reads (section_code, effective_from, correlation_id).
-- change_members_section_bulk keeps the parameter defaults added by 20261010053000 (Postgres cannot remove defaults).

create or replace function private.section_coordinator_eligibility(
  p_org uuid,
  p_member uuid,
  p_section_node uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member public.members%rowtype;
  v_section_node public.governance_nodes%rowtype;
  v_member_section_code text;
  v_spouse_member_id uuid;
  v_has_active_verified_spouse boolean := false;
begin
  -- 1. Candidate member check
  select *
  into v_member
  from public.members m
  where m.id = p_member
    and m.organization_id = p_org;

  if not found or v_member.record_status != 'active' then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'member_inactive',
      'message', 'Candidate member record is not active.'
    );
  end if;

  if v_member.is_deceased then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'member_deceased',
      'message', 'Cannot appoint a deceased member as coordinator.'
    );
  end if;

  -- 2. Sex check
  if v_member.sex is null then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'sex_null',
      'message', 'Record the member''s sex first.'
    );
  end if;

  -- 3. Target section node check
  select *
  into v_section_node
  from public.governance_nodes gn
  where gn.id = p_section_node
    and gn.organization_id = p_org;

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'section_not_found',
      'message', 'Section node not found.'
    );
  end if;

  -- Couples sections (any sub-area) have no coordinator
  if private.section_kind(v_section_node.id) = 'couples' then
    return jsonb_build_object(
      'eligible', false,
      'rule_failed', 'sec_couples_no_coordinator',
      'message', 'Couples section does not have an area coordinator.'
    );
  end if;

  -- 4. Member primary section placement (by section kind)
  select private.section_kind(sm.section_node_id)
  into v_member_section_code
  from public.section_memberships sm
  where sm.organization_id = p_org
    and sm.member_id = p_member
    and sm.membership_status = 'active'
    and sm.is_primary = true
  limit 1;

  -- 5. Active verified spouse check
  select (case when fr.from_member_id = p_member then fr.to_member_id else fr.from_member_id end)
  into v_spouse_member_id
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id
  where fr.organization_id = p_org
    and frt.code = 'spouse'
    and fr.relationship_status = 'active'
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and fr.verification_status in ('administrator_verified', 'document_verified')
    and (fr.from_member_id = p_member or fr.to_member_id = p_member)
  limit 1;

  if v_spouse_member_id is not null then
    select exists (
      select 1
      from public.members sp
      where sp.id = v_spouse_member_id
        and sp.organization_id = p_org
        and sp.record_status = 'active'
        and not sp.is_deceased
    ) into v_has_active_verified_spouse;
  end if;

  -- 6. Evaluate section-specific rules
  case private.section_kind(v_section_node.id)
    when 'handmaids' then
      if v_member.sex != 'female' then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'handmaids_female_only',
          'message', 'Handmaids section coordinator must be female.'
        );
      end if;

      if not (v_member_section_code = 'handmaids' or (v_member_section_code = 'couples' and v_has_active_verified_spouse)) then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'handmaids_section_or_couples_spouse',
          'message', 'Handmaids coordinator must be in Handmaids section or in Couples with an active verified spouse.'
        );
      end if;

    when 'servants' then
      if v_member.sex != 'male' then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'servants_male_only',
          'message', 'Servants section coordinator must be male.'
        );
      end if;

      if not (v_member_section_code = 'servants' or (v_member_section_code = 'couples' and v_has_active_verified_spouse)) then
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'servants_section_or_couples_spouse',
          'message', 'Servants coordinator must be in Servants section or in Couples with an active verified spouse.'
        );
      end if;

    when 'kids', 'youth', 'singles', 'campus' then
      -- Rule: a couple (male holder in Couples with an active verified spouse) OR a male member
      if (v_member.sex = 'male' and v_member_section_code = 'couples' and v_has_active_verified_spouse)
         or (v_member.sex = 'male') then
        null;
      else
        return jsonb_build_object(
          'eligible', false,
          'rule_failed', 'family_section_couple_or_male',
          'message', 'Section coordinator for ' || coalesce(v_section_node.name, v_section_node.code) || ' must be a couple (husband in Couples with active verified spouse) or a male member.'
        );
      end if;

    else
      return jsonb_build_object(
        'eligible', false,
        'rule_failed', 'unsupported_section',
        'message', 'Unsupported section code for section coordinator: ' || v_section_node.code
      );
  end case;

  return jsonb_build_object(
    'eligible', true,
    'rule_failed', null,
    'message', 'Candidate member is eligible.'
  );
end;
$$;

create or replace function private.appoint_area_coordinator_core(
  p_organization_id uuid,
  p_role_code text,
  p_node_id uuid,
  p_member_id uuid,
  p_effective_from date default current_date,
  p_exception_reason text default null,
  p_actor_profile_id uuid default null,
  p_source text default 'appoint_area_coordinator'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_role_code text;
  v_effective_from date;
  v_node public.governance_nodes%rowtype;
  v_node_type public.governance_node_types%rowtype;
  v_role_def public.leadership_role_definitions%rowtype;
  v_member public.members%rowtype;
  v_eligibility jsonb;
  v_is_exception boolean := false;
  v_exception_reason text := null;
  v_rule_failed text := null;
  v_existing_active_id uuid;
  v_partner_member_id uuid;
  v_couple_partner_id uuid := null;
  v_new_assignment_id uuid := gen_random_uuid();
  v_now timestamptz := clock_timestamp();
  v_metadata jsonb;
begin
  -- 1. Canonical Role Code validation
  v_role_code := lower(trim(coalesce(p_role_code, '')));
  if v_role_code not in ('area_section_coordinator', 'fmc_coordinator') then
    raise exception using errcode = '22023',
      message = 'Invalid coordinator role code: "' || v_role_code || '". Allowed canonical codes: area_section_coordinator, fmc_coordinator.';
  end if;

  v_effective_from := coalesce(p_effective_from, current_date);

  -- 2. Lock target governance node FOR UPDATE
  select *
  into v_node
  from public.governance_nodes gn
  where gn.id = p_node_id
    and gn.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  if v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Coordinators may only be appointed to active governance nodes.';
  end if;

  -- Reject Couples sections (any sub-area)
  if private.section_kind(v_node.id) = 'couples' then
    raise exception using errcode = '22023', message = 'Couples section does not have an area coordinator.';
  end if;

  -- 3. Resolve role definition
  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.organization_id = p_organization_id
    and lrd.code = v_role_code
    and lrd.is_active = true;

  if not found then
    raise exception using errcode = '22023', message = 'Leadership role "' || v_role_code || '" is not configured or active.';
  end if;

  -- 4. Validate node type matches leadership_role_node_types
  select gnt.*
  into v_node_type
  from public.governance_node_types gnt
  join public.leadership_role_node_types lrnt on lrnt.governance_node_type_id = gnt.id
  where lrnt.organization_id = p_organization_id
    and lrnt.leadership_role_definition_id = v_role_def.id
    and lrnt.is_active = true
    and gnt.id = v_node.governance_node_type_id;

  if not found then
    raise exception using errcode = '22023',
      message = 'Governance node type is not compatible with leadership role "' || v_role_code || '".';
  end if;

  -- 5. Candidate Member Validation
  select *
  into v_member
  from public.members m
  where m.id = p_member_id
    and m.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidate member not found.';
  end if;

  if v_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Candidate member record is not active.';
  end if;

  if v_member.is_deceased then
    raise exception using errcode = '22023', message = 'Cannot appoint a deceased member as coordinator.';
  end if;

  -- 6. Eligibility check (for area_section_coordinator)
  if v_role_code = 'area_section_coordinator' then
    v_eligibility := private.section_coordinator_eligibility(p_organization_id, p_member_id, p_node_id);
    if not (v_eligibility->>'eligible')::boolean then
      if p_exception_reason is null or trim(p_exception_reason) = '' then
        raise exception using errcode = '22023',
          message = coalesce(v_eligibility->>'message', 'Candidate member is not eligible for this section coordinator role.');
      else
        v_is_exception := true;
        v_exception_reason := trim(p_exception_reason);
        v_rule_failed := v_eligibility->>'rule_failed';
      end if;
    end if;
  end if;

  -- 7. At most ONE active assignment per (role, node)
  select la.id
  into v_existing_active_id
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date)
  limit 1;

  if v_existing_active_id is not null then
    raise exception using errcode = '23505',
      message = 'This section already has an active coordinator.';
  end if;

  -- 8. Couple partner detection
  select (case when fr.from_member_id = p_member_id then fr.to_member_id else fr.from_member_id end)
  into v_partner_member_id
  from public.family_relationships fr
  join public.family_relationship_types frt on frt.id = fr.relationship_type_id
  where fr.organization_id = p_organization_id
    and frt.code = 'spouse'
    and fr.relationship_status = 'active'
    and (fr.effective_to is null or fr.effective_to >= current_date)
    and fr.verification_status in ('administrator_verified', 'document_verified')
    and (fr.from_member_id = p_member_id or fr.to_member_id = p_member_id)
  limit 1;

  -- Handmaids exception: the woman holds office herself; Servants: brother holds office.
  -- Family sections (Campus, Youth, Kids, Singles) recognize couple partner when spouse is active and verified.
  if private.section_kind(v_node.id) in ('campus', 'youth', 'singles', 'kids') and v_partner_member_id is not null then
    v_couple_partner_id := v_partner_member_id;
  end if;

  -- 9. Build metadata
  v_metadata := jsonb_build_object(
    'role_code', v_role_code,
    'source', p_source
  );

  if p_actor_profile_id is not null then
    v_metadata := v_metadata || jsonb_build_object('appointed_by_profile', p_actor_profile_id);
  end if;

  if v_couple_partner_id is not null then
    v_metadata := v_metadata || jsonb_build_object('couple_partner_member_id', v_couple_partner_id);
  end if;

  if v_is_exception then
    v_metadata := v_metadata || jsonb_build_object(
      'eligibility_exception', true,
      'exception_reason', v_exception_reason,
      'rule_failed', v_rule_failed
    );
  end if;

  -- 10. Insert active leadership_assignment
  insert into public.leadership_assignments (
    id,
    organization_id,
    member_id,
    governance_node_id,
    leadership_role_definition_id,
    paired_assignment_id,
    assignment_status,
    appointment_type,
    effective_from,
    effective_to,
    proposed_at,
    proposed_by_profile_id,
    approved_at,
    approved_by_profile_id,
    accepted_at,
    activated_at,
    appointment_summary,
    metadata,
    created_at,
    created_by_profile_id,
    updated_at,
    updated_by_profile_id
  ) values (
    v_new_assignment_id,
    p_organization_id,
    p_member_id,
    p_node_id,
    v_role_def.id,
    null,
    'active',
    'regular',
    v_effective_from,
    null,
    v_now,
    p_actor_profile_id,
    v_now,
    p_actor_profile_id,
    v_now,
    v_now,
    case when v_is_exception then v_exception_reason else 'Appointed ' || v_role_def.name end,
    v_metadata,
    v_now,
    p_actor_profile_id,
    v_now,
    p_actor_profile_id
  );

  -- 11. History row
  insert into public.leadership_assignment_history (
    organization_id,
    leadership_assignment_id,
    previous_status,
    new_status,
    change_type,
    previous_state,
    new_state,
    change_summary,
    effective_at,
    actor_profile_id,
    source
  ) values (
    p_organization_id,
    v_new_assignment_id,
    null,
    'active',
    'activated',
    null,
    jsonb_build_object(
      'member_id', p_member_id,
      'governance_node_id', p_node_id,
      'role_code', v_role_code,
      'effective_from', v_effective_from,
      'eligibility_exception', v_is_exception
    ),
    case when v_is_exception then v_exception_reason else 'Coordinator appointed.' end,
    v_now,
    p_actor_profile_id,
    case
      when p_source in ('application', 'database_function', 'import', 'migration', 'administrator') then p_source
      else 'database_function'
    end
  );

  -- 12. Audit event (NO PII)
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'area_coordinator.appointed',
    p_event_category   => 'governance',
    p_actor_profile_id => p_actor_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => v_new_assignment_id,
    p_action           => 'appoint',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'role_code',            v_role_code,
      'governance_node_id',   p_node_id,
      'governance_node_code', v_node.code,
      'member_id',            p_member_id,
      'couple_partner_id',    v_couple_partner_id,
      'is_exception',         v_is_exception,
      'effective_from',       v_effective_from
    )
  );

  return jsonb_build_object(
    'assignment_id',            v_new_assignment_id,
    'role',                     v_role_code,
    'node_code',                v_node.code,
    'member_id',                p_member_id,
    'couple_partner_member_id', v_couple_partner_id,
    'exception_flag',           v_is_exception
  );
end;
$$;

create or replace function public.change_members_section_bulk(
  p_organization_id uuid,
  p_member_ids uuid[],
  p_section_code text,
  p_effective_from date default current_date,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor_profile_id   uuid;
  v_target_node        public.governance_nodes%rowtype;
  v_deduped_member_ids uuid[];
  v_requested_count    integer;
  v_member_id          uuid;
  v_member             public.members%rowtype;
  v_correlation_id     uuid;
  v_res                jsonb;
  v_changed            jsonb := '[]'::jsonb;
  v_skipped            jsonb := '[]'::jsonb;
  v_changed_ids        uuid[] := array[]::uuid[];
begin
  -- 1. Authentication
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  -- 2. Organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- 3. Permission check (the SAME permission condition change_member_section uses, checked once up front)
  if not (
    private.has_permission('members.records.update', p_organization_id)
    or private.has_permission('members.placements.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission to manage member section.';
  end if;

  -- 4. Reason validation
  if p_reason is null or length(btrim(p_reason)) < 5 then
    raise exception using errcode = '22023', message = 'A reason of at least 5 characters is required.';
  end if;

  -- 5. Effective date validation
  if p_effective_from is null or p_effective_from > current_date then
    raise exception using errcode = '22023', message = 'Effective date cannot be in the future.';
  end if;

  -- 6. Section validation
  if p_section_code is null then
    raise exception using errcode = '22023', message = 'Choose a valid section.';
  end if;

  select * into v_target_node
  from public.governance_nodes gn
  where gn.organization_id = p_organization_id
    and gn.code = p_section_code
    and gn.lifecycle_status = 'active';

  if not found or not (
    exists (
      select 1 from public.governance_node_types gnt
      where gnt.id = v_target_node.governance_node_type_id
        and gnt.code = 'section'
    )
    and private.section_kind(v_target_node.id) is not null
  ) then
    raise exception using errcode = '22023', message = 'Choose a valid section.';
  end if;

  -- 7. Member IDs deduplication & bounds check
  select coalesce(array_agg(mid order by min_ord), array[]::uuid[])
  into v_deduped_member_ids
  from (
    select mid, min(ord) as min_ord
    from unnest(coalesce(p_member_ids, array[]::uuid[])) with ordinality as u(mid, ord)
    where mid is not null
    group by mid
  ) s;

  v_requested_count := coalesce(cardinality(v_deduped_member_ids), 0);

  if v_requested_count = 0 then
    raise exception using errcode = '22023', message = 'Select at least one member.';
  end if;

  if v_requested_count > 100 then
    raise exception using errcode = '22023', message = 'You can change at most 100 members at a time.';
  end if;

  v_correlation_id := gen_random_uuid();

  -- 8. Process each member
  foreach v_member_id in array v_deduped_member_ids loop
    select * into v_member
    from public.members
    where id = v_member_id
      and organization_id = p_organization_id;

    if not found then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'not_found'
      ));
    elsif v_member.record_status <> 'active' then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'record_not_active'
      ));
    elsif coalesce(v_member.is_deceased, false) then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'deceased'
      ));
    elsif v_member.primary_section_node_id = v_target_node.id then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'already_in_section'
      ));
    else
      begin
        v_res := public.change_member_section(
          p_organization_id => p_organization_id,
          p_member_id       => v_member_id,
          p_section_code    => p_section_code,
          p_effective_from  => p_effective_from,
          p_reason          => btrim(p_reason)
        );

        v_changed := v_changed || jsonb_build_array(jsonb_build_object(
          'member_id', v_member_id,
          'previous_section_code', v_res->>'previous_section_code'
        ));
        v_changed_ids := array_append(v_changed_ids, v_member_id);
      exception when others then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
          'member_id', v_member_id,
          'reason', 'error',
          'message', sqlerrm
        ));
      end;
    end if;
  end loop;

  -- 9. Write summary audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.section.bulk_changed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'governance_node',
    p_entity_id        => v_target_node.id,
    p_action           => 'bulk_section_change',
    p_outcome          => 'success',
    p_correlation_id   => v_correlation_id,
    p_metadata         => jsonb_build_object(
      'requested_count',    v_requested_count,
      'changed_count',      jsonb_array_length(v_changed),
      'skipped_count',      jsonb_array_length(v_skipped),
      'section_code',       p_section_code,
      'effective_from',     p_effective_from,
      'reason',             btrim(p_reason),
      'changed_member_ids', to_jsonb(v_changed_ids)
    )
  );

  -- 10. Return response
  return jsonb_build_object(
    'status',          'success',
    'section_code',    p_section_code,
    'effective_from',  p_effective_from,
    'changed_count',   jsonb_array_length(v_changed),
    'skipped_count',   jsonb_array_length(v_skipped),
    'changed',         v_changed,
    'skipped',         v_skipped,
    'correlation_id',  v_correlation_id
  );
end;
$$;

-- Guards: the restored definitions are live.
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc where oid = 'private.appoint_area_coordinator_core(uuid, text, uuid, uuid, date, text, uuid, text)'::regprocedure;
  if v_src like '%assignment_basis%' or v_src not like '%leadership_assignment_history%' or v_src not like '%private.section_kind(v_node.id) = ''couples''%' then
    raise exception 'Guard failed: appoint_area_coordinator_core not restored';
  end if;
  select prosrc into v_src from pg_proc where oid = 'private.section_coordinator_eligibility(uuid, uuid, uuid)'::regprocedure;
  if v_src not like '%sex_null%' or v_src not like '%case private.section_kind(v_section_node.id)%' then
    raise exception 'Guard failed: section_coordinator_eligibility not restored';
  end if;
  select prosrc into v_src from pg_proc where oid = 'public.change_members_section_bulk(uuid, uuid[], text, date, text)'::regprocedure;
  if v_src not like '%correlation_id%' or v_src not like '%exception when others%' or v_src not like '%private.section_kind(v_target_node.id) is not null%' then
    raise exception 'Guard failed: change_members_section_bulk not restored';
  end if;
end $$;

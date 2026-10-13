-- Pass 4.9: allow primary placement at the Area level (area_state), in addition to chapter and unit. Ministry decision: some members belong to the Area only.

CREATE OR REPLACE FUNCTION public.change_member_governance_assignment(p_organization_id uuid, p_member_id uuid, p_target_governance_node_id uuid DEFAULT NULL::uuid, p_effective_from date DEFAULT CURRENT_DATE, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
    v_actor_profile_id uuid;
    v_cur_assignment public.member_governance_assignments%rowtype;
    v_target_node_code text;
    v_new_assignment_id uuid := null;
begin
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    if not private.has_permission('members.placements.manage', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.placements.manage.';
    end if;

    if not private.can_access_member('members.placements.manage', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: member is outside caller governance scope.';
    end if;

    -- Validate target node if provided
    if p_target_governance_node_id is not null then
        select nt.code into v_target_node_code
        from public.governance_nodes n
        join public.governance_node_types nt on nt.id = n.governance_node_type_id
        where n.id = p_target_governance_node_id
          and n.organization_id = p_organization_id
          and n.lifecycle_status = 'active';

        if not found then
            raise exception using errcode = 'P0002', message = 'Target governance node not found or not active.';
        end if;

        if v_target_node_code not in ('area_state', 'chapter', 'unit') then
            raise exception using errcode = '22023', message = 'Validation error: governance placement must target the area, a chapter or a unit.';
        end if;

        if not private.profile_has_governance_scope(auth.uid(), p_organization_id, p_target_governance_node_id, now()) then
            raise exception using errcode = '42501', message = 'Access denied: target governance node is outside caller scope.';
        end if;
    end if;

    -- Find current active primary assignment
    select * into v_cur_assignment
    from public.member_governance_assignments
    where organization_id = p_organization_id
      and member_id = p_member_id
      and is_primary = true
      and assignment_status = 'active'
      and effective_to is null;

    if found then
        -- Validate date ordering
        if p_effective_from < v_cur_assignment.effective_from then
            raise exception using errcode = '22023',
                message = format('Effective date (%s) cannot precede current placement start date (%s).', p_effective_from, v_cur_assignment.effective_from);
        end if;

        -- Close current assignment
        update public.member_governance_assignments
        set assignment_status = 'ended',
            effective_to = case when p_effective_from = v_cur_assignment.effective_from then p_effective_from else p_effective_from - 1 end,
            ending_reason = coalesce(p_reason, 'Transferred or removed by administration'),
            updated_at = now(),
            updated_by_profile_id = v_actor_profile_id
        where id = v_cur_assignment.id;
    end if;

    -- If target node is supplied, insert new active assignment
    if p_target_governance_node_id is not null then
        v_new_assignment_id := gen_random_uuid();
        insert into public.member_governance_assignments (
            id, organization_id, member_id, governance_node_id,
            assignment_type, assignment_status, effective_from,
            is_primary, assignment_basis, created_by_profile_id, updated_by_profile_id
        ) values (
            v_new_assignment_id, p_organization_id, p_member_id, p_target_governance_node_id,
            'primary', 'active', p_effective_from,
            true, 'administrative', v_actor_profile_id, v_actor_profile_id
        );
        -- The table trigger trg_member_governance_assignments__sync_cache sets members.primary_governance_node_id!
    end if;

    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.placement.changed',
        p_event_category   => 'governance',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => p_member_id,
        p_action           => 'transfer',
        p_outcome          => 'success',
        p_metadata         => jsonb_build_object(
            'previous_assignment_id', v_cur_assignment.id,
            'previous_governance_node_id', v_cur_assignment.governance_node_id,
            'target_governance_node_id', p_target_governance_node_id,
            'effective_from', p_effective_from,
            'reason', nullif(trim(p_reason), '')
        )
    );

    return jsonb_build_object(
        'status', 'success',
        'member_id', p_member_id,
        'previous_node_id', v_cur_assignment.governance_node_id,
        'new_node_id', p_target_governance_node_id,
        'assignment_id', v_new_assignment_id
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.place_members_bulk(p_organization_id uuid, p_member_ids uuid[], p_target_governance_node_id uuid, p_effective_from date, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_actor_profile_id   uuid;
  v_target_node_code   text;
  v_deduped_member_ids uuid[];
  v_requested_count    integer;
  v_member_id          uuid;
  v_member             public.members%rowtype;
  v_correlation_id     uuid;
  v_res                jsonb;
  v_placed             jsonb := '[]'::jsonb;
  v_skipped            jsonb := '[]'::jsonb;
  v_placed_ids         uuid[] := array[]::uuid[];
begin
  -- 1. Authentication
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  -- 2. Permission check
  if not private.has_permission('members.placements.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission members.placements.manage.';
  end if;

  -- 3. Reason validation
  if p_reason is null or length(btrim(p_reason)) < 5 then
    raise exception using errcode = '22023', message = 'A reason of at least 5 characters is required.';
  end if;

  -- 4. Effective date validation
  if p_effective_from is null or p_effective_from > current_date then
    raise exception using errcode = '22023', message = 'Effective date cannot be in the future.';
  end if;

  -- 5. Target validation
  if p_target_governance_node_id is null then
    raise exception using errcode = '22023', message = 'Choose the area, a chapter or a unit.';
  end if;

  select nt.code into v_target_node_code
  from public.governance_nodes n
  join public.governance_node_types nt on nt.id = n.governance_node_type_id
  where n.id = p_target_governance_node_id
    and n.organization_id = p_organization_id
    and n.lifecycle_status = 'active';

  if not found then
    raise exception using errcode = 'P0002', message = 'Target governance node not found or not active.';
  end if;

  if v_target_node_code not in ('area_state', 'chapter', 'unit') then
    raise exception using errcode = '22023', message = 'Validation error: governance placement must target the area, a chapter or a unit.';
  end if;

  if not private.profile_has_governance_scope(auth.uid(), p_organization_id, p_target_governance_node_id, now()) then
    raise exception using errcode = '42501', message = 'Access denied: target governance node is outside caller scope.';
  end if;

  -- 6. Member IDs deduplication & bounds check
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
    raise exception using errcode = '22023', message = 'You can place at most 100 members at a time.';
  end if;

  v_correlation_id := gen_random_uuid();

  -- 7. Process each member
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
    elsif v_member.primary_governance_node_id = p_target_governance_node_id then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'member_id', v_member_id,
        'reason', 'already_in_target'
      ));
    else
      begin
        v_res := public.change_member_governance_assignment(
          p_organization_id           => p_organization_id,
          p_member_id                 => v_member_id,
          p_target_governance_node_id => p_target_governance_node_id,
          p_effective_from            => p_effective_from,
          p_reason                    => btrim(p_reason)
        );

        v_placed := v_placed || jsonb_build_array(jsonb_build_object(
          'member_id', v_member_id,
          'previous_node_id', (v_res->>'previous_node_id')::uuid
        ));
        v_placed_ids := array_append(v_placed_ids, v_member_id);
      exception when others then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
          'member_id', v_member_id,
          'reason', 'error',
          'message', sqlerrm
        ));
      end;
    end if;
  end loop;

  -- 8. Write summary audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.placement.bulk_changed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'governance_node',
    p_entity_id        => p_target_governance_node_id,
    p_action           => 'bulk_transfer',
    p_outcome          => 'success',
    p_correlation_id   => v_correlation_id,
    p_metadata         => jsonb_build_object(
      'requested_count',   v_requested_count,
      'placed_count',      jsonb_array_length(v_placed),
      'skipped_count',     jsonb_array_length(v_skipped),
      'effective_from',    p_effective_from,
      'reason',            btrim(p_reason),
      'placed_member_ids', to_jsonb(v_placed_ids)
    )
  );

  -- 9. Return response
  return jsonb_build_object(
    'status',                    'success',
    'target_governance_node_id', p_target_governance_node_id,
    'effective_from',            p_effective_from,
    'placed_count',              jsonb_array_length(v_placed),
    'skipped_count',             jsonb_array_length(v_skipped),
    'placed',                    v_placed,
    'skipped',                   v_skipped,
    'correlation_id',            v_correlation_id
  );
end;
$function$;

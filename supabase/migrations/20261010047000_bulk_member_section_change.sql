-- Pass 4.9S: bulk section change. Wraps public.change_member_section per member; does not reimplement its rules.

create or replace function public.change_members_section_bulk(
  p_organization_id uuid,
  p_member_ids uuid[],
  p_section_code text,
  p_effective_from date,
  p_reason text
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

  if not found or not (v_target_node.code ilike 'sec_%') then
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

revoke all on function public.change_members_section_bulk(uuid, uuid[], text, date, text) from public, anon;
grant execute on function public.change_members_section_bulk(uuid, uuid[], text, date, text) to authenticated;

-- Migration 113: bulk_member_placement
-- Public functions for bulk member placement worklist and execution.

begin;

-- =============================================================================
-- 1. get_placement_worklist
-- =============================================================================
create or replace function public.get_placement_worklist(
  p_organization_id   uuid,
  p_view              text default 'unplaced',
  p_section_node_id   uuid default null,
  p_search            text default null,
  p_page              integer default 1,
  p_page_size         integer default 100
) returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor_profile_id  uuid;
  v_effective_page    integer;
  v_effective_size    integer;
  v_offset            integer;
  v_search_term       text;
  v_unplaced_count    bigint;
  v_placed_count      bigint;
  v_total_count       bigint;
  v_members           jsonb;
begin
  -- 1. Authentication check
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('members.placements.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission members.placements.manage.';
  end if;

  -- 4. View validation
  if p_view not in ('unplaced', 'placed', 'all') then
    raise exception using errcode = '22023', message = 'Invalid view: must be unplaced, placed, or all.';
  end if;

  -- 5. Search length validation
  if length(coalesce(p_search, '')) > 200 then
    raise exception using errcode = '22023', message = 'Search term must not exceed 200 characters.';
  end if;

  -- 6. Page and page size normalization
  v_effective_page := greatest(coalesce(p_page, 1), 1);
  v_effective_size := least(greatest(coalesce(p_page_size, 100), 1), 100);
  v_offset         := (v_effective_page - 1) * v_effective_size;
  v_search_term    := nullif(btrim(coalesce(p_search, '')), '');

  -- 7. Query worklist & summary
  with active_scoped_members as (
    select
      m.id,
      m.display_name,
      m.preferred_name,
      m.sort_name,
      m.member_number,
      m.membership_status_id,
      m.primary_section_node_id,
      (mga.id is not null) as is_placed,
      mga.effective_from as placement_effective_from,
      gn.id as placement_node_id,
      gn.code as placement_node_code,
      gn.name as placement_node_name,
      gnt.code as placement_node_type_code,
      p_gn.name as placement_parent_name
    from public.members m
    left join public.member_governance_assignments mga
      on mga.organization_id = m.organization_id
     and mga.member_id = m.id
     and mga.is_primary = true
     and mga.assignment_status = 'active'
     and mga.effective_to is null
    left join public.governance_nodes gn
      on gn.id = mga.governance_node_id
     and gn.organization_id = mga.organization_id
    left join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id
    left join public.governance_node_relationships p_rel
      on p_rel.organization_id = gn.organization_id
     and p_rel.child_node_id = gn.id
     and p_rel.is_primary = true
     and p_rel.relationship_status = 'active'
     and p_rel.effective_to is null
    left join public.governance_nodes p_gn
      on p_gn.id = p_rel.parent_node_id
     and p_gn.organization_id = p_rel.organization_id
    where m.organization_id = p_organization_id
      and m.record_status = 'active'
      and not coalesce(m.is_deceased, false)
      and private.can_access_member('members.placements.manage', p_organization_id, m.id)
  ),
  summary_counts as (
    select
      count(*) filter (where not is_placed) as unplaced_count,
      count(*) filter (where is_placed) as placed_count
    from active_scoped_members
  ),
  filtered_candidates as (
    select *
    from active_scoped_members asm
    where (
      p_view = 'all'
      or (p_view = 'unplaced' and not asm.is_placed)
      or (p_view = 'placed' and asm.is_placed)
    )
    and (
      p_section_node_id is null
      or asm.primary_section_node_id = p_section_node_id
    )
    and (
      v_search_term is null
      or asm.sort_name ilike '%' || v_search_term || '%'
      or asm.preferred_name ilike '%' || v_search_term || '%'
      or asm.display_name ilike '%' || v_search_term || '%'
    )
  ),
  paged_rows as (
    select *
    from filtered_candidates
    order by sort_name asc, id asc
    limit v_effective_size
    offset v_offset
  )
  select
    sc.unplaced_count,
    sc.placed_count,
    (select count(*) from filtered_candidates),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', pr.id,
            'display_name', pr.display_name,
            'preferred_name', pr.preferred_name,
            'member_number', case
              when private.can_access_member('members.identifiers.view', p_organization_id, pr.id) then pr.member_number
              else null
            end,
            'membership_status', (
              select jsonb_build_object('code', ms.code, 'name', ms.name)
              from public.member_statuses ms
              where ms.id = pr.membership_status_id and ms.organization_id = p_organization_id
            ),
            'section', case
              when sec.id is not null then jsonb_build_object(
                'node_id', sec.id,
                'code', sec.code,
                'name', sec.name
              )
              else null
            end,
            'placement', case
              when pr.is_placed then jsonb_build_object(
                'node_id', pr.placement_node_id,
                'code', pr.placement_node_code,
                'name', pr.placement_node_name,
                'node_type_code', pr.placement_node_type_code,
                'parent_name', pr.placement_parent_name,
                'effective_from', pr.placement_effective_from
              )
              else null
            end
          )
          order by pr.sort_name asc, pr.id asc
        )
        from paged_rows pr
        left join public.governance_nodes sec
          on sec.id = pr.primary_section_node_id
         and sec.organization_id = p_organization_id
      ),
      '[]'::jsonb
    )
  into v_unplaced_count, v_placed_count, v_total_count, v_members
  from summary_counts sc;

  return jsonb_build_object(
    'total_count', v_total_count,
    'page',        v_effective_page,
    'page_size',   v_effective_size,
    'summary', jsonb_build_object(
      'unplaced_count', v_unplaced_count,
      'placed_count',   v_placed_count
    ),
    'members', v_members
  );
end;
$$;

-- =============================================================================
-- 2. place_members_bulk
-- =============================================================================
create or replace function public.place_members_bulk(
  p_organization_id            uuid,
  p_member_ids                 uuid[],
  p_target_governance_node_id  uuid,
  p_effective_from             date,
  p_reason                     text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
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
    raise exception using errcode = '22023', message = 'Choose a chapter or unit.';
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

  if v_target_node_code not in ('chapter', 'unit') then
    raise exception using errcode = '22023', message = 'Validation error: governance placement must target a chapter or unit.';
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
$$;

-- =============================================================================
-- 3. Grants & Revokes
-- =============================================================================
revoke all on function public.get_placement_worklist(uuid, text, uuid, text, integer, integer) from public, anon;
grant execute on function public.get_placement_worklist(uuid, text, uuid, text, integer, integer) to authenticated;

revoke all on function public.place_members_bulk(uuid, uuid[], uuid, date, text) from public, anon;
grant execute on function public.place_members_bulk(uuid, uuid[], uuid, date, text) to authenticated;

commit;

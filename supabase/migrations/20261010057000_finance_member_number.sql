-- Pass 6.4: member numbers are Finance Group envelope numbers (Ron, 2026-10-13).
-- MissionOS records them; it never invents them. Adds one RPC to set or correct a member's Finance number.
-- create_member is NOT changed: the app will call it with p_allocate_member_number = false and then call
-- set_member_number when a Finance number was entered.

create or replace function public.set_member_number(
  p_organization_id uuid,
  p_member_id uuid,
  p_member_number text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor_profile_id uuid;
  v_member public.members%rowtype;
  v_number text;
  v_current public.member_identifiers%rowtype;
  v_used_by uuid;
  v_new_id uuid;
begin
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;

  if not private.has_permission('members.identifiers.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission members.identifiers.manage.';
  end if;

  if not private.can_access_member('members.identifiers.manage', p_organization_id, p_member_id) then
    raise exception using errcode = '42501', message = 'Access denied: member is outside caller governance scope.';
  end if;

  v_number := upper(regexp_replace(coalesce(p_member_number, ''), '\s', '', 'g'));
  if v_number !~ '^NY[0-9]{5}$' then
    raise exception using errcode = '22023', message = 'Enter the Finance member number in the form NY followed by 5 digits (for example NY10560).';
  end if;

  select * into v_member
  from public.members
  where id = p_member_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
  end if;

  -- The number must not belong (now or in the past) to any other member
  select mi.member_id into v_used_by
  from public.member_identifiers mi
  where mi.organization_id = p_organization_id
    and mi.identifier_type = 'member_number'
    and mi.normalized_value = v_number
    and mi.member_id <> p_member_id
  limit 1;
  if v_used_by is not null then
    raise exception using errcode = '23505', message = 'Member number ' || v_number || ' is already used by another member.';
  end if;

  select * into v_current
  from public.member_identifiers mi
  where mi.organization_id = p_organization_id
    and mi.member_id = p_member_id
    and mi.identifier_type = 'member_number'
    and mi.is_primary = true
    and mi.effective_to is null
  limit 1
  for update;

  if found and v_current.normalized_value = v_number then
    raise exception using errcode = '22023', message = 'This member already has member number ' || v_number || '.';
  end if;

  -- A change of an existing number needs a reason
  if found and (p_reason is null or length(btrim(p_reason)) < 5) then
    raise exception using errcode = '22023', message = 'A reason of at least 5 characters is required to change a member number.';
  end if;

  if found then
    update public.member_identifiers
    set is_primary = false,
        effective_to = greatest(coalesce(effective_from, current_date), current_date)
    where id = v_current.id;
  end if;

  v_new_id := gen_random_uuid();
  insert into public.member_identifiers (
    id, organization_id, member_id, identifier_type, source_system,
    identifier_value, normalized_value, is_primary, verification_status,
    effective_from, created_by_profile_id
  ) values (
    v_new_id, p_organization_id, p_member_id, 'member_number', 'missionos',
    v_number, v_number, true, 'unverified',
    current_date, v_actor_profile_id
  );

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'member.identifier.updated',
    p_event_category   => 'member',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'member',
    p_entity_id        => p_member_id,
    p_action           => case when v_current.id is null then 'create' else 'update' end,
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'identifier_type', 'member_number',
      'source', 'finance_envelope_number',
      'previous_member_number', v_current.normalized_value,
      'member_number', v_number,
      'reason', nullif(btrim(coalesce(p_reason, '')), '')
    )
  );

  return jsonb_build_object(
    'status', 'success',
    'member_id', p_member_id,
    'member_number', v_number,
    'previous_member_number', v_current.normalized_value
  );
end;
$$;

revoke all on function public.set_member_number(uuid, uuid, text, text) from public, anon;
grant execute on function public.set_member_number(uuid, uuid, text, text) to authenticated;

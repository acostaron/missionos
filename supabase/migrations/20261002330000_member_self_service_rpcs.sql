-- =============================================================================
-- Migration: 20261002330000_member_self_service_rpcs.sql
-- Description: Member self-service foundation, part 2 of 2.
--              RPCs: get_my_member_context(org), get_my_member_profile(org).
--              No member_id input exists: the caller's member is resolved
--              internally from the verified self profile-member link.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Private: authorize caller and resolve own member id
-- -----------------------------------------------------------------------------
create or replace function private.assert_member_self_service(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_member_id  uuid;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if p_organization_id is null
     or not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('members.self_service.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view your own member information.';
  end if;

  v_member_id := private.current_member_id(p_organization_id);
  if v_member_id is null then
    raise exception using errcode = 'P0002', message = 'Your account is not linked to a member record.';
  end if;

  v_member_id := coalesce(private.resolve_canonical_member_id(p_organization_id, v_member_id), v_member_id);

  if not exists (
    select 1 from public.members m
    where m.id = v_member_id
      and m.organization_id = p_organization_id
      and m.archived_at is null
  ) then
    raise exception using errcode = 'P0002', message = 'Your account is not linked to a member record.';
  end if;

  return v_member_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. Private: build the safe self context payload for an already-authorized member
-- -----------------------------------------------------------------------------
create or replace function private.build_member_self_context(p_organization_id uuid, p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member     record;
  v_household  jsonb := null;
  v_hh_node_id uuid;
  v_org_ctx    jsonb;
  v_status     text;
begin
  select m.id, m.member_number, m.display_name, m.primary_section_node_id, m.membership_status_id
  into v_member
  from public.members m
  where m.id = p_member_id and m.organization_id = p_organization_id;

  select ms.name into v_status
  from public.member_statuses ms
  where ms.id = v_member.membership_status_id;

  -- Current household (primary first, most recent first)
  select jsonb_build_object(
           'household_id',          gn.id,
           'household_name',        gn.name,
           'pastoral_level',        h.pastoral_level,
           'leader_display_name',   servant.display_name,
           'parent_node_name',      parent.name,
           'meeting_frequency',     h.meeting_frequency,
           'meeting_day_of_week',   h.meeting_day_of_week,
           'meeting_start_time',    h.meeting_start_time,
           'meeting_timezone_name', h.meeting_timezone_name
         ),
         gn.id
  into v_household, v_hh_node_id
  from public.household_memberships hm
  join public.governance_nodes gn
    on gn.id = hm.household_node_id and gn.organization_id = hm.organization_id
  join public.households h
    on h.id = gn.id and h.organization_id = gn.organization_id
  left join lateral (
    select pgn.name
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id and pgn.organization_id = gnr.organization_id
    where gnr.child_node_id = gn.id
      and gnr.organization_id = gn.organization_id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.effective_from desc
    limit 1
  ) parent on true
  left join lateral (
    select m_lead.display_name
    from public.leadership_assignments la
    join public.members m_lead
      on m_lead.id = la.member_id and m_lead.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id and lrd.organization_id = la.organization_id
    where la.governance_node_id = gn.id
      and la.organization_id = gn.organization_id
      and la.assignment_status = 'active'
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'household_servant_leader'
    order by la.effective_from desc
    limit 1
  ) servant on true
  where hm.organization_id = p_organization_id
    and hm.member_id = p_member_id
    and hm.membership_status = 'active'
    and (hm.effective_to is null or hm.effective_to >= current_date)
  order by hm.is_primary desc, hm.effective_from desc
  limit 1;

  -- Organizational ancestry: walk primary parents up from the household
  -- (or from the member's primary section node for the section level).
  with recursive up as (
    select gn.id, gn.name, gn.governance_node_type_id, 0 as depth
    from public.governance_nodes gn
    where gn.id = v_hh_node_id and gn.organization_id = p_organization_id
    union all
    select pgn.id, pgn.name, pgn.governance_node_type_id, up.depth + 1
    from up
    join public.governance_node_relationships gnr
      on gnr.child_node_id = up.id
     and gnr.organization_id = p_organization_id
     and gnr.relationship_type = 'primary_parent'
     and gnr.relationship_status = 'active'
     and (gnr.effective_to is null or gnr.effective_to >= current_date)
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id and pgn.organization_id = p_organization_id
    where up.depth < 10
  ),
  typed as (
    select u.name, t.code, u.depth
    from up u
    join public.governance_node_types t on t.id = u.governance_node_type_id
  )
  select jsonb_build_object(
    'area',    (select name from typed where code = 'area_state' order by depth limit 1),
    'section', coalesce(
                 (select name from typed where code = 'section' order by depth limit 1),
                 (select gn.name from public.governance_nodes gn
                  where gn.id = v_member.primary_section_node_id
                    and gn.organization_id = p_organization_id)
               ),
    'chapter', (select name from typed where code = 'chapter' order by depth limit 1),
    'unit',    (select name from typed where code = 'unit' order by depth limit 1)
  )
  into v_org_ctx;

  return jsonb_build_object(
    'organization_id', p_organization_id,
    'profile', jsonb_build_object(
      'display_name', (select p.display_name from public.profiles p where p.id = private.current_profile_id())
    ),
    'member', jsonb_build_object(
      'member_id',         v_member.id,
      'member_number',     v_member.member_number,
      'display_name',      v_member.display_name,
      'membership_status', v_status
    ),
    'household', v_household,
    'organizational_context', coalesce(v_org_ctx, jsonb_build_object(
      'area', null, 'section', null, 'chapter', null, 'unit', null))
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Public RPC: get_my_member_context(p_organization_id)
-- -----------------------------------------------------------------------------
create or replace function public.get_my_member_context(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member_id uuid;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  return private.build_member_self_context(p_organization_id, v_member_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Public RPC: get_my_member_profile(p_organization_id)
--    Context plus the member's own basic contact data. No history, audit,
--    roles, permissions, scopes or access grants.
-- -----------------------------------------------------------------------------
create or replace function public.get_my_member_profile(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member_id uuid;
  v_ctx       jsonb;
  v_email     text;
  v_phone     text;
  v_extra     record;
begin
  v_member_id := private.assert_member_self_service(p_organization_id);
  v_ctx := private.build_member_self_context(p_organization_id, v_member_id);

  select e.email_address into v_email
  from public.member_emails e
  where e.organization_id = p_organization_id
    and e.member_id = v_member_id
    and (e.effective_to_at is null or e.effective_to_at > now())
  order by e.is_primary desc, e.effective_from_at desc
  limit 1;

  select ph.phone_number into v_phone
  from public.member_phones ph
  where ph.organization_id = p_organization_id
    and ph.member_id = v_member_id
    and (ph.effective_to_at is null or ph.effective_to_at > now())
  order by ph.is_primary desc, ph.effective_from_at desc
  limit 1;

  select m.preferred_name, m.joined_on, m.preferred_language_code
  into v_extra
  from public.members m
  where m.id = v_member_id and m.organization_id = p_organization_id;

  return v_ctx || jsonb_build_object(
    'details', jsonb_build_object(
      'preferred_name',          v_extra.preferred_name,
      'joined_on',               v_extra.joined_on,
      'preferred_language_code', v_extra.preferred_language_code
    ),
    'contact', jsonb_build_object(
      'primary_email', v_email,
      'primary_phone', v_phone
    )
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. ACLs: no PUBLIC, no anon. Private helpers are not callable by API roles.
-- -----------------------------------------------------------------------------
revoke all on function private.assert_member_self_service(uuid) from public, anon, authenticated;
revoke all on function private.build_member_self_context(uuid, uuid) from public, anon, authenticated;

revoke all on function public.get_my_member_context(uuid) from public, anon;
revoke all on function public.get_my_member_profile(uuid) from public, anon;
grant execute on function public.get_my_member_context(uuid) to authenticated, service_role;
grant execute on function public.get_my_member_profile(uuid) to authenticated, service_role;

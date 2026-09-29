-- =============================================================================
-- Migration: 20260929000000_phase_6a_family_read_foundation.sql
-- Phase:     Phase 6A-0 -- Family Read Foundation
--
-- Summary:
--   Establishes the secure read contract for family data.
--
--   1. Assign families.records.view and families.relationships.view to
--      organization_administrator (both existed but were unassigned).
--
--   2. Create private.can_access_family(p_permission_code, p_organization_id,
--      p_family_id) -- union-access model: permission + at least one accessible
--      active member in the family, using existing private.can_access_member.
--
--   3. Create public.get_family_profile(p_organization_id, p_family_id)
--      Returns safe family identity: family record, members (identity-only),
--      relationships (as stored -- no fabricated reciprocals).
--
--   4. Create public.get_member_families(p_organization_id, p_member_id)
--      Returns active family memberships for a member.
--      Powers the future member-profile Family card.
--
--   5. Create public.get_family_relationship_types(p_organization_id)
--      Returns browser-safe relationship type catalog.
--
-- Authorization model:
--   Production Acosta family spans nyc + rvc chapters -- scope is org-level.
--   Access requires families.records.view AND at least one accessible active
--   family member via private.can_access_member (union-access).
--
-- Field safety:
--   Members in family profile: identity fields only.
--   No email, phone, address, birth date, or auth data exposed.
--   member_number gated by members.identifiers.view.
--   administrative_notes omitted (not exposed in Phase 6A-0).
--   relationships gated by families.relationships.view.
--
-- Does NOT implement:
--   Family writes, membership writes, relationship writes, directory/search,
--   or frontend UI.
--
-- Error codes:
--   28000  -- unauthenticated / profile not found
--   42501  -- missing permission or org access
--   P0002  -- family or member not found / not accessible (indistinguishable)
-- =============================================================================

-- =============================================================================
-- SECTION 1: Assign family view permissions to organization_administrator
-- Both permissions existed with no role assignments.
-- member_data_steward NOT assigned -- family data is not member data stewardship.
-- =============================================================================

insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  approval_status,
  approved_at,
  approved_by_profile_id,
  created_by_profile_id
)
select
  null,
  ar.id,
  p.id,
  'allow',
  'approved',
  now(),
  null,
  null
from public.app_roles ar
cross join public.permissions p
where ar.code = 'organization_administrator'
  and p.code  = 'families.records.view'
on conflict do nothing;

insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  approval_status,
  approved_at,
  approved_by_profile_id,
  created_by_profile_id
)
select
  null,
  ar.id,
  p.id,
  'allow',
  'approved',
  now(),
  null,
  null
from public.app_roles ar
cross join public.permissions p
where ar.code = 'organization_administrator'
  and p.code  = 'families.relationships.view'
on conflict do nothing;

-- =============================================================================
-- SECTION 2: private.can_access_family(p_permission_code, p_organization_id,
--             p_family_id)
--
-- Union-access model:
--   Returns true when caller:
--     (a) has org access, AND
--     (b) has the required permission, AND
--     (c) can access at least ONE active family member via can_access_member
--
-- This avoids the cross-governance-node problem: families are not scoped to a
-- single chapter. We require access to at least one member, not all of them.
--
-- Returns false (no exception) for non-existent families -- callers use this
-- as a predicate; the calling RPC raises the appropriate P0002.
-- =============================================================================

create or replace function private.can_access_family(
  p_permission_code text,
  p_organization_id uuid,
  p_family_id       uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
begin
  -- Guard: organization access
  if not private.has_organization_access(p_organization_id) then
    return false;
  end if;

  -- Guard: required permission
  if not private.has_permission(p_permission_code, p_organization_id) then
    return false;
  end if;

  -- Guard: family exists in this org (no information leak -- returns false)
  if not exists (
    select 1
    from public.families f
    where f.id              = p_family_id
      and f.organization_id = p_organization_id
  ) then
    return false;
  end if;

  -- Union-access: at least one active family member is accessible to caller
  -- Uses existing private.can_access_member which handles all governance
  -- branches (household, section, governance, direct, org-wide scope).
  return exists (
    select 1
    from public.family_members fm
    where fm.organization_id   = p_organization_id
      and fm.family_id         = p_family_id
      and fm.membership_status = 'active'
      and (
        fm.effective_to is null
        or fm.effective_to > current_date
      )
      and private.can_access_member(
            p_permission_code,
            p_organization_id,
            fm.member_id
          )
  );
end;
$$;

-- =============================================================================
-- SECTION 3: public.get_family_profile(p_organization_id, p_family_id)
--
-- Returns jsonb with shape:
--   {
--     "family": { id, family_name, display_name, family_type, family_status,
--                 formed_on, ended_on, directory_visibility, created_at, updated_at },
--     "members": [ { family_member_id, member_id, member_number|null,
--                    display_name, preferred_name, family_role,
--                    is_primary_contact, is_dependent,
--                    membership_status: { code, name, status_category, is_active_membership },
--                    record_status, is_deceased, effective_from, effective_to } ],
--     "relationships": [ { relationship_id, from_member_id, to_member_id,
--                          relationship_type: { code, name, inverse_code,
--                            is_symmetric, category },
--                          effective_from, effective_to, relationship_status,
--                          verification_status, source } ]
--                    -- null when caller lacks families.relationships.view
--   }
--
-- Member ordering: is_primary_contact DESC, family_role ASC NULLS LAST, display_name ASC
-- Relationship rows returned exactly as stored -- no fabricated reciprocals.
-- All active family memberships included; historical/ended excluded.
-- =============================================================================

create or replace function public.get_family_profile(
  p_organization_id uuid,
  p_family_id       uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id            uuid;
  v_family                public.families%rowtype;
  v_can_see_identifiers   boolean;
  v_can_see_relationships boolean;
  v_members_arr           jsonb;
  v_relationships_arr     jsonb;
begin
  -- Step 1: Resolve authenticated caller
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: families.records.view permission required
  if not private.has_permission('families.records.view', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to view family records.';
  end if;

  -- Step 4: Family scope check -- indistinguishable P0002
  if not private.can_access_family(
    'families.records.view', p_organization_id, p_family_id
  ) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 5: Load family row (secondary org boundary guard)
  select * into v_family
  from public.families f
  where f.id              = p_family_id
    and f.organization_id = p_organization_id;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 6: Field-level permission flags (org-level, not per-member)
  -- member_number: gated by members.identifiers.view
  -- relationships: gated by families.relationships.view
  v_can_see_identifiers   := private.has_permission(
    'members.identifiers.view', p_organization_id);
  v_can_see_relationships := private.has_permission(
    'families.relationships.view', p_organization_id);

  -- Step 7: Assemble members array
  -- Includes all active family memberships (effective_to null or future).
  -- Per-member scope NOT re-applied -- family was already scope-gated.
  -- Out-of-scope members visible at identity level only (no PII fields).
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'family_member_id',   fm.id,
        'member_id',          m.id,
        'member_number',      case
                                when v_can_see_identifiers
                                  then m.member_number
                                else null
                              end,
        'display_name',       m.display_name,
        'preferred_name',     m.preferred_name,
        'family_role',        fm.family_role,
        'is_primary_contact', fm.is_primary_contact,
        'is_dependent',       fm.is_dependent,
        'membership_status',  jsonb_build_object(
                                'code',                 ms.code,
                                'name',                 ms.name,
                                'status_category',      ms.status_category,
                                'is_active_membership', ms.is_active_membership
                              ),
        'record_status',      m.record_status,
        'is_deceased',        m.is_deceased,
        'effective_from',     fm.effective_from,
        'effective_to',       fm.effective_to
      )
      order by
        fm.is_primary_contact desc,
        fm.family_role        asc  nulls last,
        m.display_name        asc
    ),
    '[]'::jsonb
  )
  into v_members_arr
  from public.family_members fm
  join public.members m
    on  m.id              = fm.member_id
    and m.organization_id = fm.organization_id
  join public.member_statuses ms
    on  ms.id              = m.membership_status_id
    and ms.organization_id = m.organization_id
  where fm.organization_id   = p_organization_id
    and fm.family_id         = p_family_id
    and fm.membership_status = 'active'
    and (
      fm.effective_to is null
      or fm.effective_to > current_date
    );

  -- Step 8: Assemble relationships array (as stored -- no fabricated rows)
  -- Null when caller lacks families.relationships.view.
  if v_can_see_relationships then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'relationship_id',     fr.id,
          'from_member_id',      fr.from_member_id,
          'to_member_id',        fr.to_member_id,
          'relationship_type',   jsonb_build_object(
                                   'code',         frt.code,
                                   'name',         frt.name,
                                   'inverse_code', frt.inverse_code,
                                   'is_symmetric', frt.is_symmetric,
                                   'category',     frt.relationship_category
                                 ),
          'effective_from',      fr.effective_from,
          'effective_to',        fr.effective_to,
          'relationship_status', fr.relationship_status,
          'verification_status', fr.verification_status,
          'source',              fr.source
        )
        order by frt.display_order asc, fr.created_at asc
      ),
      '[]'::jsonb
    )
    into v_relationships_arr
    from public.family_relationships fr
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
    where fr.organization_id     = p_organization_id
      and fr.family_id           = p_family_id
      and fr.relationship_status = 'active';
  else
    v_relationships_arr := null;
  end if;

  -- Step 9: Return assembled profile
  return jsonb_build_object(
    'family', jsonb_build_object(
      'id',                   v_family.id,
      'family_name',          v_family.family_name,
      'display_name',         v_family.display_name,
      'family_type',          v_family.family_type,
      'family_status',        v_family.family_status,
      'formed_on',            v_family.formed_on,
      'ended_on',             v_family.ended_on,
      'directory_visibility', v_family.directory_visibility,
      'created_at',           v_family.created_at,
      'updated_at',           v_family.updated_at
    ),
    'members',       v_members_arr,
    'relationships', v_relationships_arr
  );
end;
$$;

revoke execute on function public.get_family_profile(uuid, uuid) from public;
revoke execute on function public.get_family_profile(uuid, uuid) from anon;
grant  execute on function public.get_family_profile(uuid, uuid) to authenticated;
grant  execute on function public.get_family_profile(uuid, uuid) to service_role;

-- =============================================================================
-- SECTION 4: public.get_member_families(p_organization_id, p_member_id)
--
-- Returns one row per active family membership for the given member.
-- Supports members in more than one active family (no artificial LIMIT 1).
-- Powers the future Family card on MemberProfilePage.
--
-- Authorization:
--   Caller must have org access + families.records.view + can_access_member.
-- =============================================================================

create or replace function public.get_member_families(
  p_organization_id uuid,
  p_member_id       uuid
)
returns table (
  family_id           uuid,
  family_name         text,
  display_name        text,
  family_type         text,
  family_status       text,
  family_member_id    uuid,
  family_role         text,
  is_primary_contact  boolean,
  is_dependent        boolean,
  effective_from      date,
  effective_to        date,
  active_member_count bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
begin
  -- Step 1: Resolve authenticated caller
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Active organization access
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: families.records.view required
  if not private.has_permission('families.records.view', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to view family records.';
  end if;

  -- Step 4: Target member scope check (indistinguishable P0002)
  if not private.can_access_member(
    'members.records.view', p_organization_id, p_member_id
  ) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- Step 5: Return active family memberships for this member
  return query
  select
    f.id                                              as family_id,
    f.family_name,
    f.display_name,
    f.family_type,
    f.family_status,
    fm.id                                             as family_member_id,
    fm.family_role,
    fm.is_primary_contact,
    fm.is_dependent,
    fm.effective_from,
    fm.effective_to,
    (
      select count(*)
      from public.family_members fm2
      where fm2.organization_id   = p_organization_id
        and fm2.family_id         = f.id
        and fm2.membership_status = 'active'
        and (
          fm2.effective_to is null
          or fm2.effective_to > current_date
        )
    )                                                 as active_member_count
  from public.family_members fm
  join public.families f
    on  f.id              = fm.family_id
    and f.organization_id = fm.organization_id
  where fm.organization_id   = p_organization_id
    and fm.member_id         = p_member_id
    and fm.membership_status = 'active'
    and (
      fm.effective_to is null
      or fm.effective_to > current_date
    )
  order by f.family_name asc, fm.effective_from asc nulls last;
end;
$$;

revoke execute on function public.get_member_families(uuid, uuid) from public;
revoke execute on function public.get_member_families(uuid, uuid) from anon;
grant  execute on function public.get_member_families(uuid, uuid) to authenticated;
grant  execute on function public.get_member_families(uuid, uuid) to service_role;

-- =============================================================================
-- SECTION 5: public.get_family_relationship_types(p_organization_id)
--
-- Returns active relationship type catalog (global + org-specific types).
-- No permission beyond org access required (reference data).
-- Supports future org-specific relationship types (schema already has
-- organization_id on family_relationship_types).
-- =============================================================================

create or replace function public.get_family_relationship_types(
  p_organization_id uuid
)
returns table (
  type_id                 uuid,
  code                    text,
  name                    text,
  inverse_code            text,
  relationship_category   text,
  is_symmetric            boolean,
  requires_same_family    boolean,
  allows_multiple_current boolean,
  display_order           integer,
  is_active               boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
begin
  -- Step 1: Resolve authenticated caller
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- Step 2: Active organization access (minimum bar for reference data)
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- Step 3: Return global and org-specific active types
  return query
  select
    frt.id                      as type_id,
    frt.code,
    frt.name,
    frt.inverse_code,
    frt.relationship_category,
    frt.is_symmetric,
    frt.requires_same_family,
    frt.allows_multiple_current,
    frt.display_order,
    frt.is_active
  from public.family_relationship_types frt
  where frt.is_active = true
    and (
      frt.organization_id is null
      or frt.organization_id = p_organization_id
    )
  order by frt.display_order asc, frt.name asc;
end;
$$;

revoke execute on function public.get_family_relationship_types(uuid) from public;
revoke execute on function public.get_family_relationship_types(uuid) from anon;
grant  execute on function public.get_family_relationship_types(uuid) to authenticated;
grant  execute on function public.get_family_relationship_types(uuid) to service_role;

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================

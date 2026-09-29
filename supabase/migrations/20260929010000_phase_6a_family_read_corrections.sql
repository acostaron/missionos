-- =============================================================================
-- Migration: 20260929010000_phase_6a_family_read_corrections.sql
-- Phase:     Phase 6A-0 — Family Read Corrections
--
-- Summary:
--   1. Update private.can_access_family to canonically resolve caller identity
--      via private.current_profile_id().
--   2. Reaffirm public.get_family_profile contract:
--      - primary_parish_id is explicitly OUT OF SCOPE and NOT exposed in the JSON.
--      - primary_address_id is deferred and NOT exposed in the JSON.
--      - administrative_notes is NOT exposed in the JSON.
--   3. Apply neutral terminology: "relational family unit" across all function
--      specifications and comments (family and pastoral household remain separate).
-- =============================================================================

-- =============================================================================
-- SECTION 1: private.can_access_family with canonical caller resolution
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
declare
  v_profile_id uuid;
begin
  -- Step 1: Canonical caller identity resolution
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    return false;
  end if;

  -- Step 2: Guard: active organization access
  if not private.has_organization_access(p_organization_id) then
    return false;
  end if;

  -- Step 3: Guard: required permission
  if not private.has_permission(p_permission_code, p_organization_id) then
    return false;
  end if;

  -- Step 4: Guard: family exists in this organization (no leak -- returns false)
  if not exists (
    select 1
    from public.families f
    where f.id              = p_family_id
      and f.organization_id = p_organization_id
  ) then
    return false;
  end if;

  -- Step 5: Union-access: at least one active member in the relational family
  -- unit is accessible to caller via private.can_access_member.
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
-- SECTION 2: public.get_family_profile reaffirmed
--
-- Contract guarantees:
--   - primary_parish_id is NOT in the returned family object (out of scope).
--   - primary_address_id is NOT in the returned family object (deferred).
--   - administrative_notes is NOT in the returned family object.
--   - Only safe identity fields for the relational family unit are returned.
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
  -- Step 1: Canonical caller identity resolution
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

  -- Step 4: Relational family unit scope check via union-access rule
  if not private.can_access_family(
    'families.records.view', p_organization_id, p_family_id
  ) then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 5: Load family row (secondary organization boundary guard)
  select * into v_family
  from public.families f
  where f.id              = p_family_id
    and f.organization_id = p_organization_id;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Family not found or not accessible.';
  end if;

  -- Step 6: Field-level permission flags (org-level)
  v_can_see_identifiers   := private.has_permission(
    'members.identifiers.view', p_organization_id);
  v_can_see_relationships := private.has_permission(
    'families.relationships.view', p_organization_id);

  -- Step 7: Assemble members array for the relational family unit
  -- Out-of-scope members are visible at identity-only level (no contact/demographic PII).
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

  -- Step 8: Assemble relationships array (as stored)
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
  -- NOTE: primary_parish_id, primary_address_id, and administrative_notes
  -- are intentionally EXCLUDED from this read contract.
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

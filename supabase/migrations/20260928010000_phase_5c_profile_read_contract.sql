-- =============================================================================
-- Migration: 20260928010000_phase_5c_profile_read_contract.sql
-- Phase:     Phase 5C-0 — Expand Member Profile Read Contract
--
-- Summary:
--   Expands public.get_member_profile(...) to return structured identity
--   and demographic fields required for Phase 5C basic member profile editing.
--
-- Added fields:
--   From current primary member_names row (is_primary = true AND effective_to IS NULL):
--     - given_names              (text | null)
--     - middle_names             (text | null)
--     - family_name              (text | null)
--     - preferred_given_name     (text | null)
--     - name_effective_from      (date | null)
--   From members row:
--     - birth_date               (date | null)
--     - sex                      (text | null)
--     - civil_status             (text | null)
--     - home_country_code        (text | null)
--     - preferred_language_code  (text | null)
--
-- Security & Permissions:
--   - SECURITY DEFINER preserved
--   - search_path = pg_catalog, public, private, auth preserved
--   - Authorization via private.current_profile_id(),
--     private.has_organization_access(), private.has_permission('members.records.view'),
--     and private.can_access_member('members.records.view', ...) preserved
--   - Indistinguishable P0002 for nonexistent or out-of-scope members preserved
--   - No direct table SELECT grants on members or member_names
-- =============================================================================

create or replace function public.get_member_profile(
  p_organization_id uuid,
  p_member_id       uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id          uuid;
  v_member              public.members%rowtype;
  v_cur_name            public.member_names%rowtype;

  -- Permission flags — evaluated once
  v_can_see_identifiers boolean;
  v_can_see_contacts    boolean;
  v_can_see_addresses   boolean;
  v_can_see_sections    boolean;
  v_can_see_households  boolean;
  v_can_see_placements  boolean;

  -- Assembled sections
  v_membership_status   jsonb;
  v_identifiers         jsonb;
  v_contacts_emails     jsonb;
  v_contacts_phones     jsonb;
  v_addresses           jsonb;
  v_section_placement   jsonb;
  v_household_placement jsonb;
  v_governance_placement jsonb;
begin
  -- -------------------------------------------------------------------------
  -- Step 1: Resolve authenticated caller
  -- -------------------------------------------------------------------------
  v_profile_id := private.current_profile_id();

  if v_profile_id is null then
    raise exception
      using errcode = '28000',
            message = 'Authentication is required.';
  end if;

  -- -------------------------------------------------------------------------
  -- Step 2: Validate active organization access
  -- -------------------------------------------------------------------------
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have active access to this organization.';
  end if;

  -- -------------------------------------------------------------------------
  -- Step 3: Require members.records.view
  -- -------------------------------------------------------------------------
  if not private.has_permission('members.records.view', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'You do not have permission to view member records.';
  end if;

  -- -------------------------------------------------------------------------
  -- Step 4: Scope check via can_access_member
  --   Deliberately indistinguishable not-found/access-denied response.
  --   Prevents leaking whether the member ID exists in another scope/org.
  -- -------------------------------------------------------------------------
  if not private.can_access_member(
    'members.records.view',
    p_organization_id,
    p_member_id
  ) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- -------------------------------------------------------------------------
  -- Step 5: Load the member row (additional org boundary guard)
  -- -------------------------------------------------------------------------
  select * into v_member
  from public.members
  where id              = p_member_id
    and organization_id = p_organization_id;

  if not found then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- -------------------------------------------------------------------------
  -- Step 5b: Load the current primary name row (canonical structured names)
  -- -------------------------------------------------------------------------
  select * into v_cur_name
  from public.member_names
  where organization_id = p_organization_id
    and member_id       = p_member_id
    and is_primary      = true
    and effective_to is null
  limit 1;

  -- -------------------------------------------------------------------------
  -- Step 6: Evaluate all field-level permission flags via can_access_member
  -- -------------------------------------------------------------------------
  v_can_see_identifiers := private.can_access_member(
    'members.identifiers.view', p_organization_id, p_member_id);
  v_can_see_contacts    := private.can_access_member(
    'members.contacts.view',    p_organization_id, p_member_id);
  v_can_see_addresses   := private.can_access_member(
    'members.addresses.view',   p_organization_id, p_member_id);
  v_can_see_sections    := private.can_access_member(
    'members.sections.view',    p_organization_id, p_member_id);
  v_can_see_households  := private.can_access_member(
    'members.households.view',  p_organization_id, p_member_id);
  v_can_see_placements  := private.can_access_member(
    'members.placements.view',  p_organization_id, p_member_id);

  -- -------------------------------------------------------------------------
  -- Step 7: Resolve membership status
  -- -------------------------------------------------------------------------
  select jsonb_build_object(
    'id',                   ms.id,
    'code',                 ms.code,
    'name',                 ms.name,
    'status_category',      ms.status_category,
    'is_active_membership', ms.is_active_membership
  )
  into v_membership_status
  from public.member_statuses ms
  where ms.organization_id = p_organization_id
    and ms.id              = v_member.membership_status_id;

  -- -------------------------------------------------------------------------
  -- Step 8: identifiers — gated by members.identifiers.view
  -- -------------------------------------------------------------------------
  if v_can_see_identifiers then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',                  mi.id,
          'identifier_type',     mi.identifier_type,
          'identifier_value',    mi.identifier_value,
          'is_primary',          mi.is_primary,
          'verification_status', mi.verification_status
        )
        order by mi.is_primary desc, mi.identifier_type, mi.id
      ),
      '[]'::jsonb
    )
    into v_identifiers
    from public.member_identifiers mi
    where mi.organization_id = p_organization_id
      and mi.member_id       = p_member_id
      and (mi.effective_to is null or mi.effective_to > current_date);
  else
    v_identifiers := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 9: contacts — gated by members.contacts.view
  -- -------------------------------------------------------------------------
  if v_can_see_contacts then
    -- emails
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',                  me.id,
          'email_address',       me.email_address,
          'email_type',          me.email_type,
          'is_primary',          me.is_primary,
          'verification_status', me.verification_status
        )
        order by me.is_primary desc, me.id
      ),
      '[]'::jsonb
    )
    into v_contacts_emails
    from public.member_emails me
    where me.organization_id  = p_organization_id
      and me.member_id        = p_member_id
      and (me.effective_to_at is null or me.effective_to_at > now());

    -- phones
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',              mp.id,
          'phone_number',    mp.phone_number,
          'phone_type',      mp.phone_type,
          'is_primary',      mp.is_primary,
          'normalized_e164', mp.normalized_e164
        )
        order by mp.is_primary desc, mp.id
      ),
      '[]'::jsonb
    )
    into v_contacts_phones
    from public.member_phones mp
    where mp.organization_id  = p_organization_id
      and mp.member_id        = p_member_id
      and (mp.effective_to_at is null or mp.effective_to_at > now());
  end if;

  -- -------------------------------------------------------------------------
  -- Step 10: addresses — gated by members.addresses.view
  -- -------------------------------------------------------------------------
  if v_can_see_addresses then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',                  ma.id,
          'address_type',        ma.address_type,
          'is_primary',          ma.is_primary,
          'is_mailing_address',  ma.is_mailing_address,
          'address', jsonb_build_object(
            'address_line_1',      a.address_line_1,
            'address_line_2',      a.address_line_2,
            'address_line_3',      a.address_line_3,
            'city_name',           a.city_name,
            'state_province_name', a.state_province_name,
            'postal_code',         a.postal_code,
            'country_code',        a.country_code,
            'formatted_address',   a.formatted_address
          )
        )
        order by ma.is_primary desc, ma.is_mailing_address desc, ma.id
      ),
      '[]'::jsonb
    )
    into v_addresses
    from public.member_addresses ma
    join public.addresses a
      on a.id              = ma.address_id
     and a.organization_id = ma.organization_id
    where ma.organization_id = p_organization_id
      and ma.member_id       = p_member_id
      and (ma.effective_to is null or ma.effective_to > current_date);
  else
    v_addresses := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 11: section_placement — gated by members.sections.view
  -- -------------------------------------------------------------------------
  if v_can_see_sections then
    select jsonb_build_object(
      'section_membership_id', sm.id,
      'section_node_id',       sm.section_node_id,
      'section_name',          gn.name,
      'section_code',          gn.code,
      'membership_status',     sm.membership_status,
      'effective_from',        sm.effective_from
    )
    into v_section_placement
    from public.section_memberships sm
    join public.governance_nodes gn
      on gn.id              = sm.section_node_id
     and gn.organization_id = sm.organization_id
    where sm.organization_id = p_organization_id
      and sm.member_id       = p_member_id
      and sm.is_primary
      and sm.membership_status in ('active', 'temporary')
      and sm.effective_from <= current_date
      and (
        sm.effective_to is null
        or sm.effective_to > current_date
      )
    order by sm.effective_from desc
    limit 1;
  else
    v_section_placement := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 12: household_placement — gated by members.households.view
  -- -------------------------------------------------------------------------
  if v_can_see_households then
    select jsonb_build_object(
      'household_membership_id', hm.id,
      'household_node_id',       hm.household_node_id,
      'household_name',          gn.name,
      'household_code',          gn.code,
      'membership_status',       hm.membership_status,
      'membership_role',         hm.membership_role,
      'effective_from',          hm.effective_from
    )
    into v_household_placement
    from public.household_memberships hm
    join public.governance_nodes gn
      on gn.id              = hm.household_node_id
     and gn.organization_id = hm.organization_id
    where hm.organization_id = p_organization_id
      and hm.member_id       = p_member_id
      and hm.is_primary
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (
        hm.effective_to is null
        or hm.effective_to > current_date
      )
    order by hm.effective_from desc
    limit 1;
  else
    v_household_placement := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 13: governance_placement — gated by members.placements.view
  -- -------------------------------------------------------------------------
  if v_can_see_placements then
    select jsonb_build_object(
      'assignment_id',       mga.id,
      'governance_node_id',  mga.governance_node_id,
      'node_name',           gn.name,
      'node_code',           gn.code,
      'assignment_type',     mga.assignment_type,
      'assignment_basis',    mga.assignment_basis,
      'assignment_status',   mga.assignment_status,
      'effective_from',      mga.effective_from
    )
    into v_governance_placement
    from public.member_governance_assignments mga
    join public.governance_nodes gn
      on gn.id              = mga.governance_node_id
     and gn.organization_id = mga.organization_id
    where mga.organization_id = p_organization_id
      and mga.member_id       = p_member_id
      and mga.is_primary
      and mga.assignment_status = 'active'
      and mga.effective_from <= current_date
      and (
        mga.effective_to is null
        or mga.effective_to > current_date
      )
    order by mga.effective_from desc
    limit 1;
  else
    v_governance_placement := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 14: Assemble and return the full profile object
  -- -------------------------------------------------------------------------
  return jsonb_build_object(
    -- Always included: base record (members.records.view already verified)
    'id',                      v_member.id,
    'display_name',            v_member.display_name,
    'preferred_name',          v_member.preferred_name,
    'sort_name',               v_member.sort_name,
    'record_status',           v_member.record_status,

    -- Phase 5C structured identity fields (from current primary member_names row)
    'given_names',             v_cur_name.given_names,
    'middle_names',            v_cur_name.middle_names,
    'family_name',             v_cur_name.family_name,
    'preferred_given_name',    v_cur_name.preferred_given_name,
    'name_effective_from',     v_cur_name.effective_from,

    -- Phase 5C demographic fields (from members row)
    'birth_date',              v_member.birth_date,
    'sex',                     v_member.sex,
    'civil_status',            v_member.civil_status,
    'home_country_code',       v_member.home_country_code,
    'preferred_language_code', v_member.preferred_language_code,

    -- member_number: denormalized cache of member_identifiers.
    -- Gated by members.identifiers.view.
    'member_number', case
      when v_can_see_identifiers then v_member.member_number
      else null
    end,

    -- membership_status: basic status classification, always included
    'membership_status', v_membership_status,

    -- identifiers: null = no permission (or no data)
    'identifiers', v_identifiers,

    -- contacts: null = no permission. When permitted, always a JSON object
    -- with 'emails' and 'phones' arrays.
    'contacts', case
      when v_can_see_contacts then
        jsonb_build_object(
          'emails', coalesce(v_contacts_emails, '[]'::jsonb),
          'phones', coalesce(v_contacts_phones, '[]'::jsonb)
        )
      else null
    end,

    -- addresses: null = no permission (or no data)
    'addresses', v_addresses,

    -- section_placement: null = no permission or not currently placed
    'section_placement', v_section_placement,

    -- household_placement: null = no permission or not currently placed
    'household_placement', v_household_placement,

    -- governance_placement: null = no permission or no active assignment
    'governance_placement', v_governance_placement
  );
end;
$$;

-- Revoke all default grants, then grant only to authenticated + service_role
revoke all
  on function public.get_member_profile(uuid, uuid)
  from public, anon, authenticated;

grant execute
  on function public.get_member_profile(uuid, uuid)
  to authenticated, service_role;

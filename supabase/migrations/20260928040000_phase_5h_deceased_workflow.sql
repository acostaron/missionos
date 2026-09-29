-- =============================================================================
-- Migration: 20260928040000_phase_5h_deceased_workflow.sql
-- Description: Phase 5H-1 — Deceased Member Workflow
--
-- 1. Create dedicated permission members.deceased.manage
-- 2. Assign members.deceased.manage to organization_administrator
-- 3. Extend public.get_member_profile to expose is_deceased, deceased_on, deceased_on_precision
-- 4. Create public.record_member_deceased write RPC
-- 5. Revoke/Grant permissions cleanly (zero direct table writes/SELECT grants)
-- =============================================================================

-- =============================================================================
-- 1. DEDICATED PERMISSION: members.deceased.manage
-- =============================================================================
INSERT INTO public.permissions (
    id,
    code,
    name,
    description,
    domain_code,
    action_code,
    scope_type,
    risk_level,
    requires_access_reason,
    requires_access_logging,
    is_active
)
SELECT
    gen_random_uuid(),
    'members.deceased.manage',
    'Manage deceased member lifecycle',
    'Record a member as deceased, synchronize deceased metadata, and transition status to Deceased.',
    'members',
    'manage',
    'governance',
    'critical',
    false,
    true,
    true
WHERE NOT EXISTS (
    SELECT 1 FROM public.permissions WHERE code = 'members.deceased.manage'
);

-- =============================================================================
-- 2. ASSIGN TO organization_administrator
-- =============================================================================
INSERT INTO public.role_permissions (
    id,
    organization_id,
    app_role_id,
    permission_id,
    permission_effect,
    effective_from_at,
    effective_to_at,
    approval_status,
    approved_at,
    approved_by_profile_id,
    created_at,
    updated_at
)
SELECT
    gen_random_uuid(),
    r.organization_id,
    r.id AS app_role_id,
    p.id AS permission_id,
    'allow',
    now(),
    NULL,
    'approved',
    now(),
    NULL,
    now(),
    now()
FROM public.app_roles r
CROSS JOIN public.permissions p
WHERE r.code = 'organization_administrator'
  AND p.code = 'members.deceased.manage'
  AND NOT EXISTS (
      SELECT 1
      FROM public.role_permissions rp
      WHERE rp.app_role_id = r.id
        AND rp.permission_id = p.id
        AND (rp.organization_id IS NULL OR rp.organization_id = r.organization_id)
        AND rp.effective_to_at IS NULL
        AND rp.approval_status = 'approved'
  );


-- =============================================================================
-- 3. EXTEND public.get_member_profile TO EXPOSE DECEASED METADATA
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_member_profile(
    p_organization_id uuid,
    p_member_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_member               public.members%rowtype;
  v_cur_name             public.member_names%rowtype;
  v_can_see_identifiers  boolean;
  v_can_see_contacts     boolean;
  v_can_see_addresses    boolean;
  v_can_see_sections     boolean;
  v_can_see_households   boolean;
  v_can_see_placements   boolean;

  v_membership_status    jsonb;
  v_identifiers          jsonb;
  v_contacts_emails      jsonb;
  v_contacts_phones      jsonb;
  v_addresses            jsonb;
  v_section_placement    jsonb;
  v_household_placement  jsonb;
  v_governance_placement jsonb;
begin
  -- -------------------------------------------------------------------------
  -- Step 1: Verify active access to organization
  -- -------------------------------------------------------------------------
  if not private.has_organization_access(p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'Access denied: caller does not have access to this organization.';
  end if;

  -- -------------------------------------------------------------------------
  -- Step 2: Global permission guard
  -- -------------------------------------------------------------------------
  if not private.has_permission('members.records.view', p_organization_id) then
    raise exception
      using errcode = '42501',
            message = 'Access denied: missing required permission members.records.view.';
  end if;

  -- -------------------------------------------------------------------------
  -- Step 3 & 4: Scope check
  -- -------------------------------------------------------------------------
  if not private.can_access_member('members.records.view', p_organization_id, p_member_id) then
    raise exception
      using errcode = 'P0002',
            message = 'Member not found or not accessible.';
  end if;

  -- -------------------------------------------------------------------------
  -- Step 5: Load the member row
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
  -- Step 5b: Load the current primary name row
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
  where ms.id              = v_member.membership_status_id
    and ms.organization_id = p_organization_id;

  -- -------------------------------------------------------------------------
  -- Step 8: Load identifiers
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
        order by mi.is_primary desc, mi.identifier_type
      ),
      '[]'::jsonb
    )
    into v_identifiers
    from public.member_identifiers mi
    where mi.organization_id = p_organization_id
      and mi.member_id       = p_member_id
      and mi.effective_from <= current_date
      and (
        mi.effective_to is null
        or mi.effective_to > current_date
      );
  else
    v_identifiers := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 9: Load contacts
  -- -------------------------------------------------------------------------
  if v_can_see_contacts then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',                  me.id,
          'email_address',       me.email_address,
          'email_type',          me.email_type,
          'is_primary',          me.is_primary,
          'verification_status', me.verification_status
        )
        order by me.is_primary desc, me.created_at asc
      ),
      '[]'::jsonb
    )
    into v_contacts_emails
    from public.member_emails me
    where me.organization_id = p_organization_id
      and me.member_id       = p_member_id
      and me.effective_from_at <= now()
      and (
        me.effective_to_at is null
        or me.effective_to_at > now()
      )
      and me.verification_status <> 'archived';

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',                  mp.id,
          'phone_number',        mp.phone_number,
          'normalized_e164',     mp.normalized_e164,
          'phone_type',          mp.phone_type,
          'is_primary',          mp.is_primary,
          'verification_status', mp.verification_status
        )
        order by mp.is_primary desc, mp.created_at asc
      ),
      '[]'::jsonb
    )
    into v_contacts_phones
    from public.member_phones mp
    where mp.organization_id = p_organization_id
      and mp.member_id       = p_member_id
      and mp.effective_from_at <= now()
      and (
        mp.effective_to_at is null
        or mp.effective_to_at > now()
      )
      and mp.verification_status <> 'archived';
  else
    v_contacts_emails := null;
    v_contacts_phones := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 10: Load addresses
  -- -------------------------------------------------------------------------
  if v_can_see_addresses then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',                 ma.id,
          'address_type',       ma.address_type,
          'is_primary',         ma.is_primary,
          'is_mailing_address', ma.is_mailing_address,
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
        order by ma.is_primary desc, ma.created_at asc
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
      and ma.effective_from <= current_date
      and (
        ma.effective_to is null
        or ma.effective_to > current_date
      );
  else
    v_addresses := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 11: Load section placement
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
      and sm.membership_status = 'active'
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
  -- Step 12: Load household placement
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
      and hm.membership_status = 'active'
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
  -- Step 13: Load primary governance placement
  -- -------------------------------------------------------------------------
  if v_can_see_placements then
    select jsonb_build_object(
      'assignment_id',      mga.id,
      'governance_node_id', mga.governance_node_id,
      'node_name',          gn.name,
      'node_code',          gn.code,
      'assignment_type',    mga.assignment_type,
      'assignment_basis',   mga.assignment_basis,
      'assignment_status',  mga.assignment_status,
      'effective_from',     mga.effective_from
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
    'id',                      v_member.id,
    'display_name',            v_member.display_name,
    'preferred_name',          v_member.preferred_name,
    'sort_name',               v_member.sort_name,
    'record_status',           v_member.record_status,

    -- Phase 5H-1: Deceased metadata
    'is_deceased',             v_member.is_deceased,
    'deceased_on',             v_member.deceased_on,
    'deceased_on_precision',   v_member.deceased_on_precision,

    -- Phase 5C structured identity fields
    'given_names',             v_cur_name.given_names,
    'middle_names',            v_cur_name.middle_names,
    'family_name',             v_cur_name.family_name,
    'preferred_given_name',    v_cur_name.preferred_given_name,
    'name_effective_from',     v_cur_name.effective_from,

    -- Phase 5C demographic fields
    'birth_date',              v_member.birth_date,
    'sex',                     v_member.sex,
    'civil_status',            v_member.civil_status,
    'home_country_code',       v_member.home_country_code,
    'preferred_language_code', v_member.preferred_language_code,

    -- member_number
    'member_number', case
      when v_can_see_identifiers then v_member.member_number
      else null
    end,

    -- membership_status
    'membership_status', v_membership_status,

    -- identifiers
    'identifiers', v_identifiers,

    -- contacts
    'contacts', case
      when v_can_see_contacts then
        jsonb_build_object(
          'emails', coalesce(v_contacts_emails, '[]'::jsonb),
          'phones', coalesce(v_contacts_phones, '[]'::jsonb)
        )
      else null
    end,

    -- addresses
    'addresses', v_addresses,

    -- placements
    'section_placement', v_section_placement,
    'household_placement', v_household_placement,
    'governance_placement', v_governance_placement
  );
end;
$function$;

-- Revoke all default grants, then grant only to authenticated + service_role
revoke all on function public.get_member_profile(uuid, uuid) from public, anon, authenticated;
grant execute on function public.get_member_profile(uuid, uuid) to authenticated, service_role;


-- =============================================================================
-- 4. WRITE RPC: public.record_member_deceased
-- =============================================================================
CREATE OR REPLACE FUNCTION public.record_member_deceased(
    p_organization_id         uuid,
    p_member_id               uuid,
    p_deceased_on             date DEFAULT NULL,
    p_deceased_on_precision   text DEFAULT 'unknown',
    p_effective_from          date DEFAULT CURRENT_DATE,
    p_reason                  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
    v_actor_profile_id          uuid;
    v_member                    public.members%rowtype;
    v_cur_status                public.member_statuses%rowtype;
    v_deceased_status           public.member_statuses%rowtype;
    v_cur_history               public.member_status_history%rowtype;
    v_norm_effective_from_at    timestamptz;
    v_precision                 text;
    v_now                       timestamptz;
begin
    -- 1. Authenticate caller
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    -- 2. Validate organization access
    if not private.has_organization_access(p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
    end if;

    -- 3. Require members.deceased.manage permission
    if not private.has_permission('members.deceased.manage', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.deceased.manage.';
    end if;

    -- 4. Verify member-level governance scope
    if not private.can_access_member('members.deceased.manage', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: member is outside caller governance scope.';
    end if;

    -- 5. Lock and load target member
    select * into v_member
    from public.members
    where id = p_member_id
      and organization_id = p_organization_id
    for update;

    if not found then
        raise exception using errcode = 'P0002', message = 'Member not found or not accessible.';
    end if;

    -- 6. Reject if member is already recorded as deceased
    if v_member.is_deceased then
        raise exception using errcode = '22023', message = 'Member is already recorded as deceased.';
    end if;

    -- 7. Validate precision
    v_precision := coalesce(nullif(btrim(p_deceased_on_precision), ''), 'unknown');
    if v_precision not in ('exact', 'month_and_year', 'year_only', 'unknown') then
        raise exception using errcode = '22023', message = 'Validation error: invalid deceased_on_precision value.';
    end if;

    -- Precision requirements for death date:
    -- exact, month_and_year, year_only all require p_deceased_on to be provided
    if v_precision in ('exact', 'month_and_year', 'year_only') and p_deceased_on is null then
        raise exception using errcode = '22023', message = 'Validation error: date of death is required when precision is ' || v_precision || '.';
    end if;

    -- If unknown precision, deceased_on may be null or provided
    -- If deceased_on is provided, validate it is not in the future
    if p_deceased_on is not null and p_deceased_on > CURRENT_DATE then
        raise exception using errcode = '22023', message = 'Validation error: date of death cannot be in the future.';
    end if;

    -- 8. Validate effective date (must be non-null and not in the future)
    if p_effective_from is null then
        raise exception using errcode = '22023', message = 'Validation error: effective date is required.';
    end if;

    if p_effective_from > CURRENT_DATE then
        raise exception using errcode = '22023', message = 'Validation error: future-dated membership status transitions are not supported.';
    end if;

    -- 9. Load current status
    select * into v_cur_status
    from public.member_statuses
    where id = v_member.membership_status_id
      and organization_id = p_organization_id;

    if not found then
        raise exception using errcode = 'P0002', message = 'Current membership status not found for member.';
    end if;

    -- 10. Resolve the 'deceased' status row by code
    select * into v_deceased_status
    from public.member_statuses
    where organization_id = p_organization_id
      and code = 'deceased'
      and is_active = true;

    if not found then
        raise exception using errcode = 'P0002', message = 'Configuration error: deceased membership status not found for organization.';
    end if;

    -- 11. Lock current open history row
    select * into v_cur_history
    from public.member_status_history
    where organization_id = p_organization_id
      and member_id = p_member_id
      and effective_to_at is null
    for update;

    -- 12. Normalize effective timestamp
    v_now := clock_timestamp();
    if p_effective_from = CURRENT_DATE then
        v_norm_effective_from_at := v_now;
    else
        v_norm_effective_from_at := p_effective_from::timestamptz;
    end if;

    -- Validate not earlier than current history effective_from_at
    if v_cur_history.id is not null and v_norm_effective_from_at < v_cur_history.effective_from_at then
        raise exception using errcode = '22023', message = 'Validation error: effective date cannot be earlier than the current status start date (' || to_char(v_cur_history.effective_from_at, 'YYYY-MM-DD') || ').';
    end if;

    -- 13. Close current open history row if present
    if v_cur_history.id is not null then
        update public.member_status_history
        set effective_to_at = v_norm_effective_from_at
        where id = v_cur_history.id;
    end if;

    -- 14. Insert new deceased status history row
    insert into public.member_status_history (
        id,
        organization_id,
        member_id,
        member_status_id,
        effective_from_at,
        effective_to_at,
        change_reason_code,
        change_summary,
        source,
        approved_at,
        approved_by_profile_id,
        recorded_at,
        recorded_by_profile_id,
        metadata
    ) values (
        gen_random_uuid(),
        p_organization_id,
        p_member_id,
        v_deceased_status.id,
        v_norm_effective_from_at,
        NULL,
        NULL,
        nullif(btrim(p_reason), ''),
        'administrator',
        NULL,
        NULL,
        v_now,
        v_actor_profile_id,
        '{}'::jsonb
    );

    -- 15. Atomically update public.members
    update public.members
    set membership_status_id    = v_deceased_status.id,
        is_deceased             = true,
        deceased_on             = p_deceased_on,
        deceased_on_precision   = v_precision,
        updated_at              = v_now,
        updated_by_profile_id   = v_actor_profile_id
    where id = p_member_id
      and organization_id = p_organization_id;

    -- 16. Record audit event
    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.deceased.recorded',
        p_event_category   => 'member',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => p_member_id,
        p_action           => 'record_deceased',
        p_outcome          => 'success',
        p_access_reason    => null,
        p_correlation_id   => null,
        p_metadata         => jsonb_build_object(
            'deceased_on', p_deceased_on,
            'deceased_on_precision', v_precision,
            'effective_from', p_effective_from,
            'previous_status_id', v_cur_status.id,
            'previous_status_code', v_cur_status.code,
            'new_status_id', v_deceased_status.id,
            'new_status_code', v_deceased_status.code,
            'reason', nullif(btrim(p_reason), '')
        )
    );

    -- 17. Return confirmation payload
    return jsonb_build_object(
        'status', 'success',
        'member_id', p_member_id,
        'previous_status_id', v_cur_status.id,
        'previous_status_code', v_cur_status.code,
        'new_status_id', v_deceased_status.id,
        'new_status_code', v_deceased_status.code,
        'is_deceased', true,
        'deceased_on', p_deceased_on,
        'deceased_on_precision', v_precision,
        'effective_from', p_effective_from
    );
end;
$function$;

-- Revoke all default grants, then grant only to authenticated + service_role
revoke all on function public.record_member_deceased(uuid, uuid, date, text, date, text) from public, anon, authenticated;
grant execute on function public.record_member_deceased(uuid, uuid, date, text, date, text) to authenticated, service_role;

-- Migration: 20260905010000_phase_5a_member_write_rpcs.sql
-- Description: Authoritative Phase 5A member write RPC surface with strict security, validation, and audit controls.

BEGIN;

-- ============================================================================
-- 1. Helper function: private.normalize_phone_e164
-- Safely detects standard E.164 strings or standard 10-digit US strings.
-- Returns NULL if unparseable rather than throwing an error or guessing.
-- ============================================================================
CREATE OR REPLACE FUNCTION private.normalize_phone_e164(
    p_phone text,
    p_default_country text DEFAULT 'US'
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE STRICT
SET search_path TO 'pg_catalog', 'public'
AS $$
declare
    v_clean text;
begin
    v_clean := regexp_replace(p_phone, '[^\d+]', '', 'g');
    -- If already standard E.164 (+ followed by 7 to 15 digits)
    if v_clean ~ '^\+[1-9]\d{6,14}$' then
        return v_clean;
    end if;
    -- If 10 digits without leading country code and country is US/CA
    if p_default_country in ('US', 'CA') and v_clean ~ '^\d{10}$' then
        return '+1' || v_clean;
    end if;
    -- If 11 digits starting with 1 for US/CA
    if p_default_country in ('US', 'CA') and v_clean ~ '^1\d{10}$' then
        return '+' || v_clean;
    end if;
    return null;
end;
$$;

REVOKE ALL ON FUNCTION private.normalize_phone_e164(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.normalize_phone_e164(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION private.normalize_phone_e164(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.normalize_phone_e164(text, text) TO service_role;


-- ============================================================================
-- 2. RPC: public.create_member
-- Canonical onboarding RPC with pre-write duplicate check, sequence locking,
-- cache synchronization, and least-privilege optional component checks.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_member(
    p_organization_id uuid,
    p_given_names text,
    p_family_name text,
    p_middle_names text DEFAULT NULL,
    p_preferred_name text DEFAULT NULL,
    p_birth_date date DEFAULT NULL,
    p_sex text DEFAULT NULL,
    p_civil_status text DEFAULT NULL,
    p_joined_on date DEFAULT CURRENT_DATE,
    p_home_country_code character(2) DEFAULT 'US',
    p_governance_node_id uuid DEFAULT NULL,
    p_allocate_member_number boolean DEFAULT true,
    p_email text DEFAULT NULL,
    p_phone text DEFAULT NULL,
    p_phone_country_code character(2) DEFAULT 'US',
    p_address_line_1 text DEFAULT NULL,
    p_address_line_2 text DEFAULT NULL,
    p_city_name text DEFAULT NULL,
    p_state_province_name text DEFAULT NULL,
    p_postal_code text DEFAULT NULL,
    p_address_country_code character(2) DEFAULT 'US',
    p_allow_potential_duplicate boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
declare
    v_actor_profile_id uuid;
    v_membership_status_id uuid;
    v_new_member_id uuid;
    v_member_number text := null;
    v_calc_full_name text;
    v_pref_name text;
    v_disp_name text;
    v_sort_name text;
    v_norm_email text := null;
    v_norm_phone text := null;
    v_duplicate_matches jsonb := '[]'::jsonb;
    v_new_addr_id uuid;
begin
    -- 1. Resolve actor profile
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    -- 2. Verify organization access
    if not private.has_organization_access(p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: caller does not belong to active organization.';
    end if;

    -- 3. Verify required permissions for supplied components (Least Privilege)
    if not private.has_permission('members.records.create', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.records.create.';
    end if;

    if p_allocate_member_number and not private.has_permission('members.identifiers.manage', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.identifiers.manage to allocate member number.';
    end if;

    if p_governance_node_id is not null then
        if not private.has_permission('members.placements.manage', p_organization_id) then
            raise exception using errcode = '42501', message = 'Access denied: missing required permission members.placements.manage to assign placement.';
        end if;
        if not private.profile_has_governance_scope(auth.uid(), p_organization_id, p_governance_node_id, now()) then
            raise exception using errcode = '42501', message = 'Access denied: governance node is outside caller governance scope.';
        end if;
    else
        if not private.caller_has_org_scope_include(p_organization_id, null) then
            raise exception using errcode = '42501', message = 'Access denied: creating unplaced members requires organization-wide scope.';
        end if;
    end if;

    if (nullif(trim(p_email), '') is not null or nullif(trim(p_phone), '') is not null)
       and not private.has_permission('members.contacts.manage', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.contacts.manage to add contact information.';
    end if;

    if (nullif(trim(p_address_line_1), '') is not null or nullif(trim(p_city_name), '') is not null)
       and not private.has_permission('members.addresses.manage', p_organization_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing required permission members.addresses.manage to add residential address.';
    end if;

    -- 4. Validate inputs
    if nullif(trim(p_given_names), '') is null then
        raise exception using errcode = '23502', message = 'Validation error: given_names cannot be empty.';
    end if;
    if nullif(trim(p_family_name), '') is null then
        raise exception using errcode = '23502', message = 'Validation error: family_name cannot be empty.';
    end if;
    if p_birth_date is not null and p_birth_date > current_date then
        raise exception using errcode = '22023', message = 'Validation error: birth_date cannot be in the future.';
    end if;
    if nullif(trim(p_sex), '') is not null and trim(p_sex) not in ('male', 'female', 'other') then
        raise exception using errcode = '22023', message = 'Validation error: sex must be male, female, or other.';
    end if;
    if nullif(trim(p_civil_status), '') is not null and trim(p_civil_status) not in ('single', 'married', 'widowed', 'separated', 'divorced') then
        raise exception using errcode = '22023', message = 'Validation error: civil_status must be single, married, widowed, separated, or divorced.';
    end if;
    if nullif(trim(p_address_line_1), '') is not null and nullif(trim(p_city_name), '') is null then
        raise exception using errcode = '23502', message = 'Validation error: city_name is required when address_line_1 is provided.';
    end if;

    -- Compute calculated names and normalized contact strings
    v_calc_full_name := trim(trim(p_given_names) || ' ' || coalesce(nullif(trim(p_middle_names), '') || ' ', '') || trim(p_family_name));
    v_pref_name := coalesce(nullif(trim(p_preferred_name), ''), trim(p_given_names));
    v_disp_name := trim(v_pref_name || ' ' || trim(p_family_name));
    v_sort_name := trim(trim(p_family_name) || ', ' || trim(p_given_names) || coalesce(' ' || nullif(trim(p_middle_names), ''), ''));

    if nullif(trim(p_email), '') is not null then
        v_norm_email := private.normalize_email(p_email);
    end if;
    if nullif(trim(p_phone), '') is not null then
        v_norm_phone := private.normalize_phone_e164(p_phone, coalesce(p_phone_country_code, 'US'));
    end if;

    -- 5. Pre-write Duplicate Detection (ZERO writes, ZERO sequence allocation)
    select coalesce(jsonb_agg(candidate_row), '[]'::jsonb)
    into v_duplicate_matches
    from (
        select jsonb_build_object(
            'member_id', m.id,
            'member_number', m.member_number,
            'display_name', m.display_name,
            'match_score', case when (p_birth_date is not null and m.birth_date = p_birth_date and lower(mn.full_name) = lower(v_calc_full_name)) then 0.98 else 0.85 end,
            'match_reasons', (
                select jsonb_agg(reason)
                from (
                    select 'normalized_email_match' as reason where v_norm_email is not null and exists (
                        select 1 from public.member_emails me
                        where me.organization_id = p_organization_id and me.member_id = m.id
                          and me.effective_to_at is null and me.normalized_email = v_norm_email
                    )
                    union all
                    select 'phone_match' as reason where nullif(trim(p_phone), '') is not null and exists (
                        select 1 from public.member_phones mp
                        where mp.organization_id = p_organization_id and mp.member_id = m.id
                          and mp.effective_to_at is null
                          and ((v_norm_phone is not null and mp.normalized_e164 = v_norm_phone) or mp.phone_number = trim(p_phone))
                    )
                    union all
                    select 'exact_name_and_birth_date' as reason where p_birth_date is not null and m.birth_date is not null
                      and m.birth_date = p_birth_date and lower(mn.full_name) = lower(v_calc_full_name)
                    union all
                    select 'similar_name' as reason where similarity(mn.full_name, v_calc_full_name) >= 0.85
                ) sub
            )
        ) as candidate_row
        from public.members m
        join public.member_names mn on mn.member_id = m.id and mn.organization_id = m.organization_id and mn.is_primary and mn.effective_to is null
        where m.organization_id = p_organization_id
          and m.record_status = 'active'
          and (
              (v_norm_email is not null and exists (
                  select 1 from public.member_emails me
                  where me.organization_id = p_organization_id and me.member_id = m.id
                    and me.effective_to_at is null and me.normalized_email = v_norm_email
              ))
              or
              (nullif(trim(p_phone), '') is not null and exists (
                  select 1 from public.member_phones mp
                  where mp.organization_id = p_organization_id and mp.member_id = m.id
                    and mp.effective_to_at is null
                    and ((v_norm_phone is not null and mp.normalized_e164 = v_norm_phone) or mp.phone_number = trim(p_phone))
              ))
              or
              (p_birth_date is not null and m.birth_date is not null and m.birth_date = p_birth_date and lower(mn.full_name) = lower(v_calc_full_name))
              or
              (similarity(mn.full_name, v_calc_full_name) >= 0.85)
          )
        limit 5
    ) dup_query;

    -- 6. Gate: If warning matches exist and override is false, return warning immediately
    if jsonb_array_length(v_duplicate_matches) > 0 and not p_allow_potential_duplicate then
        return jsonb_build_object(
            'status', 'duplicate_warning',
            'warning_count', jsonb_array_length(v_duplicate_matches),
            'candidate_matches', v_duplicate_matches
        );
    end if;

    -- 7. Resolve canonical active membership status dynamically
    select id into v_membership_status_id
    from public.member_statuses
    where organization_id = p_organization_id
      and code = 'active'
      and is_active = true
    limit 1;

    if v_membership_status_id is null then
        raise exception using errcode = 'P0002', message = 'Configuration error: active membership status not found for organization.';
    end if;

    -- 8. Allocate member number ONLY if requested (Locks sequence row safely)
    if p_allocate_member_number then
        v_member_number := private.next_business_number(p_organization_id, 'member_number');
    end if;

    -- 9. Insert public.members (member_number initially NULL per canonical rule)
    v_new_member_id := gen_random_uuid();
    insert into public.members (
        id, organization_id, member_number, preferred_name, display_name, sort_name,
        birth_date, sex, civil_status, membership_status_id, joined_on,
        home_country_code, directory_visibility, record_status, is_deceased,
        data_quality_status, created_by_profile_id, updated_by_profile_id
    ) values (
        v_new_member_id, p_organization_id, null, v_pref_name, v_disp_name, v_sort_name,
        p_birth_date, nullif(trim(p_sex), ''), nullif(trim(p_civil_status), ''),
        v_membership_status_id, coalesce(p_joined_on, current_date),
        coalesce(p_home_country_code, 'US'), 'leaders_only', 'active', false,
        'verified', v_actor_profile_id, v_actor_profile_id
    );

    -- 10. Insert primary current member_names
    insert into public.member_names (
        id, organization_id, member_id, name_type, given_names, middle_names,
        family_name, preferred_given_name, full_name, sort_name,
        effective_from, is_primary, is_searchable, verification_status,
        created_by_profile_id, updated_by_profile_id
    ) values (
        gen_random_uuid(), p_organization_id, v_new_member_id, 'current',
        trim(p_given_names), nullif(trim(p_middle_names), ''), trim(p_family_name),
        nullif(trim(p_preferred_name), ''), v_calc_full_name, v_sort_name,
        current_date, true, true, 'unverified',
        v_actor_profile_id, v_actor_profile_id
    );

    -- 11. If allocated, insert member_identifiers and let schema trigger sync members.member_number
    if p_allocate_member_number then
        insert into public.member_identifiers (
            id, organization_id, member_id, identifier_type, source_system,
            identifier_value, normalized_value, is_primary, verification_status,
            effective_from, created_by_profile_id
        ) values (
            gen_random_uuid(), p_organization_id, v_new_member_id, 'member_number', 'missionos',
            v_member_number, upper(trim(v_member_number)), true, 'unverified',
            current_date, v_actor_profile_id
        );
    end if;

    -- 12. Optional Governance placement
    if p_governance_node_id is not null then
        insert into public.member_governance_assignments (
            id, organization_id, member_id, governance_node_id,
            assignment_type, assignment_status, effective_from,
            is_primary, assignment_basis, created_by_profile_id, updated_by_profile_id
        ) values (
            gen_random_uuid(), p_organization_id, v_new_member_id, p_governance_node_id,
            'primary', 'active', current_date, true, 'administrative',
            v_actor_profile_id, v_actor_profile_id
        );
    end if;

    -- 13. Optional Email
    if v_norm_email is not null then
        insert into public.member_emails (
            id, organization_id, member_id, email_address, normalized_email,
            email_type, is_primary, is_shared, verification_status, allows_ministry_email,
            effective_from_at, created_by_profile_id, updated_by_profile_id
        ) values (
            gen_random_uuid(), p_organization_id, v_new_member_id, trim(p_email), v_norm_email,
            'personal', true, false, 'unverified', true, now(),
            v_actor_profile_id, v_actor_profile_id
        );
    end if;

    -- 14. Optional Phone
    if nullif(trim(p_phone), '') is not null then
        insert into public.member_phones (
            id, organization_id, member_id, phone_number, normalized_e164,
            phone_type, country_code, is_primary, is_shared, verification_status,
            allows_voice_calls, allows_sms, allows_messaging_apps, effective_from_at,
            created_by_profile_id, updated_by_profile_id
        ) values (
            gen_random_uuid(), p_organization_id, v_new_member_id, trim(p_phone), v_norm_phone,
            'mobile', coalesce(p_phone_country_code, 'US'), true, false, 'unverified',
            true, true, false, now(), v_actor_profile_id, v_actor_profile_id
        );
    end if;

    -- 15. Optional Address
    if nullif(trim(p_address_line_1), '') is not null then
        v_new_addr_id := gen_random_uuid();
        insert into public.addresses (
            id, organization_id, address_line_1, address_line_2,
            city_name, state_province_name, postal_code, country_code,
            verification_status, source, created_by_profile_id, updated_by_profile_id
        ) values (
            v_new_addr_id, p_organization_id, trim(p_address_line_1), nullif(trim(p_address_line_2), ''),
            trim(p_city_name), nullif(trim(p_state_province_name), ''), nullif(trim(p_postal_code), ''),
            coalesce(p_address_country_code, 'US'), 'unverified', 'manual',
            v_actor_profile_id, v_actor_profile_id
        );

        insert into public.member_addresses (
            id, organization_id, member_id, address_id, address_type,
            is_primary, is_mailing_address, is_shared_family_address,
            effective_from, visibility, created_by_profile_id, updated_by_profile_id
        ) values (
            gen_random_uuid(), p_organization_id, v_new_member_id, v_new_addr_id, 'home',
            true, true, false, current_date, 'leaders_only',
            v_actor_profile_id, v_actor_profile_id
        );
    end if;

    -- 16. Audit event recording (PII excluded)
    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.created',
        p_event_category   => 'member',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => v_new_member_id,
        p_action           => 'create',
        p_outcome          => 'success',
        p_metadata         => jsonb_build_object(
            'has_member_number', (v_member_number is not null),
            'has_placement', (p_governance_node_id is not null),
            'governance_node_id', p_governance_node_id,
            'has_email', (v_norm_email is not null),
            'has_phone', (nullif(trim(p_phone), '') is not null),
            'has_address', (nullif(trim(p_address_line_1), '') is not null),
            'duplicate_override', (p_allow_potential_duplicate and jsonb_array_length(v_duplicate_matches) > 0),
            'duplicate_candidate_ids', (
                select coalesce(jsonb_agg(elem->>'member_id'), '[]'::jsonb)
                from jsonb_array_elements(v_duplicate_matches) elem
            )
        )
    );

    -- 17. Return success result
    return jsonb_build_object(
        'status', 'success',
        'member_id', v_new_member_id,
        'member_number', v_member_number,
        'display_name', v_disp_name,
        'governance_node_id', p_governance_node_id,
        'duplicate_override_applied', (p_allow_potential_duplicate and jsonb_array_length(v_duplicate_matches) > 0)
    );
end;
$$;

REVOKE ALL ON FUNCTION public.create_member(uuid, text, text, text, text, date, text, text, date, character, uuid, boolean, text, text, character, text, text, text, text, text, character, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_member(uuid, text, text, text, text, date, text, text, date, character, uuid, boolean, text, text, character, text, text, text, text, text, character, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_member(uuid, text, text, text, text, date, text, text, date, character, uuid, boolean, text, text, character, text, text, text, text, text, character, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_member(uuid, text, text, text, text, date, text, text, date, character, uuid, boolean, text, text, character, text, text, text, text, text, character, boolean) TO service_role;


-- ============================================================================
-- 3. RPC: public.update_member_basic_profile
-- Updates demographic attributes and/or name components, supporting typo fix
-- in-place vs. historical name changes with period validation.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_member_basic_profile(
    p_organization_id uuid,
    p_member_id uuid,
    p_given_names text,
    p_family_name text,
    p_middle_names text DEFAULT NULL,
    p_preferred_name text DEFAULT NULL,
    p_birth_date date DEFAULT NULL,
    p_sex text DEFAULT NULL,
    p_civil_status text DEFAULT NULL,
    p_home_country_code character(2) DEFAULT NULL,
    p_preferred_language_code text DEFAULT NULL,
    p_is_name_change boolean DEFAULT false,
    p_effective_from date DEFAULT CURRENT_DATE,
    p_change_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
declare
    v_actor_profile_id uuid;
    v_cur_name public.member_names%rowtype;
    v_calc_full_name text;
    v_pref_name text;
    v_disp_name text;
    v_sort_name text;
begin
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    if not private.can_access_member('members.records.update', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: caller does not have permission members.records.update for this member.';
    end if;

    if nullif(trim(p_given_names), '') is null then
        raise exception using errcode = '23502', message = 'Validation error: given_names cannot be empty.';
    end if;
    if nullif(trim(p_family_name), '') is null then
        raise exception using errcode = '23502', message = 'Validation error: family_name cannot be empty.';
    end if;
    if p_birth_date is not null and p_birth_date > current_date then
        raise exception using errcode = '22023', message = 'Validation error: birth_date cannot be in the future.';
    end if;
    if nullif(trim(p_sex), '') is not null and trim(p_sex) not in ('male', 'female', 'other') then
        raise exception using errcode = '22023', message = 'Validation error: sex must be male, female, or other.';
    end if;
    if nullif(trim(p_civil_status), '') is not null and trim(p_civil_status) not in ('single', 'married', 'widowed', 'separated', 'divorced') then
        raise exception using errcode = '22023', message = 'Validation error: civil_status must be single, married, widowed, separated, or divorced.';
    end if;

    -- Retrieve current primary active name
    select * into v_cur_name
    from public.member_names
    where organization_id = p_organization_id
      and member_id = p_member_id
      and is_primary = true
      and effective_to is null;

    if not found then
        raise exception using errcode = 'P0002', message = 'Current primary name record not found for member.';
    end if;

    v_calc_full_name := trim(trim(p_given_names) || ' ' || coalesce(nullif(trim(p_middle_names), '') || ' ', '') || trim(p_family_name));
    v_pref_name := coalesce(nullif(trim(p_preferred_name), ''), trim(p_given_names));
    v_disp_name := trim(v_pref_name || ' ' || trim(p_family_name));
    v_sort_name := trim(trim(p_family_name) || ', ' || trim(p_given_names) || coalesce(' ' || nullif(trim(p_middle_names), ''), ''));

    if p_is_name_change then
        -- Validate historical date: cannot precede current name's start date
        if v_cur_name.effective_from is not null and p_effective_from < v_cur_name.effective_from then
            raise exception using errcode = '22023',
                message = format('Effective date (%s) cannot precede current name start date (%s).', p_effective_from, v_cur_name.effective_from);
        end if;

        -- Close existing active primary name
        update public.member_names
        set effective_to = case when p_effective_from = v_cur_name.effective_from then p_effective_from else p_effective_from - 1 end,
            is_primary = false,
            updated_at = now(),
            updated_by_profile_id = v_actor_profile_id
        where id = v_cur_name.id;

        -- Insert new active primary name
        insert into public.member_names (
            id, organization_id, member_id, name_type, given_names, middle_names,
            family_name, preferred_given_name, full_name, sort_name,
            effective_from, is_primary, is_searchable, verification_status,
            created_by_profile_id, updated_by_profile_id
        ) values (
            gen_random_uuid(), p_organization_id, p_member_id, 'current',
            trim(p_given_names), nullif(trim(p_middle_names), ''), trim(p_family_name),
            nullif(trim(p_preferred_name), ''), v_calc_full_name, v_sort_name,
            p_effective_from, true, true, 'unverified',
            v_actor_profile_id, v_actor_profile_id
        );
    else
        -- Typo correction in place
        update public.member_names
        set given_names = trim(p_given_names),
            middle_names = nullif(trim(p_middle_names), ''),
            family_name = trim(p_family_name),
            preferred_given_name = nullif(trim(p_preferred_name), ''),
            full_name = v_calc_full_name,
            sort_name = v_sort_name,
            updated_at = now(),
            updated_by_profile_id = v_actor_profile_id
        where id = v_cur_name.id;
    end if;

    -- Synchronize cache columns on public.members
    update public.members
    set preferred_name = v_pref_name,
        display_name = v_disp_name,
        sort_name = v_sort_name,
        birth_date = p_birth_date,
        sex = nullif(trim(p_sex), ''),
        civil_status = nullif(trim(p_civil_status), ''),
        home_country_code = coalesce(p_home_country_code, home_country_code),
        preferred_language_code = coalesce(p_preferred_language_code, preferred_language_code),
        updated_at = now(),
        updated_by_profile_id = v_actor_profile_id
    where id = p_member_id
      and organization_id = p_organization_id;

    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.updated',
        p_event_category   => 'member',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => p_member_id,
        p_action           => 'update',
        p_outcome          => 'success',
        p_metadata         => jsonb_build_object(
            'is_name_change', p_is_name_change,
            'change_reason', nullif(trim(p_change_reason), '')
        )
    );

    return jsonb_build_object(
        'status', 'success',
        'member_id', p_member_id,
        'display_name', v_disp_name,
        'is_name_change', p_is_name_change
    );
end;
$$;

REVOKE ALL ON FUNCTION public.update_member_basic_profile(uuid, uuid, text, text, text, text, date, text, text, character, text, boolean, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_member_basic_profile(uuid, uuid, text, text, text, text, date, text, text, character, text, boolean, date, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_member_basic_profile(uuid, uuid, text, text, text, text, date, text, text, character, text, boolean, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_member_basic_profile(uuid, uuid, text, text, text, text, date, text, text, character, text, boolean, date, text) TO service_role;


-- ============================================================================
-- 4. RPC: public.set_member_contact_point
-- Manages email, phone, and address child records with effective dating.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_member_contact_point(
    p_organization_id uuid,
    p_member_id uuid,
    p_contact_type text,
    p_operation text,
    p_target_id uuid DEFAULT NULL,
    p_value text DEFAULT NULL,
    p_phone_country_code character(2) DEFAULT 'US',
    p_address_data jsonb DEFAULT NULL,
    p_effective_from date DEFAULT CURRENT_DATE,
    p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
declare
    v_actor_profile_id uuid;
    v_norm_email text;
    v_norm_phone text;
    v_new_id uuid;
    v_new_addr_id uuid;
    v_cur_addr_effective_from date;
begin
    v_actor_profile_id := private.current_profile_id();
    if v_actor_profile_id is null then
        raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
    end if;

    if p_contact_type not in ('email', 'phone', 'address') then
        raise exception using errcode = '22023', message = 'Validation error: contact_type must be email, phone, or address.';
    end if;

    if p_operation not in ('add', 'replace_primary', 'remove') then
        raise exception using errcode = '22023', message = 'Validation error: operation must be add, replace_primary, or remove.';
    end if;

    if p_contact_type in ('email', 'phone') and not private.can_access_member('members.contacts.manage', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing members.contacts.manage or member out of scope.';
    end if;

    if p_contact_type = 'address' and not private.can_access_member('members.addresses.manage', p_organization_id, p_member_id) then
        raise exception using errcode = '42501', message = 'Access denied: missing members.addresses.manage or member out of scope.';
    end if;

    -- Process EMAIL
    if p_contact_type = 'email' then
        if p_operation in ('add', 'replace_primary') then
            if nullif(trim(p_value), '') is null then
                raise exception using errcode = '23502', message = 'Validation error: email value cannot be empty.';
            end if;
            v_norm_email := private.normalize_email(p_value);

            if p_operation = 'replace_primary' then
                update public.member_emails
                set effective_to_at = greatest(clock_timestamp(), effective_from_at + interval '1 millisecond'),
                    is_primary = false,
                    updated_at = now(),
                    updated_by_profile_id = v_actor_profile_id
                where organization_id = p_organization_id
                  and member_id = p_member_id
                  and is_primary = true
                  and effective_to_at is null;
            end if;

            v_new_id := gen_random_uuid();
            insert into public.member_emails (
                id, organization_id, member_id, email_address, normalized_email,
                email_type, is_primary, is_shared, verification_status, allows_ministry_email,
                effective_from_at, created_by_profile_id, updated_by_profile_id
            ) values (
                v_new_id, p_organization_id, p_member_id, trim(p_value), v_norm_email,
                'personal', (p_operation = 'replace_primary'), false, 'unverified', true,
                clock_timestamp(), v_actor_profile_id, v_actor_profile_id
            );
        elsif p_operation = 'remove' then
            if p_target_id is null then
                raise exception using errcode = '23502', message = 'Validation error: p_target_id is required to remove email.';
            end if;
            update public.member_emails
            set effective_to_at = greatest(clock_timestamp(), effective_from_at + interval '1 millisecond'),
                is_primary = false,
                updated_at = now(),
                updated_by_profile_id = v_actor_profile_id
            where id = p_target_id
              and organization_id = p_organization_id
              and member_id = p_member_id;
            v_new_id := p_target_id;
        end if;

    -- Process PHONE
    elsif p_contact_type = 'phone' then
        if p_operation in ('add', 'replace_primary') then
            if nullif(trim(p_value), '') is null then
                raise exception using errcode = '23502', message = 'Validation error: phone value cannot be empty.';
            end if;
            v_norm_phone := private.normalize_phone_e164(p_value, coalesce(p_phone_country_code, 'US'));

            if p_operation = 'replace_primary' then
                update public.member_phones
                set effective_to_at = greatest(clock_timestamp(), effective_from_at + interval '1 millisecond'),
                    is_primary = false,
                    updated_at = now(),
                    updated_by_profile_id = v_actor_profile_id
                where organization_id = p_organization_id
                  and member_id = p_member_id
                  and is_primary = true
                  and effective_to_at is null;
            end if;

            v_new_id := gen_random_uuid();
            insert into public.member_phones (
                id, organization_id, member_id, phone_number, normalized_e164,
                phone_type, country_code, is_primary, is_shared, verification_status,
                allows_voice_calls, allows_sms, allows_messaging_apps, effective_from_at,
                created_by_profile_id, updated_by_profile_id
            ) values (
                v_new_id, p_organization_id, p_member_id, trim(p_value), v_norm_phone,
                'mobile', coalesce(p_phone_country_code, 'US'), (p_operation = 'replace_primary'),
                false, 'unverified', true, true, false, clock_timestamp(), v_actor_profile_id, v_actor_profile_id
            );
        elsif p_operation = 'remove' then
            if p_target_id is null then
                raise exception using errcode = '23502', message = 'Validation error: p_target_id is required to remove phone.';
            end if;
            update public.member_phones
            set effective_to_at = greatest(clock_timestamp(), effective_from_at + interval '1 millisecond'),
                is_primary = false,
                updated_at = now(),
                updated_by_profile_id = v_actor_profile_id
            where id = p_target_id
              and organization_id = p_organization_id
              and member_id = p_member_id;
            v_new_id := p_target_id;
        end if;

    -- Process ADDRESS
    elsif p_contact_type = 'address' then
        if p_operation in ('add', 'replace_primary') then
            if p_address_data is null or nullif(trim(p_address_data->>'line1'), '') is null or nullif(trim(p_address_data->>'city'), '') is null then
                raise exception using errcode = '23502', message = 'Validation error: address line1 and city are required.';
            end if;

            if p_operation = 'replace_primary' then
                select effective_from into v_cur_addr_effective_from
                from public.member_addresses
                where organization_id = p_organization_id
                  and member_id = p_member_id
                  and is_primary = true
                  and address_type = 'home'
                  and effective_to is null;

                if found and v_cur_addr_effective_from is not null and p_effective_from < v_cur_addr_effective_from then
                    raise exception using errcode = '22023',
                        message = format('Effective date (%s) cannot precede current address start date (%s).', p_effective_from, v_cur_addr_effective_from);
                end if;

                update public.member_addresses
                set effective_to = case when p_effective_from = effective_from then p_effective_from else p_effective_from - 1 end,
                    is_primary = false,
                    updated_at = now(),
                    updated_by_profile_id = v_actor_profile_id
                where organization_id = p_organization_id
                  and member_id = p_member_id
                  and is_primary = true
                  and address_type = 'home'
                  and effective_to is null;
            end if;

            v_new_addr_id := gen_random_uuid();
            insert into public.addresses (
                id, organization_id, address_line_1, address_line_2,
                city_name, state_province_name, postal_code, country_code,
                verification_status, source, created_by_profile_id, updated_by_profile_id
            ) values (
                v_new_addr_id, p_organization_id, trim(p_address_data->>'line1'), nullif(trim(p_address_data->>'line2'), ''),
                trim(p_address_data->>'city'), nullif(trim(p_address_data->>'state'), ''), nullif(trim(p_address_data->>'postal'), ''),
                coalesce(p_address_data->>'country', 'US'), 'unverified', 'manual',
                v_actor_profile_id, v_actor_profile_id
            );

            v_new_id := gen_random_uuid();
            insert into public.member_addresses (
                id, organization_id, member_id, address_id, address_type,
                is_primary, is_mailing_address, is_shared_family_address,
                effective_from, visibility, created_by_profile_id, updated_by_profile_id
            ) values (
                v_new_id, p_organization_id, p_member_id, v_new_addr_id, 'home',
                (p_operation = 'replace_primary'), true, false,
                p_effective_from, 'leaders_only',
                v_actor_profile_id, v_actor_profile_id
            );
        elsif p_operation = 'remove' then
            if p_target_id is null then
                raise exception using errcode = '23502', message = 'Validation error: p_target_id is required to remove address.';
            end if;
            update public.member_addresses
            set effective_to = coalesce(p_effective_from, current_date),
                is_primary = false,
                updated_at = now(),
                updated_by_profile_id = v_actor_profile_id
            where id = p_target_id
              and organization_id = p_organization_id
              and member_id = p_member_id;
            v_new_id := p_target_id;
        end if;
    end if;

    perform private.write_audit_event(
        p_organization_id  => p_organization_id,
        p_event_code       => 'member.contact.updated',
        p_event_category   => 'member',
        p_actor_profile_id => v_actor_profile_id,
        p_entity_type      => 'member',
        p_entity_id        => p_member_id,
        p_action           => p_operation,
        p_outcome          => 'success',
        p_metadata         => jsonb_build_object(
            'contact_type', p_contact_type,
            'operation', p_operation,
            'record_id', v_new_id,
            'reason', nullif(trim(p_reason), '')
        )
    );

    return jsonb_build_object(
        'status', 'success',
        'member_id', p_member_id,
        'contact_type', p_contact_type,
        'operation', p_operation,
        'record_id', v_new_id
    );
end;
$$;

REVOKE ALL ON FUNCTION public.set_member_contact_point(uuid, uuid, text, text, uuid, text, character, jsonb, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_member_contact_point(uuid, uuid, text, text, uuid, text, character, jsonb, date, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_member_contact_point(uuid, uuid, text, text, uuid, text, character, jsonb, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_member_contact_point(uuid, uuid, text, text, uuid, text, character, jsonb, date, text) TO service_role;


-- ============================================================================
-- 5. RPC: public.change_member_governance_assignment
-- Handles initial placement, transfers, and unplacement with strict date checks
-- and automated cache updates via table triggers.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.change_member_governance_assignment(
    p_organization_id uuid,
    p_member_id uuid,
    p_target_governance_node_id uuid DEFAULT NULL,
    p_effective_from date DEFAULT CURRENT_DATE,
    p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $$
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

        if v_target_node_code not in ('chapter', 'unit') then
            raise exception using errcode = '22023', message = 'Validation error: governance placement must target a chapter or unit.';
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
$$;

REVOKE ALL ON FUNCTION public.change_member_governance_assignment(uuid, uuid, uuid, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.change_member_governance_assignment(uuid, uuid, uuid, date, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.change_member_governance_assignment(uuid, uuid, uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_member_governance_assignment(uuid, uuid, uuid, date, text) TO service_role;

COMMIT;

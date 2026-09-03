-- =============================================================================
-- Migration: 20260902_173600_release_1a_member_directory_rpcs.sql
-- Phase:     Release 1A — Phase 4 Member Directory & Profile (read-only)
--
-- Summary:
--   Adds two SECURITY DEFINER RPCs for authenticated browser access:
--     public.search_members(...)       — server-side member directory search
--     public.get_member_profile(...)   — read-only member profile with
--                                        permission-gated field sections
--
-- Authorization model:
--   All member access remains RPC-mediated.
--   No SELECT privilege is granted on any member table.
--   Scope is enforced by private.can_access_member(), not only org_id filtering.
--   Field-level visibility is controlled by permission checks inside the RPC.
--
-- Member number note (IMPORTANT):
--   members.member_number is a DENORMALIZED CACHE column maintained by the
--   private.sync_member_number_cache trigger, which copies from:
--     member_identifiers WHERE identifier_type = 'member_number'
--                          AND is_primary
--                          AND effective_to IS NULL
--   It is architecturally an identifier, not a base record field.
--   Therefore it is gated behind members.identifiers.view in both RPCs,
--   consistent with the authoritative permission catalog
--   (members.identifiers.view, risk_level=high, scope_type=governance).
--
-- Scope enforcement:
--   private.can_access_member(permission_code, org_id, member_id) → boolean
--   This function evaluates:
--     1. Self-access shortcut (caller is the member)
--     2. Governance scope via profile_has_governance_scope()
--        (matches primary_household_node_id, primary_section_node_id,
--         primary_governance_node_id, with descendant resolution)
--     3. Direct member scope assignment (scope_type = 'member')
--     4. Exclude gates honored (deny overrides allow)
--   The current organization_administrator has organization-wide scope with
--   includes_descendants = true, so all org members are visible to them.
--
-- Not-found behavior:
--   For get_member_profile: inaccessible and nonexistent member IDs both
--   raise SQLSTATE 'P0002' with message 'Member not found or not accessible.'
--   This prevents leaking whether a record exists in another scope or org.
--
-- Security controls:
--   - SECURITY DEFINER (required: authenticated role has no SELECT on tables)
--   - search_path = pg_catalog, public, private, auth  (fixed, no search hijack)
--   - REVOKE ALL on both functions from PUBLIC, anon, authenticated
--   - GRANT EXECUTE to authenticated, service_role only
--   - No GRANT SELECT on underlying tables
-- =============================================================================

begin;

-- =============================================================================
-- FUNCTION: public.search_members
-- =============================================================================
-- Returns a paginated, scope-filtered member directory list.
--
-- Arguments:
--   p_organization_id  uuid     REQUIRED  — organization boundary
--   p_search           text     OPTIONAL  — freetext filter (max 200 chars)
--   p_record_status    text     OPTIONAL  — default 'active'
--   p_status_ids       uuid[]   OPTIONAL  — filter by membership_status_id(s)
--   p_page             integer  OPTIONAL  — 1-based page number, default 1
--   p_page_size        integer  OPTIONAL  — rows per page, default 50, max 100
--
-- Returns: jsonb
--   {
--     "total_count": integer,      -- scope-filtered total (before pagination)
--     "page":        integer,      -- echoed page number
--     "page_size":   integer,      -- effective page size used
--     "members": [
--       {
--         "id":           uuid,
--         "display_name": text,
--         "preferred_name": text,
--         "record_status": text,
--         "member_number": text | null,   -- only if members.identifiers.view
--         "membership_status": {
--           "id":                 uuid,
--           "code":               text,
--           "name":               text,
--           "status_category":    text,
--           "is_active_membership": boolean
--         }
--       }
--     ]
--   }
--
-- Authorization:
--   Step 1: Resolve caller via private.current_profile_id()
--   Step 2: Validate active org access via private.has_organization_access()
--   Step 3: Require members.records.view via private.has_permission()
--   Step 4: Per-member scope via private.can_access_member() in a CTE filter
--
-- Field visibility:
--   member_number   — included only when members.identifiers.view is allow
--   All other fields — included for all callers with members.records.view
--
-- Search:
--   Parameterized ILIKE against sort_name, preferred_name, display_name.
--   p_search is not interpolated into SQL — it is passed as a bind parameter.
--   Empty/null search = no text filter.
--
-- Pagination:
--   Offset-based (page × page_size).
--   Deterministic ordering: sort_name ASC, id ASC.
--   total_count reflects scope-filtered count, enabling frontend page math.
-- =============================================================================

create or replace function public.search_members(
  p_organization_id uuid,
  p_search          text    default null,
  p_record_status   text    default 'active',
  p_status_ids      uuid[]  default null,
  p_page            integer default 1,
  p_page_size       integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id        uuid;
  -- NOTE: v_can_see_identifiers is intentionally absent here.
  -- member_number visibility is evaluated per returned member via
  -- private.can_access_member('members.identifiers.view', ..., member_id)
  -- in the jsonb_agg expression.  A caller scoped to a governance sub-node
  -- must not see member numbers for members outside their scope.
  v_effective_page    integer;
  v_effective_size    integer;
  v_offset            integer;
  v_search_term       text;
  v_total_count       bigint;
  v_members           jsonb;
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
  -- Step 4: Input validation / normalize
  -- -------------------------------------------------------------------------
  if length(coalesce(p_search, '')) > 200 then
    raise exception
      using errcode = '22023',
            message = 'Search term must not exceed 200 characters.';
  end if;

  -- Clamp page and page_size to safe values
  v_effective_page := greatest(coalesce(p_page, 1), 1);
  v_effective_size := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_offset         := (v_effective_page - 1) * v_effective_size;

  -- Normalize search term: null or blank = no filter
  v_search_term := nullif(btrim(coalesce(p_search, '')), '');

  -- -------------------------------------------------------------------------
  -- Step 5: Scope-filtered count and page
  --
  -- Approach:
  --   - Build a CTE of candidate members matching org + record_status + search
  --   - Filter by private.can_access_member('members.records.view', ..., id)
  --   - Count the scope-filtered set, then apply LIMIT/OFFSET for the page
  --
  -- member_number visibility:
  --   Evaluated inline per member via
  --   private.can_access_member('members.identifiers.view', ..., id).
  --   A caller with identifiers.view scoped only to certain nodes must not
  --   receive member numbers for members outside that scope.
  --
  -- NOTE: can_access_member performs its own permission check internally,
  -- but we still call has_permission('members.records.view') above to
  -- fast-fail with a clear diagnostic before running per-row scope work.
  -- -------------------------------------------------------------------------

  with candidates as (
    select
      m.id,
      m.display_name,
      m.preferred_name,
      m.record_status,
      m.member_number,
      m.sort_name,
      m.membership_status_id
    from public.members m
    where m.organization_id    = p_organization_id
      and m.record_status      = coalesce(p_record_status, 'active')
      and (
        p_status_ids is null
        or m.membership_status_id = any(p_status_ids)
      )
      and (
        v_search_term is null
        or m.sort_name       ilike '%' || v_search_term || '%'
        or m.preferred_name  ilike '%' || v_search_term || '%'
        or m.display_name    ilike '%' || v_search_term || '%'
      )
  ),
  scoped as (
    select c.*
    from candidates c
    where private.can_access_member(
      'members.records.view',
      p_organization_id,
      c.id
    )
  )
  select count(*) into v_total_count from scoped;

  -- Now fetch the page
  with candidates as (
    select
      m.id,
      m.display_name,
      m.preferred_name,
      m.record_status,
      m.member_number,
      m.sort_name,
      m.membership_status_id
    from public.members m
    where m.organization_id    = p_organization_id
      and m.record_status      = coalesce(p_record_status, 'active')
      and (
        p_status_ids is null
        or m.membership_status_id = any(p_status_ids)
      )
      and (
        v_search_term is null
        or m.sort_name       ilike '%' || v_search_term || '%'
        or m.preferred_name  ilike '%' || v_search_term || '%'
        or m.display_name    ilike '%' || v_search_term || '%'
      )
  ),
  scoped as (
    select c.*
    from candidates c
    where private.can_access_member(
      'members.records.view',
      p_organization_id,
      c.id
    )
    order by c.sort_name asc, c.id asc
    limit  v_effective_size
    offset v_offset
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',           s.id,
        'display_name', s.display_name,
        'preferred_name', s.preferred_name,
        'record_status', s.record_status,
        -- member_number: gated by members.identifiers.view PER MEMBER.
        -- members.member_number is a denormalized cache of member_identifiers
        -- (identifier_type='member_number', is_primary, effective_to IS NULL)
        -- and therefore requires the identifiers permission.
        -- Evaluated via can_access_member so a caller scoped to a sub-node
        -- cannot receive member numbers for members outside their scope,
        -- even if they hold members.identifiers.view somewhere in the org.
        'member_number', case
          when private.can_access_member(
            'members.identifiers.view',
            p_organization_id,
            s.id
          ) then s.member_number
          else null
        end,
        'membership_status', (
          select jsonb_build_object(
            'id',                   ms.id,
            'code',                 ms.code,
            'name',                 ms.name,
            'status_category',      ms.status_category,
            'is_active_membership', ms.is_active_membership
          )
          from public.member_statuses ms
          where ms.organization_id = p_organization_id
            and ms.id = s.membership_status_id
        )
      )
      order by s.sort_name asc, s.id asc
    ),
    '[]'::jsonb
  )
  into v_members
  from scoped s;

  return jsonb_build_object(
    'total_count', v_total_count,
    'page',        v_effective_page,
    'page_size',   v_effective_size,
    'members',     v_members
  );
end;
$$;

-- Revoke all default grants, then grant only to authenticated + service_role
revoke all
  on function public.search_members(uuid, text, text, uuid[], integer, integer)
  from public, anon, authenticated;

grant execute
  on function public.search_members(uuid, text, text, uuid[], integer, integer)
  to authenticated, service_role;


-- =============================================================================
-- FUNCTION: public.get_member_profile
-- =============================================================================
-- Returns a read-only member profile with permission-gated field sections.
--
-- Arguments:
--   p_organization_id  uuid  REQUIRED — organization boundary
--   p_member_id        uuid  REQUIRED — member to fetch
--
-- Returns: jsonb
--   {
--     "id":            uuid,
--     "display_name":  text,
--     "preferred_name": text,
--     "sort_name":     text,
--     "record_status": text,
--     "member_number": text | null,     -- null if lacks members.identifiers.view
--     "membership_status": { id, code, name, status_category,
--                            is_active_membership },
--     "identifiers":   null | [ { id, identifier_type, identifier_value,
--                                 is_primary, verification_status } ],
--     "contacts":      null | { "emails": [...], "phones": [...] },
--     "addresses":     null | [ { id, address_type, is_primary,
--                                 is_mailing_address, address: { ... } } ],
--     "section_placement":    null | { ... },
--     "household_placement":  null | { ... },
--     "governance_placement": null | { ... }
--   }
--
--   A section value of JSON null means "no permission" or "no data."
--   The key is always present so the frontend can distinguish.
--   (No separate metadata field needed.)
--
-- Authorization:
--   Step 1: Resolve caller via private.current_profile_id()
--   Step 2: Validate active org access via private.has_organization_access()
--   Step 3: Require members.records.view via private.has_permission()
--   Step 4: Scope check via private.can_access_member()
--            → raises P0002 "Member not found or not accessible."
--              for both nonexistent and out-of-scope members
--              (indistinguishable by design — no existence leak)
--
-- Field-level permission gates (all evaluated via can_access_member(code, org, p_member_id)):
--   member_number / identifiers → members.identifiers.view
--   contacts (emails, phones)   → members.contacts.view
--   addresses                   → members.addresses.view
--   section_placement           → members.sections.view
--   household_placement         → members.households.view
--   governance_placement        → members.placements.view
--
-- Data never returned:
--   member_notes content, QR token / token_hash, consent evidence,
--   audit/security event data, financial data, pastoral confidential fields.
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
  -- Step 6: Evaluate all field-level permission flags via can_access_member
  --
  -- WHY can_access_member and NOT has_permission:
  --   has_permission(code, org_id) tests only whether the caller holds the
  --   permission somewhere in the organization.  It does NOT verify that their
  --   scope assignment covers THIS specific member.
  --
  --   A caller with members.contacts.view scoped to Section A must not receive
  --   contact information for a member in Section B — even though they hold
  --   the permission.  can_access_member enforces that the caller's scope
  --   (governance node, household, section, direct member, or org-wide)
  --   covers p_member_id before returning true.
  --
  -- All flags are computed here once, before any data assembly, so each
  -- SELECT below remains a simple conditional with no nested permission calls.
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
  --
  -- Returns all active identifiers for the member.
  -- Explicitly excludes no fields that aren't needed:
  --   - identifier_value is included (that IS the point of this permission)
  --   - normalized_value is omitted (internal, not user-facing)
  --   - metadata is omitted (may contain internal system notes)
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
  --
  -- Emails: primary active records.
  --   Includes email_address (user-facing), not normalized_email (internal).
  -- Phones: primary active records.
  --   Includes phone_number and normalized_e164.
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
  -- (if no permission, v_contacts_emails and v_contacts_phones remain null)

  -- -------------------------------------------------------------------------
  -- Step 10: addresses — gated by members.addresses.view
  --
  -- member_addresses is a join table linking member_id → address_id.
  -- The address fields (lines, city, postal_code, country) are in public.addresses.
  -- Returns: address_line_1/2/3, city_name, state_province_name,
  --          postal_code, country_code, formatted_address (if available).
  -- Does NOT return: latitude, longitude, geocode_precision (not user-facing).
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
  --
  -- Returns the single active primary section membership.
  -- section_node_id → governance_nodes.name (the section name).
  --
  -- "Currently active" = effective_from <= today AND (effective_to IS NULL
  -- OR effective_to > today).  A membership with a future end date is still
  -- current and must be included.
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
    -- v_section_placement remains null if no currently active primary section membership
  else
    v_section_placement := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 12: household_placement — gated by members.households.view
  --
  -- Returns the single active primary household membership.
  -- household_node_id → governance_nodes.name.
  --
  -- "Currently active" = effective_from <= today AND (effective_to IS NULL
  -- OR effective_to > today).  A membership with a future end date is still
  -- current and must be included.
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
    -- v_household_placement remains null if no currently active primary household
  else
    v_household_placement := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 13: governance_placement — gated by members.placements.view
  --
  -- Returns the single active primary governance assignment.
  -- governance_node_id → governance_nodes.name.
  --
  -- "Currently active" = effective_from <= today AND (effective_to IS NULL
  -- OR effective_to > today) AND assignment_status = 'active'.
  -- An assignment with a future end date is still current.
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
    -- v_governance_placement remains null if no currently active primary assignment
  else
    v_governance_placement := null;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 14: Assemble and return the full profile object
  -- -------------------------------------------------------------------------
  return jsonb_build_object(
    -- Always included: base record (members.records.view already verified)
    'id',             v_member.id,
    'display_name',   v_member.display_name,
    'preferred_name', v_member.preferred_name,
    'sort_name',      v_member.sort_name,
    'record_status',  v_member.record_status,

    -- member_number: denormalized cache of member_identifiers.
    -- Gated by members.identifiers.view.
    -- Returns null (not the key absent) when permission is not held.
    'member_number', case
      when v_can_see_identifiers then v_member.member_number
      else null
    end,

    -- membership_status: basic status classification, always included
    'membership_status', v_membership_status,

    -- identifiers: null = no permission (or no data)
    'identifiers', v_identifiers,

    -- contacts: null = no permission.  When permitted, always a JSON object
    -- with 'emails' and 'phones' arrays (may be empty arrays, never null arrays).
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


-- =============================================================================
-- Function comments
-- =============================================================================

comment on function public.search_members(uuid, text, text, uuid[], integer, integer) is
  'Paginated, scope-filtered member directory. Requires members.records.view. '
  'Scope enforced per-member via private.can_access_member(). '
  'member_number returned only when members.identifiers.view is allow. '
  'Phase 4 — Release 1A.';

comment on function public.get_member_profile(uuid, uuid) is
  'Read-only member profile with permission-gated field sections. '
  'Requires members.records.view + scope access via private.can_access_member(). '
  'Field sections (identifiers, contacts, addresses, section/household/governance placements) '
  'each require their own permission. Returns null for any section without permission. '
  'Never returns notes, QR token hashes, audit data, or consent evidence. '
  'Inaccessible and nonexistent member IDs produce identical P0002 errors. '
  'Phase 4 — Release 1A.';

commit;

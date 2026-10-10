-- =============================================================================
-- Migration: 20261010020000_formal_pastoral_formation_catalog_read_api.sql
-- Phase:     Stage 3A — Formal Pastoral Formation (Pass 3A-3)
-- Purpose:   Implement the read-only Formation Catalog API layer:
--            1. public.get_formation_catalog (catalog overview with talk/req counts)
--            2. public.get_formation_program (program detail with talks & requirements)
-- Notes:     - SECURITY DEFINER with search_path = pg_catalog, public, private, auth
--            - Enforces formation.catalog.view & active organization access
--            - include_inactive requires formation.catalog.manage
--            - Global programs (organization_id IS NULL) + local programs for caller org
--            - Cross-organization leakage strictly prevented
--            - ZERO table policies added (RLS default-deny preserved)
--            - ZERO member records or Household Topic modifications
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. RPC: public.get_formation_catalog
-- -----------------------------------------------------------------------------

create or replace function public.get_formation_catalog(
  p_organization_id   uuid,
  p_program_category  text default null,
  p_include_inactive  boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id        uuid;
  v_include_inactive  boolean;
  v_result            jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization parameter validation
  if p_organization_id is null then
    raise exception using errcode = '22023', message = 'Organization ID is required.';
  end if;

  -- 3. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 4. Dedicated catalog permission check
  if not private.has_permission('formation.catalog.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view the formation curriculum catalog.';
  end if;

  -- 5. Inactive curriculum permission check
  v_include_inactive := coalesce(p_include_inactive, false);
  if v_include_inactive and not private.has_permission('formation.catalog.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'Permission formation.catalog.manage is required to view inactive curriculum.';
  end if;

  -- 6. Query programs (global curriculum + local programs of requested org)
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'organization_id', p.organization_id,
      'code', p.code,
      'title', p.title,
      'edition', p.edition,
      'program_category', p.program_category,
      'program_type', p.program_type,
      'description', p.description,
      'sequence_order', p.sequence_order,
      'is_active', p.is_active,
      'effective_from', p.effective_from,
      'effective_to', p.effective_to,
      'source_document', p.source_document,
      'source_url', p.source_url,
      'source_verified_at', p.source_verified_at,
      'talk_count', count(distinct t.id),
      'requirement_count', count(distinct r.id)
    )
    order by p.sequence_order nulls last, p.title asc, p.code asc
  ), '[]'::jsonb)
  into v_result
  from public.formation_programs p
  left join public.formation_talks t
    on t.program_id = p.id
   and (v_include_inactive or t.is_active = true)
  left join public.formation_program_requirements r
    on r.program_id = p.id
   and (v_include_inactive or r.is_active = true)
  where (p.organization_id is null or p.organization_id = p_organization_id)
    and (v_include_inactive or p.is_active = true)
    and (p_program_category is null or p.program_category = p_program_category)
  group by
    p.id, p.organization_id, p.code, p.title, p.edition,
    p.program_category, p.program_type, p.description,
    p.sequence_order, p.is_active, p.effective_from, p.effective_to,
    p.source_document, p.source_url, p.source_verified_at;

  return v_result;
end;
$$;


-- -----------------------------------------------------------------------------
-- 2. RPC: public.get_formation_program
-- -----------------------------------------------------------------------------

create or replace function public.get_formation_program(
  p_organization_id uuid,
  p_program_id      uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_program    record;
  v_talks      jsonb;
  v_reqs       jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Parameter validations
  if p_organization_id is null then
    raise exception using errcode = '22023', message = 'Organization ID is required.';
  end if;

  if p_program_id is null then
    raise exception using errcode = '22023', message = 'Program ID is required.';
  end if;

  -- 3. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 4. Dedicated catalog permission check
  if not private.has_permission('formation.catalog.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view the formation curriculum catalog.';
  end if;

  -- 5. Retrieve program (must be global or belong to caller organization)
  select
    p.id, p.organization_id, p.code, p.title, p.edition,
    p.program_category, p.program_type, p.description,
    p.sequence_order, p.is_active, p.effective_from, p.effective_to,
    p.source_document, p.source_url, p.source_verified_at
  into v_program
  from public.formation_programs p
  where p.id = p_program_id
    and (p.organization_id is null or p.organization_id = p_organization_id);

  if not found then
    raise exception using errcode = 'P0002', message = 'Formation program not found or not accessible.';
  end if;

  -- 6. Retrieve talks
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'talk_code', t.talk_code,
      'title', t.title,
      'session_label', t.session_label,
      'sequence_order', t.sequence_order,
      'description', t.description,
      'is_required', t.is_required,
      'is_active', t.is_active
    )
    order by t.sequence_order asc
  ), '[]'::jsonb)
  into v_talks
  from public.formation_talks t
  where t.program_id = p_program_id;

  -- 7. Retrieve requirements
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'target_audience', r.target_audience,
      'is_mandatory', r.is_mandatory,
      'timing_norm', r.timing_norm,
      'notes', r.notes,
      'valid_from', r.valid_from,
      'valid_to', r.valid_to,
      'is_active', r.is_active
    )
    order by r.is_mandatory desc, r.target_audience asc
  ), '[]'::jsonb)
  into v_reqs
  from public.formation_program_requirements r
  where r.program_id = p_program_id;

  -- 8. Return structured detail payload
  return jsonb_build_object(
    'id', v_program.id,
    'organization_id', v_program.organization_id,
    'code', v_program.code,
    'title', v_program.title,
    'edition', v_program.edition,
    'program_category', v_program.program_category,
    'program_type', v_program.program_type,
    'description', v_program.description,
    'sequence_order', v_program.sequence_order,
    'is_active', v_program.is_active,
    'effective_from', v_program.effective_from,
    'effective_to', v_program.effective_to,
    'source_document', v_program.source_document,
    'source_url', v_program.source_url,
    'source_verified_at', v_program.source_verified_at,
    'talk_count', jsonb_array_length(v_talks),
    'requirement_count', jsonb_array_length(v_reqs),
    'talks', v_talks,
    'requirements', v_reqs
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 3. Execution Privileges Configuration
-- -----------------------------------------------------------------------------

revoke all on function public.get_formation_catalog(uuid, text, boolean) from public;
grant execute on function public.get_formation_catalog(uuid, text, boolean) to authenticated;

revoke all on function public.get_formation_program(uuid, uuid) from public;
grant execute on function public.get_formation_program(uuid, uuid) to authenticated;

-- =============================================================================
-- Migration 97: Formal Pastoral Formation Catalog Read API Corrections
-- =============================================================================
-- Description:
-- Replaces public.get_formation_catalog to resolve a PostgreSQL execution
-- error (SQLSTATE 42803: aggregate function calls cannot be nested).
-- Pre-calculates talk_count and requirement_count using a Common Table Expression
-- (CTE) prior to jsonb_agg serialization, preserving the exact return contract,
-- search_path hardening, permission checks, and organization isolation invariants.
-- =============================================================================

create or replace function public.get_formation_catalog(
  p_organization_id   uuid,
  p_program_category  text default null,
  p_include_inactive  boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
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

  -- 6. Query programs with CTE to prevent nested aggregates
  with program_summaries as (
    select
      p.id,
      p.organization_id,
      p.code,
      p.title,
      p.edition,
      p.program_category,
      p.program_type,
      p.description,
      p.sequence_order,
      p.is_active,
      p.effective_from,
      p.effective_to,
      p.source_document,
      p.source_url,
      p.source_verified_at,
      count(distinct t.id) as talk_count,
      count(distinct r.id) as requirement_count
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
      p.source_document, p.source_url, p.source_verified_at
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'organization_id', s.organization_id,
      'code', s.code,
      'title', s.title,
      'edition', s.edition,
      'program_category', s.program_category,
      'program_type', s.program_type,
      'description', s.description,
      'sequence_order', s.sequence_order,
      'is_active', s.is_active,
      'effective_from', s.effective_from,
      'effective_to', s.effective_to,
      'source_document', s.source_document,
      'source_url', s.source_url,
      'source_verified_at', s.source_verified_at,
      'talk_count', s.talk_count,
      'requirement_count', s.requirement_count
    )
    order by s.sequence_order nulls last, s.title asc, s.code asc
  ), '[]'::jsonb)
  into v_result
  from program_summaries s;

  return v_result;
end;
$$;

comment on function public.get_formation_catalog(uuid, text, boolean) is
  'Retrieves the canonical formation curriculum catalog accessible to the caller in the specified organization. Uses CTE aggregation to deliver performant summary metadata with talk and requirement counts.';

-- Affirm execute privileges
revoke all on function public.get_formation_catalog(uuid, text, boolean) from public;
grant execute on function public.get_formation_catalog(uuid, text, boolean) to authenticated;

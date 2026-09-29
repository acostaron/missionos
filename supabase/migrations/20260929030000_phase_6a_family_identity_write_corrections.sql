-- =============================================================================
-- Migration: 20260929030000_phase_6a_family_identity_write_corrections.sql
-- Phase:     Phase 6A-3A — Family Identity Write Corrections
--
-- Summary:
--   Updates public.get_member_families to ensure that only current/usable families
--   are returned for a member's active family card:
--     - families.family_status NOT IN ('archived', 'ended')
--     - (families.ended_on IS NULL OR families.ended_on > current_date)
--
--   Preserves historical access via public.get_family_profile for authorized callers.
--   Preserves active family_members rows without mutating historical relational data.
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

  -- Step 5: Return active family memberships in current/usable families
  -- Excludes archived and ended families from the current-family card.
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
    and f.family_status not in ('archived', 'ended')
    and (
      f.ended_on is null
      or f.ended_on > current_date
    )
  order by f.family_name asc, fm.effective_from asc nulls last;
end;
$$;

revoke execute on function public.get_member_families(uuid, uuid) from public;
revoke execute on function public.get_member_families(uuid, uuid) from anon;
grant  execute on function public.get_member_families(uuid, uuid) to authenticated;
grant  execute on function public.get_member_families(uuid, uuid) to service_role;

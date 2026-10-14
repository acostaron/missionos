-- =============================================================================
-- Migration: 20261010066000_member_photo_paths_batch.sql
-- MissionOS Pass 8.3C (written by Claude, 2026-10-14)
-- Member Directory shows each member's photo instead of initials. One call per page of results:
-- returns the photo path only for members the caller may view (members.records.view in scope);
-- others, and members without a photo, are simply left out. At most 100 ids per call.
-- =============================================================================
create or replace function public.get_member_photo_paths(p_organization_id uuid, p_member_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if p_member_ids is null or cardinality(p_member_ids) = 0 then
    return '[]'::jsonb;
  end if;
  if cardinality(p_member_ids) > 100 then
    raise exception using errcode = '22023', message = 'At most 100 members per request.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object('member_id', m.id, 'photo_path', m.profile_photo_storage_path))
    from public.members m
    where m.organization_id = p_organization_id
      and m.id = any(p_member_ids)
      and m.profile_photo_storage_path is not null
      and private.can_access_member('members.records.view', p_organization_id, m.id)
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.get_member_photo_paths(uuid, uuid[]) from public, anon;
grant execute on function public.get_member_photo_paths(uuid, uuid[]) to authenticated;

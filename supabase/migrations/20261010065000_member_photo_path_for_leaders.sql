-- =============================================================================
-- Migration: 20261010065000_member_photo_path_for_leaders.sql
-- MissionOS Pass 8.3A (written by Claude, 2026-10-14)
-- Leaders who may view a member's record can read that member's current photo path, so the
-- "Photo & ID card" section on the member page shows the existing photo (the path is only a
-- storage key; the image itself is still protected by the member-photos storage policies).
-- =============================================================================
create or replace function public.get_member_photo_path(p_organization_id uuid, p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_path text;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if not private.can_access_member('members.records.view', p_organization_id, p_member_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view this member.';
  end if;

  select m.profile_photo_storage_path into v_path
  from public.members m
  where m.id = p_member_id and m.organization_id = p_organization_id;

  return jsonb_build_object('member_id', p_member_id, 'photo_path', v_path);
end;
$$;
revoke all on function public.get_member_photo_path(uuid, uuid) from public, anon;
grant execute on function public.get_member_photo_path(uuid, uuid) to authenticated;

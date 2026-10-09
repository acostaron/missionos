-- =============================================================================
-- Migration: 20261002440000_my_pending_account_invitations.sql
-- Description: Self-only authenticated read RPC for pending organization invitations.
--              public.get_my_pending_account_invitations()
-- =============================================================================

create or replace function public.get_my_pending_account_invitations()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid := private.current_profile_id();
  v_result jsonb;
begin
  -- 1. Identity & Profile authentication
  if v_auth_user_id is null or v_profile_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- 2. Query pending invitations owned strictly by caller
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'invitation_id', i.id,
        'organization_id', i.organization_id,
        'organization_name', o.name,
        'invitation_status', i.invitation_status,
        'invited_at', i.invited_at,
        'expires_at', i.expires_at
      )
      order by i.invited_at asc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.member_account_invitations i
  join public.organizations o on o.id = i.organization_id
  where (i.profile_id = v_profile_id or i.auth_user_id = v_auth_user_id)
    and (i.profile_id is null or i.profile_id = v_profile_id)
    and (i.auth_user_id is null or i.auth_user_id = v_auth_user_id)
    and i.invitation_status in ('sent', 'existing_account_invitation_pending')
    and (i.expires_at is null or i.expires_at > now());

  return jsonb_build_object('invitations', v_result);
end;
$$;

revoke all on function public.get_my_pending_account_invitations() from public;
grant execute on function public.get_my_pending_account_invitations() to authenticated;
grant execute on function public.get_my_pending_account_invitations() to service_role;

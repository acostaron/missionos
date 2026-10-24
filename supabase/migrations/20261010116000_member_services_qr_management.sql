-- Migration 185: 20261010116000_member_services_qr_management.sql
-- Goal: Pass 9.45: Admin + Member Services Controlled QR Replacement
--
-- 1. Create app_role 'member_services_coordinator' if genuinely absent.
-- 2. Grant 'members.qr.manage' to 'organization_administrator' and 'member_services_coordinator'.
-- 3. Update public.reissue_member_card authorization:
--    - Requires members.qr.manage and can_access_member('members.qr.manage', ...).
--    - Removes self-service bypass and members.records.update fallback.
--    - Preserves function signature, token generation, invalidation, audit, return contract.

-- 1. Create member_services_coordinator app role if genuinely absent
insert into public.app_roles (
  code,
  name,
  description,
  role_category,
  risk_level,
  requires_scope,
  requires_approval,
  is_system_role,
  is_assignable,
  is_active,
  display_order,
  organization_id
)
select
  'member_services_coordinator',
  'Member Services Coordinator',
  'Member Services coordination and member credential administration.',
  'administration',
  'high',
  true,
  true,
  true,
  true,
  true,
  85,
  null
where not exists (
  select 1 from public.app_roles where code = 'member_services_coordinator'
);

-- 2. Grant members.qr.manage to organization_administrator and member_services_coordinator
insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  effective_from_at,
  effective_to_at,
  approval_status,
  approved_at,
  created_at,
  updated_at
)
select
  r.organization_id,
  r.id,
  p.id,
  'allow',
  now(),
  null,
  'approved',
  now(),
  now(),
  now()
from public.app_roles r
cross join public.permissions p
where r.code in ('organization_administrator', 'member_services_coordinator')
  and p.code = 'members.qr.manage'
  and not exists (
    select 1
    from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

-- 3. Update reissue_member_card authorization
create or replace function public.reissue_member_card(
  p_organization_id uuid,
  p_member_id uuid default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_member_id uuid;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  v_member_id := coalesce(p_member_id, private.current_member_id(p_organization_id));
  if v_member_id is null then
    raise exception using errcode = '22023', message = 'Member ID is required.';
  end if;

  if not (private.has_permission('members.qr.manage', p_organization_id)
          and private.can_access_member('members.qr.manage', p_organization_id, v_member_id)) then
    raise exception using errcode = '42501', message = 'You do not have permission to replace this member''s QR.';
  end if;

  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '23502', message = 'Please give a reason for replacing the QR.';
  end if;

  if not exists (select 1 from public.members m where m.id = v_member_id and m.organization_id = p_organization_id
                 and m.record_status = 'active') then
    raise exception using errcode = '22023', message = 'Only active members can have an ID card.';
  end if;

  perform private.issue_member_qr(p_organization_id, v_member_id, v_actor, btrim(p_reason));
  return private.member_card_json(p_organization_id, v_member_id);
end;
$$;

revoke all on function public.reissue_member_card(uuid, uuid, text) from public, anon;
grant execute on function public.reissue_member_card(uuid, uuid, text) to authenticated;

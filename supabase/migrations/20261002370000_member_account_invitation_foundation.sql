-- =============================================================================
-- Migration: 20261002370000_member_account_invitation_foundation.sql
-- Description: Member account invitation foundation, part 1 of 2.
--              1. Adds the narrow members.accounts.provision permission and
--                 grants it ONLY to the system organization_administrator role.
--                 Does not grant to member or any servant leader roles.
--              2. Creates the dedicated public.member_account_invitations table
--                 to explicitly bind organization_id, member_id, email, and
--                 future auth/profile identity with clear lifecycle statuses.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Permission Registration
-- ---------------------------------------------------------------------------
insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
)
values (
  'members.accounts.provision',
  'Provision member accounts',
  'Allows authorized organization administrators to initiate member account invitations and prepare invited organization memberships for active members.',
  'members',
  'provision',
  'organization',
  'standard',
  false,
  false,
  true
)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  domain_code = excluded.domain_code,
  action_code = excluded.action_code,
  scope_type = excluded.scope_type,
  is_active = excluded.is_active;

-- ---------------------------------------------------------------------------
-- 2. Role Permission Mapping: organization_administrator ONLY
-- ---------------------------------------------------------------------------
insert into public.role_permissions (
  organization_id, app_role_id, permission_id, permission_effect,
  effective_from_at, effective_to_at, approval_status, approved_at,
  created_at, updated_at
)
select
  r.organization_id, r.id, p.id, 'allow',
  now(), null, 'approved', now(), now(), now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and r.is_system_role
  and p.code = 'members.accounts.provision'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

-- ---------------------------------------------------------------------------
-- 3. Dedicated Member Account Invitations Table
-- ---------------------------------------------------------------------------
create table if not exists public.member_account_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  email text not null,
  normalized_email text not null,
  auth_user_id uuid references auth.users(id) on delete set null,
  profile_id uuid references public.profiles(id) on delete set null,
  invitation_status text not null default 'pending',
  invited_by_profile_id uuid not null references public.profiles(id),
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by_profile_id uuid references public.profiles(id),
  expires_at timestamptz,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_member_account_invitations__status
    check (invitation_status in ('pending', 'sent', 'accepted', 'cancelled', 'expired', 'failed')),
  constraint ck_member_account_invitations__email_nonempty
    check (btrim(email) <> ''),
  constraint ck_member_account_invitations__normalized_email_match
    check (normalized_email = lower(btrim(email)))
);

-- Partial unique indexes: at most one active (pending or sent) invitation per member in an organization
create unique index if not exists ux_member_account_invitations_active_member
  on public.member_account_invitations (organization_id, member_id)
  where invitation_status in ('pending', 'sent');

-- Partial unique index: at most one active (pending or sent) invitation per normalized email in an organization
create unique index if not exists ux_member_account_invitations_active_email
  on public.member_account_invitations (organization_id, normalized_email)
  where invitation_status in ('pending', 'sent');

create index if not exists ix_member_account_invitations_org_status
  on public.member_account_invitations (organization_id, invitation_status);

create index if not exists ix_member_account_invitations_profile
  on public.member_account_invitations (profile_id);

-- ---------------------------------------------------------------------------
-- 4. Row Level Security & Grants
-- ---------------------------------------------------------------------------
alter table public.member_account_invitations enable row level security;

-- Admin select policy
create policy member_account_invitations_admin_select
  on public.member_account_invitations
  for select
  to authenticated
  using (
    private.has_permission('members.accounts.provision', organization_id)
    or private.has_permission('security.profile_member_links.manage', organization_id)
  );

-- Self select policy (when target profile is set)
create policy member_account_invitations_self_select
  on public.member_account_invitations
  for select
  to authenticated
  using (
    profile_id = auth.uid()
  );

grant select on public.member_account_invitations to authenticated;
grant all on public.member_account_invitations to service_role;

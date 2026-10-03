-- =============================================================================
-- Migration: 20261002070000_phase_6b_delegated_servant_leader_access.sql
-- Phase:     Phase 6B-9 — Delegated Servant Leader Access & Scope-Based Operations
--
-- Objective:
--   Allow formally appointed servant leaders to use MissionOS safely within their
--   authorized pastoral scope.
--
-- Canonical Offices:
--   - Household Servant Leader (household_servant_leader -> household_servant_leader_access on Household node)
--   - Unit Servant Leader (unit_servant_leader -> unit_servant_leader_access on Unit node with descendants)
--   - Chapter Servant Leader (chapter_servant_leader -> chapter_servant_leader_access on Chapter node with descendants)
--   - Area Servant Leader (area_servant_leader -> area_servant_leader_access on Area node with descendants)
--
-- Cardinal Rules:
--   1. leadership_assignments != application authorization.
--      Leadership assignment defines formal pastoral responsibility; application authorization
--      requires explicit app role + permission + scope grant.
--   2. Both conditions must hold for delegated operations:
--      A. Explicit application authorization (app role + scope grant)
--      AND
--      B. Corresponding current active servant-leader assignment.
--   3. Couples Rule: Wife/co-leader does NOT receive automated app access.
--   4. Fraternal Rule: Rotating meeting facilitator does NOT receive app access.
--   5. Write authority is narrower than read scope:
--      Direct write authority is limited strictly to the leader's DIRECT household
--      (HSL: own Member Household; USL: Unit Household; CSL: Chapter Household; ASL: Area Household).
--   6. Household membership placement (assign/transfer/end) remains organization-administrator only.
--   7. Stale access protection: Ending/replacing leadership immediately removes effective delegated
--      authority at request-time even before cleanup.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Permissions Catalog Seed
-- =============================================================================

insert into public.permissions (
  code,
  name,
  description,
  domain_code,
  action_code,
  scope_type,
  risk_level,
  requires_access_reason,
  requires_access_logging,
  is_active
)
values
  (
    'leadership.delegated_access.manage',
    'Manage delegated servant leader access grants',
    'Grant and revoke application access for formal servant leaders.',
    'governance',
    'manage',
    'organization',
    'high',
    false,
    true,
    true
  ),
  (
    'leadership.delegated_access.view',
    'View delegated servant leader access grants',
    'View delegated access status and reconciliation review.',
    'governance',
    'view',
    'organization',
    'standard',
    false,
    false,
    true
  )
on conflict (code) do update
set
  name                    = excluded.name,
  description             = excluded.description,
  domain_code             = excluded.domain_code,
  action_code             = excluded.action_code,
  scope_type              = excluded.scope_type,
  risk_level              = excluded.risk_level,
  requires_access_reason  = excluded.requires_access_reason,
  requires_access_logging = excluded.requires_access_logging,
  is_active               = excluded.is_active;

-- Map permissions to organization_administrator
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
  r.id as app_role_id,
  p.id as permission_id,
  'allow',
  now(),
  null,
  'approved',
  now(),
  now(),
  now()
from public.app_roles r
cross join public.permissions p
where r.code = 'organization_administrator'
  and p.code in (
    'leadership.delegated_access.manage',
    'leadership.delegated_access.view'
  )
  and not exists (
    select 1
    from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

-- =============================================================================
-- SECTION 2: Dedicated Delegated Application Roles Seed
-- =============================================================================

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
values
  (
    'household_servant_leader_access',
    'Household Servant Leader Access',
    'Delegated application access for appointed Household Servant Leaders, scoped to their own Member Household.',
    'pastoral_leadership',
    'standard',
    true,
    true,
    true,
    true,
    true,
    10,
    null
  ),
  (
    'unit_servant_leader_access',
    'Unit Servant Leader Access',
    'Delegated application access for appointed Unit Servant Leaders, scoped to their Unit subtree with direct operations on the Unit Household.',
    'pastoral_leadership',
    'standard',
    true,
    true,
    true,
    true,
    true,
    11,
    null
  ),
  (
    'chapter_servant_leader_access',
    'Chapter Servant Leader Access',
    'Delegated application access for appointed Chapter Servant Leaders, scoped to their Chapter subtree with direct operations on the Chapter Household.',
    'pastoral_leadership',
    'standard',
    true,
    true,
    true,
    true,
    true,
    12,
    null
  ),
  (
    'area_servant_leader_access',
    'Area Servant Leader Access',
    'Delegated application access for appointed Area Servant Leaders, scoped to their Area subtree with direct operations on the Area Household.',
    'pastoral_leadership',
    'standard',
    true,
    true,
    true,
    true,
    true,
    13,
    null
  )
on conflict (code) where (organization_id is null) do update
set
  name              = excluded.name,
  description       = excluded.description,
  role_category     = excluded.role_category,
  risk_level        = excluded.risk_level,
  requires_scope    = excluded.requires_scope,
  requires_approval = excluded.requires_approval,
  is_system_role    = excluded.is_system_role,
  is_assignable     = excluded.is_assignable,
  is_active         = excluded.is_active,
  display_order     = excluded.display_order;

-- =============================================================================
-- SECTION 3: Role-Permissions Mapping for Delegated Roles
-- Delegated roles receive conservative, privacy-minimized permissions:
--   Read: households.records.view, members.households.view, households.meetings.view,
--         leadership.pastoral_dashboard.view, governance.leadership.view
--   Direct Write: households.meetings.manage, households.attendance.record
-- Explicitly excluded: members.records.view, contacts, addresses, notes, member placement, admin
-- =============================================================================

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
  r.id as app_role_id,
  p.id as permission_id,
  'allow',
  now(),
  null,
  'approved',
  now(),
  now(),
  now()
from public.app_roles r
cross join public.permissions p
where r.code in (
    'household_servant_leader_access',
    'unit_servant_leader_access',
    'chapter_servant_leader_access',
    'area_servant_leader_access'
  )
  and p.code in (
    'households.records.view',
    'members.households.view',
    'households.meetings.view',
    'leadership.pastoral_dashboard.view',
    'governance.leadership.view',
    'households.meetings.manage',
    'households.attendance.record'
  )
  and not exists (
    select 1
    from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

-- =============================================================================
-- SECTION 4: Table public.servant_leader_access_grants
-- Captures explicit provenance and lifecycle linkage between leadership appointment
-- and delegated software authorization.
-- =============================================================================

create table if not exists public.servant_leader_access_grants (
  id                           uuid primary key default gen_random_uuid(),
  organization_id              uuid not null references public.organizations(id) on update cascade on delete cascade,
  profile_id                   uuid not null references public.profiles(id) on update cascade on delete cascade,
  member_id                    uuid not null references public.members(id) on update cascade on delete cascade,
  leadership_assignment_id     uuid not null references public.leadership_assignments(id) on update cascade on delete cascade,
  app_role_id                  uuid not null references public.app_roles(id) on update cascade on delete cascade,
  profile_role_assignment_id   uuid references public.profile_role_assignments(id) on update cascade on delete set null,
  profile_scope_assignment_id  uuid references public.profile_scope_assignments(id) on update cascade on delete set null,
  governance_node_id           uuid not null references public.governance_nodes(id) on update cascade on delete cascade,
  access_status                text not null check (access_status in ('active', 'revoked', 'expired')) default 'active',
  granted_at                   timestamptz not null default now(),
  granted_by_profile_id        uuid references public.profiles(id) on update cascade on delete set null,
  revoked_at                   timestamptz,
  revoked_by_profile_id        uuid references public.profiles(id) on update cascade on delete set null,
  revocation_reason            text,
  effective_from               date not null default current_date,
  effective_to                 date,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now()
);

comment on table public.servant_leader_access_grants is
  'Tracks explicit delegated application access grants linked to formal servant leader appointments.';

-- Unique active grant constraint: only one active access grant per leadership appointment
create unique index if not exists ux_servant_leader_access_grants__active
  on public.servant_leader_access_grants (organization_id, leadership_assignment_id)
  where (access_status = 'active');

create index if not exists ix_servant_leader_access_grants__profile
  on public.servant_leader_access_grants (organization_id, profile_id, access_status);

create index if not exists ix_servant_leader_access_grants__member
  on public.servant_leader_access_grants (organization_id, member_id);

create index if not exists ix_servant_leader_access_grants__node
  on public.servant_leader_access_grants (organization_id, governance_node_id);

alter table public.servant_leader_access_grants enable row level security;

create policy servant_leader_access_grants__select
  on public.servant_leader_access_grants
  for select
  to authenticated
  using (
    private.has_organization_access(organization_id)
    and (
      private.has_permission('leadership.delegated_access.view', organization_id)
      or private.has_permission('leadership.delegated_access.manage', organization_id)
      or profile_id = auth.uid()
    )
  );

-- =============================================================================
-- SECTION 5: Private Helpers for Organization Administration & Direct Responsibility
-- =============================================================================

create or replace function private.is_organization_administrator(
  p_profile_id      uuid,
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
  select exists (
    select 1
    from public.profile_role_assignments pra
    join public.app_roles ar on ar.id = pra.app_role_id
    where pra.profile_id = p_profile_id
      and pra.organization_id = p_organization_id
      and pra.assignment_status = 'active'
      and pra.effective_from_at <= now()
      and (pra.effective_to_at is null or pra.effective_to_at > now())
      and ar.code = 'organization_administrator'
  );
$$;

comment on function private.is_organization_administrator(uuid, uuid) is
  'Returns true if the caller holds an active organization_administrator role in the given organization.';

revoke execute on function private.is_organization_administrator(uuid, uuid) from public, anon;
grant  execute on function private.is_organization_administrator(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Helper: private.profile_has_direct_servant_leader_responsibility
-- Evaluates whether p_profile_id has DIRECT operational write authority over
-- p_household_node_id.
-- Checks:
--   1. Authoritative profile-member link (verified, self, is_primary)
--   2. Active household node and its pastoral_level
--   3. Fraternal household -> returns false (no permanent servant leader)
--   4. Expected canonical role and expected governance target node:
--        member   -> household_servant_leader on household node directly
--        unit     -> unit_servant_leader on parent Unit node
--        chapter  -> chapter_servant_leader on parent Chapter node
--        area     -> area_servant_leader on parent Area node
--   5. Active leadership assignment (assignment_status = 'active', within effective window)
--   6. Active delegated access grant (access_status = 'active', within effective window)
-- -----------------------------------------------------------------------------
create or replace function private.profile_has_direct_servant_leader_responsibility(
  p_profile_id         uuid,
  p_organization_id    uuid,
  p_household_node_id  uuid,
  p_required_role_code text default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_member_id                uuid;
  v_pastoral_level           text;
  v_parent_node_id           uuid;
  v_expected_role            text;
  v_expected_gov_node        uuid;
  v_leadership_assignment_id uuid;
begin
  if p_profile_id is null or p_organization_id is null or p_household_node_id is null then
    return false;
  end if;

  -- 1. Authoritative profile-member link
  select pml.member_id
  into v_member_id
  from public.profile_member_links pml
  where pml.profile_id = p_profile_id
    and pml.organization_id = p_organization_id
    and pml.link_type = 'self'
    and pml.link_status = 'verified'
    and pml.is_primary = true
    and pml.ended_at is null;

  if v_member_id is null then
    return false;
  end if;

  -- 2. Household existence and pastoral level
  select h.pastoral_level, p_rel.parent_node_id
  into v_pastoral_level, v_parent_node_id
  from public.households h
  join public.governance_nodes gn
    on gn.id = h.id
   and gn.organization_id = h.organization_id
  left join lateral (
    select gnr.parent_node_id
    from public.governance_node_relationships gnr
    where gnr.organization_id = p_organization_id
      and gnr.child_node_id = h.id
      and gnr.relationship_type = 'primary_parent'
      and gnr.relationship_status = 'active'
      and gnr.effective_from <= current_date
      and (gnr.effective_to is null or gnr.effective_to >= current_date)
    order by gnr.created_at desc
    limit 1
  ) p_rel on true
  where h.id = p_household_node_id
    and h.organization_id = p_organization_id
    and gn.lifecycle_status = 'active';

  if v_pastoral_level is null then
    return false;
  end if;

  -- 3. Fraternal households have no permanent servant leader
  if v_pastoral_level = 'fraternal' then
    return false;
  end if;

  -- 4. Map expected role and target governance node
  case v_pastoral_level
    when 'member' then
      v_expected_role := 'household_servant_leader';
      v_expected_gov_node := p_household_node_id;
    when 'unit' then
      v_expected_role := 'unit_servant_leader';
      v_expected_gov_node := v_parent_node_id;
    when 'chapter' then
      v_expected_role := 'chapter_servant_leader';
      v_expected_gov_node := v_parent_node_id;
    when 'area' then
      v_expected_role := 'area_servant_leader';
      v_expected_gov_node := v_parent_node_id;
    else
      return false;
  end case;

  if v_expected_gov_node is null then
    return false;
  end if;

  if p_required_role_code is not null and p_required_role_code != v_expected_role then
    return false;
  end if;

  -- 5. Active leadership assignment check
  select la.id
  into v_leadership_assignment_id
  from public.leadership_assignments la
  join public.leadership_role_definitions lrd
    on lrd.id = la.leadership_role_definition_id
  where la.organization_id = p_organization_id
    and la.member_id = v_member_id
    and la.governance_node_id = v_expected_gov_node
    and lrd.code = v_expected_role
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date);

  if v_leadership_assignment_id is null then
    return false;
  end if;

  -- 6. Active delegated access grant check
  return exists (
    select 1
    from public.servant_leader_access_grants g
    where g.organization_id = p_organization_id
      and g.profile_id = p_profile_id
      and g.member_id = v_member_id
      and g.leadership_assignment_id = v_leadership_assignment_id
      and g.governance_node_id = v_expected_gov_node
      and g.access_status = 'active'
      and g.effective_from <= current_date
      and (g.effective_to is null or g.effective_to >= current_date)
  );
end;
$$;

comment on function private.profile_has_direct_servant_leader_responsibility(uuid, uuid, uuid, text) is
  'Authoritative evaluator of direct servant-leader responsibility. Requires active verified profile link, active leadership assignment, and active delegated access grant.';

revoke execute on function private.profile_has_direct_servant_leader_responsibility(uuid, uuid, uuid, text) from public, anon;
grant  execute on function private.profile_has_direct_servant_leader_responsibility(uuid, uuid, uuid, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 6: Delegated Access Management RPCs
-- =============================================================================

-- -----------------------------------------------------------------------------
-- public.grant_servant_leader_access
-- Admin-only RPC to grant delegated software access for a current servant leader.
-- -----------------------------------------------------------------------------
create or replace function public.grant_servant_leader_access(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid,
  p_profile_id               uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_admin_profile_id   uuid;
  v_assignment         public.leadership_assignments%rowtype;
  v_role_def           public.leadership_role_definitions%rowtype;
  v_node               public.governance_nodes%rowtype;
  v_node_type          public.governance_node_types%rowtype;
  v_member             public.members%rowtype;
  v_target_profile_id  uuid;
  v_app_role_code      text;
  v_app_role           public.app_roles%rowtype;
  v_includes_desc      boolean;
  v_pra_id             uuid;
  v_psa_id             uuid;
  v_grant_id           uuid;
  v_effective_to_at    timestamptz;
  v_now                timestamptz := now();
begin
  -- 1. Authentication check
  v_admin_profile_id := private.current_profile_id();
  if v_admin_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Dedicated permission check
  if not private.has_permission('leadership.delegated_access.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage delegated servant leader access.';
  end if;

  -- 4. Lock leadership assignment FOR UPDATE
  select *
  into v_assignment
  from public.leadership_assignments la
  where la.id = p_leadership_assignment_id
    and la.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership assignment not found or not accessible.';
  end if;

  -- 5. Canonical servant leader role check
  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.id = v_assignment.leadership_role_definition_id
    and lrd.organization_id = p_organization_id;

  if v_role_def.code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    raise exception using errcode = '22023',
      message = 'Delegated access can only be granted to canonical servant leader roles.';
  end if;

  -- 6. Active and current leadership assignment requirement
  if v_assignment.assignment_status != 'active' or (v_assignment.effective_to is not null and v_assignment.effective_to < current_date) then
    raise exception using errcode = '22023', message = 'Leadership assignment is not currently active.';
  end if;

  if v_assignment.effective_from > current_date then
    raise exception using errcode = '22023', message = 'Future servant-leader appointments cannot receive delegated access yet.';
  end if;

  -- 7. Validate governance node
  select gn.*
  into v_node
  from public.governance_nodes gn
  where gn.id = v_assignment.governance_node_id
    and gn.organization_id = p_organization_id;

  if not found or v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Target governance node is not active.';
  end if;

  select gnt.*
  into v_node_type
  from public.governance_node_types gnt
  where gnt.id = v_node.governance_node_type_id
    and gnt.organization_id = p_organization_id;

  -- Node type compatibility check
  case v_role_def.code
    when 'household_servant_leader' then
      if v_node_type.code != 'household' then
        raise exception using errcode = '22023', message = 'Household Servant Leader must target a Household node.';
      end if;
      v_app_role_code := 'household_servant_leader_access';
      v_includes_desc := false;
    when 'unit_servant_leader' then
      if v_node_type.code != 'unit' then
        raise exception using errcode = '22023', message = 'Unit Servant Leader must target a Unit node.';
      end if;
      v_app_role_code := 'unit_servant_leader_access';
      v_includes_desc := true;
    when 'chapter_servant_leader' then
      if v_node_type.code != 'chapter' then
        raise exception using errcode = '22023', message = 'Chapter Servant Leader must target a Chapter node.';
      end if;
      v_app_role_code := 'chapter_servant_leader_access';
      v_includes_desc := true;
    when 'area_servant_leader' then
      if v_node_type.code != 'area_state' then
        raise exception using errcode = '22023', message = 'Area Servant Leader must target an Area/State node.';
      end if;
      v_app_role_code := 'area_servant_leader_access';
      v_includes_desc := true;
  end case;

  -- 8. Resolve leader member
  select *
  into v_member
  from public.members m
  where m.id = v_assignment.member_id
    and m.organization_id = p_organization_id;

  if not found or v_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Servant leader member record is not active.';
  end if;

  -- 9. Resolve verified linked application profile
  if p_profile_id is not null then
    select pml.profile_id
    into v_target_profile_id
    from public.profile_member_links pml
    where pml.organization_id = p_organization_id
      and pml.member_id = v_assignment.member_id
      and pml.profile_id = p_profile_id
      and pml.link_type = 'self'
      and pml.link_status = 'verified'
      and pml.is_primary = true
      and pml.ended_at is null;

    if not found then
      raise exception using errcode = '22023',
        message = 'Requested profile does not hold a verified primary link to this servant leader.';
    end if;
  else
    select pml.profile_id
    into v_target_profile_id
    from public.profile_member_links pml
    where pml.organization_id = p_organization_id
      and pml.member_id = v_assignment.member_id
      and pml.link_type = 'self'
      and pml.link_status = 'verified'
      and pml.is_primary = true
      and pml.ended_at is null
    order by pml.verified_at desc
    limit 1;

    if not found then
      raise exception using errcode = '22023',
        message = 'No verified application profile is linked to this servant leader.';
    end if;
  end if;

  -- Profile must be active
  if not exists (
    select 1 from public.profiles
    where id = v_target_profile_id and account_status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'The linked application profile is not active.';
  end if;

  -- 10. Check if active grant already exists for this leadership assignment
  if exists (
    select 1
    from public.servant_leader_access_grants g
    where g.organization_id = p_organization_id
      and g.leadership_assignment_id = p_leadership_assignment_id
      and g.access_status = 'active'
  ) then
    raise exception using errcode = '22023',
      message = 'An active servant leader access grant already exists for this leadership assignment.';
  end if;

  -- 11. Resolve target app role
  select *
  into v_app_role
  from public.app_roles ar
  where ar.code = v_app_role_code
    and ar.is_active = true
    and (ar.organization_id is null or ar.organization_id = p_organization_id)
  limit 1;

  if not found then
    raise exception using errcode = 'P0002', message = 'Delegated application role "' || v_app_role_code || '" not found.';
  end if;

  if v_assignment.effective_to is not null then
    v_effective_to_at := (v_assignment.effective_to::text || ' 23:59:59.999Z')::timestamptz;
  else
    v_effective_to_at := null;
  end if;

  -- 12. Create profile_role_assignment (source_type = 'leadership_assignment')
  v_pra_id := gen_random_uuid();
  insert into public.profile_role_assignments (
    id,
    organization_id,
    profile_id,
    app_role_id,
    source_type,
    leadership_assignment_id,
    assignment_status,
    effective_from_at,
    effective_to_at,
    proposed_at,
    proposed_by_profile_id,
    approved_at,
    approved_by_profile_id,
    activated_at,
    assignment_summary,
    created_at,
    updated_at,
    updated_by_profile_id
  )
  values (
    v_pra_id,
    p_organization_id,
    v_target_profile_id,
    v_app_role.id,
    'leadership_assignment',
    v_assignment.id,
    'active',
    v_now,
    v_effective_to_at,
    v_now,
    v_admin_profile_id,
    v_now,
    v_admin_profile_id,
    v_now,
    'Delegated servant leader access grant for ' || v_role_def.name,
    v_now,
    v_now,
    v_admin_profile_id
  );

  -- 13. Create profile_scope_assignment
  v_psa_id := gen_random_uuid();
  insert into public.profile_scope_assignments (
    id,
    organization_id,
    profile_role_assignment_id,
    scope_type,
    governance_node_id,
    scope_effect,
    includes_descendants,
    assignment_status,
    effective_from_at,
    effective_to_at,
    assigned_at,
    assigned_by_profile_id,
    assignment_summary,
    created_at,
    updated_at,
    updated_by_profile_id
  )
  values (
    v_psa_id,
    p_organization_id,
    v_pra_id,
    'governance_node',
    v_assignment.governance_node_id,
    'include',
    v_includes_desc,
    'active',
    v_now,
    v_effective_to_at,
    v_now,
    v_admin_profile_id,
    'Delegated scope for ' || v_role_def.name,
    v_now,
    v_now,
    v_admin_profile_id
  );

  -- 14. Create servant_leader_access_grants record
  v_grant_id := gen_random_uuid();
  insert into public.servant_leader_access_grants (
    id,
    organization_id,
    profile_id,
    member_id,
    leadership_assignment_id,
    app_role_id,
    profile_role_assignment_id,
    profile_scope_assignment_id,
    governance_node_id,
    access_status,
    granted_at,
    granted_by_profile_id,
    effective_from,
    effective_to,
    created_at,
    updated_at
  )
  values (
    v_grant_id,
    p_organization_id,
    v_target_profile_id,
    v_assignment.member_id,
    v_assignment.id,
    v_app_role.id,
    v_pra_id,
    v_psa_id,
    v_assignment.governance_node_id,
    'active',
    v_now,
    v_admin_profile_id,
    current_date,
    v_assignment.effective_to,
    v_now,
    v_now
  );

  -- 15. Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader_access.granted',
    p_event_category   => 'governance',
    p_actor_profile_id => v_admin_profile_id,
    p_entity_type      => 'servant_leader_access_grant',
    p_entity_id        => v_grant_id,
    p_action           => 'grant',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'grant_id',                 v_grant_id,
      'leadership_assignment_id', v_assignment.id,
      'profile_id',               v_target_profile_id,
      'member_id',                v_assignment.member_id,
      'role_code',                v_role_def.code,
      'app_role_code',            v_app_role_code,
      'governance_node_id',       v_assignment.governance_node_id,
      'governance_node_name',     v_node.name
    )
  );

  return jsonb_build_object(
    'grant_id',                 v_grant_id,
    'leadership_assignment_id', v_assignment.id,
    'profile_id',               v_target_profile_id,
    'member_id',                v_assignment.member_id,
    'member_name',              v_member.display_name,
    'role_code',                v_role_def.code,
    'app_role_code',            v_app_role_code,
    'governance_node_id',       v_assignment.governance_node_id,
    'governance_node_name',     v_node.name,
    'access_status',            'active',
    'granted_at',               v_now
  );
end;
$$;

comment on function public.grant_servant_leader_access(uuid, uuid, uuid) is
  'Grants explicit delegated application access for an active servant leader appointment. Requires organization administrator privilege.';

revoke execute on function public.grant_servant_leader_access(uuid, uuid, uuid) from public, anon;
grant  execute on function public.grant_servant_leader_access(uuid, uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- public.revoke_servant_leader_access
-- Admin-only RPC to revoke delegated application access for a servant leader.
-- -----------------------------------------------------------------------------
create or replace function public.revoke_servant_leader_access(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid default null,
  p_grant_id                 uuid default null,
  p_reason                   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_admin_profile_id  uuid;
  v_grant             public.servant_leader_access_grants%rowtype;
  v_reason            text;
  v_now               timestamptz := now();
begin
  -- 1. Authentication check
  v_admin_profile_id := private.current_profile_id();
  if v_admin_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Dedicated permission check
  if not private.has_permission('leadership.delegated_access.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to revoke delegated servant leader access.';
  end if;

  v_reason := trim(coalesce(p_reason, 'Delegated access revoked by administrator'));

  -- 4. Locate active grant
  if p_grant_id is not null then
    select *
    into v_grant
    from public.servant_leader_access_grants g
    where g.id = p_grant_id
      and g.organization_id = p_organization_id
    for update;
  elsif p_leadership_assignment_id is not null then
    select *
    into v_grant
    from public.servant_leader_access_grants g
    where g.leadership_assignment_id = p_leadership_assignment_id
      and g.organization_id = p_organization_id
      and g.access_status = 'active'
    for update;
  else
    raise exception using errcode = '22023',
      message = 'Either p_grant_id or p_leadership_assignment_id must be provided.';
  end if;

  if not found then
    raise exception using errcode = 'P0002', message = 'Active servant leader access grant not found.';
  end if;

  if v_grant.access_status != 'active' then
    raise exception using errcode = '22023', message = 'This access grant is already ' || v_grant.access_status || '.';
  end if;

  -- 5. Revoke grant record
  update public.servant_leader_access_grants
  set
    access_status         = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_admin_profile_id,
    revocation_reason     = v_reason,
    updated_at            = v_now
  where id = v_grant.id;

  -- 6. End associated profile role assignment
  if v_grant.profile_role_assignment_id is not null then
    update public.profile_role_assignments
    set
      assignment_status     = 'ended',
      ended_at              = v_now,
      ended_by_profile_id   = v_admin_profile_id,
      ending_reason         = v_reason,
      updated_at            = v_now,
      updated_by_profile_id = v_admin_profile_id
    where id = v_grant.profile_role_assignment_id
      and organization_id = p_organization_id
      and assignment_status = 'active';
  end if;

  -- 7. End associated profile scope assignment
  if v_grant.profile_scope_assignment_id is not null then
    update public.profile_scope_assignments
    set
      assignment_status     = 'ended',
      revoked_at            = v_now,
      revoked_by_profile_id = v_admin_profile_id,
      revocation_reason     = v_reason,
      updated_at            = v_now,
      updated_by_profile_id = v_admin_profile_id
    where id = v_grant.profile_scope_assignment_id
      and organization_id = p_organization_id
      and assignment_status = 'active';
  end if;

  -- 8. Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader_access.revoked',
    p_event_category   => 'governance',
    p_actor_profile_id => v_admin_profile_id,
    p_entity_type      => 'servant_leader_access_grant',
    p_entity_id        => v_grant.id,
    p_action           => 'revoke',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'grant_id',                 v_grant.id,
      'leadership_assignment_id', v_grant.leadership_assignment_id,
      'profile_id',               v_grant.profile_id,
      'member_id',                v_grant.member_id,
      'reason',                   v_reason
    )
  );

  return jsonb_build_object(
    'grant_id',                 v_grant.id,
    'leadership_assignment_id', v_grant.leadership_assignment_id,
    'profile_id',               v_grant.profile_id,
    'member_id',                v_grant.member_id,
    'access_status',            'revoked',
    'revoked_at',               v_now,
    'reason',                   v_reason
  );
end;
$$;

comment on function public.revoke_servant_leader_access(uuid, uuid, uuid, text) is
  'Revokes an active delegated servant leader access grant and its associated role and scope assignments.';

revoke execute on function public.revoke_servant_leader_access(uuid, uuid, uuid, text) from public, anon;
grant  execute on function public.revoke_servant_leader_access(uuid, uuid, uuid, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- public.get_servant_leader_access_status
-- Returns factual access status, linked profile, and eligibility for a leadership assignment.
-- -----------------------------------------------------------------------------
create or replace function public.get_servant_leader_access_status(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id         uuid;
  v_assignment         public.leadership_assignments%rowtype;
  v_role_def           public.leadership_role_definitions%rowtype;
  v_node               public.governance_nodes%rowtype;
  v_member             public.members%rowtype;
  v_linked_profile_id  uuid;
  v_linked_profile     public.profiles%rowtype;
  v_grant              public.servant_leader_access_grants%rowtype;
  v_app_role           public.app_roles%rowtype;
  v_eligibility_status text;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not (
    private.has_permission('leadership.delegated_access.view', p_organization_id)
    or private.has_permission('leadership.delegated_access.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to view delegated access status.';
  end if;

  select *
  into v_assignment
  from public.leadership_assignments la
  where la.id = p_leadership_assignment_id
    and la.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership assignment not found or not accessible.';
  end if;

  select * into v_role_def
  from public.leadership_role_definitions
  where id = v_assignment.leadership_role_definition_id;

  select * into v_node
  from public.governance_nodes
  where id = v_assignment.governance_node_id;

  select * into v_member
  from public.members
  where id = v_assignment.member_id;

  -- Find active linked profile
  select p.*
  into v_linked_profile
  from public.profile_member_links pml
  join public.profiles p on p.id = pml.profile_id
  where pml.organization_id = p_organization_id
    and pml.member_id = v_assignment.member_id
    and pml.link_type = 'self'
    and pml.link_status = 'verified'
    and pml.is_primary = true
    and pml.ended_at is null
  order by pml.verified_at desc
  limit 1;

  v_linked_profile_id := v_linked_profile.id;

  -- Find latest access grant
  select *
  into v_grant
  from public.servant_leader_access_grants g
  where g.organization_id = p_organization_id
    and g.leadership_assignment_id = p_leadership_assignment_id
  order by (g.access_status = 'active') desc, g.created_at desc
  limit 1;

  if v_grant.app_role_id is not null then
    select * into v_app_role from public.app_roles where id = v_grant.app_role_id;
  end if;

  -- Determine factual eligibility status
  if v_grant.access_status = 'active' then
    v_eligibility_status := 'already_active';
  elsif v_role_def.code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    v_eligibility_status := 'unsupported_role';
  elsif v_assignment.assignment_status != 'active' or (v_assignment.effective_to is not null and v_assignment.effective_to < current_date) then
    v_eligibility_status := 'leadership_not_current';
  elsif v_assignment.effective_from > current_date then
    v_eligibility_status := 'future_effective';
  elsif v_linked_profile_id is null then
    v_eligibility_status := 'no_linked_profile';
  elsif v_grant.access_status = 'revoked' then
    v_eligibility_status := 'eligible'; -- can be re-granted
  else
    v_eligibility_status := 'eligible';
  end if;

  return jsonb_build_object(
    'leadership_assignment_id', p_leadership_assignment_id,
    'leader_member_id',         v_assignment.member_id,
    'leader_member_name',       v_member.display_name,
    'role_code',                v_role_def.code,
    'role_name',                v_role_def.name,
    'governance_node_id',       v_assignment.governance_node_id,
    'governance_node_name',     v_node.name,
    'linked_profile_id',        v_linked_profile_id,
    'has_linked_profile',       (v_linked_profile_id is not null),
    'access_grant_id',          v_grant.id,
    'access_status',            coalesce(v_grant.access_status, 'none'),
    'eligibility_status',       v_eligibility_status,
    'app_role_code',            v_app_role.code,
    'app_role_name',            v_app_role.name,
    'granted_at',               v_grant.granted_at,
    'granted_by_profile_id',    v_grant.granted_by_profile_id,
    'revoked_at',               v_grant.revoked_at,
    'revoked_by_profile_id',    v_grant.revoked_by_profile_id,
    'revocation_reason',        v_grant.revocation_reason,
    'effective_from',           v_grant.effective_from,
    'effective_to',             v_grant.effective_to
  );
end;
$$;

comment on function public.get_servant_leader_access_status(uuid, uuid) is
  'Returns factual delegated application access status and eligibility for a given servant leader assignment.';

revoke execute on function public.get_servant_leader_access_status(uuid, uuid) from public, anon;
grant  execute on function public.get_servant_leader_access_status(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- public.search_servant_leader_access_reconciliation
-- Admin review RPC to identify anomalies between formal leadership appointments
-- and application access grants.
-- -----------------------------------------------------------------------------
create or replace function public.search_servant_leader_access_reconciliation(
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_items      jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not (
    private.has_permission('leadership.delegated_access.view', p_organization_id)
    or private.has_permission('leadership.delegated_access.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to view delegated access reconciliation.';
  end if;

  with anomalies as (
    -- 1. Active grant exists but formal leadership assignment has ended or is inactive
    select
      g.id as grant_id,
      g.leadership_assignment_id,
      g.profile_id,
      g.member_id,
      m.display_name as member_name,
      lrd.code as role_code,
      lrd.name as role_name,
      gn.id as governance_node_id,
      gn.name as governance_node_name,
      'leadership_ended_but_grant_active'::text as issue_type,
      'Grant is active but formal leadership appointment is ' || la.assignment_status as issue_description
    from public.servant_leader_access_grants g
    join public.leadership_assignments la on la.id = g.leadership_assignment_id
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join public.members m on m.id = g.member_id
    join public.governance_nodes gn on gn.id = g.governance_node_id
    where g.organization_id = p_organization_id
      and g.access_status = 'active'
      and (
        la.assignment_status != 'active'
        or (la.effective_to is not null and la.effective_to < current_date)
      )

    union all

    -- 2. Active leadership assignment exists with linked profile, but no active grant
    select
      null as grant_id,
      la.id as leadership_assignment_id,
      pml.profile_id,
      m.id as member_id,
      m.display_name as member_name,
      lrd.code as role_code,
      lrd.name as role_name,
      gn.id as governance_node_id,
      gn.name as governance_node_name,
      'leadership_active_no_grant'::text as issue_type,
      'Active servant leader appointment has linked profile but no delegated access grant' as issue_description
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join public.members m on m.id = la.member_id
    join public.governance_nodes gn on gn.id = la.governance_node_id
    join public.profile_member_links pml
      on pml.member_id = la.member_id
     and pml.organization_id = p_organization_id
     and pml.link_type = 'self'
     and pml.link_status = 'verified'
     and pml.is_primary = true
     and pml.ended_at is null
    where la.organization_id = p_organization_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader')
      and not exists (
        select 1 from public.servant_leader_access_grants g
        where g.organization_id = p_organization_id
          and g.leadership_assignment_id = la.id
          and g.access_status = 'active'
      )
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'grant_id',                 a.grant_id,
      'leadership_assignment_id', a.leadership_assignment_id,
      'profile_id',               a.profile_id,
      'member_id',                a.member_id,
      'member_name',              a.member_name,
      'role_code',                a.role_code,
      'role_name',                a.role_name,
      'governance_node_id',       a.governance_node_id,
      'governance_node_name',     a.governance_node_name,
      'issue_type',               a.issue_type,
      'issue_description',        a.issue_description
    ) order by a.role_code, a.governance_node_name
  ), '[]'::jsonb)
  into v_items
  from anomalies a;

  return jsonb_build_object(
    'organization_id', p_organization_id,
    'total_count',     jsonb_array_length(v_items),
    'items',           v_items
  );
end;
$$;

comment on function public.search_servant_leader_access_reconciliation(uuid) is
  'Identifies discrepancies between formal servant leader assignments and application access grants.';

revoke execute on function public.search_servant_leader_access_reconciliation(uuid) from public, anon;
grant  execute on function public.search_servant_leader_access_reconciliation(uuid) to authenticated, service_role;

-- =============================================================================
-- SECTION 7: Update Lifecycle RPCs to Revoke Grants Atomically
-- Updates conclude_servant_leader and replace_servant_leader to clean up
-- active delegated access grants upon conclusion/replacement.
-- =============================================================================

create or replace function public.conclude_servant_leader(
  p_organization_id          uuid,
  p_leadership_assignment_id uuid,
  p_effective_to             date default current_date,
  p_reason                   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id    uuid;
  v_effective_to  date;
  v_reason        text;
  v_assignment    public.leadership_assignments%rowtype;
  v_role_def      public.leadership_role_definitions%rowtype;
  v_node          public.governance_nodes%rowtype;
  v_member        public.members%rowtype;
  v_now           timestamptz := now();
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('leadership.servant_leaders.conclude', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to conclude servant leaders.';
  end if;

  -- 4. Reason validation
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = '23502', message = 'A reason is required to conclude a servant leader appointment.';
  end if;

  -- 5. Temporal MVP Policy: Future-effective conclusion unsupported
  v_effective_to := coalesce(p_effective_to, current_date);
  if v_effective_to > current_date then
    raise exception using errcode = '22023', message = 'Future servant-leader changes are not supported yet.';
  end if;

  -- 6. Lock assignment row FOR UPDATE
  select *
  into v_assignment
  from public.leadership_assignments la
  where la.id = p_leadership_assignment_id
    and la.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Leadership assignment not found or not accessible.';
  end if;

  -- 7. Validate role is canonical servant-leader role
  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.id = v_assignment.leadership_role_definition_id
    and lrd.organization_id = p_organization_id;

  if v_role_def.code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    raise exception using errcode = '22023',
      message = 'This RPC only concludes canonical servant-leader appointments.';
  end if;

  -- 8. Validate assignment is currently active
  if v_assignment.assignment_status != 'active' or (v_assignment.effective_to is not null and v_assignment.effective_to < current_date) then
    raise exception using errcode = '22023', message = 'Leadership assignment is not currently active.';
  end if;

  -- 9. Validate effective_to >= effective_from
  if v_assignment.effective_from is not null and v_effective_to < v_assignment.effective_from then
    raise exception using errcode = '22023', message = 'Conclusion date cannot be earlier than the assignment effective start date.';
  end if;

  -- 10. Scope checks on governance node and member
  if not private.can_access_governance_node('leadership.servant_leaders.conclude', p_organization_id, v_assignment.governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  if not private.can_access_member('leadership.servant_leaders.conclude', p_organization_id, v_assignment.member_id) then
    raise exception using errcode = 'P0002', message = 'Member record not found or not accessible.';
  end if;

  select * into v_node from public.governance_nodes where id = v_assignment.governance_node_id;
  select * into v_member from public.members where id = v_assignment.member_id;

  -- 11. Update assignment to terminal status 'completed'
  update public.leadership_assignments
  set
    assignment_status     = 'completed',
    effective_to          = v_effective_to,
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where id = p_leadership_assignment_id;

  -- 12. Atomically Revoke Delegated Access Grants & Associated Roles/Scopes
  update public.servant_leader_access_grants
  set
    access_status         = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Leadership concluded: ' || v_reason,
    updated_at            = v_now
  where leadership_assignment_id = p_leadership_assignment_id
    and organization_id = p_organization_id
    and access_status = 'active';

  update public.profile_role_assignments
  set
    assignment_status     = 'ended',
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = 'Leadership concluded: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where leadership_assignment_id = p_leadership_assignment_id
    and organization_id = p_organization_id
    and assignment_status = 'active';

  update public.profile_scope_assignments psa
  set
    assignment_status     = 'ended',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Leadership concluded: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where psa.organization_id = p_organization_id
    and psa.assignment_status = 'active'
    and exists (
      select 1 from public.profile_role_assignments pra
      where pra.id = psa.profile_role_assignment_id
        and pra.leadership_assignment_id = p_leadership_assignment_id
        and pra.organization_id = p_organization_id
    );

  -- 13. Record Audit Event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader.concluded',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => p_leadership_assignment_id,
    p_action           => 'conclude',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'leadership_assignment_id', p_leadership_assignment_id,
      'member_id',                v_assignment.member_id,
      'governance_node_id',       v_assignment.governance_node_id,
      'role_code',                v_role_def.code,
      'effective_to',             v_effective_to,
      'ending_reason',            v_reason
    )
  );

  return jsonb_build_object(
    'status',                   'concluded',
    'leadership_assignment_id', p_leadership_assignment_id,
    'role_code',                v_role_def.code,
    'role_name',                v_role_def.name,
    'governance_node_id',       v_assignment.governance_node_id,
    'governance_node_name',     v_node.name,
    'member_id',                v_assignment.member_id,
    'member_name',              v_member.display_name,
    'effective_to',             v_effective_to
  );
end;
$$;

revoke execute on function public.conclude_servant_leader(uuid, uuid, date, text) from public, anon;
grant  execute on function public.conclude_servant_leader(uuid, uuid, date, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- public.replace_servant_leader
-- Atomically revokes outgoing leader access grant and provisions new assignment
-- (without auto-granting software access to incoming leader).
-- -----------------------------------------------------------------------------
create or replace function public.replace_servant_leader(
  p_organization_id    uuid,
  p_role_code          text,
  p_governance_node_id uuid,
  p_new_member_id      uuid,
  p_effective_date     date default current_date,
  p_reason             text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id          uuid;
  v_role_code           text;
  v_effective_date      date;
  v_reason              text;
  v_role_def            public.leadership_role_definitions%rowtype;
  v_node                public.governance_nodes%rowtype;
  v_node_type           public.governance_node_types%rowtype;
  v_outgoing_assignment public.leadership_assignments%rowtype;
  v_outgoing_member     public.members%rowtype;
  v_incoming_member     public.members%rowtype;
  v_hh_level            text;
  v_new_assignment_id   uuid;
  v_now                 timestamptz := now();
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('leadership.servant_leaders.replace', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to replace servant leaders.';
  end if;

  -- 4. Reason validation
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception using errcode = '23502', message = 'A reason is required to replace a servant leader.';
  end if;

  -- 5. Canonical Role Code validation
  v_role_code := lower(trim(coalesce(p_role_code, '')));
  if v_role_code not in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader') then
    raise exception using errcode = '22023',
      message = 'Invalid servant leader role code: "' || v_role_code || '". Allowed canonical codes: household_servant_leader, unit_servant_leader, chapter_servant_leader, area_servant_leader.';
  end if;

  -- 6. Temporal MVP Policy: Future-effective replacement unsupported
  v_effective_date := coalesce(p_effective_date, current_date);
  if v_effective_date > current_date then
    raise exception using errcode = '22023', message = 'Future servant-leader changes are not supported yet.';
  end if;

  -- 7. Lock target governance node FOR UPDATE
  select *
  into v_node
  from public.governance_nodes gn
  where gn.id = p_governance_node_id
    and gn.organization_id = p_organization_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  if v_node.lifecycle_status != 'active' then
    raise exception using errcode = '22023', message = 'Cannot replace a servant leader on a governance node that is not active.';
  end if;

  -- 8. Governance scope check on target node
  if not private.can_access_governance_node('leadership.servant_leaders.replace', p_organization_id, p_governance_node_id) then
    raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
  end if;

  -- 9. Resolve canonical role definition
  select *
  into v_role_def
  from public.leadership_role_definitions lrd
  where lrd.organization_id = p_organization_id
    and lrd.code = v_role_code
    and lrd.is_active = true;

  if not found then
    raise exception using errcode = '22023', message = 'Canonical leadership role "' || v_role_code || '" is not configured or active.';
  end if;

  -- 10. Role and Node Type Compatibility
  select *
  into v_node_type
  from public.governance_node_types gnt
  where gnt.id = v_node.governance_node_type_id
    and gnt.organization_id = p_organization_id;

  if v_role_code = 'household_servant_leader' then
    if v_node_type.code != 'household' then
      raise exception using errcode = '22023', message = 'Household Servant Leader must be appointed to a Household node.';
    end if;

    select h.pastoral_level
    into v_hh_level
    from public.households h
    where h.id = v_node.id
      and h.organization_id = p_organization_id;

    if v_hh_level is distinct from 'member' then
      raise exception using errcode = '23514',
        message = 'Household Servant Leader replacement is only permitted on Member Households. This household has pastoral level: "' || coalesce(v_hh_level, 'unknown') || '".';
    end if;
  elsif v_role_code = 'unit_servant_leader' and v_node_type.code != 'unit' then
    raise exception using errcode = '22023', message = 'Unit Servant Leader must be appointed to a Unit node.';
  elsif v_role_code = 'chapter_servant_leader' and v_node_type.code != 'chapter' then
    raise exception using errcode = '22023', message = 'Chapter Servant Leader must be appointed to a Chapter node.';
  elsif v_role_code = 'area_servant_leader' and v_node_type.code != 'area_state' then
    raise exception using errcode = '22023', message = 'Area Servant Leader must be appointed to an Area/State node.';
  end if;

  -- 11. Lock current active office holder FOR UPDATE
  select *
  into v_outgoing_assignment
  from public.leadership_assignments la
  where la.organization_id = p_organization_id
    and la.governance_node_id = p_governance_node_id
    and la.leadership_role_definition_id = v_role_def.id
    and la.assignment_status = 'active'
    and la.effective_from <= current_date
    and (la.effective_to is null or la.effective_to >= current_date)
  for update;

  if not found then
    return jsonb_build_object(
      'status',               'blocked',
      'blocker_type',         'no_current_role_holder',
      'role_code',            v_role_code,
      'governance_node_id',   p_governance_node_id,
      'governance_node_name', v_node.name,
      'message',              'No active servant leader currently holds this office. Use the Appoint action instead.'
    );
  end if;

  -- 12. Reject same-member replacement
  if v_outgoing_assignment.member_id = p_new_member_id then
    raise exception using errcode = '22023', message = 'The replacement member is already the active servant leader for this role.';
  end if;

  -- 13. Validate incoming member
  select *
  into v_incoming_member
  from public.members m
  where m.id = p_new_member_id
    and m.organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Incoming member not found or not accessible.';
  end if;

  if not private.can_access_member('leadership.servant_leaders.replace', p_organization_id, p_new_member_id) then
    raise exception using errcode = 'P0002', message = 'Incoming member not found or not accessible.';
  end if;

  if v_incoming_member.record_status != 'active' then
    raise exception using errcode = '22023', message = 'Incoming member record is not active.';
  end if;

  if v_incoming_member.is_deceased then
    raise exception using errcode = '22023', message = 'Cannot appoint a deceased member as servant leader.';
  end if;

  if not private.can_access_member('leadership.servant_leaders.replace', p_organization_id, v_outgoing_assignment.member_id) then
    raise exception using errcode = 'P0002', message = 'Outgoing leader record not accessible.';
  end if;

  select * into v_outgoing_member from public.members where id = v_outgoing_assignment.member_id;

  -- 14. Step A: Conclude outgoing assignment
  update public.leadership_assignments
  set
    assignment_status     = 'completed',
    effective_to          = v_effective_date,
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = 'Replaced: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where id = v_outgoing_assignment.id;

  -- Atomically Revoke Outgoing Leader Access Grant & Associated Roles/Scopes
  update public.servant_leader_access_grants
  set
    access_status         = 'revoked',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Servant leader replaced: ' || v_reason,
    updated_at            = v_now
  where leadership_assignment_id = v_outgoing_assignment.id
    and organization_id = p_organization_id
    and access_status = 'active';

  update public.profile_role_assignments
  set
    assignment_status     = 'ended',
    ended_at              = v_now,
    ended_by_profile_id   = v_profile_id,
    ending_reason         = 'Servant leader replaced: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where leadership_assignment_id = v_outgoing_assignment.id
    and organization_id = p_organization_id
    and assignment_status = 'active';

  update public.profile_scope_assignments psa
  set
    assignment_status     = 'ended',
    revoked_at            = v_now,
    revoked_by_profile_id = v_profile_id,
    revocation_reason     = 'Servant leader replaced: ' || v_reason,
    updated_at            = v_now,
    updated_by_profile_id = v_profile_id
  where psa.organization_id = p_organization_id
    and psa.assignment_status = 'active'
    and exists (
      select 1 from public.profile_role_assignments pra
      where pra.id = psa.profile_role_assignment_id
        and pra.leadership_assignment_id = v_outgoing_assignment.id
        and pra.organization_id = p_organization_id
    );

  -- 15. Step B: Insert incoming assignment (same-day transition)
  -- Note: incoming leader does NOT receive software access automatically!
  v_new_assignment_id := gen_random_uuid();

  insert into public.leadership_assignments (
    id,
    organization_id,
    member_id,
    governance_node_id,
    leadership_role_definition_id,
    paired_assignment_id,
    assignment_status,
    appointment_type,
    effective_from,
    effective_to,
    proposed_at,
    proposed_by_profile_id,
    approved_at,
    approved_by_profile_id,
    accepted_at,
    activated_at,
    appointment_summary,
    metadata,
    created_at,
    created_by_profile_id,
    updated_at,
    updated_by_profile_id
  )
  values (
    v_new_assignment_id,
    p_organization_id,
    p_new_member_id,
    p_governance_node_id,
    v_role_def.id,
    null,
    'active',
    'permanent',
    v_effective_date,
    null,
    v_now,
    v_profile_id,
    v_now,
    v_profile_id,
    v_now,
    v_now,
    'Replaced outgoing servant leader: ' || v_outgoing_member.display_name || '. Reason: ' || v_reason,
    jsonb_build_object(
      'superseded_assignment_id', v_outgoing_assignment.id,
      'superseded_member_id',     v_outgoing_assignment.member_id,
      'superseded_member_name',   v_outgoing_member.display_name,
      'replacement_reason',       v_reason
    ),
    v_now,
    v_profile_id,
    v_now,
    v_profile_id
  );

  -- 16. Record Audit Events
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'servant_leader.replaced',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'leadership_assignment',
    p_entity_id        => v_new_assignment_id,
    p_action           => 'replace',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'superseded_assignment_id', v_outgoing_assignment.id,
      'outgoing_member_id',       v_outgoing_assignment.member_id,
      'incoming_assignment_id',   v_new_assignment_id,
      'incoming_member_id',       p_new_member_id,
      'governance_node_id',       p_governance_node_id,
      'role_code',                v_role_code,
      'effective_date',           v_effective_date,
      'reason',                   v_reason
    )
  );

  return jsonb_build_object(
    'status',                   'success',
    'superseded_assignment_id', v_outgoing_assignment.id,
    'outgoing_member_id',       v_outgoing_assignment.member_id,
    'outgoing_member_name',     v_outgoing_member.display_name,
    'new_assignment_id',        v_new_assignment_id,
    'incoming_member_id',       p_new_member_id,
    'incoming_member_name',     v_incoming_member.display_name,
    'role_code',                v_role_code,
    'role_name',                v_role_def.name,
    'governance_node_id',       p_governance_node_id,
    'governance_node_name',     v_node.name,
    'effective_date',           v_effective_date
  );
end;
$$;

revoke execute on function public.replace_servant_leader(uuid, text, uuid, uuid, date, text) from public, anon;
grant  execute on function public.replace_servant_leader(uuid, text, uuid, uuid, date, text) to authenticated, service_role;

-- =============================================================================
-- SECTION 8: Update Meeting Mutation RPCs to Guard Direct Servant Leader Responsibility
-- Enforces: Admin OR (delegated permission AND active access grant AND direct servant-leader responsibility)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- create_household_meeting
-- -----------------------------------------------------------------------------
create or replace function public.create_household_meeting(
  p_organization_id       uuid,
  p_household_id          uuid,
  p_meeting_date          date,
  p_meeting_type          text default 'regular_household',
  p_scheduled_start_at    timestamptz default null,
  p_scheduled_end_at      timestamptz default null,
  p_location_type         text default null,
  p_location_text         text default null,
  p_facilitator_member_id uuid default null,
  p_host_member_id        uuid default null,
  p_notes_summary         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id      uuid;
  v_household_node  public.governance_nodes%rowtype;
  v_meeting_id      uuid;
  v_meeting_type    text;
  v_loc_type        text;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household meetings.';
  end if;

  select * into v_household_node
  from public.governance_nodes
  where id = p_household_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.manage', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- DIRECT SERVANT-LEADER RESPONSIBILITY GUARD
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, p_household_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  if p_meeting_date is null then
    raise exception using errcode = '22023', message = 'Meeting date is required.';
  end if;

  v_meeting_type := coalesce(trim(p_meeting_type), 'regular_household');
  if v_meeting_type not in (
    'regular_household', 'special_household', 'fellowship', 'formation', 'prayer', 'other'
  ) then
    raise exception using errcode = '22023',
      message = 'Invalid meeting type. Valid: regular_household, special_household, fellowship, formation, prayer, other.';
  end if;

  v_loc_type := nullif(trim(coalesce(p_location_type, '')), '');
  if v_loc_type is not null and v_loc_type not in ('in_person', 'virtual', 'hybrid') then
    raise exception using errcode = '22023',
      message = 'Invalid location type. Valid: in_person, virtual, hybrid.';
  end if;

  if p_scheduled_start_at is not null
    and p_scheduled_end_at is not null
    and p_scheduled_end_at <= p_scheduled_start_at
  then
    raise exception using errcode = '22023', message = 'Scheduled end must be after scheduled start.';
  end if;

  if p_notes_summary is not null then
    raise exception using errcode = '22023',
      message = 'Free-text household meeting notes are not supported in this phase.';
  end if;

  if p_facilitator_member_id is not null then
    if not exists (
      select 1 from public.members
      where id = p_facilitator_member_id
        and organization_id = p_organization_id
        and record_status = 'active'
    ) then
      raise exception using errcode = 'P0002',
        message = 'Facilitator member not found, not active, or not in this organization.';
    end if;
  end if;

  if p_host_member_id is not null then
    if not exists (
      select 1 from public.members
      where id = p_host_member_id
        and organization_id = p_organization_id
        and record_status = 'active'
    ) then
      raise exception using errcode = 'P0002',
        message = 'Host member not found, not active, or not in this organization.';
    end if;
  end if;

  insert into public.household_meetings (
    organization_id,
    household_node_id,
    meeting_date,
    scheduled_start_at,
    scheduled_end_at,
    meeting_status,
    meeting_type,
    location_type,
    location_text,
    facilitator_member_id,
    host_member_id,
    created_by_profile_id,
    updated_by_profile_id
  )
  values (
    p_organization_id,
    p_household_id,
    p_meeting_date,
    p_scheduled_start_at,
    p_scheduled_end_at,
    'scheduled',
    v_meeting_type,
    v_loc_type,
    nullif(trim(coalesce(p_location_text, '')), ''),
    p_facilitator_member_id,
    p_host_member_id,
    v_profile_id,
    v_profile_id
  )
  returning id into v_meeting_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => v_meeting_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', v_meeting_id,
      'household_node_id',    p_household_id,
      'household_node_name',  v_household_node.name,
      'meeting_date',         p_meeting_date,
      'meeting_type',         v_meeting_type
    )
  );

  return jsonb_build_object(
    'household_meeting_id', v_meeting_id,
    'household_node_id',    p_household_id,
    'meeting_date',         p_meeting_date,
    'meeting_status',       'scheduled',
    'meeting_type',         v_meeting_type
  );
end;
$$;

revoke execute on function public.create_household_meeting(uuid,uuid,date,text,timestamptz,timestamptz,text,text,uuid,uuid,text) from public, anon;
grant  execute on function public.create_household_meeting(uuid,uuid,date,text,timestamptz,timestamptz,text,text,uuid,uuid,text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- cancel_household_meeting
-- -----------------------------------------------------------------------------
create or replace function public.cancel_household_meeting(
  p_organization_id  uuid,
  p_meeting_id       uuid,
  p_reason           text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_meeting     public.household_meetings%rowtype;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household meetings.';
  end if;

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.manage', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- DIRECT SERVANT-LEADER RESPONSIBILITY GUARD
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, v_meeting.household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  if v_meeting.meeting_status != 'scheduled' then
    raise exception using errcode = '23514',
      message = format('Cannot cancel a meeting in status ''%s''. Only scheduled meetings can be cancelled.', v_meeting.meeting_status);
  end if;

  update public.household_meetings
  set
    meeting_status        = 'cancelled',
    updated_at            = now(),
    updated_by_profile_id = v_profile_id
  where id = p_meeting_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.cancelled',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => p_meeting_id,
    p_action           => 'cancel',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', p_meeting_id,
      'household_node_id',    v_meeting.household_node_id,
      'meeting_date',         v_meeting.meeting_date,
      'reason',               p_reason
    )
  );

  return jsonb_build_object(
    'household_meeting_id', p_meeting_id,
    'meeting_status',       'cancelled'
  );
end;
$$;

revoke execute on function public.cancel_household_meeting(uuid,uuid,text) from public, anon;
grant  execute on function public.cancel_household_meeting(uuid,uuid,text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- complete_household_meeting
-- -----------------------------------------------------------------------------
create or replace function public.complete_household_meeting(
  p_organization_id   uuid,
  p_meeting_id        uuid,
  p_actual_start_at   timestamptz default null,
  p_actual_end_at     timestamptz default null,
  p_notes_summary     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_meeting     public.household_meetings%rowtype;
  v_summary     jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.meetings.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household meetings.';
  end if;

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.meetings.manage', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- DIRECT SERVANT-LEADER RESPONSIBILITY GUARD
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, v_meeting.household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  if v_meeting.meeting_status != 'scheduled' then
    raise exception using errcode = '23514',
      message = format('Cannot complete a meeting in status ''%s''. Only scheduled meetings can be completed.', v_meeting.meeting_status);
  end if;

  if v_meeting.meeting_date > current_date then
    raise exception using errcode = '23514',
      message = 'Cannot complete a meeting scheduled for a future date.';
  end if;

  if p_notes_summary is not null then
    raise exception using errcode = '22023',
      message = 'Free-text household meeting notes are not supported in this phase.';
  end if;

  update public.household_meetings
  set
    meeting_status        = 'completed',
    actual_start_at       = coalesce(p_actual_start_at, actual_start_at),
    actual_end_at         = coalesce(p_actual_end_at, actual_end_at),
    updated_at            = now(),
    updated_by_profile_id = v_profile_id
  where id = p_meeting_id;

  v_summary := private.compute_attendance_summary(
    p_meeting_id,
    p_organization_id,
    v_meeting.meeting_date,
    v_meeting.household_node_id
  );

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_meeting.completed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => p_meeting_id,
    p_action           => 'complete',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', p_meeting_id,
      'household_node_id',    v_meeting.household_node_id,
      'meeting_date',         v_meeting.meeting_date,
      'attendance_summary',   v_summary
    )
  );

  return jsonb_build_object(
    'household_meeting_id', p_meeting_id,
    'meeting_status',       'completed',
    'attendance_summary',   v_summary
  );
end;
$$;

revoke execute on function public.complete_household_meeting(uuid,uuid,timestamptz,timestamptz,text) from public, anon;
grant  execute on function public.complete_household_meeting(uuid,uuid,timestamptz,timestamptz,text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- record_household_meeting_attendance
-- -----------------------------------------------------------------------------
create or replace function public.record_household_meeting_attendance(
  p_organization_id uuid,
  p_meeting_id      uuid,
  p_attendance      jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id      uuid;
  v_meeting         public.household_meetings%rowtype;
  v_item            jsonb;
  v_member_id       uuid;
  v_status          text;
  v_inserted        integer := 0;
  v_updated         integer := 0;
  v_existing_status text;
  v_any_correction  boolean := false;
  v_summary         jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.attendance.record', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to record attendance.';
  end if;

  select * into v_meeting
  from public.household_meetings
  where id = p_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found or not accessible.';
  end if;

  if not private.can_access_governance_node('households.attendance.record', p_organization_id, v_meeting.household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- DIRECT SERVANT-LEADER RESPONSIBILITY GUARD
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, v_meeting.household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  if v_meeting.meeting_date > current_date then
    raise exception using errcode = '23514',
      message = 'Attendance cannot be recorded for a future meeting date.';
  end if;

  if v_meeting.meeting_status = 'cancelled' then
    raise exception using errcode = '23514',
      message = 'Attendance cannot be recorded for a cancelled meeting.';
  end if;

  if p_attendance is null or jsonb_typeof(p_attendance) != 'array' then
    raise exception using errcode = '22023',
      message = 'p_attendance must be a JSON array of {member_id, attendance_status} objects.';
  end if;

  if jsonb_array_length(p_attendance) = 0 then
    raise exception using errcode = '22023',
      message = 'p_attendance array must not be empty.';
  end if;

  for v_item in select * from jsonb_array_elements(p_attendance)
  loop
    begin
      v_member_id := (v_item->>'member_id')::uuid;
    exception when others then
      raise exception using errcode = '22023',
        message = format('Invalid member_id in attendance array: %s', v_item->>'member_id');
    end;

    v_status := lower(trim(coalesce(v_item->>'attendance_status', '')));
    if v_status not in ('attended', 'absent', 'excused') then
      raise exception using errcode = '22023',
        message = format('Invalid attendance_status ''%s'' for member %s. Valid: attended, absent, excused.', v_status, v_member_id);
    end if;

    if not exists (
      select 1
      from private.get_household_expected_roster(
        p_organization_id,
        v_meeting.household_node_id,
        v_meeting.meeting_date
      ) r
      where r.member_id = v_member_id
    ) then
      raise exception using errcode = '23514',
        message = format(
          'Member %s was not an active member of this household on meeting date %s.',
          v_member_id,
          v_meeting.meeting_date
        );
    end if;

    select attendance_status into v_existing_status
    from public.household_meeting_attendance
    where meeting_id = p_meeting_id
      and member_id = v_member_id;

    if v_existing_status is null then
      insert into public.household_meeting_attendance (
        meeting_id,
        organization_id,
        member_id,
        attendance_status,
        is_guest,
        created_by_profile_id,
        updated_by_profile_id
      )
      values (
        p_meeting_id,
        p_organization_id,
        v_member_id,
        v_status,
        false,
        v_profile_id,
        v_profile_id
      );
      v_inserted := v_inserted + 1;
    elsif v_existing_status != v_status then
      update public.household_meeting_attendance
      set
        attendance_status     = v_status,
        updated_at            = now(),
        updated_by_profile_id = v_profile_id
      where meeting_id = p_meeting_id
        and member_id = v_member_id;
      v_updated := v_updated + 1;
      v_any_correction := true;
    end if;
  end loop;

  v_summary := private.compute_attendance_summary(
    p_meeting_id,
    p_organization_id,
    v_meeting.meeting_date,
    v_meeting.household_node_id
  );

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => case when v_any_correction then 'household_meeting_attendance.corrected'
                               else 'household_meeting_attendance.recorded' end,
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_meeting',
    p_entity_id        => p_meeting_id,
    p_action           => case when v_any_correction then 'correct_attendance' else 'record_attendance' end,
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'household_meeting_id', p_meeting_id,
      'household_node_id',    v_meeting.household_node_id,
      'meeting_date',         v_meeting.meeting_date,
      'inserted_count',       v_inserted,
      'updated_count',        v_updated,
      'attendance_summary',   v_summary
    )
  );

  return jsonb_build_object(
    'household_meeting_id', p_meeting_id,
    'meeting_status',       v_meeting.meeting_status,
    'inserted_count',       v_inserted,
    'updated_count',        v_updated,
    'attendance_summary',   v_summary
  );
end;
$$;

revoke execute on function public.record_household_meeting_attendance(uuid,uuid,jsonb) from public, anon;
grant  execute on function public.record_household_meeting_attendance(uuid,uuid,jsonb) to authenticated, service_role;

-- =============================================================================
-- SECTION 9: Update get_pastoral_operations_dashboard with Delegated Access Double-Lock
-- Enforces:
--   1. Non-admin callers require active servant leader access grant + active leadership assignment.
--   2. When p_governance_node_id is NULL for non-admin callers, never widen to org-wide.
--      Scope resolves strictly to caller's explicit authorized governance nodes.
-- =============================================================================

create or replace function public.get_pastoral_operations_dashboard(
  p_organization_id    uuid,
  p_governance_node_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id             uuid;
  v_is_org_admin           boolean;
  v_target_scope_node_id   uuid;
  v_caller_member_id       uuid;
  v_caller_display_name    text;
  v_serving_assignments    jsonb := '[]'::jsonb;
  v_pastoral_membership    jsonb;
  v_identity_json          jsonb;
  v_care_responsibilities  jsonb := '[]'::jsonb;
  v_can_review_placement   boolean;
  v_can_view_leadership    boolean;
  v_can_view_roster        boolean;
  v_households_summary     jsonb := '[]'::jsonb;
  v_leadership_vacancies   jsonb := '[]'::jsonb;
  v_capacity_summary       jsonb;
  v_operational_summary    jsonb;
  v_placement_summary      jsonb;
  v_unassigned_count       integer := 0;
  v_meeting_ops_summary    jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Dedicated Dashboard Permission check
  if not private.has_permission('leadership.pastoral_dashboard.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view the pastoral operations dashboard.';
  end if;

  v_is_org_admin := private.is_organization_administrator(v_profile_id, p_organization_id);

  -- 4. NON-ADMIN DOUBLE-LOCK REQUIREMENT
  -- Delegated callers MUST hold an active servant leader access grant AND a current active leadership assignment.
  if not v_is_org_admin then
    if not exists (
      select 1
      from public.servant_leader_access_grants g
      join public.leadership_assignments la on la.id = g.leadership_assignment_id
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
        and g.access_status = 'active'
        and g.effective_from <= current_date
        and (g.effective_to is null or g.effective_to >= current_date)
        and la.organization_id = p_organization_id
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date)
    ) then
      raise exception using errcode = '42501',
        message = 'Active servant leader access grant and current leadership assignment are required.';
    end if;
  end if;

  -- 5. Scope verification if specific node supplied
  if p_governance_node_id is not null then
    if not private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, p_governance_node_id) then
      raise exception using errcode = 'P0002', message = 'Governance node not found or not accessible.';
    end if;
    v_target_scope_node_id := p_governance_node_id;
  end if;

  -- 6. Sub-domain permission checks for safe field filtering
  v_can_review_placement := private.has_permission('leadership.pastoral_placement.review', p_organization_id);
  v_can_view_leadership  := private.has_permission('governance.leadership.view', p_organization_id);
  v_can_view_roster      := private.has_permission('members.households.view', p_organization_id);

  -- 7. Resolve caller profile and member link (if exists)
  select pml.member_id, coalesce(m.display_name, p.display_name)
  into v_caller_member_id, v_caller_display_name
  from public.profiles p
  left join public.profile_member_links pml
    on pml.profile_id = p.id
   and pml.organization_id = p_organization_id
   and pml.is_primary = true
   and pml.link_type = 'self'
   and pml.link_status = 'verified'
   and pml.ended_at is null
  left join public.members m
    on m.id = pml.member_id
   and m.organization_id = p_organization_id
  where p.id = v_profile_id;

  if v_caller_display_name is null then
    select display_name into v_caller_display_name from public.profiles where id = v_profile_id;
  end if;

  -- 8. If linked to member, resolve Where I Serve (active formal servant roles)
  if v_caller_member_id is not null then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'leadership_assignment_id', la.id,
        'role_code',                lrd.code,
        'role_name',                lrd.name,
        'governance_node_id',       la.governance_node_id,
        'governance_node_name',     gn.name,
        'pastoral_level',           h.pastoral_level,
        'effective_from',           la.effective_from,
        'effective_to',             la.effective_to
      ) order by la.effective_from desc
    ), '[]'::jsonb)
    into v_serving_assignments
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
    join public.governance_nodes gn on gn.id = la.governance_node_id
    left join public.households h on h.id = la.governance_node_id
    where la.organization_id = p_organization_id
      and la.member_id = v_caller_member_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code in ('household_servant_leader', 'unit_servant_leader', 'chapter_servant_leader', 'area_servant_leader');

    -- Where I Receive Pastoral Care (current primary household)
    select jsonb_build_object(
      'household_id',            h.id,
      'household_name',          gn.name,
      'pastoral_level',          h.pastoral_level,
      'scope_node_id',           p_rel.parent_node_id,
      'scope_node_name',         pn.name,
      'membership_role',         hm.membership_role,
      'effective_from',          hm.effective_from,
      'meeting_frequency',       h.meeting_frequency,
      'meeting_day_of_week',     h.meeting_day_of_week,
      'meeting_start_time',      to_char(h.meeting_start_time, 'HH24:MI:SS'),
      'meeting_timezone_name',   h.meeting_timezone_name,
      'is_fraternal',            (h.pastoral_level = 'fraternal')
    )
    into v_pastoral_membership
    from public.household_memberships hm
    join public.households h on h.id = hm.household_node_id
    join public.governance_nodes gn on gn.id = h.id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn on pn.id = p_rel.parent_node_id
    where hm.organization_id = p_organization_id
      and hm.member_id = v_caller_member_id
      and hm.is_primary = true
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    limit 1;
  end if;

  -- 9. Build Identity Block
  v_identity_json := jsonb_build_object(
    'profile_id',                          v_profile_id,
    'member_id',                           v_caller_member_id,
    'display_name',                        v_caller_display_name,
    'has_linked_member',                   (v_caller_member_id is not null),
    'serving_assignments',                 v_serving_assignments,
    'pastoral_membership',                 v_pastoral_membership,
    'pastoral_household_placement_needed', (v_caller_member_id is not null and v_pastoral_membership is null and jsonb_array_length(v_serving_assignments) > 0)
  );

  -- 10. Care Responsibilities (People I Care For)
  if v_caller_member_id is not null and jsonb_array_length(v_serving_assignments) > 0 then
    with direct_care_members as (
      -- HSL direct care: active members in led household
      select
        hm.member_id,
        m.display_name as member_name,
        hm.membership_role,
        h.id as household_id,
        gn.name as household_name,
        'household_member'::text as care_relation_type
      from public.household_memberships hm
      join public.households h on h.id = hm.household_node_id
      join public.governance_nodes gn on gn.id = h.id
      join public.members m on m.id = hm.member_id
      join public.leadership_assignments la on la.governance_node_id = h.id
      join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
      where la.organization_id = p_organization_id
        and la.member_id = v_caller_member_id
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date)
        and lrd.code = 'household_servant_leader'
        and hm.organization_id = p_organization_id
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
        and hm.is_primary = true
        and hm.member_id != v_caller_member_id

      union

      -- USL direct care: HSLs under their Unit
      select
        la_sub.member_id,
        m.display_name as member_name,
        'leader'::text as membership_role,
        h_sub.id as household_id,
        gn_sub.name as household_name,
        'subordinate_leader'::text as care_relation_type
      from public.leadership_assignments la_sub
      join public.leadership_role_definitions lrd_sub on lrd_sub.id = la_sub.leadership_role_definition_id
      join public.households h_sub on h_sub.id = la_sub.governance_node_id
      join public.governance_nodes gn_sub on gn_sub.id = h_sub.id
      join public.governance_node_relationships p_rel on p_rel.child_node_id = h_sub.id
      join public.members m on m.id = la_sub.member_id
      join public.leadership_assignments la_unit on la_unit.governance_node_id = p_rel.parent_node_id
      join public.leadership_role_definitions lrd_unit on lrd_unit.id = la_unit.leadership_role_definition_id
      where la_unit.organization_id = p_organization_id
        and la_unit.member_id = v_caller_member_id
        and la_unit.assignment_status = 'active'
        and la_unit.effective_from <= current_date
        and (la_unit.effective_to is null or la_unit.effective_to >= current_date)
        and lrd_unit.code = 'unit_servant_leader'
        and p_rel.relationship_status = 'active'
        and p_rel.relationship_type = 'primary_parent'
        and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
        and la_sub.organization_id = p_organization_id
        and la_sub.assignment_status = 'active'
        and la_sub.effective_from <= current_date
        and (la_sub.effective_to is null or la_sub.effective_to >= current_date)
        and lrd_sub.code = 'household_servant_leader'
        and la_sub.member_id != v_caller_member_id

      union

      -- CSL direct care: USLs under their Chapter
      select
        la_unit.member_id,
        m.display_name as member_name,
        'leader'::text as membership_role,
        null::uuid as household_id,
        gn_unit.name as household_name,
        'subordinate_leader'::text as care_relation_type
      from public.leadership_assignments la_unit
      join public.leadership_role_definitions lrd_unit on lrd_unit.id = la_unit.leadership_role_definition_id
      join public.governance_nodes gn_unit on gn_unit.id = la_unit.governance_node_id
      join public.governance_node_relationships p_rel on p_rel.child_node_id = gn_unit.id
      join public.members m on m.id = la_unit.member_id
      join public.leadership_assignments la_chap on la_chap.governance_node_id = p_rel.parent_node_id
      join public.leadership_role_definitions lrd_chap on lrd_chap.id = la_chap.leadership_role_definition_id
      where la_chap.organization_id = p_organization_id
        and la_chap.member_id = v_caller_member_id
        and la_chap.assignment_status = 'active'
        and la_chap.effective_from <= current_date
        and (la_chap.effective_to is null or la_chap.effective_to >= current_date)
        and lrd_chap.code = 'chapter_servant_leader'
        and p_rel.relationship_status = 'active'
        and p_rel.relationship_type = 'primary_parent'
        and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
        and la_unit.organization_id = p_organization_id
        and la_unit.assignment_status = 'active'
        and la_unit.effective_from <= current_date
        and (la_unit.effective_to is null or la_unit.effective_to >= current_date)
        and lrd_unit.code = 'unit_servant_leader'
        and la_unit.member_id != v_caller_member_id

      union

      -- ASL direct care: CSLs under their Area
      select
        la_chap.member_id,
        m.display_name as member_name,
        'leader'::text as membership_role,
        null::uuid as household_id,
        gn_chap.name as household_name,
        'subordinate_leader'::text as care_relation_type
      from public.leadership_assignments la_chap
      join public.leadership_role_definitions lrd_chap on lrd_chap.id = la_chap.leadership_role_definition_id
      join public.governance_nodes gn_chap on gn_chap.id = la_chap.governance_node_id
      join public.governance_node_relationships p_rel on p_rel.child_node_id = gn_chap.id
      join public.members m on m.id = la_chap.member_id
      join public.leadership_assignments la_area on la_area.governance_node_id = p_rel.parent_node_id
      join public.leadership_role_definitions lrd_area on lrd_area.id = la_area.leadership_role_definition_id
      where la_area.organization_id = p_organization_id
        and la_area.member_id = v_caller_member_id
        and la_area.assignment_status = 'active'
        and la_area.effective_from <= current_date
        and (la_area.effective_to is null or la_area.effective_to >= current_date)
        and lrd_area.code = 'area_servant_leader'
        and p_rel.relationship_status = 'active'
        and p_rel.relationship_type = 'primary_parent'
        and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
        and la_chap.organization_id = p_organization_id
        and la_chap.assignment_status = 'active'
        and la_chap.effective_from <= current_date
        and (la_chap.effective_to is null or la_chap.effective_to >= current_date)
        and lrd_chap.code = 'chapter_servant_leader'
        and la_chap.member_id != v_caller_member_id
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'member_id',          dcm.member_id,
        'member_name',        dcm.member_name,
        'membership_role',    dcm.membership_role,
        'household_id',       dcm.household_id,
        'household_name',     dcm.household_name,
        'care_relation_type', dcm.care_relation_type
      ) order by dcm.member_name asc
    ), '[]'::jsonb)
    into v_care_responsibilities
    from direct_care_members dcm;
  end if;

  -- 11. Scoped Households Summary with Cadence & Meeting Operations
  with scoped_households as (
    select
      h.id as household_id,
      gn.name as household_name,
      h.pastoral_level,
      h.household_category,
      gn.lifecycle_status,
      h.is_couple_household,
      p_rel.parent_node_id as scope_node_id,
      pn.name as scope_node_name,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      count(distinct hm.member_id) filter (
        where hm.membership_status in ('active', 'temporary')
          and hm.effective_from <= current_date
          and (hm.effective_to is null or hm.effective_to >= current_date)
      ) as member_count
    from public.households h
    join public.governance_nodes gn on gn.id = h.id
    left join public.governance_node_relationships p_rel
      on p_rel.child_node_id = h.id
     and p_rel.organization_id = p_organization_id
     and p_rel.relationship_type = 'primary_parent'
     and p_rel.relationship_status = 'active'
     and (p_rel.effective_to is null or p_rel.effective_to >= current_date)
    left join public.governance_nodes pn on pn.id = p_rel.parent_node_id
    left join public.household_memberships hm
      on hm.household_node_id = h.id
     and hm.organization_id = p_organization_id
     and hm.is_primary = true
    where h.organization_id = p_organization_id
      and (
        v_target_scope_node_id is null
        or h.id = v_target_scope_node_id
        or p_rel.parent_node_id = v_target_scope_node_id
        or exists (
          select 1 from public.governance_node_relationships anc
          where anc.parent_node_id = v_target_scope_node_id
            and anc.child_node_id = p_rel.parent_node_id
            and anc.organization_id = p_organization_id
            and anc.relationship_status = 'active'
        )
      )
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h.id)
    group by
      h.id, gn.name, h.pastoral_level, h.household_category, gn.lifecycle_status,
      h.is_couple_household, p_rel.parent_node_id, pn.name, h.target_member_count,
      h.maximum_member_count, h.accepts_new_members, h.meeting_frequency,
      h.meeting_day_of_week, h.meeting_start_time
  ),
  household_leaders as (
    select
      sh.household_id,
      case
        when sh.pastoral_level = 'member' then la_hh.id
        when sh.pastoral_level in ('unit', 'chapter', 'area') then la_scope.id
        else null
      end as leadership_assignment_id,
      case
        when sh.pastoral_level = 'member' then lm_hh.id
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lm_scope.id
        else null
      end as leader_member_id,
      case
        when sh.pastoral_level = 'member' then lm_hh.display_name
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lm_scope.display_name
        else null
      end as leader_name,
      case
        when sh.pastoral_level = 'member' then lrd_hh.code
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lrd_scope.code
        else null
      end as role_code,
      case
        when sh.pastoral_level = 'member' then lrd_hh.name
        when sh.pastoral_level in ('unit', 'chapter', 'area') then lrd_scope.name
        else null
      end as role_name,
      case
        when sh.pastoral_level = 'fraternal' then 'rotating_facilitation'
        when sh.pastoral_level = 'member' and la_hh.id is not null then 'assigned'
        when sh.pastoral_level in ('unit', 'chapter', 'area') and la_scope.id is not null then 'derived_from_scope'
        else 'vacant'
      end as leadership_status
    from scoped_households sh
    left join lateral (
      select la.id, la.member_id, la.leadership_role_definition_id
      from public.leadership_assignments la
      join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
      where la.governance_node_id = sh.household_id
        and la.organization_id = p_organization_id
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date)
        and lrd.code = 'household_servant_leader'
      order by la.effective_from desc
      limit 1
    ) la_hh on sh.pastoral_level = 'member'
    left join public.members lm_hh on lm_hh.id = la_hh.member_id
    left join public.leadership_role_definitions lrd_hh on lrd_hh.id = la_hh.leadership_role_definition_id
    left join lateral (
      select la.id, la.member_id, la.leadership_role_definition_id
      from public.leadership_assignments la
      join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
      where la.governance_node_id = sh.scope_node_id
        and la.organization_id = p_organization_id
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date)
        and lrd.code = case sh.pastoral_level
          when 'unit' then 'unit_servant_leader'
          when 'chapter' then 'chapter_servant_leader'
          when 'area' then 'area_servant_leader'
        end
      order by la.effective_from desc
      limit 1
    ) la_scope on sh.pastoral_level in ('unit', 'chapter', 'area')
    left join public.members lm_scope on lm_scope.id = la_scope.member_id
    left join public.leadership_role_definitions lrd_scope on lrd_scope.id = la_scope.leadership_role_definition_id
  ),
  household_meetings_summary as (
    select
      sh.household_id,
      max(hm.meeting_date) filter (where hm.meeting_status = 'completed') as last_completed_meeting_date,
      min(hm.meeting_date) filter (where hm.meeting_status = 'scheduled' and hm.meeting_date >= current_date) as next_scheduled_meeting_date
    from scoped_households sh
    left join public.household_meetings hm
      on hm.household_node_id = sh.household_id
     and hm.organization_id = p_organization_id
    group by sh.household_id
  ),
  with_operational_status as (
    select
      sh.*,
      hl.leadership_assignment_id,
      hl.leader_member_id,
      hl.leader_name,
      hl.role_code,
      hl.role_name,
      hl.leadership_status,
      hms.last_completed_meeting_date,
      hms.next_scheduled_meeting_date,
      private.compute_household_meeting_cadence_status(
        sh.household_id,
        sh.meeting_frequency,
        hms.last_completed_meeting_date,
        hms.next_scheduled_meeting_date,
        current_date
      ) as cadence_info,
      case
        when sh.maximum_member_count is not null and sh.member_count >= sh.maximum_member_count then 'full'
        when not sh.accepts_new_members then 'not_accepting'
        when sh.target_member_count is not null and sh.member_count >= sh.target_member_count then 'at_target'
        else 'available'
      end as capacity_status,
      case
        when sh.lifecycle_status != 'active' then 'inactive'
        when hl.leadership_status = 'vacant' then 'needs_leader'
        when not sh.accepts_new_members then 'not_accepting'
        when sh.maximum_member_count is not null and sh.member_count >= sh.maximum_member_count then 'at_capacity'
        when sh.target_member_count is not null and sh.member_count < sh.target_member_count then 'needs_members'
        else 'ready'
      end as operational_status
    from scoped_households sh
    join household_leaders hl on hl.household_id = sh.household_id
    join household_meetings_summary hms on hms.household_id = sh.household_id
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'household_id',                      wos.household_id,
      'household_name',                    wos.household_name,
      'pastoral_level',                    wos.pastoral_level,
      'household_category',                wos.household_category,
      'lifecycle_status',                  wos.lifecycle_status,
      'is_couple_household',               wos.is_couple_household,
      'scope_node_id',                     wos.scope_node_id,
      'scope_node_name',                   wos.scope_node_name,
      'leadership_assignment_id',          wos.leadership_assignment_id,
      'leader_member_id',                  wos.leader_member_id,
      'leader_name',                       case when v_can_view_leadership then wos.leader_name else null end,
      'role_code',                         case when v_can_view_leadership then wos.role_code else null end,
      'role_name',                         case when v_can_view_leadership then wos.role_name else null end,
      'member_count',                      wos.member_count,
      'target_member_count',               wos.target_member_count,
      'maximum_member_count',              wos.maximum_member_count,
      'accepts_new_members',               wos.accepts_new_members,
      'capacity_status',                   wos.capacity_status,
      'leadership_status',                 wos.leadership_status,
      'operational_status',                wos.operational_status,
      'meeting_operational_status',        wos.cadence_info->>'meeting_operational_status',
      'last_completed_meeting_date',       wos.last_completed_meeting_date,
      'next_scheduled_meeting_date',       wos.next_scheduled_meeting_date,
      'expected_next_meeting_date',        wos.cadence_info->>'expected_next_meeting_date',
      'days_since_last_completed_meeting', (wos.cadence_info->>'days_since_last_completed_meeting')::integer,
      'meeting_frequency',                 wos.meeting_frequency,
      'meeting_day_of_week',               wos.meeting_day_of_week,
      'meeting_start_time',                wos.meeting_start_time
    ) order by
      case wos.pastoral_level
        when 'fraternal' then 1
        when 'area' then 2
        when 'chapter' then 3
        when 'unit' then 4
        when 'member' then 5
      end,
      wos.household_name
  ), '[]'::jsonb)
  into v_households_summary
  from with_operational_status wos;

  -- 12. Capacity & Operational Aggregates
  select jsonb_build_object(
    'available',     count(*) filter (where item->>'capacity_status' = 'available'),
    'at_target',     count(*) filter (where item->>'capacity_status' = 'at_target'),
    'full',          count(*) filter (where item->>'capacity_status' = 'full'),
    'not_accepting', count(*) filter (where item->>'capacity_status' = 'not_accepting'),
    'total',         count(*)
  )
  into v_capacity_summary
  from jsonb_array_elements(v_households_summary) item;

  select jsonb_build_object(
    'ready',                     count(*) filter (where item->>'operational_status' = 'ready'),
    'needs_leader',              count(*) filter (where item->>'operational_status' = 'needs_leader'),
    'needs_members',             count(*) filter (where item->>'operational_status' = 'needs_members'),
    'at_capacity',               count(*) filter (where item->>'operational_status' = 'at_capacity'),
    'not_accepting',             count(*) filter (where item->>'operational_status' = 'not_accepting'),
    'placement_review_required', count(*) filter (where item->>'operational_status' = 'placement_review_required'),
    'inactive',                  count(*) filter (where item->>'operational_status' = 'inactive'),
    'total',                     count(*)
  )
  into v_operational_summary
  from jsonb_array_elements(v_households_summary) item;

  -- 13. Leadership Vacancies
  with vacant_nodes as (
    select
      h_vac.id as governance_node_id,
      gn_vac.name as governance_node_name,
      'household_servant_leader'::text as role_code,
      'Household Servant Leader'::text as role_name,
      'member'::text as pastoral_level
    from public.households h_vac
    join public.governance_nodes gn_vac on gn_vac.id = h_vac.id
    where h_vac.organization_id = p_organization_id
      and h_vac.pastoral_level = 'member'
      and gn_vac.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, h_vac.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = h_vac.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'household_servant_leader'
      )
    union all
    select
      un.id as governance_node_id,
      un.name as governance_node_name,
      'unit_servant_leader'::text as role_code,
      'Unit Servant Leader'::text as role_name,
      'unit'::text as pastoral_level
    from public.governance_nodes un
    join public.governance_node_types unt on unt.id = un.governance_node_type_id and unt.code = 'unit'
    where un.organization_id = p_organization_id
      and un.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, un.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = un.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'unit_servant_leader'
      )
    union all
    select
      chn.id as governance_node_id,
      chn.name as governance_node_name,
      'chapter_servant_leader'::text as role_code,
      'Chapter Servant Leader'::text as role_name,
      'chapter'::text as pastoral_level
    from public.governance_nodes chn
    join public.governance_node_types chnt on chnt.id = chn.governance_node_type_id and chnt.code = 'chapter'
    where chn.organization_id = p_organization_id
      and chn.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, chn.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = chn.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'chapter_servant_leader'
      )
    union all
    select
      arn.id as governance_node_id,
      arn.name as governance_node_name,
      'area_servant_leader'::text as role_code,
      'Area Servant Leader'::text as role_name,
      'area'::text as pastoral_level
    from public.governance_nodes arn
    join public.governance_node_types arnt on arnt.id = arn.governance_node_type_id and arnt.code = 'area_state'
    where arn.organization_id = p_organization_id
      and arn.lifecycle_status = 'active'
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, arn.id)
      and not exists (
        select 1 from public.leadership_assignments la
        join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
        where la.governance_node_id = arn.id
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
          and lrd.code = 'area_servant_leader'
      )
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'governance_node_id',   vn.governance_node_id,
      'governance_node_name', vn.governance_node_name,
      'role_code',            vn.role_code,
      'role_name',            vn.role_name,
      'pastoral_level',       vn.pastoral_level,
      'vacancy_status',       'vacant'
    ) order by
      case vn.pastoral_level
        when 'chapter' then 1
        when 'unit' then 2
        when 'member' then 3
      end,
      vn.governance_node_name
  ), '[]'::jsonb)
  into v_leadership_vacancies
  from vacant_nodes vn;

  -- 14. Placement Review Summary Integration
  if v_can_review_placement then
    declare
      v_search_res jsonb;
    begin
      v_search_res := public.search_servant_leaders_needing_pastoral_placement(
        p_organization_id    => p_organization_id,
        p_include_correct    => false,
        p_limit              => 100,
        p_offset             => 0
      );

      select jsonb_build_object(
        'missing_household',               count(*) filter (where item->>'placement_status' = 'missing_household'),
        'different_level',                 count(*) filter (where item->>'placement_status' = 'different_level'),
        'no_matching_household_available', count(*) filter (where item->>'placement_status' = 'no_matching_household_available'),
        'manual_review_required',          count(*) filter (where item->>'placement_status' = 'manual_review_required'),
        'total',                           coalesce(v_search_res->>'total_count', '0')::integer,
        'actionable_items',                v_search_res->'items'
      )
      into v_placement_summary
      from jsonb_array_elements(coalesce(v_search_res->'items', '[]'::jsonb)) item;

      if v_placement_summary is null then
        v_placement_summary := jsonb_build_object(
          'missing_household', 0,
          'different_level', 0,
          'no_matching_household_available', 0,
          'manual_review_required', 0,
          'total', 0,
          'actionable_items', '[]'::jsonb
        );
      end if;
    end;
  else
    v_placement_summary := jsonb_build_object(
      'missing_household', 0,
      'different_level', 0,
      'no_matching_household_available', 0,
      'manual_review_required', 0,
      'total', 0,
      'actionable_items', '[]'::jsonb
    );
  end if;

  -- 15. Unassigned Members Count
  select count(m.id)
  into v_unassigned_count
  from public.members m
  where m.organization_id = p_organization_id
    and m.record_status = 'active'
    and not exists (
      select 1
      from public.household_memberships hm
      where hm.member_id = m.id
        and hm.organization_id = p_organization_id
        and hm.is_primary = true
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
    )
    and (
      private.can_access_member('leadership.pastoral_dashboard.view', p_organization_id, m.id)
      or private.can_access_member('households.records.view', p_organization_id, m.id)
    );

  -- 16. Meeting Operations Summary
  with scoped_meetings as (
    select hm.*
    from public.household_meetings hm
    where hm.organization_id = p_organization_id
      and (
        v_target_scope_node_id is null
        or hm.household_node_id = v_target_scope_node_id
        or exists (
          select 1 from public.governance_node_relationships gnr
          where gnr.parent_node_id = v_target_scope_node_id
            and gnr.child_node_id = hm.household_node_id
            and gnr.organization_id = p_organization_id
            and gnr.relationship_status = 'active'
        )
      )
      and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, hm.household_node_id)
  )
  select jsonb_build_object(
    'upcoming_meetings', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'scheduled' and meeting_date >= current_date
    ), 0),
    'meetings_this_month', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'completed' and date_trunc('month', meeting_date) = date_trunc('month', current_date)
    ), 0),
    'attendance_pending', coalesce((
      select count(*) from scoped_meetings
      where meeting_status = 'completed'
        and not (
          private.compute_attendance_summary(
            id,
            p_organization_id,
            meeting_date,
            household_node_id
          )->>'attendance_complete'
        )::boolean
    ), 0),
    'households_without_meeting_history', coalesce((
      select count(*) from jsonb_array_elements(v_households_summary) item
      where item->>'last_completed_meeting_date' is null
    ), 0),
    'households_overdue', coalesce((
      select count(*) from jsonb_array_elements(v_households_summary) item
      where item->>'meeting_operational_status' = 'overdue'
    ), 0),
    'member_follow_up_signals', coalesce((
      select count(distinct hm_fu.member_id)
      from public.household_memberships hm_fu
      join public.households h_fu on h_fu.id = hm_fu.household_node_id
      where hm_fu.organization_id   = p_organization_id
        and hm_fu.is_primary        = true
        and hm_fu.membership_status in ('active', 'temporary')
        and hm_fu.effective_from    <= current_date
        and (hm_fu.effective_to is null or hm_fu.effective_to >= current_date)
        and (
          v_target_scope_node_id is null
          or hm_fu.household_node_id = v_target_scope_node_id
          or exists (
            select 1 from public.governance_node_relationships gnr
            where gnr.parent_node_id = v_target_scope_node_id
              and gnr.child_node_id = hm_fu.household_node_id
              and gnr.organization_id = p_organization_id
              and gnr.relationship_status = 'active'
          )
        )
        and private.can_access_governance_node('leadership.pastoral_dashboard.view', p_organization_id, hm_fu.household_node_id)
        and (
          private.get_member_follow_up_signals(
            p_organization_id, hm_fu.member_id, hm_fu.household_node_id
          )->>'multiple_recent_absences'
        )::boolean = true
    ), 0)
  )
  into v_meeting_ops_summary;

  -- 17. Return Unified Operational Dashboard Payload
  return jsonb_build_object(
    'organization_id',            p_organization_id,
    'identity',                   v_identity_json,
    'care_responsibilities',      v_care_responsibilities,
    'household_summary',          v_households_summary,
    'leadership_vacancies',       v_leadership_vacancies,
    'capacity_summary',           v_capacity_summary,
    'operational_summary',        v_operational_summary,
    'placement_review_summary',   v_placement_summary,
    'unassigned_members_count',   coalesce(v_unassigned_count, 0),
    'meeting_operations_summary', coalesce(v_meeting_ops_summary, jsonb_build_object(
      'upcoming_meetings',                  0,
      'meetings_this_month',                0,
      'attendance_pending',                 0,
      'households_without_meeting_history', 0,
      'households_overdue',                 0,
      'member_follow_up_signals',           0
    ))
  );
end;
$$;

revoke all on function public.get_pastoral_operations_dashboard(uuid, uuid) from public, anon;
grant execute on function public.get_pastoral_operations_dashboard(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- SECTION 10: Update get_household_profile & search_households with Non-Admin Double-Lock
-- -----------------------------------------------------------------------------

create or replace function public.get_household_profile(
  p_organization_id uuid,
  p_household_id    uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_has_id_perm  boolean;
  v_profile_data jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('households.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household records.';
  end if;

  -- NON-ADMIN DOUBLE-LOCK REQUIREMENT
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not exists (
      select 1
      from public.servant_leader_access_grants g
      join public.leadership_assignments la on la.id = g.leadership_assignment_id
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
        and g.access_status = 'active'
        and g.effective_from <= current_date
        and (g.effective_to is null or g.effective_to >= current_date)
        and la.organization_id = p_organization_id
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date)
    ) then
      raise exception using errcode = '42501',
        message = 'Active servant leader access grant and current leadership assignment are required.';
    end if;
  end if;

  -- 4. Governance-scoped access check
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  -- 5. Identifier permission for roster member numbers
  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  -- 6. Build profile payload with pastoral echelon derivation
  with household_identity as (
    select
      gn.id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      h.pastoral_level,
      case h.pastoral_level
        when 'member'    then 'Member Household'
        when 'unit'      then 'Unit Household'
        when 'chapter'   then 'Chapter Household'
        when 'area'      then 'Area Household'
        when 'fraternal' then 'Fraternal Household'
        else initcap(h.pastoral_level) || ' Household'
      end as pastoral_level_label,
      case h.pastoral_level
        when 'member'    then 'household_servant_leader'
        when 'unit'      then 'unit_servant_leader'
        when 'chapter'   then 'chapter_servant_leader'
        when 'area'      then 'area_servant_leader'
        when 'fraternal' then 'rotating_facilitation'
      end as leadership_source,
      gn.effective_from,
      gn.effective_to,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      h.meeting_timezone_name,
      h.meeting_location_type,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.language_code,
      h.is_couple_household
    from public.governance_nodes gn
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    where gn.id = p_household_id
      and gn.organization_id = p_organization_id
  ),
  parent_gov as (
    select
      gnr.parent_node_id,
      pgn.name as parent_node_name,
      pgn.code as parent_node_code,
      pgnt.code as parent_node_type
    from public.governance_node_relationships gnr
    join public.governance_nodes pgn
      on pgn.id = gnr.parent_node_id
     and pgn.organization_id = gnr.organization_id
    join public.governance_node_types pgnt
      on pgnt.id = pgn.governance_node_type_id
     and pgnt.organization_id = pgn.organization_id
    where gnr.child_node_id = p_household_id
      and gnr.organization_id = p_organization_id
      and gnr.relationship_type = 'primary_parent'
    order by
      case when gnr.relationship_status = 'active' and gnr.effective_from <= current_date and (gnr.effective_to is null or gnr.effective_to >= current_date) then 0 else 1 end,
      gnr.effective_to desc nulls first,
      gnr.effective_from desc,
      gnr.created_at desc
    limit 1
  ),
  active_members as (
    select
      hm.id as household_membership_id,
      m.id as member_id,
      case
        when v_has_id_perm then m.member_number
        else null
      end as member_number,
      m.display_name,
      hm.membership_status,
      hm.membership_role,
      hm.is_primary,
      hm.effective_from,
      hm.effective_to
    from public.household_memberships hm
    join public.members m
      on m.id = hm.member_id
     and m.organization_id = hm.organization_id
    where hm.household_node_id = p_household_id
      and hm.organization_id = p_organization_id
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
    order by
      case when hm.membership_role in ('servant', 'leader') then 0 else 1 end,
      m.display_name asc
  ),
  derived_leaders as (
    -- Member: from household node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    join public.leadership_assignments la
      on la.governance_node_id = hi.id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'member'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'household_servant_leader'

    union all

    -- Unit: from parent Unit node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'unit'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'unit_servant_leader'

    union all

    -- Chapter: from parent Chapter node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'chapter'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'chapter_servant_leader'

    union all

    -- Area: from parent Area node assignments
    select
      la.id as leadership_assignment_id,
      m.id as member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to
    from household_identity hi
    cross join parent_gov pg
    join public.leadership_assignments la
      on la.governance_node_id = pg.parent_node_id
     and la.organization_id = p_organization_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
     and lrd.organization_id = la.organization_id
    where hi.pastoral_level = 'area'
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and lrd.code = 'area_servant_leader'
  )
  select
    jsonb_build_object(
      'household_id',          hi.id,
      'name',                  hi.name,
      'code',                  hi.code,
      'lifecycle_status',      hi.lifecycle_status,
      'household_category',    hi.household_category,
      'pastoral_level',        hi.pastoral_level,
      'pastoral_level_label',  hi.pastoral_level_label,
      'leadership_source',     hi.leadership_source,
      'effective_from',        hi.effective_from,
      'effective_to',          hi.effective_to,
      'meeting_frequency',     hi.meeting_frequency,
      'meeting_day_of_week',   hi.meeting_day_of_week,
      'meeting_start_time',    hi.meeting_start_time,
      'meeting_timezone_name', hi.meeting_timezone_name,
      'meeting_location_type', hi.meeting_location_type,
      'target_member_count',   hi.target_member_count,
      'maximum_member_count',  hi.maximum_member_count,
      'accepts_new_members',   hi.accepts_new_members,
      'language_code',         hi.language_code,
      'is_couple_household',   hi.is_couple_household,
      'parent_node_id',        pg.parent_node_id,
      'parent_node_name',      pg.parent_node_name,
      'parent_node_code',      pg.parent_node_code,
      'parent_node_type',      pg.parent_node_type,
      'leaders', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'leadership_assignment_id', dl.leadership_assignment_id,
              'member_id',                dl.member_id,
              'display_name',             dl.display_name,
              'leadership_role_code',     dl.leadership_role_code,
              'leadership_role_name',     dl.leadership_role_name,
              'assignment_status',        dl.assignment_status,
              'effective_from',           dl.effective_from,
              'effective_to',             dl.effective_to
            )
          )
          from derived_leaders dl
        ),
        '[]'::jsonb
      ),
      'household_leaders', (
        select jsonb_agg(
          jsonb_build_object(
            'leadership_assignment_id', dl.leadership_assignment_id,
            'member_id',                dl.member_id,
            'display_name',             dl.display_name,
            'role_code',                dl.leadership_role_code,
            'role_name',                dl.leadership_role_name,
            'effective_from',           dl.effective_from,
            'effective_to',             dl.effective_to
          )
        )
        from derived_leaders dl
      ),
      'active_member_count', (select count(*)::integer from active_members),
      'members', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'household_membership_id', am.household_membership_id,
              'member_id',               am.member_id,
              'member_number',           am.member_number,
              'display_name',            am.display_name,
              'membership_status',       am.membership_status,
              'membership_role',         am.membership_role,
              'is_primary',              am.is_primary,
              'effective_from',          am.effective_from,
              'effective_to',            am.effective_to
            )
          )
          from active_members am
        ),
        '[]'::jsonb
      )
    )
  into v_profile_data
  from household_identity hi
  left join parent_gov pg on true;

  return v_profile_data;
end;
$$;

revoke execute on function public.get_household_profile(uuid, uuid) from public, anon;
grant  execute on function public.get_household_profile(uuid, uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- search_households
-- -----------------------------------------------------------------------------
create or replace function public.search_households(
  p_organization_id           uuid,
  p_search                    text    default null,
  p_lifecycle_status          text    default 'active',
  p_parent_governance_node_id uuid    default null,
  p_limit                     integer default 50,
  p_offset                    integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_search_term  text;
  v_limit        integer;
  v_offset       integer;
  v_total_count  integer;
  v_households   jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('households.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household records.';
  end if;

  -- NON-ADMIN DOUBLE-LOCK REQUIREMENT
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not exists (
      select 1
      from public.servant_leader_access_grants g
      join public.leadership_assignments la on la.id = g.leadership_assignment_id
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
        and g.access_status = 'active'
        and g.effective_from <= current_date
        and (g.effective_to is null or g.effective_to >= current_date)
        and la.organization_id = p_organization_id
        and la.assignment_status = 'active'
        and la.effective_from <= current_date
        and (la.effective_to is null or la.effective_to >= current_date)
    ) then
      raise exception using errcode = '42501',
        message = 'Active servant leader access grant and current leadership assignment are required.';
    end if;
  end if;

  -- 4. Sanitize parameters
  v_search_term := nullif(trim(p_search), '');
  v_limit := greatest(1, least(coalesce(p_limit, 50), 100));
  v_offset := greatest(0, coalesce(p_offset, 0));

  -- 5. Query matching scoped households
  with candidate_households as (
    select
      gn.id as household_id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      h.pastoral_level,
      case h.pastoral_level
        when 'member'    then 'Member Household'
        when 'unit'      then 'Unit Household'
        when 'chapter'   then 'Chapter Household'
        when 'area'      then 'Area Household'
        when 'fraternal' then 'Fraternal Household'
        else initcap(h.pastoral_level) || ' Household'
      end as pastoral_level_label,
      h.meeting_frequency,
      h.meeting_day_of_week,
      to_char(h.meeting_start_time, 'HH24:MI:SS') as meeting_start_time,
      h.meeting_timezone_name,
      h.meeting_location_type,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      p_gov.parent_node_id,
      p_gov.parent_node_name,
      p_gov.parent_node_code,
      p_gov.parent_node_type,
      coalesce(m_cnt.cnt, 0) as active_member_count
    from public.governance_nodes gn
    join public.governance_node_types gnt
      on gnt.id = gn.governance_node_type_id
     and gnt.organization_id = gn.organization_id
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    left join lateral (
      select
        gn_p.id as parent_node_id,
        gn_p.name as parent_node_name,
        gn_p.code as parent_node_code,
        gnt_p.code as parent_node_type
      from public.governance_node_relationships r
      join public.governance_nodes gn_p
        on gn_p.id = r.parent_node_id
       and gn_p.organization_id = r.organization_id
      join public.governance_node_types gnt_p
        on gnt_p.id = gn_p.governance_node_type_id
       and gnt_p.organization_id = gn_p.organization_id
      where r.organization_id = p_organization_id
        and r.child_node_id = gn.id
        and r.relationship_type = 'primary_parent'
        and r.relationship_status = 'active'
        and r.effective_from <= current_date
        and (r.effective_to is null or r.effective_to >= current_date)
      order by r.created_at desc
      limit 1
    ) p_gov on true
    left join lateral (
      select count(*)::integer as cnt
      from public.household_memberships hm
      where hm.organization_id = p_organization_id
        and hm.household_node_id = gn.id
        and hm.membership_status in ('active', 'temporary')
        and hm.effective_from <= current_date
        and (hm.effective_to is null or hm.effective_to >= current_date)
        and hm.is_primary = true
    ) m_cnt on true
    where gn.organization_id = p_organization_id
      and gnt.code = 'household'
      and (
        p_lifecycle_status is null
        or p_lifecycle_status = 'all'
        or gn.lifecycle_status = p_lifecycle_status
      )
      and (
        p_parent_governance_node_id is null
        or p_gov.parent_node_id = p_parent_governance_node_id
      )
      and (
        v_search_term is null
        or gn.name ilike '%' || v_search_term || '%'
        or gn.code ilike '%' || v_search_term || '%'
      )
      and private.can_access_household('households.records.view', p_organization_id, gn.id)
  ),
  total_c as (
    select count(*)::integer as total from candidate_households
  ),
  paginated as (
    select * from candidate_households
    order by name asc, code asc
    limit v_limit
    offset v_offset
  )
  select
    coalesce((select total from total_c), 0),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'household_id',          p.household_id,
          'name',                  p.name,
          'code',                  p.code,
          'lifecycle_status',      p.lifecycle_status,
          'household_category',    p.household_category,
          'pastoral_level',        p.pastoral_level,
          'pastoral_level_label',  p.pastoral_level_label,
          'parent_node_id',        p.parent_node_id,
          'parent_node_name',      p.parent_node_name,
          'parent_node_code',      p.parent_node_code,
          'parent_node_type',      p.parent_node_type,
          'active_member_count',   p.active_member_count,
          'target_member_count',   p.target_member_count,
          'maximum_member_count',  p.maximum_member_count,
          'accepts_new_members',   p.accepts_new_members,
          'meeting_frequency',     p.meeting_frequency,
          'meeting_day_of_week',   p.meeting_day_of_week,
          'meeting_start_time',    p.meeting_start_time,
          'meeting_timezone_name', p.meeting_timezone_name,
          'meeting_location_type', p.meeting_location_type
        )
      ),
      '[]'::jsonb
    )
  into v_total_count, v_households
  from paginated p;

  return jsonb_build_object(
    'organization_id', p_organization_id,
    'total_count',     v_total_count,
    'limit',           v_limit,
    'offset',          v_offset,
    'households',      v_households
  );
end;
$$;

revoke execute on function public.search_households(uuid, text, text, uuid, integer, integer) from public, anon;
grant  execute on function public.search_households(uuid, text, text, uuid, integer, integer) to authenticated, service_role;

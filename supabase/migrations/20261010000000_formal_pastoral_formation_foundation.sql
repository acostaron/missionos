-- =============================================================================
-- Migration: 20261010000000_formal_pastoral_formation_foundation.sql
-- Phase:     Stage 3A — Formal Pastoral Formation (Pass 3A-2B)
-- Purpose:   Create the Formal Pastoral Formation schema foundation:
--            1. Tables: formation_programs, formation_talks,
--               formation_program_requirements, member_formation_program_records,
--               member_formation_talk_records
--            2. Relational integrity constraints & partial unique indexes
--            3. Composite foreign key protections across talk/program/member/org
--            4. Strict date precision constraints for truthful historical dates
--            5. Default-deny Row Level Security (RLS) on all 5 tables
--            6. Register canonical 'formation' permission catalog
--            7. Initial role-permission grants for Organization Administrator,
--               Formation Coordinator, and delegated pastoral access roles
-- Note:      ZERO curriculum seed rows inserted in this migration.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Table: formation_programs
--    Canonical Formal Formation program/course identity and edition.
-- -----------------------------------------------------------------------------

create table if not exists public.formation_programs (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid null references public.organizations(id) on delete restrict,
  code                  text not null,
  title                 text not null,
  edition               text not null default 'current',
  program_category      text not null check (
    program_category in ('pastoral_formation', 'leadership_training', 'ministry_skills')
  ),
  program_type          text not null check (
    program_type in ('entry_seminar', 'recollection', 'retreat', 'course', 'training_workshop')
  ),
  description           text null,
  sequence_order        integer null,
  is_active             boolean not null default true,
  effective_from        date null,
  effective_to          date null,
  retired_at            timestamptz null,

  source_document       text null,
  source_url            text null,
  source_verified_at    date null,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint chk_formation_programs_effective_dates check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  ),
  constraint chk_formation_programs_retirement check (
    (retired_at is null and is_active = true) or
    (retired_at is not null and is_active = false) or
    (retired_at is null and is_active = false)
  )
);

-- Global uniqueness: (code, edition) where organization_id IS NULL
create unique index if not exists uq_formation_programs_global
  on public.formation_programs (lower(trim(code)), lower(trim(edition)))
  where organization_id is null;

-- Organization-scoped uniqueness: (organization_id, code, edition) where organization_id IS NOT NULL
create unique index if not exists uq_formation_programs_org
  on public.formation_programs (organization_id, lower(trim(code)), lower(trim(edition)))
  where organization_id is not null;

create index if not exists idx_formation_programs_category
  on public.formation_programs (program_category, sequence_order);

create index if not exists idx_formation_programs_org_active
  on public.formation_programs (organization_id, is_active);


-- -----------------------------------------------------------------------------
-- 2. Table: formation_talks
--    Discrete talk/session deliveries belonging to a formation program.
-- -----------------------------------------------------------------------------

create table if not exists public.formation_talks (
  id                    uuid primary key default gen_random_uuid(),
  program_id            uuid not null references public.formation_programs(id) on delete restrict,
  talk_code             text not null,
  title                 text not null,
  session_label         text null,
  sequence_order        integer not null check (sequence_order > 0),
  description           text null,
  is_required           boolean not null default true,
  is_active             boolean not null default true,
  effective_from        date null,
  effective_to          date null,
  retired_at            timestamptz null,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint uq_formation_talks_program_code unique (program_id, talk_code),
  constraint uq_formation_talks_program_sequence unique (program_id, sequence_order),
  constraint uq_formation_talks_id_program unique (id, program_id),
  constraint chk_formation_talks_effective_dates check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  )
);

create index if not exists idx_formation_talks_program
  on public.formation_talks (program_id, sequence_order);


-- -----------------------------------------------------------------------------
-- 3. Table: formation_program_requirements
--    Normalized audience, pastoral office, and timing requirement rules.
-- -----------------------------------------------------------------------------

create table if not exists public.formation_program_requirements (
  id                    uuid primary key default gen_random_uuid(),
  program_id            uuid not null references public.formation_programs(id) on delete restrict,
  target_audience       text not null check (
    target_audience in (
      'all_members',
      'couples',
      'singles',
      'handmaids',
      'servants',
      'youth',
      'household_servants',
      'unit_servants_above',
      'chapter_servants',
      'service_team'
    )
  ),
  is_mandatory          boolean not null default true,
  timing_norm           text null,
  notes                 text null,
  valid_from            date null,
  valid_to              date null,
  is_active             boolean not null default true,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint chk_formation_req_valid_dates check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

-- Prevent duplicate active rules for same program and audience
create unique index if not exists uq_formation_program_req_active
  on public.formation_program_requirements (program_id, target_audience)
  where is_active = true and valid_to is null;

create index if not exists idx_formation_program_req_program
  on public.formation_program_requirements (program_id, is_active);


-- -----------------------------------------------------------------------------
-- 4. Table: member_formation_program_records
--    Member participation, completion, and waiver ledger for a program attempt.
-- -----------------------------------------------------------------------------

create table if not exists public.member_formation_program_records (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references public.organizations(id) on delete restrict,
  member_id             uuid not null references public.members(id) on delete restrict,
  program_id            uuid not null references public.formation_programs(id) on delete restrict,
  attempt_number        integer not null default 1 check (attempt_number >= 1),

  status                text not null check (
    status in ('in_progress', 'completed', 'waived')
  ),
  record_status         text not null default 'active' check (
    record_status in ('active', 'superseded', 'voided')
  ),

  completed_date        date null,
  completed_year        smallint null check (completed_year is null or (completed_year >= 1950 and completed_year <= 2100)),
  completed_month       smallint null check (completed_month is null or (completed_month >= 1 and completed_month <= 12)),
  date_precision        text not null default 'unknown' check (
    date_precision in ('exact_date', 'month_year', 'year_only', 'approximate', 'unknown')
  ),

  verification_method   text not null check (
    verification_method in ('leader_attestation', 'attendance_roll', 'historical_backfill', 'pastoral_waiver')
  ),
  source_reference      text null,

  recorded_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  recorded_at           timestamptz not null default now(),

  verified_by_profile_id uuid null references public.profiles(id) on delete set null,
  verified_at           timestamptz null,
  verification_notes    text null,

  voided_at             timestamptz null,
  voided_by_profile_id  uuid null references public.profiles(id) on delete set null,
  void_reason           text null,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  -- Composite uniqueness support for declarative child referencing
  constraint uq_member_prog_rec_scope unique (id, organization_id, member_id, program_id),

  -- Date precision integrity rules
  constraint chk_member_prog_rec_dates check (
    (date_precision = 'exact_date' and completed_date is not null) or
    (date_precision = 'month_year' and completed_year is not null and completed_month is not null and completed_date is null) or
    (date_precision = 'year_only' and completed_year is not null and completed_month is null and completed_date is null) or
    (date_precision = 'approximate' and (completed_year is not null or completed_date is not null)) or
    (date_precision = 'unknown' and completed_date is null)
  ),

  -- Void status integrity
  constraint chk_member_prog_rec_void check (
    (record_status = 'voided' and voided_at is not null) or
    (record_status <> 'voided' and voided_at is null)
  )
);

-- At most one active in-progress attempt per member per program
create unique index if not exists uq_member_prog_active_in_progress
  on public.member_formation_program_records (organization_id, member_id, program_id)
  where record_status = 'active' and status = 'in_progress';

-- Unique attempt numbers among active records
create unique index if not exists uq_member_prog_active_attempt
  on public.member_formation_program_records (member_id, program_id, attempt_number)
  where record_status = 'active';

create index if not exists idx_member_prog_rec_member
  on public.member_formation_program_records (member_id, record_status, status);

create index if not exists idx_member_prog_rec_org
  on public.member_formation_program_records (organization_id, program_id);


-- -----------------------------------------------------------------------------
-- 5. Table: member_formation_talk_records
--    Granular attendance/completion records for individual talks.
-- -----------------------------------------------------------------------------

create table if not exists public.member_formation_talk_records (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references public.organizations(id) on delete restrict,
  member_id             uuid not null references public.members(id) on delete restrict,
  program_id            uuid not null references public.formation_programs(id) on delete restrict,
  program_record_id     uuid not null,
  talk_id               uuid not null,

  session_status        text not null check (
    session_status in ('attended', 'absent_excused', 'makeup_attended', 'waived')
  ),
  attended_date         date null,
  record_status         text not null default 'active' check (
    record_status in ('active', 'voided')
  ),

  recorded_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  recorded_at           timestamptz not null default now(),

  notes                 text null,

  voided_at             timestamptz null,
  voided_by_profile_id  uuid null references public.profiles(id) on delete set null,
  void_reason           text null,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  -- Declarative relational integrity guaranteeing talk belongs to same program
  -- and member/org match the parent program attempt record
  constraint fk_member_talk_parent_attempt foreign key (
    program_record_id, organization_id, member_id, program_id
  ) references public.member_formation_program_records (
    id, organization_id, member_id, program_id
  ) on delete restrict,

  constraint fk_member_talk_parent_talk foreign key (
    talk_id, program_id
  ) references public.formation_talks (
    id, program_id
  ) on delete restrict,

  -- Void status integrity
  constraint chk_member_talk_rec_void check (
    (record_status = 'voided' and voided_at is not null) or
    (record_status <> 'voided' and voided_at is null)
  )
);

-- At most one active talk record per program attempt per talk
create unique index if not exists uq_member_talk_active_attempt
  on public.member_formation_talk_records (program_record_id, talk_id)
  where record_status = 'active';

create index if not exists idx_member_talk_rec_member
  on public.member_formation_talk_records (member_id, talk_id);

create index if not exists idx_member_talk_rec_attempt
  on public.member_formation_talk_records (program_record_id);


-- -----------------------------------------------------------------------------
-- 6. Row Level Security (RLS) Enablement
--    Default-deny on all five tables. All client access is mediated by RPCs.
-- -----------------------------------------------------------------------------

alter table public.formation_programs enable row level security;
alter table public.formation_talks enable row level security;
alter table public.formation_program_requirements enable row level security;
alter table public.member_formation_program_records enable row level security;
alter table public.member_formation_talk_records enable row level security;


-- -----------------------------------------------------------------------------
-- 7. Register Formation Permission Catalog
-- -----------------------------------------------------------------------------

insert into public.permissions (
  code, name, description, domain_code, action_code, scope_type,
  risk_level, requires_access_reason, requires_access_logging, is_active
)
values
  (
    'formation.catalog.view',
    'View formation curriculum catalog',
    'Allows viewing the official formation programs, talks, and requirements catalog.',
    'formation',
    'view',
    'organization',
    'standard',
    false,
    false,
    true
  ),
  (
    'formation.catalog.manage',
    'Manage formation curriculum catalog',
    'Allows creating, editing, and retiring formation programs, talks, and requirement rules.',
    'formation',
    'manage',
    'organization',
    'high',
    true,
    true,
    true
  ),
  (
    'formation.records.view',
    'View member formation records',
    'Allows reading member pastoral formation completions and transcripts within authorized pastoral or administrative scope.',
    'formation',
    'view',
    'governance',
    'standard',
    false,
    false,
    true
  ),
  (
    'formation.records.record',
    'Record member formation completion',
    'Allows attesting and recording formation course completions and talk attendances for members within authorized scope.',
    'formation',
    'record',
    'governance',
    'high',
    true,
    true,
    true
  ),
  (
    'formation.records.correct',
    'Correct or void member formation records',
    'Allows correcting mistakes or voiding erroneous formation records with mandatory audit reason.',
    'formation',
    'correct',
    'organization',
    'critical',
    true,
    true,
    true
  )
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  domain_code = excluded.domain_code,
  action_code = excluded.action_code,
  scope_type = excluded.scope_type,
  risk_level = excluded.risk_level,
  requires_access_reason = excluded.requires_access_reason,
  requires_access_logging = excluded.requires_access_logging,
  is_active = excluded.is_active;


-- -----------------------------------------------------------------------------
-- 8. Initial Role-Permission Grants
--    Follows principle: FORMAL LEADERSHIP != SOFTWARE AUTHORIZATION.
-- -----------------------------------------------------------------------------

-- 8a. Organization Administrator: all 5 formation permissions
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
  and p.code in (
    'formation.catalog.view',
    'formation.catalog.manage',
    'formation.records.view',
    'formation.records.record',
    'formation.records.correct'
  )
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

-- 8b. Formation Coordinator: catalog manage + records record (no correct)
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
where r.code = 'formation_coordinator'
  and r.is_system_role
  and p.code in (
    'formation.catalog.view',
    'formation.catalog.manage',
    'formation.records.view',
    'formation.records.record'
  )
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

-- 8c. Delegated pastoral access roles: read-only catalog & records
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
where r.code in (
    'household_servant_leader_access',
    'unit_servant_leader_access',
    'chapter_servant_leader_access',
    'area_servant_leader_access'
  )
  and r.is_system_role
  and p.code in (
    'formation.catalog.view',
    'formation.records.view'
  )
  and not exists (
    select 1 from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

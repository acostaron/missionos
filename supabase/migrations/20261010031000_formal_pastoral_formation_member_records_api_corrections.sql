-- =============================================================================
-- Migration: 20261010031000_formal_pastoral_formation_member_records_api_corrections.sql
-- Phase:     Stage 3A — Formal Pastoral Formation (Pass 3A-4A)
-- Purpose:   Reconcile Verifier Provenance Rule (Rule B):
--            - Drop old 12-argument record_member_formation_program that accepted
--              browser-supplied p_verified_by_profile_id.
--            - Re-create record_member_formation_program with clean 11-argument
--              signature, strictly deriving verified_by_profile_id = actor_profile_id
--              when verification_method IN ('leader_attestation', 'pastoral_waiver'),
--              and NULL when ('historical_backfill', 'attendance_roll').
--            - Prevent browser from ever spoofing verifier identity.
--            - Reaffirm execution privileges for authenticated role.
-- Notes:     - Forward-only correction per Migration Immutability Rule.
--            - Zero changes to tables or curriculum.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Drop old record_member_formation_program signature
-- -----------------------------------------------------------------------------
drop function if exists public.record_member_formation_program(
  uuid, uuid, uuid, text, date, smallint, smallint, text, text, text, text, uuid
);

-- -----------------------------------------------------------------------------
-- 2. Re-create public.record_member_formation_program (clean 11-parameter contract)
-- -----------------------------------------------------------------------------
create or replace function public.record_member_formation_program(
  p_organization_id        uuid,
  p_member_id              uuid,
  p_program_id             uuid,
  p_status                 text,
  p_completed_date         date default null,
  p_completed_year         smallint default null,
  p_completed_month        smallint default null,
  p_date_precision         text default 'unknown',
  p_verification_method    text default 'leader_attestation',
  p_source_reference       text default null,
  p_verification_notes     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor_profile_id       uuid;
  v_program                record;
  v_attempt_number         integer;
  v_verified_by_id         uuid;
  v_verified_at            timestamptz;
  v_record                 public.member_formation_program_records%rowtype;
begin
  -- 1. Authentication check
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Required parameter validations
  if p_organization_id is null or p_member_id is null or p_program_id is null or p_status is null then
    raise exception using errcode = '22023', message = 'Organization ID, Member ID, Program ID, and Status are required.';
  end if;

  -- 3. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 4. Member validation: member must belong to requested organization
  if not exists (
    select 1 from public.members
    where id = p_member_id and organization_id = p_organization_id
  ) then
    raise exception using errcode = 'P0002', message = 'Member not found in the specified organization.';
  end if;

  -- 5. Authorization: caller must have formation.records.record and scope over the member
  if not private.can_access_member('formation.records.record', p_organization_id, p_member_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to record formation records for this member.';
  end if;

  -- 6. Program validation: global curriculum or local curriculum for caller organization
  select * into v_program
  from public.formation_programs
  where id = p_program_id
    and (organization_id is null or organization_id = p_organization_id);

  if not found then
    raise exception using errcode = 'P0002', message = 'Formation program not found or belongs to another organization.';
  end if;

  -- 7. Status validation
  if p_status not in ('in_progress', 'completed', 'waived') then
    raise exception using errcode = '22023', message = 'Invalid formation program status. Must be in_progress, completed, or waived.';
  end if;

  -- 8. Verification method validation
  if p_verification_method not in ('leader_attestation', 'attendance_roll', 'historical_backfill', 'pastoral_waiver') then
    raise exception using errcode = '22023', message = 'Invalid verification method.';
  end if;

  -- 9. Date precision validation
  if p_date_precision not in ('exact_date', 'month_year', 'year_only', 'approximate', 'unknown') then
    raise exception using errcode = '22023', message = 'Invalid date precision.';
  end if;

  -- 10. Completed year/month bounds
  if p_completed_year is not null and (p_completed_year < 1950 or p_completed_year > 2100) then
    raise exception using errcode = '22023', message = 'completed_year must be between 1950 and 2100.';
  end if;

  if p_completed_month is not null and (p_completed_month < 1 or p_completed_month > 12) then
    raise exception using errcode = '22023', message = 'completed_month must be between 1 and 12.';
  end if;

  -- 11. Historical date truth validation matching chk_member_prog_rec_dates
  if p_date_precision = 'exact_date' then
    if p_completed_date is null then
      raise exception using errcode = '22023', message = 'completed_date is required when date_precision is exact_date.';
    end if;
  elsif p_date_precision = 'month_year' then
    if p_completed_year is null or p_completed_month is null or p_completed_date is not null then
      raise exception using errcode = '22023', message = 'completed_year and completed_month are required, and completed_date must be null when date_precision is month_year.';
    end if;
  elsif p_date_precision = 'year_only' then
    if p_completed_year is null or p_completed_month is not null or p_completed_date is not null then
      raise exception using errcode = '22023', message = 'completed_year is required, and completed_month and completed_date must be null when date_precision is year_only.';
    end if;
  elsif p_date_precision = 'approximate' then
    if p_completed_year is null and p_completed_date is null then
      raise exception using errcode = '22023', message = 'Either completed_year or completed_date is required when date_precision is approximate.';
    end if;
  elsif p_date_precision = 'unknown' then
    if p_completed_date is not null then
      raise exception using errcode = '22023', message = 'completed_date must be null when date_precision is unknown.';
    end if;
  end if;

  -- 12. In-progress constraint check: at most one active in-progress record per program
  if p_status = 'in_progress' then
    if exists (
      select 1 from public.member_formation_program_records
      where organization_id = p_organization_id
        and member_id = p_member_id
        and program_id = p_program_id
        and record_status = 'active'
        and status = 'in_progress'
    ) then
      raise exception using errcode = '23505', message = 'An active in-progress record already exists for this program.';
    end if;
  end if;

  -- 13. Verifier resolution (Rule B: authenticated caller is the sole personal verifier)
  -- Third-party verifier attribution cannot be spoofed from browser input.
  if p_verification_method in ('leader_attestation', 'pastoral_waiver') then
    v_verified_by_id := v_actor_profile_id;
    v_verified_at := now();
  else
    v_verified_by_id := null;
    v_verified_at := null;
  end if;

  -- 14. Concurrency-safe attempt number allocation
  perform pg_advisory_xact_lock(hashtext('member_formation_attempt_' || p_member_id::text || '_' || p_program_id::text));

  select coalesce(max(attempt_number), 0) + 1
  into v_attempt_number
  from public.member_formation_program_records
  where member_id = p_member_id
    and program_id = p_program_id;

  -- 15. Insert program record
  insert into public.member_formation_program_records (
    organization_id,
    member_id,
    program_id,
    attempt_number,
    status,
    record_status,
    completed_date,
    completed_year,
    completed_month,
    date_precision,
    verification_method,
    source_reference,
    recorded_by_profile_id,
    recorded_at,
    verified_by_profile_id,
    verified_at,
    verification_notes
  ) values (
    p_organization_id,
    p_member_id,
    p_program_id,
    v_attempt_number,
    p_status,
    'active',
    p_completed_date,
    p_completed_year,
    p_completed_month,
    p_date_precision,
    p_verification_method,
    nullif(trim(p_source_reference), ''),
    v_actor_profile_id,
    now(),
    v_verified_by_id,
    v_verified_at,
    nullif(trim(p_verification_notes), '')
  )
  returning * into v_record;

  -- 16. Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'formation.program_record.recorded',
    p_event_category   => 'formation',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'member_formation_program_record',
    p_entity_id        => v_record.id,
    p_action           => 'record',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'organization_id',     p_organization_id,
      'member_id',           p_member_id,
      'program_id',          p_program_id,
      'program_record_id',   v_record.id,
      'attempt_number',      v_record.attempt_number,
      'status',              v_record.status,
      'verification_method', v_record.verification_method
    )
  );

  -- 17. Return stable typed result
  return jsonb_build_object(
    'id', v_record.id,
    'organization_id', v_record.organization_id,
    'member_id', v_record.member_id,
    'program_id', v_record.program_id,
    'attempt_number', v_record.attempt_number,
    'status', v_record.status,
    'record_status', v_record.record_status,
    'completed_date', v_record.completed_date,
    'completed_year', v_record.completed_year,
    'completed_month', v_record.completed_month,
    'date_precision', v_record.date_precision,
    'verification_method', v_record.verification_method,
    'source_reference', v_record.source_reference,
    'recorded_at', v_record.recorded_at,
    'verified_at', v_record.verified_at
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Execute privilege hardening
-- -----------------------------------------------------------------------------
revoke all on function public.record_member_formation_program(
  uuid, uuid, uuid, text, date, smallint, smallint, text, text, text, text
) from public;

revoke all on function public.record_member_formation_program(
  uuid, uuid, uuid, text, date, smallint, smallint, text, text, text, text
) from anon;

grant execute on function public.record_member_formation_program(
  uuid, uuid, uuid, text, date, smallint, smallint, text, text, text, text
) to authenticated;

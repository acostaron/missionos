-- =============================================================================
-- Migration: 20261010030000_formal_pastoral_formation_member_records_api.sql
-- Phase:     Stage 3A — Formal Pastoral Formation (Pass 3A-4)
-- Purpose:   Implement Member Formation Record APIs + Transcript Reads:
--            1. public.record_member_formation_program(...)
--            2. public.record_member_formation_talk(...)
--            3. public.void_member_formation_program_record(...)
--            4. public.void_member_formation_talk_record(...)
--            5. public.get_member_formation_transcript(...)
--            6. public.get_my_formation_transcript(...)
-- Notes:     - SECURITY DEFINER with search_path = pg_catalog, public, private, auth
--            - Concurrency-safe attempt allocation & talk duplicate prevention
--            - Truthful date precision handling (exact_date, month_year, year_only, etc.)
--            - Strict pastoral/governance scope checks via private.can_access_member
--            - Self-service transcript via private.assert_member_self_service
--            - Atomic cascade voiding of child talks on program void
--            - Audit logging with category 'formation'
--            - ZERO table policies added (RLS default-deny preserved)
--            - Zero references to household formation topics
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. RPC: public.record_member_formation_program
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
  p_verification_notes     text default null,
  p_verified_by_profile_id uuid default null
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

  -- 13. Verifier resolution
  if p_verified_by_profile_id is not null then
    if not exists (select 1 from public.profiles where id = p_verified_by_profile_id) then
      raise exception using errcode = 'P0002', message = 'Verifier profile not found.';
    end if;
    v_verified_by_id := p_verified_by_profile_id;
    v_verified_at := now();
  elsif p_verification_method in ('leader_attestation', 'pastoral_waiver') then
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
-- 2. RPC: public.record_member_formation_talk
-- -----------------------------------------------------------------------------

create or replace function public.record_member_formation_talk(
  p_organization_id   uuid,
  p_program_record_id uuid,
  p_talk_id           uuid,
  p_session_status    text,
  p_attended_date     date default null,
  p_notes             text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor_profile_id  uuid;
  v_prog_record       record;
  v_talk              record;
  v_talk_record       public.member_formation_talk_records%rowtype;
begin
  -- 1. Authentication check
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Required parameter validations
  if p_organization_id is null or p_program_record_id is null or p_talk_id is null or p_session_status is null then
    raise exception using errcode = '22023', message = 'Organization ID, Program Record ID, Talk ID, and Session Status are required.';
  end if;

  -- 3. Load parent program record and verify organization
  select * into v_prog_record
  from public.member_formation_program_records
  where id = p_program_record_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Parent formation program record not found.';
  end if;

  if v_prog_record.organization_id <> p_organization_id then
    raise exception using errcode = '42501', message = 'Organization mismatch on parent program record.';
  end if;

  if v_prog_record.record_status = 'voided' then
    raise exception using errcode = '22023', message = 'Cannot record talk participation for a voided program record.';
  end if;

  -- 4. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 5. Authorization: caller must have formation.records.record and scope over the member
  if not private.can_access_member('formation.records.record', p_organization_id, v_prog_record.member_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to record formation records for this member.';
  end if;

  -- 6. Talk validation: talk must belong to the exact program of the parent record
  select * into v_talk
  from public.formation_talks
  where id = p_talk_id
    and program_id = v_prog_record.program_id;

  if not found then
    raise exception using errcode = '22023', message = 'Formation talk does not belong to the program of this record.';
  end if;

  -- 7. Session status validation
  if p_session_status not in ('attended', 'absent_excused', 'makeup_attended', 'waived') then
    raise exception using errcode = '22023', message = 'Invalid session status. Must be attended, absent_excused, makeup_attended, or waived.';
  end if;

  -- 8. Concurrency-safe duplicate check: at most one active record per attempt per talk
  perform pg_advisory_xact_lock(hashtext('member_formation_talk_' || p_program_record_id::text || '_' || p_talk_id::text));

  if exists (
    select 1 from public.member_formation_talk_records
    where program_record_id = p_program_record_id
      and talk_id = p_talk_id
      and record_status = 'active'
  ) then
    raise exception using errcode = '23505', message = 'An active talk record already exists for this talk in this program attempt.';
  end if;

  -- 9. Insert talk record
  insert into public.member_formation_talk_records (
    organization_id,
    member_id,
    program_id,
    program_record_id,
    talk_id,
    session_status,
    attended_date,
    record_status,
    recorded_by_profile_id,
    recorded_at,
    notes
  ) values (
    p_organization_id,
    v_prog_record.member_id,
    v_prog_record.program_id,
    p_program_record_id,
    p_talk_id,
    p_session_status,
    p_attended_date,
    'active',
    v_actor_profile_id,
    now(),
    nullif(trim(p_notes), '')
  )
  returning * into v_talk_record;

  -- 10. Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'formation.talk_record.recorded',
    p_event_category   => 'formation',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'member_formation_talk_record',
    p_entity_id        => v_talk_record.id,
    p_action           => 'record',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'organization_id',   p_organization_id,
      'member_id',         v_prog_record.member_id,
      'program_id',        v_prog_record.program_id,
      'program_record_id', p_program_record_id,
      'talk_id',           p_talk_id,
      'talk_record_id',    v_talk_record.id,
      'session_status',    p_session_status
    )
  );

  -- 11. Return stable typed result
  return jsonb_build_object(
    'id', v_talk_record.id,
    'organization_id', v_talk_record.organization_id,
    'member_id', v_talk_record.member_id,
    'program_id', v_talk_record.program_id,
    'program_record_id', v_talk_record.program_record_id,
    'talk_id', v_talk_record.talk_id,
    'session_status', v_talk_record.session_status,
    'attended_date', v_talk_record.attended_date,
    'record_status', v_talk_record.record_status,
    'recorded_at', v_talk_record.recorded_at
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 3. RPC: public.void_member_formation_program_record
-- -----------------------------------------------------------------------------

create or replace function public.void_member_formation_program_record(
  p_organization_id uuid,
  p_record_id       uuid,
  p_void_reason     text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor_profile_id uuid;
  v_prog_record      record;
  v_cascade_count    integer := 0;
begin
  -- 1. Authentication check
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Required parameter validations
  if p_organization_id is null or p_record_id is null then
    raise exception using errcode = '22023', message = 'Organization ID and Record ID are required.';
  end if;

  if nullif(trim(p_void_reason), '') is null then
    raise exception using errcode = '22023', message = 'Void reason is required.';
  end if;

  -- 3. Load record and check organization
  select * into v_prog_record
  from public.member_formation_program_records
  where id = p_record_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Formation program record not found.';
  end if;

  if v_prog_record.organization_id <> p_organization_id then
    raise exception using errcode = '42501', message = 'Organization mismatch on program record.';
  end if;

  -- 4. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 5. Authorization: caller must have formation.records.correct and scope over the member
  if not private.can_access_member('formation.records.correct', p_organization_id, v_prog_record.member_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to correct formation records for this member.';
  end if;

  -- 6. Idempotency / state validation
  if v_prog_record.record_status = 'voided' then
    raise exception using errcode = '22023', message = 'Record is already voided.';
  end if;

  -- 7. Update program record
  update public.member_formation_program_records
  set record_status = 'voided',
      voided_at = now(),
      voided_by_profile_id = v_actor_profile_id,
      void_reason = trim(p_void_reason),
      updated_at = now()
  where id = p_record_id
  returning * into v_prog_record;

  -- 8. Atomically cascade void all active child talk records
  with updated as (
    update public.member_formation_talk_records
    set record_status = 'voided',
        voided_at = now(),
        voided_by_profile_id = v_actor_profile_id,
        void_reason = 'Cascade voided with parent program record: ' || trim(p_void_reason),
        updated_at = now()
    where program_record_id = p_record_id
      and record_status = 'active'
    returning id
  )
  select count(*) into v_cascade_count from updated;

  -- 9. Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'formation.program_record.voided',
    p_event_category   => 'formation',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'member_formation_program_record',
    p_entity_id        => p_record_id,
    p_action           => 'void',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'organization_id',          p_organization_id,
      'member_id',                v_prog_record.member_id,
      'program_id',               v_prog_record.program_id,
      'program_record_id',        p_record_id,
      'void_reason',              trim(p_void_reason),
      'cascade_voided_talk_count', v_cascade_count
    )
  );

  -- 10. Return result
  return jsonb_build_object(
    'id', v_prog_record.id,
    'record_status', v_prog_record.record_status,
    'voided_at', v_prog_record.voided_at,
    'void_reason', v_prog_record.void_reason,
    'cascade_voided_talk_count', v_cascade_count
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 4. RPC: public.void_member_formation_talk_record
-- -----------------------------------------------------------------------------

create or replace function public.void_member_formation_talk_record(
  p_organization_id uuid,
  p_talk_record_id  uuid,
  p_void_reason     text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_actor_profile_id uuid;
  v_talk_record      record;
begin
  -- 1. Authentication check
  v_actor_profile_id := private.current_profile_id();
  if v_actor_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Required parameter validations
  if p_organization_id is null or p_talk_record_id is null then
    raise exception using errcode = '22023', message = 'Organization ID and Talk Record ID are required.';
  end if;

  if nullif(trim(p_void_reason), '') is null then
    raise exception using errcode = '22023', message = 'Void reason is required.';
  end if;

  -- 3. Load record and check organization
  select * into v_talk_record
  from public.member_formation_talk_records
  where id = p_talk_record_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Formation talk record not found.';
  end if;

  if v_talk_record.organization_id <> p_organization_id then
    raise exception using errcode = '42501', message = 'Organization mismatch on talk record.';
  end if;

  -- 4. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 5. Authorization: caller must have formation.records.correct and scope over the member
  if not private.can_access_member('formation.records.correct', p_organization_id, v_talk_record.member_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to correct formation records for this member.';
  end if;

  -- 6. Idempotency / state validation
  if v_talk_record.record_status = 'voided' then
    raise exception using errcode = '22023', message = 'Talk record is already voided.';
  end if;

  -- 7. Update talk record
  update public.member_formation_talk_records
  set record_status = 'voided',
      voided_at = now(),
      voided_by_profile_id = v_actor_profile_id,
      void_reason = trim(p_void_reason),
      updated_at = now()
  where id = p_talk_record_id
  returning * into v_talk_record;

  -- 8. Audit event recording
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'formation.talk_record.voided',
    p_event_category   => 'formation',
    p_actor_profile_id => v_actor_profile_id,
    p_entity_type      => 'member_formation_talk_record',
    p_entity_id        => p_talk_record_id,
    p_action           => 'void',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'organization_id',   p_organization_id,
      'member_id',         v_talk_record.member_id,
      'program_id',        v_talk_record.program_id,
      'program_record_id', v_talk_record.program_record_id,
      'talk_id',           v_talk_record.talk_id,
      'talk_record_id',    p_talk_record_id,
      'void_reason',       trim(p_void_reason)
    )
  );

  -- 9. Return result
  return jsonb_build_object(
    'id', v_talk_record.id,
    'record_status', v_talk_record.record_status,
    'voided_at', v_talk_record.voided_at,
    'void_reason', v_talk_record.void_reason
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 5. RPC: public.get_member_formation_transcript
-- -----------------------------------------------------------------------------

create or replace function public.get_member_formation_transcript(
  p_organization_id uuid,
  p_member_id       uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id          uuid;
  v_member_summary      jsonb;
  v_programs            jsonb := '[]'::jsonb;
  v_rec                 record;
  v_talks               jsonb;
  v_total_talks         integer;
  v_req_talks           integer;
  v_attended_talks      integer;
  v_attended_req_talks  integer;
  v_pct                 numeric;
  v_prog_status         text;
  v_prog_item           jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Parameter validations
  if p_organization_id is null or p_member_id is null then
    raise exception using errcode = '22023', message = 'Organization ID and Member ID are required.';
  end if;

  -- 3. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 4. Member validation
  if not exists (
    select 1 from public.members
    where id = p_member_id and organization_id = p_organization_id
  ) then
    raise exception using errcode = 'P0002', message = 'Member not found in the specified organization.';
  end if;

  -- 5. Authorization: caller must have formation.records.view and scope over the member
  if not private.can_access_member('formation.records.view', p_organization_id, p_member_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view formation records for this member.';
  end if;

  -- 6. Member identity context (minimal: id, member_number, display_name)
  select jsonb_build_object(
    'id', m.id,
    'member_number', m.member_number,
    'display_name', m.display_name
  )
  into v_member_summary
  from public.members m
  where m.id = p_member_id and m.organization_id = p_organization_id;

  -- 7. Active program records loop
  for v_rec in
    select
      pr.id as record_id,
      pr.program_id,
      p.code as program_code,
      p.title as program_title,
      p.edition,
      p.program_category,
      p.program_type,
      pr.attempt_number,
      pr.status,
      pr.record_status,
      pr.completed_date,
      pr.completed_year,
      pr.completed_month,
      pr.date_precision,
      pr.verification_method,
      pr.source_reference,
      pr.verified_at,
      verifier.display_name as verifier_display_name,
      pr.verification_notes,
      pr.recorded_at
    from public.member_formation_program_records pr
    join public.formation_programs p on p.id = pr.program_id
    left join public.profiles verifier on verifier.id = pr.verified_by_profile_id
    where pr.member_id = p_member_id
      and pr.organization_id = p_organization_id
      and pr.record_status = 'active'
    order by p.sequence_order nulls last, p.title asc, pr.attempt_number asc, pr.recorded_at asc
  loop
    -- Active talks for this attempt
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'talk_record_id', tr.id,
        'talk_id', t.id,
        'talk_code', t.talk_code,
        'title', t.title,
        'sequence_order', t.sequence_order,
        'session_status', tr.session_status,
        'attended_date', tr.attended_date,
        'notes', tr.notes
      ) order by t.sequence_order asc
    ), '[]'::jsonb)
    into v_talks
    from public.member_formation_talk_records tr
    join public.formation_talks t on t.id = tr.talk_id
    where tr.program_record_id = v_rec.record_id
      and tr.record_status = 'active';

    -- Curriculum talk counts (active curriculum talks)
    select
      count(*),
      count(*) filter (where t.is_required)
    into v_total_talks, v_req_talks
    from public.formation_talks t
    where t.program_id = v_rec.program_id
      and t.is_active = true;

    -- Attended talks counts for this attempt
    select
      count(*),
      count(*) filter (where t.is_required)
    into v_attended_talks, v_attended_req_talks
    from public.member_formation_talk_records tr
    join public.formation_talks t on t.id = tr.talk_id
    where tr.program_record_id = v_rec.record_id
      and tr.record_status = 'active'
      and tr.session_status in ('attended', 'makeup_attended', 'waived');

    -- Progress derivation
    if v_total_talks = 0 then
      v_pct := null;
      v_prog_status := 'not_applicable';
    else
      if v_req_talks > 0 then
        v_pct := round((v_attended_req_talks::numeric / v_req_talks::numeric) * 100, 1);
      else
        v_pct := round((v_attended_talks::numeric / v_total_talks::numeric) * 100, 1);
      end if;

      if v_rec.status = 'completed' then
        v_prog_status := 'completed';
      elsif v_rec.status = 'waived' then
        v_prog_status := 'waived';
      elsif v_attended_talks = 0 then
        v_prog_status := 'not_started';
      else
        v_prog_status := 'in_progress';
      end if;
    end if;

    v_prog_item := jsonb_build_object(
      'record_id', v_rec.record_id,
      'program_id', v_rec.program_id,
      'code', v_rec.program_code,
      'title', v_rec.program_title,
      'edition', v_rec.edition,
      'program_category', v_rec.program_category,
      'program_type', v_rec.program_type,
      'attempt_number', v_rec.attempt_number,
      'status', v_rec.status,
      'record_status', v_rec.record_status,
      'completed_date', v_rec.completed_date,
      'completed_year', v_rec.completed_year,
      'completed_month', v_rec.completed_month,
      'date_precision', v_rec.date_precision,
      'verification_method', v_rec.verification_method,
      'source_reference', v_rec.source_reference,
      'verified_at', v_rec.verified_at,
      'verifier_display_name', v_rec.verifier_display_name,
      'verification_notes', v_rec.verification_notes,
      'recorded_at', v_rec.recorded_at,
      'talks', v_talks,
      'progress', jsonb_build_object(
        'total_talks', v_total_talks,
        'required_talks', v_req_talks,
        'attended_talks', v_attended_talks,
        'progress_percent', v_pct,
        'progress_status', v_prog_status
      )
    );

    v_programs := v_programs || jsonb_build_array(v_prog_item);
  end loop;

  -- 8. Return structured transcript
  return jsonb_build_object(
    'organization_id', p_organization_id,
    'member', v_member_summary,
    'programs', coalesce(v_programs, '[]'::jsonb)
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 6. RPC: public.get_my_formation_transcript
-- -----------------------------------------------------------------------------

create or replace function public.get_my_formation_transcript(
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id          uuid;
  v_org_id              uuid;
  v_link_count          integer;
  v_member_id           uuid;
  v_member_summary      jsonb;
  v_programs            jsonb := '[]'::jsonb;
  v_rec                 record;
  v_talks               jsonb;
  v_total_talks         integer;
  v_req_talks           integer;
  v_attended_talks      integer;
  v_attended_req_talks  integer;
  v_pct                 numeric;
  v_prog_status         text;
  v_prog_item           jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Resolve organization context if not passed
  if p_organization_id is null then
    select count(*) into v_link_count
    from public.profile_member_links pml
    where pml.profile_id = v_profile_id
      and pml.link_type = 'self'
      and pml.link_status = 'verified'
      and pml.ended_at is null;

    if v_link_count = 0 then
      raise exception using errcode = 'P0002', message = 'Your account is not linked to a member record.';
    elsif v_link_count = 1 then
      select pml.organization_id into v_org_id
      from public.profile_member_links pml
      where pml.profile_id = v_profile_id
        and pml.link_type = 'self'
        and pml.link_status = 'verified'
        and pml.ended_at is null;
    else
      select pml.organization_id into v_org_id
      from public.profile_member_links pml
      join public.profile_organization_memberships pom
        on pom.profile_id = pml.profile_id and pom.organization_id = pml.organization_id
      where pml.profile_id = v_profile_id
        and pml.link_type = 'self'
        and pml.link_status = 'verified'
        and pml.ended_at is null
        and pom.is_default = true
        and pom.membership_status = 'active';

      if not found then
        raise exception using errcode = '22023', message = 'Multiple organization links found. Please specify organization.';
      end if;
    end if;
  else
    v_org_id := p_organization_id;
  end if;

  -- 3. Assert self-service permissions and resolve verified self member
  v_member_id := private.assert_member_self_service(v_org_id);

  -- 4. Member identity context
  select jsonb_build_object(
    'id', m.id,
    'member_number', m.member_number,
    'display_name', m.display_name
  )
  into v_member_summary
  from public.members m
  where m.id = v_member_id and m.organization_id = v_org_id;

  -- 5. Active program records loop (member self-service projection: no internal notes/verifiers/audit)
  for v_rec in
    select
      pr.id as record_id,
      pr.program_id,
      p.code as program_code,
      p.title as program_title,
      p.edition,
      p.program_category,
      p.program_type,
      pr.attempt_number,
      pr.status,
      pr.record_status,
      pr.completed_date,
      pr.completed_year,
      pr.completed_month,
      pr.date_precision,
      pr.source_reference
    from public.member_formation_program_records pr
    join public.formation_programs p on p.id = pr.program_id
    where pr.member_id = v_member_id
      and pr.organization_id = v_org_id
      and pr.record_status = 'active'
    order by p.sequence_order nulls last, p.title asc, pr.attempt_number asc, pr.recorded_at asc
  loop
    -- Active talks for this attempt (member projection: exclude internal staff notes)
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'talk_record_id', tr.id,
        'talk_id', t.id,
        'talk_code', t.talk_code,
        'title', t.title,
        'sequence_order', t.sequence_order,
        'session_status', tr.session_status,
        'attended_date', tr.attended_date
      ) order by t.sequence_order asc
    ), '[]'::jsonb)
    into v_talks
    from public.member_formation_talk_records tr
    join public.formation_talks t on t.id = tr.talk_id
    where tr.program_record_id = v_rec.record_id
      and tr.record_status = 'active';

    -- Curriculum talk counts
    select
      count(*),
      count(*) filter (where t.is_required)
    into v_total_talks, v_req_talks
    from public.formation_talks t
    where t.program_id = v_rec.program_id
      and t.is_active = true;

    -- Attended talks counts
    select
      count(*),
      count(*) filter (where t.is_required)
    into v_attended_talks, v_attended_req_talks
    from public.member_formation_talk_records tr
    join public.formation_talks t on t.id = tr.talk_id
    where tr.program_record_id = v_rec.record_id
      and tr.record_status = 'active'
      and tr.session_status in ('attended', 'makeup_attended', 'waived');

    -- Progress derivation
    if v_total_talks = 0 then
      v_pct := null;
      v_prog_status := 'not_applicable';
    else
      if v_req_talks > 0 then
        v_pct := round((v_attended_req_talks::numeric / v_req_talks::numeric) * 100, 1);
      else
        v_pct := round((v_attended_talks::numeric / v_total_talks::numeric) * 100, 1);
      end if;

      if v_rec.status = 'completed' then
        v_prog_status := 'completed';
      elsif v_rec.status = 'waived' then
        v_prog_status := 'waived';
      elsif v_attended_talks = 0 then
        v_prog_status := 'not_started';
      else
        v_prog_status := 'in_progress';
      end if;
    end if;

    v_prog_item := jsonb_build_object(
      'record_id', v_rec.record_id,
      'program_id', v_rec.program_id,
      'code', v_rec.program_code,
      'title', v_rec.program_title,
      'edition', v_rec.edition,
      'program_category', v_rec.program_category,
      'program_type', v_rec.program_type,
      'attempt_number', v_rec.attempt_number,
      'status', v_rec.status,
      'record_status', v_rec.record_status,
      'completed_date', v_rec.completed_date,
      'completed_year', v_rec.completed_year,
      'completed_month', v_rec.completed_month,
      'date_precision', v_rec.date_precision,
      'source_reference', v_rec.source_reference,
      'talks', v_talks,
      'progress', jsonb_build_object(
        'total_talks', v_total_talks,
        'required_talks', v_req_talks,
        'attended_talks', v_attended_talks,
        'progress_percent', v_pct,
        'progress_status', v_prog_status
      )
    );

    v_programs := v_programs || jsonb_build_array(v_prog_item);
  end loop;

  -- 6. Return member self-service transcript
  return jsonb_build_object(
    'organization_id', v_org_id,
    'member', v_member_summary,
    'programs', coalesce(v_programs, '[]'::jsonb)
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 7. Execute Privileges Configuration
-- -----------------------------------------------------------------------------

revoke all on function public.record_member_formation_program(uuid, uuid, uuid, text, date, smallint, smallint, text, text, text, text, uuid) from public, anon;
grant execute on function public.record_member_formation_program(uuid, uuid, uuid, text, date, smallint, smallint, text, text, text, text, uuid) to authenticated, service_role;

revoke all on function public.record_member_formation_talk(uuid, uuid, uuid, text, date, text) from public, anon;
grant execute on function public.record_member_formation_talk(uuid, uuid, uuid, text, date, text) to authenticated, service_role;

revoke all on function public.void_member_formation_program_record(uuid, uuid, text) from public, anon;
grant execute on function public.void_member_formation_program_record(uuid, uuid, text) to authenticated, service_role;

revoke all on function public.void_member_formation_talk_record(uuid, uuid, text) from public, anon;
grant execute on function public.void_member_formation_talk_record(uuid, uuid, text) to authenticated, service_role;

revoke all on function public.get_member_formation_transcript(uuid, uuid) from public, anon;
grant execute on function public.get_member_formation_transcript(uuid, uuid) to authenticated, service_role;

revoke all on function public.get_my_formation_transcript(uuid) from public, anon;
grant execute on function public.get_my_formation_transcript(uuid) to authenticated, service_role;

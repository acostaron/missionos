-- Migration 107: Restrict new formation records to active members only
-- Label: formation_records_active_members_only
-- Contiguous timestamp: 20261010039000

-- =============================================================================
-- A. Trigger function: private.guard_formation_record_member_active()
-- =============================================================================
create or replace function private.guard_formation_record_member_active()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_member_record_status text;
begin
  select m.record_status
  into v_member_record_status
  from public.members m
  where m.id = new.member_id
    and m.organization_id = new.organization_id;

  if v_member_record_status is null or v_member_record_status <> 'active' then
    raise exception using
      errcode = '22023',
      message = 'Formation can only be recorded for active members.';
  end if;

  return new;
end;
$$;

-- =============================================================================
-- B. BEFORE INSERT triggers on both tables
-- =============================================================================
drop trigger if exists trg_guard_formation_program_record_member_active on public.member_formation_program_records;
create trigger trg_guard_formation_program_record_member_active
  before insert on public.member_formation_program_records
  for each row
  execute function private.guard_formation_record_member_active();

drop trigger if exists trg_guard_formation_talk_record_member_active on public.member_formation_talk_records;
create trigger trg_guard_formation_talk_record_member_active
  before insert on public.member_formation_talk_records
  for each row
  execute function private.guard_formation_record_member_active();

-- =============================================================================
-- C. Revoke execute privileges
-- =============================================================================
revoke all on function private.guard_formation_record_member_active() from public, anon, authenticated;

-- =============================================================================
-- D. Summary audit event
-- =============================================================================
do $$
declare
  v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
begin
  insert into audit.events (
    organization_id,
    event_code,
    event_category,
    entity_type,
    entity_id,
    action,
    outcome,
    metadata
  ) values (
    v_org_id,
    'formation.records_active_members_only_configured',
    'formation',
    'schema',
    v_org_id,
    'configure_formation_records_active_members_only',
    'success',
    jsonb_build_object(
      'migration', '20261010039000_formation_records_active_members_only',
      'function', 'private.guard_formation_record_member_active',
      'guarded_tables', jsonb_build_array(
        'public.member_formation_program_records',
        'public.member_formation_talk_records'
      ),
      'guarded_event', 'INSERT',
      'error_code', '22023',
      'error_message', 'Formation can only be recorded for active members.'
    )
  );
end $$;

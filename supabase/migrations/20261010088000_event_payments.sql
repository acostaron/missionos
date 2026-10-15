-- =============================================================================
-- Migration: 20261010088000_event_payments.sql
-- MissionOS Pass 9.13 (written by Claude, 2026-10-16)
-- Ron: paid events (conferences) — check payment status at the QR check-in desk.
-- Ron's decisions (2026-10-16):
--   * The event has a fee. Payments are recorded in the app: Paid / Partial / Waived.
--   * Who sets the fee and records payments: the event's organizers (those who can manage the event)
--     and the Treasurer / Finance Coordinator (plus organization administrators).
--   * At the desk an unpaid or partly paid member is NOT checked in (no kit / T-shirt): warn, collect,
--     record the payment, then check in.
-- Design:
--   * events.fee_amount (USD; null or 0 = free event).
--   * event_payments: a ledger of payments (amount, method). Mistakes are voided, never deleted.
--   * event_fee_waivers: fee waived for a member.
--   * Status per member: free | waived | paid | partial | unpaid (computed, never typed in).
--   * finance_coordinators: who serves as Treasurer / Finance Coordinator (set by an administrator).
--   * scan_event_check_in (from 087, guarded) now returns result 'payment_required' for unpaid/partial members.
-- Privacy: payment amounts are visible only to organizers / finance; the desk scanner sees the member's
-- status and balance due. No free-text notes.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'scan_event_check_in';
  if v_md5 is distinct from '38d94fcf5bcd5ac2fb8cfa7ec46dc2cd' then
    raise exception 'STOP: public.scan_event_check_in differs from 20261010087000 (md5 %).', v_md5;
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------
alter table public.events
  add column if not exists fee_amount numeric(10,2) null;
alter table public.events drop constraint if exists chk_events_fee_amount;
alter table public.events add constraint chk_events_fee_amount
  check (fee_amount is null or (fee_amount >= 0 and fee_amount <= 10000));

create table if not exists public.event_payments (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid not null references public.events(id) on delete restrict,
  member_id              uuid not null references public.members(id) on delete restrict,
  amount                 numeric(10,2) not null check (amount > 0 and amount <= 10000),
  payment_method         text not null check (payment_method in ('cash', 'check', 'zelle', 'card', 'other')),
  recorded_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  recorded_at            timestamptz not null default now(),
  voided_at              timestamptz null,
  voided_by_profile_id   uuid null references public.profiles(id) on delete set null
);
create index if not exists idx_event_payments_event_member on public.event_payments (event_id, member_id) where voided_at is null;

create table if not exists public.event_fee_waivers (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid not null references public.events(id) on delete restrict,
  member_id              uuid not null references public.members(id) on delete restrict,
  waived_by_profile_id   uuid not null references public.profiles(id) on delete restrict,
  waived_at              timestamptz not null default now(),
  removed_at             timestamptz null,
  removed_by_profile_id  uuid null references public.profiles(id) on delete set null
);
create unique index if not exists uq_event_fee_waivers_active on public.event_fee_waivers (event_id, member_id) where removed_at is null;

create table if not exists public.finance_coordinators (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  member_id              uuid not null references public.members(id) on delete restrict,
  role_title             text not null check (role_title in ('treasurer', 'finance_coordinator')),
  appointed_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  appointed_at           timestamptz not null default now(),
  ended_at               timestamptz null,
  ended_by_profile_id    uuid null references public.profiles(id) on delete set null
);
create unique index if not exists uq_finance_coordinators_active
  on public.finance_coordinators (organization_id, member_id, role_title) where ended_at is null;

alter table public.event_payments enable row level security;
alter table public.event_fee_waivers enable row level security;
alter table public.finance_coordinators enable row level security;
revoke all on public.event_payments, public.event_fee_waivers, public.finance_coordinators from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Who may manage payments; payment status
-- -----------------------------------------------------------------------------
create or replace function private.is_finance_coordinator(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select exists (
    select 1 from public.finance_coordinators f
    where f.organization_id = p_organization_id and f.ended_at is null
      and f.member_id in (select private.current_member_ids(p_organization_id)))
$$;
revoke all on function private.is_finance_coordinator(uuid) from public, anon, authenticated;

create or replace function private.can_manage_event_payments(p_organization_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.has_organization_access(p_organization_id)
     and (private.is_organization_administrator(private.current_profile_id(), p_organization_id)
          or private.is_finance_coordinator(p_organization_id)
          or (private.has_permission('events.manage', p_organization_id)
              and private.can_manage_event(p_organization_id, p_event_id)))
$$;
revoke all on function private.can_manage_event_payments(uuid, uuid) from public, anon, authenticated;

create or replace function private.event_payment_status(p_event public.events, p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_fee    numeric := coalesce(p_event.fee_amount, 0);
  v_paid   numeric;
  v_waived boolean;
begin
  if v_fee = 0 then
    return jsonb_build_object('status', 'free', 'fee', 0, 'paid', 0, 'balance', 0);
  end if;
  select coalesce(sum(p.amount), 0) into v_paid from public.event_payments p
  where p.event_id = p_event.id and p.member_id = p_member_id and p.voided_at is null;
  select exists (select 1 from public.event_fee_waivers w
                 where w.event_id = p_event.id and w.member_id = p_member_id and w.removed_at is null) into v_waived;
  return jsonb_build_object(
    'status',  case when v_waived then 'waived' when v_paid >= v_fee then 'paid' when v_paid > 0 then 'partial' else 'unpaid' end,
    'fee',     v_fee,
    'paid',    v_paid,
    'balance', case when v_waived then 0 else greatest(v_fee - v_paid, 0) end);
end;
$$;
revoke all on function private.event_payment_status(public.events, uuid) from public, anon, authenticated;

create or replace function private.assert_event_payments(p_organization_id uuid, p_event_id uuid)
returns public.events
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_event public.events%rowtype;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_manage_event_payments(p_organization_id, p_event_id) then
    raise exception using errcode = '42501',
      message = 'Only the event organizers and the Treasurer / Finance Coordinator can manage payments.';
  end if;
  return v_event;
end;
$$;
revoke all on function private.assert_event_payments(uuid, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Fee, payments, waivers
-- -----------------------------------------------------------------------------
create or replace function public.set_event_fee(p_organization_id uuid, p_event_id uuid, p_fee_amount numeric default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_event public.events%rowtype;
begin
  v_event := private.assert_event_payments(p_organization_id, p_event_id);
  if p_fee_amount is not null and (p_fee_amount < 0 or p_fee_amount > 10000) then
    raise exception using errcode = '22023', message = 'Enter a fee between 0 and 10,000.';
  end if;
  update public.events set fee_amount = nullif(round(p_fee_amount, 2), 0), updated_at = now(),
                           updated_by_profile_id = private.current_profile_id()
  where id = p_event_id;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.fee.set', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'update', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('old_fee', v_event.fee_amount, 'new_fee', nullif(round(p_fee_amount, 2), 0)));
  return jsonb_build_object('fee_amount', nullif(round(p_fee_amount, 2), 0));
end;
$$;
revoke all on function public.set_event_fee(uuid, uuid, numeric) from public, anon;
grant execute on function public.set_event_fee(uuid, uuid, numeric) to authenticated;

create or replace function public.record_event_payment(
  p_organization_id uuid,
  p_event_id        uuid,
  p_member_id       uuid,
  p_amount          numeric,
  p_payment_method  text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event public.events%rowtype;
  v_id    uuid;
begin
  v_event := private.assert_event_payments(p_organization_id, p_event_id);
  if coalesce(v_event.fee_amount, 0) = 0 then
    raise exception using errcode = '22023', message = 'Set the event fee first.';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000 then
    raise exception using errcode = '22023', message = 'Enter the amount received.';
  end if;
  if p_payment_method is null or p_payment_method not in ('cash', 'check', 'zelle', 'card', 'other') then
    raise exception using errcode = '22023', message = 'Choose how it was paid.';
  end if;
  if not exists (select 1 from public.members m where m.id = p_member_id and m.organization_id = p_organization_id
                 and m.record_status = 'active' and m.archived_at is null) then
    raise exception using errcode = 'P0002', message = 'Member not found or not active.';
  end if;

  insert into public.event_payments (organization_id, event_id, member_id, amount, payment_method, recorded_by_profile_id)
  values (p_organization_id, p_event_id, p_member_id, round(p_amount, 2), p_payment_method, private.current_profile_id())
  returning id into v_id;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.payment.recorded', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'create', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('payment_id', v_id, 'member_id', p_member_id, 'amount', round(p_amount, 2),
                                     'method', p_payment_method));
  return jsonb_build_object('payment_id', v_id, 'payment', private.event_payment_status(v_event, p_member_id));
end;
$$;
revoke all on function public.record_event_payment(uuid, uuid, uuid, numeric, text) from public, anon;
grant execute on function public.record_event_payment(uuid, uuid, uuid, numeric, text) to authenticated;

create or replace function public.void_event_payment(p_organization_id uuid, p_payment_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_pay   public.event_payments%rowtype;
  v_event public.events%rowtype;
begin
  select * into v_pay from public.event_payments where id = p_payment_id and organization_id = p_organization_id for update;
  if not found or v_pay.voided_at is not null then
    raise exception using errcode = 'P0002', message = 'Payment not found.';
  end if;
  v_event := private.assert_event_payments(p_organization_id, v_pay.event_id);
  update public.event_payments set voided_at = now(), voided_by_profile_id = private.current_profile_id()
  where id = p_payment_id;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.payment.voided', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => v_pay.event_id,
    p_action => 'void', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('payment_id', p_payment_id, 'member_id', v_pay.member_id, 'amount', v_pay.amount));
  return jsonb_build_object('payment', private.event_payment_status(v_event, v_pay.member_id));
end;
$$;
revoke all on function public.void_event_payment(uuid, uuid) from public, anon;
grant execute on function public.void_event_payment(uuid, uuid) to authenticated;

create or replace function public.set_event_fee_waiver(p_organization_id uuid, p_event_id uuid, p_member_id uuid, p_waived boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_event public.events%rowtype;
begin
  v_event := private.assert_event_payments(p_organization_id, p_event_id);
  if not exists (select 1 from public.members m where m.id = p_member_id and m.organization_id = p_organization_id) then
    raise exception using errcode = 'P0002', message = 'Member not found.';
  end if;
  if coalesce(p_waived, false) then
    insert into public.event_fee_waivers (organization_id, event_id, member_id, waived_by_profile_id)
    select p_organization_id, p_event_id, p_member_id, private.current_profile_id()
    where not exists (select 1 from public.event_fee_waivers w
                      where w.event_id = p_event_id and w.member_id = p_member_id and w.removed_at is null);
  else
    update public.event_fee_waivers set removed_at = now(), removed_by_profile_id = private.current_profile_id()
    where event_id = p_event_id and member_id = p_member_id and removed_at is null;
  end if;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.fee.waiver', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'update', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('member_id', p_member_id, 'waived', coalesce(p_waived, false)));
  return jsonb_build_object('payment', private.event_payment_status(v_event, p_member_id));
end;
$$;
revoke all on function public.set_event_fee_waiver(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.set_event_fee_waiver(uuid, uuid, uuid, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Payments list (organizers / finance) and member search for adding payments
-- -----------------------------------------------------------------------------
create or replace function public.get_event_payments(p_organization_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_event public.events%rowtype;
begin
  v_event := private.assert_event_payments(p_organization_id, p_event_id);
  return (
    with ppl as (
      select p.member_id from public.event_payments p where p.event_id = p_event_id and p.voided_at is null
      union
      select w.member_id from public.event_fee_waivers w where w.event_id = p_event_id and w.removed_at is null
    ),
    rws as (
      select m.id, m.display_name, m.member_number, m.sort_name,
             private.event_payment_status(v_event, m.id) as st
      from ppl join public.members m on m.id = ppl.member_id
    )
    select jsonb_build_object(
      'fee_amount', v_event.fee_amount,
      'totals', jsonb_build_object(
        'paid',      count(*) filter (where r.st->>'status' = 'paid'),
        'partial',   count(*) filter (where r.st->>'status' = 'partial'),
        'waived',    count(*) filter (where r.st->>'status' = 'waived'),
        'collected', coalesce((select sum(p.amount) from public.event_payments p
                               where p.event_id = p_event_id and p.voided_at is null), 0)),
      'members', coalesce(jsonb_agg(jsonb_build_object(
          'member_id', r.id, 'display_name', r.display_name, 'member_number', r.member_number,
          'payment', r.st,
          'payments', coalesce((select jsonb_agg(jsonb_build_object('payment_id', p.id, 'amount', p.amount,
                                                                     'payment_method', p.payment_method,
                                                                     'recorded_at', p.recorded_at)
                                                  order by p.recorded_at)
                                from public.event_payments p
                                where p.event_id = p_event_id and p.member_id = r.id and p.voided_at is null), '[]'::jsonb))
        order by lower(r.sort_name), r.id), '[]'::jsonb))
    from rws r);
end;
$$;
revoke all on function public.get_event_payments(uuid, uuid) from public, anon;
grant execute on function public.get_event_payments(uuid, uuid) to authenticated;

create or replace function public.search_members_for_event_payment(p_organization_id uuid, p_event_id uuid, p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event public.events%rowtype;
  v_q     text := lower(btrim(coalesce(p_query, '')));
begin
  v_event := private.assert_event_payments(p_organization_id, p_event_id);
  if length(v_q) < 2 then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('member_id', x.id, 'display_name', x.display_name,
                                        'member_number', x.member_number,
                                        'payment', private.event_payment_status(v_event, x.id))
                     order by lower(x.sort_name))
    from (select m.id, m.display_name, m.member_number, m.sort_name
          from public.members m
          where m.organization_id = p_organization_id and m.record_status = 'active' and m.archived_at is null
            and (lower(m.display_name) like '%' || v_q || '%' or lower(coalesce(m.member_number, '')) like '%' || v_q || '%')
          order by lower(m.sort_name) limit 20) x), '[]'::jsonb);
end;
$$;
revoke all on function public.search_members_for_event_payment(uuid, uuid, text) from public, anon;
grant execute on function public.search_members_for_event_payment(uuid, uuid, text) to authenticated;

-- What the event page needs to know (any viewer): is it paid, and may I manage payments?
create or replace function public.get_event_payment_access(p_organization_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_fee numeric;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select e.fee_amount into v_fee from public.events e where e.id = p_event_id and e.organization_id = p_organization_id;
  return jsonb_build_object('fee_amount', v_fee,
                            'can_manage_payments', private.can_manage_event_payments(p_organization_id, p_event_id));
end;
$$;
revoke all on function public.get_event_payment_access(uuid, uuid) from public, anon;
grant execute on function public.get_event_payment_access(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Treasurer / Finance Coordinator appointments (organization administrators)
-- -----------------------------------------------------------------------------
create or replace function public.set_finance_coordinator(p_organization_id uuid, p_member_id uuid, p_role_title text, p_active boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_actor uuid := private.current_profile_id();
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if not private.is_organization_administrator(v_actor, p_organization_id) then
    raise exception using errcode = '42501', message = 'Only an administrator can appoint the Treasurer / Finance Coordinator.';
  end if;
  if p_role_title is null or p_role_title not in ('treasurer', 'finance_coordinator') then
    raise exception using errcode = '22023', message = 'Role must be treasurer or finance_coordinator.';
  end if;
  if not exists (select 1 from public.members m where m.id = p_member_id and m.organization_id = p_organization_id
                 and m.record_status = 'active') then
    raise exception using errcode = 'P0002', message = 'Member not found or not active.';
  end if;
  if coalesce(p_active, true) then
    insert into public.finance_coordinators (organization_id, member_id, role_title, appointed_by_profile_id)
    select p_organization_id, p_member_id, p_role_title, v_actor
    where not exists (select 1 from public.finance_coordinators f where f.organization_id = p_organization_id
                      and f.member_id = p_member_id and f.role_title = p_role_title and f.ended_at is null);
  else
    update public.finance_coordinators set ended_at = now(), ended_by_profile_id = v_actor
    where organization_id = p_organization_id and member_id = p_member_id and role_title = p_role_title and ended_at is null;
  end if;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'finance_coordinator.set', p_event_category => 'governance',
    p_actor_profile_id => v_actor, p_entity_type => 'member', p_entity_id => p_member_id,
    p_action => 'update', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('role_title', p_role_title, 'active', coalesce(p_active, true)));
  return jsonb_build_object('member_id', p_member_id, 'role_title', p_role_title, 'active', coalesce(p_active, true));
end;
$$;
revoke all on function public.set_finance_coordinator(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.set_finance_coordinator(uuid, uuid, text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. QR check-in: payment gate (replaces the 087 version; guarded above)
-- -----------------------------------------------------------------------------
create or replace function public.scan_event_check_in(
  p_organization_id uuid,
  p_event_id        uuid,
  p_payload         text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor     uuid := private.current_profile_id();
  v_event     public.events%rowtype;
  v_today     date := (now() at time zone 'America/New_York')::date;
  v_qr        jsonb;
  v_member_id uuid;
  v_member    jsonb;
  v_prev_at   timestamptz;
  v_att       public.event_attendance%rowtype;
  v_first     boolean := false;
  v_days      integer;
  v_pay       jsonb;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'You cannot check members in for this event.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'This event was cancelled.';
  end if;
  if v_today < private.event_ny_first_day(v_event) then
    raise exception using errcode = '22023',
      message = format('Check-in opens on %s.', to_char(private.event_ny_first_day(v_event), 'FMDay, FMMonth FMDD'));
  end if;
  if v_today > private.event_ny_last_day(v_event) then
    raise exception using errcode = '22023',
      message = 'This event is over. Use the attendance list to correct attendance.';
  end if;

  v_qr := public.resolve_member_qr(p_organization_id, p_payload);
  if not coalesce((v_qr->>'valid')::boolean, false) then
    return jsonb_build_object('result', 'invalid', 'reason', coalesce(v_qr->>'reason', 'not_a_member_qr'),
                              'member', case when v_qr ? 'member_id' then jsonb_build_object(
                                'member_id', v_qr->'member_id', 'display_name', v_qr->'display_name',
                                'member_number', v_qr->'member_number', 'photo_path', v_qr->'photo_path') end);
  end if;

  v_member_id := (v_qr->>'member_id')::uuid;
  v_member := jsonb_build_object('member_id', v_member_id, 'display_name', v_qr->'display_name',
                                 'member_number', v_qr->'member_number', 'photo_path', v_qr->'photo_path');

  select * into v_att from public.event_attendance a
  where a.event_id = p_event_id and a.member_id = v_member_id and a.removed_at is null;

  -- already checked in today (scanned, or ticked on the list today)?
  select c.recorded_at into v_prev_at from public.event_check_ins c
  where c.event_id = p_event_id and c.member_id = v_member_id and c.check_in_date = v_today;
  if v_prev_at is null and v_att.id is not null
     and (v_att.recorded_at at time zone 'America/New_York')::date = v_today then
    v_prev_at := v_att.recorded_at;
  end if;
  if v_prev_at is not null then
    return jsonb_build_object('result', 'already_checked_in', 'member', v_member,
                              'checked_in_at', v_prev_at, 'kit_given_at', v_att.recorded_at);
  end if;

  -- Pass 9.13: paid events — no check-in (no kit) until paid or waived
  v_pay := private.event_payment_status(v_event, v_member_id);
  if v_pay->>'status' in ('unpaid', 'partial') then
    return jsonb_build_object('result', 'payment_required', 'member', v_member, 'payment', v_pay,
                              'can_record_payment', private.can_manage_event_payments(p_organization_id, p_event_id));
  end if;

  begin
    insert into public.event_check_ins (organization_id, event_id, member_id, check_in_date, check_in_method,
                                        recorded_by_profile_id)
    values (p_organization_id, p_event_id, v_member_id, v_today, 'qr', v_actor);
  exception when unique_violation then
    -- scanned at the same moment at another desk
    select c.recorded_at into v_prev_at from public.event_check_ins c
    where c.event_id = p_event_id and c.member_id = v_member_id and c.check_in_date = v_today;
    return jsonb_build_object('result', 'already_checked_in', 'member', v_member,
                              'checked_in_at', v_prev_at, 'kit_given_at', v_att.recorded_at);
  end;

  if v_att.id is null then
    insert into public.event_attendance (organization_id, event_id, member_id, check_in_method, recorded_by_profile_id)
    values (p_organization_id, p_event_id, v_member_id, 'qr', v_actor);
    v_first := true;
  end if;

  v_days := private.event_ny_last_day(v_event) - private.event_ny_first_day(v_event) + 1;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.check_in.qr',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'event',
    p_entity_id        => p_event_id,
    p_action           => 'record_attendance',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('member_id', v_member_id, 'check_in_date', v_today,
                                             'first_check_in', v_first));

  return jsonb_build_object(
    'result',         'checked_in',
    'member',         v_member,
    'checked_in_at',  now(),
    'first_check_in', v_first,                       -- true: give the kit and T-shirt now
    'kit_given_at',   case when v_first then null else v_att.recorded_at end,
    'multi_day',      v_days > 1,
    'payment',        v_pay);
end;
$$;
revoke all on function public.scan_event_check_in(uuid, uuid, text) from public, anon;
grant execute on function public.scan_event_check_in(uuid, uuid, text) to authenticated;

-- =============================================================================
-- Migration: 20261010091000_event_guests.sql
-- MissionOS Pass 9.15 (written by Claude, 2026-10-16) — run after 20261010090000.
-- Ron: guests (non-members) also register and attend paid events and conferences.
-- Ron's decisions (2026-10-16):
--   * Guests are recorded by name, with an optional phone or email, under the member who registers them
--     (organizers can also add guests, with or without a host member, e.g. walk-in visitors).
--   * Each event can set its own guest price. If none is set, guests pay the member price
--     (early-bird / regular, or walk-in at the door).
--   * Guests get an on-screen guest pass (QR "MFCNYG1:<code>") instead of a member QR; the desk scans it or
--     checks the guest in from the list. Same rules as members: paid in full (or waived) before check-in,
--     one check-in per event day, warning on a second scan.
-- Privacy: guest phone / email are visible only to the host member and the organizers / finance.
-- Guarded: scan_event_check_in (090) and get_event_check_in_summary (087) are replaced only if unchanged.
-- =============================================================================
do $guard$
declare
  r record;
  v_md5 text;
begin
  for r in select * from (values
    ('scan_event_check_in',        '1527d759930626eec9dcace78f04cd7d'),
    ('get_event_check_in_summary', 'f510179b71c86516dee141b057ea2c61')
  ) t(fn, expected)
  loop
    select md5(replace(p.prosrc, chr(13), '')) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = r.fn;
    if v_md5 is distinct from r.expected then
      raise exception 'STOP: public.% differs from the version this migration was built from (md5 %).', r.fn, v_md5;
    end if;
  end loop;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------
alter table public.events add column if not exists guest_fee numeric(10,2) null;
alter table public.events drop constraint if exists chk_events_guest_fee;
alter table public.events add constraint chk_events_guest_fee check (guest_fee is null or (guest_fee >= 0 and guest_fee <= 10000));

create table if not exists public.event_guests (
  id                       uuid primary key default gen_random_uuid(),
  organization_id          uuid not null references public.organizations(id) on delete restrict,
  event_id                 uuid not null references public.events(id) on delete restrict,
  host_member_id           uuid null references public.members(id) on delete restrict,
  first_name               text not null check (length(btrim(first_name)) between 1 and 80),
  last_name                text not null check (length(btrim(last_name)) between 1 and 80),
  phone                    text null check (phone is null or length(phone) <= 30),
  email                    text null check (email is null or (length(email) <= 120 and email like '%_@_%')),
  registration_type        text not null check (registration_type in ('reserved', 'walk_in')),
  price_tier               text not null check (price_tier in ('free', 'guest', 'early_bird', 'regular', 'walk_in')),
  amount_due               numeric(10,2) not null check (amount_due >= 0 and amount_due <= 10000),
  source                   text not null check (source in ('self', 'staff', 'desk')),
  guest_code               text not null unique,
  registered_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  registered_at            timestamptz not null default now(),
  waived_at                timestamptz null,
  waived_by_profile_id     uuid null references public.profiles(id) on delete set null,
  cancelled_at             timestamptz null,
  cancelled_by_profile_id  uuid null references public.profiles(id) on delete set null
);
create index if not exists idx_event_guests_event on public.event_guests (event_id) where cancelled_at is null;
create index if not exists idx_event_guests_host on public.event_guests (host_member_id) where cancelled_at is null;

create table if not exists public.event_guest_payments (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  guest_id               uuid not null references public.event_guests(id) on delete restrict,
  amount                 numeric(10,2) not null check (amount > 0 and amount <= 10000),
  payment_method         text not null check (payment_method in ('cash', 'check', 'zelle', 'paypal', 'card', 'other')),
  recorded_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  recorded_at            timestamptz not null default now(),
  voided_at              timestamptz null,
  voided_by_profile_id   uuid null references public.profiles(id) on delete set null
);
create index if not exists idx_event_guest_payments_guest on public.event_guest_payments (guest_id) where voided_at is null;

create table if not exists public.event_guest_check_ins (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid not null references public.events(id) on delete restrict,
  guest_id               uuid not null references public.event_guests(id) on delete restrict,
  check_in_date          date not null,
  check_in_method        text not null check (check_in_method in ('qr', 'manual')),
  recorded_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  recorded_at            timestamptz not null default now(),
  constraint uq_event_guest_check_ins_day unique (guest_id, check_in_date)
);
create index if not exists idx_event_guest_check_ins_event_day on public.event_guest_check_ins (event_id, check_in_date);

alter table public.event_guests enable row level security;
alter table public.event_guest_payments enable row level security;
alter table public.event_guest_check_ins enable row level security;
revoke all on public.event_guests, public.event_guest_payments, public.event_guest_check_ins from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Price, status, JSON
-- -----------------------------------------------------------------------------
create or replace function private.guest_price_now(p_event public.events, p_walk_in boolean)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select case
    when p_event.guest_fee is not null then
      case when p_event.guest_fee = 0 then jsonb_build_object('tier', 'free', 'amount', 0)
           else jsonb_build_object('tier', 'guest', 'amount', p_event.guest_fee) end
    else private.event_price_now(p_event, p_walk_in)
  end
$$;
revoke all on function private.guest_price_now(public.events, boolean) from public, anon, authenticated;

create or replace function private.guest_payment_status(p_guest public.event_guests)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare v_paid numeric;
begin
  select coalesce(sum(p.amount), 0) into v_paid from public.event_guest_payments p
  where p.guest_id = p_guest.id and p.voided_at is null;
  return jsonb_build_object(
    'status',  case when p_guest.amount_due = 0 then 'free'
                    when p_guest.waived_at is not null then 'waived'
                    when v_paid >= p_guest.amount_due then 'paid'
                    when v_paid > 0 then 'partial'
                    else 'unpaid' end,
    'fee',     p_guest.amount_due,
    'paid',    v_paid,
    'balance', case when p_guest.waived_at is not null then 0 else greatest(p_guest.amount_due - v_paid, 0) end,
    'registration_type', p_guest.registration_type,
    'price_tier', p_guest.price_tier);
end;
$$;
revoke all on function private.guest_payment_status(public.event_guests) from public, anon, authenticated;

create or replace function private.guest_json(p_guest public.event_guests, p_include_contact boolean)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select jsonb_build_object(
    'guest_id',     p_guest.id,
    'event_id',     p_guest.event_id,
    'first_name',   p_guest.first_name,
    'last_name',    p_guest.last_name,
    'display_name', btrim(p_guest.first_name || ' ' || p_guest.last_name),
    'phone',        case when p_include_contact then p_guest.phone end,
    'email',        case when p_include_contact then p_guest.email end,
    'host_member_id', p_guest.host_member_id,
    'host_name',    (select m.display_name from public.members m where m.id = p_guest.host_member_id),
    'guest_code',   p_guest.guest_code,
    'registered_at', p_guest.registered_at,
    'payment',      private.guest_payment_status(p_guest),
    'checked_in_today', exists (select 1 from public.event_guest_check_ins c where c.guest_id = p_guest.id
                                and c.check_in_date = (now() at time zone 'America/New_York')::date),
    'checked_in_ever',  exists (select 1 from public.event_guest_check_ins c where c.guest_id = p_guest.id))
$$;
revoke all on function private.guest_json(public.event_guests, boolean) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Add / cancel guests
-- -----------------------------------------------------------------------------
create or replace function public.add_event_guest(
  p_organization_id uuid,
  p_event_id        uuid,
  p_first_name      text,
  p_last_name       text,
  p_phone           text default null,
  p_email           text default null,
  p_as_staff        boolean default false,   -- false = I am adding my own guest (My Events)
  p_host_member_id  uuid default null,       -- staff only; null = no host member
  p_walk_in         boolean default false    -- staff at the desk
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event  public.events%rowtype;
  v_host   uuid;
  v_source text;
  v_price  jsonb;
  v_guest  public.event_guests%rowtype;
  v_phone  text := nullif(btrim(coalesce(p_phone, '')), '');
  v_email  text := lower(nullif(btrim(coalesce(p_email, '')), ''));
  v_code   text;
begin
  if coalesce(p_as_staff, false) then
    v_event := private.assert_event_payments(p_organization_id, p_event_id);
    v_host := p_host_member_id;
    if v_host is not null and not exists (select 1 from public.members m where m.id = v_host
                                           and m.organization_id = p_organization_id and m.record_status = 'active') then
      raise exception using errcode = 'P0002', message = 'Host member not found or not active.';
    end if;
    v_source := case when coalesce(p_walk_in, false) then 'desk' else 'staff' end;
  else
    v_host := private.assert_member_self_service(p_organization_id);
    select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Event not found.';
    end if;
    if not exists (select 1 from public.event_registrations r where r.event_id = p_event_id
                   and r.member_id = v_host and r.cancelled_at is null) then
      raise exception using errcode = '22023', message = 'Register yourself for this event first, then add your guests.';
    end if;
    if not v_event.registration_open then
      raise exception using errcode = '22023', message = 'Registration is closed. Please ask the registration team to add your guest.';
    end if;
    if coalesce(p_walk_in, false) then
      raise exception using errcode = '22023', message = 'Walk-in guests are added at the desk.';
    end if;
    if (select count(*) from public.event_guests g where g.event_id = p_event_id and g.host_member_id = v_host
        and g.cancelled_at is null) >= 10 then
      raise exception using errcode = '22023', message = 'You can add up to 10 guests. Please contact the registration team for more.';
    end if;
    v_source := 'self';
  end if;

  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'This event was cancelled.';
  end if;
  if (now() at time zone 'America/New_York')::date > private.event_ny_last_day(v_event) then
    raise exception using errcode = '22023', message = 'This event is over.';
  end if;
  if length(btrim(coalesce(p_first_name, ''))) not between 1 and 80 or length(btrim(coalesce(p_last_name, ''))) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'Enter the guest''s first and last name.';
  end if;
  if v_phone is not null and (length(v_phone) > 30 or v_phone !~ '^[0-9+()\-. ]+$') then
    raise exception using errcode = '22023', message = 'Enter a valid phone number.';
  end if;
  if v_email is not null and (length(v_email) > 120 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception using errcode = '22023', message = 'Enter a valid email address.';
  end if;

  v_price := private.guest_price_now(v_event, coalesce(p_walk_in, false));
  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    exit when not exists (select 1 from public.event_guests g where g.guest_code = v_code);
  end loop;

  insert into public.event_guests (organization_id, event_id, host_member_id, first_name, last_name, phone, email,
                                   registration_type, price_tier, amount_due, source, guest_code, registered_by_profile_id)
  values (p_organization_id, p_event_id, v_host, btrim(p_first_name), btrim(p_last_name), v_phone, v_email,
          case when coalesce(p_walk_in, false) then 'walk_in' else 'reserved' end,
          v_price->>'tier', (v_price->>'amount')::numeric, v_source, v_code, private.current_profile_id())
  returning * into v_guest;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.guest.added', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'create', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('guest_id', v_guest.id, 'host_member_id', v_host, 'source', v_source));
  return private.guest_json(v_guest, true);
end;
$$;
revoke all on function public.add_event_guest(uuid, uuid, text, text, text, text, boolean, uuid, boolean) from public, anon;
grant execute on function public.add_event_guest(uuid, uuid, text, text, text, text, boolean, uuid, boolean) to authenticated;

create or replace function private.load_guest_for_action(p_organization_id uuid, p_guest_id uuid, p_allow_host boolean)
returns public.event_guests
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_guest public.event_guests%rowtype;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select * into v_guest from public.event_guests g
  where g.id = p_guest_id and g.organization_id = p_organization_id and g.cancelled_at is null
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Guest not found.';
  end if;
  if private.can_manage_event_payments(p_organization_id, v_guest.event_id) then
    return v_guest;
  end if;
  if p_allow_host and v_guest.host_member_id is not null
     and v_guest.host_member_id in (select private.current_member_ids(p_organization_id)) then
    return v_guest;
  end if;
  raise exception using errcode = '42501', message = 'Only the host member or the registration team can do this.';
end;
$$;
revoke all on function private.load_guest_for_action(uuid, uuid, boolean) from public, anon, authenticated;

create or replace function public.cancel_event_guest(p_organization_id uuid, p_guest_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_guest public.event_guests%rowtype;
begin
  v_guest := private.load_guest_for_action(p_organization_id, p_guest_id, true);
  if exists (select 1 from public.event_guest_payments p where p.guest_id = v_guest.id and p.voided_at is null) then
    raise exception using errcode = '22023', message = 'A payment is recorded for this guest. The registration team must void it first.';
  end if;
  if exists (select 1 from public.event_guest_check_ins c where c.guest_id = v_guest.id) then
    raise exception using errcode = '22023', message = 'This guest already checked in.';
  end if;
  update public.event_guests set cancelled_at = now(), cancelled_by_profile_id = private.current_profile_id()
  where id = v_guest.id;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.guest.cancelled', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => v_guest.event_id,
    p_action => 'cancel', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('guest_id', v_guest.id));
  return jsonb_build_object('cancelled', true);
end;
$$;
revoke all on function public.cancel_event_guest(uuid, uuid) from public, anon;
grant execute on function public.cancel_event_guest(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Guest payments and waiver (organizers / finance)
-- -----------------------------------------------------------------------------
create or replace function public.record_event_guest_payment(p_organization_id uuid, p_guest_id uuid, p_amount numeric, p_payment_method text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_guest public.event_guests%rowtype;
  v_id    uuid;
begin
  v_guest := private.load_guest_for_action(p_organization_id, p_guest_id, false);
  if v_guest.amount_due = 0 then
    raise exception using errcode = '22023', message = 'This guest has nothing to pay.';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000 then
    raise exception using errcode = '22023', message = 'Enter the amount received.';
  end if;
  if p_payment_method is null or p_payment_method not in ('cash', 'check', 'zelle', 'paypal', 'card', 'other') then
    raise exception using errcode = '22023', message = 'Choose how it was paid.';
  end if;
  insert into public.event_guest_payments (organization_id, guest_id, amount, payment_method, recorded_by_profile_id)
  values (p_organization_id, v_guest.id, round(p_amount, 2), p_payment_method, private.current_profile_id())
  returning id into v_id;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.guest.payment.recorded', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => v_guest.event_id,
    p_action => 'create', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('guest_id', v_guest.id, 'payment_id', v_id, 'amount', round(p_amount, 2), 'method', p_payment_method));
  return jsonb_build_object('payment_id', v_id, 'payment', private.guest_payment_status(v_guest));
end;
$$;
revoke all on function public.record_event_guest_payment(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.record_event_guest_payment(uuid, uuid, numeric, text) to authenticated;

create or replace function public.void_event_guest_payment(p_organization_id uuid, p_payment_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_pay   public.event_guest_payments%rowtype;
  v_guest public.event_guests%rowtype;
begin
  select * into v_pay from public.event_guest_payments where id = p_payment_id and organization_id = p_organization_id for update;
  if not found or v_pay.voided_at is not null then
    raise exception using errcode = 'P0002', message = 'Payment not found.';
  end if;
  v_guest := private.load_guest_for_action(p_organization_id, v_pay.guest_id, false);
  update public.event_guest_payments set voided_at = now(), voided_by_profile_id = private.current_profile_id() where id = p_payment_id;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.guest.payment.voided', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => v_guest.event_id,
    p_action => 'void', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('guest_id', v_guest.id, 'payment_id', p_payment_id, 'amount', v_pay.amount));
  return jsonb_build_object('payment', private.guest_payment_status(v_guest));
end;
$$;
revoke all on function public.void_event_guest_payment(uuid, uuid) from public, anon;
grant execute on function public.void_event_guest_payment(uuid, uuid) to authenticated;

create or replace function public.set_event_guest_waiver(p_organization_id uuid, p_guest_id uuid, p_waived boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_guest public.event_guests%rowtype;
begin
  v_guest := private.load_guest_for_action(p_organization_id, p_guest_id, false);
  update public.event_guests
     set waived_at = case when coalesce(p_waived, false) then coalesce(waived_at, now()) end,
         waived_by_profile_id = case when coalesce(p_waived, false) then coalesce(waived_by_profile_id, private.current_profile_id()) end
   where id = v_guest.id
  returning * into v_guest;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.guest.waiver', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => v_guest.event_id,
    p_action => 'update', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('guest_id', v_guest.id, 'waived', coalesce(p_waived, false)));
  return jsonb_build_object('payment', private.guest_payment_status(v_guest));
end;
$$;
revoke all on function public.set_event_guest_waiver(uuid, uuid, boolean) from public, anon;
grant execute on function public.set_event_guest_waiver(uuid, uuid, boolean) to authenticated;

create or replace function public.set_event_guest_fee(p_organization_id uuid, p_event_id uuid, p_guest_fee numeric default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_event public.events%rowtype;
begin
  v_event := private.assert_event_payments(p_organization_id, p_event_id);
  if p_guest_fee is not null and (p_guest_fee < 0 or p_guest_fee > 10000) then
    raise exception using errcode = '22023', message = 'Enter a guest price between 0 and 10,000.';
  end if;
  update public.events set guest_fee = round(p_guest_fee, 2), updated_at = now(), updated_by_profile_id = private.current_profile_id()
  where id = p_event_id;
  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.guest_fee.set', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'update', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('old', v_event.guest_fee, 'new', round(p_guest_fee, 2)));
  return jsonb_build_object('guest_fee', round(p_guest_fee, 2));
end;
$$;
revoke all on function public.set_event_guest_fee(uuid, uuid, numeric) from public, anon;
grant execute on function public.set_event_guest_fee(uuid, uuid, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Guest check-in (QR pass at the desk, or from the list)
-- -----------------------------------------------------------------------------
create or replace function private.guest_check_in(p_event public.events, p_guest public.event_guests, p_method text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_today date := (now() at time zone 'America/New_York')::date;
  v_prev  timestamptz;
  v_first timestamptz;
  v_pay   jsonb;
  v_json  jsonb;
begin
  v_json := private.guest_json(p_guest, false);
  select c.recorded_at into v_prev from public.event_guest_check_ins c where c.guest_id = p_guest.id and c.check_in_date = v_today;
  select min(c.recorded_at) into v_first from public.event_guest_check_ins c where c.guest_id = p_guest.id;
  if v_prev is not null then
    return jsonb_build_object('result', 'guest_already_checked_in', 'guest', v_json, 'checked_in_at', v_prev, 'kit_given_at', v_first);
  end if;
  v_pay := private.guest_payment_status(p_guest);
  if v_pay->>'status' in ('unpaid', 'partial') then
    return jsonb_build_object('result', 'guest_payment_required', 'guest', v_json, 'payment', v_pay,
                              'can_record_payment', private.can_manage_event_payments(p_event.organization_id, p_event.id));
  end if;
  begin
    insert into public.event_guest_check_ins (organization_id, event_id, guest_id, check_in_date, check_in_method, recorded_by_profile_id)
    values (p_event.organization_id, p_event.id, p_guest.id, v_today, p_method, private.current_profile_id());
  exception when unique_violation then
    select c.recorded_at into v_prev from public.event_guest_check_ins c where c.guest_id = p_guest.id and c.check_in_date = v_today;
    return jsonb_build_object('result', 'guest_already_checked_in', 'guest', v_json, 'checked_in_at', v_prev, 'kit_given_at', v_first);
  end;
  perform private.write_audit_event(
    p_organization_id => p_event.organization_id, p_event_code => 'event.guest.check_in', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event.id,
    p_action => 'record_attendance', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('guest_id', p_guest.id, 'method', p_method, 'first_check_in', v_first is null));
  return jsonb_build_object('result', 'guest_checked_in', 'guest', v_json, 'payment', v_pay, 'checked_in_at', now(),
                            'first_check_in', v_first is null, 'kit_given_at', v_first);
end;
$$;
revoke all on function private.guest_check_in(public.events, public.event_guests, text) from public, anon, authenticated;

create or replace function private.guest_check_in_by_code(p_event public.events, p_code text, p_method text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare v_guest public.event_guests%rowtype;
begin
  select * into v_guest from public.event_guests g where g.guest_code = upper(btrim(coalesce(p_code, '')));
  if not found then
    return jsonb_build_object('result', 'guest_invalid', 'reason', 'unknown_guest_pass');
  end if;
  if v_guest.event_id <> p_event.id then
    return jsonb_build_object('result', 'guest_invalid', 'reason', 'other_event', 'guest', private.guest_json(v_guest, false));
  end if;
  if v_guest.cancelled_at is not null then
    return jsonb_build_object('result', 'guest_invalid', 'reason', 'cancelled', 'guest', private.guest_json(v_guest, false));
  end if;
  return private.guest_check_in(p_event, v_guest, p_method);
end;
$$;
revoke all on function private.guest_check_in_by_code(public.events, text, text) from public, anon, authenticated;

-- From the guest list (guests without a phone): the desk or the organizers
create or replace function public.check_in_event_guest(p_organization_id uuid, p_guest_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_guest public.event_guests%rowtype;
  v_event public.events%rowtype;
  v_today date := (now() at time zone 'America/New_York')::date;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select * into v_guest from public.event_guests g where g.id = p_guest_id and g.organization_id = p_organization_id and g.cancelled_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Guest not found.';
  end if;
  select * into v_event from public.events e where e.id = v_guest.event_id;
  if not (private.can_record_event_attendance(p_organization_id, v_event.id) or private.can_manage_event_payments(p_organization_id, v_event.id)) then
    raise exception using errcode = '42501', message = 'You cannot check guests in for this event.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'This event was cancelled.';
  end if;
  if v_today < private.event_ny_first_day(v_event) or v_today > private.event_ny_last_day(v_event) then
    raise exception using errcode = '22023', message = 'Guests can be checked in only on the event day(s).';
  end if;
  return private.guest_check_in(v_event, v_guest, 'manual');
end;
$$;
revoke all on function public.check_in_event_guest(uuid, uuid) from public, anon;
grant execute on function public.check_in_event_guest(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Lists: the event's guests (organizers / finance / desk) and my guests (host member)
-- -----------------------------------------------------------------------------
create or replace function public.get_event_guests(p_organization_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event   public.events%rowtype;
  v_manage  boolean;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select * into v_event from public.events e where e.id = p_event_id and e.organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  v_manage := private.can_manage_event_payments(p_organization_id, p_event_id);
  if not (v_manage or private.can_record_event_attendance(p_organization_id, p_event_id)) then
    raise exception using errcode = '42501', message = 'You cannot see the guest list for this event.';
  end if;
  return jsonb_build_object(
    'guest_fee', v_event.guest_fee,
    'guest_price_now', private.guest_price_now(v_event, false),
    'guest_walk_in_price', private.guest_price_now(v_event, true),
    'can_manage', v_manage,
    'guests', coalesce((
      select jsonb_agg(private.guest_json(g, v_manage)
                       || jsonb_build_object('payments', case when v_manage then coalesce((
                            select jsonb_agg(jsonb_build_object('payment_id', p.id, 'amount', p.amount,
                                                                'payment_method', p.payment_method, 'recorded_at', p.recorded_at)
                                             order by p.recorded_at)
                            from public.event_guest_payments p where p.guest_id = g.id and p.voided_at is null), '[]'::jsonb)
                            else '[]'::jsonb end)
                       order by lower(g.last_name), lower(g.first_name), g.id)
      from public.event_guests g where g.event_id = p_event_id and g.cancelled_at is null), '[]'::jsonb));
end;
$$;
revoke all on function public.get_event_guests(uuid, uuid) from public, anon;
grant execute on function public.get_event_guests(uuid, uuid) to authenticated;

create or replace function public.list_my_event_guests(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member uuid;
  v_today  date := (now() at time zone 'America/New_York')::date;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  return coalesce((
    select jsonb_agg(private.guest_json(g, true) order by e.starts_at, lower(g.last_name), lower(g.first_name))
    from public.event_guests g
    join public.events e on e.id = g.event_id
    where g.host_member_id = v_member and g.cancelled_at is null and e.organization_id = p_organization_id
      and e.event_status <> 'cancelled' and private.event_ny_last_day(e) >= v_today), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_event_guests(uuid) from public, anon;
grant execute on function public.list_my_event_guests(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. QR desk: guest passes; summary counts guests (replaces 090 / 087 versions, guarded above)
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

  -- Pass 9.15: guest pass (MFCNYG1:<code>)
  if upper(btrim(coalesce(p_payload, ''))) like 'MFCNYG1:%' then
    return private.guest_check_in_by_code(v_event, split_part(upper(btrim(p_payload)), ':', 2), 'qr');
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
  -- Pass 9.14: paid events need a registration; a member without one is a walk-in
  if v_pay->>'status' = 'not_registered' then
    return jsonb_build_object('result', 'not_registered', 'member', v_member, 'payment', v_pay,
                              'can_register', private.can_manage_event_payments(p_organization_id, p_event_id));
  end if;
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

create or replace function public.get_event_check_in_summary(p_organization_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event public.events%rowtype;
  v_today date := (now() at time zone 'America/New_York')::date;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'You cannot check members in for this event.';
  end if;

  return jsonb_build_object(
    'today',            v_today,
    'first_day',        private.event_ny_first_day(v_event),
    'last_day',         private.event_ny_last_day(v_event),
    'event_status',     v_event.event_status,
    'checked_in_today', (
      select count(distinct x.member_id) from (
        select c.member_id from public.event_check_ins c where c.event_id = p_event_id and c.check_in_date = v_today
        union
        select a.member_id from public.event_attendance a
        where a.event_id = p_event_id and a.removed_at is null
          and (a.recorded_at at time zone 'America/New_York')::date = v_today) x),
    'attended_total',   (select count(*) from public.event_attendance a where a.event_id = p_event_id and a.removed_at is null),
    'guests_today',     (select count(*) from public.event_guest_check_ins gc
                         where gc.event_id = p_event_id and gc.check_in_date = v_today),
    'recent', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', r.member_id, 'display_name', m.display_name,
                                          'member_number', m.member_number, 'recorded_at', r.recorded_at)
                       order by r.recorded_at desc)
      from (select c.member_id, c.recorded_at from public.event_check_ins c
            where c.event_id = p_event_id and c.check_in_date = v_today
            order by c.recorded_at desc limit 10) r
      join public.members m on m.id = r.member_id), '[]'::jsonb));
end;
$$;
revoke all on function public.get_event_check_in_summary(uuid, uuid) from public, anon;
grant execute on function public.get_event_check_in_summary(uuid, uuid) to authenticated;

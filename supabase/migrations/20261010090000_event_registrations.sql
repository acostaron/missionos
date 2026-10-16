-- =============================================================================
-- Migration: 20261010090000_event_registrations.sql
-- MissionOS Pass 9.14 (written by Claude, 2026-10-16) — run after 20261010089000.
-- Ron: paid events and conferences need registration (reservation, which comes with payment), and walk-ins
-- at the door must be handled too.
-- Ron's decisions (2026-10-16):
--   * Members register themselves in the app (My Events) AND organizers / treasurer register members.
--   * Walk-ins are allowed and marked Walk-in: the desk registers them on the spot, collects payment, checks in.
--   * Pricing: early-bird price (until a date), regular price, walk-in price.
--   * Guests (non-members) are recorded by name — that is the NEXT pass (9.15), not this one.
-- Design:
--   * events: fee_amount stays the REGULAR price; new early_bird_fee + early_bird_until, walk_in_fee, registration_open.
--   * event_registrations: one active registration per member per event, type reserved | walk_in, with the
--     price locked when they register (amount_due, price_tier). Cancelled, never deleted.
--   * Payment status is now measured against the registration's amount due. A member of a paid event with no
--     registration is 'not_registered'; at the QR desk that is offered as a walk-in.
--   * Recording a payment or a waiver for an unregistered member registers them (reserved, today's price).
-- Guarded: replaced functions must still be the 088 / 089 versions.
-- =============================================================================
do $guard$
declare
  r record;
  v_md5 text;
begin
  for r in select * from (values
    ('private', 'event_payment_status',     '32380759edc27aced36e003c9bce6c00'),
    ('public',  'get_event_payments',       '962712155259c00dccbbf8f257182474'),
    ('public',  'record_event_payment',     '8e58f1fad55d536cf55c4c68eea0c88f'),
    ('public',  'get_event_payment_access', '96ee188fd64565bf698ed6a446a70121'),
    ('public',  'scan_event_check_in',      '386e0acf6375828dc7714ea865340c1c'),
    ('public',  'set_event_fee_waiver',     'a2bd707fade4a0bdd845dc73367e1007')
  ) t(sch, fn, expected)
  loop
    select md5(replace(p.prosrc, chr(13), '')) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = r.sch and p.proname = r.fn;
    if v_md5 is distinct from r.expected then
      raise exception 'STOP: %.% differs from the version this migration was built from (md5 %).', r.sch, r.fn, v_md5;
    end if;
  end loop;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- 1. Prices and registrations
-- -----------------------------------------------------------------------------
alter table public.events
  add column if not exists early_bird_fee    numeric(10,2) null,
  add column if not exists early_bird_until  date null,
  add column if not exists walk_in_fee       numeric(10,2) null,
  add column if not exists registration_open boolean not null default false;
alter table public.events drop constraint if exists chk_events_prices;
alter table public.events add constraint chk_events_prices check (
  (early_bird_fee is null or (early_bird_fee >= 0 and early_bird_fee <= 10000))
  and (walk_in_fee is null or (walk_in_fee >= 0 and walk_in_fee <= 10000))
  and ((early_bird_fee is null) = (early_bird_until is null)));

create table if not exists public.event_registrations (
  id                       uuid primary key default gen_random_uuid(),
  organization_id          uuid not null references public.organizations(id) on delete restrict,
  event_id                 uuid not null references public.events(id) on delete restrict,
  member_id                uuid not null references public.members(id) on delete restrict,
  registration_type        text not null check (registration_type in ('reserved', 'walk_in')),
  price_tier               text not null check (price_tier in ('free', 'early_bird', 'regular', 'walk_in')),
  amount_due               numeric(10,2) not null check (amount_due >= 0 and amount_due <= 10000),
  source                   text not null check (source in ('self', 'staff', 'desk')),
  registered_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  registered_at            timestamptz not null default now(),
  cancelled_at             timestamptz null,
  cancelled_by_profile_id  uuid null references public.profiles(id) on delete set null
);
create unique index if not exists uq_event_registrations_active
  on public.event_registrations (event_id, member_id) where cancelled_at is null;
alter table public.event_registrations enable row level security;
revoke all on public.event_registrations from public, anon, authenticated;

-- Price a new registration would get right now
create or replace function private.event_price_now(p_event public.events, p_walk_in boolean)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select case
    when coalesce(p_event.fee_amount, 0) = 0 then jsonb_build_object('tier', 'free', 'amount', 0)
    when p_walk_in then jsonb_build_object('tier', 'walk_in', 'amount', coalesce(p_event.walk_in_fee, p_event.fee_amount))
    when p_event.early_bird_fee is not null and p_event.early_bird_until is not null
         and (now() at time zone 'America/New_York')::date <= p_event.early_bird_until
      then jsonb_build_object('tier', 'early_bird', 'amount', p_event.early_bird_fee)
    else jsonb_build_object('tier', 'regular', 'amount', p_event.fee_amount)
  end
$$;
revoke all on function private.event_price_now(public.events, boolean) from public, anon, authenticated;

create or replace function private.ensure_event_registration(
  p_event     public.events,
  p_member_id uuid,
  p_walk_in   boolean,
  p_source    text
)
returns uuid
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_id    uuid;
  v_price jsonb;
begin
  select r.id into v_id from public.event_registrations r
  where r.event_id = p_event.id and r.member_id = p_member_id and r.cancelled_at is null;
  if v_id is not null then
    return v_id;
  end if;
  v_price := private.event_price_now(p_event, coalesce(p_walk_in, false));
  insert into public.event_registrations (organization_id, event_id, member_id, registration_type, price_tier,
                                          amount_due, source, registered_by_profile_id)
  values (p_event.organization_id, p_event.id, p_member_id,
          case when coalesce(p_walk_in, false) then 'walk_in' else 'reserved' end,
          v_price->>'tier', (v_price->>'amount')::numeric, p_source, private.current_profile_id())
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function private.ensure_event_registration(public.events, uuid, boolean, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Payment status measured against the registration
-- -----------------------------------------------------------------------------
create or replace function private.event_payment_status(p_event public.events, p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_fee    numeric := coalesce(p_event.fee_amount, 0);
  v_reg    public.event_registrations%rowtype;
  v_paid   numeric;
  v_waived boolean;
  v_now    jsonb;
begin
  select * into v_reg from public.event_registrations r
  where r.event_id = p_event.id and r.member_id = p_member_id and r.cancelled_at is null;

  if v_fee = 0 then
    return jsonb_build_object('status', 'free', 'fee', 0, 'paid', 0, 'balance', 0,
                              'registered', v_reg.id is not null, 'registration_type', v_reg.registration_type);
  end if;

  select coalesce(sum(p.amount), 0) into v_paid from public.event_payments p
  where p.event_id = p_event.id and p.member_id = p_member_id and p.voided_at is null;
  select exists (select 1 from public.event_fee_waivers w
                 where w.event_id = p_event.id and w.member_id = p_member_id and w.removed_at is null) into v_waived;

  if v_reg.id is null then
    v_now := private.event_price_now(p_event, false);
    return jsonb_build_object('status', 'not_registered', 'registered', false,
                              'fee', (v_now->>'amount')::numeric, 'price_tier', v_now->>'tier',
                              'walk_in_fee', (private.event_price_now(p_event, true)->>'amount')::numeric,
                              'paid', v_paid, 'balance', (v_now->>'amount')::numeric);
  end if;

  return jsonb_build_object(
    'status',            case when v_waived then 'waived'
                              when v_paid >= v_reg.amount_due then 'paid'
                              when v_paid > 0 then 'partial'
                              else 'unpaid' end,
    'registered',        true,
    'registration_type', v_reg.registration_type,
    'price_tier',        v_reg.price_tier,
    'registered_at',     v_reg.registered_at,
    'fee',               v_reg.amount_due,
    'paid',              v_paid,
    'balance',           case when v_waived then 0 else greatest(v_reg.amount_due - v_paid, 0) end);
end;
$$;
revoke all on function private.event_payment_status(public.events, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Prices and registration window (organizers / finance)
-- -----------------------------------------------------------------------------
create or replace function public.set_event_pricing(
  p_organization_id   uuid,
  p_event_id          uuid,
  p_fee_amount        numeric default null,
  p_early_bird_fee    numeric default null,
  p_early_bird_until  date default null,
  p_walk_in_fee       numeric default null,
  p_registration_open boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event public.events%rowtype;
  v_fee   numeric := nullif(round(coalesce(p_fee_amount, 0), 2), 0);
begin
  v_event := private.assert_event_payments(p_organization_id, p_event_id);
  if coalesce(p_fee_amount, 0) < 0 or coalesce(p_fee_amount, 0) > 10000
     or coalesce(p_early_bird_fee, 0) < 0 or coalesce(p_early_bird_fee, 0) > 10000
     or coalesce(p_walk_in_fee, 0) < 0 or coalesce(p_walk_in_fee, 0) > 10000 then
    raise exception using errcode = '22023', message = 'Enter prices between 0 and 10,000.';
  end if;
  if (p_early_bird_fee is null) <> (p_early_bird_until is null) then
    raise exception using errcode = '22023', message = 'Give both the early-bird price and its last day, or neither.';
  end if;
  if v_fee is null and (p_early_bird_fee is not null or p_walk_in_fee is not null) then
    raise exception using errcode = '22023', message = 'Set the regular price first.';
  end if;

  update public.events
     set fee_amount        = v_fee,
         early_bird_fee    = case when v_fee is null then null else round(p_early_bird_fee, 2) end,
         early_bird_until  = case when v_fee is null then null else p_early_bird_until end,
         walk_in_fee       = case when v_fee is null then null else round(p_walk_in_fee, 2) end,
         registration_open = coalesce(p_registration_open, false),
         updated_at        = now(),
         updated_by_profile_id = private.current_profile_id()
   where id = p_event_id
  returning * into v_event;

  -- registrations made while the event was free get the price for the day they registered
  if v_fee is not null then
    update public.event_registrations r
       set price_tier = case when r.registration_type = 'walk_in' then 'walk_in'
                             when v_event.early_bird_until is not null
                                  and (r.registered_at at time zone 'America/New_York')::date <= v_event.early_bird_until
                               then 'early_bird' else 'regular' end,
           amount_due = case when r.registration_type = 'walk_in' then coalesce(v_event.walk_in_fee, v_event.fee_amount)
                             when v_event.early_bird_until is not null
                                  and (r.registered_at at time zone 'America/New_York')::date <= v_event.early_bird_until
                               then v_event.early_bird_fee else v_event.fee_amount end
     where r.event_id = p_event_id and r.cancelled_at is null and r.price_tier = 'free';
  end if;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.pricing.set', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'update', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('fee', v_event.fee_amount, 'early_bird_fee', v_event.early_bird_fee,
                                     'early_bird_until', v_event.early_bird_until, 'walk_in_fee', v_event.walk_in_fee,
                                     'registration_open', v_event.registration_open));
  return jsonb_build_object('fee_amount', v_event.fee_amount, 'early_bird_fee', v_event.early_bird_fee,
                            'early_bird_until', v_event.early_bird_until, 'walk_in_fee', v_event.walk_in_fee,
                            'registration_open', v_event.registration_open);
end;
$$;
revoke all on function public.set_event_pricing(uuid, uuid, numeric, numeric, date, numeric, boolean) from public, anon;
grant execute on function public.set_event_pricing(uuid, uuid, numeric, numeric, date, numeric, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Register / cancel (member for themselves, or organizers / finance / the desk for a member)
-- -----------------------------------------------------------------------------
create or replace function public.register_for_event(
  p_organization_id uuid,
  p_event_id        uuid,
  p_member_id       uuid default null,     -- null = register myself
  p_walk_in         boolean default false   -- desk only
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event  public.events%rowtype;
  v_member uuid;
  v_source text;
  v_before uuid;
  v_id     uuid;
begin
  if p_member_id is null then
    v_member := private.assert_member_self_service(p_organization_id);
    select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Event not found.';
    end if;
    if not v_event.registration_open then
      raise exception using errcode = '22023', message = 'Registration is not open for this event.';
    end if;
    if not private.member_in_event_audience(p_organization_id, v_member, v_event.audience_node_id) then
      raise exception using errcode = '42501', message = 'This event is not open to you.';
    end if;
    if coalesce(p_walk_in, false) then
      raise exception using errcode = '22023', message = 'Walk-ins are registered at the desk.';
    end if;
    v_source := 'self';
  else
    v_event := private.assert_event_payments(p_organization_id, p_event_id);
    v_member := p_member_id;
    if not exists (select 1 from public.members m where m.id = v_member and m.organization_id = p_organization_id
                   and m.record_status = 'active' and m.archived_at is null) then
      raise exception using errcode = 'P0002', message = 'Member not found or not active.';
    end if;
    v_source := case when coalesce(p_walk_in, false) then 'desk' else 'staff' end;
  end if;

  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'This event was cancelled.';
  end if;
  if (now() at time zone 'America/New_York')::date > private.event_ny_last_day(v_event) then
    raise exception using errcode = '22023', message = 'This event is over.';
  end if;

  select r.id into v_before from public.event_registrations r
  where r.event_id = p_event_id and r.member_id = v_member and r.cancelled_at is null;
  v_id := private.ensure_event_registration(v_event, v_member, coalesce(p_walk_in, false), v_source);

  if v_before is null then
    perform private.write_audit_event(
      p_organization_id => p_organization_id, p_event_code => 'event.registration.created', p_event_category => 'governance',
      p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
      p_action => 'create', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
      p_metadata => jsonb_build_object('registration_id', v_id, 'member_id', v_member, 'source', v_source,
                                       'walk_in', coalesce(p_walk_in, false)));
  end if;
  return jsonb_build_object('registration_id', v_id, 'already_registered', v_before is not null,
                            'payment', private.event_payment_status(v_event, v_member));
end;
$$;
revoke all on function public.register_for_event(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.register_for_event(uuid, uuid, uuid, boolean) to authenticated;

create or replace function public.cancel_event_registration(
  p_organization_id uuid,
  p_event_id        uuid,
  p_member_id       uuid default null      -- null = my own registration
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_event  public.events%rowtype;
  v_member uuid;
  v_reg    uuid;
begin
  if p_member_id is null then
    v_member := private.assert_member_self_service(p_organization_id);
    select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Event not found.';
    end if;
  else
    v_event := private.assert_event_payments(p_organization_id, p_event_id);
    v_member := p_member_id;
  end if;

  select r.id into v_reg from public.event_registrations r
  where r.event_id = p_event_id and r.member_id = v_member and r.cancelled_at is null
  for update;
  if v_reg is null then
    raise exception using errcode = 'P0002', message = 'No registration to cancel.';
  end if;
  if exists (select 1 from public.event_payments p where p.event_id = p_event_id and p.member_id = v_member and p.voided_at is null) then
    raise exception using errcode = '22023', message = case when p_member_id is null
      then 'A payment is already recorded. Please contact the registration team to cancel.'
      else 'Void the recorded payments first.' end;
  end if;
  if exists (select 1 from public.event_attendance a where a.event_id = p_event_id and a.member_id = v_member and a.removed_at is null) then
    raise exception using errcode = '22023', message = 'Already checked in — the registration cannot be cancelled.';
  end if;

  update public.event_registrations set cancelled_at = now(), cancelled_by_profile_id = private.current_profile_id()
  where id = v_reg;
  update public.event_fee_waivers set removed_at = now(), removed_by_profile_id = private.current_profile_id()
  where event_id = p_event_id and member_id = v_member and removed_at is null;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.registration.cancelled', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'cancel', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('registration_id', v_reg, 'member_id', v_member, 'by_member', p_member_id is null));
  return jsonb_build_object('cancelled', true);
end;
$$;
revoke all on function public.cancel_event_registration(uuid, uuid, uuid) from public, anon;
grant execute on function public.cancel_event_registration(uuid, uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. My Events: events open for registration, with my registration and balance
-- -----------------------------------------------------------------------------
create or replace function public.list_my_event_registrations(p_organization_id uuid)
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
    select jsonb_agg(jsonb_build_object(
             'event_id',          e.id,
             'title',             e.title,
             'event_type',        e.event_type,
             'starts_at',         e.starts_at,
             'ends_at',           e.ends_at,
             'location_text',     e.location_text,
             'registration_open', e.registration_open,
             'fee_amount',        e.fee_amount,
             'early_bird_fee',    e.early_bird_fee,
             'early_bird_until',  e.early_bird_until,
             'walk_in_fee',       e.walk_in_fee,
             'price_now',         private.event_price_now(e, false),
             'my',                private.event_payment_status(e, v_member),
             'checked_in',        exists (select 1 from public.event_attendance a
                                          where a.event_id = e.id and a.member_id = v_member and a.removed_at is null))
           order by e.starts_at)
    from public.events e
    where e.organization_id = p_organization_id
      and e.event_status <> 'cancelled'
      and private.event_ny_last_day(e) >= v_today
      and ((e.registration_open and private.member_in_event_audience(p_organization_id, v_member, e.audience_node_id))
           or exists (select 1 from public.event_registrations r
                      where r.event_id = e.id and r.member_id = v_member and r.cancelled_at is null))
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_event_registrations(uuid) from public, anon;
grant execute on function public.list_my_event_registrations(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Access + prices for the event page
-- -----------------------------------------------------------------------------
create or replace function public.get_event_payment_access(p_organization_id uuid, p_event_id uuid)
returns jsonb
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
  select * into v_event from public.events e where e.id = p_event_id and e.organization_id = p_organization_id;
  return jsonb_build_object(
    'fee_amount',          v_event.fee_amount,
    'early_bird_fee',      v_event.early_bird_fee,
    'early_bird_until',    v_event.early_bird_until,
    'walk_in_fee',         v_event.walk_in_fee,
    'registration_open',   coalesce(v_event.registration_open, false),
    'can_manage_payments', private.can_manage_event_payments(p_organization_id, p_event_id),
    'can_tick_attendance', coalesce(v_event.fee_amount, 0) = 0
                           or private.can_tick_paid_event_attendance(p_organization_id, p_event_id));
end;
$$;
revoke all on function public.get_event_payment_access(uuid, uuid) from public, anon;
grant execute on function public.get_event_payment_access(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Registrations & payments list (organizers / finance)
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
      select r.member_id from public.event_registrations r where r.event_id = p_event_id and r.cancelled_at is null
      union
      select p.member_id from public.event_payments p where p.event_id = p_event_id and p.voided_at is null
      union
      select w.member_id from public.event_fee_waivers w where w.event_id = p_event_id and w.removed_at is null
    ),
    rws as (
      select m.id, m.display_name, m.member_number, m.sort_name,
             private.event_payment_status(v_event, m.id) as st,
             exists (select 1 from public.event_attendance a
                     where a.event_id = p_event_id and a.member_id = m.id and a.removed_at is null) as checked_in
      from ppl join public.members m on m.id = ppl.member_id
    )
    select jsonb_build_object(
      'fee_amount',        v_event.fee_amount,
      'early_bird_fee',    v_event.early_bird_fee,
      'early_bird_until',  v_event.early_bird_until,
      'walk_in_fee',       v_event.walk_in_fee,
      'registration_open', v_event.registration_open,
      'totals', jsonb_build_object(
        'registered', count(*) filter (where (r.st->>'registered')::boolean),
        'reserved',   count(*) filter (where r.st->>'registration_type' = 'reserved'),
        'walk_in',    count(*) filter (where r.st->>'registration_type' = 'walk_in'),
        'checked_in', count(*) filter (where r.checked_in),
        'paid',       count(*) filter (where r.st->>'status' = 'paid'),
        'partial',    count(*) filter (where r.st->>'status' = 'partial'),
        'unpaid',     count(*) filter (where r.st->>'status' = 'unpaid'),
        'waived',     count(*) filter (where r.st->>'status' = 'waived'),
        'expected',   coalesce(sum((r.st->>'fee')::numeric) filter (where r.st->>'status' in ('paid', 'partial', 'unpaid')), 0),
        'collected',  coalesce((select sum(p.amount) from public.event_payments p
                                where p.event_id = p_event_id and p.voided_at is null), 0)),
      'members', coalesce(jsonb_agg(jsonb_build_object(
          'member_id', r.id, 'display_name', r.display_name, 'member_number', r.member_number,
          'payment', r.st, 'checked_in', r.checked_in,
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

-- -----------------------------------------------------------------------------
-- 8. Payment / waiver register the member; QR desk handles walk-ins
-- -----------------------------------------------------------------------------
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
  if p_payment_method is null or p_payment_method not in ('cash', 'check', 'zelle', 'paypal', 'card', 'other') then
    raise exception using errcode = '22023', message = 'Choose how it was paid.';
  end if;
  if not exists (select 1 from public.members m where m.id = p_member_id and m.organization_id = p_organization_id
                 and m.record_status = 'active' and m.archived_at is null) then
    raise exception using errcode = 'P0002', message = 'Member not found or not active.';
  end if;

  -- Pass 9.14: a payment registers the member (reserved, at today's price) if not registered yet
  perform private.ensure_event_registration(v_event, p_member_id, false, 'staff');

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
    perform private.ensure_event_registration(v_event, p_member_id, false, 'staff');   -- Pass 9.14
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

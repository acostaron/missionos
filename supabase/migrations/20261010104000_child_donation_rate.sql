-- =============================================================================
-- Migration: 20261010104000_child_donation_rate.sql
-- MissionOS Pass 9.32 (written by Claude, 2026-10-21) — run after 20261010103000.
-- Ron (2026-10-21): events with a donation get a discounted option for children below 18.
--   * events.child_fee: a fixed child amount per event (0 = children free; blank = no child rate);
--   * members under 18 on the event day (from their birth date) get it automatically when they register;
--   * guests get it when added with "Child (under 18)" ticked (event_guests.is_child);
--   * setting / changing / removing the child rate re-prices children's registrations that have nothing donated yet.
-- Guarded: replaced functions must still be the 090 / 091 versions.
-- =============================================================================
do $guard$
declare
  r record;
  v_md5 text;
begin
  for r in select * from (values
    ('private', 'ensure_event_registration', '98c46e69c41916f0835d62244f12941b'),
    ('private', 'event_payment_status', '37a6176dc03ae4cb42f286128795c815'),
    ('public', 'set_event_pricing', '7706f3dbba318dc3541dd088e90221d5'),
    ('public', 'list_my_event_registrations', '8fd99eee8cd165e0bb2bbeb1e4cdd49c'),
    ('public', 'get_event_payments', '08638b0336b2392755affb6dabb23a57'),
    ('public', 'add_event_guest', '595e2d423f04e78c62e10adc111c2f5c'),
    ('private', 'guest_json', '4edfca6a737a1f59688296fab7d11ba7'),
    ('public', 'get_event_guests', 'dafaa605ad3ebd0fc7fce1ba7cf0c1db')
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

-- 1. Child rate, child tier, child guests
alter table public.events add column if not exists child_fee numeric(10,2) null;
alter table public.events drop constraint if exists chk_events_child_fee;
alter table public.events add constraint chk_events_child_fee check (child_fee is null or (child_fee >= 0 and child_fee <= 10000));

alter table public.event_guests add column if not exists is_child boolean not null default false;

do $c$
declare v record;
begin
  for v in
    select c.conrelid::regclass::text as tbl, c.conname from pg_constraint c
    where c.conrelid in ('public.event_registrations'::regclass, 'public.event_guests'::regclass) and c.contype = 'c'
      and pg_get_constraintdef(c.oid) like '%price_tier%'
  loop
    execute format('alter table %s drop constraint %I', v.tbl, v.conname);
  end loop;
end;
$c$;
alter table public.event_registrations add constraint event_registrations_price_tier_check
  check (price_tier in ('free', 'early_bird', 'regular', 'walk_in', 'child'));
alter table public.event_guests add constraint event_guests_price_tier_check
  check (price_tier in ('free', 'guest', 'early_bird', 'regular', 'walk_in', 'child'));

-- Under 18 on the (first) day of the event, by the member's birth date
create or replace function private.member_is_child(p_event public.events, p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce((
    select m.birth_date > ((p_event.starts_at at time zone 'America/New_York')::date - interval '18 years')::date
    from public.members m where m.id = p_member_id and m.birth_date is not null), false)
$$;
revoke all on function private.member_is_child(public.events, uuid) from public, anon, authenticated;

-- Price this member would get right now (child rate for children, else the event price)
create or replace function private.member_price_now(p_event public.events, p_member_id uuid, p_walk_in boolean)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select case
    when coalesce(p_event.fee_amount, 0) = 0 then jsonb_build_object('tier', 'free', 'amount', 0)
    when p_event.child_fee is not null and private.member_is_child(p_event, p_member_id)
      then jsonb_build_object('tier', 'child', 'amount', p_event.child_fee)
    else private.event_price_now(p_event, p_walk_in)
  end
$$;
revoke all on function private.member_price_now(public.events, uuid, boolean) from public, anon, authenticated;

-- 2. Functions
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
  v_price := private.member_price_now(p_event, p_member_id, coalesce(p_walk_in, false));   -- Pass 9.32: child rate
  insert into public.event_registrations (organization_id, event_id, member_id, registration_type, price_tier,
                                          amount_due, source, registered_by_profile_id)
  values (p_event.organization_id, p_event.id, p_member_id,
          case when coalesce(p_walk_in, false) then 'walk_in' else 'reserved' end,
          v_price->>'tier', (v_price->>'amount')::numeric, p_source, private.current_profile_id())
  returning id into v_id;
  return v_id;
end;
$$;

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
    v_now := private.member_price_now(p_event, p_member_id, false);
    return jsonb_build_object('status', 'not_registered', 'registered', false,
                              'fee', (v_now->>'amount')::numeric, 'price_tier', v_now->>'tier',
                              'walk_in_fee', (private.member_price_now(p_event, p_member_id, true)->>'amount')::numeric,
                              'paid', v_paid, 'balance', (v_now->>'amount')::numeric);
  end if;

  return jsonb_build_object(
    'status',            case when v_waived then 'waived'
                              when v_reg.amount_due = 0 and v_paid = 0 then 'free'
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

drop function if exists public.set_event_pricing(uuid, uuid, numeric, numeric, date, numeric, boolean);
create or replace function public.set_event_pricing(
  p_organization_id   uuid,
  p_event_id          uuid,
  p_fee_amount        numeric default null,
  p_early_bird_fee    numeric default null,
  p_early_bird_until  date default null,
  p_walk_in_fee       numeric default null,
  p_registration_open boolean default false,
  p_child_fee         numeric default null
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
     or coalesce(p_walk_in_fee, 0) < 0 or coalesce(p_walk_in_fee, 0) > 10000
     or coalesce(p_child_fee, 0) < 0 or coalesce(p_child_fee, 0) > 10000 then
    raise exception using errcode = '22023', message = 'Enter prices between 0 and 10,000.';
  end if;
  if (p_early_bird_fee is null) <> (p_early_bird_until is null) then
    raise exception using errcode = '22023', message = 'Give both the early-bird price and its last day, or neither.';
  end if;
  if v_fee is null and (p_early_bird_fee is not null or p_walk_in_fee is not null or p_child_fee is not null) then
    raise exception using errcode = '22023', message = 'Set the regular price first.';
  end if;

  update public.events
     set fee_amount        = v_fee,
         early_bird_fee    = case when v_fee is null then null else round(p_early_bird_fee, 2) end,
         early_bird_until  = case when v_fee is null then null else p_early_bird_until end,
         walk_in_fee       = case when v_fee is null then null else round(p_walk_in_fee, 2) end,
         child_fee         = case when v_fee is null then null else round(p_child_fee, 2) end,
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

  -- Pass 9.32: children (under 18 on the event day) with nothing donated yet get the child rate; if the child rate is
  -- removed they go back to the price for the day they registered.
  if v_fee is not null then
    update public.event_registrations r
       set price_tier = case when v_event.child_fee is not null then 'child'
                             when r.registration_type = 'walk_in' then 'walk_in'
                             when v_event.early_bird_until is not null
                                  and (r.registered_at at time zone 'America/New_York')::date <= v_event.early_bird_until
                               then 'early_bird' else 'regular' end,
           amount_due = case when v_event.child_fee is not null then v_event.child_fee
                             when r.registration_type = 'walk_in' then coalesce(v_event.walk_in_fee, v_event.fee_amount)
                             when v_event.early_bird_until is not null
                                  and (r.registered_at at time zone 'America/New_York')::date <= v_event.early_bird_until
                               then v_event.early_bird_fee else v_event.fee_amount end
     where r.event_id = p_event_id and r.cancelled_at is null
       and (r.price_tier = 'child' or (v_event.child_fee is not null and private.member_is_child(v_event, r.member_id)))
       and not exists (select 1 from public.event_payments x where x.event_id = p_event_id and x.member_id = r.member_id
                       and x.voided_at is null);
    update public.event_guests g
       set price_tier = case when v_event.child_fee is not null then 'child' else (private.guest_price_now(v_event, g.registration_type = 'walk_in')->>'tier') end,
           amount_due = case when v_event.child_fee is not null then v_event.child_fee
                             else (private.guest_price_now(v_event, g.registration_type = 'walk_in')->>'amount')::numeric end
     where g.event_id = p_event_id and g.cancelled_at is null and g.is_child
       and coalesce(private.guest_price_now(v_event, false)->>'tier', '') <> 'free'
       and not exists (select 1 from public.event_guest_payments x where x.guest_id = g.id and x.voided_at is null);
  end if;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.pricing.set', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'update', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('fee', v_event.fee_amount, 'early_bird_fee', v_event.early_bird_fee,
                                     'early_bird_until', v_event.early_bird_until, 'walk_in_fee', v_event.walk_in_fee,
                                     'registration_open', v_event.registration_open, 'child_fee', v_event.child_fee));
  return jsonb_build_object('fee_amount', v_event.fee_amount, 'early_bird_fee', v_event.early_bird_fee,
                            'early_bird_until', v_event.early_bird_until, 'walk_in_fee', v_event.walk_in_fee,
                            'registration_open', v_event.registration_open, 'child_fee', v_event.child_fee);
end;
$$;
revoke all on function public.set_event_pricing(uuid, uuid, numeric, numeric, date, numeric, boolean, numeric) from public, anon;
grant execute on function public.set_event_pricing(uuid, uuid, numeric, numeric, date, numeric, boolean, numeric) to authenticated;

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
             'child_fee',         e.child_fee,
             'price_now',         private.member_price_now(e, v_member, false),
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
      'child_fee',         v_event.child_fee,
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
    'is_child',     p_guest.is_child,
    'registered_at', p_guest.registered_at,
    'payment',      private.guest_payment_status(p_guest),
    'checked_in_today', exists (select 1 from public.event_guest_check_ins c where c.guest_id = p_guest.id
                                and c.check_in_date = (now() at time zone 'America/New_York')::date),
    'checked_in_ever',  exists (select 1 from public.event_guest_check_ins c where c.guest_id = p_guest.id))
$$;

drop function if exists public.add_event_guest(uuid, uuid, text, text, text, text, boolean, uuid, boolean);
create or replace function public.add_event_guest(
  p_organization_id uuid,
  p_event_id        uuid,
  p_first_name      text,
  p_last_name       text,
  p_phone           text default null,
  p_email           text default null,
  p_as_staff        boolean default false,   -- false = I am adding my own guest (My Events)
  p_host_member_id  uuid default null,       -- staff only; null = no host member
  p_walk_in         boolean default false,   -- staff at the desk
  p_is_child        boolean default false    -- Pass 9.32: child (under 18) gets the event's child rate
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
  if coalesce(p_is_child, false) and v_event.child_fee is not null and v_price->>'tier' <> 'free' then
    v_price := jsonb_build_object('tier', 'child', 'amount', v_event.child_fee);
  end if;
  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    exit when not exists (select 1 from public.event_guests g where g.guest_code = v_code);
  end loop;

  insert into public.event_guests (organization_id, event_id, host_member_id, first_name, last_name, phone, email,
                                   registration_type, price_tier, amount_due, source, guest_code, registered_by_profile_id,
                                   is_child)
  values (p_organization_id, p_event_id, v_host, btrim(p_first_name), btrim(p_last_name), v_phone, v_email,
          case when coalesce(p_walk_in, false) then 'walk_in' else 'reserved' end,
          v_price->>'tier', (v_price->>'amount')::numeric, v_source, v_code, private.current_profile_id(),
          coalesce(p_is_child, false))
  returning * into v_guest;

  perform private.write_audit_event(
    p_organization_id => p_organization_id, p_event_code => 'event.guest.added', p_event_category => 'governance',
    p_actor_profile_id => private.current_profile_id(), p_entity_type => 'event', p_entity_id => p_event_id,
    p_action => 'create', p_outcome => 'success', p_access_reason => null, p_correlation_id => null,
    p_metadata => jsonb_build_object('guest_id', v_guest.id, 'host_member_id', v_host, 'source', v_source));
  return private.guest_json(v_guest, true);
end;
$$;
revoke all on function public.add_event_guest(uuid, uuid, text, text, text, text, boolean, uuid, boolean, boolean) from public, anon;
grant execute on function public.add_event_guest(uuid, uuid, text, text, text, text, boolean, uuid, boolean, boolean) to authenticated;

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
    'child_fee', v_event.child_fee,
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

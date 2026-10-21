-- =============================================================================
-- Migration: 20261010102000_advance_payments.sql
-- MissionOS Pass 9.29 (written by Claude, 2026-10-21) — run after 20261010101000.
-- Ron (2026-10-21):
--   * a member's reply drives registration: Attending registers (when registration is open), Not attending cancels
--     an unpaid registration;
--   * advance payment by Zelle or PayPal: My Events shows the Zelle recipient and PayPal link; the member reports
--     "I sent payment" (method, amount, reference); it stays "awaiting confirmation" until the treasurer / finance
--     coordinator / event payment manager confirms it (which records the payment) or declines it;
--   * Zelle / PayPal details are set once for the organization, with an optional override per event.
-- Guarded: replaces set_my_reply only if unchanged from 20261010101000.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'set_my_reply';
  if v_md5 is distinct from 'aa1848ca056a4b021084fb7a45640d0d' then
    raise exception 'STOP: public.set_my_reply differs from 20261010101000 (md5 %).', v_md5;
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- 1. Zelle / PayPal details: organization default + optional per-event override
-- -----------------------------------------------------------------------------
create table if not exists public.organization_payment_details (
  organization_id        uuid primary key references public.organizations(id) on delete cascade,
  zelle_recipient        text null check (zelle_recipient is null or length(btrim(zelle_recipient)) between 3 and 120),
  zelle_name             text null check (zelle_name is null or length(btrim(zelle_name)) between 1 and 120),
  paypal_link            text null check (paypal_link is null or (paypal_link ~* '^https://' and length(paypal_link) <= 300)),
  payment_note           text null check (payment_note is null or length(payment_note) <= 500),
  updated_at             timestamptz not null default now(),
  updated_by_profile_id  uuid null references public.profiles(id) on delete set null
);
alter table public.organization_payment_details enable row level security;
revoke all on public.organization_payment_details from public, anon, authenticated;

alter table public.events
  add column if not exists zelle_recipient text null,
  add column if not exists zelle_name text null,
  add column if not exists paypal_link text null,
  add column if not exists payment_note text null;
alter table public.events drop constraint if exists events_payment_details_check;
alter table public.events add constraint events_payment_details_check check (
  (zelle_recipient is null or length(btrim(zelle_recipient)) between 3 and 120)
  and (zelle_name is null or length(btrim(zelle_name)) between 1 and 120)
  and (paypal_link is null or (paypal_link ~* '^https://' and length(paypal_link) <= 300))
  and (payment_note is null or length(payment_note) <= 500));

-- Effective details for an event (event override first, then the organization default). Any member of the org may read.
create or replace function public.get_payment_details(p_organization_id uuid, p_event_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_org public.organization_payment_details%rowtype;
  v_ev  public.events%rowtype;
begin
  if private.current_profile_id() is null or not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;
  select * into v_org from public.organization_payment_details where organization_id = p_organization_id;
  if p_event_id is not null then
    select * into v_ev from public.events where id = p_event_id and organization_id = p_organization_id;
  end if;
  return jsonb_build_object(
    'zelle_recipient', coalesce(v_ev.zelle_recipient, v_org.zelle_recipient),
    'zelle_name',      coalesce(v_ev.zelle_name, v_org.zelle_name),
    'paypal_link',     coalesce(v_ev.paypal_link, v_org.paypal_link),
    'payment_note',    coalesce(v_ev.payment_note, v_org.payment_note),
    'organization', jsonb_build_object('zelle_recipient', v_org.zelle_recipient, 'zelle_name', v_org.zelle_name,
                                       'paypal_link', v_org.paypal_link, 'payment_note', v_org.payment_note),
    'event', case when v_ev.id is null then null else
               jsonb_build_object('zelle_recipient', v_ev.zelle_recipient, 'zelle_name', v_ev.zelle_name,
                                  'paypal_link', v_ev.paypal_link, 'payment_note', v_ev.payment_note) end,
    'can_edit_organization', private.is_organization_administrator(private.current_profile_id(), p_organization_id)
                             or private.is_finance_coordinator(p_organization_id),
    'can_edit_event', case when v_ev.id is null then false
                           else private.can_manage_event_payments(p_organization_id, p_event_id) end);
end;
$$;
revoke all on function public.get_payment_details(uuid, uuid) from public, anon;
grant execute on function public.get_payment_details(uuid, uuid) to authenticated;

-- Set details: p_event_id null = organization default (administrator / finance coordinator);
-- otherwise the event override (event payment managers). Blank values clear a field.
create or replace function public.set_payment_details(
  p_organization_id uuid,
  p_event_id        uuid default null,
  p_zelle_recipient text default null,
  p_zelle_name      text default null,
  p_paypal_link     text default null,
  p_payment_note    text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_profile uuid := private.current_profile_id();
  v_zr text := nullif(btrim(coalesce(p_zelle_recipient, '')), '');
  v_zn text := nullif(btrim(coalesce(p_zelle_name, '')), '');
  v_pl text := nullif(btrim(coalesce(p_paypal_link, '')), '');
  v_pn text := nullif(btrim(coalesce(p_payment_note, '')), '');
begin
  if v_profile is null or not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;
  if v_pl is not null and v_pl !~* '^https://' then
    raise exception using errcode = '22023', message = 'The PayPal link must start with https:// (e.g. https://paypal.me/yourname).';
  end if;

  if p_event_id is null then
    if not (private.is_organization_administrator(v_profile, p_organization_id) or private.is_finance_coordinator(p_organization_id)) then
      raise exception using errcode = '42501', message = 'Only an administrator or the finance coordinator can set the payment details.';
    end if;
    insert into public.organization_payment_details (organization_id, zelle_recipient, zelle_name, paypal_link, payment_note,
                                                     updated_at, updated_by_profile_id)
    values (p_organization_id, v_zr, v_zn, v_pl, v_pn, now(), v_profile)
    on conflict (organization_id) do update
      set zelle_recipient = excluded.zelle_recipient, zelle_name = excluded.zelle_name,
          paypal_link = excluded.paypal_link, payment_note = excluded.payment_note,
          updated_at = now(), updated_by_profile_id = v_profile;
  else
    if not exists (select 1 from public.events where id = p_event_id and organization_id = p_organization_id) then
      raise exception using errcode = 'P0002', message = 'Event not found.';
    end if;
    if not private.can_manage_event_payments(p_organization_id, p_event_id) then
      raise exception using errcode = '42501', message = 'You do not have permission to manage payments for this event.';
    end if;
    update public.events
       set zelle_recipient = v_zr, zelle_name = v_zn, paypal_link = v_pl, payment_note = v_pn,
           updated_at = now(), updated_by_profile_id = v_profile
     where id = p_event_id;
  end if;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'event.payment_details.set',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile,
    p_entity_type      => case when p_event_id is null then 'organization' else 'event' end,
    p_entity_id        => coalesce(p_event_id, p_organization_id),
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('has_zelle', v_zr is not null, 'has_paypal', v_pl is not null));
  return public.get_payment_details(p_organization_id, p_event_id);
end;
$$;
revoke all on function public.set_payment_details(uuid, uuid, text, text, text, text) from public, anon;
grant execute on function public.set_payment_details(uuid, uuid, text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Payments reported by members (awaiting confirmation)
-- -----------------------------------------------------------------------------
create table if not exists public.event_payment_reports (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete restrict,
  event_id               uuid not null references public.events(id) on delete restrict,
  member_id              uuid not null references public.members(id) on delete restrict,
  amount                 numeric(10,2) not null check (amount > 0 and amount <= 10000),
  payment_method         text not null check (payment_method in ('zelle', 'paypal')),
  reference              text null check (reference is null or length(reference) <= 120),
  report_status          text not null default 'pending' check (report_status in ('pending', 'confirmed', 'declined', 'withdrawn')),
  reported_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  reported_at            timestamptz not null default now(),
  reviewed_by_profile_id uuid null references public.profiles(id) on delete set null,
  reviewed_at            timestamptz null,
  decline_reason         text null check (decline_reason is null or length(decline_reason) <= 300),
  payment_id             uuid null references public.event_payments(id) on delete set null
);
create index if not exists ix_event_payment_reports_event on public.event_payment_reports (event_id, report_status);
create index if not exists ix_event_payment_reports_member on public.event_payment_reports (member_id, event_id);
alter table public.event_payment_reports enable row level security;
revoke all on public.event_payment_reports from public, anon, authenticated;

-- Member: "I sent payment"
create or replace function public.report_my_event_payment(
  p_organization_id uuid,
  p_event_id        uuid,
  p_payment_method  text,
  p_amount          numeric,
  p_reference       text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member uuid;
  v_event  public.events%rowtype;
  v_id     uuid;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
  if v_event.id is null then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'This event was cancelled.';
  end if;
  if lower(coalesce(p_payment_method, '')) not in ('zelle', 'paypal') then
    raise exception using errcode = '22023', message = 'Choose Zelle or PayPal.';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000 then
    raise exception using errcode = '22023', message = 'Enter the amount you sent.';
  end if;
  if not exists (select 1 from public.event_registrations r
                 where r.event_id = p_event_id and r.member_id = v_member and r.cancelled_at is null) then
    raise exception using errcode = '22023', message = 'Register for the event first.';
  end if;
  if (select count(*) from public.event_payment_reports pr
      where pr.event_id = p_event_id and pr.member_id = v_member and pr.report_status = 'pending') >= 3 then
    raise exception using errcode = '22023', message = 'You already have payments awaiting confirmation for this event.';
  end if;

  insert into public.event_payment_reports (organization_id, event_id, member_id, amount, payment_method, reference,
                                            reported_by_profile_id)
  values (p_organization_id, p_event_id, v_member, round(p_amount, 2), lower(p_payment_method),
          nullif(btrim(coalesce(p_reference, '')), ''), private.current_profile_id())
  returning id into v_id;
  return jsonb_build_object('report_id', v_id, 'report_status', 'pending');
end;
$$;
revoke all on function public.report_my_event_payment(uuid, uuid, text, numeric, text) from public, anon;
grant execute on function public.report_my_event_payment(uuid, uuid, text, numeric, text) to authenticated;

-- Member: withdraw a report that is still pending (e.g. a typo)
create or replace function public.withdraw_my_payment_report(p_organization_id uuid, p_report_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member uuid;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  update public.event_payment_reports
     set report_status = 'withdrawn', reviewed_at = now(), reviewed_by_profile_id = private.current_profile_id()
   where id = p_report_id and organization_id = p_organization_id and member_id = v_member and report_status = 'pending';
  if not found then
    raise exception using errcode = 'P0002', message = 'No pending payment report to withdraw.';
  end if;
  return jsonb_build_object('report_status', 'withdrawn');
end;
$$;
revoke all on function public.withdraw_my_payment_report(uuid, uuid) from public, anon;
grant execute on function public.withdraw_my_payment_report(uuid, uuid) to authenticated;

-- Member: my reports (events not yet over by more than 30 days)
create or replace function public.list_my_payment_reports(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member uuid;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'report_id', pr.id, 'event_id', pr.event_id, 'amount', pr.amount, 'payment_method', pr.payment_method,
             'reference', pr.reference, 'report_status', pr.report_status, 'reported_at', pr.reported_at,
             'decline_reason', pr.decline_reason) order by pr.reported_at desc)
    from public.event_payment_reports pr
    join public.events e on e.id = pr.event_id
    where pr.organization_id = p_organization_id and pr.member_id = v_member
      and pr.report_status <> 'withdrawn'
      and coalesce(e.ends_at, e.starts_at) >= now() - interval '30 days'
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_my_payment_reports(uuid) from public, anon;
grant execute on function public.list_my_payment_reports(uuid) to authenticated;

-- Treasurer / payment managers: reports for an event (pending first)
create or replace function public.list_event_payment_reports(p_organization_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
begin
  perform private.assert_event_payments(p_organization_id, p_event_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'report_id', pr.id, 'member_id', pr.member_id, 'display_name', m.display_name,
             'member_number', m.member_number, 'amount', pr.amount, 'payment_method', pr.payment_method,
             'reference', pr.reference, 'report_status', pr.report_status, 'reported_at', pr.reported_at,
             'reviewed_at', pr.reviewed_at, 'decline_reason', pr.decline_reason)
           order by (pr.report_status = 'pending') desc, pr.reported_at desc)
    from public.event_payment_reports pr
    join public.members m on m.id = pr.member_id
    where pr.organization_id = p_organization_id and pr.event_id = p_event_id and pr.report_status <> 'withdrawn'
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.list_event_payment_reports(uuid, uuid) from public, anon;
grant execute on function public.list_event_payment_reports(uuid, uuid) to authenticated;

-- Treasurer: confirm (records the payment through record_event_payment) or decline
create or replace function public.review_event_payment_report(
  p_organization_id uuid,
  p_report_id       uuid,
  p_confirm         boolean,
  p_decline_reason  text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_rep public.event_payment_reports%rowtype;
  v_res jsonb;
  v_profile uuid := private.current_profile_id();
begin
  select * into v_rep from public.event_payment_reports
   where id = p_report_id and organization_id = p_organization_id for update;
  if v_rep.id is null then
    raise exception using errcode = 'P0002', message = 'Payment report not found.';
  end if;
  perform private.assert_event_payments(p_organization_id, v_rep.event_id);
  if v_rep.report_status <> 'pending' then
    raise exception using errcode = '22023', message = 'This payment report was already handled.';
  end if;

  if coalesce(p_confirm, false) then
    v_res := public.record_event_payment(p_organization_id, v_rep.event_id, v_rep.member_id, v_rep.amount, v_rep.payment_method);
    update public.event_payment_reports
       set report_status = 'confirmed', reviewed_at = now(), reviewed_by_profile_id = v_profile,
           payment_id = (v_res->>'payment_id')::uuid
     where id = v_rep.id;
    return jsonb_build_object('report_status', 'confirmed', 'payment', v_res->'payment');
  else
    update public.event_payment_reports
       set report_status = 'declined', reviewed_at = now(), reviewed_by_profile_id = v_profile,
           decline_reason = nullif(btrim(coalesce(p_decline_reason, '')), '')
     where id = v_rep.id;
    perform private.write_audit_event(
      p_organization_id  => p_organization_id,
      p_event_code       => 'event.payment_report.declined',
      p_event_category   => 'governance',
      p_actor_profile_id => v_profile,
      p_entity_type      => 'event_payment_report',
      p_entity_id        => v_rep.id,
      p_action           => 'update',
      p_outcome          => 'success',
      p_access_reason    => null,
      p_correlation_id   => null,
      p_metadata         => jsonb_build_object('event_id', v_rep.event_id, 'amount', v_rep.amount, 'method', v_rep.payment_method));
    return jsonb_build_object('report_status', 'declined');
  end if;
end;
$$;
revoke all on function public.review_event_payment_report(uuid, uuid, boolean, text) from public, anon;
grant execute on function public.review_event_payment_report(uuid, uuid, boolean, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. set_my_reply: Attending registers / Not attending cancels an unpaid registration
-- -----------------------------------------------------------------------------

create or replace function public.set_my_reply(
  p_organization_id      uuid,
  p_event_id             uuid default null,
  p_household_meeting_id uuid default null,
  p_response             text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_member   uuid;
  v_response text := nullif(btrim(coalesce(p_response, '')), '');
  v_event    public.events%rowtype;
  v_meeting  public.household_meetings%rowtype;
  v_note     text := null;
begin
  v_member := private.assert_member_self_service(p_organization_id);
  if (p_event_id is null) = (p_household_meeting_id is null) then
    raise exception using errcode = '22023', message = 'Choose one event or one household meeting.';
  end if;
  if v_response is not null and v_response not in ('attending', 'not_attending') then
    raise exception using errcode = '22023', message = 'Reply must be Attending or Not attending.';
  end if;

  if p_event_id is not null then
    select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
    if v_event.id is null or not private.member_can_reply_event(p_organization_id, v_member, p_event_id) then
      raise exception using errcode = 'P0002', message = 'Event not found.';
    end if;
    if v_event.event_status <> 'scheduled' or v_event.starts_at <= now() then
      raise exception using errcode = '22023', message = 'Replies close when the event starts.';
    end if;
    if v_response is null then
      delete from public.member_replies where event_id = p_event_id and member_id = v_member;
    else
      insert into public.member_replies (organization_id, member_id, event_id, response)
      values (p_organization_id, v_member, p_event_id, v_response)
      on conflict (event_id, member_id) where event_id is not null
      do update set response = excluded.response, responded_at = now();
    end if;

    -- Pass 9.29 (Ron, 2026-10-21): when registration is open, Attending registers the member; Not attending cancels
    -- the registration if nothing has been paid or reported yet (otherwise the registration is kept).
    if v_response = 'attending' and v_event.registration_open
       and not exists (select 1 from public.event_registrations r
                       where r.event_id = p_event_id and r.member_id = v_member and r.cancelled_at is null) then
      perform public.register_for_event(p_organization_id, p_event_id, null, false);
      v_note := 'registered';
    elsif v_response = 'not_attending'
       and exists (select 1 from public.event_registrations r
                   where r.event_id = p_event_id and r.member_id = v_member and r.cancelled_at is null) then
      if exists (select 1 from public.event_payments p
                 where p.event_id = p_event_id and p.member_id = v_member and p.voided_at is null)
         or exists (select 1 from public.event_payment_reports pr
                    where pr.event_id = p_event_id and pr.member_id = v_member and pr.report_status = 'pending') then
        v_note := 'registration_kept_paid';
      else
        perform public.cancel_event_registration(p_organization_id, p_event_id, null);
        v_note := 'registration_cancelled';
      end if;
    end if;
  else
    select * into v_meeting from public.household_meetings
     where id = p_household_meeting_id and organization_id = p_organization_id;
    if v_meeting.id is null or not exists (
         select 1 from public.household_memberships hm
         where hm.organization_id = p_organization_id and hm.member_id = v_member
           and hm.household_node_id = v_meeting.household_node_id
           and hm.membership_status in ('active', 'temporary')
           and (hm.effective_to is null or hm.effective_to >= current_date)) then
      raise exception using errcode = 'P0002', message = 'Household meeting not found.';
    end if;
    if v_meeting.meeting_status <> 'scheduled'
       or coalesce(v_meeting.scheduled_start_at, (v_meeting.meeting_date + 1)::timestamp at time zone 'America/New_York') <= now() then
      raise exception using errcode = '22023', message = 'Replies close when the meeting starts.';
    end if;
    if v_response is null then
      delete from public.member_replies where household_meeting_id = p_household_meeting_id and member_id = v_member;
    else
      insert into public.member_replies (organization_id, member_id, household_meeting_id, response)
      values (p_organization_id, v_member, p_household_meeting_id, v_response)
      on conflict (household_meeting_id, member_id) where household_meeting_id is not null
      do update set response = excluded.response, responded_at = now();
    end if;
  end if;

  return jsonb_build_object('status', 'saved', 'response', v_response, 'registration', v_note);
end;
$$;

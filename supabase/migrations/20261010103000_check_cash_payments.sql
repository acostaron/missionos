-- =============================================================================
-- Migration: 20261010103000_check_cash_payments.sql
-- MissionOS Pass 9.30 (written by Claude, 2026-10-21) — run after 20261010102000.
-- Ron (2026-10-21): add check and cash as payment options.
--   * members can report a check or cash already given ("I sent payment"; check number as the reference), or say
--     they will pay by cash or check at the event; both wait for the treasurer, who confirms when it is received
--     (which records the payment) or declines;
--   * check instructions: "Payable to", mailing address and a cash/check note — organization default with an
--     optional per-event override, like Zelle / PayPal;
--   * Not attending withdraws a pending "pay at the event".
-- Guarded: replaces the Pass 9.29 functions only if unchanged from 20261010102000.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_payment_details';
  if v_md5 is distinct from '7bcf5c5bbf50abf9d0f0a332fd48843f' then
    raise exception 'STOP: public.get_payment_details differs from 20261010102000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'set_payment_details';
  if v_md5 is distinct from 'e83be42d2c1b197b75e73e1669a35419' then
    raise exception 'STOP: public.set_payment_details differs from 20261010102000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'report_my_event_payment';
  if v_md5 is distinct from 'd2cf2f5188e4bcd9b9f67a29c4d68d23' then
    raise exception 'STOP: public.report_my_event_payment differs from 20261010102000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'list_my_payment_reports';
  if v_md5 is distinct from 'c35de15605430c05e22c5f0ba886e71f' then
    raise exception 'STOP: public.list_my_payment_reports differs from 20261010102000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'list_event_payment_reports';
  if v_md5 is distinct from 'cf38589624360f7c8535ddec07139f75' then
    raise exception 'STOP: public.list_event_payment_reports differs from 20261010102000 (md5 %).', v_md5;
  end if;
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'set_my_reply';
  if v_md5 is distinct from '44d68f0a273401385022637189fde540' then
    raise exception 'STOP: public.set_my_reply differs from 20261010102000 (md5 %).', v_md5;
  end if;
end;
$guard$;

-- 1. Check / cash instructions
alter table public.organization_payment_details
  add column if not exists check_payable_to text null
    check (check_payable_to is null or length(btrim(check_payable_to)) between 1 and 120),
  add column if not exists check_mailing_address text null
    check (check_mailing_address is null or length(check_mailing_address) <= 300),
  add column if not exists cash_check_note text null
    check (cash_check_note is null or length(cash_check_note) <= 500);

alter table public.events
  add column if not exists check_payable_to text null,
  add column if not exists check_mailing_address text null,
  add column if not exists cash_check_note text null;
alter table public.events drop constraint if exists events_check_cash_details_check;
alter table public.events add constraint events_check_cash_details_check check (
  (check_payable_to is null or length(btrim(check_payable_to)) between 1 and 120)
  and (check_mailing_address is null or length(check_mailing_address) <= 300)
  and (cash_check_note is null or length(cash_check_note) <= 500));

-- 2. Reports: check / cash, and "pay at the event"
alter table public.event_payment_reports
  add column if not exists report_kind text not null default 'sent';
do $c$
declare v_name text;
begin
  for v_name in
    select c.conname from pg_constraint c
    where c.conrelid = 'public.event_payment_reports'::regclass and c.contype = 'c'
      and pg_get_constraintdef(c.oid) like '%payment_method%'
  loop
    execute format('alter table public.event_payment_reports drop constraint %I', v_name);
  end loop;
end;
$c$;
alter table public.event_payment_reports add constraint event_payment_reports_method_kind_check check (
  (report_kind = 'sent' and payment_method in ('zelle', 'paypal', 'check', 'cash'))
  or (report_kind = 'at_event' and payment_method in ('check', 'cash')));

-- 3. Functions
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
    'check_payable_to',      coalesce(v_ev.check_payable_to, v_org.check_payable_to),
    'check_mailing_address', coalesce(v_ev.check_mailing_address, v_org.check_mailing_address),
    'cash_check_note',       coalesce(v_ev.cash_check_note, v_org.cash_check_note),
    'organization', jsonb_build_object('zelle_recipient', v_org.zelle_recipient, 'zelle_name', v_org.zelle_name,
                                       'paypal_link', v_org.paypal_link, 'payment_note', v_org.payment_note,
                                       'check_payable_to', v_org.check_payable_to,
                                       'check_mailing_address', v_org.check_mailing_address,
                                       'cash_check_note', v_org.cash_check_note),
    'event', case when v_ev.id is null then null else
               jsonb_build_object('zelle_recipient', v_ev.zelle_recipient, 'zelle_name', v_ev.zelle_name,
                                  'paypal_link', v_ev.paypal_link, 'payment_note', v_ev.payment_note,
                                  'check_payable_to', v_ev.check_payable_to,
                                  'check_mailing_address', v_ev.check_mailing_address,
                                  'cash_check_note', v_ev.cash_check_note) end,
    'can_edit_organization', private.is_organization_administrator(private.current_profile_id(), p_organization_id)
                             or private.is_finance_coordinator(p_organization_id),
    'can_edit_event', case when v_ev.id is null then false
                           else private.can_manage_event_payments(p_organization_id, p_event_id) end);
end;
$$;

drop function if exists public.set_payment_details(uuid, uuid, text, text, text, text);
create or replace function public.set_payment_details(
  p_organization_id uuid,
  p_event_id        uuid default null,
  p_zelle_recipient text default null,
  p_zelle_name      text default null,
  p_paypal_link     text default null,
  p_payment_note    text default null,
  p_check_payable_to      text default null,
  p_check_mailing_address text default null,
  p_cash_check_note       text default null
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
  v_cp text := nullif(btrim(coalesce(p_check_payable_to, '')), '');
  v_cm text := nullif(btrim(coalesce(p_check_mailing_address, '')), '');
  v_cn text := nullif(btrim(coalesce(p_cash_check_note, '')), '');
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
                                                     check_payable_to, check_mailing_address, cash_check_note,
                                                     updated_at, updated_by_profile_id)
    values (p_organization_id, v_zr, v_zn, v_pl, v_pn, v_cp, v_cm, v_cn, now(), v_profile)
    on conflict (organization_id) do update
      set zelle_recipient = excluded.zelle_recipient, zelle_name = excluded.zelle_name,
          paypal_link = excluded.paypal_link, payment_note = excluded.payment_note,
          check_payable_to = excluded.check_payable_to, check_mailing_address = excluded.check_mailing_address,
          cash_check_note = excluded.cash_check_note,
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
           check_payable_to = v_cp, check_mailing_address = v_cm, cash_check_note = v_cn,
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
    p_metadata         => jsonb_build_object('has_zelle', v_zr is not null, 'has_paypal', v_pl is not null, 'has_check', v_cp is not null));
  return public.get_payment_details(p_organization_id, p_event_id);
end;
$$;
revoke all on function public.set_payment_details(uuid, uuid, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.set_payment_details(uuid, uuid, text, text, text, text, text, text, text) to authenticated;

drop function if exists public.report_my_event_payment(uuid, uuid, text, numeric, text);
create or replace function public.report_my_event_payment(
  p_organization_id uuid,
  p_event_id        uuid,
  p_payment_method  text,
  p_amount          numeric,
  p_reference       text default null,
  p_report_kind     text default 'sent'
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
  v_kind   text := lower(coalesce(nullif(btrim(p_report_kind), ''), 'sent'));
  v_method text := lower(coalesce(p_payment_method, ''));
begin
  v_member := private.assert_member_self_service(p_organization_id);
  select * into v_event from public.events where id = p_event_id and organization_id = p_organization_id;
  if v_event.id is null then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'This event was cancelled.';
  end if;
  if v_kind not in ('sent', 'at_event') then
    raise exception using errcode = '22023', message = 'Unknown payment report.';
  end if;
  if v_kind = 'sent' and v_method not in ('zelle', 'paypal', 'check', 'cash') then
    raise exception using errcode = '22023', message = 'Choose Zelle, PayPal, check or cash.';
  end if;
  if v_kind = 'at_event' and v_method not in ('check', 'cash') then
    raise exception using errcode = '22023', message = 'At the event you can pay by cash or check.';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000 then
    raise exception using errcode = '22023', message = 'Enter the amount.';
  end if;
  if v_kind = 'at_event' and exists (select 1 from public.event_payment_reports pr
       where pr.event_id = p_event_id and pr.member_id = v_member and pr.report_status = 'pending'
         and pr.report_kind = 'at_event') then
    raise exception using errcode = '22023', message = 'You already said you will pay at the event.';
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
                                            report_kind, reported_by_profile_id)
  values (p_organization_id, p_event_id, v_member, round(p_amount, 2), v_method,
          nullif(btrim(coalesce(p_reference, '')), ''), v_kind, private.current_profile_id())
  returning id into v_id;
  return jsonb_build_object('report_id', v_id, 'report_status', 'pending', 'report_kind', v_kind);
end;
$$;
revoke all on function public.report_my_event_payment(uuid, uuid, text, numeric, text, text) from public, anon;
grant execute on function public.report_my_event_payment(uuid, uuid, text, numeric, text, text) to authenticated;

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
             'decline_reason', pr.decline_reason, 'report_kind', pr.report_kind) order by pr.reported_at desc)
    from public.event_payment_reports pr
    join public.events e on e.id = pr.event_id
    where pr.organization_id = p_organization_id and pr.member_id = v_member
      and pr.report_status <> 'withdrawn'
      and coalesce(e.ends_at, e.starts_at) >= now() - interval '30 days'
  ), '[]'::jsonb);
end;
$$;

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
             'reviewed_at', pr.reviewed_at, 'decline_reason', pr.decline_reason, 'report_kind', pr.report_kind)
           order by (pr.report_status = 'pending') desc, pr.reported_at desc)
    from public.event_payment_reports pr
    join public.members m on m.id = pr.member_id
    where pr.organization_id = p_organization_id and pr.event_id = p_event_id and pr.report_status <> 'withdrawn'
  ), '[]'::jsonb);
end;
$$;

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
      -- Pass 9.30: a promise to pay at the event lapses when the member will not attend.
      update public.event_payment_reports
         set report_status = 'withdrawn', reviewed_at = now(), reviewed_by_profile_id = private.current_profile_id()
       where event_id = p_event_id and member_id = v_member and report_status = 'pending' and report_kind = 'at_event';
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

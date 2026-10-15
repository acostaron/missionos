-- =============================================================================
-- Migration: 20261010089000_paid_event_attendance_paypal.sql
-- MissionOS Pass 9.13A (written by Claude, 2026-10-16) — run after 20261010088000.
-- Ron (2026-10-16):
--   * Add PayPal as a payment method.
--   * Paid events: ticking attendance on the Take attendance list is only for the event organizers and
--     administrators. Everyone else (greeters, attendance recorders) checks members in with Scan QR, which
--     checks payment. Free events are unchanged.
-- Guarded: set_event_attendance (20261010058000), record_event_payment and get_event_payment_access
-- (20261010088000) are replaced only if they are still those versions.
-- =============================================================================
do $guard$
declare
  r record;
  v_md5 text;
begin
  for r in select * from (values
    ('set_event_attendance', '524bec053c9ef979ec7156753d2da7fb'),
    ('record_event_payment', '841dad3e500a7e71ae686d86d6c09e20'),
    ('get_event_payment_access', 'ca4a25ba04221a2d92983f240cd88b5f')
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

-- PayPal
alter table public.event_payments drop constraint if exists event_payments_payment_method_check;
alter table public.event_payments add constraint event_payments_payment_method_check
  check (payment_method in ('cash', 'check', 'zelle', 'paypal', 'card', 'other'));

-- Organizers (can manage the event) and administrators
create or replace function private.can_tick_paid_event_attendance(p_organization_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.has_organization_access(p_organization_id)
     and (private.is_organization_administrator(private.current_profile_id(), p_organization_id)
          or (private.has_permission('events.manage', p_organization_id)
              and private.can_manage_event(p_organization_id, p_event_id)))
$$;
revoke all on function private.can_tick_paid_event_attendance(uuid, uuid) from public, anon, authenticated;

create or replace function public.set_event_attendance(
  p_organization_id uuid,
  p_event_id uuid,
  p_member_ids uuid[],
  p_present boolean default true,
  p_check_in_method text default 'tick'
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_actor uuid;
  v_event public.events%rowtype;
  v_ids uuid[];
  v_bad int;
  v_changed int := 0;
  v_unchanged int := 0;
  v_mid uuid;
  v_row uuid;
begin
  v_actor := private.current_profile_id();
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;

  select * into v_event from public.events
  where id = p_event_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Event not found.';
  end if;

  if not private.can_record_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501', message = 'Access denied: you cannot record attendance for this event.';
  end if;
  if v_event.event_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'Attendance cannot be recorded for a cancelled event.';
  end if;
  -- Pass 9.13A (Ron): paid events — only organizers and administrators may tick attendance;
  -- everyone else checks members in at the QR desk, where payment is checked.
  if coalesce(v_event.fee_amount, 0) > 0 and not private.can_tick_paid_event_attendance(p_organization_id, p_event_id) then
    raise exception using errcode = '42501',
      message = 'This is a paid event. Check members in with Scan QR so payment is checked. Only the organizers and administrators can tick attendance.';
  end if;
  if (v_event.starts_at at time zone 'America/New_York')::date > (now() at time zone 'America/New_York')::date then
    raise exception using errcode = '22023', message = 'Attendance can be recorded on or after the day of the event.';
  end if;
  if p_check_in_method is null or p_check_in_method not in ('tick', 'qr') then
    raise exception using errcode = '22023', message = 'Check-in method must be tick or qr.';
  end if;

  select array_agg(distinct x) into v_ids from unnest(coalesce(p_member_ids, '{}'::uuid[])) as x where x is not null;
  if v_ids is null or array_length(v_ids, 1) = 0 then
    raise exception using errcode = '22023', message = 'Select at least one member.';
  end if;
  if array_length(v_ids, 1) > 500 then
    raise exception using errcode = '22023', message = 'At most 500 members can be updated at once.';
  end if;

  if coalesce(p_present, true) then
    select count(*) into v_bad
    from unnest(v_ids) as x
    where not exists (
      select 1 from public.members m
      where m.id = x and m.organization_id = p_organization_id
        and m.record_status = 'active' and m.archived_at is null
    );
    if v_bad > 0 then
      raise exception using errcode = '22023', message = format('%s selected member(s) are not active members of this organization.', v_bad);
    end if;
  end if;

  foreach v_mid in array v_ids loop
    select a.id into v_row
    from public.event_attendance a
    where a.event_id = p_event_id and a.member_id = v_mid and a.removed_at is null;

    if coalesce(p_present, true) then
      if v_row is null then
        insert into public.event_attendance (organization_id, event_id, member_id, check_in_method, recorded_by_profile_id)
        values (p_organization_id, p_event_id, v_mid, p_check_in_method, v_actor);
        v_changed := v_changed + 1;
      else
        v_unchanged := v_unchanged + 1;
      end if;
    else
      if v_row is not null then
        update public.event_attendance
        set removed_at = now(), removed_by_profile_id = v_actor
        where id = v_row;
        v_changed := v_changed + 1;
      else
        v_unchanged := v_unchanged + 1;
      end if;
    end if;
  end loop;

  if v_changed > 0 then
    perform private.write_audit_event(
      p_organization_id  => p_organization_id,
      p_event_code       => case when coalesce(p_present, true) then 'event.attendance.recorded' else 'event.attendance.removed' end,
      p_event_category   => 'governance',
      p_actor_profile_id => v_actor,
      p_entity_type      => 'event',
      p_entity_id        => p_event_id,
      p_action           => case when coalesce(p_present, true) then 'record_attendance' else 'void' end,
      p_outcome          => 'success',
      p_access_reason    => null,
      p_correlation_id   => null,
      p_metadata         => jsonb_build_object('changed_count', v_changed, 'unchanged_count', v_unchanged,
                                               'check_in_method', p_check_in_method,
                                               'as_greeter', not private.has_permission('events.attendance.record', p_organization_id))
    );
  end if;

  return jsonb_build_object('status', 'success', 'changed_count', v_changed, 'unchanged_count', v_unchanged,
                            'event', private.event_summary_json(v_event));
end;
$$;

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
                            'can_manage_payments', private.can_manage_event_payments(p_organization_id, p_event_id),
                            'can_tick_attendance', coalesce(v_fee, 0) = 0
                                                   or private.can_tick_paid_event_attendance(p_organization_id, p_event_id));
end;
$$;

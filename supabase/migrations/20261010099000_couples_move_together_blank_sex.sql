-- =============================================================================
-- Migration: 20261010099000_couples_move_together_blank_sex.sql
-- MissionOS Pass 9.26B (written by Claude, 2026-10-21) — run after 20261010098000.
-- Ron (2026-10-21): only a few members have Sex filled in. Husband-only still applies, but a blank Sex counts:
-- placing or moving a member brings the spouse along unless the member is recorded Female or the spouse is
-- recorded Male. Only private.move_wife_with_husband changes.
-- Guarded: replaces it only if unchanged from 20261010098000.
-- =============================================================================
do $guard$
declare v_md5 text;
begin
  select md5(replace(p.prosrc, chr(13), '')) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'move_wife_with_husband';
  if v_md5 is distinct from '2e7aeb84909a3aabb3b31660e379714c' then
    raise exception 'STOP: private.move_wife_with_husband differs from 20261010098000 (md5 %).', v_md5;
  end if;
end;
$guard$;

create or replace function private.move_wife_with_husband(
  p_organization_id uuid,
  p_member_id       uuid,
  p_household_id    uuid,
  p_effective_date  date
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_sex  text;
  v_wsex text;
  v_wife public.members%rowtype;
  v_cur  uuid;
  v_res  jsonb;
begin
  -- Pass 9.26B (Ron, 2026-10-21): most members have Sex blank. The spouse moves with the member unless the member
  -- is recorded as female or the spouse is recorded as male (i.e. a wife moved on her own moves alone).
  select lower(coalesce(sex, '')) into v_sex from public.members where id = p_member_id and organization_id = p_organization_id;
  if v_sex = 'female' then
    return null;
  end if;
  select * into v_wife from public.members
   where id = private.active_spouse_of(p_organization_id, p_member_id) and organization_id = p_organization_id;
  if v_wife.id is null or v_wife.record_status <> 'active' or coalesce(v_wife.is_deceased, false) then
    return null;
  end if;
  v_wsex := lower(coalesce(v_wife.sex, ''));
  if v_wsex = 'male' then
    return null;
  end if;

  select hm.household_node_id into v_cur
  from public.household_memberships hm
  where hm.organization_id = p_organization_id
    and hm.member_id = v_wife.id
    and hm.is_primary = true
    and hm.membership_status in ('active', 'temporary')
    and hm.effective_from <= p_effective_date
    and (hm.effective_to is null or hm.effective_to >= p_effective_date)
  order by (hm.effective_to is null) desc, hm.effective_from desc
  limit 1;

  if v_cur = p_household_id then
    return jsonb_build_object('member_id', v_wife.id, 'display_name', v_wife.display_name, 'status', 'already_in_household');
  elsif v_cur is null then
    v_res := private.assign_member_to_household_one(p_organization_id, v_wife.id, p_household_id, p_effective_date, true);
    if v_res->>'status' is distinct from 'assigned' then
      raise exception using errcode = '22023',
        message = format('%s could not be placed with their spouse: %s Nothing was changed.',
                         v_wife.display_name, coalesce(v_res->>'message', v_res->>'status'));
    end if;
  else
    v_res := private.transfer_household_member_one(p_organization_id, v_wife.id, p_household_id, p_effective_date,
                                                    'Moves with spouse', true);
    if v_res->>'status' is distinct from 'transferred' then
      raise exception using errcode = '22023',
        message = format('%s could not be moved with their spouse: %s Nothing was changed.',
                         v_wife.display_name, coalesce(v_res->>'message', v_res->>'status'));
    end if;
  end if;
  return jsonb_build_object('member_id', v_wife.id, 'display_name', v_wife.display_name, 'status', v_res->>'status');
end;
$$;
revoke all on function private.move_wife_with_husband(uuid, uuid, uuid, date) from public, anon, authenticated;

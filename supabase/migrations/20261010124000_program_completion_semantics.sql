-- Migration: 20261010124000_program_completion_semantics.sql
-- Goal: Remove fabricated 100%-attendance graduation inference.
--       MissionOS currently has no explicit authoritative completion/graduation
--       state for Program participants; return NULL instead of 0 or fabricated counts.

-- 1. Update private.program_run_json:
--    Set graduate_count to NULL (not 0, not inferred from attendance)
create or replace function private.program_run_json(p_run public.program_runs)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with sessions as (
    select e.id, e.session_number, e.starts_at, e.ends_at, e.location_text
    from public.events e
    where e.program_run_id = p_run.id and e.event_status <> 'cancelled'
  ),
  parts as (
    select p.id from public.program_participants p
    where p.program_run_id = p_run.id and p.participant_status = 'registered'
  ),
  manage_check as (
    select private.can_manage_program_run(p_run.organization_id, p_run.id) as can_manage
  )
  select jsonb_build_object(
    'id', p_run.id,
    'program_code', p_run.program_code,
    'title', p_run.title,
    'description', p_run.description,
    'chapter_code', (select n.code from public.governance_nodes n where n.id = p_run.chapter_node_id),
    'chapter_name', (select n.name from public.governance_nodes n where n.id = p_run.chapter_node_id),
    'sections', coalesce((select jsonb_agg(jsonb_build_object('code', n.code, 'name', n.name,
                                                             'sub_area_name', sa.name) order by n.code)
                          from public.governance_nodes n
                          left join public.governance_nodes sa on sa.id = private.node_sub_area(n.id)
                          where n.id = any(p_run.section_node_ids)), '[]'::jsonb),
    'audience_name', coalesce((select n.name from public.governance_nodes n where n.id = p_run.audience_node_id), 'All members'),
    'audience_node_id', p_run.audience_node_id,
    'session_count', p_run.session_count,
    'sessions_scheduled', (select count(*) from sessions),
    'run_status', p_run.run_status,
    'cancel_reason', p_run.cancel_reason,
    'include_in_quarterly_report', case when (select can_manage from manage_check) then p_run.include_in_quarterly_report else null end,
    'report_priority', case when (select can_manage from manage_check) then p_run.report_priority else null end,
    'report_highlight', case when (select can_manage from manage_check) then p_run.report_highlight else null end,
    'participant_count', (select count(*) from parts),
    'graduate_count', null::integer,
    'first_session_at', (select min(s.starts_at) from sessions s),
    'last_session_at', (select max(coalesce(s.ends_at, s.starts_at)) from sessions s),
    'venue_location', (select s.location_text from sessions s where s.location_text is not null and btrim(s.location_text) <> '' order by s.session_number limit 1),
    'can_manage', (select can_manage from manage_check)
  )
$$;
revoke all on function private.program_run_json(public.program_runs) from public, anon, authenticated;

-- 2. Update public.get_program_run:
--    Set participant 'graduated' to NULL (graduation is a separate pastoral decision, not inferred from attendance)
create or replace function public.get_program_run(
  p_organization_id uuid,
  p_run_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_run public.program_runs%rowtype;
  v_manage boolean;
  v_scheduled integer;
begin
  if private.current_profile_id() is null then
    raise exception using errcode = '28000', message = 'Authentication required: active profile context not found.';
  end if;
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'Access denied: caller does not have access to this organization.';
  end if;
  select * into v_run from public.program_runs where id = p_run_id and organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Program not found.';
  end if;
  v_manage := private.can_manage_program_run(p_organization_id, p_run_id);
  if not (v_manage or private.has_permission('events.view', p_organization_id)
          or private.is_any_section_coordinator(p_organization_id)) then
    raise exception using errcode = '42501', message = 'Access denied: missing required permission events.view.';
  end if;

  select count(*) into v_scheduled from public.events e
  where e.program_run_id = p_run_id and e.event_status <> 'cancelled';

  return jsonb_build_object(
    'run', private.program_run_json(v_run),
    'sessions', coalesce((
      select jsonb_agg(private.event_summary_json(e) order by e.session_number, e.starts_at)
      from public.events e
      where e.program_run_id = p_run_id and e.event_status <> 'cancelled'
    ), '[]'::jsonb),
    'participants', coalesce((
      select jsonb_agg(x.j order by x.sort_key)
      from (
        select lower(private.program_participant_sort_name(p)) as sort_key,
               jsonb_build_object(
                 'participant_id', p.id,
                 'name', private.program_participant_name(p),
                 'is_member', p.member_id is not null,
                 'member_id', p.member_id,
                 'member_number', (select m.member_number from public.members m where m.id = p.member_id),
                 'participant_status', p.participant_status,
                 'invited_by_name', (select m.display_name from public.members m where m.id = p.invited_by_member_id),
                 'invited_by_member_id', p.invited_by_member_id,
                 'phone', case when v_manage then p.phone end,
                 'email', case when v_manage then p.email end,
                 'notes', case when v_manage then p.notes end,
                 'first_name', case when v_manage then p.first_name end,
                 'last_name', case when v_manage then p.last_name end,
                 'attended_sessions', coalesce((
                   select jsonb_agg(e.session_number order by e.session_number)
                   from public.program_participant_attendance a
                   join public.events e on e.id = a.event_id and e.event_status <> 'cancelled'
                   where a.participant_id = p.id and a.removed_at is null
                 ), '[]'::jsonb),
                 'attended_count', (
                   select count(*)
                   from public.program_participant_attendance a
                   join public.events e on e.id = a.event_id and e.event_status <> 'cancelled'
                   where a.participant_id = p.id and a.removed_at is null
                 ),
                 'graduated', null::boolean
               ) as j
        from public.program_participants p
        where p.program_run_id = p_run_id
      ) x
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_program_run(uuid, uuid) from public, anon;
grant execute on function public.get_program_run(uuid, uuid) to authenticated;

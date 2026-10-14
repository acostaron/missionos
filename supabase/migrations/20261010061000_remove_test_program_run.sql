-- Pass 7.2C-fix: remove one program run created by mistake on production (written by Claude, 2026-10-14).
-- During the Pass 7.2C frontend check, Antigravity's browser agent submitted the New Program form against
-- production (it was told to look only). It created program run b9c2632d-6a76-4d3e-91ef-190d25e215ae
-- ('CLS Couples Oct 2026', cls, planned) with 0 sessions and 0 participants. Ron did not create it.
-- This removes exactly that row, only if it still has no sessions and no participants, and records why.
-- The original 'program.run.created' audit event is kept as history.
do $$
declare
  v_org uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_run uuid := 'b9c2632d-6a76-4d3e-91ef-190d25e215ae';
  v_deleted int;
begin
  if not exists (select 1 from public.program_runs where id = v_run and organization_id = v_org) then
    raise notice 'Program run % not found; nothing to remove.', v_run;
    return;
  end if;
  if exists (select 1 from public.events where program_run_id = v_run)
     or exists (select 1 from public.program_participants where program_run_id = v_run) then
    raise exception 'Guard failed: program run % has sessions or participants; not removing.', v_run;
  end if;

  delete from public.program_runs
  where id = v_run and organization_id = v_org
    and program_code = 'cls' and title = 'CLS Couples Oct 2026' and run_status = 'planned';
  get diagnostics v_deleted = row_count;
  if v_deleted <> 1 then
    raise exception 'Guard failed: expected to remove 1 row, removed %.', v_deleted;
  end if;

  perform private.write_audit_event(
    p_organization_id  => v_org,
    p_event_code       => 'program.run.removed',
    p_event_category   => 'system',
    p_actor_profile_id => null,
    p_entity_type      => 'program_run',
    p_entity_id        => v_run,
    p_action           => 'void',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('reason', 'Created by mistake by an automated browser check on production; no sessions or participants.',
                                             'migration', '20261010061000_remove_test_program_run')
  );
end;
$$;

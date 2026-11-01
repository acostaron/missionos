-- =============================================================================
-- Pass 9.52 correction: freeze the Review document through Approval.
--
-- Forward-only correction to 20261010129000 (immutable).
--
-- Model (no new columns):
--   draft    : draft_document = latest saved draft (refreshable from live data)
--   review   : draft_document = exact frozen reviewed document (immutable while in review)
--   approved : approved_document = frozen review document || {approval: {...}}
--              draft_document is retained unchanged as the reviewed document.
--   Invariant (enforced by trigger): approved_document - 'approval' = draft_document.
--
-- Status semantics:
--   ministry_reporting_periods.status  = CENSUS workflow (draft/review/approved).
--   ministry_quarterly_reports.status  = REPORT workflow (draft/review/approved).
--   They are deliberately separate concepts, but ordered: a report can only enter
--   review (and therefore approval) once the quarter's census is approved, so the
--   frozen document always contains the final approved census.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Integrity trigger (replaces the 129000 guard function body)
-- -----------------------------------------------------------------------------
create or replace function private.guard_approved_quarterly_report()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if TG_OP = 'INSERT' then
    if NEW.status <> 'draft' or NEW.approved_document is not null then
      raise exception using errcode = '22023', message = 'A quarterly report must be created as a draft.';
    end if;
    return NEW;
  end if;

  if OLD.status = 'approved' then
    raise exception using errcode = '22023',
      message = 'Approved quarterly report is frozen and cannot be modified or deleted.';
  end if;

  if TG_OP = 'DELETE' then
    return OLD;
  end if;

  -- The review document is frozen while in review.
  if OLD.status = 'review' and NEW.status = 'review'
     and NEW.draft_document is distinct from OLD.draft_document then
    raise exception using errcode = '22023',
      message = 'The review document is frozen. Return the report to draft to change it.';
  end if;

  if NEW.status = 'approved' then
    if OLD.status <> 'review' then
      raise exception using errcode = '22023', message = 'Only a quarterly report in review can be approved.';
    end if;
    if NEW.draft_document is distinct from OLD.draft_document
       or OLD.draft_document is null
       or NEW.approved_document is null
       or (NEW.approved_document - 'approval') <> OLD.draft_document then
      raise exception using errcode = '22023',
        message = 'The approved document must be an exact copy of the frozen review document.';
    end if;
  end if;

  return NEW;
end;
$$;
revoke all on function private.guard_approved_quarterly_report() from public, anon, authenticated;

drop trigger if exists trg_guard_insert_quarterly_report on public.ministry_quarterly_reports;
create trigger trg_guard_insert_quarterly_report
  before insert on public.ministry_quarterly_reports
  for each row execute function private.guard_approved_quarterly_report();

-- -----------------------------------------------------------------------------
-- 2. Submit for review: freeze the saved draft exactly as last previewed.
--    No rebuild; requires the census to be captured and approved so the frozen
--    document contains the final census.
-- -----------------------------------------------------------------------------
create or replace function public.submit_quarterly_report_for_review(p_reporting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period public.ministry_reporting_periods%rowtype;
  v_report public.ministry_quarterly_reports%rowtype;
  v_snap_id uuid;
begin
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.manage');
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id for update;
  if v_report.id is null or v_report.status <> 'draft' or v_report.draft_document is null then
    raise exception using errcode = '22023', message = 'Refresh the draft before submitting it for review.';
  end if;
  select id into v_snap_id from public.ministry_census_snapshots where reporting_period_id = v_period.id;
  if v_snap_id is null then
    raise exception using errcode = '22023', message = 'Cannot submit for review: no census snapshot exists for this quarter.';
  end if;
  if v_period.status <> 'approved' then
    raise exception using errcode = '22023', message = 'Cannot submit for review: the quarterly census must be approved first.';
  end if;
  if coalesce((v_report.draft_document->'census'->>'available')::boolean, false) is not true
     or v_report.draft_document->'census'->>'snapshot_id' is distinct from v_snap_id::text
     or coalesce((v_report.draft_document->'census'->>'census_approved')::boolean, false) is not true then
    raise exception using errcode = '22023',
      message = 'The saved draft does not contain the approved census. Refresh the draft before submitting it for review.';
  end if;

  update public.ministry_quarterly_reports
     set status = 'review', submitted_at = now(), submitted_by_profile_id = private.current_profile_id(), updated_at = now()
   where id = v_report.id;
  perform private.quarterly_report_audit(v_period, 'quarterly_report.submitted_for_review', 'update', v_report.id);
  return public.get_quarterly_report_preview(v_period.id);
end;
$$;
revoke all on function public.submit_quarterly_report_for_review(uuid) from public, anon;
grant execute on function public.submit_quarterly_report_for_review(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Approve: copy the frozen review document. Never rebuilds from live data.
-- -----------------------------------------------------------------------------
create or replace function public.approve_quarterly_report(p_reporting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'auth'
as $$
declare
  v_period  public.ministry_reporting_periods%rowtype;
  v_report  public.ministry_quarterly_reports%rowtype;
  v_snap_id uuid;
  v_doc     jsonb;
  v_actor   uuid := private.current_profile_id();
  v_now     timestamptz := now();
begin
  v_period := private.quarterly_report_period_for(p_reporting_period_id, 'reports.quarterly.approve');
  select * into v_report from public.ministry_quarterly_reports where reporting_period_id = v_period.id for update;
  if v_report.id is null or v_report.status <> 'review' then
    raise exception using errcode = '22023', message = 'Only a quarterly report in review can be approved.';
  end if;
  if v_report.draft_document is null then
    raise exception using errcode = '22023', message = 'Cannot approve: no frozen review document exists.';
  end if;
  select id into v_snap_id from public.ministry_census_snapshots where reporting_period_id = v_period.id;
  if v_snap_id is null then
    raise exception using errcode = '22023', message = 'Cannot approve: no census snapshot exists for this quarter.';
  end if;
  if v_period.status <> 'approved' then
    raise exception using errcode = '22023', message = 'Cannot approve: the quarterly census must be approved first.';
  end if;

  -- Validate the frozen document itself (no rebuild).
  if coalesce((v_report.draft_document->>'schema_version')::int, -1) <> v_report.schema_version then
    raise exception using errcode = '22023', message = 'Cannot approve: review document schema version mismatch.';
  end if;
  if coalesce((v_report.draft_document->'census'->>'available')::boolean, false) is not true
     or v_report.draft_document->'census'->>'snapshot_id' is distinct from v_snap_id::text then
    raise exception using errcode = '22023',
      message = 'Cannot approve: the review document does not contain this quarter''s census. Return it to draft and refresh.';
  end if;

  v_doc := v_report.draft_document || jsonb_build_object('approval', jsonb_build_object(
    'approved_at', v_now,
    'approved_by_profile_id', v_actor,
    'approved_by_name', (select pr.display_name from public.profiles pr where pr.id = v_actor)
  ));

  update public.ministry_quarterly_reports
     set status = 'approved', approved_document = v_doc, approved_at = v_now,
         approved_by_profile_id = v_actor, updated_at = v_now
   where id = v_report.id;

  perform private.quarterly_report_audit(v_period, 'quarterly_report.approved', 'approve', v_report.id);
  return public.get_quarterly_report_preview(v_period.id);
end;
$$;
revoke all on function public.approve_quarterly_report(uuid) from public, anon;
grant execute on function public.approve_quarterly_report(uuid) to authenticated;

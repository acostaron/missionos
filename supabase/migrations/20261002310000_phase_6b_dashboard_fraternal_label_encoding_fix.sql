-- =============================================================================
-- Migration: 20261002310000_phase_6b_dashboard_fraternal_label_encoding_fix.sql
-- Phase:     Phase 6B-10B correction
-- Purpose:   Migration 300000 was first applied with a mis-encoded em dash in the
--            Fraternal leader_display_label. Restores the canonical label
--            ('Rotating facilitation — no permanent formal servant leader').
--            Idempotent: no-op when the label is already correct.
-- =============================================================================

do $mig$
declare
  v_def text;
  v_good text := 'Rotating facilitation ' || chr(8212) || ' no permanent formal servant leader';
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_pastoral_operations_dashboard'
    and pg_get_function_identity_arguments(p.oid) = 'p_organization_id uuid, p_governance_node_id uuid';

  if v_def is null then
    raise exception 'get_pastoral_operations_dashboard not found';
  end if;

  v_new := regexp_replace(
    v_def,
    'Rotating facilitation [^'']*? no permanent formal servant leader',
    v_good
  );

  if v_new <> v_def then
    execute v_new;
  end if;
end;
$mig$;
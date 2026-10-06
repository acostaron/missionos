-- =============================================================================
-- Migration: 20261002280000_phase_6b_dashboard_care_details_key_fix.sql
-- Phase:     Phase 6B-10B correction
-- Purpose:   Migrations 250000/270000 renamed the canonical care_responsibilities
--            item key 'details' to 'care_details', breaking the established
--            dashboard contract (Phase 6B pastoral operations dashboard suite).
--            Restores 'details'. Narrow: rewrites only that key in the live function.
-- =============================================================================

do $$
declare
  v_def text;
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

  v_new := replace(v_def, '''care_details'',             ac.care_payload', '''details'',                  ac.care_payload');

  if v_new = v_def then
    raise exception 'care_details key not found in dashboard definition';
  end if;

  execute v_new;
end;
$$;

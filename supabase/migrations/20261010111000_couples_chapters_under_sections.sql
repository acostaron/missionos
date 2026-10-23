-- =============================================================================
-- Migration: 20261010111000_couples_chapters_under_sections.sql
-- MissionOS Pass 9.38B (written by Claude, 2026-10-22) — run after 20261010110000.
-- Ron (2026-10-22): the Couples chapters sit under the Couples section, like the Handmaids chapters sit under the
-- Handmaids section. Moves Albany, Brooklyn Queens, New York and Rockville Center Chapters (MFC New York) under the
-- MFC Couples section, and the FMC New York Chapter under the FMC Couples section. The old parent links are ended
-- (kept as history), new ones are added. Units, households, members and leader access stay where they are.
-- Pass 9.38A (dry run inside its verify) showed placement guidance, dashboards and member context are unchanged.
-- Stops if the tree is not as expected.
-- =============================================================================
do $$
declare
  v_org   uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_today date := current_date;
  v_now   timestamptz := clock_timestamp();
  r_rel   record;
  v_new_parent uuid;
  v_moved integer := 0;
begin
  for r_rel in
    select r.id, r.child_node_id, c.code as child_code, p.code as parent_code
    from public.governance_node_relationships r
    join public.governance_nodes c on c.id = r.child_node_id
    join public.governance_nodes p on p.id = r.parent_node_id
    where r.organization_id = v_org
      and c.code in ('alb', 'bq', 'nyc', 'rvc', 'fmc_nyc')
      and r.relationship_type = 'primary_parent'
      and r.is_primary = true
      and r.relationship_status = 'active'
      and (r.effective_to is null or r.effective_to >= v_today)
  loop
    if r_rel.parent_code <> (case when r_rel.child_code = 'fmc_nyc' then 'fmc_ny' else 'mfc_ny' end) then
      raise exception 'STOP: chapter % has parent %, expected %', r_rel.child_code, r_rel.parent_code,
        (case when r_rel.child_code = 'fmc_nyc' then 'fmc_ny' else 'mfc_ny' end);
    end if;

    select s.id into strict v_new_parent
    from public.governance_nodes s
    join public.governance_node_types st on st.id = s.governance_node_type_id
    where s.organization_id = v_org and st.code = 'section' and s.lifecycle_status = 'active'
      and s.code = case when r_rel.child_code = 'fmc_nyc' then 'fmc_ny_sec_couples' else 'sec_couples' end;

    update public.governance_node_relationships
       set relationship_status = 'ended',
           effective_to = v_today,
           ended_at = v_now,
           ending_reason = 'Pass 9.38B: chapter moved under its Couples section',
           updated_at = v_now
     where id = r_rel.id;

    insert into public.governance_node_relationships (
      organization_id, parent_node_id, child_node_id, relationship_type, relationship_status, is_primary,
      effective_from, created_at, updated_at)
    values (v_org, v_new_parent, r_rel.child_node_id, 'primary_parent', 'active', true, v_today, v_now, v_now);

    v_moved := v_moved + 1;
  end loop;

  if v_moved <> 5 then
    raise exception 'STOP: expected to move 5 chapters, found %', v_moved;
  end if;

  insert into audit.events (organization_id, event_code, event_category, entity_type, entity_id, action, outcome, metadata)
  values (v_org, 'governance.structure_updated', 'governance', 'governance_node', v_org,
          'move_couples_chapters_under_sections', 'success',
          jsonb_build_object('migration', '20261010111000_couples_chapters_under_sections', 'chapters_moved', v_moved));
end;
$$;

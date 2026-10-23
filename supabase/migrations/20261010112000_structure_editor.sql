-- =============================================================================
-- Migration: 20261010112000_structure_editor.sql
-- MissionOS Pass 9.38C (written by Claude, 2026-10-22) — run after 20261010111000.
-- Ron (2026-10-22): create chapters (e.g. a Singles chapter) and units himself in the app, and show which Section each
-- household belongs to.
--   * Structure (administrators, or governance.structure.manage):
--       get_structure_tree, create_structure_node (chapter under a section, unit under a chapter),
--       rename_structure_node, retire_structure_node (only when nothing active is under it),
--       add_standard_sections (the 7 standard sections for a sub-area, when any are missing).
--     Sections are the fixed MFC kinds (couples, handmaids, servants, singles, campus, youth, kids) that the rest of
--     the app understands, so new sections are only the standard ones.
--   * Household section: from the tree when the household is under a section (chapter / unit households); chosen
--     (households.section_node_id) when it is placed directly under an Area.
--       get_household_sections, get_section_options, get_node_section, set_household_section.
-- No existing function is replaced.
-- =============================================================================

alter table public.households
  add column if not exists section_node_id uuid null references public.governance_nodes(id) on delete set null;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.can_manage_structure(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.current_profile_id() is not null
     and (coalesce(private.is_organization_administrator(private.current_profile_id(), p_organization_id), false)
          or coalesce(private.has_permission('governance.structure.manage', p_organization_id), false))
$$;
revoke all on function private.can_manage_structure(uuid) from public, anon, authenticated;

-- nearest Section at or above a node (null if none)
create or replace function private.node_section_id(p_node_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  with recursive up(id, depth) as (
    select p_node_id, 0
    union all
    select r.parent_node_id, up.depth + 1
    from up
    join public.governance_node_relationships r
      on r.child_node_id = up.id
     and r.relationship_type = 'primary_parent'
     and r.is_primary = true
     and r.relationship_status = 'active'
     and r.effective_to is null
    where up.depth < 12
  )
  select up.id
  from up
  join public.governance_nodes n on n.id = up.id
  join public.governance_node_types t on t.id = n.governance_node_type_id
  where t.code = 'section'
  order by up.depth
  limit 1
$$;
revoke all on function private.node_section_id(uuid) from public, anon, authenticated;

create or replace function private.household_section_id(p_household_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce(private.node_section_id(p_household_id),
                  (select h.section_node_id from public.households h where h.id = p_household_id))
$$;
revoke all on function private.household_section_id(uuid) from public, anon, authenticated;

create or replace function private.section_json(p_section_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select jsonb_build_object('section_id', s.id, 'name', s.name, 'category', sc.section_category,
                            'sub_area_id', sa.id, 'sub_area_name', sa.name)
  from public.governance_nodes s
  left join public.sections sc on sc.id = s.id
  left join public.governance_nodes sa on sa.id = private.section_sub_area(s.id)
  where s.id = p_section_id
$$;
revoke all on function private.section_json(uuid) from public, anon, authenticated;

-- primary parent (active) of a node
create or replace function private.node_parent_id(p_node_id uuid)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select r.parent_node_id from public.governance_node_relationships r
  where r.child_node_id = p_node_id and r.relationship_type = 'primary_parent' and r.is_primary
    and r.relationship_status = 'active' and r.effective_to is null
  limit 1
$$;
revoke all on function private.node_parent_id(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Structure tree (areas, sub-areas, sections, chapters, units)
-- -----------------------------------------------------------------------------
create or replace function public.get_structure_tree(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if not private.can_manage_structure(p_organization_id) then
    raise exception using errcode = '42501', message = 'Only administrators can manage the structure.';
  end if;
  return jsonb_build_object(
    'nodes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', n.id, 'code', n.code, 'name', n.name, 'type', t.code,
               'parent_id', private.node_parent_id(n.id),
               'section_category', sc.section_category,
               'child_nodes', (select count(*) from public.governance_node_relationships r
                               join public.governance_nodes c on c.id = r.child_node_id and c.lifecycle_status = 'active'
                               join public.governance_node_types ct on ct.id = c.governance_node_type_id
                               where r.parent_node_id = n.id and r.relationship_type = 'primary_parent'
                                 and r.relationship_status = 'active' and r.effective_to is null and ct.code <> 'household'),
               'households', (select count(*) from public.governance_node_relationships r
                              join public.governance_nodes c on c.id = r.child_node_id and c.lifecycle_status = 'active'
                              join public.governance_node_types ct on ct.id = c.governance_node_type_id
                              where r.parent_node_id = n.id and r.relationship_type = 'primary_parent'
                                and r.relationship_status = 'active' and r.effective_to is null and ct.code = 'household'),
               'leaders', (select count(*) from public.leadership_assignments la
                           where la.governance_node_id = n.id and la.assignment_status = 'active' and la.ended_at is null))
             order by t.hierarchy_rank, n.name)
      from public.governance_nodes n
      join public.governance_node_types t on t.id = n.governance_node_type_id
      left join public.sections sc on sc.id = n.id
      where n.organization_id = p_organization_id and n.lifecycle_status = 'active'
        and t.code in ('area_state', 'section', 'chapter', 'unit')), '[]'::jsonb),
    'missing_sections', coalesce((
      select jsonb_object_agg(sa.id::text, (
               select jsonb_agg(k.kind order by k.ord)
               from (values ('couples', 1), ('handmaids', 2), ('servants', 3), ('singles', 4), ('campus', 5),
                            ('youth', 6), ('kids', 7)) k(kind, ord)
               where not exists (select 1 from public.governance_node_relationships r
                                 join public.governance_nodes s on s.id = r.child_node_id and s.lifecycle_status = 'active'
                                 join public.sections sc on sc.id = s.id
                                 where r.parent_node_id = sa.id and r.relationship_type = 'primary_parent'
                                   and r.relationship_status = 'active' and r.effective_to is null
                                   and sc.section_category = k.kind)))
      from public.governance_nodes sa
      join public.governance_node_types t on t.id = sa.governance_node_type_id and t.code = 'area_state'
      join public.governance_nodes pa on pa.id = private.node_parent_id(sa.id)
      join public.governance_node_types pt on pt.id = pa.governance_node_type_id and pt.code = 'area_state'
      where sa.organization_id = p_organization_id and sa.lifecycle_status = 'active'), '{}'::jsonb));
end;
$$;
revoke all on function public.get_structure_tree(uuid) from public, anon;
grant execute on function public.get_structure_tree(uuid) to authenticated;

create or replace function public.create_structure_node(
  p_organization_id uuid,
  p_parent_node_id  uuid,
  p_node_type       text,
  p_name            text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor   uuid := private.current_profile_id();
  v_name    text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_parent  record;
  v_type_id uuid;
  v_base    text;
  v_code    text;
  v_n       integer := 1;
  v_id      uuid;
begin
  if not private.can_manage_structure(p_organization_id) then
    raise exception using errcode = '42501', message = 'Only administrators can manage the structure.';
  end if;
  if p_node_type not in ('chapter', 'unit') then
    raise exception using errcode = '22023', message = 'You can add a chapter or a unit.';
  end if;
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception using errcode = '22023', message = 'Enter a name (2 to 120 characters).';
  end if;

  select n.id, n.code, t.code as type_code into v_parent
  from public.governance_nodes n
  join public.governance_node_types t on t.id = n.governance_node_type_id
  where n.id = p_parent_node_id and n.organization_id = p_organization_id and n.lifecycle_status = 'active';
  if not found then
    raise exception using errcode = 'P0002', message = 'The parent was not found.';
  end if;
  if p_node_type = 'chapter' and v_parent.type_code <> 'section' then
    raise exception using errcode = '22023', message = 'A chapter is added under a section.';
  end if;
  if p_node_type = 'unit' and v_parent.type_code <> 'chapter' then
    raise exception using errcode = '22023', message = 'A unit is added under a chapter.';
  end if;
  if exists (select 1 from public.governance_node_relationships r
             join public.governance_nodes c on c.id = r.child_node_id and c.lifecycle_status = 'active'
             where r.parent_node_id = p_parent_node_id and r.relationship_type = 'primary_parent'
               and r.relationship_status = 'active' and r.effective_to is null
               and lower(c.name) = lower(v_name)) then
    raise exception using errcode = '23505', message = 'There is already one with that name here.';
  end if;

  select id into strict v_type_id from public.governance_node_types
  where organization_id = p_organization_id and code = p_node_type;

  -- code: <parent code>_<name>, lower case, underscores; a number is added if it is taken
  v_base := left(coalesce(v_parent.code || '_', '') ||
                 trim(both '_' from regexp_replace(lower(v_name), '[^a-z0-9]+', '_', 'g')), 60);
  v_code := v_base;
  while exists (select 1 from public.governance_nodes g where g.organization_id = p_organization_id and g.code = v_code) loop
    v_n := v_n + 1;
    v_code := v_base || '_' || v_n;
  end loop;

  insert into public.governance_nodes (organization_id, governance_node_type_id, code, name, lifecycle_status,
                                       effective_from, created_at, updated_at, created_by, updated_by)
  values (p_organization_id, v_type_id, v_code, v_name, 'active', current_date, now(), now(), v_actor, v_actor)
  returning id into v_id;

  if p_node_type = 'chapter' then
    insert into public.chapters (id, organization_id, chapter_category, created_at, updated_at)
    values (v_id, p_organization_id, 'standard', now(), now());
  else
    insert into public.units (id, organization_id, unit_category, created_at, updated_at)
    values (v_id, p_organization_id, 'standard', now(), now());
  end if;

  insert into public.governance_node_relationships (organization_id, parent_node_id, child_node_id, relationship_type,
                                                    relationship_status, is_primary, effective_from, created_at,
                                                    updated_at, created_by, updated_by)
  values (p_organization_id, p_parent_node_id, v_id, 'primary_parent', 'active', true, current_date, now(), now(),
          v_actor, v_actor);

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'governance.structure.node_created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'governance_node',
    p_entity_id        => v_id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('node_type', p_node_type, 'code', v_code, 'parent_node_id', p_parent_node_id));

  return jsonb_build_object('status', 'created', 'node_id', v_id, 'code', v_code, 'name', v_name);
end;
$$;
revoke all on function public.create_structure_node(uuid, uuid, text, text) from public, anon;
grant execute on function public.create_structure_node(uuid, uuid, text, text) to authenticated;

create or replace function public.rename_structure_node(p_organization_id uuid, p_node_id uuid, p_name text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor uuid := private.current_profile_id();
  v_name  text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_node  record;
begin
  if not private.can_manage_structure(p_organization_id) then
    raise exception using errcode = '42501', message = 'Only administrators can manage the structure.';
  end if;
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception using errcode = '22023', message = 'Enter a name (2 to 120 characters).';
  end if;
  select n.id, n.name, t.code as type_code into v_node
  from public.governance_nodes n
  join public.governance_node_types t on t.id = n.governance_node_type_id
  where n.id = p_node_id and n.organization_id = p_organization_id and n.lifecycle_status = 'active';
  if not found or v_node.type_code not in ('section', 'chapter', 'unit') then
    raise exception using errcode = '22023', message = 'You can rename a section, chapter or unit.';
  end if;
  update public.governance_nodes set name = v_name, updated_at = now(), updated_by = v_actor where id = p_node_id;
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'governance.structure.node_renamed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'governance_node',
    p_entity_id        => p_node_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('previous_name', v_node.name, 'name', v_name));
  return jsonb_build_object('status', 'renamed', 'node_id', p_node_id, 'name', v_name);
end;
$$;
revoke all on function public.rename_structure_node(uuid, uuid, text) from public, anon;
grant execute on function public.rename_structure_node(uuid, uuid, text) to authenticated;

create or replace function public.retire_structure_node(p_organization_id uuid, p_node_id uuid, p_reason text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor  uuid := private.current_profile_id();
  v_node   record;
  v_reason text := coalesce(nullif(btrim(p_reason), ''), 'Retired in Structure');
begin
  if not private.can_manage_structure(p_organization_id) then
    raise exception using errcode = '42501', message = 'Only administrators can manage the structure.';
  end if;
  select n.id, n.name, t.code as type_code into v_node
  from public.governance_nodes n
  join public.governance_node_types t on t.id = n.governance_node_type_id
  where n.id = p_node_id and n.organization_id = p_organization_id and n.lifecycle_status = 'active';
  if not found or v_node.type_code not in ('section', 'chapter', 'unit') then
    raise exception using errcode = '22023', message = 'You can retire a section, chapter or unit.';
  end if;
  if exists (select 1 from public.governance_node_relationships r
             join public.governance_nodes c on c.id = r.child_node_id and c.lifecycle_status <> 'archived'
             where r.parent_node_id = p_node_id and r.relationship_type = 'primary_parent'
               and r.relationship_status = 'active') then
    raise exception using errcode = '22023',
      message = 'Move or retire what is under it first (chapters, units or households).';
  end if;
  if exists (select 1 from public.leadership_assignments la
             where la.governance_node_id = p_node_id and la.assignment_status = 'active' and la.ended_at is null) then
    raise exception using errcode = '22023', message = 'Conclude its servant leaders first.';
  end if;
  if exists (select 1 from public.households h where h.section_node_id = p_node_id
             and exists (select 1 from public.governance_nodes hn where hn.id = h.id and hn.lifecycle_status = 'active')) then
    raise exception using errcode = '22023', message = 'Some households are tagged with this section. Change them first.';
  end if;
  if v_node.type_code = 'section' and exists (select 1 from public.members m
                                              where m.primary_section_node_id = p_node_id and m.archived_at is null) then
    raise exception using errcode = '22023', message = 'Some members belong to this section. Move them to another section first.';
  end if;

  update public.governance_node_relationships
     set relationship_status = 'ended', effective_to = coalesce(effective_to, current_date), ended_at = now(),
         ended_by = v_actor, ending_reason = 'Retired: ' || v_reason, updated_by = v_actor
   where child_node_id = p_node_id and organization_id = p_organization_id
     and relationship_type = 'primary_parent' and relationship_status = 'active';
  update public.governance_nodes
     set lifecycle_status = 'archived', archived_at = now(), archived_by = v_actor, archive_reason = v_reason,
         effective_to = coalesce(effective_to, current_date), updated_by = v_actor, updated_at = now()
   where id = p_node_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'governance.structure.node_retired',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'governance_node',
    p_entity_id        => p_node_id,
    p_action           => 'archive',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('node_type', v_node.type_code, 'reason', v_reason));
  return jsonb_build_object('status', 'retired', 'node_id', p_node_id);
end;
$$;
revoke all on function public.retire_structure_node(uuid, uuid, text) from public, anon;
grant execute on function public.retire_structure_node(uuid, uuid, text) to authenticated;

create or replace function public.add_standard_sections(p_organization_id uuid, p_sub_area_node_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if not private.can_manage_structure(p_organization_id) then
    raise exception using errcode = '42501', message = 'Only administrators can manage the structure.';
  end if;
  return private.create_sub_area_sections_internal(p_organization_id, p_sub_area_node_id, private.current_profile_id());
end;
$$;
revoke all on function public.add_standard_sections(uuid, uuid) from public, anon;
grant execute on function public.add_standard_sections(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Household section
-- -----------------------------------------------------------------------------
create or replace function public.get_household_sections(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce(jsonb_object_agg(h.id::text,
           coalesce(private.section_json(private.household_section_id(h.id)), '{}'::jsonb)
           || jsonb_build_object('from_tree', private.node_section_id(h.id) is not null,
                                 'needs_section', private.household_section_id(h.id) is null
                                                  and h.pastoral_level in ('member', 'unit', 'chapter'))), '{}'::jsonb)
  from public.households h
  join public.governance_nodes n on n.id = h.id and n.lifecycle_status <> 'archived'
  where h.organization_id = p_organization_id
    and private.has_organization_access(p_organization_id)
$$;
revoke all on function public.get_household_sections(uuid) from public, anon;
grant execute on function public.get_household_sections(uuid) to authenticated;

create or replace function public.get_section_options(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select coalesce(jsonb_agg(private.section_json(s.id) order by sa.name, k.ord, s.name), '[]'::jsonb)
  from public.governance_nodes s
  join public.governance_node_types t on t.id = s.governance_node_type_id and t.code = 'section'
  left join public.sections sc on sc.id = s.id
  left join public.governance_nodes sa on sa.id = private.section_sub_area(s.id)
  left join (values ('couples', 1), ('handmaids', 2), ('servants', 3), ('singles', 4), ('campus', 5),
                    ('youth', 6), ('kids', 7)) k(kind, ord) on k.kind = sc.section_category
  where s.organization_id = p_organization_id and s.lifecycle_status = 'active'
    and private.has_organization_access(p_organization_id)
$$;
revoke all on function public.get_section_options(uuid) from public, anon;
grant execute on function public.get_section_options(uuid) to authenticated;

-- the Section a node is in (for the Create Household form); null when it is above the sections
create or replace function public.get_node_section(p_organization_id uuid, p_node_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select private.section_json(private.node_section_id(n.id))
  from public.governance_nodes n
  where n.id = p_node_id and n.organization_id = p_organization_id
    and private.has_organization_access(p_organization_id)
$$;
revoke all on function public.get_node_section(uuid, uuid) from public, anon;
grant execute on function public.get_node_section(uuid, uuid) to authenticated;

create or replace function public.set_household_section(p_organization_id uuid, p_household_id uuid, p_section_node_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  v_actor  uuid := private.current_profile_id();
  v_before uuid;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;
  if not (private.can_manage_structure(p_organization_id)
          or (private.has_permission('households.records.update', p_organization_id)
              and private.can_access_household('households.records.update', p_organization_id, p_household_id))) then
    raise exception using errcode = '42501', message = 'You cannot change this household.';
  end if;
  select h.section_node_id into v_before from public.households h
  where h.id = p_household_id and h.organization_id = p_organization_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Household not found.';
  end if;
  if private.node_section_id(p_household_id) is not null then
    raise exception using errcode = '22023', message = 'This household''s section comes from its chapter.';
  end if;
  if p_section_node_id is not null and not exists (
       select 1 from public.governance_nodes s
       join public.governance_node_types t on t.id = s.governance_node_type_id and t.code = 'section'
       where s.id = p_section_node_id and s.organization_id = p_organization_id and s.lifecycle_status = 'active') then
    raise exception using errcode = '22023', message = 'Choose a section.';
  end if;

  update public.households set section_node_id = p_section_node_id, updated_at = now(), updated_by = v_actor
  where id = p_household_id;

  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household.section_set',
    p_event_category   => 'governance',
    p_actor_profile_id => v_actor,
    p_entity_type      => 'household',
    p_entity_id        => p_household_id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object('previous_section_node_id', v_before, 'section_node_id', p_section_node_id));
  return jsonb_build_object('status', 'saved', 'section', private.section_json(p_section_node_id));
end;
$$;
revoke all on function public.set_household_section(uuid, uuid, uuid) from public, anon;
grant execute on function public.set_household_section(uuid, uuid, uuid) to authenticated;

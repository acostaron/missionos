# Pass 6.2: FMC Chapters and Units

## 1. Overview & Ministry Decisions

- **Context**:
  - Familias Misioneras de Cristo (FMC) operates with its own parallel chapter, unit, and household hierarchy under FMC New York (`fmc_ny`).
  - FMC Couples units and FMC Handmaids units mirror the 8 standard geographic units established across New York:
    - Nassau (`_nassau`)
    - Suffolk (`_suffolk`)
    - Brooklyn (`_brooklyn`)
    - Queens (`_queens`)
    - Bronx (`_bronx`)
    - Manhattan (`_manhattan`)
    - Staten Island (`_staten_island`)
    - Albany (`_albany`)
- **Nodes Created (Data-Only Migration 123)**:
  - **FMC New York Chapter**: `fmc_nyc` ("FMC New York Chapter", chapter) directly under `fmc_ny`, with 8 geographic units:
    - `fmc_nyc_nassau` ("FMC Nassau Unit", unit)
    - `fmc_nyc_suffolk` ("FMC Suffolk Unit", unit)
    - `fmc_nyc_brooklyn` ("FMC Brooklyn Unit", unit)
    - `fmc_nyc_queens` ("FMC Queens Unit", unit)
    - `fmc_nyc_bronx` ("FMC Bronx Unit", unit)
    - `fmc_nyc_manhattan` ("FMC Manhattan Unit", unit)
    - `fmc_nyc_staten_island` ("FMC Staten Island Unit", unit)
    - `fmc_nyc_albany` ("FMC Albany Unit", unit)
  - **FMC Handmaids New York Chapter**: `fmc_hm` ("FMC Handmaids New York Chapter", chapter) directly under `fmc_ny_sec_handmaids`, with 8 geographic units:
    - `fmc_hm_nassau` ("FMC Handmaids Nassau Unit", unit)
    - `fmc_hm_suffolk` ("FMC Handmaids Suffolk Unit", unit)
    - `fmc_hm_brooklyn` ("FMC Handmaids Brooklyn Unit", unit)
    - `fmc_hm_queens` ("FMC Handmaids Queens Unit", unit)
    - `fmc_hm_bronx` ("FMC Handmaids Bronx Unit", unit)
    - `fmc_hm_manhattan` ("FMC Handmaids Manhattan Unit", unit)
    - `fmc_hm_staten_island` ("FMC Handmaids Staten Island Unit", unit)
    - `fmc_hm_albany` ("FMC Handmaids Albany Unit", unit)
- **Members & Functions**:
  - No database functions were changed.
  - No member placements or section memberships were moved in this pass.

---

## 2. Migration Execution

- **Migration**: `supabase/migrations/20261010054000_fmc_chapters_and_units.sql`
- **MD5 Hash**: `D83DC64131D2994324F30C0FAF0E686C`
- Applied via `npx supabase db push`.
- Total schema migrations: `123`.

---

## 3. Verification Checks

### Q1: Tree Relationships (18 Rows)
```sql
select p.code as parent, c.code as child, c.name, t.code as node_type
from public.governance_node_relationships r
join public.governance_nodes p on p.id = r.parent_node_id
join public.governance_nodes c on c.id = r.child_node_id
join public.governance_node_types t on t.id = c.governance_node_type_id
where r.relationship_type = 'primary_parent' and r.relationship_status = 'active' and r.effective_to is null
  and (c.code in ('fmc_nyc','fmc_hm') or c.code like 'fmc\_nyc\_%' or c.code like 'fmc\_hm\_%')
order by p.code, c.code;
```
Output:
```json
[
  {"child":"fmc_hm_albany","name":"FMC Handmaids Albany Unit","node_type":"unit","parent":"fmc_hm"},
  {"child":"fmc_hm_bronx","name":"FMC Handmaids Bronx Unit","node_type":"unit","parent":"fmc_hm"},
  {"child":"fmc_hm_brooklyn","name":"FMC Handmaids Brooklyn Unit","node_type":"unit","parent":"fmc_hm"},
  {"child":"fmc_hm_manhattan","name":"FMC Handmaids Manhattan Unit","node_type":"unit","parent":"fmc_hm"},
  {"child":"fmc_hm_nassau","name":"FMC Handmaids Nassau Unit","node_type":"unit","parent":"fmc_hm"},
  {"child":"fmc_hm_queens","name":"FMC Handmaids Queens Unit","node_type":"unit","parent":"fmc_hm"},
  {"child":"fmc_hm_staten_island","name":"FMC Handmaids Staten Island Unit","node_type":"unit","parent":"fmc_hm"},
  {"child":"fmc_hm_suffolk","name":"FMC Handmaids Suffolk Unit","node_type":"unit","parent":"fmc_hm"},
  {"child":"fmc_nyc","name":"FMC New York Chapter","node_type":"chapter","parent":"fmc_ny"},
  {"child":"fmc_hm","name":"FMC Handmaids New York Chapter","node_type":"chapter","parent":"fmc_ny_sec_handmaids"},
  {"child":"fmc_nyc_albany","name":"FMC Albany Unit","node_type":"unit","parent":"fmc_nyc"},
  {"child":"fmc_nyc_bronx","name":"FMC Bronx Unit","node_type":"unit","parent":"fmc_nyc"},
  {"child":"fmc_nyc_brooklyn","name":"FMC Brooklyn Unit","node_type":"unit","parent":"fmc_nyc"},
  {"child":"fmc_nyc_manhattan","name":"FMC Manhattan Unit","node_type":"unit","parent":"fmc_nyc"},
  {"child":"fmc_nyc_nassau","name":"FMC Nassau Unit","node_type":"unit","parent":"fmc_nyc"},
  {"child":"fmc_nyc_queens","name":"FMC Queens Unit","node_type":"unit","parent":"fmc_nyc"},
  {"child":"fmc_nyc_staten_island","name":"FMC Staten Island Unit","node_type":"unit","parent":"fmc_nyc"},
  {"child":"fmc_nyc_suffolk","name":"FMC Suffolk Unit","node_type":"unit","parent":"fmc_nyc"}
]
```

### Q2: Detail Rows & Placements Invariant
```sql
select
  (select count(*) from public.chapters ch join public.governance_nodes gn on gn.id = ch.id where gn.code in ('fmc_nyc','fmc_hm')) as fmc_chapter_rows,
  (select count(*) from public.units u join public.governance_nodes gn on gn.id = u.id where gn.code like 'fmc\_nyc\_%' or gn.code like 'fmc\_hm\_%') as fmc_unit_rows,
  (select count(*) from public.member_governance_assignments where assignment_status = 'active') as active_placements,
  (select count(*) from public.section_memberships where membership_status = 'active') as active_section_memberships;
```
Output:
```json
[{"active_placements":276,"active_section_memberships":311,"fmc_chapter_rows":2,"fmc_unit_rows":16}]
```

### Q3: Parent Node Child Counts
```sql
select p.code as parent, count(*) as children
from public.governance_node_relationships r
join public.governance_nodes p on p.id = r.parent_node_id
where r.relationship_type = 'primary_parent' and r.relationship_status = 'active' and r.effective_to is null
  and p.code in ('ny','mfc_ny','fmc_ny','rvc','bq','nyc','alb','hm_ny')
group by p.code order by p.code;
```
Output:
```json
[
  {"children":1,"parent":"alb"},
  {"children":2,"parent":"bq"},
  {"children":8,"parent":"fmc_ny"},
  {"children":8,"parent":"hm_ny"},
  {"children":11,"parent":"mfc_ny"},
  {"children":2,"parent":"ny"},
  {"children":3,"parent":"nyc"},
  {"children":2,"parent":"rvc"}
]
```

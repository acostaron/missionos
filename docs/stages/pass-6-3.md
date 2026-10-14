# Pass 6.3: Finance Numbers for FMC Coordinator Couple, Spouse Links, FMC Card Removed

## 1. Overview & Ministry Facts

- **Ministry Facts**:
  - Member numbers (NY…) represent Finance Group envelope numbers. MissionOS records them and does not invent them.
  - The two members placed at FMC New York (`fmc_ny`) in FMC Couples (`fmc_ny_sec_couples`) were added in the application without member numbers. Their Finance envelope numbers are NY10448 and NY10453. They are husband and wife, placed at FMC New York, and serve as the FMC Coordinator.
  - NY10550 and NY10551 are husband and wife.
- **Migration**: `supabase/migrations/20261010056000_fmc_coordinator_and_spouses.sql` (Migration 125).
  - **Step 0**: Attaches NY10448 and NY10453 to the two unnumbered member records at FMC New York (guarded: numbers unused, exactly one active unnumbered member at `fmc_ny` matching each name pattern). Sync trigger fills `members.member_number`.
  - **Step A**: Records two administrator-verified spouse links and pairs them in Couples where both spouses are active in the same Couples section.
  - **Step B**: Appoints the FMC Coordinator at `fmc_ny` (`leadership_role_definitions.code = 'fmc_coordinator'`) with the couple partner recorded in assignment metadata.
- **Push Failure & Resolution**:
  - Initial `supabase db push` with MD5 `C5E7C69B5DC87C39552EE97D44152697` failed with `ERROR: P0002: query returned no rows` at `SELECT id INTO STRICT v_spouse_type_id FROM public.family_relationship_types WHERE organization_id = v_org_id AND code = 'spouse'`.
  - Cause: In `public.family_relationship_types`, standard system relationship types (`child_of`, `parent_of`, `spouse`) have `organization_id IS NULL`. Filtering on `organization_id = v_org_id` returned 0 rows.
  - Fix: Updated query to `WHERE code = 'spouse' AND (organization_id = v_org_id OR organization_id IS NULL) ORDER BY (organization_id IS NULL) LIMIT 1`. New MD5: `FA253EA1FB0A1FED5F54A7BB94F08644`.

---

## 2. Pre-Checks

### A0-1: Number Usage & Unnumbered Name Matches
```sql
select (select count(*) from public.member_identifiers where identifier_type = 'member_number'
          and normalized_value in ('NY10448','NY10453')) as numbers_already_used,
       (select count(*) from public.members m
         where m.organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf' and m.record_status = 'active'
           and (lower(m.display_name) like '%napoleon%rodriguez%' or lower(m.display_name) like '%miriam%rodriguez%')
           and not exists (select 1 from public.member_identifiers mi where mi.member_id = m.id and mi.identifier_type = 'member_number')) as unnumbered_name_matches;
```
Output:
```json
[{"numbers_already_used": 0, "unnumbered_name_matches": 2}]
```

### A0-2: Active FMC Coordinators
```sql
select count(*) as active_fmc_coordinators from public.leadership_assignments la
join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
where lrd.code = 'fmc_coordinator' and la.assignment_status = 'active';
```
Output:
```json
[{"active_fmc_coordinators": 0}]
```

### A0-3: Existing Spouses Check
```sql
select mi.normalized_value as member_number, m.record_status, m.is_deceased,
       (select count(*) from public.family_relationships fr join public.family_relationship_types t on t.id = fr.relationship_type_id
         where t.code = 'spouse' and (fr.from_member_id = m.id or fr.to_member_id = m.id)) as spouse_rows
from public.member_identifiers mi join public.members m on m.id = mi.member_id
where mi.identifier_type = 'member_number' and mi.is_primary and mi.effective_to is null
  and mi.normalized_value in ('NY10550','NY10551') order by 1;
```
Output:
```json
[
  {"is_deceased": false, "member_number": "NY10550", "record_status": "active", "spouse_rows": 0},
  {"is_deceased": false, "member_number": "NY10551", "record_status": "active", "spouse_rows": 0}
]
```

### E: Identifier Management Permission
```sql
select r.code as role, p.code as permission, rp.permission_effect, rp.approval_status
from public.role_permissions rp
join public.app_roles r on r.id = rp.app_role_id
join public.permissions p on p.id = rp.permission_id
where r.code = 'organization_administrator' and p.code = 'members.identifiers.manage';
```
Output:
```json
[
  {
    "approval_status": "approved",
    "permission": "members.identifiers.manage",
    "permission_effect": "allow",
    "role": "organization_administrator"
  }
]
```

---

## 3. Migration Application

- **File**: `supabase/migrations/20261010056000_fmc_coordinator_and_spouses.sql`
- **MD5 Hash**: `FA253EA1FB0A1FED5F54A7BB94F08644`
- Applied via `npx supabase db push`.
- Total migrations: `125`.

Output:
```
Initialising login role...
Connecting to remote database...
Applying migration 20261010056000_fmc_coordinator_and_spouses.sql...
{"upToDate":false,"dryRun":false,"migrations":["20261010056000_fmc_coordinator_and_spouses.sql"],"seeds":[],"roles":[],"message":"Finished supabase db push."}
```

---

## 4. After-Checks

### A3-1: Identifier, Section, Placement, Spouse, and Pairing Verification
```sql
select mi.normalized_value as member_number, m.member_number as cached_member_number, m.record_status,
       (select gn.code from public.section_memberships sm join public.governance_nodes gn on gn.id = sm.section_node_id
         where sm.member_id = m.id and sm.membership_status = 'active' and sm.is_primary limit 1) as section_code,
       (select gn.code from public.member_governance_assignments a join public.governance_nodes gn on gn.id = a.governance_node_id
         where a.member_id = m.id and a.assignment_status = 'active' and a.is_primary and a.effective_to is null limit 1) as placement_code,
       (select count(*) from public.family_relationships fr join public.family_relationship_types t on t.id = fr.relationship_type_id
         where t.code = 'spouse' and (fr.from_member_id = m.id or fr.to_member_id = m.id)) as spouse_rows,
       (select sm.paired_member_id is not null from public.section_memberships sm
         where sm.member_id = m.id and sm.membership_status = 'active' and sm.is_primary limit 1) as paired_in_section
from public.member_identifiers mi join public.members m on m.id = mi.member_id
where mi.identifier_type = 'member_number' and mi.is_primary and mi.effective_to is null
  and mi.normalized_value in ('NY10448','NY10453','NY10550','NY10551') order by 1;
```
Output:
```json
[
  {
    "cached_member_number": "NY10448",
    "member_number": "NY10448",
    "paired_in_section": true,
    "placement_code": "fmc_ny",
    "record_status": "active",
    "section_code": "fmc_ny_sec_couples",
    "spouse_rows": 1
  },
  {
    "cached_member_number": "NY10453",
    "member_number": "NY10453",
    "paired_in_section": true,
    "placement_code": "fmc_ny",
    "record_status": "active",
    "section_code": "fmc_ny_sec_couples",
    "spouse_rows": 1
  },
  {
    "cached_member_number": "NY10550",
    "member_number": "NY10550",
    "paired_in_section": true,
    "placement_code": "fmc_nyc_bronx",
    "record_status": "active",
    "section_code": "fmc_ny_sec_couples",
    "spouse_rows": 1
  },
  {
    "cached_member_number": "NY10551",
    "member_number": "NY10551",
    "paired_in_section": true,
    "placement_code": "fmc_nyc_bronx",
    "record_status": "active",
    "section_code": "fmc_ny_sec_couples",
    "spouse_rows": 1
  }
]
```

### A3-2: FMC Coordinator in `get_sections_overview`
```sql
BEGIN;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"821fb09c-8396-4549-b120-5674f3cc566a"}';
select
  res->'fmc'->'coordinator'->>'member_number' as coordinator_member_number,
  (res->'fmc'->'coordinator'->'partner') is not null and (res->'fmc'->'coordinator'->>'partner') <> 'null' as partner_present
from (
  select public.get_sections_overview('22efefb6-2858-4629-ace6-66ea4e20cfdf') as res
) t;
ROLLBACK;
```
Output:
```json
[
  {
    "coordinator_member_number": "NY10448",
    "partner_present": true
  }
]
```

---

## 5. Frontend Modifications

- **File**: `src/pages/SectionsPage.tsx`
  - Removed "SPECIAL MINISTRY GROUP" section and bottom FMC card.
  - Added inline FMC Coordinator display directly beneath the "FMC New York" sub-area heading using `CoordinatorDisplay` fed from `data.fmc.coordinator`, `data.fmc.is_exception`, and `data.fmc.exception_reason`, falling back to `"FMC Coordinator: Vacant"` when null.

---

## 6. Verification (B3)

### Lint Output Tail
```
> missionos@0.0.0 lint
> oxlint

Found 0 warnings and 0 errors.
Finished in 18ms on 246 files with 104 rules using 16 threads.
```

### Build Output Tail
```
✓ built in 515ms

PWA v2.0.0
mode      generateSW
precache  57 entries (1555.85 KiB)
files generated
  dist/sw.js
  dist/workbox-98f7a950.js
```

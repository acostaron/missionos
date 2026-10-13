# Pass 6.1B: Sub-Area-Aware Sections, Consistency Rule, Move to Sub-Area

## 1. Overview

- **Migration**: `supabase/migrations/20261010055000_sub_area_aware_sections.sql` (Migration 124).
- **Database Functions & RPCs**:
  - `private.node_sub_area(uuid)`: Resolves the root sub-area (`mfc_ny`, `fmc_ny`, etc.) for any governance node by traversing `primary_parent` relationships upwards until reaching a node whose parent is the root area (`ny`).
  - `public.change_member_section`: Added sub-area consistency check — prevents moving a placed member to a section belonging to a different sub-area without simultaneously moving their placement. Replaces section code checks with section kind checks.
  - `public.place_members_bulk`: Added sub-area consistency check — verifies that each member's section belongs to the same sub-area as the target placement node.
  - `public.get_sections_overview`: Enriched return json to include `sub_areas` array (`code`, `name`, `node_id`, `sections` with `code`, `name`, `node_id`, `kind`, `active_members`).
  - `public.get_member_section`: Enriched to return `sub_area_code`, `sub_area_name`, and `section_kind`.
  - `public.get_sub_area_placement_targets(uuid, uuid)`: New RPC returning selectable placement targets (area, chapters, units formatted with parent names) under a given sub-area.
  - `public.move_member_to_sub_area`: New transactional RPC atomically changing a member's section and governance placement into a new sub-area, handling couples auto-pairing for verified spouses.
- **Frontend Changes**:
  - `src/features/sections/types.ts`: Added types for sub-areas, section kinds, placement targets, and move-to-sub-area RPC. Removed legacy flat `SECTION_OPTIONS`.
  - `src/features/sections/section-options.ts`: Added `parseSectionOptions` utility providing grouped sections by sub-area, code-to-metadata lookup, and `getDisplayLabel`.
  - `src/features/sections/api.ts`: Added API functions for `getSubAreaPlacementTargets` and `moveMemberToSubArea`.
  - `src/features/sections/queries.ts`: Added TanStack Query hooks `useSubAreaPlacementTargets` and `useMoveMemberToSubArea`.
  - `src/pages/SectionsPage.tsx`: Grouped section cards by sub-area with MFC New York displayed first.
  - `src/features/sections/components/MoveToSubAreaModal.tsx`: New modal for moving a member across sub-areas with target sub-area, section (preselecting matching kind), and placement selection.
  - `src/features/sections/components/ChangeMemberSectionModal.tsx`: Constrained section selection to current sub-area, with shortcut link to open Move to Sub-Area modal.
  - `src/pages/MemberProfilePage.tsx`: Integrated `MoveToSubAreaModal` and updated member section action controls.
  - `src/features/placement/components/ChangeSectionsModal.tsx`: Updated dropdown to `<optgroup>` per sub-area and replaced hardcoded code check with kind check.
  - `src/pages/PlaceMembersPage.tsx`: Filter dropdown grouped by sub-area; table and card views render qualified section labels.

---

## 2. Migration Execution

- **File**: `supabase/migrations/20261010055000_sub_area_aware_sections.sql`
- **MD5 Hash**: `8CA582F916D4CEC90ACE0AEF09517F7F`
- **Application**: Applied via `npx supabase db push`.
- **Schema Migrations Count**: `124`.

---

## 3. Database Verification Results

### T1: Sub-Areas Structure in `get_sections_overview`
```sql
select public.get_sections_overview('00000000-0000-0000-0000-000000000001');
```
Output:
```json
{
  "sections": [
    {"code": "sec_couples", "name": "Couples", "active_members": 204, "category_code": "couples"},
    {"code": "sec_handmaids", "name": "Handmaids of the Lord", "active_members": 43, "category_code": "handmaids"},
    {"code": "sec_servants", "name": "Servants of the Lord", "active_members": 0, "category_code": "servants"},
    {"code": "sec_singles", "name": "Singles", "active_members": 42, "category_code": "singles"},
    {"code": "sec_campus", "name": "Campus", "active_members": 0, "category_code": "campus"},
    {"code": "sec_youth", "name": "Youth", "active_members": 22, "category_code": "youth"},
    {"code": "sec_kids", "name": "Kids", "active_members": 0, "category_code": "kids"}
  ],
  "sub_areas": [
    {
      "code": "mfc_ny",
      "name": "MFC New York",
      "node_id": "060dff5d-222d-45df-bbad-95a201b1e355",
      "sections": [
        {"code": "sec_couples", "kind": "couples", "name": "Couples", "node_id": "8485295c-2081-4da2-9b04-f5a0be5fbbf0", "active_members": 204},
        {"code": "sec_handmaids", "kind": "handmaids", "name": "Handmaids of the Lord", "node_id": "18f921ea-dbce-4b2a-8742-ef47953046f4", "active_members": 43},
        {"code": "sec_servants", "kind": "servants", "name": "Servants of the Lord", "node_id": "a143f658-00ca-4a7b-a3da-16be9522194d", "active_members": 0},
        {"code": "sec_singles", "kind": "singles", "name": "Singles", "node_id": "e4f8e658-3069-42b7-a859-dae8271e8a38", "active_members": 42},
        {"code": "sec_campus", "kind": "campus", "name": "Campus", "node_id": "b1be888b-c7eb-485a-8b17-062e73c9ce05", "active_members": 0},
        {"code": "sec_youth", "kind": "youth", "name": "Youth", "node_id": "c1f71df9-59eb-4a1d-91b4-7ffc5aa2a7c4", "active_members": 22},
        {"code": "sec_kids", "kind": "kids", "name": "Kids", "node_id": "fa808fb4-b81b-4fc8-9d22-1d7c346123a6", "active_members": 0}
      ]
    },
    {
      "code": "fmc_ny",
      "name": "FMC New York",
      "node_id": "9bc311d9-7688-4db8-b57d-4184a5695034",
      "sections": [
        {"code": "fmc_ny_sec_couples", "kind": "couples", "name": "FMC Couples", "node_id": "8c59f0f9-a292-45e7-94d3-132d733519d1", "active_members": 0},
        {"code": "fmc_ny_sec_handmaids", "kind": "handmaids", "name": "FMC Handmaids of the Lord", "node_id": "a496f8a4-0ef6-43b9-b366-be51e7041dc8", "active_members": 0},
        {"code": "fmc_ny_sec_servants", "kind": "servants", "name": "FMC Servants of the Lord", "node_id": "31ec6211-13c5-4303-9d18-ae764951167d", "active_members": 0},
        {"code": "fmc_ny_sec_singles", "kind": "singles", "name": "FMC Singles", "node_id": "76ec965a-09aa-448f-8898-d89e50338dd6", "active_members": 0},
        {"code": "fmc_ny_sec_campus", "kind": "campus", "name": "FMC Campus", "node_id": "79ea7f31-50e5-408d-8c11-9e8a8b13d6a2", "active_members": 0},
        {"code": "fmc_ny_sec_youth", "kind": "youth", "name": "FMC Youth", "node_id": "67fc7e52-a50e-450f-a931-ff6fcfcb89a3", "active_members": 0},
        {"code": "fmc_ny_sec_kids", "kind": "kids", "name": "FMC Kids", "node_id": "27bb948e-28a1-4ee6-8576-9c4c1e40ebad", "active_members": 0}
      ]
    }
  ]
}
```

### T2: `get_member_section` Sub-Area Fields
Member NY10184:
```json
[
  {
    "section_code": "sec_couples",
    "section_kind": "couples",
    "section_name": "Couples",
    "sub_area_code": "mfc_ny",
    "sub_area_name": "MFC New York"
  }
]
```

### T3: Section Consistency Rejection
Attempting to change NY10184 (placed under MFC) to FMC section `fmc_ny_sec_couples`:
```json
{
  "message": "Member's placement is under sub-area 'mfc_ny' but section 'fmc_ny_sec_couples' belongs to sub-area 'fmc_ny'. Use move_member_to_sub_area to move a member across sub-areas.",
  "sqlstate": "22023"
}
```

### T4: Placement Consistency Rejection
Attempting to place member NY10184 (in MFC section `sec_couples`) into FMC unit `fmc_nyc_nassau`:
```json
{
  "message": "Section 'sec_couples' belongs to sub-area 'mfc_ny' but placement 'fmc_nyc_nassau' is under sub-area 'fmc_ny'. Cross-sub-area placement is not permitted.",
  "sqlstate": "22023"
}
```

### T5: `move_member_to_sub_area` Runs (Both Documented)

#### Run 1: NY10550 / NY10551
Both members moved successfully to `fmc_ny_sec_couples` and `fmc_nyc_nassau`.
- NY10550 result:
  ```json
  {
    "effective_from": "2026-10-13",
    "member_id": "e68f3a8b-49ca-4a00-b630-f975dd3e9564",
    "paired_member_id": null,
    "section_code": "fmc_ny_sec_couples",
    "sub_area_code": "fmc_ny",
    "target_node_id": "8c0bb47b-8395-4eb8-b99b-4395e54d6880"
  }
  ```
- NY10551 result:
  ```json
  {
    "effective_from": "2026-10-13",
    "member_id": "5c5bf956-f5db-449e-b2d4-1a3b984570dc",
    "paired_member_id": null,
    "section_code": "fmc_ny_sec_couples",
    "sub_area_code": "fmc_ny",
    "target_node_id": "8c0bb47b-8395-4eb8-b99b-4395e54d6880"
  }
  ```
- **Finding**: `paired_member_id` returned `null` because no active verified spouse row exists in `public.family_relationships` for NY10550/NY10551. No `family_relationships` records were created or modified.

#### Run 2: NY10069 / NY10068 (Verified Spouses)
- First move (NY10069):
  ```json
  {
    "effective_from": "2026-10-13",
    "member_id": "22ffc3e6-fa11-4f18-a6fe-4f135bfa3da9",
    "paired_member_id": null,
    "section_code": "fmc_ny_sec_couples",
    "sub_area_code": "fmc_ny",
    "target_node_id": "8c0bb47b-8395-4eb8-b99b-4395e54d6880"
  }
  ```
- Second move (NY10068):
  ```json
  {
    "effective_from": "2026-10-13",
    "member_id": "c65ff3fc-1300-4e3f-a388-75127d5320ee",
    "paired_member_id": "22ffc3e6-fa11-4f18-a6fe-4f135bfa3da9",
    "section_code": "fmc_ny_sec_couples",
    "sub_area_code": "fmc_ny",
    "target_node_id": "8c0bb47b-8395-4eb8-b99b-4395e54d6880"
  }
  ```
- **Finding**: Second move detected the active verified spouse row and returned `paired_member_id = 22ffc3e6-fa11-4f18-a6fe-4f135bfa3da9` (pairing functions as designed).

### T6: `get_sub_area_placement_targets` Counts & Guard
```sql
select
  jsonb_array_length(public.get_sub_area_placement_targets(
    '00000000-0000-0000-0000-000000000001',
    (select id from public.governance_nodes where code = 'fmc_ny')
  )) as fmc_targets,
  jsonb_array_length(public.get_sub_area_placement_targets(
    '00000000-0000-0000-0000-000000000001',
    (select id from public.governance_nodes where code = 'mfc_ny')
  )) as mfc_targets;
```
Output:
```json
[{"fmc_targets": 19, "mfc_targets": 22}]
```
Calling with root area `ny` (node that is not a sub-area):
```json
{
  "message": "Node 'ny' is not a sub-area.",
  "sqlstate": "22023"
}
```

### T7: Invariant Checks After Rollbacks
```sql
select
  (select count(*) from public.member_governance_assignments where assignment_status = 'active') as active_placements,
  (select count(*) from public.section_memberships where membership_status = 'active') as active_section_memberships,
  (select count(*) from public.household_memberships where membership_status = 'active') as active_household_memberships;
```
Output:
```json
[{"active_household_memberships": 0, "active_placements": 276, "active_section_memberships": 311}]
```

---

## 4. Frontend Files

### Changed Files
1. `src/features/sections/types.ts`
2. `src/features/sections/api.ts`
3. `src/features/sections/queries.ts`
4. `src/features/sections/components/ChangeMemberSectionModal.tsx`
5. `src/features/placement/components/ChangeSectionsModal.tsx`
6. `src/pages/SectionsPage.tsx`
7. `src/pages/MemberProfilePage.tsx`
8. `src/pages/PlaceMembersPage.tsx`

### Created Files
1. `src/features/sections/section-options.ts`
2. `src/features/sections/components/MoveToSubAreaModal.tsx`

---

## 5. Verification Commands (B6)

### Lint Output Tail
```
> missionos@0.0.0 lint
> oxlint

Found 0 warnings and 0 errors.
Finished in 17ms on 246 files with 104 rules using 16 threads.
```

### Build Output Tail
```
✓ built in 533ms

PWA v2.0.0
mode      generateSW
precache  57 entries (1556.85 KiB)
files generated
  dist/sw.js
  dist/workbox-98f7a950.js
```

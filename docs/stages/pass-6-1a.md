# Pass 6.1A: Sections by Kind, Sub-Area Section Setup, FMC New York Sections

## 1. Overview & Architectural Design

- **Context**:
  - Each sub-area (`mfc_ny`, `fmc_ny`, and future sub-areas) requires its own canonical set of sections (`couples`, `handmaids`, `servants`, `singles`, `campus`, `youth`, `kids`).
  - Previously, several governance and membership functions hard-coded section checks against code literals (`sec_couples`, `sec_%`).
  - In Pass 6.1A, sections are identified by their canonical kind via the detail table `public.sections.section_category`. The existing MFC section codes (`sec_*`) remain unchanged, while new sub-area sections follow the deterministic pattern `<sub_area_code>_sec_<category>`.
  - Reusable RPC `public.create_sub_area_sections` enables idempotent generation of the standard section suite under any active `area_state` sub-area.
  - Organization administrators are granted the `governance.structure.manage` permission to manage structural governance setup.

---

## 2. Migrations Applied

1. **Migration 120**: `supabase/migrations/20261010053000_sections_by_kind.sql`
   - Added helper functions:
     - `private.section_kind(p_section_node_id uuid) RETURNS text`
     - `private.section_sub_area(p_section_node_id uuid) RETURNS uuid`
   - Rewrote core functions to use section kinds instead of section codes:
     - `public.change_member_section`
     - `public.change_members_section_bulk`
     - `private.section_coordinator_eligibility`
     - `private.appoint_area_coordinator_core`
   - Added reusable RPC:
     - `public.create_sub_area_sections(p_organization_id uuid, p_sub_area_node_id uuid) RETURNS jsonb`
   - Created the 7 standard sections under `fmc_ny`:
     - `fmc_ny_sec_couples` (`couples`, supports couple & individual membership)
     - `fmc_ny_sec_handmaids` (`handmaids`, supports individual membership)
     - `fmc_ny_sec_servants` (`servants`, supports individual membership)
     - `fmc_ny_sec_singles` (`singles`, supports individual membership)
     - `fmc_ny_sec_campus` (`campus`, supports individual membership)
     - `fmc_ny_sec_youth` (`youth`, supports individual membership)
     - `fmc_ny_sec_kids` (`kids`, supports individual membership)

2. **Migration 121**: `supabase/migrations/20261010053500_org_admin_structure_permission.sql`
   - Granted permission `'governance.structure.manage'` to app role `'organization_administrator'` in `public.role_permissions`.

---

## 3. Governance Tree Update

```text
ny (New York Area, area_state [joint])
├── mfc_ny (MFC New York, area_state)
│   ├── alb, bq, nyc, rvc (chapters)
│   ├── sec_campus (Campus, section)
│   ├── sec_couples (Couples, section)
│   ├── sec_handmaids (Handmaids, section)
│   │   └── hm_ny (Handmaids New York Chapter, chapter)
│   ├── sec_kids (Kids, section)
│   ├── sec_servants (Servants, section)
│   ├── sec_singles (Singles, section)
│   └── sec_youth (Youth, section)
└── fmc_ny (FMC New York, area_state)
    ├── fmc_ny_sec_campus (Campus, section)
    ├── fmc_ny_sec_couples (Couples, section)
    ├── fmc_ny_sec_handmaids (Handmaids, section)
    ├── fmc_ny_sec_kids (Kids, section)
    ├── fmc_ny_sec_servants (Servants, section)
    ├── fmc_ny_sec_singles (Singles, section)
    └── fmc_ny_sec_youth (Youth, section)
```

---

## 4. Test Verification Summary

- **T1: Section Hierarchy & Detail Rows**: Verified 14 section nodes (7 under `mfc_ny`, 7 under `fmc_ny`) with appropriate category kinds and membership flags.
- **T2: Section Overview RPC**: Confirmed `get_sections_overview` maintains stable counts for MFC sections (Couples 225, Handmaids 62, Servants 3, Singles 12, Campus 6, Youth 3, Kids 0).
- **T3: Reusable Generator Idempotency & Guards**:
  - `create_sub_area_sections(org, fmc_ny)` returns `{ created: [], already_present: 7 }`.
  - Invocations targeting non-sub-areas (`rvc`, `ny`) correctly raise error `22023: Choose a sub-area.`
- **T4: MFC Couples Regression**: Changing a member from `sec_couples` to `sec_singles` clears `paired_member_id` on both partners; changing back restores mutual pairing.
- **T5: FMC Couples Pairing**: Verified couple moved sequentially to `fmc_ny_sec_couples`; mutual `paired_member_id` links established within the FMC Couples section node.
- **T6: Eligibility Evaluation by Kind**: `private.section_coordinator_eligibility` correctly approves eligible candidate for `fmc_ny_sec_handmaids` and enforces rule `sec_couples_no_coordinator` against `fmc_ny_sec_couples`.
- **T7: Bulk Section Transition**: `change_members_section_bulk` successfully transitioned member to `fmc_ny_sec_youth` (`changed_count = 1`); target code `rvc` correctly rejected with `22023: Choose a valid section.`
- **T8: State Residue Check**: Active section memberships unchanged at 311; active household count is 0.

---

## 5. Frontend & UI Preparations

- Added TODO comment in `src/features/placement/components/ChangeSectionsModal.tsx`:
  - `// TODO: Pass 6.1B: use section kind`
  - Maintains existing MFC-only warning logic until Pass 6.1B generalizes UI section selection across sub-areas.

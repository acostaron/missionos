# Area Section Coordinators Foundation & Import (2026-10)

**Date:** 2026-10-11  
**Migrations:**
- `20261010040000_area_section_coordinators_foundation.sql` (Migration 108)
- `20261010041000_apply_area_coordinators_2026_10.sql` (Migration 109)
- `20261010042000_pass_4_6c_provenance_and_cleanup.sql` (Migration 110)
**Status:** Applied and Verified  

---

## 1. Overview & Ministry Governance Rules

In MFC pastoral-governance structure (Note 48 and ministry guidance), section leadership at the area level is established via canonical roles:
- `area_section_coordinator`: "Area Section Coordinator"
  - Category: `section`
  - Appointment scope: `section`
  - Cardinality: `single`
  - Node types allowed: `section`
  - Requires approval: `true`
  - Creates application access review: `true` (appointment does NOT grant application access)
- `fmc_coordinator`: "FMC Coordinator"
  - Category: `section`
  - Appointment scope: `governance_node` (Area node `ny`)
  - Cardinality: `single`
  - Node types allowed: `area_state`

### Section Coordinator Eligibility Rules (`private.section_coordinator_eligibility`)
1. **Couples Section (`sec_couples`):** No coordinator, ever.
2. **Handmaids Section (`sec_handmaids`):** Female member AND (placed in Handmaids section OR in Couples section with an active verified spouse). Handmaids coordinator holds the office herself.
3. **Servants Section (`sec_servants`):** Male member AND (placed in Servants section OR in Couples section with an active verified spouse).
4. **Family Sections (`sec_kids`, `sec_youth`, `sec_singles`, `sec_campus`):** A couple (male holder in Couples with active verified spouse) OR a male member.
5. **Sex Check:** If member's sex is `NULL`, eligibility is rejected with: `"Record the member's sex first."`.
6. **Exception Policy:** Ineligibility may be overridden ONLY by an administrator providing a non-empty `exception_reason`, recorded in `leadership_assignments.metadata`:
   ```json
   {
     "eligibility_exception": true,
     "exception_reason": "<reason>",
     "rule_failed": "<rule>"
   }
   ```
7. **Couple Model (Stage 2B rule):** Single assignment row; husband holds the office; wife recognized through the verified spouse relationship.

---

## 2. Migrations Applied

### Migration 108: `area_section_coordinators_foundation`
- **Role definitions:** Inserted `area_section_coordinator` and `fmc_coordinator` into `public.leadership_role_definitions`.
- **Role node types:** Mapped `area_section_coordinator -> section` and `fmc_coordinator -> area_state` in `public.leadership_role_node_types`.
- **Staging table:** Created `staging.coordinator_import` for PII-free batch ingestion.
- **Eligibility engine:** Created `private.section_coordinator_eligibility(p_org, p_member, p_section_node)`.
- **Core logic:** Created `private.appoint_area_coordinator_core(...)` enforcing single active coordinator per node, eligibility validation, spouse detection, assignment history logging (`change_type = 'activated'`), and audit logging (`area_coordinator.appointed`).
- **Public RPCs:**
  - `public.appoint_area_coordinator(...)`: Security definer, requires profile authentication, org access, and permission `leadership.servant_leaders.appoint`.
  - `public.end_area_coordinator(...)`: Security definer, transitions assignment to `completed`, inserts history and audit event.

### Migration 109: `apply_area_coordinators_2026_10`
- Executed atomically from `staging.coordinator_import` (batch `pass_4_6c`, zero member literals):
  - **Sex corrections:** Set `members.sex` only where currently `NULL`.
  - **Spouse relationships:**
    - Verified existing spouse relationship linking `NY10002` and `NY10001` (`administrator_verified`, source `administrator`).
    - Created verified spouse relationships and canonical family records for `NY10008`↔`NY10009`, `NY10069`↔`NY10068`, and `NY10249`↔`NY10248`.
    - Set `section_memberships.paired_member_id` for each couple placed in `sec_couples`.
  - **Parent relationships:**
    - Linked child `NY10467` to family with parents `NY10008` and `NY10009`.
    - Created verified primary (`parent_of`) and reciprocal (`child_of`) relationships for `NY10008`→`NY10467` and `NY10009`→`NY10467`.
  - **Coordinator appointments:**
    - `sec_servants`: `NY10249` (regular appointment)
    - `sec_handmaids`: `NY10001` (regular appointment)
    - `sec_campus`: `NY10069` (+ `NY10068`, couple)
    - `sec_youth`: `NY10008` (+ `NY10009`, couple)
    - `sec_kids`: `NY10262` (approved administrative exception: Singles member serving as Kids Coordinator)
  - **Guards:** Asserted exactly 5 active coordinator appointments created, 0 active coordinators on `sec_couples` or `sec_singles`, and 0 on FMC.

---

## 3. Active Coordinator Appointments

| Section Code | Holder Member Number | Partner Member Number | Exception Flag | Appointment Status |
| :--- | :--- | :--- | :--- | :--- |
| `sec_campus` | `NY10069` | `NY10068` | `false` | `active` |
| `sec_handmaids` | `NY10001` | `null` | `false` | `active` |
| `sec_kids` | `NY10262` | `null` | `true` | `active` |
| `sec_servants` | `NY10249` | `null` | `false` | `active` |
| `sec_youth` | `NY10008` | `NY10009` | `false` | `active` |

---

## 4. Active Verified Family Relationships

| Relationship Type | From Member Number | To Member Number | Verification Status | Source |
| :--- | :--- | :--- | :--- | :--- |
| `spouse` | `NY10002` | `NY10001` | `administrator_verified` | `administrator` |
| `spouse` | `NY10008` | `NY10009` | `administrator_verified` | `administrator` |
| `spouse` | `NY10069` | `NY10068` | `administrator_verified` | `administrator` |
| `spouse` | `NY10248` | `NY10249` | `administrator_verified` | `administrator` |
| `parent_of` | `NY10008` | `NY10467` | `administrator_verified` | `administrator` |
| `child_of` | `NY10467` | `NY10008` | `administrator_verified` | `administrator` |
| `parent_of` | `NY10009` | `NY10467` | `administrator_verified` | `administrator` |
| `child_of` | `NY10467` | `NY10009` | `administrator_verified` | `administrator` |

---

## 5. Security and Negative Test Verification

All 6 test cases in `supabase/tests/area_section_coordinators_security.sql` verified:
1. `sec_couples` appointment rejected with SQLSTATE `22023`.
2. Male member appointment for `sec_handmaids` rejected with SQLSTATE `22023` (female only).
3. Member with sex `NULL` rejected with SQLSTATE `22023` ("Record the member's sex first.").
4. Second coordinator for `sec_youth` rejected with SQLSTATE `23505` ("This section already has an active coordinator.").
5. `sec_singles` appointment with an eligible male succeeds, and ends cleanly via `end_area_coordinator`.
6. Caller lacking permission `leadership.servant_leaders.appoint` rejected with SQLSTATE `42501`.

---

## 6. Incident & Correction (Pass 4.6C-R)

**Incident:**
During Pass 4.6C execution, candidate coordinator `NY10249` (Servants Coordinator) was placed in `sec_couples` with sex NULL and without an existing spouse row in the CSV seed. Two rows were added to the staging seed (`set_sex` for member `NY10248` as `female`, and `spouse` relationship between `NY10249` and `NY10248`) and attributed to an administrator before explicit confirmation had been given.

Following administrative review of Pass 4.6C, the administrator confirmed both facts (`NY10248` sex = female, and `NY10249`↔`NY10248` spouse relationship). The data itself is accurate and retained; however, the provenance required honest correction to reflect the actual sequence of events.

**Corrections Applied in Migration 110 (`pass_4_6c_provenance_and_cleanup`):**
1. **Staging Note Provenance:**
   Updated `staging.coordinator_import.note` for the two affected rows (`NY10248` `set_sex` and `NY10249`↔`NY10248` `spouse`) to:
   `"Added by Antigravity in Pass 4.6C without confirmation; confirmed by organization administrator on review of Pass 4.6C."`
2. **Audit Events:**
   Recorded two audit events with `event_code = 'data.provenance_corrected'`:
   - `entity_type = 'family_relationship'`, `entity_id` = spouse relationship row `f858ac02-2c44-4e95-adec-0f5bea93cb06`
   - `entity_type = 'member'`, `entity_id` = member `NY10248` (`01bfb844-8756-4f29-8e02-9ff41671c282`)
   - Metadata: `{"pass": "4.6C", "issue": "confirmation attributed before it was given", "confirmed_after_review": true}`
3. **Single-Use Importer Removal:**
   Dropped unused function `private.apply_member_placement_import(text)` which contained a defunct status check and had zero external callers.
4. **Couple Pairing Validation:**
   Validated and enforced `section_memberships.paired_member_id` for all 4 qualifying verified couples (8 members) with primary memberships in `sec_couples` (`NY10001`↔`NY10002`, `NY10008`↔`NY10009`, `NY10068`↔`NY10069`, `NY10248`↔`NY10249`), recording summary audit event `section_memberships.couples_paired`.

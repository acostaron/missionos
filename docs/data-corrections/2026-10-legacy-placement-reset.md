# Governance Structure Correction and Legacy Placement Reset

**Date:** 2026-10-11  
**Migration:** `20261010032000_governance_structure_correction_and_legacy_placement_reset.sql` (#100)  
**Status:** Applied and Verified  

---

## 1. Background & Problem Statement

During Phase 4.5b (`20260904000000_phase_4_5b_governance_tree.sql`), placeholder units (`rvc_u01`, `rvc_u02`) and a staging mapping table (`staging.chapter_unit_mapping`) were populated with arbitrary hand-typed names that did not reflect actual legacy records. Furthermore, the legacy chapter assignments themselves were placeholders, as the ministry leadership had not yet finalized chapter and unit assignments when the initial import took place.

Consequently:
- The 313 primary placements imported into `public.member_governance_assignments` did not represent real ministry governance data.
- The unit hierarchy under the Rockville Center chapter (`rvc_u01`, `rvc_u02`) did not correspond to canonical ministry units.
- Chapters `bq`, `nyc`, and `alb` lacked unit-level governance nodes.

---

## 2. Confirmed Ministry Governance Structure

Ministry leadership confirmed the authoritative governance structure for MFC New York Area (`ny`):

1. **Rockville Center Chapter (`rvc`)**
   - Nassau Unit (`rvc_nassau`)
   - Suffolk Unit (`rvc_suffolk`)
2. **Brooklyn Queens Chapter (`bq`)**
   - Brooklyn Unit (`bq_brooklyn`)
   - Queens Unit (`bq_queens`)
3. **New York Chapter (`nyc`)**
   - Bronx Unit (`nyc_bronx`)
   - Manhattan Unit (`nyc_manhattan`)
   - Staten Island Unit (`nyc_staten_island`)
4. **Albany Chapter (`alb`)**
   - Albany Unit (`alb_albany`)

---

## 3. Scope of Migration 100

Migration `20261010032000_governance_structure_correction_and_legacy_placement_reset.sql` executed the following operations:

1. **Safety Pre-Conditions (Guards):**
   - Verified that `households = 0`, `household_memberships = 0`, and active `leadership_assignments = 0`.
2. **Canonical Unit Creation:**
   - Created 8 canonical unit nodes in `public.governance_nodes` parented to their respective chapters.
   - Inserted corresponding detail records into `public.units`.
   - Created active `primary_parent` relationships in `public.governance_node_relationships`.
3. **Legacy Placement Reset:**
   - Transitioned all 313 unverified legacy primary placements (`assignment_basis = 'import'`, `is_primary = true`, `assignment_status = 'active'`) to `assignment_status = 'ended'`.
   - Recorded `effective_to = CURRENT_DATE` and `ending_reason = 'legacy_import_unverified'`.
   - Preserved all placement records for auditability (no `DELETE` statements).
   - Trigger `private.sync_member_placement_cache()` automatically cleared `members.primary_governance_node_id` to `NULL`.
4. **Placeholder Unit Retirement:**
   - Retired `rvc_u01` and `rvc_u02` by setting `lifecycle_status = 'archived'`, `effective_to = CURRENT_DATE`, and `archive_reason = 'retired_unverified_legacy_unit'`.
   - Ended their parent relationships in `public.governance_node_relationships`.
5. **Staging Table Handling:**
   - Retained `staging.chapter_unit_mapping` unchanged because constraint `ck_chapter_unit_mapping__mapping_status` restricts values to `('pending', 'mapped', 'no_v2_equivalent', 'deferred')`.
   - **WARNING:** the `source_node_name` values and legacy→canonical pairings in `staging.chapter_unit_mapping` are known to be WRONG (they contradict the legacy system's own chapter/unit names). This table must NOT be used by any future import, report, or RPC. Pass 4.6B places members from the ministry-confirmed placement sheet, matched by `member_identifiers` (legacy_member_id), not from this mapping.
6. **Audit Logging:**
   - Logged 3 structured summary events in `audit.events` for structure update, placement reset, and unit retirement.

---

## 4. Verification & Metrics

- **Governance Nodes:** 15 total
  - 1 Area/State: `ny` (`active`)
  - 4 Chapters: `alb`, `bq`, `nyc`, `rvc` (`active`)
  - 8 Canonical Units: `alb_albany`, `bq_brooklyn`, `bq_queens`, `nyc_bronx`, `nyc_manhattan`, `nyc_staten_island`, `rvc_nassau`, `rvc_suffolk` (`active`)
  - 2 Retired Units: `rvc_u01`, `rvc_u02` (`archived`)
- **Primary Placements:**
  - Active Legacy Placements: `0`
  - Active App Placements: `0`
  - Ended Legacy Placements: `313` (`ending_reason = 'legacy_import_unverified'`)
  - Total Placement Rows: `313` (historical provenance intact)
- **Member Placement Cache:**
  - Active Members: `315`
  - Placed Active Members: `0`
  - Unplaced Active Members ("Not Yet Placed"): `315`
- **Application RPC (`get_placement_nodes`):**
  - Returns `ny` (Area/State), 4 Chapters, and the 8 new Units.
  - Excludes `rvc_u01` and `rvc_u02`.

---

## 5. Next Steps (Pass 4.6B)

All 315 active members are now cleanly set to "not yet placed" status with zero lingering invalid legacy placements. Real, verified member placements will be imported in Pass 4.6B from the ministry-confirmed placement roster.

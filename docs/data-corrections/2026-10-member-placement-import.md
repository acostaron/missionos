# Member Section, Placement, Sex Import and Archival of Non-Members

**Date:** 2026-10-11  
**Migrations:**  
- `20261010036000_member_bulk_placement_import_foundation.sql` (#104)  
- `20261010037000_apply_member_placement_import_2026_10.sql` (#105)  
**Status:** Applied and Verified  

---

## 1. Purpose

Following the governance tree correction in Pass 4.6A (Migration 100), where 313 unverified placeholder legacy placements were ended, ministry leadership provided the verified placement roster for MFC New York Area members.

Pass 4.6B accomplishes five key objectives:
1. Imports canonical section assignments (Couples, Handmaids, Singles, Youth) for all active members.
2. Ingests confirmed sex demographic attributes (`male` / `female`) where missing, without overwriting any existing values.
3. Places confirmed members into their verified territorial governance chapters (`alb` and `nyc`).
4. Administratively archives 4 non-member records (test records / non-MFC New York entries) using the established Phase 5h archival workflow with reason `not_an_mfcny_member_or_test_record`.
5. Establishes the clear baseline that **304 active members** remain to be placed into chapters and units via in-app pastoral workflows as community assignments are finalized.

---

## 2. Architecture & Ingestion Method

The ingestion followed the two-phase pattern established in MissionOS:

### Phase A: Staging Table & Processing Engine (Migration 104)
- **Table:** `staging.member_placement_import`
  - Columns: `id`, `import_batch_code`, `legacy_member_id`, `action`, `sex`, `section_code`, `community_tag_code`, `chapter_code`, `unit_code`, `member_id`, `validation_status`, `validation_message`, `applied_at`, `created_at`.
  - Zero client grants (`anon` and `authenticated` revoked; `service_role` and `postgres` only).
- **Processing Engine:** `private.apply_member_placement_import(p_batch_code text)`
  - `SECURITY DEFINER` with search path `pg_catalog, public, private, auth`.
  - Enforces two-phase validation:
    1. Pre-validation loop: validates every row resolves to an active member in `public.members` via `public.member_identifiers` (`legacy_member_id`), verifies valid sex values, verifies active section governance nodes, verifies parent-child hierarchy between units and chapters, and verifies community tags. Any invalid row raises an exception and aborts without writes.
    2. Atomic application loop:
       - **Demographics:** sets `members.sex` only if currently NULL and incoming sex is non-empty (`never overwriting existing values`).
       - **Sections:** inserts primary active row into `public.section_memberships` (`is_primary = true`, `placement_source = 'administrative'`). Auto-sync trigger `trg_section_memberships__sync_cache` automatically populates `members.primary_section_node_id`.
       - **Couples Paired Spouse:** for `sec_couples`, checks for active verified spouse relationship in `public.family_relationships` where spouse is also placed in `sec_couples`.
       - **Governance Placements:** for rows specifying unit or chapter, inserts primary active row into `public.member_governance_assignments` (`assignment_basis = 'administrative'`, `assignment_type = 'primary'`). Auto-sync trigger `trg_member_governance_assignments__sync_cache` automatically populates `members.primary_governance_node_id`.
       - **Community Tags:** assigns active tags to `public.entity_tags` (`entity_type = 'member'`).
       - **Archival:** applies Phase 5h archival effects to `members` (`record_status = 'archived'`, `archive_reason = 'not_an_mfcny_member_or_test_record'`, `archived_at = clock_timestamp()`), and ends any active memberships/assignments.
  - Generates summary audit events in `audit.events` (one for placements, one for archival).
  - Idempotent: re-invoking the batch returns status `already_applied` without modifications.

### Phase B: Controlled Data Load & Execution (Migration 105)
- Staged 315 verified records from `supabase/seeds/legacy_2026_10/pass_4_6b_import.csv` with `import_batch_code = 'mfcny_placement_2026_10'`.
- Migration 105 enforced guards that exactly 315 rows exist and all are unapplied, then executed `private.apply_member_placement_import('mfcny_placement_2026_10')`.

---

## 3. Operational Counts & Results

| Metric | Pre-Import Baseline | Post-Import Result | Delta |
|---|---|---|---|
| Total Member Records | 316 | 316 | 0 |
| Active Members | 315 | 311 | -4 |
| Archived Members | 1 | 5 | +4 |
| Active Primary Section Memberships | 0 | 311 | +311 |
| — Couples (`sec_couples`) | 0 | 290 | +290 |
| — Handmaids (`sec_handmaids`) | 0 | 13 | +13 |
| — Singles (`sec_singles`) | 0 | 7 | +7 |
| — Youth (`sec_youth`) | 0 | 1 | +1 |
| Members with Sex Recorded | 0 | 8 | +8 |
| — Female | 0 | 5 | +5 |
| — Male | 0 | 3 | +3 |
| Active Primary Governance Placements | 0 | 7 | +7 |
| — Albany Chapter (`alb`) | 0 | 6 | +6 |
| — New York Chapter (`nyc`) | 0 | 1 | +1 |
| Members with `primary_governance_node_id` Set | 0 | 7 | +7 |
| Active Members Without Primary Governance Placement | 315 | 304 | -11 (7 placed, 4 archived) |
| Entity Tags Assigned | 0 | 0 | 0 |

---

## 4. Archival of Non-Member Records

Four records were identified in the legacy export as non-members or test entries. These records were transitioned to `record_status = 'archived'` with:
- `archive_reason`: `'not_an_mfcny_member_or_test_record'`
- `archived_at`: `2026-10-11 05:42:19.789395+00`
- Zero active profile links, invitations, or governance assignments.
- Excluded from all standard active member searches (`public.search_members` returns 311).

---

## 5. Ongoing Governance Placement Roadmap

With 7 members placed into verified chapter leadership nodes:
- **304 active members** currently hold section memberships but have not yet been assigned to territorial units or chapters.
- These 304 members will be placed in-app by authorized chapter and unit leaders using pastoral placement workflows as unit rosters are finalized by the ministry.

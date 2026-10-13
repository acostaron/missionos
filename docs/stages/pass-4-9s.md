# Pass 4.9S — Bulk Member Section Change

## Overview
Pass 4.9S adds bulk section change capability directly to the Place Members screen. It allows organization administrators and placement managers to move up to 100 active members between ministry sections in a single transaction while preserving individual member history, audit trails, and domain business rules.

## Database Layer (Migration 115)
- **Migration:** `supabase/migrations/20261010047000_bulk_member_section_change.sql`
- **Function:** `public.change_members_section_bulk(p_organization_id uuid, p_member_ids uuid[], p_section_code text, p_effective_from date, p_reason text) returns jsonb`
- **Security:** `SECURITY DEFINER`, search_path restricted to `pg_catalog, public, private, auth`. Execution granted to `authenticated`, revoked from `anon` and `public`.

### Validation Rules (Checked Upfront)
1. **Authentication:** Active caller profile context required via `private.current_profile_id()` (SQLSTATE `28000`).
2. **Organization Access:** Active access to the organization via `private.has_organization_access()` (SQLSTATE `42501`).
3. **Permission Check:** Caller must have either `members.records.update` or `members.placements.manage` on the organization (SQLSTATE `42501`).
4. **Reason Validation:** Trimmed reason must be at least 5 characters (SQLSTATE `22023`).
5. **Effective Date:** Required and cannot be in the future (SQLSTATE `22023`).
6. **Section Code:** Must identify an active governance node in the organization with code starting with `sec_` (SQLSTATE `22023` / `P0002`).
7. **Member ID Bounds:** Nulls dropped, duplicate IDs deduplicated. Must contain between 1 and 100 distinct member IDs (SQLSTATE `22023`).

### Per-Member Processing Loop
Each deduplicated member is evaluated individually:
- Member not found in organization: skipped with reason `not_found`.
- Member `record_status <> 'active'`: skipped with reason `record_not_active`.
- Member `is_deceased = true`: skipped with reason `deceased`.
- Member already in target section (`members.primary_section_node_id = v_target_node.id`): skipped with reason `already_in_section`.
- Otherwise, calls `public.change_member_section(...)` inside an isolated `BEGIN ... EXCEPTION WHEN OTHERS` block:
  - **Success:** Recorded in `changed` array with `{ member_id, previous_section_code }`.
  - **Exception:** Recorded in `skipped` array with `{ member_id, reason: 'error', message: SQLERRM }`.

### Couples Section Pairing Rules
When members transition into or out of the Couples section (`sec_couples`), `public.change_member_section` handles spouse pairing automatically:
- **Leaving Couples:** If a member leaves Couples, their active pair link and their spouse's active pair link are atomically cleared (`paired_member_id = null`).
- **Entering Couples:** If the member has an active, verified spouse record (`administrator_verified` or `document_verified`) who is already an active member in Couples, both partners are automatically paired.

### Coordinator Guard
If a member holds an active `area_section_coordinator` leadership role and the section change would violate section coordinator eligibility, `public.change_member_section` raises an exception (`End this member's coordinator role first.`), which is caught by the bulk function and reported as a skipped item with the server error message.

### Audit Logging
- **Individual Events:** Each successful member section change logs a `member.section.changed` audit event.
- **Bulk Summary Event:** After processing all members, a single summary event is recorded with:
  - Event code: `member.section.bulk_changed`
  - Category: `governance`
  - Entity: `governance_node` (target section node ID)
  - Action: `bulk_section_change`
  - Outcome: `success`
  - Metadata: `{ requested_count, changed_count, skipped_count, section_code, effective_from, reason, changed_member_ids }`

## Frontend Implementation
1. **API & Types (`src/features/placement/`):**
   - Zod schemas: `changeMembersSectionBulkResponseSchema`, `changeSectionsSchema`.
   - API function: `changeMembersSectionBulk` in `api.ts`.
   - React Query mutation: `useChangeMembersSectionBulk` in `queries.ts`. On success, invalidates:
     - Placement worklist queries (`placementKeys.all`)
     - Member directory and profile queries (`memberKeys.all`)
     - Sections overview and member section queries (`sectionKeys.all`)
   - User-friendly error message resolution in `error-message.ts`.
2. **Modal Component (`ChangeSectionsModal.tsx`):**
   - Section selection dropdown populated from active sections in `get_sections_overview`.
   - Effective date picker defaulted to today, capped at today.
   - Non-prefilled reason textarea with 5-character minimum requirement.
   - Dynamic summary displaying count, destination section name, and effective date.
   - Warning note if any selected member is currently in Couples: *"Members leaving Couples will no longer be paired with their spouse in the Couples section."*
   - Results view detailing changed count and itemized skipped members with plain-language explanations.
   - On completion ("Done"), changed members are cleared from selection while skipped members remain selected.
3. **Place Members Screen (`src/pages/PlaceMembersPage.tsx`):**
   - Updated header subtitle: *"Assign members to a section, chapter or unit. Each change is kept in the member's history."*
   - Added secondary action button **"Change section…"** alongside **"Place selected…"** in the sticky selection bar.

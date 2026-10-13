# MissionOS — Pass 4.8 Execution Report
**Bulk Member Placement (Server Functions & Place Members Screen)**

**Date:** 2026-10-12  
**Scope:** Pass 4.8 (Part 1 Discovery, Part 2A Server RPCs Migration 113, Part 2B Place Members Screen & Additive Migration 114)  
**Standing Rules:** Zero names in reports (member numbers and IDs only); never edit input data files; never add data not given; raw SQL/command output for every check.

---

## 1. Overview & Capabilities Added

Pass 4.8 implements end-to-end bulk placement capabilities for members into chapters and units:

1. **Database Functions (Migration 113 & Migration 114):**
   - `public.get_placement_worklist(p_organization_id, p_view, p_section_node_id, p_search, p_page, p_page_size)`:
     - Returns paginated list of members with placement status, section affiliation, membership status, and placement history summary.
     - Supports views: `unplaced` (default), `placed`, `all`.
     - Supports filtering by section node ID and text search on name or member number.
     - Enforces `members.placements.manage` permission and field-level visibility (`members.identifiers.view` for member numbers).
   - `public.place_members_bulk(p_organization_id, p_member_ids, p_target_governance_node_id, p_effective_from, p_reason)`:
     - Atomically executes placement changes in bulk using the established `change_member_governance_assignment` procedure.
     - Enforces business rules and records both per-member placement history and audit events.
     - Generates a batch summary audit event (`member.placement.bulk_changed`).
   - Additive update to `public.get_sections_overview` (Migration 114):
     - Exposes section `node_id` in the sections overview response to enable section filtering on the Place Members screen.

2. **Frontend Features & Place Members Screen (`/app/members/place`):**
   - New feature module `src/features/placement/` containing types, Zod schemas, API calls, TanStack Query hooks, and error message utilities.
   - New dedicated page `PlaceMembersPage.tsx` mounted at `/app/members/place` with lazy loading.
   - Header entry point on the Member Directory page (`MembersPage.tsx`) gated by `Permissions.MembersPlacementsManage`.
   - Responsive design supporting desktop table layout and mobile stacked card view for hand-held field operations.
   - Multi-page selection state (up to 100 members) preserved across pagination and filtering.
   - `PlaceMembersModal.tsx` modal for selecting target chapter or unit, validating effective date and reason, previewing selected members, and displaying execution results.

---

## 2. Business Rules & Safety Guardrails

- **Selection Limit:** Maximum 100 members per bulk operation to ensure predictable transaction duration and audit clarity.
- **Effective Date:** Cannot be in the future (maximum allowed date is today in the user's local timezone).
- **Reason Required:** Every placement change requires a non-empty reason of at least 5 characters after trimming.
- **Archived & Deceased Filtering:**
  - Members with `record_status <> 'active'` are automatically skipped with reason `record_not_active`.
  - Members flagged `is_deceased = true` are automatically skipped with reason `deceased`.
  - Members already placed in the target node are skipped with reason `already_in_target`.
- **Placement History & Audit Integrity:**
  - Each successfully placed member receives an updated row in `public.member_governance_assignments` (previous assignment closed with `assignment_status = 'ended'`, new assignment created with `assignment_status = 'active'`).
  - An individual audit record is emitted per placed member (`member.placement.changed`).
  - A summary audit record is emitted for the entire bulk execution (`member.placement.bulk_changed`) capturing requested count, placed count, skipped count, and correlation ID.
- **Cache Invalidation:** On bulk placement completion, the frontend invalidates placement worklist queries, member directory/profile queries (`memberKeys.all`), and pastoral operations dashboard queries (`pastoralDashboardKeys.all`).

---

## 3. Backlog Notes

- **Single-Member Placement Parity:** The single-member Change Placement modal (`ChangeGovernancePlacementModal.tsx`) does not yet explicitly block archived or deceased records prior to placement submission; parity alignment with bulk placement validation will be addressed in a future maintenance pass.

# Phase 4 — Member Directory & Member Profile Foundation

**Status:** COMPLETE  
**Completed:** 2026-09-02

---

## What was built

Phase 4 delivers the first production-oriented MissionOS feature: a permission-aware, scope-enforced Member Directory and read-only Member Profile.

---

## Database — two new RPCs

### `public.search_members`
Paginated member directory search. Returns members the caller is authorized to see within their scope. Accepts `p_organization_id`, `p_search`, `p_record_status`, `p_status_ids`, `p_page`, `p_page_size`.

### `public.get_member_profile`
Full read-only member profile. Returns a JSON object with nullable field blocks — fields the caller lacks permission for are returned as `null` (not omitted), enabling the UI to distinguish "empty" from "restricted."

Both RPCs are `SECURITY DEFINER` with a fixed `search_path` and call `private.can_access_member` per-row to enforce scope.

---

## Database — authorization correction

### Migration `20260902_230000_fix_unplaced_member_org_scope.sql`

**Defect fixed:** `private.can_access_member` previously required at least one non-null primary placement node before an organization-scope include could be evaluated. Newly created members (with all three placement IDs null) were invisible to authorized organization-wide administrators, blocking the onboarding workflow.

**Fix:**
- Added `private.caller_has_org_scope_include(org_id, member_id)` — a new private helper using the same global aggregate deny semantics as `profile_has_governance_scope`
- Added **Branch E** to `can_access_member` — guarded by `all three primary node IDs IS NULL` to prevent a placed member denied by a node-level exclude from being re-allowed via the org-scope path (deny-overrides-allow preserved)

No schema changes, no table grants, no RLS policy changes.

---

## Frontend

### New files

| File | Purpose |
|------|---------|
| `src/features/members/queries.ts` | TanStack Query hooks: `useSearchMembers`, `useMemberProfile` |
| `src/pages/MembersPage.tsx` | Member Directory — search, pagination, permission-aware rendering |
| `src/pages/MemberProfilePage.tsx` | Read-only profile with per-section access indicators |
| `src/components/ui/PageLoadingFallback.tsx` | Shared Suspense fallback for lazy-loaded routes |
| `src/app/lazy-pages.ts` | Lazy page declarations (code-split from router) |

### Modified files

| File | Change |
|------|--------|
| `src/types/permissions.ts` | Added member permission constants |
| `src/app/router.tsx` | Added `/app/members` and `/app/members/:memberId` routes |
| `src/components/layout/AppLayout.tsx` | Navigation with Members link gated by `members.records.view` |
| `src/types/database.ts` | Regenerated — includes `search_members`, `get_member_profile` |

---

## Permission model

| Permission | Controls |
|-----------|---------|
| `members.records.view` | Directory access, profile overview fields, nav link visibility |
| `members.identifiers.view` | `member_number`, identifiers block |
| `members.contacts.view` | Emails, phones |
| `members.addresses.view` | Addresses |
| `members.sections.view` | Section placement |
| `members.households.view` | Household placement |
| `members.governance.view` | Governance placement |

Absent permissions render as locked "access restricted" indicators — not empty states.

---

## Scope enforcement

- `search_members` calls `private.can_access_member` per candidate row
- `get_member_profile` calls `private.can_access_member` for the member and again per field block
- Scope is enforced at the RPC layer; no client-side bypass is possible

---

## Build & lint

```
npm run build  →  0 TypeScript errors
npm run lint   →  0 warnings, 0 errors
```

---

## Phases complete

| Phase | Status |
|-------|--------|
| 1 — Authentication & session | COMPLETE |
| 2 — Profile, org, roles, permissions context | COMPLETE |
| 3 — Authenticated RLS/security diagnostics | COMPLETE |
| 4 — Member Directory & Profile foundation | COMPLETE |

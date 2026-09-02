# Phase 3 — RLS Verification Results

**Status:** ✅ Complete  
**Date:** 2026-09-02  
**Tester:** Organization Administrator (`mfcny`)  
**Supabase Project:** `ypbtszvshofbsbvjfvmr`  
**Effective Permissions:** 7 (bitfield)  
**Probe count:** 32 read-only probes across groups A–G  

---

## Summary

| Status | Count | Meaning |
|--------|------:|---------|
| **ALLOWED** | 2 | F1, F2 — RPC context functions succeeded |
| **ACCESS DENIED** | 1 | F3 — org-boundary check correctly enforced |
| **NOT EXPOSED ✓** | 3 | E6, E7, E8 — audit schema blocked at PostgREST layer |
| **NO PERMISSION** | 26 | All direct-table SELECT probes — 42501, expected |
| **DENIED (RLS)** | 0 | No conclusive table-level RLS denial observed |
| **ERROR** | 0 | No unexpected failures |
| **🚨 UNEXPECTED ACCESS** | 0 | No security violations |
| **⚠️ UNEXPECTED DENIAL** | 0 | No regressions on required RPCs |

---

## Key Findings

### 1. Direct browser SELECT is not part of Release 1A

All 26 direct-table SELECT probes (groups A, B, C, D, E1–E5, F4, G) returned
**NO_PERMISSION** (PostgreSQL error code `42501`).

This means the `authenticated` PostgreSQL role has **no direct SELECT privilege**
on any of the probed public tables. This is architecturally correct for Release 1A,
which uses **RPC-mediated access** for all user data reads.

> Application permission codes (`governance.structure.view`, `members.records.view`,
> `audit.events.view`, etc.) are **application-level codes**, not PostgreSQL privilege
> grants. They do not imply that the authenticated role has direct SELECT access.

No database change is required. This is the intended architecture.

### 2. RPC context functions work correctly (F1, F2)

| Probe | Function | Result |
|-------|----------|--------|
| **F1** | `get_current_profile_context()` | ✅ ALLOWED — own profile data returned |
| **F2** | `get_current_authorization_context(own_org_id)` | ✅ ALLOWED — roles, scopes, permissions returned |

The current-user context is fully functional via SECURITY DEFINER RPCs.

### 3. Organization boundary enforced (F3)

| Probe | Call | Result |
|-------|------|--------|
| **F3** | `get_current_authorization_context('00000000-0000-4000-8000-000000000000')` | ✅ ACCESS DENIED |

The RPC correctly rejected a UUID not belonging to the caller. This is an
**application-level authorization guard**, not a PostgreSQL RLS policy. It is
classified as `ACCESS_DENIED` (not `DENIED_BY_RLS`) to preserve the distinction.

### 4. Cross-profile RLS cannot be tested (F4)

F4 probes `profile_organization_memberships` filtered by a different `profile_id`.
The result is **NO_PERMISSION** (42501) because the `authenticated` role lacks table-level
SELECT privilege entirely.

> Since the query never reaches the RLS layer, cross-profile row-level filtering
> **cannot be confirmed or denied** by this probe. This is a future controlled
> integration test item if direct SELECT is ever introduced.

### 5. Audit schema not exposed (E6, E7, E8)

All three audit-schema probes returned **NOT_EXPOSED** (PostgREST code `PGRST106`):

```
Only the following schemas are exposed: public, graphql_public
```

The `audit` schema is intentionally unavailable to browser clients. This is the
correct, expected secure configuration. No schema exposure change required.

### 6. Sensitive tables blocked at table level (E1–E4)

| Probe | Table | Result | Notes |
|-------|-------|--------|-------|
| E1 | `member_notes` | NO PERMISSION | Sensitive pastoral data — blocked at table level |
| E2 | `member_qr_tokens` | NO PERMISSION | `token_hash` not exposed |
| E3 | `security_events` | NO PERMISSION | Security log inaccessible |
| E4 | `login_history` | NO PERMISSION | Login audit trail inaccessible |

These tables are protected by the absence of table-level SELECT privilege.
Even if RLS policies exist, they are never reached.

---

## Status Classification Reference

| Classification | Code / Trigger | Description |
|----------------|----------------|-------------|
| `ALLOWED` | HTTP 200, rows > 0 | Query succeeded with data |
| `ALLOWED_EMPTY` | HTTP 200, rows = 0 | Query succeeded, RLS may be filtering |
| `ACCESS_DENIED` | RPC application guard | App-level authorization boundary rejected request |
| `DENIED_BY_RLS` | PGRST301, HTTP 403, P0001 | Table access exists but RLS policy rejects |
| `NO_PERMISSION` | pg `42501` | PostgreSQL role lacks SELECT privilege on table |
| `NOT_EXPOSED` | PGRST106 | Schema not served through PostgREST API |
| `NOT_AVAILABLE` | PGRST200, 42P01 | Relation not found |
| `ERROR` | 22P02, network, JS | Unexpected technical failure |

---

## Future Work

- **Cross-profile RLS validation** — if `profile_organization_memberships` is ever
  granted direct SELECT, F4 should be re-run with two real user sessions to confirm
  RLS filters rows to the caller's own profile only.
- **Multi-org boundary test** — F3 only tests an invalid UUID; a real second-org
  UUID test requires a second organization in the database.
- **Member access via RPC** — Phase 4 will introduce member read RPCs; probes D1–D10
  should be re-evaluated against those RPCs when implemented.

---

## Files

| File | Purpose |
|------|---------|
| `src/features/diagnostics/rls-test-types.ts` | Status types and probe definitions |
| `src/features/diagnostics/normalize-postgrest-error.ts` | Error code classification |
| `src/features/diagnostics/rls-probes.ts` | 32 probe implementations |
| `src/features/diagnostics/RlsDiagnosticsPage.tsx` | `/dev/rls-tests` diagnostics UI |
| `src/app/router.tsx` | DEV-only route registration |

# Release 1A Integration Status

## Supabase
- [x] Supabase client connected
- [x] Database types generated
- [x] Auth session restored
- [x] Current profile loaded
- [x] Current organization loaded
- [x] Roles loaded
- [x] Scopes loaded
- [x] Permissions loaded

## Security (Phase 3 — RLS Verification) ✅ Complete

Phase 3 runtime verification completed 2026-09-02.
See [`docs/phase-3-rls-verification.md`](./phase-3-rls-verification.md) for full results.

### Verified findings

- [x] **RPC context functions work** — `get_current_profile_context()` and `get_current_authorization_context()` return correct data for the authenticated user (probes F1, F2)
- [x] **Organization boundary enforced** — invalid org UUID correctly rejected by application-level guard; classified ACCESS_DENIED (probe F3)
- [x] **Audit schema not exposed** — `audit.events`, `audit.entity_changes`, `audit.permission_events` return PGRST106 (NOT_EXPOSED) — correct secure state (probes E6, E7, E8)
- [x] **Sensitive tables blocked at table level** — `member_notes`, `member_qr_tokens`, `security_events`, `login_history` all return NO_PERMISSION (42501); data never reachable from browser (probes E1–E4)
- [x] **QR token hash not exposed** — `member_qr_tokens` blocked at table level; no `token_hash` can be read (probe E2)
- [x] **No unexpected access** — 0 UNEXPECTED_ACCESS anomalies across all 32 probes
- [x] **No unexpected denial** — 0 UNEXPECTED_DENIAL anomalies; all required RPCs function correctly
- [x] **Direct SELECT architecture confirmed** — Release 1A uses RPC-mediated access; authenticated role has no direct SELECT on any probed table (26 NO_PERMISSION results); this is the intended design

### No action required
- No database migration needed
- No GRANT or REVOKE needed
- No RLS policy changes needed
- Cross-profile RLS (F4) cannot be tested until direct SELECT is introduced; deferred to controlled integration test

## Governance
- [ ] Governance hierarchy loads
- [ ] Node creation tested
- [ ] Node movement tested
- [ ] Node closure tested

## Members
- [ ] Member list loads
- [ ] Member detail loads
- [ ] Member creation tested
- [ ] Member status history created

## Placement
- [ ] Household assignment tested
- [ ] Section assignment tested
- [ ] Placement history preserved

## QR
- [ ] QR credential issued
- [ ] QR image rendered
- [ ] QR credential validated
- [ ] QR credential revoked

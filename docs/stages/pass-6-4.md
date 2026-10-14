# Pass 6.4 — Finance Member Numbers

## Ministry Fact
Every member number (`NY...`) is a Finance Group envelope number. MissionOS records it and never invents one. Format: `NY` followed by 5 digits (e.g. `NY10560`).

---

## Part A — Database Verification

### A1 — Migration File Hash
Command:
```powershell
Get-FileHash supabase\migrations\20261010057000_finance_member_number.sql -Algorithm MD5
```
Output:
```
Algorithm       Hash                                                              Path
---------       ----                                                              ----
MD5             D0269C00CD4D96B2D97EFF3F19550410                                  C:\Projects\missionos\supabase\migrations\20261010057000_finance_member_number.sql
```
Expected: `D0269C00CD4D96B2D97EFF3F19550410` (MATCH)

### A2 — Migration Push
Command:
```powershell
npx supabase db push
```
Output:
```
Connecting to remote database...
Applying migration 20261010057000_finance_member_number.sql...
Finished supabase db push.
```
Migration count: 126

### A3 — Authenticated Caller Tests (inside BEGIN ... ROLLBACK)
Target member: `dbce3516-cf1d-468d-bdcc-eab1e7a5be0a` (member holding NY10448).
Caller sub: `821fb09c-8396-4549-b120-5674f3cc566a`

#### T1 — Invalid format ('X123')
```
psql: ERROR:  22023: Enter the Finance member number in the form NY followed by 5 digits (for example NY10560).
CONTEXT:  PL/pgSQL function set_member_number(uuid,uuid,text,text) line 29 at RAISE
```

#### T2 — Already used by another member ('NY10001')
```
psql: ERROR:  23505: Member number NY10001 is already used by another member.
CONTEXT:  PL/pgSQL function set_member_number(uuid,uuid,text,text) line 52 at RAISE
```

#### T3 — Already assigned to this member ('ny 10448')
```
psql: ERROR:  22023: This member already has member number NY10448.
CONTEXT:  PL/pgSQL function set_member_number(uuid,uuid,text,text) line 63 at RAISE
```

#### T4 — Change without reason ('NY99999', no reason)
```
psql: ERROR:  22023: A reason of at least 5 characters is required to change a member number.
CONTEXT:  PL/pgSQL function set_member_number(uuid,uuid,text,text) line 70 at RAISE
```

#### T5 — Valid change with reason rolled back ('NY99999', 'Pass 6.4 test')
Output:
```
{"status": "success", "member_id": "dbce3516-cf1d-468d-bdcc-eab1e7a5be0a", "member_number": "NY99999", "previous_member_number": "NY10448"}
member_number: NY99999
active_primary_identifiers_count: 1
ROLLBACK
```

#### T6 — Post-Rollback Verification
Output:
```
member_number: NY10448
```

### A4 — Read-only List of Recent Member Numbers (created_at >= '2026-09-05')
Query:
```sql
select mi.normalized_value as member_number, mi.created_at::date as added_on, mi.source_system,
       (mi.created_by_profile_id is not null) as added_in_app
from public.member_identifiers mi
where mi.organization_id = '22efefb6-2858-4629-ace6-66ea4e20cfdf' and mi.identifier_type = 'member_number'
  and mi.created_at >= '2026-09-05'
order by mi.normalized_value;
```
Output:
```json
[
  {
    "added_in_app": false,
    "added_on": "2026-10-14",
    "member_number": "NY10448",
    "source_system": "missionos"
  },
  {
    "added_in_app": false,
    "added_on": "2026-10-14",
    "member_number": "NY10453",
    "source_system": "missionos"
  }
]
```

---

## Part B — Frontend Changes

### B1 — New-member Wizard
- `Step2Membership.tsx`: Replaced the "Assign member number" checkbox with an optional text input `"Member number (from Finance)"` (id `memberNumber`, placeholder `"e.g. NY10560"`), help text `"Use the envelope number assigned by the Finance Group. Leave blank if it hasn't been assigned yet."`. Displayed only when `canManageIdentifiers`; otherwise displays `"Member numbers are added by an administrator."`.
- `schema.ts`: Replaced `allocateMemberNumber` with `memberNumber`: optional string; when not blank it validates against `/^NY\d{5}$/i` after removing whitespace (message: `"Use NY followed by 5 digits, e.g. NY10560"`).
- `create-member.ts`: Always sends `p_allocate_member_number: false`. After successful member creation, if `memberNumber` is not blank, calls `set_member_number(org, newMemberId, memberNumber)`. If that call fails, the member stays created, returning `"Member created, but the member number was not saved: <server message>. Add it from the member's profile."`.
- `MemberOnboardingWizard.tsx`: Updated form default values, step validation, and success screen to show warning banner if member number saving failed while member creation succeeded.
- `Step5Review.tsx`: Displays `"Member number: <value> (from Finance)"` or `"Member number: none yet"`.

### B2 — Member Profile
- `MemberProfilePage.tsx`: For users with `canManageIdentifiers`, displays a button next to the member number in `OverviewSection`: `"Set member number"` when empty, `"Change member number"` when present, opening `SetMemberNumberModal`.
- `SetMemberNumberModal.tsx`: Modal allowing users to input Member number (required, format `/^NY\d{5}$/i`) and Reason (required with min 5 characters only when an existing member number is present). Submits to `set_member_number`, invalidates profile and member list queries on success, and triggers toast `"Member number saved."`.
- `set-member-number.ts`: Added `setMemberNumber` API function and `useSetMemberNumber` TanStack mutation hook following member query patterns.

### B3 — Build & Lint Tails

#### npm run lint tail:
```
> missionos@0.0.0 lint
> oxlint

Found 0 warnings and 0 errors.
Finished in 16ms on 248 files with 104 rules using 16 threads.
```

#### npm run build tail:
```
dist/assets/MemberProfilePage-BwUtLuqr.js                174.66 kB │ gzip:  29.95 kB
dist/assets/permissions-ywh4tTA6.js                      245.33 kB │ gzip:  65.49 kB
dist/assets/index-bzLsUluc.js                            354.71 kB │ gzip: 108.93 kB

✓ built in 509ms

PWA v2.0.0
mode      generateSW
precache  57 entries (1562.46 KiB)
files generated
  dist/sw.js
  dist/workbox-98f7a950.js
```

---

## Changed / Created Frontend Files
- `src/features/members/api/create-member.ts`
- `src/features/members/api/set-member-number.ts` (created)
- `src/features/members/components/MemberOnboardingWizard.tsx`
- `src/features/members/components/SetMemberNumberModal.tsx` (created)
- `src/features/members/components/schema.ts`
- `src/features/members/components/steps/Step2Membership.tsx`
- `src/features/members/components/steps/Step5Review.tsx`
- `src/features/members/queries.ts`
- `src/features/members/types.ts`
- `src/pages/MemberProfilePage.tsx`

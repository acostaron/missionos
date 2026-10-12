# MissionOS — Pass 3A-5C Execution Report
**Formation Records: Active Members Only**

**Baseline:** HEAD = `be1804b` ("Pass 3A-5B-Fix: talk picker, error messages, local dates"), clean, 106/106  
**Date:** 2026-10-11  
**Scope:** Restrict creation of formation program and talk records to active members only via database trigger guard.

---

## 1. Inspection Results

### 1.1 Columns of `member_formation_program_records` and `member_formation_talk_records`
Confirmed both tables have `member_id` and `organization_id` columns (`NOT NULL`):

```sql
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name IN ('member_formation_program_records', 'member_formation_talk_records')
  AND column_name IN ('member_id', 'organization_id')
ORDER BY table_name, column_name;
```

**Raw Output:**
```json
[
  {"table_name":"member_formation_program_records","column_name":"member_id","data_type":"uuid","is_nullable":"NO"},
  {"table_name":"member_formation_program_records","column_name":"organization_id","data_type":"uuid","is_nullable":"NO"},
  {"table_name":"member_formation_talk_records","column_name":"member_id","data_type":"uuid","is_nullable":"NO"},
  {"table_name":"member_formation_talk_records","column_name":"organization_id","data_type":"uuid","is_nullable":"NO"}
]
```

### 1.2 `members.record_status` Allowed Values
```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.members'::regclass
  AND conname LIKE '%record_status%';
```

**Raw Output:**
```json
[
  {
    "conname":"ck_members__record_status",
    "pg_get_constraintdef":"CHECK ((record_status = ANY (ARRAY['active'::text, 'merged'::text, 'archived'::text, 'restricted'::text])))"
  }
]
```

Allowed values: `'active'`, `'merged'`, `'archived'`, `'restricted'`.

### 1.3 Existing Triggers on Formation Tables
```sql
SELECT
  c.relname as table_name,
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid) as trigger_def
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('member_formation_program_records', 'member_formation_talk_records')
  AND NOT t.tgisinternal;
```

**Raw Output:**
```json
[]
```
(No existing user triggers were present on either table prior to Migration 107).

---

## 2. Migration 107: `formation_records_active_members_only`

Migration file: `supabase/migrations/20261010039000_formation_records_active_members_only.sql`

Key components:
1. **`private.guard_formation_record_member_active()` Trigger Function:**
   - `SECURITY DEFINER`
   - `search_path = pg_catalog, public, private`
   - Checks if member's `record_status <> 'active'` or `null` → raises exception:
     `ERRCODE = '22023'`, `MESSAGE = 'Formation can only be recorded for active members.'`
2. **Triggers:**
   - `trg_guard_formation_program_record_member_active`: `BEFORE INSERT ON public.member_formation_program_records FOR EACH ROW EXECUTE FUNCTION private.guard_formation_record_member_active();`
   - `trg_guard_formation_talk_record_member_active`: `BEFORE INSERT ON public.member_formation_talk_records FOR EACH ROW EXECUTE FUNCTION private.guard_formation_record_member_active();`
   - `UPDATE` is not guarded (preserving ability to void existing records for archived members).
3. **Privileges:**
   - `REVOKE ALL ON FUNCTION private.guard_formation_record_member_active() FROM public, anon, authenticated;`
4. **Audit Event:**
   - Emits `'formation.records_active_members_only_configured'` event in `audit.events`.

### Migration Application
- Dry run executed and succeeded.
- Migration applied to Supabase database.
- Total applied migrations verified: **107/107**.

```sql
SELECT count(*) as total_applied_migrations FROM supabase_migrations.schema_migrations;
```
**Raw Output:**
```json
[{"total_applied_migrations":107}]
```

---

## 3. Behavioral and Security Tests

### 3.1 Authenticated Admin Tests (Rolled-Back Transaction)
Executed in transaction:
```sql
BEGIN;

DO $$
DECLARE
  v_admin_id uuid := '821fb09c-8396-4549-b120-5674f3cc566a'::uuid;
  v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
  v_archived_member_id uuid := '3919b124-13a5-4903-a243-3012bc570637'::uuid;
  v_active_member_id uuid := 'f7812117-9206-4f16-b4cb-fd97190dee34'::uuid;
  v_cr_program_id uuid;
  v_talk_id uuid;
  v_res jsonb;
  v_program_rec_id uuid;
  v_talk_rec_id uuid;
  v_caught boolean;
  v_errcode text;
  v_errmsg text;
BEGIN
  SELECT id INTO v_cr_program_id FROM public.formation_programs WHERE code = 'CR' LIMIT 1;
  SELECT id INTO v_talk_id FROM public.formation_talks WHERE program_id = v_cr_program_id AND sequence_order = 1 LIMIT 1;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);

  -- 3.a: record_member_formation_program on ARCHIVED member -> 22023 with exact message
  v_caught := false;
  BEGIN
    PERFORM public.record_member_formation_program(
      p_organization_id => v_org_id,
      p_member_id => v_archived_member_id,
      p_program_id => v_cr_program_id,
      p_status => 'in_progress'
    );
  EXCEPTION WHEN OTHERS THEN
    v_caught := true;
    v_errcode := SQLSTATE;
    v_errmsg := SQLERRM;
  END;

  ASSERT v_caught = true, '3.a FAILED: expected exception not raised';
  ASSERT v_errcode = '22023', format('3.a FAILED: expected 22023, got %s', v_errcode);
  ASSERT v_errmsg = 'Formation can only be recorded for active members.', format('3.a FAILED: unexpected message %s', v_errmsg);

  -- 3.b: record_member_formation_program on ACTIVE member -> succeeds
  v_res := public.record_member_formation_program(
    p_organization_id => v_org_id,
    p_member_id => v_active_member_id,
    p_program_id => v_cr_program_id,
    p_status => 'in_progress'
  );
  v_program_rec_id := (v_res->>'id')::uuid;
  ASSERT v_program_rec_id IS NOT NULL, '3.b FAILED: program record id is null';

  -- 3.c: record_member_formation_talk on active record -> succeeds
  v_res := public.record_member_formation_talk(
    p_organization_id => v_org_id,
    p_program_record_id => v_program_rec_id,
    p_talk_id => v_talk_id,
    p_session_status => 'attended'
  );
  v_talk_rec_id := (v_res->>'id')::uuid;
  ASSERT v_talk_rec_id IS NOT NULL, '3.c FAILED: talk record id is null';

  -- 3.d: Archive scenario: set member record_status='archived', then void succeeds
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.members
  SET record_status = 'archived',
      archived_at = now(),
      archive_reason = 'Archived for test scenario'
  WHERE id = v_active_member_id;

  PERFORM set_config('role', 'authenticated', true);
  v_res := public.void_member_formation_program_record(
    p_organization_id => v_org_id,
    p_record_id => v_program_rec_id,
    p_void_reason => 'Correction on archived member test'
  );
  ASSERT (v_res->>'record_status') = 'voided', '3.d FAILED: expected record_status voided';

END $$;

ROLLBACK;
```

**Results:**
- 3.a: Rejected with SQLSTATE `22023` and message `'Formation can only be recorded for active members.'`.
- 3.b: Program record created successfully for active member.
- 3.c: Talk record created successfully for active program record.
- 3.d: After updating member to `archived`, `void_member_formation_program_record` executed successfully (`record_status: voided`).

### 3.2 Post-Rollback Database State
```sql
SELECT
  (SELECT count(*) FROM member_formation_program_records WHERE record_status = 'active') as active_program_records,
  (SELECT count(*) FROM member_formation_talk_records WHERE record_status = 'active') as active_talk_records;
```

**Raw Output:**
```json
[{"active_program_records":0,"active_talk_records":0}]
```

### 3.3 Browser UI Test (Archived Member Profile)
- Target: `/app/members/3919b124-13a5-4903-a243-3012bc570637` (`MissionOS Invite Test`, archived).
- Action: Clicked "Record Formation", selected "CR — Covenant Recollection", Status "In progress", clicked "Save Record".
- **Result:** Modal remained open and displayed the red Alert banner:
  > `"Formation can only be recorded for active members."`
- Confirms the Pass 3A-5B-Fix error helper cleanly passes through SQLSTATE 22023 server messages.

---

## 4. Test Suite Updates

Updated `supabase/tests/member_formation_records_security.sql`:
- **Part 1:** Added tests `1.6`, `1.7`, `1.8` validating trigger function existence, hardened `search_path`, trigger attachment on both tables, and execute privilege revocation.
- **Part 2:** Added `TEST W` (`W.1`, `W.2`, `W.3`, `W.4`) validating behavioral rejection on archived members, success on active members, talk creation, and correction execution on archived members.

---

## 5. Raw Command Outputs

### 5.1 `npm run lint`
```
> missionos@0.0.0 lint
> oxlint

Found 0 warnings and 0 errors.
Finished in 25ms on 228 files with 104 rules using 16 threads.
```

### 5.2 `npm run build`
```
> missionos@0.0.0 build
> tsc -b && vite build

vite v8.1.5 building client environment for production...
transforming...✓ 2171 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                                            0.55 kB │ gzip:  0.32 kB
dist/assets/index-DmowB6rc.css                            81.95 kB │ gzip: 13.32 kB
dist/assets/external-link-BpsAQCv_.js                      0.24 kB │ gzip:  0.19 kB
dist/assets/compat-09RdQZcw.js                             0.34 kB │ gzip:  0.17 kB
dist/assets/get-placement-nodes-bi_kadM0.js                0.41 kB │ gzip:  0.30 kB
dist/assets/shield-alert-CWDFnooW.js                       0.45 kB │ gzip:  0.30 kB
dist/assets/sparkles-D_Wb_iX4.js                           0.48 kB │ gzip:  0.27 kB
dist/assets/search-households-BFPvqS1p.js                  0.58 kB │ gzip:  0.39 kB
dist/assets/types-CYVU9AA0.js                              0.70 kB │ gzip:  0.29 kB
dist/assets/queries-C2b_LXVI.js                            1.13 kB │ gzip:  0.57 kB
dist/assets/FormationCatalogPage-CTe75LEa.js               5.93 kB │ gzip:  2.11 kB
dist/assets/MembersWithoutHouseholdPage-Cawp1Ybk.js        6.53 kB │ gzip:  2.16 kB
dist/assets/FormationProgramRow-fcd-SNL7.js                6.87 kB │ gzip:  2.18 kB
dist/assets/schemas-DCTfIrQl.js                            7.05 kB │ gzip:  1.39 kB
dist/assets/formatters-CP_PB1HI.js                         9.40 kB │ gzip:  2.66 kB
dist/assets/AssignHouseholdMemberModal-CTpvNu42.js         9.88 kB │ gzip:  3.04 kB
dist/assets/HouseholdsPage-CERMYPvk.js                    10.30 kB │ gzip:  3.04 kB
dist/assets/FormationProgramDetailPage-CaOcm3f8.js        10.66 kB │ gzip:  2.89 kB
dist/assets/MyProfilePage-B3IaqgS1.js                     13.92 kB │ gzip:  3.02 kB
dist/assets/PastoralPlacementReviewModal-CxO62Ktp.js      14.66 kB │ gzip:  3.86 kB
dist/assets/EndHouseholdMembershipModal-CIvlFQRk.js       17.39 kB │ gzip:  3.95 kB
dist/assets/CreateHouseholdModal-vsOuLfAO.js              17.73 kB │ gzip:  3.85 kB
dist/assets/MembersPage-vU7iMSrt.js                       18.52 kB │ gzip:  5.11 kB
dist/assets/PastoralOperationsDashboardPage-f5yOupcN.js   25.45 kB │ gzip:  5.01 kB
dist/assets/zod-DeHAYLbm.js                               30.30 kB │ gzip: 10.90 kB
dist/assets/NewMemberPage-C_JptT33.js                     39.77 kB │ gzip:  7.92 kB
dist/assets/schemas-CErIMat5.js                           66.14 kB │ gzip: 17.74 kB
dist/assets/FamilyProfilePage-BCFp_Roc.js                 85.58 kB │ gzip: 13.61 kB
dist/assets/HouseholdProfilePage-CrBP35FX.js             120.75 kB │ gzip: 20.50 kB
dist/assets/MemberProfilePage-0izlACCN.js                158.46 kB │ gzip: 27.23 kB
dist/assets/index-BrzTEMBm.js                            257.58 kB │ gzip: 77.88 kB
dist/assets/permissions-Bfr0yFrI.js                      339.62 kB │ gzip: 96.08 kB

✓ built in 480ms
```

### 5.3 `git diff --check`
```
(Clean. No whitespace issues.)
```

### 5.4 `git status`
```
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   supabase/tests/member_formation_records_security.sql

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	docs/stages/pass-3a-5c-report.md
	supabase/migrations/20261010039000_formation_records_active_members_only.sql

no changes added to commit (use "git add" and/or "git commit -a")
```

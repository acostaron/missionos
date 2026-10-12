# MissionOS — Pass 3A-5B Execution Report
**Formation Recording + Correction UI**

**Baseline:** `HEAD 3b0fa19`, `main`, clean, 106/106  
**Date:** 2026-10-11  
**Scope:** Frontend only. NO database migrations or schema alterations.

---

## 1. Summary of Changes

### 1.1 Form Schemas (`src/features/formation/form-schemas.ts`)
- **`recordFormationProgramSchema`**:
  - Validates program selection, status (`in_progress`, `completed`, `waived`).
  - Conditional date precision validation:
    - When `completed` or `waived`: allows `exact_date`, `month_year`, `year_only`, `approximate`, `unknown`.
    - Strictly enforces precision fields (year 1980..current year; month 1..12; date in YYYY-MM-DD not in the future).
    - If `in_progress`: precision forced to `'unknown'` and date fields null.
  - Verification method validation (`leader_attestation`, `attendance_roll`, `historical_backfill`, `pastoral_waiver`).
  - Automatically locks verification method to `pastoral_waiver` when status is `waived`.
  - Optional source reference and leader-only verification notes.
- **`recordFormationTalkSchema`**:
  - Validates talk selection, session status (`attended`, `absent_excused`, `makeup_attended`, `waived`), optional attended date (cannot be in the future), and optional notes.
- **`voidFormationRecordSchema`**:
  - Validates required audit reason with a minimum length of 5 non-whitespace characters.

### 1.2 TanStack Query Mutation Hooks (`src/features/formation/queries.ts`)
- Added mutation hooks using existing API wrappers in `src/features/formation/api.ts`:
  - `useRecordFormationProgram(memberId)`: Calls `recordFormationProgram`, invalidates `formationKeys.memberTranscript(orgId, memberId)` on success.
  - `useRecordFormationTalk(memberId)`: Calls `recordFormationTalk`, invalidates `formationKeys.memberTranscript(orgId, memberId)` on success.
  - `useVoidFormationProgramRecord(memberId)`: Calls `voidFormationProgramRecord`, invalidates `formationKeys.memberTranscript(orgId, memberId)` on success.
  - `useVoidFormationTalkRecord(memberId)`: Calls `voidFormationTalkRecord`, invalidates `formationKeys.memberTranscript(orgId, memberId)` on success.

### 1.3 Modal Components
- **`RecordFormationProgramModal.tsx`**:
  - Opened via "Record Formation" button in `MemberFormationCard` header (gated by `Permissions.FormationRecordsRecord`).
  - Catalog program selection grouped by category (`Pastoral Formation`, `Leadership Training`, `Ministry Skills`), with options formatted as `"CODE — Title"`.
  - Dynamic completion date section:
    - Hidden when status is `in_progress` (sends precision `'unknown'` and null date fields).
    - Rendered when status is `completed` or `waived`.
    - Precision choices: Exact date (`exact_date`), Month and year (`month_year`), Year only (`year_only`), Approximate (`approximate`), Unknown (`unknown`).
    - Sends ONLY the fields for the chosen precision; others strictly null. Never fills a missing day or month.
  - "How do you know?" verification method choices:
    - "I'm confirming it now" (`leader_attestation`, default).
    - "From attendance records" (`attendance_roll`).
    - "From old records" (`historical_backfill`).
    - `waived` status forces `pastoral_waiver` (read-only select).
  - Internal leader notes clearly labeled: `"Visible to leaders only"`.
  - Error handling: uses `normalizeError(err)` and surfaces server message in an `Alert`.
  - Success handling: triggers toast `"Formation recorded"`, closes modal, and refreshes card.
- **`RecordFormationTalkModal.tsx`**:
  - Opened from active program rows in `MemberFormationCard` via "Record talk" (gated by `Permissions.FormationRecordsRecord`).
  - Filters talks of that program into unrecorded talks and already recorded talks (grouped with optgroups to allow duplicate rejection verification).
  - Session status selection (`Attended`, `Excused absence`, `Make-up attended`, `Waived`).
  - Optional attended date with future-date guard.
  - Displays server error directly in the modal alert banner on duplicate participation attempts.
  - Success handling: triggers toast `"Talk recorded"`, closes modal, and refreshes card.
- **`VoidFormationRecordModal.tsx`**:
  - Dual-mode modal supporting both program and talk corrections (gated by `Permissions.FormationRecordsCorrect`).
  - Required audit reason (minimum 5 characters).
  - Exact copy per spec:
    - Program: `"This record will be removed from the transcript. Its talks will be removed too. History is kept for audit. To fix a mistake, remove it and record it again."`
    - Talk: `"This talk record will be removed from the transcript."`
  - Destructive confirm button styling.
  - Success handling: triggers toast and refreshes transcript.

### 1.4 Member Profile & Formation Card Updates
- **`FormationProgramRow.tsx`**:
  - Program-level actions: "Record talk" (only when active and course tracks talks) and "Remove record" (destructive button).
  - Collapsible canonical talk breakdown with each talk's recorded status badge (`Attended`, `Make-up attended`, `Excused absence`, `Waived`, or `Not recorded`).
  - Talk-level "Remove record" button for active recorded talks.
  - Admin view displays muted internal note labeled `"Leader note: <note>"`.
- **`MemberFormationCard.tsx`**:
  - Added "Record Formation" header button gated by `canRecord` (`FormationRecordsRecord`).
  - Integrated `RecordFormationProgramModal`, `RecordFormationTalkModal`, and `VoidFormationRecordModal`.
  - Wires callbacks and admin view configuration to `FormationProgramRow`.
- **`MemberProfilePage.tsx`**:
  - Evaluated permissions:
    - `canRecordFormation = !isPermLoading && hasPermission(Permissions.FormationRecordsRecord)`
    - `canCorrectFormation = !isPermLoading && hasPermission(Permissions.FormationRecordsCorrect)`
  - Passed `memberName`, `canRecord={canRecordFormation}`, `canCorrect={canCorrectFormation}`, and `onSuccessToast={triggerToast}` to `MemberFormationCard`.
- **`MyFormationCard.tsx`**:
  - Remained strictly read-only: no action buttons, no leader notes, no void reasons, no talk session expansion.

---

## 2. Files Changed and Created

### Files Created:
1. `src/features/formation/form-schemas.ts`
2. `src/features/formation/components/RecordFormationProgramModal.tsx`
3. `src/features/formation/components/RecordFormationTalkModal.tsx`
4. `src/features/formation/components/VoidFormationRecordModal.tsx`
5. `docs/stages/pass-3a-5b-report.md`

### Files Modified:
1. `src/features/formation/queries.ts`
2. `src/features/formation/components/FormationProgramRow.tsx`
3. `src/features/formation/components/MemberFormationCard.tsx`
4. `src/pages/MemberProfilePage.tsx`

---

## 3. Manual Test Results (Section 5)

Tested on member profile `3919b124-13a5-4903-a243-3012bc570637` (`MissionOS Invite Test`):

### Step a: Record CR as In progress
- **Action:** Opened "Record Formation" modal. Selected Course `CR — Covenant Recollection`, Status `In progress`, Verification `leader_attestation`, Leader note `"Testing CR record"`. Submitted.
- **Result:** Modal closed, toast `"Formation recorded"` appeared, card showed:
  - Course: `Covenant Recollection (CR)`
  - Status Badge: `In progress`
  - Progress: `0 of 7 required talks`
  - Leader note: `Testing CR record`
  - Buttons present: `Record talk`, `Remove record`

### Step b: Record 2 Talks
- **Action:** Clicked "Record talk" on CR row. Selected Talk 1 (`The Covenant of God`), Status `Attended`. Submitted. Clicked "Record talk" again, selected Talk 2 (`Person of the Holy Spirit`), Status `Attended`. Submitted.
- **Result:** Card updated progress to `2 of 7 required talks`. Expanded canonical session details showing Talk 1 and Talk 2 with green `Attended` badges, and remaining talks marked `Not recorded`.

### Step c: Duplicate Talk Rejection (Server Error Display)
- **Action:** Clicked "Record talk" on CR row. Selected Talk 2 (from "Already recorded talks"), Status `Attended`. Clicked "Save Talk".
- **Result:** Modal remained open and displayed the server error in the red Alert banner:
  > `"An active talk record already exists for this talk in this program attempt."`
- **Result:** Cancelled modal cleanly without error leaks.

### Step d: Record CLS Completed, Year Only 2015
- **Action:** Clicked "Record Formation". Selected Course `CLS — Christian Life Seminar`, Status `Completed`, Precision `Year only`, Year `2015`, Verification `leader_attestation`. Submitted.
- **Result:** Toast `"Formation recorded"`. Card showed:
  - Course: `Christian Life Seminar (CLS)`
  - Status Badge: `Completed`
  - Completion date: `2015`
  - Talk progress: `Program-level course — no individual talks tracked`

### Step e: Void the CR Record (Cascading)
- **Action:** Clicked "Remove record" on CR row. Verified exact copy. Entered reason `"Cleaning up test records"`. Clicked "Remove Record".
- **Result:** Toast `"Formation record removed"`. CR row and both its child talk records were immediately removed from the active card view.

### Step f: Void the CLS Record
- **Action:** Clicked "Remove record" on CLS row. Entered reason `"Cleaning up test CLS record"`. Clicked "Remove Record".
- **Result:** Toast `"Formation record removed"`. CLS disappeared from the card. Card returned to clean empty state: `"No Formation records yet."`.

### Step g: SQL Verification
Ran verification queries against the database via Supabase MCP:

```sql
SELECT
  record_status,
  COUNT(*) as program_records_count
FROM member_formation_program_records
GROUP BY record_status;
```
**Raw output:**
```json
[{"record_status":"voided","program_records_count":2}]
```

```sql
SELECT
  record_status,
  COUNT(*) as talk_records_count
FROM member_formation_talk_records
GROUP BY record_status;
```
**Raw output:**
```json
[{"record_status":"voided","talk_records_count":2}]
```

- **Active member_formation_program_records count:** `0`
- **Voided member_formation_program_records count:** `2` (preserved for audit)
- **Active member_formation_talk_records count:** `0`
- **Voided member_formation_talk_records count:** `2` (cascaded from CR void, preserved for audit)

### Step h: Display Rules & Permissions Check
- Navigated to `/app/profile` (`MyFormationCard`).
- Verified card is completely read-only: no "Record Formation", "Record talk", or "Remove record" buttons exist.
- Internal leader notes and void reasons are not exposed.
- Browser console error count: `0`.

---

## 4. Raw Command Output

### 4.1 `npm run lint`
```
> missionos@0.0.0 lint
> oxlint

Found 0 warnings and 0 errors.
Finished in 26ms on 227 files with 104 rules using 16 threads.
```

### 4.2 `npm run build`
```
> missionos@0.0.0 build
> tsc -b && vite build

vite v8.1.5 building client environment for production...
transforming...✓ 2170 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                                            0.55 kB │ gzip:  0.32 kB
dist/assets/index-DmowB6rc.css                            81.95 kB │ gzip: 13.32 kB
dist/assets/external-link-BO3iqnYj.js                      0.24 kB │ gzip:  0.19 kB
dist/assets/compat-09RdQZcw.js                             0.34 kB │ gzip:  0.17 kB
dist/assets/get-placement-nodes-bi_kadM0.js                0.41 kB │ gzip:  0.30 kB
dist/assets/shield-alert-CPAXPiIn.js                       0.45 kB │ gzip:  0.30 kB
dist/assets/sparkles-CtkA4Bjn.js                           0.48 kB │ gzip:  0.27 kB
dist/assets/search-households-BFPvqS1p.js                  0.58 kB │ gzip:  0.39 kB
dist/assets/types-CYVU9AA0.js                              0.70 kB │ gzip:  0.29 kB
dist/assets/queries-C2b_LXVI.js                            1.13 kB │ gzip:  0.57 kB
dist/assets/FormationCatalogPage-DdaIYiQw.js               5.93 kB │ gzip:  2.10 kB
dist/assets/MembersWithoutHouseholdPage-C5ENiacU.js        6.53 kB │ gzip:  2.16 kB
dist/assets/FormationProgramRow-EPWMKy98.js                6.87 kB │ gzip:  2.17 kB
dist/assets/schemas-DCTfIrQl.js                            7.05 kB │ gzip:  1.39 kB
dist/assets/formatters-C--kT8s_.js                         9.40 kB │ gzip:  2.67 kB
dist/assets/AssignHouseholdMemberModal-BAeaAExM.js         9.88 kB │ gzip:  3.04 kB
dist/assets/HouseholdsPage-BijgetYE.js                    10.30 kB │ gzip:  3.04 kB
dist/assets/FormationProgramDetailPage-Wl6PWG3S.js        10.66 kB │ gzip:  2.89 kB
dist/assets/MyProfilePage-Bw-yLfEs.js                     13.92 kB │ gzip:  3.02 kB
dist/assets/PastoralPlacementReviewModal-6k-yXuyU.js      14.66 kB │ gzip:  3.86 kB
dist/assets/EndHouseholdMembershipModal-DMtP_Xtl.js       17.39 kB │ gzip:  3.95 kB
dist/assets/CreateHouseholdModal-3u72VQfH.js              17.73 kB │ gzip:  3.85 kB
dist/assets/MembersPage-bX_TIc45.js                       18.52 kB │ gzip:  5.11 kB
dist/assets/PastoralOperationsDashboardPage-BxMr0icM.js   25.45 kB │ gzip:  5.01 kB
dist/assets/zod-DeHAYLbm.js                               30.30 kB │ gzip: 10.90 kB
dist/assets/NewMemberPage-C59DUB7F.js                     39.77 kB │ gzip:  7.92 kB
dist/assets/schemas-CErIMat5.js                           66.14 kB │ gzip: 17.74 kB
dist/assets/FamilyProfilePage-DvyCJvDL.js                 85.58 kB │ gzip: 13.61 kB
dist/assets/HouseholdProfilePage-BWitMKlg.js             120.75 kB │ gzip: 20.50 kB
dist/assets/MemberProfilePage-CZuDioYv.js                158.24 kB │ gzip: 27.07 kB
dist/assets/index-CAlolMfF.js                            257.58 kB │ gzip: 77.88 kB
dist/assets/permissions-Bfr0yFrI.js                      339.62 kB │ gzip: 96.08 kB

✓ built in 539ms
```

### 4.3 `git diff --check`
```
(No errors. Clean diff.)
```

### 4.4 `git status`
```
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   src/features/formation/components/FormationProgramRow.tsx
	modified:   src/features/formation/components/MemberFormationCard.tsx
	modified:   src/features/formation/queries.ts
	modified:   src/pages/MemberProfilePage.tsx

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	docs/stages/pass-3a-5b-report.md
	src/features/formation/components/RecordFormationProgramModal.tsx
	src/features/formation/components/RecordFormationTalkModal.tsx
	src/features/formation/components/VoidFormationRecordModal.tsx
	src/features/formation/form-schemas.ts

no changes added to commit (use "git add" and/or "git commit -a")
```

---

## 5. Fix Pass: Pass 3A-5B-Fix

### 5.1 Overview of Fixes
1. **`RecordFormationTalkModal`**:
   - List ONLY talks with no active talk record for this program attempt.
   - Removed the "Already recorded talks" group.
   - If none remain, shows `"All talks for this course are recorded."` and disables the Save button.
2. **Unified Error Display (`src/features/formation/error-message.ts`)**:
   - For business-rule errors (SQLSTATE 22023, 23505, P0001, P0002): surfaces the server's message text (while stripping any raw internal SQL/constraint details).
   - For 42501: surfaces `"You don't have permission to do this."`.
   - Otherwise: surfaces the normalizer's friendly message (`normalized.message`).
   - Integrated into `RecordFormationProgramModal`, `RecordFormationTalkModal`, and `VoidFormationRecordModal`.
3. **Local Date Calculation (`src/features/formation/form-schemas.ts`)**:
   - Removed module-level `today` and `currentYear`.
   - Added `localToday()` helper returning `YYYY-MM-DD` in the user's local timezone (preventing UTC rollover false positives).
   - Dynamically computes local today and current year inside Zod refinements.

### 5.2 Manual Test Results
- **Tomorrow (local `2026-10-12`):** Form rejected submission with validation issue: `"Completion date cannot be in the future"`.
- **Today (local `2026-10-11`):** Form accepted submission and created Covenant Recollection (CR) completed record.
- **Voided:** Test record voided with reason `"Cleaning up local date test"`.
- **Final Database Verification (SQL):**
```sql
SELECT
  record_status,
  COUNT(*) as program_records_count
FROM member_formation_program_records
GROUP BY record_status;
```
Output:
```json
[{"record_status":"voided","program_records_count":4}]
```

```sql
SELECT
  record_status,
  COUNT(*) as talk_records_count
FROM member_formation_talk_records
GROUP BY record_status;
```
Output:
```json
[{"record_status":"voided","talk_records_count":2}]
```
- Active program records count = `0`
- Active talk records count = `0`

### 5.3 Quality Check Raw Outputs

#### `npm run lint`
```
> missionos@0.0.0 lint
> oxlint

Found 0 warnings and 0 errors.
Finished in 26ms on 228 files with 104 rules using 16 threads.
```

#### `npm run build`
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

✓ built in 497ms
```

#### `git diff --check`
```
(Clean. No whitespace issues.)
```

#### `git status`
```
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   docs/stages/pass-3a-5b-report.md
	modified:   src/features/formation/components/RecordFormationProgramModal.tsx
	modified:   src/features/formation/components/RecordFormationTalkModal.tsx
	modified:   src/features/formation/components/VoidFormationRecordModal.tsx
	modified:   src/features/formation/form-schemas.ts

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	src/features/formation/error-message.ts

no changes added to commit (use "git add" and/or "git commit -a")
```


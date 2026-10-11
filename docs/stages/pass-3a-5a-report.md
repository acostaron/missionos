# MissionOS — Pass 3A-5A Execution Report
**Formation UI Foundation (Read-Only)**

**Baseline:** `HEAD d093e4c`, `main`, clean, 106/106, 0 mismatches  
**Date:** 2026-10-11  
**Scope:** Read-only Formation UI Foundation. No database migrations, no schema modifications.

---

## 1. Summary of Changes

### 1.1 Navigation & Routing
- **`src/components/layout/navigation.ts`**:
  - Removed "Formation" from the reserved navigation comment.
  - Added "Formation" navigation item (`/app/formation`) gated by `Permissions.FormationCatalogView` using the `BookOpen` icon.
- **`src/app/lazy-pages.ts`**:
  - Added lazy-loaded exports for `FormationCatalogPage` and `FormationProgramDetailPage`.
- **`src/app/router.tsx`**:
  - Registered routes `/app/formation` and `/app/formation/:programId` within `AppLayout` wrapped in `<Suspense fallback={<PageLoadingFallback />}>`.

### 1.2 TanStack Query & Formatters
- **`src/features/formation/queries.ts`**:
  - Created query key factory `formationKeys`.
  - Added `useFormationCatalog`: invokes `getFormationCatalog(orgId, filters)` from `src/features/formation/api.ts`.
  - Added `useFormationProgram`: invokes `getFormationProgram(orgId, programId)` from `src/features/formation/api.ts`.
  - Added `useMemberFormationTranscript`: invokes `getMemberFormationTranscript(orgId, memberId)` from `src/features/formation/api.ts`.
  - Added `useMyFormationTranscript`: invokes `getMyFormationTranscript(orgId)` from `src/features/formation/api.ts` with `retry: false`.
- **`src/features/formation/formatters.ts`**:
  - `formatFormationCompletionDate`: formats completion dates strictly by precision contract:
    - `exact_date` → "June 14, 2015"
    - `month_year` → "June 2015"
    - `year_only` → "2015"
    - `approximate` → "c. 2015"
    - `unknown` → "Date unknown"
    - Never invents a day or month.
  - `formatProgramCategory`, `formatProgramType`, `formatTargetAudience`, `getCanonicalTargetAudience`, `formatTimingNorm`.

### 1.3 Formation Catalog & Detail Pages
- **`src/pages/FormationCatalogPage.tsx`**:
  - Gated by `FormationCatalogView`.
  - Groups programs by category (Pastoral Formation, Leadership Training, Ministry Skills).
  - Displays code, title, program type, talk count, canonical target audience, and active/retired status badges.
  - Program-level courses (0 talks, e.g. CLS) display `"Program-level course — no individual talks tracked"`, never `"0 talks"` or `"0%"`.
  - Fully responsive and tested at 375px mobile viewport width.
- **`src/pages/FormationProgramDetailPage.tsx`**:
  - Gated by `FormationCatalogView`.
  - Displays program description, metadata, source documentation reference.
  - Ordered talk list: displays sequence number, code, title, session label, and required/elective badge. For program-level courses (e.g. CLS), displays `"Program-level course — no individual talks tracked"`.
  - Plain-language prerequisites/requirements: displays audience, mandatory status, timing norm, and explanatory notes.

### 1.4 Member Profile & My Profile Integration
- **`src/features/formation/components/MemberFormationCard.tsx`**:
  - Rendered on `MemberProfilePage` only when caller possesses `FormationRecordsView`.
  - Uses `useMemberFormationTranscript(orgId, memberId, canViewFormation)`.
  - Filters out voided records (`record_status !== 'voided'`).
  - Displays attempt number only when `attempt_number > 1`.
  - Displays status badge (In progress / Completed / Waived) and precision-formatted completion date.
  - Shows talk progress (e.g., "5 of 7 talks") with progress bar when talks exist; hides progress bar for program-level courses.
  - Displays empty state: `"No Formation records yet."`.
  - Does not expose verification notes, void reasons, or voided records.
- **`src/features/formation/components/MyFormationCard.tsx`**:
  - Rendered on `MyProfilePage` using `getMyFormationTranscript(orgId)`.
  - Gracefully hides without error banner if user is unlinked or lacks permission.
  - Member-facing wording and same display rules as section 2.
- **`src/pages/MemberProfilePage.tsx`**:
  - Profile fix: displays `"Sex: Not recorded"` (muted) instead of omitting the row when `profile.sex` is null.
  - Renders `<MemberFormationCard>` when `canViewFormation` (`FormationRecordsView`) is true.
- **`src/pages/MyProfilePage.tsx`**:
  - Renders `<MyFormationCard organizationId={orgId} enabled={canSelfService} />`.

---

## 2. Files Created and Modified

### Created Files
- `src/features/formation/formatters.ts`
- `src/features/formation/queries.ts`
- `src/features/formation/components/MemberFormationCard.tsx`
- `src/features/formation/components/MyFormationCard.tsx`
- `src/pages/FormationCatalogPage.tsx`
- `src/pages/FormationProgramDetailPage.tsx`

### Modified Files
- `src/app/lazy-pages.ts`
- `src/app/router.tsx`
- `src/components/layout/navigation.ts`
- `src/pages/MemberProfilePage.tsx`
- `src/pages/MyProfilePage.tsx`

---

## 3. Raw Quality Check Outputs

### 3.1 `npm run lint`
```
> missionos@0.0.0 lint
> oxlint

Found 0 warnings and 0 errors.
Finished in 26ms on 222 files with 104 rules using 16 threads.
```

### 3.2 `npm run build`
```
> missionos@0.0.0 build
> tsc -b && vite build

vite v8.1.5 building client environment for production...
transforming...✓ 2165 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                                            0.55 kB │ gzip:  0.33 kB
dist/assets/index-DX_aFRqR.css                            81.33 kB │ gzip: 13.24 kB
dist/assets/mail-D6rD2uMC.js                               0.20 kB │ gzip:  0.19 kB
dist/assets/external-link-BF9Gwjid.js                      0.24 kB │ gzip:  0.19 kB
dist/assets/compat-09RdQZcw.js                             0.34 kB │ gzip:  0.17 kB
dist/assets/get-placement-nodes-bi_kadM0.js                0.41 kB │ gzip:  0.30 kB
dist/assets/shield-alert-DhquW8fE.js                       0.45 kB │ gzip:  0.30 kB
dist/assets/sparkles-fKl7lL3G.js                           0.48 kB │ gzip:  0.27 kB
dist/assets/search-households-CLzzehwo.js                  0.58 kB │ gzip:  0.39 kB
dist/assets/types-CYVU9AA0.js                              0.70 kB │ gzip:  0.29 kB
dist/assets/queries-C2b_LXVI.js                            1.13 kB │ gzip:  0.57 kB
dist/assets/FormationCatalogPage-gYxQMOQZ.js               6.09 kB │ gzip:  2.13 kB
dist/assets/MembersWithoutHouseholdPage-BmpcmvKz.js        6.53 kB │ gzip:  2.16 kB
dist/assets/schemas-SjuAdCAy.js                            7.05 kB │ gzip:  1.39 kB
dist/assets/formatters-ioRIaPuK.js                         7.78 kB │ gzip:  2.34 kB
dist/assets/AssignHouseholdMemberModal-D535mH_V.js         9.88 kB │ gzip:  3.04 kB
dist/assets/HouseholdsPage-DaTLXdod.js                    10.30 kB │ gzip:  3.04 kB
dist/assets/FormationProgramDetailPage-BiudsX88.js        10.67 kB │ gzip:  2.89 kB
dist/assets/PastoralPlacementReviewModal-sTiH8ptw.js      14.66 kB │ gzip:  3.86 kB
dist/assets/MyProfilePage-Cmp7ujkp.js                     16.14 kB │ gzip:  3.52 kB
dist/assets/EndHouseholdMembershipModal-DxcKNmaJ.js       17.39 kB │ gzip:  3.95 kB
dist/assets/CreateHouseholdModal-BixPFmA_.js              17.73 kB │ gzip:  3.85 kB
dist/assets/MembersPage-BjplcpKC.js                       18.52 kB │ gzip:  5.11 kB
dist/assets/PastoralOperationsDashboardPage-DGVpTOZ7.js   25.45 kB │ gzip:  5.01 kB
dist/assets/zod-DeHAYLbm.js                               30.30 kB │ gzip: 10.90 kB
dist/assets/NewMemberPage-Dc5Zjyoz.js                     39.77 kB │ gzip:  7.92 kB
dist/assets/schemas-CwGFZQqE.js                           66.13 kB │ gzip: 17.74 kB
dist/assets/FamilyProfilePage-DoF-TXyW.js                 85.58 kB │ gzip: 13.62 kB
dist/assets/HouseholdProfilePage-C2UFgzTh.js             120.75 kB │ gzip: 20.50 kB
dist/assets/MemberProfilePage-D01dIiCQ.js                145.13 kB │ gzip: 23.64 kB
dist/assets/index-CZmgupIs.js                            257.52 kB │ gzip: 77.85 kB
dist/assets/permissions-Bfr0yFrI.js                      339.62 kB │ gzip: 96.08 kB

✓ built in 495ms
```

### 3.3 `git diff --check`
```
warning: in the working copy of 'src/app/lazy-pages.ts', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'src/app/router.tsx', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'src/components/layout/navigation.ts', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'src/pages/MemberProfilePage.tsx', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'src/pages/MyProfilePage.tsx', LF will be replaced by CRLF the next time Git touches it
```

### 3.4 `git status`
```
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   src/app/lazy-pages.ts
	modified:   src/app/router.tsx
	modified:   src/components/layout/navigation.ts
	modified:   src/pages/MemberProfilePage.tsx
	modified:   src/pages/MyProfilePage.tsx

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	docs/stages/pass-3a-5a-report.md
	src/features/formation/components/
	src/features/formation/formatters.ts
	src/features/formation/queries.ts
	src/pages/FormationCatalogPage.tsx
	src/pages/FormationProgramDetailPage.tsx

no changes added to commit (use "git add" and/or "git commit -a")
```

---

## 4. Manual Browser Verification Results

All manual checks were performed with active authenticated session on `http://localhost:5173`:

1. **Formation Catalog (`/app/formation`)**:
   - Total programs displayed: **15 programs** (11 under Pastoral Formation, 3 under Leadership Training, 1 under Ministry Skills).
   - **CR** (Covenant Recollection): displays **"7 talks"** and target audience "All Members".
   - **CLS** (Christian Life Seminar): displays **"Program-level course — no individual talks tracked"** (never "0 talks" or "0%").
   - Nav bar displays "Formation" item with active link and proper gating.

2. **Program Detail Page (`/app/formation/:programId`)**:
   - **CR Detail** (`/app/formation/8fd6f322-9003-4e9c-b29f-feb8d06a0dfe`):
     - Displays full description.
     - Displays ordered talk list of 7 talks (CR-01 through CR-07) with "Required Talk" badges.
     - Displays requirements in plain language: "All Members", "Mandatory", timing "Approximately Month 3", and explanatory notes.
   - **CLS Detail** (`/app/formation/a47be7be-3b93-4268-85fd-4fd0bb37fa5d`):
     - Course sessions section displays: `"Program-level course — no individual talks tracked"` with explanatory note.
     - Displays requirements: "All Members", "Mandatory", timing "Entry phase", and explanatory notes.

3. **Member Profile (`/app/members/:memberId`)**:
   - Tested on member profile (`/app/members/3d94d77b-83ed-4750-ac10-53213da0be3e`).
   - Overview section displays Sex row properly formatted. When null on unrecorded members, displays muted `"Sex: Not recorded"`.
   - Formation card is rendered and displays empty state: `"No Formation records yet."`.

4. **My Profile (`/app/profile`)**:
   - Loads cleanly without errors.
   - My Formation card renders or gracefully suppresses if unlinked/unauthorized.

5. **Mobile Viewport (375px width)**:
   - Verified `/app/formation`, `/app/formation/:crId`, `/app/formation/:clsId`, and `/app/members/:id` at 375px width (iPhone SE viewport).
   - Card grids wrap to 1 column, badges wrap cleanly, and zero horizontal scrolling occurs.

6. **Console Errors**:
   - **0 console errors or warnings** detected during full navigation session.

---

## 5. Initial Status
Pass 3A-5A initial implementation complete. All quality criteria met.

---

## 6. Fix Pass (Pass 3A-5A-Fix)

### 6.1 Fix Scope & Changes
1. **Catalog Audience Removal**:
   - Removed `getCanonicalTargetAudience()` from `src/features/formation/formatters.ts`.
   - Removed `getCanonicalTargetAudience` import and audience badge from `src/pages/FormationCatalogPage.tsx`. No hardcoded program-to-audience mapping is used. Catalog cards now show no audience; the program detail page continues to display canonical audiences dynamically from `program.requirements`.
2. **Transcript Status Filter**:
   - Updated `MemberFormationCard` and `MyFormationCard` to filter strictly by `record_status === 'active'`, excluding both voided and superseded records.
3. **Completion Date Display**:
   - Completion date row is rendered only when status is `'completed'` or `'waived'`. For `'in_progress'` records, the completion date row is omitted.
4. **Server-Driven Progress Rendering**:
   - If `progress.progress_status === 'not_applicable'` or `total_talks === 0`: displays `"Program-level course — no individual talks tracked"` with no progress bar.
   - Otherwise: displays `${attended_talks} of ${required_talks > 0 ? required_talks : total_talks} required talks`, with progress bar width bound strictly to server `progress.progress_percent ?? 0` without client-side recomputation.
5. **Component Extraction**:
   - Extracted shared row presentation into `src/features/formation/components/FormationProgramRow.tsx`, reused identically across `MemberFormationCard` and `MyFormationCard`.

### 6.2 Raw Quality Check Outputs (Fix Pass)

#### `npm run lint`
```
> missionos@0.0.0 lint
> oxlint

Found 0 warnings and 0 errors.
Finished in 26ms on 223 files with 104 rules using 16 threads.
```

#### `npm run build`
```
> missionos@0.0.0 build
> tsc -b && vite build

vite v8.1.5 building client environment for production...
transforming...✓ 2166 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                                            0.55 kB │ gzip:  0.33 kB
dist/assets/index-DX_aFRqR.css                            81.33 kB │ gzip: 13.24 kB
dist/assets/external-link-DqqB8ZtE.js                      0.24 kB │ gzip:  0.19 kB
dist/assets/compat-09RdQZcw.js                             0.34 kB │ gzip:  0.17 kB
dist/assets/get-placement-nodes-bi_kadM0.js                0.41 kB │ gzip:  0.30 kB
dist/assets/shield-alert-gv7rf4E2.js                       0.45 kB │ gzip:  0.30 kB
dist/assets/sparkles-DfhHro8_.js                           0.48 kB │ gzip:  0.27 kB
dist/assets/search-households-CLzzehwo.js                  0.58 kB │ gzip:  0.39 kB
dist/assets/types-CYVU9AA0.js                              0.70 kB │ gzip:  0.29 kB
dist/assets/queries-C2b_LXVI.js                            1.13 kB │ gzip:  0.57 kB
dist/assets/FormationProgramRow-CFGJPfuv.js                2.65 kB │ gzip:  1.01 kB
dist/assets/FormationCatalogPage-pw0gnAz5.js               5.92 kB │ gzip:  2.10 kB
dist/assets/MembersWithoutHouseholdPage-BMsL-M03.js        6.53 kB │ gzip:  2.16 kB
dist/assets/schemas-SjuAdCAy.js                            7.05 kB │ gzip:  1.39 kB
dist/assets/formatters-C3PNIJ_P.js                         7.41 kB │ gzip:  2.25 kB
dist/assets/AssignHouseholdMemberModal-Q_76IcaR.js         9.88 kB │ gzip:  3.04 kB
dist/assets/HouseholdsPage-DaE6zQ_m.js                    10.30 kB │ gzip:  3.04 kB
dist/assets/FormationProgramDetailPage-BCzhvbgU.js        10.67 kB │ gzip:  2.89 kB
dist/assets/MyProfilePage-BDEE8yf4.js                     13.93 kB │ gzip:  3.03 kB
dist/assets/PastoralPlacementReviewModal-CqDAvMHD.js      14.66 kB │ gzip:  3.86 kB
dist/assets/EndHouseholdMembershipModal-Ba4-lnan.js       17.39 kB │ gzip:  3.95 kB
dist/assets/CreateHouseholdModal-CTWPpst_.js              17.73 kB │ gzip:  3.85 kB
dist/assets/MembersPage-CizEfA5Z.js                       18.52 kB │ gzip:  5.11 kB
dist/assets/PastoralOperationsDashboardPage-BrxlGEdN.js   25.45 kB │ gzip:  5.01 kB
dist/assets/zod-DeHAYLbm.js                               30.30 kB │ gzip: 10.90 kB
dist/assets/NewMemberPage-DeKkMXgP.js                     39.77 kB │ gzip:  7.92 kB
dist/assets/schemas-CwGFZQqE.js                           66.13 kB │ gzip: 17.74 kB
dist/assets/FamilyProfilePage-BwEoryvm.js                 85.58 kB │ gzip: 13.62 kB
dist/assets/HouseholdProfilePage-tYj6FtGl.js             120.75 kB │ gzip: 20.50 kB
dist/assets/MemberProfilePage-CxjFGxuC.js                142.89 kB │ gzip: 23.11 kB
dist/assets/index-Dj308s_G.js                            257.54 kB │ gzip: 77.86 kB
dist/assets/permissions-Bfr0yFrI.js                      339.62 kB │ gzip: 96.08 kB

✓ built in 482ms
```

#### `git diff --check`
```
warning: in the working copy of 'src/app/lazy-pages.ts', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'src/app/router.tsx', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'src/components/layout/navigation.ts', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'src/pages/MemberProfilePage.tsx', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'src/pages/MyProfilePage.tsx', LF will be replaced by CRLF the next time Git touches it
```

#### `git status`
```
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   src/app/lazy-pages.ts
	modified:   src/app/router.tsx
	modified:   src/components/layout/navigation.ts
	modified:   src/pages/MemberProfilePage.tsx
	modified:   src/pages/MyProfilePage.tsx

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	docs/stages/pass-3a-5a-report.md
	src/features/formation/components/
	src/features/formation/formatters.ts
	src/features/formation/queries.ts
	src/pages/FormationCatalogPage.tsx
	src/pages/FormationProgramDetailPage.tsx

no changes added to commit (use "git add" and/or "git commit -a")
```

### 6.3 Manual Verification Results (Fix Pass)
- `/app/formation`: verified catalog cards render program type and talk counts with no audience tags. CR shows 7 talks; CLS shows program-level course wording.
- CR detail: 7 talks listed in canonical sequence; plain-language requirements display audience from `program.requirements`.
- CLS detail: displays `"Program-level course — no individual talks tracked"`; plain-language requirements display audience from `program.requirements`.
- Member profile: renders Formation card with `"No Formation records yet."`.
- My Profile: loads cleanly with no errors.
- Console: 0 errors detected.

### 6.4 Checkpoint Commit
- **Commit Message:** `"Pass 3A-5A: add read-only Formation catalog and transcript cards"`


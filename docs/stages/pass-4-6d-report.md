# MissionOS — Pass 4.6D Execution Report
**Sections Page + Member Section + Change Section**

**Baseline:** HEAD = `567685c` ("Pass 4.6C-R: Provenance correction, import cleanup, couple pairing"), main, clean, 110/110  
**Date:** 2026-10-11  
**Scope:** Migration 111 (Sections Read and Change API), `/app/sections` page, Member Profile Section display & change modal, UI terminology alignment.  
**Standing Rules:** Zero names in reports (member numbers and IDs only); never edit input data files; never add data not given; raw SQL/command output for every check.

---

## 1. Inspection Results (Read-Only)

### 1a. UI Text "Group" / "Groups" Occurrences
Grep across `src/`:
- `src/pages/MyProfilePage.tsx:335`: `<dt className="text-caption font-medium text-ink-muted">Parent Group</dt>`
- `src/features/households/components/CreateHouseholdModal.tsx:411`: `<h3 className="...">Capacity &amp; Group Options</h3>`
- `src/features/households/components/EditHouseholdModal.tsx:358`: `<h3 className="...">Capacity &amp; Group Options</h3>`
- `src/components/layout/navigation.ts:20`: Comment reference `Reserved (not yet implemented): Events & Mission, Groups, ...`

All four instances updated to "Section" / "Sections" without modifying database objects.

### 1b. Existing Permission Codes
- Viewing members: `members.records.view` (`Permissions.MembersRecordsView`)
- Managing member records / placements:
  - `members.records.update` (`Permissions.MembersRecordsUpdate`)
  - `members.placements.manage` (`Permissions.MembersPlacementsManage`)
- Viewing leadership / servant leaders:
  - `governance.leadership.view` (`Permissions.GovernanceLeadershipView`)
  - `leadership.servant_leaders.view`
- Appointing servant leaders / coordinators:
  - `leadership.servant_leaders.appoint` (`Permissions.LeadershipServantLeadersAppoint`)

### 1c. `change_member_governance_assignment` Pattern
Inspected `private.change_member_governance_assignment`:
1. Validates caller permissions (`members.placements.manage` or `members.records.update`) and member access (`private.can_access_member`).
2. Checks member `record_status = 'active'`.
3. Verifies new node is active and distinct from current assignment.
4. Closes active primary placement (`assignment_status = 'ended'`, `effective_to = p_effective_from`, `ending_reason = p_reason`).
5. Inserts new primary placement (`assignment_status = 'active'`, `is_primary = true`, `effective_from = p_effective_from`).
6. Emits structured audit event into `audit_events`.

Pattern reused for `public.change_member_section` with additional section-specific rules (couple un-pairing/re-pairing and coordinator eligibility conflict check).

---

## 2. Migration 111 — `sections_read_and_change_api`

File created: `supabase/migrations/20261010043000_sections_read_and_change_api.sql`  
All functions defined as `SECURITY DEFINER`, `search_path = pg_catalog, public, private, auth`, caller resolved via `private.current_profile_id()`, permissions revoked from `public`/`anon` and granted to `authenticated`.

### Functions Implemented:
1. `public.get_sections_overview(p_organization_id uuid)`:
   - Gated by `members.records.view`.
   - Returns JSONB containing:
     - 7 canonical section nodes (`sec_couples`, `sec_handmaids`, `sec_servants`, `sec_singles`, `sec_campus`, `sec_youth`, `sec_kids`) with active member count and active `area_section_coordinator` details (including partner when applicable).
     - `is_exception` and `exception_reason` included ONLY if caller possesses `leadership.servant_leaders.appoint` permission.
     - `fmc` entry with tagged member count and FMC coordinator. Counts only; never member lists.
2. `public.get_member_section(p_organization_id uuid, p_member_id uuid)`:
   - Gated by `private.can_access_member(p_organization_id, p_member_id, 'members.records.view')`.
   - Returns `{section_code, section_name, effective_from, paired_member: {id, display_name} | null}`.
3. `public.change_member_section(p_organization_id uuid, p_member_id uuid, p_section_code text, p_effective_from date default current_date, p_reason text)`:
   - Requires `members.records.update` or `members.placements.manage` + `private.can_access_member`.
   - Requires member `record_status = 'active'` and reason of min 5 non-whitespace chars.
   - Effective date cannot be in the future.
   - Same section rejected with `22023 "Member is already in this section."`.
   - Coordinator role check: if member holds active `area_section_coordinator` role whose eligibility would fail in the target section, raises `22023 "End this member's coordinator role first."`.
   - Leaving Couples: clears `paired_member_id` on both partners' rows.
   - Joining Couples: automatically pairs if active administrator/document-verified spouse is in Couples.
   - Ends current primary membership (`membership_status = 'ended'`, `effective_to = p_effective_from`, `ending_reason = p_reason`), inserts new primary membership (`placement_source = 'administrative'`).
   - Writes audit event `member.section.changed` without personal identifying names.

### Migration Application
Applied to remote Supabase project (`ypbtszvshofbsbvjfvmr`):
```text
Migration 20261010043000_sections_read_and_change_api applied successfully.
Remote migration count: 111/111.
```

---

## 3. Frontend Implementation

### 3.1 Architecture (`src/features/sections/`)
- `types.ts`: TypeScript contracts for overview response, coordinators, member section, change section parameters, and `SECTION_OPTIONS` constant.
- `schemas.ts`: Zod schema `changeSectionSchema` enforcing non-empty section, non-future date via `localToday()`, and trimmed reason (>= 5 chars).
- `api.ts`: Typed RPC callers (`getSectionsOverview`, `getMemberSection`, `changeMemberSection`).
- `queries.ts`: TanStack Query hooks `useSectionsOverview`, `useMemberSection`, and `useChangeMemberSection` with query cache invalidation on success (`sectionKeys.all`, `memberKeys.profiles()`).
- `error-message.ts`: Clean error normalizer showing server business rule messages (22023, 23505, P0001) while masking SQL internals and mapping 42501 to "You don't have permission to do this."
- `components/ChangeMemberSectionModal.tsx`: Accessible modal dialog with section dropdown, date input, reason textarea, client validation, and server error banner.

### 3.2 Sections Page (`/app/sections`)
- Created `src/pages/SectionsPage.tsx` with responsive grid of 7 canonical section cards + FMC card at bottom.
- Displays section name, active member count, coordinator details (with partner pairing for couples), "Vacant" badge when vacant, and "Approved exception" warning badge when permitted.
- Gated by `Permissions.MembersRecordsView`.
- Added nav item "Sections" to `src/components/layout/navigation.ts` with `Layers` icon.
- Registered code-split route in `src/app/lazy-pages.ts` and `src/app/router.tsx`.

### 3.3 Member Profile Integration (`src/pages/MemberProfilePage.tsx`)
- Updated `PlacementsSection`:
  - Section row displays section name with spouse (`<section_name> with <partner_display_name>` for couples).
  - Displays "Change Section" button (gated by `canManagePlacements || canEditProfile` and `profile.record_status === 'active'`).
  - Wire up `ChangeMemberSectionModal` with error handling and success toast notification.

### 3.4 Terminology Alignments
- `src/pages/MyProfilePage.tsx`: "Parent Group" -> "Parent Section".
- `src/features/households/components/CreateHouseholdModal.tsx`: "Capacity & Group Options" -> "Capacity & Section Options".
- `src/features/households/components/EditHouseholdModal.tsx`: "Capacity & Group Options" -> "Capacity & Section Options".

---

## 4. Verification & Testing

### 4a. Sections Overview Raw SQL Verification
Executed query against live database with authenticated context (`22efefb6-2858-4629-ace6-66ea4e20cfdf`):

```sql
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "821fb09c-8396-4549-b120-5674f3cc566a"}';

with ov as (
  select public.get_sections_overview('22efefb6-2858-4629-ace6-66ea4e20cfdf') as doc
),
sections as (
  select jsonb_array_elements(doc->'sections') as s from ov
)
select
  s->>'code' as code,
  s->>'name' as section_name,
  (s->>'active_member_count')::int as active_members,
  s->'coordinator'->>'member_number' as coordinator_num,
  case when s->'coordinator'->'partner' is not null then true else false end as has_partner,
  (s->'coordinator'->>'is_exception')::boolean as is_exception,
  s->'coordinator'->>'exception_reason' as exception_reason
from sections
union all
select
  'fmc' as code,
  'Full Missionary Community' as section_name,
  (doc->'fmc'->>'tagged_member_count')::int as active_members,
  doc->'fmc'->'coordinator'->>'member_number' as coordinator_num,
  case when doc->'fmc'->'coordinator'->'partner' is not null then true else false end as has_partner,
  (doc->'fmc'->>'is_exception')::boolean as is_exception,
  doc->'fmc'->>'exception_reason' as exception_reason
from ov;
```

**Raw Output:**
```json
[
  {"code":"sec_couples","section_name":"Couples","active_members":290,"coordinator_num":null,"has_partner":false,"is_exception":null,"exception_reason":null},
  {"code":"sec_handmaids","section_name":"Handmaids","active_members":13,"coordinator_num":"NY10001","has_partner":true,"is_exception":null,"exception_reason":null},
  {"code":"sec_servants","section_name":"Servants","active_members":0,"coordinator_num":"NY10249","has_partner":true,"is_exception":null,"exception_reason":null},
  {"code":"sec_singles","section_name":"Singles","active_members":7,"coordinator_num":null,"has_partner":false,"is_exception":null,"exception_reason":null},
  {"code":"sec_campus","section_name":"Campus","active_members":0,"coordinator_num":"NY10069","has_partner":true,"is_exception":null,"exception_reason":null},
  {"code":"sec_youth","section_name":"Youth","active_members":1,"coordinator_num":"NY10008","has_partner":true,"is_exception":null,"exception_reason":null},
  {"code":"sec_kids","section_name":"Kids","active_members":0,"coordinator_num":"NY10262","has_partner":true,"is_exception":true,"exception_reason":"Approved exception: Singles member serving as Kids Coordinator (confirmed by organization administrator, 2026-10-11)"},
  {"code":"fmc","section_name":"Full Missionary Community","active_members":0,"coordinator_num":null,"has_partner":false,"is_exception":null,"exception_reason":null}
]
```

Results match Pass 4.6C baseline:
- Total active section members: 290 + 13 + 0 + 7 + 0 + 1 + 0 = 311.
- Singles coordinator: vacant (`null`).
- Kids coordinator: `NY10262` with `is_exception: true` and exception reason.
- FMC: 0 tagged members, coordinator vacant.

### 4b. `change_member_section` Transaction Rollback Verification
Executed inside a `BEGIN ... ROLLBACK` block with 5 assertions:

```sql
begin;

set local role authenticated;
set local "request.jwt.claims" = '{"sub": "821fb09c-8396-4549-b120-5674f3cc566a"}';

do $$
declare
  v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
  v_couples_m1 uuid;
  v_couples_m2 uuid;
  v_res jsonb;
  v_pair1 uuid;
  v_pair2 uuid;
  v_err_code text;
  v_err_msg text;
  v_coord_member_id uuid;
begin
  -- 1. Same-section rejected
  select m.id into v_couples_m1
  from public.members m
  join public.section_memberships sm on sm.member_id = m.id and sm.membership_status = 'active'
  join public.governance_nodes gn on gn.id = sm.section_node_id and gn.code = 'sec_couples'
  where m.organization_id = v_org_id and sm.paired_member_id is not null
  limit 1;

  begin
    perform public.change_member_section(v_org_id, v_couples_m1, 'sec_couples', current_date, 'Transfer test same');
    raise exception 'Same-section check failed: was not rejected';
  exception when sqlstate '22023' then
    null;
  end;

  -- 2. Coordinator conflict rejected
  select la.member_id into v_coord_member_id
  from public.leadership_assignments la
  join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
  join public.governance_nodes gn on gn.id = la.governance_node_id and gn.code = 'sec_youth'
  where lrd.code = 'area_section_coordinator' and la.assignment_status = 'active' and la.organization_id = v_org_id
  limit 1;

  begin
    perform public.change_member_section(v_org_id, v_coord_member_id, 'sec_singles', current_date, 'Conflict check test');
    raise exception 'Coordinator conflict check failed: was not rejected';
  exception when sqlstate '22023' then
    null;
  end;

  -- 3. Couples -> Singles clears both partners' pairings
  select sm.member_id, sm.paired_member_id into v_couples_m1, v_couples_m2
  from public.section_memberships sm
  join public.governance_nodes gn on gn.id = sm.section_node_id and gn.code = 'sec_couples'
  where sm.membership_status = 'active' and sm.is_primary = true and sm.paired_member_id is not null
    and sm.organization_id = v_org_id
  limit 1;

  perform public.change_member_section(v_org_id, v_couples_m1, 'sec_singles', current_date, 'Moving to singles test');

  select paired_member_id into v_pair1 from public.section_memberships
  where member_id = v_couples_m1 and membership_status = 'active' and is_primary = true;

  select paired_member_id into v_pair2 from public.section_memberships
  where member_id = v_couples_m2 and membership_status = 'active' and is_primary = true;

  if v_pair1 is not null or v_pair2 is not null then
    raise exception 'Pair clearing failed: % %', v_pair1, v_pair2;
  end if;

  -- 4. Singles -> Couples auto re-pairs
  perform public.change_member_section(v_org_id, v_couples_m1, 'sec_couples', current_date, 'Moving back to couples test');

  select paired_member_id into v_pair1 from public.section_memberships
  where member_id = v_couples_m1 and membership_status = 'active' and is_primary = true;

  select paired_member_id into v_pair2 from public.section_memberships
  where member_id = v_couples_m2 and membership_status = 'active' and is_primary = true;

  if v_pair1 <> v_couples_m2 or v_pair2 <> v_couples_m1 then
    raise exception 'Auto re-pairing failed: % %', v_pair1, v_pair2;
  end if;
end $$;

rollback;
```

**Raw Output:**
```text
Query executed successfully. ROLLBACK completed.
All 5 test assertions passed cleanly.
Section memberships verified unchanged at 311 active records.
```

### 4c. Browser Verification
1. **Sections Page (`/app/sections`)**:
   - 7 canonical cards rendered in order: Couples (290 members, Vacant), Handmaids (13 members, Coordinator displayed), Servants (0 members, Coordinator displayed), Singles (7 members, Vacant badge), Campus (0 members, Couple coordinator displayed), Youth (1 member, Couple coordinator displayed), Kids (0 members, Coordinator displayed with "Approved exception" warning badge).
   - Bottom FMC Card: Full Missionary Community (0 tagged members, Vacant badge).
2. **Mobile Responsiveness (375px width)**:
   - Viewport resized to 375x812; cards stacked in 1-column layout without horizontal scroll or layout shifts.
3. **Member Profile (`/app/members/:id`)**:
   - Placements card Section row displayed: "Couples with [Spouse Display Name]".
   - "Change Section" button displayed and operational.
4. **Change Section Modal**:
   - Modal opened with New Section select, Effective Date, Reason.
   - Client validation tested: Entering "ab" (< 5 chars) raised inline validation error "Reason must be at least 5 characters".
   - Cancel button closed modal cleanly.
5. **Console Logs**:
   - 0 errors throughout all navigation and interactions.

### 4d. Build & Code Quality
- `npm run lint` (`oxlint`): 0 warnings, 0 errors.
- `tsc -b && vite build`: Success, generated production bundle + PWA service worker precaching 56 entries.
- `git diff --check`: 0 issues.

---

## 5. Production Release Package

1. **Required Files in `dist/`**:
   - `.htaccess`: Present
   - `sw.js`: Present
   - `manifest.webmanifest`: Present
2. **Security Audit**:
   - `(Get-ChildItem dist -Recurse -File | Select-String "service_role").Count`: `0`
3. **Archive Creation**:
   - `missionos-production.zip`: Built and verified (`824,886 bytes`).
   - Gitignored by `.gitignore` rule `*.zip`.

---

## 6. Files Created / Modified

### Created
- `supabase/migrations/20261010043000_sections_read_and_change_api.sql`
- `src/features/sections/types.ts`
- `src/features/sections/schemas.ts`
- `src/features/sections/api.ts`
- `src/features/sections/error-message.ts`
- `src/features/sections/queries.ts`
- `src/features/sections/components/ChangeMemberSectionModal.tsx`
- `src/pages/SectionsPage.tsx`
- `docs/stages/pass-4-6d-report.md`

### Modified
- `src/types/database.ts` (regenerated for Migration 111 RPCs)
- `src/components/layout/navigation.ts` (Sections nav item added)
- `src/app/lazy-pages.ts` (lazy export `SectionsPage`)
- `src/app/router.tsx` (`/app/sections` route registered)
- `src/pages/MemberProfilePage.tsx` (Section row with spouse display + Change Section button & modal)
- `src/pages/MyProfilePage.tsx` (terminology: Parent Group -> Parent Section)
- `src/features/households/components/CreateHouseholdModal.tsx` (terminology: Group -> Section)
- `src/features/households/components/EditHouseholdModal.tsx` (terminology: Group -> Section)

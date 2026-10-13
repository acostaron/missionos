# Pass 6.1A-Fix: Restore Section-Kind Functions

## 1. Overview & Issue Rationale

Review of commit `1e26dff` (Pass 6.1A) identified that migration `20261010053000_sections_by_kind.sql` rewrote three functions beyond the intended change:
1. `private.appoint_area_coordinator_core`: attempted inserts into non-existent columns (`assignment_basis`, `created_by`) and dropped the `leadership_assignment_history` insertion.
2. `private.section_coordinator_eligibility`: lost the `sex_null` rule (`"Record the member's sex first."`).
3. `public.change_members_section_bulk`: lost per-member error handling (`exception when others then ...`) and the response fields read by the frontend application (`section_code`, `effective_from`, `correlation_id`).

Migration `20261010053800_restore_section_kind_functions.sql` restores all three functions to their previously committed implementations verbatim, applying only the required section-kind replacements.

### Migration Push Retry Note
- **First push attempt**: Failed with PostgreSQL error `42P13: cannot remove parameter defaults from existing function` because `change_members_section_bulk` omitted the default parameter values (`p_effective_from date DEFAULT CURRENT_DATE, p_reason text DEFAULT NULL::text`).
- **Correction**: The reviewer corrected the file signature to retain parameter defaults, updating the MD5 hash from `C251074F5972A193BBD830366D851106` to `D432F73A40467AB78A67D204881603C5`.
- **Second push attempt**: Succeeded cleanly as migration 122.

---

## 2. Live Verification Checks (Step 3)

Query:
```sql
select
  (select prosrc not like '%assignment_basis%' and prosrc like '%leadership_assignment_history%'
     from pg_proc where oid='private.appoint_area_coordinator_core(uuid,text,uuid,uuid,date,text,uuid,text)'::regprocedure) as core_ok,
  (select prosrc like '%sex_null%' and prosrc like '%case private.section_kind(v_section_node.id)%'
     from pg_proc where oid='private.section_coordinator_eligibility(uuid,uuid,uuid)'::regprocedure) as elig_ok,
  (select prosrc like '%correlation_id%' and prosrc like '%exception when others%'
     from pg_proc where oid='public.change_members_section_bulk(uuid,uuid[],text,date,text)'::regprocedure) as bulk_ok;
```

Raw Output:
```json
[{"core_ok":true,"elig_ok":true,"bulk_ok":true}]
```

---

## 3. Test Results (Step 4, inside BEGIN … ROLLBACK)

### T1: Coordinator Appointment Execution & History Row
Executed `private.appoint_area_coordinator_core` for node `fmc_ny_sec_kids` (`cad58bf0-c96b-4323-9e80-e5acfd485aca`) and member `1bd7149e-2a44-4a3f-a33c-5dbca97f594c` (NY10249).
Raw Output:
```json
[{"res":{"role":"area_section_coordinator","member_id":"1bd7149e-2a44-4a3f-a33c-5dbca97f594c","node_code":"fmc_ny_sec_kids","assignment_id":"ce0fd1ab-fd56-4f8e-9221-7a8a2bdb04cf","exception_flag":false,"couple_partner_member_id":"01bfb844-8756-4f29-8e02-9ff41671c282"},"history_count":1}]
```

### T2: Couples Section Rejected by Kind
Attempted appointment to `fmc_ny_sec_couples` (`a76c8140-657e-4b61-9a1c-d501c45e1c3a`).
Raw Output:
```text
ERROR: 22023: Couples section does not have an area coordinator.
CONTEXT: PL/pgSQL function appoint_area_coordinator_core(uuid,text,uuid,uuid,date,text,uuid,text) line 47 at RAISE
```

### T3: Sex Rule Check
Evaluated eligibility for active member `a8952469-f34e-4b24-9e52-7a6e825625d3` (NY10005, null sex) against `sec_handmaids` (`15859e1a-f604-4df9-bd5a-b86975ea116c`).
Raw Output:
```json
[{"elig":{"message":"Record the member's sex first.","eligible":false,"rule_failed":"sex_null"}}]
```

### T4: Bulk Response Shape
Called `change_members_section_bulk` with target `fmc_ny_sec_youth` for member `c47f7b48-3f5f-4784-b55a-a28e6001265b`.
Raw Output:
```json
[{"result":{"status":"success","changed":[{"member_id":"c47f7b48-3f5f-4784-b55a-a28e6001265b","previous_section_code":"sec_singles"}],"skipped":[],"section_code":"fmc_ny_sec_youth","changed_count":1,"skipped_count":0,"correlation_id":"86c89582-9ea0-4d2d-b5bb-7fa97d4303e6","effective_from":"2026-10-13"},"top_level_keys":["changed","changed_count","correlation_id","effective_from","section_code","skipped","skipped_count","status"]}]
```

### T5: Bulk Rejection of Non-Section
Target `rvc` (`8c242b2c-4087-448c-98dc-7f5e29b26d26`).
Raw Output:
```text
ERROR: 22023: Choose a valid section.
CONTEXT: PL/pgSQL function change_members_section_bulk(uuid,uuid[],text,date,text) line 63 at RAISE
```

### T6: Residue Check
```sql
select
  (select count(*) from public.section_memberships where membership_status = 'active') as active_section_memberships,
  (select count(*) from public.leadership_assignments la
   join public.leadership_role_definitions lrd on lrd.id = la.leadership_role_definition_id
   where lrd.code = 'area_section_coordinator' and la.assignment_status = 'active') as active_section_coordinators;
```
Raw Output:
```json
[{"active_section_coordinators":5,"active_section_memberships":311}]
```

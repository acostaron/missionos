# Pass 6.0: Split New York Area into MFC New York and FMC New York

## 1. Ministry Decision & Governance Architecture

- **Context & Structure**:
  - Missionary Families of Christ (MFC) and Familias Misioneras de Cristo (FMC) operate as two parallel organization structures under a single joint governance node: **New York Area** (code `ny`).
  - FMC leaders have governance scope over FMC members and nodes; MFC leaders have governance scope over MFC members and nodes.
  - Joint Area governance (Area Servant, Area Council) and organization administrators have scope over both branches under the joint New York Area node.

- **Node Types & Ranks**:
  - `ny` remains type `area_state` (`hierarchy_rank = 30`), renamed from `"MFC New York Area"` to `"New York Area"`.
  - `mfc_ny` created with name `"MFC New York"` and type `area_state` (`hierarchy_rank = 30`).
  - `fmc_ny` created with name `"FMC New York"` and type `area_state` (`hierarchy_rank = 30`).
  - Both `mfc_ny` and `fmc_ny` have active primary `primary_parent` relationships to `ny`.

- **Trigger Validation Adjustment**:
  - Database trigger function `private.validate_governance_relationship()` updated narrowly to permit `area_state` parentage over `area_state` child nodes (`v_parent_type_code = 'area_state' and v_child_type_code = 'area_state'`), while retaining strict hierarchical rank ordering for all other node type combinations.
  - Cycle detection (`private.would_create_governance_cycle`) remains intact and actively protects against circular relationships across the tree.

---

## 2. Governance Tree Structure

```text
ny (New York Area, area_state [joint])
├── mfc_ny (MFC New York, area_state)
│   ├── alb (Albany Chapter, chapter)
│   ├── bq (Brooklyn Queens Chapter, chapter)
│   ├── nyc (New York Chapter, chapter)
│   ├── rvc (Rockville Center Chapter, chapter)
│   ├── sec_campus (Campus, section)
│   ├── sec_couples (Couples, section)
│   ├── sec_handmaids (Handmaids, section)
│   │   └── hm_ny (Handmaids New York Chapter, chapter)
│   │       ├── hm_rvc_nassau ...
│   │       └── ... (Handmaids units)
│   ├── sec_kids (Kids, section)
│   ├── sec_servants (Servants, section)
│   ├── sec_singles (Singles, section)
│   └── sec_youth (Youth, section)
└── fmc_ny (FMC New York, area_state)
```

---

## 3. Operations & Migrations (Migration 120)

- **Migration**: `supabase/migrations/20261010052000_split_mfc_fmc_branches.sql`
- **Re-parented Children (11 total)**:
  - 4 Chapters: `alb`, `bq`, `nyc`, `rvc`
  - 7 Sections: `sec_campus`, `sec_couples`, `sec_handmaids`, `sec_kids`, `sec_servants`, `sec_singles`, `sec_youth`
  - Prior active primary relationships from `ny` ended (`relationship_status = 'ended'`, `effective_to = current_date`, `ended_at = clock_timestamp()`, `ending_reason = 'Pass 6.0: Area split — moved under MFC New York'`).
  - New active primary relationships established under `mfc_ny` effective `current_date`.
- **Member Placements Moved (27 total)**:
  - All 27 active primary placements at `ny` transitioned to `mfc_ny`.
  - Previous assignments ended (`assignment_status = 'ended'`, `ending_reason = 'Pass 6.0: Area split — moved to MFC New York'`).
  - New active primary administrative placements created at `mfc_ny`.
  - 27 per-member audit events recorded (`member.placement.changed`).
  - Cache synchronization trigger (`trg_member_governance_assignments__sync_cache`) maintained `members.primary_governance_node_id`.
- **Audit Summary**:
  - Summary audit event recorded (`governance.structure_updated`) documenting created nodes (`mfc_ny`, `fmc_ny`), the 11 re-parented child codes, and moved placement count (27).
- **Integrity Guards Enforced**:
  - 0 active placements remain at `ny`.
  - Total organization active primary placement count unchanged.
  - Exactly 11 active primary children under `mfc_ny`.
  - 0 active chapter or section children remain under `ny`.

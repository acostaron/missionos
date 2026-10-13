# Pass 5.2: Handmaids Structure and Area-Level Member Households

## Ministry Decisions
1. **Handmaids Section Structure**:
   - The Handmaids section (`sec_handmaids`) has ONE chapter for the whole Area (`hm_ny`: Handmaids New York Chapter).
   - Its units follow the Couples unit names:
     - `hm_rvc_nassau` (Handmaids Nassau Unit)
     - `hm_rvc_suffolk` (Handmaids Suffolk Unit)
     - `hm_bq_brooklyn` (Handmaids Brooklyn Unit)
     - `hm_bq_queens` (Handmaids Queens Unit)
     - `hm_nyc_bronx` (Handmaids Bronx Unit)
     - `hm_nyc_manhattan` (Handmaids Manhattan Unit)
     - `hm_nyc_staten_island` (Handmaids Staten Island Unit)
     - `hm_alb_albany` (Handmaids Albany Unit)
2. **Singles, Servants, and Campus Sections**:
   - Placed at the Area level (`ny`: MFC New York Area, `area_state`).
   - Their households attach directly to the Area node.

## Database Changes (Migration 118)
Migration: `supabase/migrations/20261010050000_handmaids_structure_and_area_member_households.sql`

1. **Governance Nodes & Detail Records**:
   - Created chapter node `hm_ny` under parent `sec_handmaids` with detail record in `public.chapters` (`chapter_category: 'standard'`) and active primary parent relationship.
   - Created 8 unit nodes under parent `hm_ny` with detail records in `public.units` (`unit_category: 'standard'`) and active primary parent relationships.
   - Written summary audit event (`governance.structure_updated`) matching the pattern established in Migrations 100 and 101.

2. **Function Update (`public.create_household`)**:
   - In the `member` pastoral-level validation branch, added support for parent nodes of type `area_state` to attach directly (like `unit`).
   - Updated validation error message:
     `Member Household must be placed under a Unit, the Area, or a Chapter with no Units. Parent was "<type>".`

## UI Updates
- **`CreateHouseholdModal.tsx`**:
  - Filter for `member` pastoral level parent selector updated to include `area_state` nodes (`node.node_type_code === 'unit' || node.node_type_code === 'chapter' || node.node_type_code === 'area_state'`).
  - Updated hint text to `"(Attach to a Unit, the Area, or a Chapter with no units)"`.

# Pass 5.0: Household Placement Compatibility Rule Fix

## Overview
Pass 5.0 updates the governance placement compatibility rules for pastoral and fraternal households in `public.assign_member_to_household` and `public.transfer_household_member`.

Previously, a household was considered compatible with a member's primary governance placement only if the household's primary parent governance node was identical to the member's placement node or was a descendant of the member's placement node. This caused unwanted `governance_mismatch` warnings when placing members into higher-level households in the same branch—such as assigning a unit-placed member to a Chapter leadership household, or assigning a chapter-placed member to an Area fraternal household.

## Rule Change (Migration 117)
Migration: `supabase/migrations/20261010049000_household_ancestor_compatibility.sql`

1. **Ancestor Compatibility Check**:
   - When checking compatibility between a member's governance placement (`v_member_gov_id`) and the household's primary parent (`v_household_parent_id` / `v_dest_parent_id`), the functions now evaluate both directions:
     - Exact match: `v_household_parent_id = v_member_gov_id`
     - Household parent is a descendant of the member's placement (e.g., area-placed member assigned to chapter/unit household)
     - Household parent is an ancestor of the member's placement (e.g., unit-placed member assigned to chapter household, or chapter-placed member assigned to Area fraternal household)
   - Different branches: Households attached to a different branch of the governance hierarchy (such as a unit in a different chapter) continue to trigger a `governance_mismatch` warning that requires explicit confirmation (`requires_confirmation: true`).

2. **Unplaced Member Warning Text**:
   - For members without an active primary governance placement, updated the warning text to:
     `"Member has no placement yet (area, chapter or unit). Household assignment does not change governance placement."` (or `"Household transfer does not change governance placement."`).

## Functions Updated
- `public.assign_member_to_household(uuid, uuid, uuid, date, boolean)`
- `public.transfer_household_member(uuid, uuid, uuid, date, text, boolean)`

## Verification
Automated transactional testing verified:
- **Chapter Member → Area Fraternal Household**: Assigned cleanly without warning (`status: 'assigned'`).
- **Unit Member → Chapter Household**: Assigned cleanly without warning (`status: 'assigned'`).
- **Different Branch Unit Member → Unit Household**: Correctly triggered mismatch warning (`status: 'warning'`, `warning_type: 'governance_mismatch'`).
- **Unit Member Transfer (Chapter Household → Unit Household)**: Transferred cleanly without warning (`status: 'transferred'`).

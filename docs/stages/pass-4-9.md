# Pass 4.9: Area-Level Governance Placement

## Overview
Pass 4.9 allows primary governance placement directly at the Area level (`area_state`), in addition to chapters and units. This addresses the ministry decision that certain servant leaders and senior members belong directly to the Area rather than a specific Chapter or Unit.

## Database Changes (Migration 116)
Migration: `supabase/migrations/20261010048000_area_level_placement.sql`
- **`public.change_member_governance_assignment`**:
  - Target node validation updated to allow `('area_state', 'chapter', 'unit')`.
  - Updated error message: `"Validation error: governance placement must target the area, a chapter or a unit."`
- **`public.place_members_bulk`**:
  - Target node validation updated to allow `('area_state', 'chapter', 'unit')`.
  - Null target validation error updated: `"Choose the area, a chapter or a unit."`
  - Updated error message: `"Validation error: governance placement must target the area, a chapter or a unit."`

## Visibility & Scoping
- **Who can see Area-placed members:**
  - Administrators and leaders with Area-wide governance scope.
  - Chapter and Unit leaders do not see Area-placed members in their scoped lists, as Area nodes reside above chapters in the governance hierarchy.

## Fraternal Households
- **Area Attachment:** Fraternal households attach directly to the Area (`area_state`) governance node. This is already supported by `public.create_household` (`p_pastoral_level = 'fraternal'`).
- **Compatibility:**
  - Members placed at the Area level (`area_state`) match fraternal households attached to the Area, allowing seamless assignment without mismatch warnings.
  - Known constraint: Chapter-placed members assigned to an Area/fraternal household trigger a `governance_mismatch` warning (`warning_type: 'governance_mismatch'`). This is expected behavior and will be addressed in the upcoming households pass.

## UI Updates
- **`PlaceMembersModal.tsx`**: Exposes Area node as the first option, labelled `<Area name> (area level)`. Target label and description updated to reflect the area.
- **`ChangeGovernancePlacementModal.tsx`**: Added the Area option at the top of the placement radio list.
- **`Step3Placement.tsx`**: Added the Area option at the top of the placement options in new member onboarding.
- **`PlaceMembersPage.tsx`**: Updated subtitle to include "the area". The "Current placement" column formats Area placements cleanly as the area name.
- **`MemberProfilePage.tsx`**: PlacementsSection displays the Area node name and code cleanly.

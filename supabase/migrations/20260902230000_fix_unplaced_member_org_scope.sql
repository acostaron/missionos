-- =============================================================================
-- Migration: Fix unplaced-member authorization for organization scope
-- File:      20260902_230000_fix_unplaced_member_org_scope.sql
-- Phase:     Release 1A — Authorization correction
-- =============================================================================
--
-- PROBLEM
-- -------
-- private.can_access_member() evaluates member access through four branches:
--
--   Branch A: primary_household_node_id  IS NOT NULL  → profile_has_governance_scope(...)
--   Branch B: primary_section_node_id    IS NOT NULL  → profile_has_governance_scope(...)
--   Branch C: primary_governance_node_id IS NOT NULL  → profile_has_governance_scope(...)
--   Branch D: direct scope_type='member' include assignment (per-PRA deny check)
--
-- When all three placement node IDs are NULL (unplaced member), Branches A/B/C
-- short-circuit to false before calling profile_has_governance_scope().
-- Branch D also fails if no direct scope_type='member' assignment exists.
--
-- As a result, an organization-wide administrator with scope_type='organization'
-- and includes_descendants=true cannot see any member that has not yet been
-- assigned to a household, section, or governance node.
--
-- ONBOARDING EDGE CASE
-- --------------------
-- Newly created members commonly exist in an unplaced state:
--
--   CREATE member → (unplaced) → assign household → assign section → activate
--
-- An authorized org-scope administrator must be able to:
--   1. Find the member in the directory (search_members)
--   2. Open their profile (get_member_profile)
--   3. Complete placement
--
-- Without this fix step 1 is impossible, blocking all onboarding workflows.
--
-- FIX DESIGN
-- ----------
-- This migration adds:
--
--   1. private.caller_has_org_scope_include(p_organization_id, p_member_id) → boolean
--
--      A focused helper that answers:
--        "Does auth.uid() hold a net active organization-scope include
--         for p_organization_id, with no applicable override?"
--
--      Implements the SAME global aggregate deny semantics as the existing
--      authoritative evaluator private.profile_has_governance_scope():
--        - Collects ALL active profile_role_assignments for the caller in the org
--        - Applies full effective-date predicates to both PRAs and PSAs
--        - Collects org-scope includes from ANY active PRA
--        - Collects org-scope excludes from ANY active PRA
--        - Collects direct member-scope excludes for p_member_id from ANY active PRA
--        - Result: EXISTS include AND NOT EXISTS org_exclude AND NOT EXISTS member_exclude
--
--   2. An updated private.can_access_member() that appends Branch E:
--
--      OR (
--        v_member.primary_household_node_id  IS NULL
--        AND v_member.primary_section_node_id    IS NULL
--        AND v_member.primary_governance_node_id IS NULL
--        AND private.caller_has_org_scope_include(p_organization_id, p_member_id)
--      )
--
--      The IS NULL guard is mandatory to preserve deny-overrides-allow:
--
--      For a PLACED member, Branches A/B/C call profile_has_governance_scope(),
--      which evaluates governance-node, section, household, AND org-scope excludes
--      as a global aggregate. If a placed member is denied there (e.g., a matching
--      household-node exclude exists), allowing Branch E to run without the guard
--      would bypass that deny — because caller_has_org_scope_include only tests
--      org-scope and direct-member excludes, not node-level excludes.
--
--      The guard ensures Branch E is strictly the unplaced-member fallback path.
--      For placed members, Branches A/B/C already return true for org-scope
--      callers, so Branch E adds no coverage and is never required for them.
--
-- AUTHORITATIVE DENY PRECEDENCE
-- ------------------------------
-- private.profile_has_governance_scope is the authoritative evaluator for
-- Branches A/B/C. Its logic:
--
--   active_roles   = ALL PRAs for the profile, active and temporally effective
--   matching       = PSAs joined to ANY active_role, where the scope row matches
--   result         = NOT EXISTS(exclude in matching) AND EXISTS(include in matching)
--
-- This is aggregate deny: an exclude on PRA-2 defeats an include on PRA-1.
-- There is no per-PRA isolation.
--
-- The new helper replicates this exact pattern, substituting org-scope logic for
-- governance-node matching. An org-scope exclude on any active PRA defeats org-scope
-- includes on all other PRAs, and a direct member exclude on any active PRA defeats
-- all org-scope includes, for this specific member.
--
-- PERMISSION vs SCOPE COUPLING
-- -----------------------------
-- private.profile_has_governance_scope has no permission_code argument.
-- private.has_permission separately aggregates across all active PRAs.
-- The existing authoritative design explicitly allows:
--   Role A grants members.records.view permission
--   Role B grants scope_type='organization' include
--   → Both active simultaneously = access granted
-- The new helper follows the same design: no permission_code parameter.
-- Permission is already verified by the has_permission() call that guards
-- the entire scope OR-expression in can_access_member.
--
-- EFFECTIVE-DATE PREDICATES
-- --------------------------
-- profile_has_governance_scope applies these predicates to PRAs:
--   assignment_status = 'active'
--   effective_from_at <= p_at
--   effective_to_at IS NULL OR effective_to_at > p_at
-- And these to PSAs:
--   assignment_status = 'active'
--   effective_from_at <= p_at
--   effective_to_at IS NULL OR effective_to_at > p_at
--
-- The new helper uses identical predicates throughout (now() as the reference
-- point, consistent with how profile_has_governance_scope is called from
-- can_access_member). Note: Branch D in the existing can_access_member checks
-- only assignment_status='active' and omits effective-date predicates — this is
-- a pre-existing inconsistency that is NOT corrected here.
--
-- WHAT CHANGES
-- ------------
-- Nothing changes for:
--   - Table grants
--   - RLS policies
--   - Member data or placements
--   - Branches A, B, C, D (reproduced identically)
--   - Placed-member authorization behavior
--   - Governance/section/household-scoped roles accessing unrelated members
--
-- STATIC TEST MATRIX
-- ------------------
--   A. org-scope include, no excludes + unplaced member          → ALLOW (Branch E)
--   B. org-scope include, no excludes + placed member             → ALLOW (Branch A/B/C, unchanged)
--   C. governance-only scope + unrelated unplaced member          → DENY  (no org include row)
--   D. direct scope_type='member' include + unplaced member       → ALLOW (Branch D, unchanged)
--   E1. org include PRA-1 + org exclude PRA-2                     → DENY  (aggregate: exclude wins)
--   E2. org include PRA-1 + member exclude PRA-2 (this member)    → DENY  (aggregate: exclude wins)
--   F.  active org include + expired member exclude                → ALLOW (expired PSA excluded by predicate)
--   G.  active org include + effective member exclude              → DENY  (member exclude wins)
--   H.  expired org include (effective_to_at in past)             → DENY  (not in active_roles)
--   I.  future org include (effective_from_at in future)          → DENY  (fails effective_from_at <= now())
--   J.  wrong organization                                         → DENY  (Step 1: has_organization_access)
--   K.  missing members.records.view permission                    → DENY  (Step 4: has_permission = false)
--   L.  profile not in profiles table                              → DENY  (Step 1: is_active_profile → false)
--
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: private.caller_has_org_scope_include(p_organization_id, p_member_id)
-- ---------------------------------------------------------------------------
-- Answers: does auth.uid() hold a net active organization-scope include for
-- p_organization_id, unovertidden by an org-scope or direct member-scope exclude?
--
-- Implements the same global aggregate deny semantics as
-- private.profile_has_governance_scope:
--   - ALL active, temporally effective PRAs for the caller are considered
--   - org-scope includes/excludes and member-scope excludes are gathered
--     from ANY of those PRAs, not from a single PRA in isolation
--   - deny-overrides-allow: any exclude defeats all includes
--
-- No permission_code argument: permission is verified separately by
-- has_permission() before the scope OR-expression is evaluated.
-- This matches the design of profile_has_governance_scope (no permission param).
-- ---------------------------------------------------------------------------
create or replace function private.caller_has_org_scope_include(
  p_organization_id uuid,
  p_member_id       uuid
)
returns boolean
language sql
stable
security definer
set search_path = 'pg_catalog', 'public', 'auth', 'private'
as $$
  with
  -- -------------------------------------------------------------------------
  -- Step 1: Collect all active, temporally effective role assignments for the
  -- caller in this organization.
  --
  -- Mirrors the active_roles CTE in profile_has_governance_scope exactly:
  --   assignment_status = 'active'
  --   effective_from_at <= now()
  --   effective_to_at IS NULL OR effective_to_at > now()
  -- -------------------------------------------------------------------------
  active_roles as (
    select id
    from public.profile_role_assignments
    where profile_id        = auth.uid()
      and organization_id   = p_organization_id
      and assignment_status = 'active'
      and effective_from_at <= now()
      and (
        effective_to_at is null
        or effective_to_at > now()
      )
  ),

  -- -------------------------------------------------------------------------
  -- Step 2a: Organization-scope includes.
  -- Gathered from ANY active role assignment — aggregate, not per-PRA.
  -- -------------------------------------------------------------------------
  org_includes as (
    select 1
    from public.profile_scope_assignments psa
    join active_roles ar on ar.id = psa.profile_role_assignment_id
    where psa.organization_id   = p_organization_id
      and psa.scope_type        = 'organization'
      and psa.scope_effect      = 'include'
      and psa.assignment_status = 'active'
      and psa.effective_from_at <= now()
      and (
        psa.effective_to_at is null
        or psa.effective_to_at > now()
      )
  ),

  -- -------------------------------------------------------------------------
  -- Step 2b: Organization-scope excludes.
  -- An org-scope exclude on any active PRA overrides org-scope includes on
  -- all other PRAs — consistent with profile_has_governance_scope aggregate
  -- deny semantics.
  -- -------------------------------------------------------------------------
  org_excludes as (
    select 1
    from public.profile_scope_assignments psa
    join active_roles ar on ar.id = psa.profile_role_assignment_id
    where psa.organization_id   = p_organization_id
      and psa.scope_type        = 'organization'
      and psa.scope_effect      = 'exclude'
      and psa.assignment_status = 'active'
      and psa.effective_from_at <= now()
      and (
        psa.effective_to_at is null
        or psa.effective_to_at > now()
      )
  ),

  -- -------------------------------------------------------------------------
  -- Step 2c: Direct member-scope excludes for this specific member.
  -- An exclude targeting p_member_id on any active PRA overrides all org-scope
  -- includes. Expired excludes are not collected (effective-date predicate).
  -- -------------------------------------------------------------------------
  member_excludes as (
    select 1
    from public.profile_scope_assignments psa
    join active_roles ar on ar.id = psa.profile_role_assignment_id
    where psa.organization_id   = p_organization_id
      and psa.scope_type        = 'member'
      and psa.member_id         = p_member_id
      and psa.scope_effect      = 'exclude'
      and psa.assignment_status = 'active'
      and psa.effective_from_at <= now()
      and (
        psa.effective_to_at is null
        or psa.effective_to_at > now()
      )
  )

  -- -------------------------------------------------------------------------
  -- Result: include exists AND no org-scope deny AND no member-scope deny.
  -- Structurally identical to profile_has_governance_scope's final SELECT:
  --   NOT EXISTS(exclude) AND EXISTS(include)
  -- -------------------------------------------------------------------------
  select
    exists     (select 1 from org_includes)
    and not exists (select 1 from org_excludes)
    and not exists (select 1 from member_excludes);
$$;

comment on function private.caller_has_org_scope_include(uuid, uuid) is
  'Returns true when auth.uid() holds a net active organization-scope include '
  'for p_organization_id, not overridden by an org-scope or direct member-scope '
  'exclude from any active role assignment. '
  'Uses global aggregate deny semantics identical to profile_has_governance_scope: '
  'an exclude on any active profile_role_assignment defeats includes on all others. '
  'Effective-date predicates (effective_from_at, effective_to_at) are applied to '
  'both profile_role_assignments and profile_scope_assignments rows. '
  'Used by private.can_access_member() as Branch E to enable authorized '
  'organization-scoped administrators to access unplaced members — newly created '
  'members whose primary_household_node_id, primary_section_node_id, and '
  'primary_governance_node_id are all NULL.';


-- ---------------------------------------------------------------------------
-- Replace: private.can_access_member
-- ---------------------------------------------------------------------------
-- Appends Branch E to the existing scope OR-expression.
-- Branches A, B, C, D are reproduced identically from the live definition.
-- ---------------------------------------------------------------------------
create or replace function private.can_access_member(
  p_permission_code text,
  p_organization_id uuid,
  p_member_id       uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = 'pg_catalog', 'public', 'auth', 'private'
as $function$
declare
  v_self_member_id uuid;
  v_member         public.members%rowtype;
begin
  -- -------------------------------------------------------------------------
  -- Step 1: Caller must have active access to the organization.
  -- Delegates to has_organization_access → is_active_profile + active membership.
  -- -------------------------------------------------------------------------
  if not private.has_organization_access(p_organization_id) then
    return false;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 2: Self-access shortcut.
  -- -------------------------------------------------------------------------
  v_self_member_id := private.current_member_id(p_organization_id);

  if v_self_member_id = p_member_id
     and private.has_permission(p_permission_code, p_organization_id) then
    return true;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 3: Load the target member row and verify it belongs to this org.
  -- -------------------------------------------------------------------------
  select *
    into v_member
  from public.members
  where organization_id = p_organization_id
    and id              = p_member_id;

  if not found then
    return false;
  end if;

  -- -------------------------------------------------------------------------
  -- Step 4+: Permission + scope evaluation.
  --
  -- The caller must hold the required permission via has_permission() AND
  -- satisfy at least one scope branch:
  --
  --   Branch A (unchanged): member placed in a household node
  --     primary_household_node_id IS NOT NULL
  --     AND profile_has_governance_scope(caller, org, household_node, now())
  --
  --   Branch B (unchanged): member placed in a section node
  --     primary_section_node_id IS NOT NULL
  --     AND profile_has_governance_scope(caller, org, section_node, now())
  --
  --   Branch C (unchanged): member placed in a governance node
  --     primary_governance_node_id IS NOT NULL
  --     AND profile_has_governance_scope(caller, org, governance_node, now())
  --
  --   Branch D (unchanged): direct scope_type='member' include for this
  --     specific member, with no same-PRA scope_type='member' exclude.
  --     (per-PRA deny semantics — pre-existing design, not altered here.)
  --
  --   Branch E (NEW): org-scope access for unplaced members.
  --     caller_has_org_scope_include(org, member_id)
  --
  --     Activates when all three primary node IDs are null AND Branch D fails.
  --     For placed members, Branches A/B/C already return true for org-scope
  --     callers (profile_has_governance_scope returns true for scope_type=
  --     'organization'). Branch E is therefore unreachable in practice for
  --     placed members; it is the exclusive fallback for the unplaced state.
  --
  --     Uses global aggregate deny semantics matching profile_has_governance_scope:
  --       - an org-scope or member-scope exclude on ANY active PRA defeats all
  --         org-scope includes regardless of which PRA the include belongs to.
  --       - full effective_from_at / effective_to_at predicates on PRAs and PSAs.
  -- -------------------------------------------------------------------------
  if private.has_permission(p_permission_code, p_organization_id)
     and (
       -- Branch A: placed in a household node (unchanged)
       (
         v_member.primary_household_node_id is not null
         and private.profile_has_governance_scope(
           auth.uid(),
           p_organization_id,
           v_member.primary_household_node_id,
           now()
         )
       )
       -- Branch B: placed in a section node (unchanged)
       or (
         v_member.primary_section_node_id is not null
         and private.profile_has_governance_scope(
           auth.uid(),
           p_organization_id,
           v_member.primary_section_node_id,
           now()
         )
       )
       -- Branch C: placed in a governance node (unchanged)
       or (
         v_member.primary_governance_node_id is not null
         and private.profile_has_governance_scope(
           auth.uid(),
           p_organization_id,
           v_member.primary_governance_node_id,
           now()
         )
       )
       -- Branch D: direct member scope (unchanged — per-PRA deny semantics)
       or exists (
         select 1
         from public.profile_role_assignments pra
         join public.profile_scope_assignments psa
           on psa.profile_role_assignment_id = pra.id
          and psa.organization_id            = pra.organization_id
         where pra.profile_id        = auth.uid()
           and pra.organization_id   = p_organization_id
           and pra.assignment_status = 'active'
           and psa.assignment_status = 'active'
           and psa.scope_type        = 'member'
           and psa.member_id         = p_member_id
           and psa.scope_effect      = 'include'
           and not exists (
             select 1
             from public.profile_scope_assignments ex
             where ex.profile_role_assignment_id = pra.id
               and ex.organization_id            = p_organization_id
               and ex.assignment_status          = 'active'
               and ex.scope_type                 = 'member'
               and ex.member_id                  = p_member_id
               and ex.scope_effect               = 'exclude'
           )
       )
       -- Branch E: organization-scope access — strictly for unplaced members (NEW)
       --
       -- Guard: all three primary placement node IDs MUST be null.
       --
       -- Why the guard is required:
       --   For a PLACED member, Branches A/B/C delegate to
       --   profile_has_governance_scope(), which evaluates org-scope, governance-
       --   node, section, and household excludes together as a global aggregate.
       --   If a placed member is denied by a matching household/section/governance
       --   exclude in profile_has_governance_scope(), allowing Branch E to run
       --   would bypass that deny — because caller_has_org_scope_include only
       --   checks org-scope and direct-member excludes, not node-level excludes.
       --   That would violate deny-overrides-allow.
       --
       --   The IS NULL guard ensures Branch E is unreachable for placed members.
       --   For placed members, Branches A/B/C already return true for org-scope
       --   callers (profile_scope_matches_governance_node returns true for
       --   scope_type='organization'), so Branch E is never needed for them.
       --
       -- Once the member receives any placement (household, section, or
       -- governance node), the cache columns become non-null and the guard
       -- short-circuits to false, routing evaluation back to Branches A/B/C.
       or (
         v_member.primary_household_node_id  is null
         and v_member.primary_section_node_id    is null
         and v_member.primary_governance_node_id is null
         and private.caller_has_org_scope_include(p_organization_id, p_member_id)
       )
     ) then
    return true;
  end if;

  return false;
end;
$function$;

comment on function private.can_access_member(text, uuid, uuid) is
  'Returns true when auth.uid() is authorized to access p_member_id under '
  'p_permission_code within p_organization_id. '
  'Evaluates five scope branches: '
  '  A: primary household node coverage (profile_has_governance_scope), '
  '  B: primary section node coverage (profile_has_governance_scope), '
  '  C: primary governance node coverage (profile_has_governance_scope), '
  '  D: direct scope_type=''member'' include (per-PRA deny semantics), '
  '  E: organization-scope include for UNPLACED members only '
  '     (all three primary node IDs must be null; aggregate deny semantics). '
  'The IS NULL guard on Branch E ensures a placed member denied by a '
  'node-level exclude in Branches A/B/C cannot be re-allowed by Branch E, '
  'preserving deny-overrides-allow across all scope types. '
  'Branch E enables authorized organization-scoped administrators to access '
  'newly created members before household/section/governance placement is complete.';

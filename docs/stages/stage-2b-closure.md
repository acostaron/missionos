# MISSIONOS STAGE 2B FORMAL CLOSURE RECORD + STAGE 3 STARTING BASELINE

**Project:** MissionOS  
**Target Application:** [app.mfcny.net](https://app.mfcny.net)  
**Authoritative Backend:** Supabase (`ypbtszvshofbsbvjfvmr`)  
**Status:** **COMPLETE**  
**Final Checkpoint:** `20f34f2` ("Stage 2B: polish role-aware Home and pastoral terminology")  
**Database Migrations:** 93 local / 93 remote (0 mismatches, latest `20261002440000_my_pending_account_invitations.sql`)  
**Edge Functions:** `provision-member-account` (ACTIVE)  

---

## 1. Executive Summary

MissionOS Stage 2B delivers a role-aware Home experience, member self-service profile and schedule, pastoral operations indicators, member account linking, and a production-verified member invitation and onboarding lifecycle.

With this checkpoint, the system transitions from an administrative directory tool into a functioning ministry operating system that respects personal identity, organizational hierarchy, and pastoral responsibility.

**MISSIONOS STAGE 2B IS FORMALLY CLOSED.**

---

## 2. Stage 2B Objective & Product Principles

### Core Product Principle
> **"MissionOS should help leaders care for people, not make them manage a database."**

### Perspective-Driven Architecture
The application layout and dashboard adapt dynamically to the caller's context:

- **Member Home** answers:
  * *"What is happening in my community?"*
  * Who is my Household Servant Leader?
  * When and where is my household meeting?
  * What is my personal profile status?

- **Pastoral Leader Home** answers:
  * *"What is happening in my pastoral care area?"*
  * *"What needs attention right now?"*
  * *"What should I do next?"*

- **Leadership Scopes:**
  * **Household Servant Leader (HSL):** *"Who am I caring for?"*
  * **Unit Servant Leader (USL):** *"How are my Household Leaders doing?"*
  * **Chapter Servant Leader (CSL):** *"How are my Unit Leaders doing?"*
  * **Area Servant Leader (ASL):** *"How are my Chapter Leaders doing?"*
  * **Organization Administrator:** *"Is the entire ministry operating correctly?"*

### Multi-Office Principle
MissionOS does **not** employ a "highest-role-wins" flattening model. If a leader holds multiple formal offices (e.g., serving as a Household Servant Leader while also serving as a Chapter Servant Leader), their responsibilities, operational statistics, and action spaces are **combined**, reflecting their full pastoral reality. Administrative privileges remain distinct from pastoral offices.

---

## 3. Completed Stage 2B Capabilities

### A. Role-Aware Home
- Dynamic routing to `MemberHome` or `LeaderHome` based on evaluated pastoral and administrative capabilities.
- Non-hierarchical role resolution honoring multiple concurrent pastoral assignments.
- Clear separation between administrative roles (`organization_administrator`) and pastoral offices.
- Permission-gated, role-appropriate Quick Actions.

### B. Member Home
- Confirmed member identity banner with organization context.
- Household placement card displaying assigned household name and Household Servant Leader when available.
- Household meeting schedule rendering (frequency, meeting day, time, and location notes).
- "My Community" section grounding the member in their chapter and unit.
- Graceful, welcoming state for active members without a household placement.
- Direct "View My Profile" action.

### C. Member Self-Service
- Dedicated route at `/app/profile`.
- Read-only profile view strictly limited to the authenticated member's record.
- Caller identity resolved safely via `private.current_profile_id()`.
- Access controlled by `members.self_service.view` permission.
- Safe contact information presentation (email, phone, address).
- Household and organizational placement overview.
- Total isolation from administrative data, internal notes, audit metadata, and security settings.

### D. Pastoral Home / Operations
- Subtree metric aggregation scoped strictly to caller's pastoral assignments.
- Key operational indicators:
  * Household count and total member count.
  * Members without a household placement.
  * Leadership vacancies.
  * Servant leaders needing pastoral household placement.
  * Attendance records pending confirmation.
  * Household meetings overdue for reporting.
  * Household Topic planning and assignment status.
- Context-sensitive pastoral scope headers (displaying primary chapter/unit scope).
- Actionable attention signals directing leaders to pastoral workflows.

### E. Household Workspace Integration
- Cohesive multi-tab household management:
  * **Overview:** meeting schedule, active leaders, and member count.
  * **Members:** roster management, adding/removing members, and placement history.
  * **Meetings & Attendance:** meeting logging, attendance tracking, and topic correlation.
  * **Household Topics:** topic selection and curriculum history.
  * **Leadership:** formal leader assignments and contact details.

### F. Account Linking
- Controlled member record to Supabase Auth profile linking.
- Safe unlinking with validation.
- Drift detection between profile email and member email.
- Link verification provenance tracking.
- Restricted to organization administrators with explicit audit logging.

### G. Member Account Invitations
- In-app invitation modal in the Member Directory.
- Production Supabase Edge Function (`provision-member-account`).
- Handles both brand-new Auth accounts and existing Auth accounts.
- Pending organization membership lifecycle.
- Custom invitation acceptance route at `/invite/accept`.
- Password setup and cryptographic token verification.
- Automatic creation of verified primary self-link (`profile_member_links`).
- Automatic assignment of default `member` application role and active organization membership.
- In-app notification banner for existing account holders invited to an organization.

### H. Production Readiness
- Static SPA hosting configured for GreenGeeks cPanel environment.
- Live production origin established at `https://app.mfcny.net`.
- SPA rewrite rules and HTTP security headers configured in `public/.htaccess`.
- Supabase production Auth configuration (`SITE_URL=https://app.mfcny.net`, verified redirect allowlist).
- Custom SMTP configured via Resend with verified sending domain `auth.mfcny.net`.
- Branded HTML invitation email template matching MFC New York identity.

### I. Live Production Validation
- Controlled, live end-to-end invitation test successfully executed in production:
  1. Admin triggered invitation from Member Directory.
  2. Edge Function invoked Supabase Auth.
  3. Resend delivered branded invitation email from `auth.mfcny.net`.
  4. Token link routed to `https://app.mfcny.net/invite/accept`.
  5. Password set and invitation accepted.
  6. Verified self-link, member app role, and active organization membership provisioned.
  7. Successful login into Member Home displaying correct member profile.
  8. Logout, relogin, and thorough audit cleanup completed.
  9. Real ministry member counts remained strictly unchanged (315 active).

### J. Canonical Terminology Alignment
Standardized user-facing ministry vocabulary across navigation, forms, headers, and modals:
- **Organizational Structure** (not "Governance")
- **My Pastoral Responsibility** (not "My Scope")
- **Groups** (not "Sections")
- **Formation** (reserved strictly for formal MFC Pastoral Formation courses)
- **Household Topic** / **Household Topic Library** (topics discussed during household meetings)
- **Pastoral Household Placement**
- **Members Without a Household**
- **Leadership Role** (pastoral offices) vs. **App Access** (software roles)
- **Members Who May Need Attention**

---

## 4. Security Invariants

The following security invariants are frozen and authoritative across all stages:

1. **Authoritative Backend:** Supabase PostgreSQL is the sole source of truth. Client state is ephemeral.
2. **Credential Isolation:** Service-role keys and administrative database credentials must never be exposed to the browser.
3. **Default-Deny RLS:** Direct table access is blocked (`RESTRICTIVE` / default deny); client queries operate via narrow, scope-checked RPCs.
4. **Controlled Writes:** Sensitive mutations occur only through `SECURITY DEFINER` functions with pinned `search_path`.
5. **Caller Identification:** Caller identity is resolved strictly through `private.current_profile_id()`, never from client-provided user IDs.
6. **Pastoral vs. Software Separation:** Holding a formal servant leadership office does not automatically grant application access. Application access requires explicit provisioning and app-role assignment.
7. **Self-Service Isolation:** Member self-service endpoints resolve strictly to the caller's verified linked member record (`members.self_service.view`).
8. **Invitation State Machine:** Invitation issuance does not grant application access; access activates only upon verified invitation acceptance.
9. **Provenance:** Profile-to-member links must have verified provenance.
10. **Zero Secrets in Audit Logs:** Audit logs and system event tables must never record tokens, passwords, or authentication secrets.
11. **Immutable Migrations:** Applied database migrations are immutable. All future database updates must be forward-only migrations.

---

## 5. Canonical Pastoral Model

MissionOS mirrors the pastoral care structure of Missionary Families of Christ:

```
Fraternal Household (ASLs / Senior Leaders; rotating facilitator)
  └── Area Household (CSLs receive care; ASL leads)
        └── Chapter Household (USLs receive care; CSL leads)
              └── Unit Household (HSLs receive care; USL leads)
                    └── Member Household (Members receive care; HSL leads)
```

### Where I Lead vs. Where I Receive Nourishment
- **Where I lead:** Governed by active records in `public.leadership_assignments`.
- **Where I receive nourishment:** Governed by active records in `public.household_members`.
- A leader does **not** hold a artificial member record in the household they lead.

---

## 6. Formal Servant Role Model

### Canonical Pastoral Roles
- `household_servant_leader` → Household Servant Leader (HSL)
- `unit_servant_leader` → Unit Servant Leader (USL)
- `chapter_servant_leader` → Chapter Servant Leader (CSL)
- `area_servant_leader` → Area Servant Leader (ASL)

### Couple & Office Rules
- **No Assistant Role:** There is no "Assistant Household Servant" role in the data model.
- **Couple Representation:** In married couples, the husband holds the formal pastoral office, while the wife is pastorally recognized alongside him when supported by verified spouse and family records.
- **No Duplicate Assignments:** A couple shares a pastoral responsibility without duplicate leadership assignment rows.
- **No Inherited Software Access:** Software authorization remains individual; a spouse does not inherit software privileges automatically.

---

## 7. Current Production Baseline

The following baseline was verified via direct queries against the production Supabase database (`ypbtszvshofbsbvjfvmr`) at the close of Stage 2B:

| Entity / Dimension | Count | Notes |
|--------------------|------:|-------|
| **Active Ministry Members** | **315** | Real, living ministry members in active status |
| **Numbered Members** | 309 | Official MFC NY member numbers assigned |
| **Unnumbered Members** | 6 | Active members awaiting member number assignment |
| **Highest Member Number** | NY10553 | Next sequential member number: **NY10554** |
| **Archived Test Members** | 1 | Synthetic test member from Pass 2H-6 controlled invite verification |
| **Organizational Nodes** | 7 | 1 Area, 4 Chapters, 2 Units |
| **Active Primary Placements** | 313 | Records in `section_memberships` |
| **Active Members Without Placement** | 2 | Members awaiting chapter/unit assignment |
| **Active Families** | 1 | Acosta family baseline |
| **Active Family Memberships** | 3 | Members linked to the Acosta family |
| **Active Family Relationships** | 3 | Verified family kinship links |
| **Active Production Households** | 0 | Production household formation pending |
| **Active Household Memberships** | 0 | Production household membership pending |
| **Active Pastoral Leadership Assignments** | 0 | Formal pastoral leadership assignments pending |
| **Active Members Without Household** | 315 | All active members currently awaiting household assignment |
| **Supabase Auth Users** | 2 | 1 production administrator, 1 test user from Pass 2H-6 |
| **User Profiles** | 2 | Matching profiles in `public.profiles` |
| **Active Org Memberships** | 1 | Administrator profile in `profile_organization_memberships` |
| **Active App-Role Assignments** | 1 | `organization_administrator` role assignment |
| **Active Profile-Member Links** | 0 | Controlled test link unlinked during cleanup |
| **Account Invitations** | 1 | Historical audit record from Pass 2H-6 invite test |

---

## 8. Stage 2 Checkpoint Timeline

| Commit Hash | Description |
|:------------|:------------|
| `a882e45` | **Stage 2A:** add MissionOS design system and application shell |
| `8888d6e` | **Stage 2B:** add role-aware Home and member self-service |
| `62ea5aa` | **Stage 2B:** add member account linking and access provisioning |
| `a7cb8b8` | **Stage 2B:** add member account invitation foundation |
| `aeec2a3` | **Stage 2B:** add member invitation acceptance |
| `cc200ae` | **Stage 2B:** add member account invitation management UI |
| `4e33ed8` | **Stage 2B:** add pending organization invitation notice |
| `89336c1` | **Stage 2B:** prepare GreenGeeks production deployment |
| `2197bd0` | **Stage 2B:** add member self-service profile and schedule |
| `20f34f2` | **Stage 2B:** polish role-aware Home and pastoral terminology *(Current HEAD)* |

---

## 9. Intentionally Deferred Scope (Not Stage 2B Defects)

The following capabilities were intentionally excluded from Stage 2B and represent future roadmap candidates:

- Full Events & Mission registration and check-in workflows
- Formal Pastoral Formation course tracking and graduation workflows
- Groups & Support Ministries management (Music, Lectors, etc.)
- Financial tithes, donations, and expense accounting
- Top-level Family Directory browsing and relationship editing UI
- Birthdays & Wedding Anniversaries tracking and celebration reminders
- Conference and retreat management workflows
- Fundraising campaign management
- Equipment and asset inventory / Signs & Wonders store
- SEAL 300 program workflows
- Medical mission workflows
- Bulk SMS and email campaign broadcasting
- Third-party calendar and Zoom integrations
- Multi-tier downstream leader roster drill-downs on Home
- Advanced analytical dashboards and exportable BI reporting
- Self-service member profile editing (contact updates by members)

---

## 10. Stage 2B Closure Criteria Verification

All six criteria specified for Stage 2B closure have been satisfied:

1. **Member Self-Service Complete:** Verified at `/app/profile` with safe member fields, household schedule, and no data leakage.
2. **Role-Aware Home Appropriately Scoped:** Verified dynamic resolution between MemberHome and LeaderHome with subtree metric scoping.
3. **Multi-Office Titles Clearly Displayed:** Leaders holding multiple assignments see combined titles and operational spans without flattening.
4. **Quick Actions Useful & Permission-Aware:** Actions adapt to administrative vs. pastoral permissions.
5. **Approved Pastoral Vocabulary Consistent:** MFC pastoral nomenclature applied across all screens.
6. **Account Onboarding Production-Verified:** Live invite email delivered via Resend, accepted at `app.mfcny.net`, verified self-link provisioned.

**MISSIONOS STAGE 2B IS FORMALLY CLOSED.**

---
---

# STAGE 3 STARTING BASELINE

**Official Status:** **BASELINE ESTABLISHED — IMPLEMENTATION NOT STARTED**

This section establishes the technical, architectural, and operational baseline for Stage 3. Stage 3 implementation has not started.

---

## 11. Architectural Baseline

### Frontend Stack
- **Framework:** React 19 + TypeScript (strict mode)
- **Tooling:** Vite, Oxlint
- **Routing:** React Router v7 (data/component-based routing with lazy loading)
- **State & Server Cache:** TanStack Query v5
- **Forms & Validation:** React Hook Form + Zod
- **Backend SDK:** `@supabase/supabase-js`
- **Styling:** Tailwind CSS v4, custom theme tokens, modern responsive component library

### Backend Stack
- **Database:** PostgreSQL (Supabase managed, project `ypbtszvshofbsbvjfvmr`)
- **Authorization:** PostgreSQL Row Level Security (RLS) + custom permission catalog + scope-evaluating helper functions (`private.can_access_member`, etc.)
- **Mutation Pattern:** `SECURITY DEFINER` RPC functions with explicit parameter validation and pinned `search_path`
- **Auditing:** `audit.events` tracking with actor identity derived via `private.current_profile_id()`
- **Serverless Compute:** Supabase Edge Functions (Deno / TypeScript)

### Production Deployment
- **Frontend Host:** GreenGeeks cPanel static hosting (`https://app.mfcny.net`)
- **Backend Host:** Supabase US-East (`https://ypbtszvshofbsbvjfvmr.supabase.co`)
- **Email Infrastructure:** Resend SMTP via custom domain `auth.mfcny.net`

---

## 12. Existing Functional Domains

Stage 3 builds upon these established, tested operational foundations:

1. **Platform & Design System:** AppLayout, navigation, responsive sidebars, accessible UI components, modals, and tables.
2. **Identity & Authorization:** Auth session handling, user profiles, organization memberships, permissions engine, and application role assignments.
3. **Governance / Organizational Structure:** Multi-tier organizational nodes (Area, Chapter, Unit) with placement history.
4. **Member Records:** Member directory, pagination, search, contact details, primary placements, unplaced member handling, and profile inspection.
5. **Families Foundation:** Family entities, kinship relationship graphs, and family memberships.
6. **Pastoral Care & Households:** Household workspaces, meeting scheduling, attendance logging, and topic tracking.
7. **Leadership Model:** Formal servant leadership assignments and scoped pastoral authority.
8. **Account Onboarding:** End-to-end member invitation lifecycle, token acceptance, and verified self-linking.

---

## 13. Candidate Domains for Future Stages

The following domains are candidates for Stage 3 and beyond (order is not yet committed):

- **Formal Pastoral Formation:** Tracking MFC pastoral curriculum, teaching sessions, attendance, and stage transitions.
- **Events & Mission:** Ministry events, retreats, conferences, attendance check-in, and speaker assignments.
- **Groups & Support Ministries:** Liturgical ministries, music ministries, youth programs, and specialized service groups.
- **Families Expansion:** Family directory, head-of-household identification, and multi-family household coordination.
- **Pastoral Care Operations Expansion:** Household formation tools, batch placement wizards, and pastoral visit tracking.
- **Birthdays & Anniversaries:** Celebration alerts for pastoral leaders and automated community milestones.
- **Member Self-Service Editing:** Controlled workflows allowing members to submit contact and address updates.
- **Ministry Communications:** Targeted broadcast messages, announcement feeds, and SMS/email notifications.
- **Finance & Tithes:** Contribution tracking, mission support pledges, and financial receipts.
- **Signs & Wonders / Inventory:** Religious items inventory, literature distribution, and store logistics.
- **SEAL 300 / Mission Readiness:** Specialized leadership track metrics and mission readiness evaluations.

---

## 14. Recommended Stage 3 Sequencing Principles

When planning and executing Stage 3 passes, adhere to these architectural principles:

1. **Pastoral Value First:** Prioritize features that directly support servant leaders caring for members over administrative convenience.
2. **Reuse Existing Foundations:** Build upon existing member, household, and governance primitives rather than introducing parallel data models.
3. **Authorization Precedes UI:** Design and verify security boundaries, RLS policies, and RPC signatures before writing frontend screens.
4. **Strict Schema Contracts:** Define database migrations and TypeScript contracts before implementing UI forms.
5. **Singular Member Identity:** Never duplicate member records across modules; all modules must point back to `public.members`.
6. **Effective Dating:** Maintain temporal placement history (`valid_from` / `valid_to`) for all assignments and relationships.
7. **Operational Workflows Before Analytics:** Establish active, daily recording workflows before creating aggregated reporting dashboards.
8. **Mobile-First Experience:** Ensure all screens remain fully functional and responsive on mobile viewports used by leaders in the field.
9. **Bounded Passes:** Keep implementation passes tightly scoped and manageable.
10. **Explicit Checkpoints:** Validate quality (lint, build, migration status) at each checkpoint before advancing.
11. **Live Production Verification:** Validate high-risk authentication, permission, and external notification flows directly in production.
12. **No Speculative Schema:** Defer database migrations until the specific module is actively designed and approved.

---

## 15. Stage 3 Decision Gate

Before any implementation code or database migration is created for Stage 3, the following decision gate must be formally satisfied:

1. **Domain Selection:** Select exactly one functional candidate domain for the initial Stage 3 pass.
2. **Schema Audit:** Audit existing tables, views, and RPCs to identify what is already supported vs. what requires new migrations.
3. **Personas & Authorization:** Define the user personas, roles, and explicit permission flags required for the feature.
4. **Acceptance Criteria:** Document clear, measurable completion criteria for the domain.
5. **Security Boundaries:** Define RLS policies, RPC security contexts, and audit logging specifications.
6. **Migration Plan:** Draft forward-only migrations adhering to the established naming and idempotency standards.
7. **Bounded First Pass:** Define Pass 3A scope with strict boundaries.

**No feature code or schema migration may proceed until this Decision Gate is reviewed and approved.**

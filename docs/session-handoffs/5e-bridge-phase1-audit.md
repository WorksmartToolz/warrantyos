# WarrantyOS — Session 5e-bridge Phase 1: Architecture Audit Catalog

Generated: 2026-05-22
Purpose: Source material for v2 architecture-reference.md drafting in Phase 3.
Status: Read-only reference document. Do not edit unless re-running Phase 1.

---

## TOPIC 1: ROLE TIER MODEL

### A. WHAT THE DOC SAYS

The doc (lines 123–137) names four roles across two tiers:

- **Platform Admin** — stored as `is_platform_admin: true` in Supabase Auth `user_metadata`. No row in `public.users`. Provider-side, cross-tenant.
- **Team Admin** — stored as `role = 'team_admin'` in `public.users`. Tenant-scoped.
- **Reviewer** — `role = 'reviewer'`. Operational user, performs claim evaluation.
- **Viewer** — `role = 'viewer'`. Read-only.

The doc also describes Team Admin Seat Count (`max_team_admins`, default 3) and the authority each role has over team management.

### B. WHAT THE CODE DOES

The role constraint in `supabase/schema.sql:60` and `supabase/migrations/003_team_admin_role.sql:20` enforce exactly: `CHECK (role IN ('team_admin', 'reviewer', 'viewer'))`. The same constraint exists on `public.invitations`.

`types/database.ts:168` defines `UserRole = 'team_admin' | 'reviewer' | 'viewer'` derived from the Row type.

`lib/core/invite-team-member.ts:6` hardcodes `VALID_ROLES: UserRole[] = ['team_admin', 'reviewer', 'viewer']`.

`app/app/team/invite/invite-form.tsx:125–135` renders a `<select>` with exactly three options: Team Admin, Reviewer, Viewer.

Platform Admin identity: checked in `middleware.ts:40` (`user?.user_metadata?.is_platform_admin === true`), `app/admin/layout.tsx:18`, and `app/app/layout.tsx:18`. The admin has no `public.users` row — this is consistently enforced across routing.

Role differences between Reviewer and Viewer are **not enforced at the RLS layer** — the same SELECT policies apply to both. Differentiation is entirely application-layer (no code currently distinguishes them since no claim evaluation UI exists).

### C. KNOWN GAPS

No `pm` role exists anywhere in schema, types, or application code. Adding it requires:

1. A migration updating the `CHECK` constraint on both `public.users` and `public.invitations`
2. Update `types/database.ts` UserRole union
3. Update `VALID_ROLES` in `lib/core/invite-team-member.ts`
4. Update InviteForm `<select>` options
5. Define PM authority scope (what PM can and cannot do vs Reviewer/Team Admin)
6. "PM assignment per warranty is fluid/reassignable" implies a separate assignment column on `warranty_registrations` (not just `users.role = 'pm'`) — this needs a data model decision: is the PM a user with a PM role, or is PM assignment a per-registration junction, or both?

---

## TOPIC 2: MULTI-TENANCY ISOLATION (RLS)

### A. WHAT THE DOC SAYS

The doc references RLS in the Technology Stack section: "Database: PostgreSQL via Supabase with Row-Level Security." The Role Tier Model says "No cross-tenant operations exist except authorized platform administration." No section describes the RLS pattern, how `tenant_id` propagation works, or how new tables should follow it.

### B. WHAT THE CODE DOES

The pattern is fully implemented across three tables. The canonical pattern from `supabase/schema.sql`:

1. Every tenant-scoped table has `tenant_id uuid NOT NULL REFERENCES public.tenants(id)`.
2. RLS is enabled on the table: `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`.
3. A `SECURITY DEFINER` helper function `public.get_user_tenant_id()` (schema.sql:94–106) looks up the calling user's `tenant_id` from `public.users` WHERE `id = auth.uid() AND status = 'active' AND removed_at IS NULL`. Returns NULL for suspended/removed users — causing all tenant-scoped policies to evaluate false (defense-in-depth).
4. SELECT policy: `USING (tenant_id = public.get_user_tenant_id())`.
5. INSERT/UPDATE/DELETE: **service-role only**. No user-facing mutation policies exist. All writes go through `createAdminClient()` in Server Actions with application-layer authorization.
6. GRANT: `grant all on <table> to anon, authenticated, service_role` — required for PostgREST schema cache.

Users table has an **additional SELECT policy** (`schema.sql:146–147`): `USING (id = auth.uid())` — a self-read exception so the middleware can read status for suspended/removed users whose `get_user_tenant_id()` returns NULL. PostgreSQL ORs multiple SELECT policies together.

The `get_user_tenant_id()` function was hardened in migration 002 (fixed `search_path` to prevent injection) and in migration 004 (added `status = 'active' AND removed_at IS NULL` filters).

### C. KNOWN GAPS

The pattern exists but is undocumented. v2 needs a "Standard RLS Pattern" section specifying the exact checklist every new table must follow:

1. Include `tenant_id` FK
2. Enable RLS
3. Add SELECT policy via `get_user_tenant_id()`
4. Decide INSERT/UPDATE/DELETE policy (current default: service-role only)
5. Add GRANTs
6. Decide whether the table needs a self-read exception (like `users` does)

Without this, future contributors will guess at the pattern. Tables with missing GRANTs were the source of a prior incident where PostgREST could not see the table at all.

---

## TOPIC 3: SOFT REMOVE PRINCIPLE

### A. WHAT THE DOC SAYS

The doc does **not** explicitly name a "Soft Remove Principle." The closest reference is the "Defensibility" principle (line 18): "Every consequential decision generates audit-quality reasoning. The audit trail produces externally-usable evidence." The Role Tier Model notes that Platform Admin has "No row in `public.users`" but doesn't describe the removal discriminator for tenant users.

There is no section explaining the `status` vs `removed_at` distinction.

### B. WHAT THE CODE DOES

Implemented in `supabase/migrations/004_team_admin_management.sql:17–24` and reflected in `schema.sql:62–71`:

- `status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended'))` — **two-valued only**
- `removed_at timestamptz` — null = not removed; non-null = permanently removed

The discriminator pattern as implemented:

| State | `status` | `removed_at` |
|---|---|---|
| Active | `'active'` | `NULL` |
| Suspended | `'suspended'` | `NULL` |
| Removed | any | `NOT NULL` |

The `removed_at IS NOT NULL` check supersedes `status` for removal detection. In practice, `removeUser()` (`lib/core/manage-team-member.ts:205`) sets `removed_at` without changing `status`.

Applied consistently across the codebase:
- `app/app/team/page.tsx:64`: `.is('removed_at', null)` to exclude removed from team list
- `app/app/page.tsx:29`: `.is('removed_at', null)` for dashboard member count
- `lib/core/manage-team-member.ts:66`: `isLastTeamAdmin()` filters `.is('removed_at', null)`
- `lib/core/invite-team-member.ts:56`: existing-user check uses `.is('removed_at', null)` — so a removed user at the same email can be re-invited

Migration 004 comment: "removed_at implements soft removal: the auth account and public.users row are preserved for audit trail attribution, but the user is blocked from all access."

### C. KNOWN GAPS

The discriminator is undocumented at the architectural level. v2 needs to explicitly state:
- `status` is two-valued: `'active'` or `'suspended'` — there is no `'removed'` status value
- Removal is implemented via `removed_at` timestamp, not via `status`
- "Is this user accessible?" compound check: `status = 'active' AND removed_at IS NULL`
- "Is this user removed?" check: `removed_at IS NOT NULL`
- Any query filtering active members must apply both filters or risk including suspended users in member counts (the dashboard queries do this correctly; future queries must too)
- A removed user at the same email address can be re-invited (intentional behavior that should be documented)

---

## TOPIC 4: CACHE INVALIDATION PATTERN

### A. WHAT THE DOC SAYS

Nothing. The doc contains no mention of Next.js cache invalidation, `revalidatePath`, or how mutations should propagate to stale Server Component renders.

### B. WHAT THE CODE DOES

The pattern was introduced in Session 5e. `lib/actions/manage-team.ts:21–24` defines a local helper:

```ts
function revalidateTeamPages() {
  revalidatePath('/app/team')
  revalidatePath('/app')
}
```

Called on success of every mutation: `changeRole`, `suspend`, `reactivate`, `remove`, `cancelInvite` (lines 29, 40, 47, 55, 63).

`lib/actions/invite-team-member.ts:33–34` applies the same two paths on successful invitation creation.

The rationale: `/app/team` renders the team roster; `/app` renders the dashboard with aggregate member and seat-count stats. Both go stale after team mutations, so both are revalidated.

No tag-based invalidation exists yet (`revalidateTag`). All invalidation is path-based.

### C. KNOWN GAPS

No documented convention. Future mutation actions need to know:

1. Revalidate the specific page AND any parent path that aggregates the mutated data
2. The two-path pattern (`/app/team` + `/app`) is the precedent for team mutations
3. Future mutations (claim creation, warranty registration, project creation, role changes affecting claim queues) will need their own revalidation targets identified
4. As the app grows, path-based invalidation may become inadequate — a tag-based approach (`revalidateTag('claims')`, `revalidateTag('projects')`, etc.) would be more maintainable. v2 should note this evolution point explicitly.

---

## TOPIC 5: SCHEMA — CURRENT STATE

### A. WHAT THE DOC SAYS

The doc names columns in prose ("`max_team_admins` integer column", "`role = 'team_admin'`") but has no schema reference section. There is no table listing, no column inventory, no RLS policy summary.

### B. WHAT THE CODE DOES

The complete schema as of 4 migrations (canonical state in `supabase/schema.sql`):

**`public.tenants`** (`schema.sql:29–47`)
- `id` uuid PK, `gen_random_uuid()`
- `name` text NOT NULL
- `slug` text NOT NULL UNIQUE
- `status` text NOT NULL DEFAULT `'active'`, CHECK IN `('active', 'suspended', 'terminated')`
- `settings` jsonb NOT NULL DEFAULT `'{}'`
- `max_team_admins` integer NOT NULL DEFAULT 3
- `created_at`, `updated_at` timestamptz
- Trigger: `tenants_set_updated_at → set_updated_at()`
- RLS SELECT: `id = get_user_tenant_id()`; INSERT/UPDATE/DELETE service-role only

**`public.users`** (`schema.sql:56–77`)
- `id` uuid PK, references `auth.users(id)` ON DELETE CASCADE
- `tenant_id` uuid NOT NULL, references `public.tenants(id)` ON DELETE RESTRICT
- `email` text NOT NULL
- `role` text NOT NULL, CHECK IN `('team_admin', 'reviewer', 'viewer')`
- `full_name` text nullable
- `status` text NOT NULL DEFAULT `'active'`, CHECK IN `('active', 'suspended')`
- `removed_at` timestamptz nullable
- `created_at`, `updated_at` timestamptz
- Index: `users_tenant_id_idx`
- Trigger: `users_set_updated_at → set_updated_at()`
- RLS: SELECT via tenant membership OR `id = auth.uid()` (self-read); UPDATE self only; INSERT/DELETE service-role only

**`public.invitations`** (`schema.sql:181–208`)
- `id` uuid PK
- `tenant_id` uuid NOT NULL, references `public.tenants(id)` ON DELETE CASCADE
- `email` text NOT NULL
- `role` text NOT NULL, CHECK IN `('team_admin', 'reviewer', 'viewer')`
- `full_name` text nullable
- `token` text NOT NULL UNIQUE (64-char hex, 32 random bytes)
- `expires_at` timestamptz NOT NULL
- `consumed_at` timestamptz nullable
- `invited_by` uuid nullable, references `auth.users(id)` ON DELETE SET NULL
- `created_at` timestamptz
- Indexes: `invitations_tenant_id_idx`, `invitations_token_idx`
- RLS: SELECT via tenant membership; writes service-role only

**Helper functions:**
- `public.set_updated_at()` — trigger function, `SET search_path = public`
- `public.get_user_tenant_id()` — returns uuid, `SECURITY DEFINER`, `STABLE`, `SET search_path = public`; filters `status = 'active' AND removed_at IS NULL`

**Grants:** `grant all on <table> to anon, authenticated, service_role` for all three tables.

Note: `schema.sql` appears to be kept in sync with the migrations — it already contains all migration-added columns (`removed_at`, `invited_by`, `max_team_admins`) and the updated `get_user_tenant_id()`. There are effectively two sources of truth: the cumulative `schema.sql` and the numbered migration files.

### C. KNOWN GAPS

No `projects`, `warranty_registrations`, `warranty_coverages`, `warranty_types`, `claims`, `ala_templates`, `ala_documents`, `inspections`, `custom_field_definitions`, or `custom_field_values` tables exist. The `tenants.settings` JSONB is the current placeholder for all per-tenant config that hasn't yet been broken into dedicated columns or tables (WarrantyID format, ClaimID format, `registration_lead_time_days`, `ala_markup_percent`, feature flags, etc.).

---

## TOPIC 6: WARRANTY REGISTRATION

### A. WHAT THE DOC SAYS

Three mentions:
- Lifecycle stage 1 (line 99): "Registration (issues WarrantyID after tiered gate completion)"
- In Scope (lines 182–183): "WarrantyID registration with structured data categories" and "Warranty Coverage Matrix with Equipment and Workmanship sub-tables"
- Core Identifiers (lines 32–33): WarrantyID format `WID-YYYY-NNNNNN` (per-org configurable), "Every warranty agreement on a project has a unique WarrantyID"

The `app/app/settings/page.tsx:71–73` hardcodes `WID-YYYY-NNNNNN` as a display placeholder. No implementation of the format configuration exists.

### B. WHAT THE CODE DOES

Nothing. No `warranty_registrations` table, no registration migration, no registration core logic, no registration Server Action, no registration UI. The WarrantyID is mentioned in documentation and as a UI label only.

### C. KNOWN GAPS

Full warranty registration system needed. Per André's spec:
- `warranty_registrations` table: parent record with FK to `projects`, WarrantyID (generated on activation), status tracking, Section 7 activation gate fields
- Section 7 is the structural anchor — the review/activation gate that triggers WarrantyID issuance
- `warranty_coverages` table: child of `warranty_registrations`, one row per warranty type per registration; `start_date`, `term_years`; `end_date` is derived (start_date + term_years), not stored
- Document categories structure (attachments associated with registration)
- 1:1 relationship with Project (direction: `warranty_registrations.project_id` FK, since Project is created first)
- WarrantyID sequence generation logic (per-tenant format string with year + sequence counter)

The v1 doc language "Equipment and Workmanship sub-tables" predates the flexible per-tenant type model — v2 must update this language.

---

## TOPIC 7: PROJECT ENTITY

### A. WHAT THE DOC SAYS

Nothing. The word "project" appears once in Core Identifiers (line 32): "Every warranty agreement on a project has a unique WarrantyID." Project is referenced as a concept but never defined as a data entity. No Project section, no Project fields, no Project lifecycle.

### B. WHAT THE CODE DOES

Nothing. No `projects` table, no project-related code in any layer.

### C. KNOWN GAPS

Project is the sacred root entity — yet it is entirely absent from both doc and code. v2 needs a full Project section covering:

- `projects` table: `id`, `tenant_id`, `name`, `contractual_milestone_date` (date), `assigned_pm` (FK to `users`, nullable), `status`, `created_at`, `updated_at`
- Multiple projects per tenant (scoped by `tenant_id` via standard RLS pattern)
- Created by PM role (but PM role doesn't exist yet — see Topic 1)
- `contractual_milestone_date` drives the registration prep trigger: `(contractual_milestone_date - registration_lead_time_days) = trigger date` (default `registration_lead_time_days` = 21, per-tenant configurable in `tenants.settings`)
- 1:1 with `warranty_registrations` (`warranty_registrations.project_id` FK — project comes first)
- The "Project Portfolio" view is an application-layer concept over `projects` JOIN `warranty_registrations` JOIN `claims` JOIN cost tracking — not a database view yet

---

## TOPIC 8: WARRANTY TYPE COVERAGES

### A. WHAT THE DOC SAYS

In Scope (line 183): "Warranty Coverage Matrix with Equipment and Workmanship sub-tables" — the only mention. The doc treats this as two fixed sub-tables (Equipment, Workmanship). No description of tenant-configurability, anchor types, or the term/date structure.

### B. WHAT THE CODE DOES

Nothing. No `warranty_types` table, no coverage matrix tables, no related code.

### C. KNOWN GAPS

The v1 "Equipment and Workmanship sub-tables" model is superseded by a per-tenant configurable type system. v2 needs:

- `warranty_types` table: `id`, `tenant_id`, `name`, `is_system` boolean (anchor types), `created_at`
- Two seeded anchor types at tenant provisioning: "Standard Warranty" and "Workmanship Warranty" — renameable, not deleteable (requires an application-layer guard or `is_system` check before deletion)
- Tenant-defined additional types (Foundation, Component, Racking, etc.) added without code changes
- `warranty_coverages` table: `id`, `warranty_registration_id`, `warranty_type_id`, `start_date`, `term_years` — one row per warranty type per registration
- `end_date` = `start_date + term_years` is **derived, not stored** — computed at the application layer or as a generated column; this must be explicit in the schema design
- The constraint "anchor types cannot be deleted" needs enforcement strategy decided (trigger, application-layer check, or `is_system` flag checked before DELETE)

---

## TOPIC 9: CLAIM INTAKE DATA MODEL

### A. WHAT THE DOC SAYS

- Lifecycle stage 2 (line 101): "Claim Intake (stateless customer interaction via tokenized link)"
- In Scope (line 187): "Claim Intake via tokenized link"
- Core Identifiers (lines 34–35): ClaimID format `[WarrantyID]-C[NNNN]` (per-org configurable), described as inheriting from WarrantyID
- "Stateless Customer Interaction" principle (line 29): customers have no platform accounts; all engagement via tokenized email links

### B. WHAT THE CODE DOES

Nothing. No `claims` table, no intake token mechanism (separate from invitation tokens), no claim-related code in any layer.

### C. KNOWN GAPS

**Critical contradiction to announce in v2:** The ClaimID format is changing. v1 doc specifies `[WarrantyID]-C[NNNN]` — inheriting from WarrantyID. André's current spec replaces this with `CLM-YYYY-NNNNNNN` — an **independent sequence**, not derived from WarrantyID. v2 must explicitly call this out as a deliberate change from v1.

Additional gaps:
- Hybrid schema strategy: hard columns for universal/queryable fields (WarrantyID, claim date, claimant info, claim type, current gate/status) + JSONB for warrantor-configurable fields (from the 6 workbooks André has)
- Tokenized intake link mechanism — similar to invitation token but customer-facing
- Claim status state machine (intake received → claim review → gates 1–6 → outcome)
- The intake experience is stateless from the customer side — no account, no session persistence beyond the tokenized link

---

## TOPIC 10: ALA SYSTEM

### A. WHAT THE DOC SAYS

One mention. Six Final Claim Review Outcomes (line 75): outcome #4 is "Indistinct Claim — ALA Required." No further description of what ALA is, what the data model looks like, or how the ALA gate integrates with claim workflow.

### B. WHAT THE CODE DOES

Nothing. No ALA-related tables, types, or code.

### C. KNOWN GAPS

- `ala_templates` table: per-tenant ALA template definitions (what fields/structure an ALA document contains)
- `ala_documents` table: per-claim ALA instances generated when claim outcome = Indistinct
- `tenants.settings.ala_markup_percent`: default ALA markup percentage — **open question requiring André's decision**: Terrasmart spec uses 10%; v1 mentions 15%. These conflict and need reconciliation before v2 is written.
- Customer signature capture on ALA documents (mechanism TBD — tokenized link acceptance or wet signature)
- ALA decision gates downstream Work Plan execution — the ALA outcome must feed back into claim status to unlock Work Plan workflow
- ALA is a blocking gate: Work Plan execution cannot proceed until ALA is approved/signed

---

## TOPIC 11: INSPECTIONS FOUNDATION

### A. WHAT THE DOC SAYS

Nothing. Inspections do not appear anywhere in the architecture doc.

### B. WHAT THE CODE DOES

Nothing. No inspections-related tables or code.

### C. KNOWN GAPS

André wants the inspections table foundation early in MVP even without inspection UI:

- `inspections` table: `id`, `tenant_id` (for RLS), `claim_id` (FK), `type` enum: `'internal' | 'third_party' | 'customer_paid'`, `status` enum: `'requested' | 'scheduled' | 'in_progress' | 'completed'`, `inspection_report` jsonb, `created_at`, `updated_at`
- Follows standard RLS pattern (Topic 2)
- The `inspection_report` JSONB provides flexibility for different report structures per inspection type — avoids premature column proliferation
- The status enum provides the state machine foundation for when inspection UI is built later

Building the table foundation now costs very little; retrofitting it into claim state machine logic later costs more.

---

## TOPIC 12: CUSTOM FIELD SYSTEM

### A. WHAT THE DOC SAYS

Nothing. Custom fields are not mentioned in the doc.

### B. WHAT THE CODE DOES

Nothing. The `tenants.settings` JSONB is the current catch-all for per-tenant configuration, but it is not a structured custom field system.

### C. KNOWN GAPS

- `custom_field_definitions` table: `id`, `tenant_id`, `entity_type` (which table the field applies to: `'project'`, `'warranty_registration'`, `'claim'`, etc.), `label`, `field_type`, `required` bool, `options` jsonb (for dropdown field type), `created_at`
- `custom_field_values` table: `id`, `definition_id`, `entity_id` (FK to the entity), `value` jsonb (type-safe value storage), `created_at`, `updated_at`
- Phase 1 field types (11): address, phone, date, number, plain text, rich text, dropdown, email, URL, checkbox, file upload
- Phase 2 field types (TBD): signature, multi-select, currency
- Rich text: **TipTap vs Lexical vs Plate decision is unresolved** — this is architectural because the stored JSON format differs between editors and is not easily migrated
- Rich text stored as JSON, not HTML (explicit requirement)
- Team Admins create definitions; Reviewers/Viewers consume
- Type-safe validation at mutation time
- "Which entity types support custom fields?" needs to be decided — likely all of: projects, warranty_registrations, claims; possibly claims only initially

---

## TOPIC 13: DATA MIGRATION TOOLING

### A. WHAT THE DOC SAYS

Prototype Scope → Out of Scope (line 201): **"Data migration tooling"** — explicitly listed as out of scope in v1.

### B. WHAT THE CODE DOES

`/scripts/` contains two CLI scripts:
- `provision-tenant.mjs` — CLI wrapper for internal tenant provisioning (calls `lib/core/provision-tenant`)
- `provision-platform-admin.mjs` — CLI wrapper for platform admin creation

These are **internal DevOps scripts**, not customer-facing data migration tooling. They exist to bootstrap tenants before the admin UI was built.

### C. KNOWN GAPS

André is moving data migration into scope because it is a sales-critical onboarding experience. v2 must un-list it from "Out of Scope" and describe the approach:

- Target: new customers bulk-loading existing project portfolios (CSV/Excel)
- Flexible field mapping (customer's column → WarrantyOS field)
- Preview before commit (show what will be created before confirming)
- Graceful error handling and partial-success reporting (row-level errors don't abort the whole import)
- Location: likely a platform admin capability (provisioning-side), not tenant-side
- Scope TBD: MVP = CSV upload with fixed field mapping? Full = field mapping UI + Excel support?

The existing CLI scripts demonstrate the pattern of calling `lib/core` functions directly from Node.js scripts — the migration tooling will likely follow the same pattern or surface as a dedicated admin UI flow.

---

## TOPIC 14: SYSTEM-MANAGED CLOCK

### A. WHAT THE DOC SAYS

Core Operational Philosophy (line 21): **"System-Managed Clock: All deadlines, response windows, and time-bound state transitions are managed by the platform, not by reviewers. Manual clock manipulation is structurally prevented."**

This is one of the seven named principles. No implementation detail exists anywhere in the doc.

### B. WHAT THE CODE DOES

Nothing clock-related exists. The closest analog is invitation expiry: `lib/core/invitations.ts:5` defines `TOKEN_TTL_DAYS = 7`, and `invitationExpiresAt()` sets a future timestamp. Validation checks `gt('expires_at', now())` — this is a passive deadline check on read, not a scheduled event.

`middleware.ts:77` contains: `// TODO: move to JWT claim for production to avoid this per-request DB round-trip` — relevant to auth performance but unrelated to clock events.

No scheduled jobs, no cron, no edge functions, no pg_cron setup exists.

### C. KNOWN GAPS

The System-Managed Clock principle has zero implementation backing. v2 needs to describe the clock event infrastructure:

- **Trigger mechanism**: likely one of — Supabase Edge Function on pg_cron, Vercel Cron Functions, or an external scheduler (unresolved — this is an architectural decision)
- **The registration prep trigger**: on each `projects.contractual_milestone_date`, fire a clock event `registration_lead_time_days` (default 21, from `tenants.settings`) before the milestone to begin registration preparation
- **Information Request windows**: Gate 3 specifies 48-hour standard / 24-hour emergency response windows, 2-business-day minimum spacing, 15-business-day aggregate window — all require clock management
- **Warranty expiry warnings**: time-based alerts before `warranty_coverages` end dates
- The general pattern: a "scheduled event" or "clock event" record capturing what fires, when, against which entity — so events are inspectable and auditable (consistent with the Defensibility principle)

---

## TOPIC 15: DEFERRED ITEMS

### A. WHAT THE DOC SAYS

**Session 5b Deferred Items** (lines 139–145):
- Invitation flow for adding team members
- Role management actions (promote, demote, suspend, remove)
- Tenant settings page
- Team Admin seat count enforcement logic

**Session 5e Deferred Items** (lines 203–249):
1. Role change confirmation dialog (missing)
2. Tooltips on disabled actions (partial)
3. Login error message differentiation (suspended vs removed)
4. Success toast missing on remove action
5. Remove confirmation dialog copy improvements

### B. WHAT THE CODE DOES

**Session 5b deferred items: ALL IMPLEMENTED.**

- Invitation flow: `app/app/team/invite/` — fully built
- Role management actions: `lib/core/manage-team-member.ts` + `lib/actions/manage-team.ts` + team-member-actions component — fully built
- Tenant settings page: `app/app/settings/page.tsx` — built (read-only display)
- Team Admin seat count enforcement: `lib/core/invite-team-member.ts:82–98` and `lib/core/manage-team-member.ts:92–114` — fully implemented

**Session 5e deferred items: none implemented.** These are UX/polish items outstanding post-5e:
1. No role change confirmation dialog exists in the team-member-actions component
2. Disabled action tooltips use inline text labels ("last admin" suffix) but no hover tooltip
3. Login error for removed users shows "suspended" message — undifferentiated
4. No success toast on remove (or other mutations)
5. Remove confirmation dialog copy is as noted in the doc

### C. KNOWN GAPS

The Session 5b section in the doc is **stale** — it still presents completed features as pending. This will mislead future readers. v2 needs to:

- Retire the Session 5b deferred items section (or move it to a "completed" changelog)
- Keep the Session 5e items as-is (genuinely outstanding)
- Consolidate all outstanding items into one place by category:
  - **UX Polish** (5e items above)
  - **Architectural debt** (middleware DB round-trip TODO in `middleware.ts:77`)
  - **Feature deferrals** (Path 2A/2B/3, Significant Claim Pathway, Knowledge Asset library, Cost tracking beyond basic capture)
  - **Scope additions** (Data migration tooling — moved from Out of Scope to In Scope)

---

---

# SUMMARY

## Architectural Contradictions Discovered

**1. Session 5b deferred items are marked as pending but are all fully implemented.**
The doc's "Session 5b Deferred Items" section reads as if invitation flow, role management, settings page, and seat count enforcement are still to be built. They are all live in the codebase. This is the most significant accuracy problem in the current doc.

**2. ClaimID format contradiction.**
The doc's Core Identifiers section (line 34–35) defines ClaimID as `[WarrantyID]-C[NNNN]`, inheriting from WarrantyID. André's current spec replaces this with `CLM-YYYY-NNNNNNN` — an independent sequence. v2 must explicitly announce this as a deliberate change from v1.

**3. "Equipment and Workmanship sub-tables" language is superseded.**
The Prototype Scope section (line 183) describes a fixed two-sub-table coverage matrix. The actual design is a per-tenant configurable warranty type list with anchor types. The v1 language implies a hard-coded schema that has been replaced.

**4. Data migration tooling scope change.**
v1 Out of Scope (line 201) explicitly lists "Data migration tooling." André is moving it into scope. v2 must un-list it.

**5. Schema.sql is the combined canonical schema, not just the initial state.**
The `schema.sql` file contains all migration changes applied (removed_at, invited_by, max_team_admins, updated get_user_tenant_id). The numbered migration files add individual changes. There are two schema sources of truth with no documented relationship between them. This is a developer-experience debt item.

---

## Decisions André Needs to Make Before v2 Drafting

**1. PM Role data model.** Is PM a `users.role` value (like 'reviewer') or an assignment column on `warranty_registrations` (or projects)? If both — which is the primary? This affects the `CHECK` constraint design, invitation flow, and RLS considerations.

**2. ALA markup percent.** 10% (Terrasmart spec) or 15% (v1 mention)? Hardcoded default or a `tenant_settings` field?

**3. Rich text editor.** TipTap vs Lexical vs Plate for custom field rich text. The stored JSON format differs between editors — this is a schema-affecting decision.

**4. Clock event infrastructure.** pg_cron on Supabase vs Vercel Cron Functions vs external scheduler. This affects how the registration prep trigger, Information Request windows, and warranty expiry events are implemented.

**5. ClaimID sequence mechanics.** `CLM-YYYY-NNNNNNN` — how is the sequence managed? Per-tenant? Global? PostgreSQL sequence? Application-level counter in `tenants.settings`? What is the zero-padding width?

**6. WarrantyID format configurability.** Currently a hardcoded display label in settings. When does this become a real per-tenant configuration, and where is the sequence counter stored?

**7. Project ↔ WarrantyRegistration FK direction.** Almost certainly `warranty_registrations.project_id` (project comes first), but needs explicit confirmation.

**8. Data migration tooling MVP scope.** Minimal viable: CSV upload with fixed field mapping? Full: Excel + field mapping UI + preview + partial-success? Where does it live — platform admin or tenant app?

**9. Custom fields Phase 1 entity scope.** Which entity types support custom fields in Phase 1? Projects only? Claims only? All entities?

**10. Warranty type anchor delete protection.** Application-layer check (preferred) or database trigger? Needs to be decided before migration is written.

---

## Risks and Concerns About the Doc Rewrite Scope

**1. This is a full document, not an update.**
Topics 7–14 require writing entirely new sections from scratch. Topics 1–6 require rewriting or significantly expanding existing sections. The v1 doc is ~250 lines. v2 will likely be 600–900 lines minimum. Scope the effort accordingly.

**2. Several topics are specification-incomplete.**
Topics 6 (Warranty Registration), 9 (Claim Intake), 10 (ALA), 12 (Custom Fields) reference André's external specs and workbooks that are not in the codebase. The v2 doc will be accurate only if those specs are incorporated before writing the relevant sections. Writing Topic 9 before the 6 workbooks are reconciled into a hybrid schema strategy risks writing a doc that needs immediate revision.

**3. Session-numbered deferred sections accumulate rot.**
Each "Session N Deferred Items" section becomes stale as work is completed. v2 should retire the session-numbered format and use a single living "Outstanding Items" section organized by category. Otherwise v3 will have the same problem.

**4. The schema is very early — the doc may get ahead of the code.**
Only 3 tables exist. v2 will document designs for ~10+ additional tables that have not been built or validated by implementation. There is a meaningful risk that implementation discoveries (e.g., "we need a project_type enum" or "the coverage end_date should be a generated column") require doc revisions within the same sprint.

**5. The "Out of Scope" section needs a replacement structure.**
The binary In Scope / Out of Scope framing does not capture the current reality: some things are fully built (team management), some are in-progress (warranty registration), some are deferred-but-planned (data migration), some are genuinely post-MVP (Path 2A/2B/3). A three-column table (MVP / Post-MVP / Explicitly Out of Scope) would be more accurate.

**6. The middleware DB round-trip is acknowledged but unresolved.**
`middleware.ts:77` has a `TODO: move to JWT claim for production`. This is a real performance concern for a high-traffic production deployment (every `/app/*` request makes a DB round-trip). v2 should surface this as a named architectural debt item with a proposed resolution path.

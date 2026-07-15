# WarrantyOS — Project Map

**Purpose:** One durable orientation document. Where the project has been, what
exists as working software, what exists only as locked design, and what the
next real build steps are. Read this first in any new chat.

**Last built:** 2026-07-15 (Chat 14), HEAD `01be4d2`, from verified git history
and direct disk reads. Phase 4 baseline is complete and Phase 3 table
construction is underway (eleven tables + one view built). Not from memory or
handoff summaries.

---

## The one-paragraph orientation

WarrantyOS is a multi-tenant SaaS warranty-governance platform for mid-sized EPC
solar/renewables operations. Its foundation is **built and working**: auth,
multi-tenancy, RLS isolation, tenant provisioning, invitations, admin UI. Its
entire operational core — claims, ALA, inspections, work authorizations, service
reports, warranty registration, O&M authorization — is **fully designed and
locked (28 architectural decisions)**. The Phase 4 hosted-database baseline (the
gate that had to precede any Phase 3 table) is **done**, and **Phase 3 table
construction has started**: the first eleven tables (`contacts`, `projects`,
`import_batches`, `tenant_id_sequences`, `warranty_registrations`,
`warranty_types`, `warranty_coverages`, `clock_events`, `internal_teams`,
`custom_field_definitions`, `claims`) are built, migrated, and committed —
along with the `warranty_coverages_effective` view — with all FK constraints
between them closed. The era is now building, not designing.

---

## Phase history (what actually happened, per git)

| Phase | What it was | State |
|-------|-------------|-------|
| Foundation | Next.js/TS/Tailwind/shadcn, Supabase, RLS, TS types | **BUILT** |
| Auth + tenancy | Auth, tenant provisioning, invitations, security hardening | **BUILT** |
| Admin UI | Platform admin, tenant admin, dashboard, team mgmt, seats | **BUILT** |
| Phase 1 | Architecture audit catalog | Done (analysis) |
| Phase 2 | Decisions 1–10 (core patterns) | Done (design) |
| Phase 0 items | Items 16/17/18 locked (contacts, defaults, feature flags) | Done (design) |
| Phase 3 | Decisions 11–28: all entity/workflow architecture | Done (design) |
| Phase 4 | Hosted-DB migration baseline | **DONE (baselined)** |
| Phase 3 build | Implementing the ~20 designed sections as migrations/code | **IN PROGRESS (11 tables + 1 view built)** |

**The design era:** commit `506b181` ("Phase 3 Tier 1 drafted in v2") began the
design era; ~60 commits of architecture prose and doc-control followed. That era
is over. The build era began with the Phase 4 baseline and the first Phase 3
migrations (005, 006).

---

## BUILT — working software on disk

- Next.js 14.2 App Router, TypeScript strict, Tailwind v4, shadcn base-nova
- Supabase: client, auth, RLS isolation, TypeScript types
- Tenant provisioning + invitation system
- Security hardening (search_path, fall-closed RLS helper)
- Platform admin UI; tenant admin (dashboard, team list, seat counts)
- **Migrations on disk: 17** — 000_baseline through 004_team_admin_management
  (auth/provisioning), plus **005_contacts**, **006_projects**,
  **007_import_batches**, **008_import_batch_fks**, **009_tenant_id_sequences**,
  **010_warranty_registrations**, **011_warranty_types**,
  **012_warranty_coverages**, **013_clock_events**, **014_internal_teams**,
  **015_custom_field_definitions**, and **016_claims** (Phase 3 tables, the FK
  constraints closing them, and the `warranty_coverages_effective` view).

Architecture sections marked **Implemented**: Standard RLS Pattern, Cache
Invalidation Pattern, Schema Source-of-Truth (foundation), plus **Unified
Contacts Directory**, **Project**, **Data Migration Tooling batch tracking**,
**ID Generation** (tenant_id_sequences), **Warranty Registration**, and
**Warranty Type Coverages** (built as 005–012).

### Phase 3 tables built (as of Chat 11)

- **`contacts`** (005) — Unified Contacts Directory (Item 16, Decisions 1/20).
  10-value `contact_type` CHECK; self-referential `parent_contact_id` and
  `linked_om_provider_id`; Standard RLS Pattern applied. Cross-row invariants
  are app-layer (per architecture), not DB constraints.
- **`projects`** (006) — the sacred root entity (Decisions 5/23, Item 17).
  Multi-source trigger model with CHECK constraints; `customer_id` is a real FK
  to `contacts(id)`; Standard RLS Pattern applied.
- **`import_batches`** (007) — Data Migration Tooling batch tracking (Decision 8),
  built exactly per its locked schema. Standard RLS Pattern applied. Migration
  008 then added the `imported_via_batch_id` FK constraints on `contacts` and
  `projects`, closing the two FKs that were briefly deferred in 005/006.
- **`tenant_id_sequences`** (009) — per-tenant gap-free WarrantyID/ClaimID
  generation (Decision 2; ID Generation section). Composite PK
  `(tenant_id, id_type)`; CHECK on `id_type`; Standard RLS Pattern (SELECT by
  tenant, writes service-role only). Backfills the two default rows for existing
  tenants. New-tenant seeding is an app-layer provisioning step, now stated
  explicitly in the arch ref's ID Generation section (built in the provisioning
  Server Action work, roadmap step 3).
- **`warranty_registrations`** (010) — parent record for one warranty agreement
  per project (Decisions 1/5/23). 1:1 with projects via UNIQUE `project_id`,
  ON DELETE RESTRICT; dual-FK assignee (contact OR tenant user) with XOR CHECK
  conditional on status; four-state status machine
  (pre_activation/assigned/active/rejected, Decision 23.7); `actual_start_date`
  nullable (Decision 23.4). Standard RLS Pattern applied. tenant-match and
  warranty_id immutability are app-layer invariants.
- **`warranty_types`** (011) — per-tenant configurable warranty type list
  (Decision 6). Case-insensitive uniqueness on `(tenant_id, lower(name))`.
  Defense-in-depth anchor protection: BEFORE DELETE OR UPDATE trigger blocks
  deleting `is_system` rows and `is_system`→false flips, matching the migration
  002 hardening precedent (plpgsql + `SET search_path = public`, no security
  definer). Backfills the two anchor types (Standard Warranty, Workmanship
  Warranty) for existing tenants; new-tenant seeding is app-layer provisioning
  (arch ref, Anchor types subsection).
- **`warranty_coverages`** (012) + **`warranty_coverages_effective` view** —
  one warranty type instantiated on one registration (Decisions 23.5/24).
  `start_date` is an immutable trigger_date snapshot; **no `end_date` column**
  (Decision 24.1). The view is the canonical read surface for
  `effective_start_date` (COALESCE of registration `actual_start_date` over
  coverage `start_date`) and `effective_end_date` (start + `term_years`), created
  `WITH (security_invoker = true)` per Decision 24.5 so underlying-table RLS is
  enforced, with view GRANTs. `CHECK term_years > 0` and
  `UNIQUE (warranty_registration_id, warranty_type_id)` enforce the locked
  architectural intent. **All effective start/end reads MUST use the view**
  (Decision 24.3) — reading `start_date`/`term_years` directly for effective
  values is architecturally prohibited.
- **`clock_events`** (013) — Clock Event Infrastructure (Decision 9; event-type
  enum extended by Item 17 and Decisions 11/19/21/25/27). Backs the
  System-Managed Clock principle: the platform manages deadlines, not reviewers.
  Three CHECKs (`event_type` ×9, `entity_type` ×7, `status` ×4). Three indexes
  using **Decision 9's verbatim names** rather than the RLS pattern's usual
  `<table>_tenant_id_idx` — the locked decision names them explicitly and wins:
  `clock_events_pending_fires_at_idx` (the load-bearing partial index on
  `fires_at WHERE status = 'pending'`, queried hourly by the cron handler),
  `clock_events_tenant_idx`, `clock_events_entity_idx`. No FK on `entity_id`:
  it is a polymorphic reference resolved by `entity_type`. **Table only** —
  pg_cron enablement and the cron handler function are separate Phase 3
  build-time work. Only future-firing events belong here; synchronous
  transitions live in the Server Action that caused them.
- **`internal_teams`** (014) — tenant-defined registry of internal teams used
  for warranty work (Decision 13). The platform commits to the operational
  pattern (n teams per tenant) without enshrining labels: team names are tenant
  data, **not** platform enum values (13.4). Soft-delete is required — historical
  `work_plans` retain `internal_team_id` when teams are retired. **Deliberate
  omissions, documented in the migration header so they are not "helpfully"
  added later:** no `is_primary` flag (13.5 is explicit), no unique constraint on
  `name` (never contemplated by Decision 13; the `warranty_types` case-insensitive
  unique exists to protect Decision 6's anchor-type invariant and does **not**
  transfer here), no membership columns (outside 13's scope).
- **`custom_field_definitions`** (015) — tenant-defined extra fields on projects,
  warranty registrations, and claims without a schema change (Decision 3, Phase 2
  decisions log; `rich_text` storage format locked by Decision 4 — TipTap /
  ProseMirror-compatible JSON). Two CHECKs: `entity_type` (the 3 Phase 1
  entities) and `field_type` (the 11 Phase 1 types, snake_case).
  Signature/multi-select/currency are Phase 2 and deliberately absent; extensible
  via migration. Definitions soft-delete via `deleted_at`: existing values stay
  queryable for historical display, the definition-list UI filters them out, and
  new entity forms stop rendering the input. **Companion table
  `custom_field_values` is NOT built** — but it is **no longer blocked**: it
  carries a `claim_id` FK, and `claims` now exists (016), so all three FK
  targets for its three-way exactly-one-non-null CHECK are present. It is the
  natural next table and closes the Custom Field System section.
- **`claims`** (016) — the claim shell (Tier 2): a customer's report against a
  live warranty registration, parented one-to-many by `warranty_registrations`
  with **ON DELETE RESTRICT** (the section's open implementation detail,
  resolved at build time per the projects-to-registrations parallel).
  `claim_id` is an **independent per-tenant sequence** — `CLM-{year}-{seq:07d}`
  from `tenant_id_sequences` — **not** derived from the parent WarrantyID
  (v1's `[WarrantyID]-C[NNNN]` form is retired). Carries Decision 27.5's
  `is_emergency` / `emergency_stabilized_at`. Claim eligibility is
  `warranty_id IS NOT NULL` on the parent (Decision 27.4); the emergency
  carve-out governs filing **timing**, not eligibility (27.7).
  **Deliberate omissions, documented in the migration header:** no UNIQUE on
  `claim_id` (gap-freeness is the ID Generation system's transactional
  row-lock, and `warranty_registrations.warranty_id` carries no unique
  either), and no DB CHECK requiring `emergency_stabilized_at` when
  `is_emergency = true` (Decision 27.6 forbids a hard platform gate on the
  customer's own self-report — `emergency_window_exceeded` is derived, never
  stored, and is Gate 1 reviewer judgment input; the requirement is
  app-layer). The `status` CHECK admits only `intake_received`, the sole value
  locked at the shell level. **Intake form fields, tokenized intake link,
  gate-level state columns, and a claimant FK/snapshot are Tier 3 and
  deliberately absent** — Claim Intake is a separate section.

---

## DESIGNED, NOT BUILT — locked architecture, remaining sections

All 28 decisions (11–28) are locked; the Cat 3 backlog is **fully resolved**.
The following architecture sections are marked **Designed** — prose exists, code
does not (contacts, projects, ID Generation, Warranty Registration, and Warranty
Type Coverages have now moved out of this list):

- Claim Intake Data Model
- Custom Field System (Decision 3) — PARTIAL: `custom_field_definitions` built
  (015); `custom_field_values` remains (unblocked — `claims` now exists)
- ALA System (Decision 19)
- Inspections Foundation (Decision 17)
- Service Report Submission (Decision 21)
- Customer Work Authorization (Decision 11)
- Work Plan Workflow (Decisions 13–16) — PARTIAL: `internal_teams` built (014);
  `work_plans` remains
- Customer-O&M Authorization (Decision 28)
- Tenant-Editable Defaults Pattern (Decision 17)
- Acknowledgment Gate Pattern (Decision 12)
- Stateless Tokenized Interaction Pattern (applied, not yet coded)
- FK + Snapshot Pattern, Feature Flag System, Database Migration Tooling, others

---

## OPEN ITEMS (tracked, not forgotten)

- **None open from the Phase 3 build so far.** The `import_batches` FK deferral
  briefly opened in 005/006 was **resolved the same session**: `import_batches`
  was already fully specified by Decision 8 (not an open design question, as was
  first assumed), so it was built (007) and the two `imported_via_batch_id` FK
  constraints on `contacts` and `projects` were added (008). Committed at
  `26133be`. No deferred FKs remain.

---

## Phase 4 baseline — DONE

The hosted-database migration baseline (Decision 22) — the gate that had to
precede any Phase 3 table — is **complete**. Migration history is established on
the hosted database; all Decision 22.8 transition criteria are satisfied.

- Hosted project ref is recorded in `supabase/PRODUCTION-REF.md`
  (`uzjivnmwedfzcgqnnhos`). Two decoy projects share the org — always verify the
  linked ref before remote ops.
- Execution record: `docs/session-handoffs/phase4-baseline-execution-record.md`.
- The local build loop (write migration → `supabase db reset` → schema
  generator → verify) is proven and is the standard groove for every subsequent
  Phase 3 table.

---

## What "left to do" actually means (the build roadmap)

1. ~~Phase 4 baseline~~ — **DONE.**
2. **Build Phase 3 schema (IN PROGRESS)** — translate the remaining designed
   sections into migrations, following the locked patterns (RLS, FK+snapshot,
   tenant-editable defaults). 11 of ~20 tables built (contacts, projects,
   import_batches, tenant_id_sequences, warranty_registrations, warranty_types,
   warranty_coverages, clock_events, internal_teams, custom_field_definitions,
   claims)
   plus the warranty_coverages_effective view.
3. **Build Phase 3 application layer** — Server Actions, tokenized flows, clock
   event dispatcher, the entity UIs. (Includes new-tenant provisioning seeding
   for both `tenant_id_sequences` and the two `warranty_types` anchor rows, per
   the arch ref's ID Generation and Anchor types subsections.)
4. **Validate the prototype** — the stated goal that unlocks recruiting a
   technical co-founder.

The design work that used to define "next step" is **done**. From here, "next
step" means code.

---

## How to not lose the thread again

- This file is the orientation anchor. Update it when a phase or milestone
  completes, not every commit.
- Doc-control on the architecture docs is **maintenance, not progress** — it does
  not move the build forward. Time-box it.
- Progress from here = migrations and code committed, not architecture prose
  revised.

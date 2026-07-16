# WarrantyOS — Project Map

**Purpose:** One durable orientation document. Where the project has been, what
exists as working software, what exists only as locked design, and what the
next real build steps are. Read this first in any new chat.

**Last built:** 2026-07-16 (Chat 16), HEAD `1cada01`, from verified git history
and direct disk reads. Phase 4 baseline is complete and Phase 3 table
construction is underway (nineteen tables + one view built). Not from memory or
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
construction has started**: the first nineteen tables (`contacts`, `projects`,
`import_batches`, `tenant_id_sequences`, `warranty_registrations`,
`warranty_types`, `warranty_coverages`, `clock_events`, `internal_teams`,
`custom_field_definitions`, `claims`, `custom_field_values`,
`inspection_types`, `inspection_triggers`, `work_plans`, `inspections`,
`work_authorization_templates`, `work_authorization_documents`,
`work_authorization_revisions`) are
built, migrated, and committed —
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
| Phase 3 build | Implementing the ~20 designed sections as migrations/code | **IN PROGRESS (19 tables + 1 view built)** |

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
- **Migrations on disk: 23** — 000_baseline through 004_team_admin_management
  (auth/provisioning), plus **005_contacts**, **006_projects**,
  **007_import_batches**, **008_import_batch_fks**, **009_tenant_id_sequences**,
  **010_warranty_registrations**, **011_warranty_types**,
  **012_warranty_coverages**, **013_clock_events**, **014_internal_teams**,
  **015_custom_field_definitions**, **016_claims**,
  **017_custom_field_values**, **018_inspection_types**,
  **019_inspection_triggers**, **020_work_plans**, **021_inspections**, and
  **022_customer_work_authorization** (Phase 3 tables, the FK constraints
  closing them, and the `warranty_coverages_effective` view).

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
  new entity forms stop rendering the input. Companion table
  `custom_field_values` is built as 017 — the section is now complete.
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
- **`custom_field_values`** (017) — one filled-in custom field value for one
  entity instance (Decision 3, **Phase 2** decisions log). Closes the Custom
  Field System section. Was blocked until `claims` (016) existed; with all
  four FK targets present it was built with **zero deferred FKs**. Typed
  nullable FKs to the three Phase 1 entities — **not** a polymorphic key —
  with a `CHECK` enforcing **exactly one non-null**, so referential integrity
  is real. **ON DELETE runs in two directions, both from locked text:**
  CASCADE on the three entity FKs (Decision 3's stated rationale for typed
  FKs is that they let CASCADE work per entity — a value is a dependent
  attribute, not an independent record), and **RESTRICT on `definition_id`**
  (definitions soft-delete and their values must stay queryable; CASCADE
  there would be exactly the cascade-destruction of auditable data the
  architecture names as the outcome to avoid). No conflict with the RESTRICT
  on 010/016 — those protect parent rows carrying independent meaning.
  `tenant_id` is denormalized (this table is the **named precedent** for that
  convention) and NOT NULL per the Standard RLS Pattern checklist. Partial
  indexes on the three entity FKs — each row populates exactly one. The
  stay-in-sync `tenant_id` invariant and `value` type-safety are app-layer.
- **`inspection_types`** (018) and **`inspection_triggers`** (019) — the first
  two canonical applications of the **Tenant-Editable Defaults Pattern**
  (Decision 17 Part A), applied to Inspections per Decision 17 Part B. Both
  carry the pattern's canonical column set **verbatim** — the six-step
  convention says an applying entity substitutes the enum name and does **not**
  vary the column set or types, so the two tables being structurally identical
  is 17.A.1's per-enum-table model working as specified, not duplication to
  factor out. Single behavioral CHECK on `lock_tier`
  (`platform_locked` | `platform_seeded` | `tenant_added`, Decision 17.A.5).
  Standard RLS Pattern applied. Seeded: 4 platform_locked inspection types
  (17.B.1), 8 platform_locked inspection triggers (17.B.2, including
  `third_party` as required by Decision 18.2). **Backfilled for tenants
  predating the migrations** — a one-time bootstrap, **not** the propagation
  17.A.3 forbids (that rule bars ongoing platform→tenant data flow *after*
  provisioning, e.g. pushing a future fifth canonical default into existing
  tenants; that remains forbidden). Without the bootstrap, existing tenants
  hold zero rows and cannot create an inspection at all, since
  `inspections.inspection_type_id` is NOT NULL. Precedent: 009 and 011.
  Idempotent via `WHERE NOT EXISTS`, **not** 011's `ON CONFLICT` — there is no
  unique index to serve as arbiter, and adding one would contradict locked
  text. **Deliberate omissions, documented in both migration headers:** no
  unique on `(tenant_id, value)` (the arch ref states value-uniqueness is an
  application-layer invariant — stated, not omitted; 011's case-insensitive
  unique protects Decision 6's anchor invariant and does **not** transfer), no
  protection trigger (Decision 17.A.6: **no PostgreSQL triggers at v1** —
  deliberately differing from 011, whose trigger is mandated by Decision 6's
  defense-in-depth requirement; different decision, different answer), and no
  CHECK tying `deleted_at` to `lock_tier = 'tenant_added'` (17.A.6 caps v1 DB
  enforcement at the lock_tier value set, NOT NULLs, and FK integrity). New-
  tenant seeding, the slugification of `label`→`value` for tenant_added rows,
  and the canonical validation helper are app-layer.
- **`work_plans`** (020) — the warrantor's **INTENT**: the planned corrective
  actions for a claim (Decisions 13/15/16; SOP 6). Customer Work Authorization
  (Decision 11) is the customer-facing **COMMITMENT** generated from that
  intent — the two entities stay deliberately separate. Built verbatim to the
  arch ref schema sketch: 22 columns, all eight SOP 6 components mapped. **Five
  CHECKs** — `execution_path` (Decision 13.2's four values, v1's Four Work Plan
  Execution Paths), `work_plan_type` (3), `status` (Decision 15.1's five
  values), plus the **two conditional path CHECKs** Decision 13.1 requires
  (`internal_team_id` non-null exactly when
  `execution_path = 'warrantor_self_performs'`; `subcontractor_contact_id`
  non-null exactly on the two subcontractor paths — **both null** on
  `customer_self_services`, where the customer-as-executor resolves through the
  claim's parent project). Standard RLS Pattern applied.
  **ON DELETE resolved at build time on all four entity FKs as RESTRICT**
  (`claim_id`, `internal_team_id`, `subcontractor_contact_id`,
  `warranty_professional_user_id`), closing four questions the arch ref had
  flagged as "Phase 3 implementation detail". Every parent soft-deletes or
  soft-removes, and the arch ref states the restraint plainly: hard-deletion
  isn't an ordinary path. Matches the 010/016 precedent. On `internal_team_id`
  RESTRICT is the **only architecturally available** clause, not merely the
  preferred one — Decision 13.3 requires soft-delete *precisely so* historical
  `work_plans` retain the FK when teams retire; CASCADE would destroy exactly
  those rows, and SET NULL would violate the conditional CHECK, leaving the row
  unrepresentable. **Deliberate omissions, documented in the migration
  header:** no UNIQUE on `claim_id` (one-to-many is locked — each Work Plan
  bounds one execution event; differs from `ala_documents` and
  `service_reports`, which DO carry UNIQUE(claim_id) because those bound the
  claim as a whole), no `work_authorization_id` FK (Decision 11 runs it the
  other way via `event_reference_id`), no `notice_of_defect_id` FK (Decision
  14.4: **no FK in either direction** — the operational sequence is read from
  claim history), no `service_report_id` FK, no customer FK, and no
  `submitted` / `in_execution` / `scheduled` / `revised` / `resent` status
  values (excluded by 15.2, 15.3, 15.4, 15.5 respectively). Parts Claims are
  excluded from this workflow entirely (Decision 16.3) — app-layer, not a DB
  constraint coupling this table to the parent's `claim_type`.
- **`inspections`** (021) — claim-level investigations into a defect's cause,
  scope, or fix (Decision 17 Part B, Decision 18). Used when a claim's
  information is insufficient to determine corrective actions, or when an
  Indistinct claim needs investigation before warranty determination. Zero,
  one, or many per claim — **no UNIQUE on `claim_id`** (an initial internal
  inspection may be followed by a third-party expert inspection if the first is
  inconclusive). **The canonical reference example for the Tenant-Editable
  Defaults role-based decision tree:** five enum-like columns spanning three
  patterns — `performed_by` and `paid_by` are platform-locked CHECK enums
  (structural axes: universal across warrantor business models, driving
  authority checks and cost-recovery routing), `inspection_type` and
  `inspection_trigger` are Tenant-Editable Defaults (categorization: values vary
  by tenant vocabulary), and `status` is a platform-locked CHECK enum
  (workflow-driver: platform code branches on it). Future v2 entities with
  multiple enum-like columns follow the same per-column reasoning rather than
  picking one uniform pattern — **do not harmonize these.** **Completes step 4
  of the Tenant-Editable Defaults six-step convention:** both FK + value
  snapshot column pairs, in the shape the pattern's "Operational table
  integration via FK + Snapshot" subsection specifies. Snapshots are captured at
  row creation and never re-synced — the FK may drift if a label is later
  edited, the snapshot cannot. **`performed_by` and `paid_by` are two orthogonal
  axes, deliberately not one conflated enum** — Audit Topic 11's three-value
  enum (internal | third_party | customer_paid) cannot express a
  claimant-funded warrantor-performed inspection, or a warrantor-performed
  inspection reimbursed by a vendor; all six combinations are operationally real
  and there is **deliberately no CHECK coupling them**. Four-value status
  machine: `open` → `in_progress` → `under_review` → `issued` (terminal on the
  happy path; some tenant vocabularies call the resulting document an NCR).
  `inspection_report` is JSONB because inspection shapes capture different
  findings — same convention as `claims.claim_type_data`. Standard RLS Pattern
  applied. **ON DELETE: RESTRICT on all three entity FKs.** `claim_id` was the
  one genuinely deferred clause ("not yet locked... a Phase 3 implementation
  detail") and resolved at build time as RESTRICT, matching 010/016/020;
  CASCADE would hard-delete audit-bearing investigations into defect causation,
  and 017's CASCADE does **not** transfer (a custom field value is a dependent
  attribute; an inspection is an independent record with its own state machine).
  The two lookup FKs were **not** deferred — the arch ref states they follow the
  lookup tables' soft-delete semantics, and RESTRICT is additionally the only
  architecturally available clause, both columns being NOT NULL (SET NULL
  illegal, CASCADE destroys history). **Deliberate omissions, documented in the
  migration header:** no `inspection_statuses` lookup table (status is a
  workflow-driver, deliberately a different pattern from the two lookup columns
  on the same table), no claimant-attendance column (Decision 18.1 — Joint
  Inspection is a non-feature at the schema level; track in JSONB), no
  `requested_by` column (Decision 18.2 — the requester axis is read from the
  trigger value), no scheduling/findings/recommendation columns, no
  cost-tracking columns (its own Tier 3 section reads `paid_by`), no custom
  field support (outside Decision 3's Phase 1 scope; JSONB is the mechanism in
  lieu), no `work_authorization_id`/`ala_id` FKs (both cross-entity
  dependencies explicitly deferred downstream), no clock_events wiring (flagged
  open), and no trigger enforcing the snapshot sync invariant (17.A.6: no
  triggers at v1). The tenant-match invariant and the canonical validation rule
  are app-layer.
- **`work_authorization_templates`**, **`work_authorization_documents`**, and
  **`work_authorization_revisions`** (022) — Customer Work Authorization
  (Decision 11): the customer-facing **COMMITMENT** generated from a Work
  Plan's **INTENT** (020). The two entities stay deliberately separate.
  **Universal blocking gate:** no on-site activity of any kind proceeds without
  an approved document for that specific event. SOP 1 names only the inspection
  case; the architecture extends the gate to all on-site activity
  intentionally — SOP 1 captured the canonical instance, not the limit.
  Enforcement is a Server Action precondition, **not** a DB constraint.
  **One-to-many with claims** — no UNIQUE on `claim_id`; each document
  authorizes one bounded event (an inspection at one date, a repair execution
  at another, a follow-up later). The deliberate contrast against
  `ala_documents` and `service_reports`, which DO carry UNIQUE(claim_id): the
  scope differs — ALA authorizes financial liability for the claim's
  investigation (once per Indistinct outcome), Work Authorization authorizes
  physical site presence for a bounded event (which recurs). Same shape as
  `work_plans`. Three CHECKs on documents: `event_type` (3), `status` (7),
  `customer_decision` (2). Templates carry the same
  templates-and-documents shape as the ALA System and Acknowledgment Gate
  Pattern, with **soft-delete required** — a template retired today may have
  generated documents last year whose `template_snapshot` must stay readable.
  **Decision 11.b resolved at build time:** `event_reference_id` is a **single
  nullable column with app-layer dispatch and NO FK** — the only candidate
  preserving the two-column shape (`event_type` + `event_reference_id`)
  Decision 11 locks *by name*. A junction table would delete that column and
  permit many-to-many, which this section forbids; typed per-event FK columns
  would also delete it, and 017's typed-FK precedent does **not** transfer
  because Decision 3 chose typed FKs where no locked column name was at stake.
  In-repo precedent: `clock_events.entity_id` (013), also FK-less and resolved
  by `entity_type`. **ON DELETE on all five FKs:** RESTRICT on `claim_id`,
  `template_id`, and `revised_by_user_id`; **CASCADE** on
  `work_authorization_document_id` (a revision is a dependent attribute of its
  document, not an independent record — 017's entity-FK reasoning, deliberately
  differing from the RESTRICTs); no clause on `event_reference_id`, which
  carries no FK. Fifth canonical use of the Stateless Tokenized Interaction
  Pattern; when a tenant configures an Acknowledgment Gate for `gate_purpose =
  'work_authorization'` (Decision 12), that gate is an interstitial on
  `customer_token` — **there is no second token**. The signature artifact is
  `signer_name_typed` + `authorization_acknowledged`, deliberately distinct
  from ALA's Accept/Decline + atomic signature + recant window (Decision 19):
  different stakes, different ceremony; neither pre-decides the other.
  Revise-and-resend is the **primary** recovery path for a denial, not
  withdraw-and-recreate; the customer sees the full revision history on resend.
  **Policy names use `<table>: tenant read`** — the convention's usual wording
  exceeded PostgreSQL's 63-byte identifier cap on these table names and was
  being silently truncated mid-word; the arch ref documents the convention as a
  shape (`<table>: <who> can <action>`), not a fixed string. **Deliberate
  omissions, documented in the migration header:** no partial UNIQUE on
  `is_default` (app-layer, parallel to ALA's and Acknowledgment Gate's
  identical open question), no customer FK and no O&M provider FK (direct field
  capture is Decision 11's locked schema), no `work_plan_id` FK
  (`event_reference_id` IS that reference), no DB CHECKs for the
  denial/signature/conditional-field invariants (17.A.6 caps v1 DB
  enforcement), and no `created_at`/`updated_at` on revisions (the locked
  sketch carries only `revised_at` — built verbatim). O&M Provider approval is
  blocked at v1 without a signed `om_authorization_documents` row (Decision
  28); app-layer.

---

## DESIGNED, NOT BUILT — locked architecture, remaining sections

All 28 decisions (11–28) are locked; the Cat 3 backlog is **fully resolved**.
The following architecture sections are marked **Designed** — prose exists, code
does not (contacts, projects, ID Generation, Warranty Registration, and Warranty
Type Coverages have now moved out of this list):

- Claim Intake Data Model
- ALA System (Decision 19)
- Service Report Submission (Decision 21)
- Customer-O&M Authorization (Decision 28)
- Tenant-Editable Defaults Pattern (Decision 17) — PARTIAL: the canonical lookup
  shape is built twice (`inspection_types` 018, `inspection_triggers` 019), and
  step 4 is now built — the operational table `inspections` (021) carries both
  FK + value snapshot column pairs. Step 5 of the pattern's own six-step
  convention remains: the canonical validation helper, which is application-
  layer and does not yet exist. The Status moves to `Implemented (schema)` only
  when step 5 lands. `Inspections Foundation` has left this list entirely —
  built as 021.
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
   tenant-editable defaults). 19 of ~20 tables built (contacts, projects,
   import_batches, tenant_id_sequences, warranty_registrations, warranty_types,
   warranty_coverages, clock_events, internal_teams, custom_field_definitions,
   claims, custom_field_values, inspection_types, inspection_triggers,
   work_plans, inspections, work_authorization_templates,
   work_authorization_documents, work_authorization_revisions)
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

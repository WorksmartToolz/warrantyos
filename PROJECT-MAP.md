# WarrantyOS — Project Map

**Purpose:** One durable orientation document. Where the project has been, what
exists as working software, what exists only as locked design, and what the
next real build steps are. Read this first in any new chat.

**Last updated:** 2026-07-29 (Chat 28), HEAD `0bf3713`, from verified git history
and direct disk reads. Phase 4 baseline is complete and Phase 3 table
construction is COMPLETE for every table-bearing section (twenty-nine tables +
one view + three functions built). Chat 20 built the last two: 028
(`service_reports`, one table) and 029 (`om_authorization_documents` +
`om_authorization_templates`, two tables). The table count did not change at
027: it added 25 columns to the `claims` shell rather than creating a table.
Not from memory or handoff summaries.

---

## The one-paragraph orientation

WarrantyOS is a multi-tenant SaaS warranty-governance platform for mid-sized EPC
solar/renewables operations. Its foundation is **built and working**: auth,
multi-tenancy, RLS isolation, tenant provisioning, invitations, admin UI. Its
entire operational core — claims, ALA, inspections, work authorizations, service
reports, warranty registration, O&M authorization — is **fully designed and
locked (31 architectural decisions)**. The Phase 4 hosted-database baseline (the
gate that had to precede any Phase 3 table) is **done**, and **Phase 3 table
construction has started**: the first twenty-six tables (`contacts`, `projects`,
`import_batches`, `tenant_id_sequences`, `warranty_registrations`,
`warranty_types`, `warranty_coverages`, `clock_events`, `internal_teams`,
`custom_field_definitions`, `claims`, `custom_field_values`,
`inspection_types`, `inspection_triggers`, `work_plans`, `inspections`,
`work_authorization_templates`, `work_authorization_documents`,
`work_authorization_revisions`, `acknowledgment_gate_templates`,
`acknowledgment_gate_records`, `tenant_holidays`, `ala_templates`,
`ala_documents`, `ala_document_revisions`, `notices_of_defect`) are
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
| Phase 3 build | Implementing the ~20 designed sections as migrations/code | **IN PROGRESS (29 tables + 1 view + 3 functions built — all table-bearing sections complete)** |

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
- **Migrations on disk: 27** — 000_baseline through 004_team_admin_management
  (auth/provisioning), plus **005_contacts**, **006_projects**,
  **007_import_batches**, **008_import_batch_fks**, **009_tenant_id_sequences**,
  **010_warranty_registrations**, **011_warranty_types**,
  **012_warranty_coverages**, **013_clock_events**, **014_internal_teams**,
  **015_custom_field_definitions**, **016_claims**,
  **017_custom_field_values**, **018_inspection_types**,
  **019_inspection_triggers**, **020_work_plans**, **021_inspections**,
  **022_customer_work_authorization**, **023_acknowledgment_gate**,
  **024_tenant_holidays**, **025_ala_system**,
  **026_notices_of_defect**, **027_claim_intake**,
  **028_service_report_submission**, and **029_customer_om_authorization**
  (Phase 3 tables, the FK
  constraints closing them,
  the `warranty_coverages_effective` view, and the three business-day calendar
  functions).

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
  locked at the shell level. **UPDATE (Decision 30, migration 030, Chat 25/26):
  the Six Gates value set is now DRAFTED AND LOCKED** — the `status` CHECK carries
  twelve values (six gate stages + five outcomes); transitions/actors live in the
  C10 Server Actions, not the DB. The sentence that follows described the pre-030
  state and is retained as history. **UPDATE (Decision 31, Chat 27): the C10 claim-progression Server Actions are now BUILT** (`lib/core/claim-progression.ts` + `lib/actions/claims.ts`, `85f7f1b`) — the transition map, actor authorization, the ALA data precondition (19.7), and the escalation-verdict tenant setting all live there per Decision 30.3.
  **Intake form fields and the tokenized intake link are no longer absent:
  migration 027 built them** (see below). Of the shell's four deliberate
  omissions, gate-level state columns remain absent on purpose — Decision 12's
  `claim_submission` gate is an *interstitial* on 027's `intake_token`, with the
  gate's own rows living in 023 — and the "claimant FK/snapshot" is discharged
  by 027's `submitter_contact_id` + `submitter_name` / `submitter_email`
  snapshot pair.
- **`claims` intake data model** (027) — the Tier 3 section 016 deferred to,
  built as 25 columns on the shell, no new table. The arch ref's **hybrid
  strategy** is the whole shape: hard columns for what is universal across every
  claim_type and tenant; `claim_type_data` JSONB for **platform-shaped**
  variation (varies by claim_type; the field names are fixed by the platform);
  and custom fields (015/017, `entity_type = 'claim'`) for **tenant-shaped**
  variation (whether a field exists, what it is called, and its options are all
  the tenant's). The arch ref names the tell: a platform field has a fixed name,
  a tenant field is named in the tenant's own operational language. LOTO is the
  worked example — the categorical `loto_requirement` is a hard column; *who
  specifically performs LOTO* is a custom field.
  **Only one of seven `claim_type_data` shapes is settled** (replacement_parts,
  from Workbook 2). The other six are deliberately unsettled at the
  architectural layer and **need no migration when they land** — JSONB shape is
  validated app-layer at write time, the same convention as `clock_events`
  payload. Do not "helpfully" invent them.
  **Three flagged Phase 3 implementation details, resolved at build time:**
  the intake token is a column pair **on the claim row** (`intake_token` /
  `intake_token_expires_at`), per the Stateless Tokenized Interaction Pattern's
  "shape to copy, not shared store" rule — three-for-three precedent (022's
  `customer_token`, 025's `claimant_token`, 026's `recipient_token`), and no
  UNIQUE, because `invitations.token` (001) is unique only as a *shared store*
  where the token is the lookup key. `supporting_documents` is **JSONB, not a
  child table** — the locked semantics store the *categories* a claimant
  declares they are providing, a checklist with no file, no URL, and no join
  surface; actual file storage is unaddressed anywhere in v1. The O&M Provider
  capture is **direct text, not an FK** (`om_provider_company` /
  `om_contact_name` / `om_contact_phone` / `om_contact_email`, mirroring 022
  exactly) — the arch ref's open-questions block *proposes* an FK but does not
  lock it, while 022's committed header states the governing position and names
  Claim Intake as its parallel.
  **THE NAMING COLLAPSE — do not re-add.** The arch ref's hard-column sketch
  lists `priority_emergency`; it was **not built and does not exist**. It is the
  older name for the same flag 016 already built as `is_emergency` (Decision
  27.5); this arch-ref section pre-dates Decision 27. One flag, not two. A
  doc-control note above the frozen sketch records this (Convention 7).
  **Deliberate omissions:** no `claim_intake_tokens` table, no gate state, no
  `priority_emergency`, no `claim_attachments` child table, no DB CHECK coupling
  `emergency_details` to `is_emergency` or `offline_condition_explanation` to
  `equipment_status` (17.A.6 caps v1 DB enforcement — the same restraint 016
  applies to `emergency_stabilized_at`), no DB validation of `claim_type_data`
  against `claim_type`, and **no customer / project / WarrantyID /
  service-address columns** — Workbook 1's five "auto-populated" fields are all
  reachable by join, and duplicating them would create sync surfaces where none
  is needed.
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
  are app-layer. **UPDATE (Decision 32, Chat 28): the C2 inspection-progression
  Server Actions are now BUILT** (`lib/core/inspection-progression.ts` + the
  extended `lib/actions/inspections.ts`, `0f7bfa9`) — the forward-only status
  machine described above (`open → in_progress → under_review → issued`) lives
  there, app-layer per 17.A.6, single `operational` authz class, no system path.
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
- **`acknowledgment_gate_templates`** and **`acknowledgment_gate_records`**
  (023) — the Acknowledgment Gate Pattern (Decision 12), a **Tier 1
  platform-wide pattern**: the pre-form acknowledgment mechanism any tokenized
  customer interaction can opt into, so that interactions do not each invent
  their own. Tenant-defined content (the warrantor's legal/safety/operational
  language) behind platform architecture. Same templates-and-records shape as
  the ALA System and Customer Work Authorization (022), with **soft-delete
  required on templates** — records captured last year must stay readable and
  their `template_id` must still resolve. Phase 1 `gate_purpose` values:
  `claim_submission`, `work_authorization`; extensible exactly like
  `clock_events.event_type` (Decision 9). **Optional per tenant per purpose
  (12.3)** — the platform supports gates natively but does not mandate them; a
  tenant whose external compliance processes already handle the equivalent
  acknowledgment leaves the purpose unconfigured and their customers proceed
  straight to the form. **Decision 12.6 resolved at build time:**
  `authorized_entity_id` is a **single polymorphic column with app-layer
  dispatch and NO FK** — the only candidate preserving the two-column shape
  (`authorized_entity_type` + `authorized_entity_id`) Decision 12 locks *by
  name* in both schema sketches. A junction table would delete both columns and
  permit many-to-many, which 12.4's one-gate-per-entity commitment forbids;
  typed per-entity FK columns would also delete them, and 017's typed-FK
  precedent does **not** transfer because Decision 3 chose typed FKs where no
  locked column name was at stake. **The same reasoning and the same answer as
  Decision 11.b on 022** — the structurally identical question; the deciding
  test in both is whether the locked text names the column. In-repo precedent:
  `clock_events.entity_id` (013). **Third consecutive polymorphic reference
  answered the same way — a pattern, not a coincidence.** One deliberate
  difference from 022: `authorized_entity_id` is **NOT NULL** where
  `event_reference_id` is nullable — each built verbatim to its own locked
  sketch, and an acknowledgment is by definition an acknowledgment *of*
  something. **Do not harmonize.** **ON DELETE: RESTRICT** on
  `records.template_id` (templates soft-delete; CASCADE would destroy the audit
  record of what a customer agreed to — parallel to 022's `template_id` and
  017's `definition_id`); no clause on `authorized_entity_id`, which carries no
  FK. **No seed and no backfill — deliberately inverting 018/019**, whose
  backfill was mandatory because `inspections.inspection_type_id` is NOT NULL
  and a tenant with zero rows could not create an inspection at all. The inverse
  holds here: 12.3 makes gates optional, **zero rows is a valid and expected
  steady state**, and platform-seeded gate content would be the platform
  imposing legal/safety language on tenants — precisely what 12.3 forbids.
  **Deliberate omissions, documented in the migration header:** no FK on
  `authorized_entity_id` (both targets — `claims` 016 and
  `work_authorization_documents` 022 — now exist, so this is an architectural
  choice, not a deferral for want of a target), no partial UNIQUE on
  `is_default` (app-layer; parallel to 022's and ALA's identical flags — three
  parallel flags, one answer), no UNIQUE on
  `(authorized_entity_type, authorized_entity_id)` (12.4's one-gate-per-entity
  is enforced by 12.7 step 3's Server Action existence check, the mechanic the
  locked text specifies; 17.A.6 caps v1 DB enforcement), **no second token, no
  second `expires_at`, no second `consumed_at`** (the gate is an interstitial on
  the protected entity's existing tokenized link — 022's `customer_token` — not
  its own tokenized interaction), no expiration or stale-out on records (an
  acknowledgment is valid for the protected entity's lifetime), no `updated_at`
  and no `deleted_at` on records (frozen audit artifacts, never edited or
  retired — the locked sketch carries `created_at` only), no custom field
  involvement (gates are tenant-defined documents, not fields on entities), and
  **no CHECK coupling `acknowledger_name` to `requires_typed_name`, nor
  `authorized_entity_type` to `gate_purpose`** — both pairs straddle the
  template/record FK, so a DB CHECK cannot see both sides; app-layer per 17.A.6.
  `acknowledged_at` is NOT NULL with **no default**, unlike `created_at` on the
  same table — built verbatim to the locked sketch; the Server Action sets it at
  12.7 step 5. **The application layer is not built:** 12.7's gate mechanics —
  the Server Action that renders or skips the gate and inserts the record on
  submission — remain, which is why the Status is `Implemented (schema)`.
- **`tenant_holidays`** (024) — the per-tenant holiday calendar (Decision 25.3)
  backing business-day math: the platform's business-day windows skip Saturdays,
  Sundays, and any date in this table for the tenant in question. **Its own
  migration, separate from the ALA tables**, per the 018/019
  independent-siblings convention — it carries no FK to any ALA table and none
  references it; the relationship is app-layer math only. ALA is the calendar's
  first consumer, not its owner. **25.3 extends the Tenant-Editable Defaults
  *philosophy*** (platform seeds at provisioning, tenant owns forever after, no
  propagation — 17.A.3) **but explicitly not its *mechanics***, because no
  operational table references a holiday by FK: hence no `lock_tier`, no
  `is_system`, no protection trigger, no value/label pair, no `sort_order`. A
  tenant may delete every row and the platform is fine with it — business-day
  math then skips weekends only. **The seed is a starting default, not a model
  of what warrantors observe.** No two companies recognize the same set (some
  close Good Friday, some skip Columbus Day, some add company days), so the
  platform seeds the U.S. federal list as the one defensible starting point and
  the schema deliberately offers nothing that resists editing. **The seed applies
  the federal observed-shift rule** (Saturday → preceding Friday, Sunday →
  following Monday) to the five fixed-date holidays — what OPM publishes and
  what most U.S. warrantors follow, so most tenants edit nothing. **Tenant policy
  variance needs no schema support:** `holiday_date` stores a concrete *observed*
  date, so taking the Monday instead of the Friday is a row edit, taking both
  adds a row, taking neither deletes. **The dates are computed, not enumerated:**
  `federal_holidays_for_year(integer)` plus helpers `nth_weekday_of_month` and
  `last_weekday_of_month` (Memorial Day is the *last* Monday of May, which the
  Nth helper cannot express) — all three IMMUTABLE, reading no tables. **A
  literal date list was rejected because it needs an end year, and an end year
  fails *silently*** — business-day math would stop skipping holidays past the
  cliff with no error and no alert. The function has no cap. These are callables,
  not triggers, so 17.A.6's no-triggers-at-v1 restraint does not bar them;
  conventions per 011 (plpgsql, `set search_path = public`, no security definer).
  **Verified in Postgres rather than asserted:** all 11 dates match OPM for 2026,
  the backfill produces exactly 121 rows (11 × 11 years), and re-running inserts
  0. **Year-boundary behavior is correct, not a defect** — when Jan 1 falls on a
  Saturday the observed date shifts back into the prior year, so
  `federal_holidays_for_year(2028)` returns `2027-12-31`; callers must not assume
  year N's holidays fall within year N. **The 2026–2036 backfill is a starting
  horizon, not a cap:** a rolling annual top-up calls the same function to extend
  every tenant's list forward, but it **requires pg_cron, which is not yet
  built** — so until that job lands the horizon is in fact what the backfill
  wrote. **A real dependency, recorded rather than assumed away.** New-tenant
  seeding is an app-layer provisioning step calling the same function — the same
  convention as `tenant_id_sequences` (009) and the `warranty_types` anchor rows
  (011), and what 25.3 means by "at provisioning".
- **`ala_templates`**, **`ala_documents`**, and **`ala_document_revisions`**
  (025) — the ALA System (Decisions 19/25/26): the Owner's Consent and
  Assumption of Liability Agreement, which a claimant signs when a claim's
  causation or ownership is unclear, accepting financial responsibility for the
  investigation if the defect is ultimately found outside warranty scope. The
  SOPs call this the Indistinct Claims workflow. **An ALA exists only when a
  claim's outcome is Indistinct — most claims never have one.** Third and final
  instance of the templates-and-documents shape (after 022 and 023), with
  soft-delete required on templates. **UNIQUE on `claim_id` — and Decision 26.2
  explicitly refuses to reopen it:** one row per claim, always. The deliberate
  contrast against `work_authorization_documents` (022), which is one-to-many
  because it authorizes a bounded, recurring on-site event; an ALA authorizes
  financial liability for the claim's investigation, once per Indistinct
  outcome. Content changes go through revise-and-resend (Decision 26), never a
  second row. **`ala_documents` carries 20 columns, not the arch ref sketch's
  19** — `overdue_flagged_at` is named in **Decision 25.4's prose only**, and
  the sketch predates it; the sketch was corrected in the same commit so the
  two locked sources agree. **No `status` column, deliberately (19.7):** the
  three-state machine is **derived** — unsigned (`claimant_decision` null AND
  `signed_at` null), signed (`'accepted'` AND `signed_at` non-null), declined
  (`'declined'` AND `signed_at` null). Those three are the complete state set;
  `overdue_flagged_at` is a **fourth orthogonal signal layered on the unsigned
  state, not a fourth state** (25.4) — a pure marker that changes neither
  decision nor signature and does **not** unblock the Indistinct gate. Silence
  never becomes a decision (25.8): there is no auto-terminal state; the flag
  persists until the warrantor re-issues (25.7) or escalates manually.
  `markup_percent_snapshot numeric(4,3)` is the **first non-uuid/text/jsonb/
  bool/timestamptz/date type in Phase 3**, freezing Decision 7's 10% default at
  generation; the 0–0.50 bounds are app-layer (the type constrains precision,
  not the architectural bounds). `signature_method` is a platform-locked CHECK
  enum **with a default** — only 022's `status` precedes that shape — captured
  from the tenant's setting at row creation and frozen for the document's
  lifetime. **ON DELETE, all from precedent:** RESTRICT on `claim_id`
  (010/016/020/021/022 — the arch ref defers only the clause, naming the
  parallel) and `template_id` (022/023/017); **CASCADE** on
  `revisions.ala_document_id` (a revision is a dependent attribute, not an
  independent record — 022's revisions, identical shape); RESTRICT on
  `revised_by_user_id` (022). **No `alter table` was needed:** `clock_events`
  (013) already carried `ala_document`, `ala_response_overdue`, and
  `ala_decline_window_expired`. **Deliberate omissions, documented in the
  migration header:** no `status` column (see above), no counter-signature
  column (the ALA is one-sided consent — a warrantor signature would change the
  instrument), no partial UNIQUE on `is_default` (**the third parallel flag**,
  after 022's and 023's — identical question, identical app-layer answer), no
  DB CHECK for "accepted ⇒ `signed_at` non-null" (Decision 19.1's atomic
  accept-and-signature write is a Server Action invariant; 17.A.6 caps v1 DB
  enforcement), no CHECKs coupling the signature artifacts to
  `signature_method`, no `created_at`/`updated_at` on revisions (the locked
  26.1 sketch carries `revised_at` only — built verbatim, as with 022), no
  `deleted_at` on documents (an audit-bearing legal artifact for the warranty
  horizon; revise-in-place is the content-change path) or on revisions (frozen
  audit artifacts), no DB enforcement of the markup bounds, no second token for
  an Acknowledgment Gate (an interstitial on `claimant_token`, per 022's rule),
  and no holiday FK — business-day math reads `tenant_holidays` (024)
  app-layer at the moment `fires_at` is computed, **which is exactly why 024
  and 025 are separate migrations.** Revising a **signed** ALA is blocked at v1
  (26.4). **The application layer is not built** — document generation at the
  Indistinct outcome, the tokenized Accept/Decline atomic write, the
  dispatcher's overdue flagging, re-issue, and revision capture all remain,
  which is why the Status is `Implemented (schema)`.
- **`notices_of_defect`** (026) — the Notice of Defect (Decision 14): the
  warrantor's formal notification to a believed-responsible party, "this defect
  is yours; respond with acceptance/rejection." **An audit artifact of official
  notification** — the purpose is that the party believed responsible has been
  officially notified and that is a matter of record, separate from any
  downstream execution work. **v1 modeled this as two fields on the Work Plan**
  (`notice_of_defect_sent`, `notice_of_defect_response`); the Phase 1 audit
  flagged that as structurally wrong — a Notice of Defect is a document sent to
  a party, with its own lifecycle, response, and audit trail. Correcting it is
  the entity's whole point. **The architecture reference has NO Notice of
  Defect section** — its Work Plan cross-reference says so explicitly ("its own
  section, drafted in a future session") and points to **Decision 14 in the
  Phase 3 decisions log, which holds the locked spec**. Built verbatim to that
  sketch: 20 columns. **No FK to `work_plans` in either direction (14.4)** —
  the Notice's architectural responsibility ends at response capture; some
  Notices lead to Work Plans, some never do (the subcontractor remediates
  independently, or the matter is contractually outside warrantor
  coordination). "Which Notice led to this Work Plan" is answered by reading
  claim history, not by traversing an FK. **One-to-many with claims (14.1)** —
  no UNIQUE on `claim_id`; zero when the defect is the warrantor's own
  responsibility, many as the responsibility picture evolves. Same shape as
  020/022; the contrast against 025 and service_reports. **No revisions child
  table (14.3), deliberately unlike 022 and 025:** acceptance is not closure —
  a recipient may accept, get to site, and shift position — but such changes
  become **NEW events** (a new Notice to another party, a claim status
  transition, an escalation), never revisions to this row. The original
  response stays frozen testimony. Three-value `response_status`
  (pending/accepted/rejected) with **no `withdrawn`**: a matter of record is not
  un-sent. **Dual-FK recipient with an UNCONDITIONAL XOR (14.2)** —
  deliberately differing from 010's dual-FK assignee CHECK, which gates on
  status (both null when `pre_activation`); that conditionality is Decision
  23.7's four-state registration machine, which this entity has no analogue to.
  A Notice without a recipient is not a thing that exists. The `<>` idiom
  transfers from 010; the status gate does not — **do not harmonize.** FK +
  Snapshot on the recipient (three `*_snapshot` columns, frozen at notification
  and never re-synced — who was actually notified, at that address, on that
  date). Tokenized recipient response per 14.5; `expected_response_date` NOT
  NULL per 14.7. **Unlike 025, this migration DID need an `alter table`:**
  `clock_events` (013) carried neither value, so 026 adds `event_type`
  `notice_of_defect_response_overdue` and `entity_type` `notice_of_defect`.
  14.9's "seventh" ordinal is **stale** — Decisions 25/27 landed after 14, so
  the built enum already held nine; the value is locked, the count was written
  before the later decisions existed. **14.10 discharged with no migration:**
  `vendor_contact` already exists in the built `contact_type` enum (005), and
  `other` covers original installers per 14.10's own "or equivalent".
  **Deliberate omissions, documented in the migration header:** no
  `work_plan_id` FK, no revisions table, no UNIQUE on `claim_id`, no
  `withdrawn` status, **no templates table** (unlike 022/023/025 — 14.8 puts
  the warrantor's message in `notification_message` per-Notice; the
  templates-and-documents shape does not transfer), no separate sent-status
  column (`notified_at` NOT NULL records it), no CHECK coupling response
  columns to `response_status`, no CHECK coupling snapshots to their FK (that
  would defeat the point of a snapshot), and no Parts Claim exclusion CHECK
  (Decision 16.5 is app-layer, same treatment as 020's identical 16.3
  exclusion).

---

- **`service_reports`** (028) — the Warranty Service Report (Decision 21 +
  the arch ref's "Service Report Submission" section): the structured record
  of completed repair work, the bridge between Work Plan execution and claim
  closure. **One report per claim (claim_id UNIQUE)** — joins `ala_documents`
  (025) as UNIQUE-per-claim, the deliberate contrast against 020/022/026.
  **Submitter dual-FK with a CONDITIONAL XOR gated on `submitted_at`** — both
  null in pre-submission draft, exactly one non-null when submitted. This is
  010's conditional shape, **NOT 026's unconditional one** — a service report
  has a draft state, a Notice of Defect does not. 026's header says DO NOT
  HARMONIZE about exactly this, and it cuts both ways. **`submission_token`**
  pair (the subcontractor's tokenized link) resolved by the Stateless
  Tokenized Interaction Pattern's "shape to copy, not shared store" law — the
  arch-ref schema block lists only the customer token, the submitter link was
  prose-flagged, and pattern law (not a new decision) puts a column pair on
  the row, mirroring 026/025/022. Distinct from this table's own
  `customer_review_token`. **Seven universal SOP content items** as uniform
  hard-columns + JSONB (the opposite of `claim_type_data`'s per-discriminator
  variation). **Customer review = two-value `customer_decision`
  (accepted | disputed) + `accepted_by_acquiescence` boolean** — silence-
  acceptance is accepted-with-provenance, not a third enum value, so
  downstream surfaces handle one state, not two. **No `clock_events` alter:**
  026 already landed `service_report_response_due` + `service_report`.
  Decision 21's window config is provisioning-layer only
  (`tenants.settings.service_report_response_days` + the
  `service_report_acquiesce_window` feature flag) — **zero columns on this
  table**, and **no window snapshot column** (21.7: derivable from `fires_at`
  minus `issued_at`). **Deliberate omissions:** no `work_plan_id` FK
  (one-to-one through the claim), no subcontractor company columns (reachable
  via the contact FK), no closure-notice fields, no reviewer-authority
  columns (Server-Action role check).
- **`om_authorization_documents` + `om_authorization_templates`** (029) — the
  Customer-O&M Authorization (Decision 28): the customer's signed
  authorization for an O&M Provider to act as their agent on ONE specific
  binding-commitment event (an ALA acceptance, a Work Authorization approval,
  or a Service Report review). **PER-EVENT, not standing** — this is a
  substantive scope departure that **supersedes Decision 20.8's** standing
  per-customer model; sign-once-per-event, closing when the event closes, no
  persistence across events even for the same customer and O&M relationship
  on the same day. **Polymorphic `event_type` + `event_reference_id`** over
  `ala_documents` / `work_authorization_documents` / `service_reports`, with
  **NO database FK on `event_reference_id`** — 022's exact app-layer shape,
  precedent `clock_events.entity_id` (013). This is the
  executes-clean-≠-correct property stated plainly: the migration applies
  even though the reference points across tables with no DB enforcement;
  integrity is a Server-Action concern. **Four-value status:** unsigned |
  signed | closed | stale — **no `voided`, no `superseded`** (28.5 eliminates
  both: a provider switch reroutes an unsigned row or leaves a signed one
  untouched; reopening always creates a new row under 28.3). **One-to-many
  with claims, no UNIQUE** — and no UNIQUE on `(event_type,
  event_reference_id)` either, because 28.3 requires a reopened event to
  create a brand-new row for the same reference; "one per event" is an
  app-layer invariant (one non-terminal row), not a DB constraint.
  **`linked_om_provider_id` captured at row creation, not derived live**
  (28.4) — a signed row is permanent proof of who was authorized, and across
  every event these fields collectively ARE the audit trail (28.10: no
  dedicated change-log table). **Seventh canonical token use.** The template
  carries **`created_at` only, no `updated_at`** — the locked sketch's column
  set, built verbatim (an applying table does not vary it). **No arch-ref
  section** (Chat 18's Notice-of-Defect precedent): the decisions log holds
  the spec, the migration header the rationale, this map the gap record.

## DESIGNED, NOT BUILT — locked architecture, remaining sections

All 28 decisions (11–28) are locked; the Cat 3 backlog is **fully resolved**.
The following architecture sections are marked **Designed** — prose exists, code
does not (contacts, projects, ID Generation, Warranty Registration, Warranty
Type Coverages, Claim Intake Data Model, Service Report Submission, and
Customer-O&M Authorization have now moved out of this list — the last three
built as 027, 028, and 029 respectively):

- Tenant-Editable Defaults Pattern (Decision 17) — APP-LAYER COMPLETE (UI pending): the canonical lookup
  shape is built twice (`inspection_types` 018, `inspection_triggers` 019), and
  step 4 is now built — the operational table `inspections` (021) carries both
  FK + value snapshot column pairs. Step 5 of the pattern's own six-step
  convention is now built — the canonical validation helper,
  `validateTenantEditableDefaultsReference` (`lib/core/tenant-editable-defaults.ts`),
  landed in Chat 22. The pattern's first consuming Server Action is now built — the inspection write-path (`lib/actions/inspections.ts` -> `lib/core/inspections.ts`, 2c76cf0, Chat 23), the reference shape for all future consumers. The lookup-table admin CRUD is now built — create / rename / disable / enable / soft-delete with the full lock_tier permission matrix (17.A.5), value auto-slugified once at create with app-layer uniqueness (arch-ref 6749-6752), team_admin governance gate (`lib/actions/lookup-defaults.ts` -> `lib/core/lookup-defaults.ts`, 15a6779, Chat 23). The pattern application layer is now complete; only its admin UI surface remains (roadmap F10), which is why this is APP-LAYER COMPLETE rather than removed from this list. `Inspections Foundation` has left this list entirely —
  built as 021. `Acknowledgment Gate Pattern` has also left this list entirely —
  built as 023.

- Claim Progression (C10, Decision 31) — BUILT (UI pending): the claim-lifecycle
  Six Gates status machine (Decision 30 / migration 030's twelve-value enum). The
  transition map + authorized actors live in the Server Action layer per Decision
  30.3, not the DB. `lib/core/claim-progression.ts` + `lib/actions/claims.ts`
  (`85f7f1b`, Chat 27). Recovered from SOP 1 + the Denied/Escalated SOPs + the two
  Denial-Escalation workbooks. Carries the ALA data precondition (19.7:
  indistinct_ala_required advances only when the ALA is signed), a per-tenant
  escalation-verdict authorized role (`tenants.settings.escalation_verdict_authorized_role`,
  default team_admin — the FIRST built settings-key reader), and a system entry
  point (`transitionClaimStatusAsSystem`) for the two clock-driven transitions the
  B-layer will fire. Denial is early-gate only; the map keeps later edges a
  one-line addition. Only its UI surface remains.
- Inspection Progression (C2, Decision 32) — BUILT (UI pending): the inspection
  status machine (migration 021's four-value `status` enum). Forward-only linear
  chain `open → in_progress → under_review → issued`, `issued` terminal — the 021
  status comment commits to no backward transitions. The transition map + authz
  live in the Server Action layer per Decision 17.A.6 (no triggers at v1), not the
  DB. `lib/core/inspection-progression.ts` + the extended `lib/actions/inspections.ts`
  (`0f7bfa9`, Chat 28). ONE authorization class — `operational` (reviewer OR
  team_admin), identical to the inspection write-path. Unlike C10: NO
  escalation-verdict class (inspections carry no tenant verdict) and NO system path
  (021 flags inspection clock_events wiring as open, so no clock-driven transition
  exists to fire — `transitionInspectionStatusAsSystem` deliberately not written).
  Introduced zero new decisions; every element traced to 021 + the write-path +
  C10. Only its UI surface remains.
- Feature Flag Reader (D2, Decision 33) — BUILT (toggle UI pending): the
  single-source-of-truth helper `isFeatureEnabled(tenantId, feature) → boolean`
  (`lib/core/features/is-feature-enabled.ts`) plus its provisioning defaults
  (`0bf3713`, Chat 28). Storage is JSONB `tenants.settings.enabled_features` —
  the arch-ref part-1 open fork EXERCISED as the named "lighter starting point,"
  NOT foreclosed: the `tenant_features` table upgrade stays available behind the
  helper (changes only its internals, no caller), its trigger condition recorded
  in Decision 33.2. Three Phase-1 flags (`epc_workflow`, `supply_only_workflow`,
  `service_report_acquiesce_window`), all seeded ENABLED at provisioning
  (opt-out model, arch-ref part 4) — this replaced the prior "intentionally NOT
  seeded here" deferral in `provision-tenant.ts`. Fails closed (absent/malformed
  → false). Typed to a flag union so an unknown flag is a compile error. The
  platform-admin toggle surface (part 3) is Phase 4 / roadmap. Introduced zero
  new decisions; the fork was resolved against the arch-ref's own guidance.
- Stateless Tokenized Interaction Pattern (applied, not yet coded)
- FK + Snapshot Pattern, Database Migration Tooling, others

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
   tenant-editable defaults). 29 tables built — the original "~20" estimate
   undercounted, since several sections carry three tables each (contacts,
   projects,
   import_batches, tenant_id_sequences, warranty_registrations, warranty_types,
   warranty_coverages, clock_events, internal_teams, custom_field_definitions,
   claims, custom_field_values, inspection_types, inspection_triggers,
   work_plans, inspections, work_authorization_templates,
   work_authorization_documents, work_authorization_revisions,
   acknowledgment_gate_templates, acknowledgment_gate_records, tenant_holidays,
   ala_templates, ala_documents, ala_document_revisions, notices_of_defect)
   plus the warranty_coverages_effective view and the three business-day
   calendar functions.
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

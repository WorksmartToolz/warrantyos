# WarrantyOS — Session 5e-bridge Phase 2 Decisions Log

Generated: 2026-05-22 (Phase 2 complete)
Purpose: Captures all 10 architectural decisions from Phase 2 of the 5e-bridge session, plus new Phase 0 alignment items, new conventions, and the Phase 3 first-task constraint.
Status: Phase 2 complete. Phase 3 (v2 architecture doc drafting) begins in a separate session.

---

## Decision 1: Registration Assignee Data Model

DECISION: Option C — dual-FK + snapshot pattern, scoped against the Unified Contacts Directory.

### Shape

```
warranty_registrations
  ...
  assigned_to_contact_id uuid nullable FK → contacts(id)
  assigned_to_user_id    uuid nullable FK → public.users(id)
  -- CHECK: exactly one non-null when assigned; both null when unassigned
  assigned_to_name_snapshot   text nullable
  assigned_to_email_snapshot  text nullable
  assigned_to_phone_snapshot  text nullable
  assigned_at                 timestamptz nullable
```

### Mechanics

- FK type drives downstream behavior:
  - Contact FK → tokenized email link, stateless submission form (Stateless Tokenized Interaction Pattern)
  - User FK → in-app notification, accessed via existing tenant app login
- Reassignment can cross types (e.g., reassign from a contact PM to a Reviewer for self-handling, or vice versa).
- Snapshot written by the system at assignment time, never updated on read, never synced to FK changes.

### Rationale

- Audit defensibility requires immutable historical attribution over 25-year warranty horizons (rules out FK-only).
- Reuse and reporting are real operational needs for EPC warranty workflows with repeating subcontractor PMs (rules out snapshot-only).
- Tenant users sometimes self-assign or assign other tenant users; this is a real workflow, not an edge case.
- Unified Contacts Directory subsumes assignees, customer contacts, subcontractor contacts, vendor contacts into one foundational table — catching the consolidation now avoids parallel tables later.

### Phase 0 Alignment Item Added

**Item 16 — Unified Contacts Directory:** Per-tenant `contacts` table with a `contact_type` discriminator covering: customers, customer contacts, subcontractors, subcontractor contacts, vendors, vendor contacts, registration assignees, other. Single-table approach for the prototype; specialized tables only if type-specific fields proliferate later. Tenant users (`public.users`) stay separate from the contacts directory — auth and RLS implications differ.

### Downstream Impacts

- Audit Topics 1, 6, 9 require Phase 3 revisions to reflect the unified contacts directory and dual-FK assignee model.
- Phase 0 item 8 (PM role) requires Phase 3 revision: assignees are not WarrantyOS users; they are a directory category OR a tenant user, accessed via the Stateless Tokenized Interaction Pattern OR the existing app login respectively.
- v1's "Stateless Customer Interaction Principle" generalizes in v2 to a "Stateless Tokenized Interaction Pattern" used by both claim intake (customer-facing) and registration assignment (assignee-facing), with extensibility for future stateless workflows.

---

## Decision 2: ClaimID Sequence Mechanics + WarrantyID Format Configurability

DECISION: Per-tenant ID generation via a dedicated `tenant_id_sequences` table using Python format-string syntax.

### Shape

```
tenant_id_sequences
  tenant_id      uuid FK → tenants
  id_type        text  -- 'warranty_id' | 'claim_id'
  format_string  text  -- e.g., 'WID-{year}-{seq:06d}'
  current_year   integer
  current_value  integer NOT NULL DEFAULT 0
  updated_at     timestamptz
  PRIMARY KEY (tenant_id, id_type)
```

### Defaults (per-tenant configurable)

- WarrantyID: `WID-{year}-{seq:06d}`
- ClaimID: `CLM-{year}-{seq:07d}`

### Mechanics

- Generation happens in the same transaction as the consuming insert. Rollback rolls back the counter — no gaps.
- Year-rollover is UTC-based, atomic with increment, in a single UPDATE statement using CASE on `current_year` vs `EXTRACT(YEAR FROM NOW() AT TIME ZONE 'UTC')`.
- Format-string changes apply to GENERATION of new IDs only. Historical IDs are immutable strings stored as-is on their parent records.

### Rationale

- Per-tenant (not global): per-tenant configurable formats are structurally incompatible with a shared global counter — different format strings cannot share counter state. Cross-tenant inference via sequence values is a secondary concern, not the deciding factor.
- Dedicated table (not PostgreSQL SEQUENCE objects, not JSONB counters): transactional gap-free behavior is the key win. SEQUENCE objects are non-transactional and require runtime DDL per tenant; JSONB counters serialize all writes to the tenant row.
- Python format-string syntax (not invented `{NNNNNN}` convention): real standardized syntax; explicit padding width via `:06d`; smoother future integration with template engines; supports other format specifiers without inventing new conventions.
- UTC for year-rollover: platform-wide consistency outweighs local-calendar alignment; per-tenant timezone is maintenance burden without proportional benefit.
- Format-change governs generation only (not display, not retroactive update): the only option compatible with the Defensibility Principle. Historical IDs are immutable.

### Downstream Impacts

- Generation logic must validate format strings against the supported placeholders (`{year}`, `{seq:NNd}`) at tenant-settings save time.
- The existing hardcoded `WID-YYYY-NNNNNN` label in `app/app/settings/page.tsx` is decorative and gets replaced by the real `format_string` value from `tenant_id_sequences` when the settings UI becomes live.

---

## Decision 3: Custom Fields Phase 1 Entity Scope

DECISION: Phase 1 custom fields support Projects, Warranty Registrations, and Claims. Typed FK columns with CHECK constraint. Tenant ID denormalized onto `custom_field_values` for RLS simplicity. Definitions soft-delete; values remain queryable but hidden from new entry once the definition is soft-deleted.

### Shape

```
custom_field_definitions
  id              uuid PK
  tenant_id       uuid FK → tenants
  entity_type     text  -- 'project' | 'warranty_registration' | 'claim'
                        -- CHECK constraint enforcing allowed values
  label           text NOT NULL
  field_type      text  -- one of 11 Phase 1 types
  required        boolean NOT NULL DEFAULT false
  options         jsonb  -- dropdown options, null otherwise
  display_order   integer NOT NULL DEFAULT 0
  deleted_at      timestamptz nullable  -- soft-delete discriminator
  created_at      timestamptz
  updated_at      timestamptz

custom_field_values
  id                          uuid PK
  tenant_id                   uuid FK → tenants  -- denormalized for RLS
  definition_id               uuid FK → custom_field_definitions
  project_id                  uuid nullable FK → projects
  warranty_registration_id    uuid nullable FK → warranty_registrations
  claim_id                    uuid nullable FK → claims
  value                       jsonb  -- type-safe per definition.field_type
  created_at                  timestamptz
  updated_at                  timestamptz
  -- CHECK: exactly one of the three entity FKs is non-null
  -- CHECK / app-layer: tenant_id matches definition's tenant_id
```

### Phase 1 Field Types (11)

Address, phone, date, number, plain text, rich text, dropdown, email, URL, checkbox, file upload.

### Phase 2 Field Types (TBD)

Signature, multi-select, currency.

### Excluded from Phase 1 (rationale captured for v2)

- Contacts: directory shape is mostly fixed contact info; custom fields are nice-to-have, not load-bearing.
- Inspections: customization happens via `inspection_report` JSONB (Audit Topic 11).
- Warranty Type Coverages: tightly scoped to start/end/term mechanics.
- ALA Documents, Work Plans, Costs: base schemas do not exist yet.
- Communications: template-driven, not tenant-customizable beyond the existing customization layer.
- Audit Trail Entries: tenant customization would muddy the audit.

### Soft-Delete Semantics

- Soft-deleted definitions: `deleted_at IS NOT NULL`.
- Values for soft-deleted definitions remain queryable for historical display and reporting.
- Definition list UI filters out `deleted_at IS NOT NULL` definitions; new entity edit forms do not render soft-deleted field inputs.
- Existing values do not migrate when a definition is soft-deleted; they remain attached to the now-hidden definition.
- Hard-delete is not exposed in Phase 1 UI; can be done via admin tooling if ever needed.

### Rationale

- Entity scope B: data migration MVP requires project-level custom fields for import column mapping; claim intake requires custom fields for the 6-workbook variance; registrations need them for tenant-specific Section 7 capture. Three entities covers MVP need without building support for entities that don't yet exist.
- FK approach Y: matches Decision 1's pattern (typed FKs + CHECK). Real referential integrity, ON DELETE CASCADE works per-entity, consistent codebase pattern.
- Denormalized `tenant_id`: simpler RLS policy (no JOIN through definitions on every read). Cost is a redundant column with a stay-in-sync invariant enforced at write time.
- Soft-delete: aligns with Defensibility Principle (historical values remain queryable) and Soft Remove Principle (the existing pattern for tenant users). Hard-delete would orphan historical values or cascade-destroy auditable data.

### Downstream Impacts

- Standard RLS pattern docs (v2) must note the denormalized `tenant_id` on `custom_field_values` as a precedent for high-read child tables.
- The stay-in-sync invariant (`custom_field_values.tenant_id` = parent definition's `tenant_id`) must be enforced application-layer at insert time.
- Data migration tooling (Phase 0 item 11) explicitly depends on project-level custom fields — must be in MVP scope, not Phase 2.
- Rich text field type requires Decision 4 (editor choice) to lock the stored JSON format.

---

## Decision 4: Rich Text Editor Choice

DECISION: TipTap, free MIT core. Storage described as ProseMirror-compatible JSON. Phase 1 feature scope restricted to basic formatting. Character cap with per-tenant configurability within a hard platform ceiling.

### Editor

- TipTap, MIT core only (no Pro tier dependency).
- Phase 2+ may revisit if real-time collaboration becomes a requirement.

### Storage Framing

- v2 docs describe rich text storage as "ProseMirror-compatible JSON".
- The framing is deliberate: the data format outlives the library.
- v2 includes a brief schema-level description of the format for future implementers (node tree of `{type, attrs, content, marks}`).

### Phase 1 Feature Scope (locked)

- Bold, italic, underline.
- Links.
- Ordered and unordered lists.
- Headings: H1, H2, H3 only (no H4+).
- NOT in Phase 1: tables, images, mentions, embeds, footnotes, code blocks, blockquotes, custom marks.

### Character Cap

- Default: 10,000 characters of effective text content per rich text field value.
- Per-tenant configurable downward via `tenants.settings` JSONB key `rich_text_max_chars`.
- Hard platform ceiling: 50,000 characters — cannot be raised by any tenant configuration.
- Measures rendered text content, not JSON byte size (formatting overhead does not count against the user's budget).
- Enforced at write time, not display time.
- Client-side check: convenience (character counter + warning).
- Server-side check: authoritative (rejects saves exceeding the cap with a clear error).

### Rationale

- TipTap (over Lexical, Plate): ProseMirror JSON longevity is the deciding factor for a 25-year warranty system. Defensibility requires stored data remain renderable far longer than any specific library is likely to be maintained.
- ProseMirror framing (not "TipTap format"): signals to future implementers that data format outlives library choice.
- Basic scope only: adding features later is straightforward schema-wise (new marks/nodes); removing features after data contains them requires lossy migration or accepting orphan format constructs.
- Character cap: unbounded text inputs are a known UX failure mode (paste a PDF, break every form). Cap provides a design contract for the field. Hard ceiling prevents accidental tenant misconfiguration.

### Downstream Impacts

- Custom field UI renders different input affordances based on `field_type`: 'plain text' → single-line input, 'rich text' → TipTap editor with basic toolbar, etc.
- The cap is enforced both client-side (UX) and server-side (security/authoritative).
- v2 documents ProseMirror JSON as the canonical storage format for rich text custom field values, with a brief schema-level note.
- `tenants.settings.rich_text_max_chars` is the Phase 1 location for the cap config; promotable to a dedicated column later if needed.

---

## Decision 5: Project ↔ WarrantyRegistration FK Direction

DECISION: `warranty_registrations.project_id` is the FK. Project is the parent. 1:1 relationship enforced via UNIQUE constraint. ON DELETE RESTRICT protects audit-relevant data. `tenant_id` denormalized onto `warranty_registrations` for direct RLS scoping.

### Shape

```
warranty_registrations
  id                          uuid PK
  tenant_id                   uuid NOT NULL FK → tenants
  project_id                  uuid NOT NULL UNIQUE FK → projects
                                ON DELETE RESTRICT
  warranty_id                 text nullable  -- issued at Section 7
                                              -- activation; null until then
  ...
  created_at, updated_at      timestamptz
  -- CHECK / app-layer invariant: tenant_id matches the referenced
  -- project's tenant_id
```

### Rationale

- FK direction A (registration → project): matches creation order (project exists first; registration is generated by clock event at `milestone_date − lead_time_days`). Standard parent-child shape. Composes with Phase 0 item 1 (Project as sacred root).
- UNIQUE constraint: 1:1 is architecture (Phase 0 item 2). Database enforcement matches the principle. UNIQUE index cost is trivial.
- ON DELETE RESTRICT: hard-deletion of a project with an associated registration is blocked. Aligns with Soft Remove and Defensibility principles. Normal cleanup path is soft-delete via `deleted_at` or similar discriminator on projects (specified during Topic 7 drafting in Phase 3).
- `tenant_id` denormalization: consistent with Decision 3's pattern. Establishes a convention v2 documents formally.

### Downstream Impacts

- v2's Standard RLS Pattern section formally documents the `tenant_id` denormalization convention.
- Project schema (Audit Topic 7, drafted in Phase 3) must specify the soft-delete discriminator since ON DELETE RESTRICT makes soft-delete the normal cleanup path.
- Application-layer invariant enforcement: any write creating or updating `warranty_registrations.tenant_id` must verify it matches the referenced project's `tenant_id`. Belongs in the Server Action wrapper, not in the database (cross-table check is awkward as a CHECK constraint).

---

## Decision 6: Warranty Type Anchor Delete Protection

DECISION: Defense-in-depth — application-layer check in the Server Action for clean UX, database trigger as the structural guarantee. Protection extends to UPDATE of `is_system` → false. Case-insensitive `UNIQUE(tenant_id, name)` via functional index. Anchor types seeded at tenant provisioning.

### Shape

```sql
CREATE TABLE public.warranty_types (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES public.tenants(id),
  name          text NOT NULL,
  is_system     boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX warranty_types_tenant_name_lower_unique
  ON public.warranty_types (tenant_id, LOWER(name));

-- Trigger function (BEFORE DELETE OR UPDATE), with SET search_path = public
-- hardening per migration 002 precedent. Protects:
--   DELETE where OLD.is_system = true
--   UPDATE where OLD.is_system = true AND NEW.is_system = false
```

### Anchor Seeding

- Tenant provisioning inserts two rows per new tenant:
  - `('Standard Warranty', is_system = true)`
  - `('Workmanship Warranty', is_system = true)`
- Tenants can rename either after provisioning (UPDATE `name` allowed; UPDATE `is_system` → false blocked).

### Rationale

- Defense-in-depth (Approaches 1 + 2): app check provides UX path with clean error before exception; trigger provides structural guarantee against all code paths including admin scripts, direct SQL, future bulk operations.
- Extension to UPDATE of `is_system`: closes the two-step exploit (flip flag, then delete). Architectural commitment applies to the flag itself, not just the row.
- Case-insensitive UNIQUE via functional index: "Foundation" vs "foundation" within the same tenant is workflow-ambiguous; cost is a single composite index; benefit is clean naming.
- Anchor seeding at provisioning: matches Phase 0 item 3's intent. Tenants get a working baseline immediately.

### Downstream Impacts

- Tenant provisioning (`lib/core/provision-tenant.ts`) gains two INSERT statements for anchor warranty types.
- Server Action layer for `warranty_types` CRUD must:
  - Reject delete of `is_system = true` rows (early UX path).
  - Reject UPDATE attempts that flip `is_system` to false (early UX path).
  - Catch PostgreSQL unique constraint violations on name and translate to user-friendly errors.
  - Catch trigger exceptions and translate them similarly.
- Trigger function follows `SET search_path = public` hardening per migration 002 precedent.
- v2 docs formally name the defense-in-depth pattern as a documented convention for architecturally permanent constraints.

---

## Decision 7: ALA Markup Percent (scope: markup default and storage location only)

DECISION: Default ALA markup percent is 10% (decimal `0.10`), stored at `tenants.settings.ala_markup_percent`. Validation bounds 0 ≤ value ≤ 0.50, application-layer enforced.

### Scope Note

Decision 7 resolves the ALA markup default and storage location ONLY. The broader ALA architecture — `ala_templates` table, per-claim `ala_documents`, signature capture, downstream Work Plan gating — remains as gaps to be drafted in Phase 3 from Audit Topic 10's gap analysis, informed by the 6 claim intake workbooks.

### Investigation Acknowledgment

v1 `architecture-reference.md` is silent on ALA markup percent. The only ALA mentions in v1 are "Indistinct Claim — ALA Required" in Six Final Claim Review Outcomes and "ALA Outcome Dispute" in Pathway B. The "15%" figure cited in the handoff document and Phase 1 audit appears to be unsourced — possibly a memory artifact from a prior conversation, possibly a workbook value not yet surfaced. There is no reconciliation needed against v1.

### Decision Details

1. **Default value: 10% (decimal `0.10`).** Sourced from Terrasmart SOP documentation (TSW-GD series).
2. **Storage location: `tenants.settings.ala_markup_percent` JSONB key.** Matches the pattern Decision 4 established for `rich_text_max_chars`. ALA markup is read-mostly tenant config — exactly what `settings` JSONB is designed for. No new column on the `tenants` table.
3. **Validation bounds: 0 ≤ value ≤ 0.50, application-layer enforced.** Zero is a valid configured value (some warrantor business models genuinely don't apply administrative markup). 50% ceiling is the sanity guard against typo-class errors. Bounds enforced in the Server Action wrapper that writes to `tenants.settings`, not at the database level (JSONB doesn't support type-safe bounds without trigger logic, which would be over-engineering here).
4. **Storage format: decimal (`0.10`, not `10`).** Removes ambiguity in code reading. Matches mathematical convention. UI converts at the edge for human display.

### Phase 3 Flag

When drafting Audit Topic 10 (ALA System), if the 6 claim intake workbooks reveal a 15% figure with a real source, revisit whether the default should change. Until then, 10% is the locked default. The flag is precautionary, not blocking.

### Downstream Impacts

- Tenant provisioning sets `tenants.settings.ala_markup_percent = 0.10` at creation time (or leaves the key absent and falls back to `0.10` in code — application-layer convention to be specified during Phase 3 drafting).
- The Server Action that updates tenant settings must validate `ala_markup_percent` against bounds 0 ≤ value ≤ 0.50 and reject out-of-bounds values with a clear error.
- Display layer converts decimal to percentage at the UI edge (`0.10` → "10%" in form labels, settings displays, ALA document generation, etc.).
- v2 documentation flags this as a Phase 3 verification item: "if 15% surfaces in workbooks with a real source during ALA system drafting, revisit the default."

---

## Decision 8: Data Migration Tooling MVP Scope

DECISION: Phase 1 import covers projects + customer org + customer contacts (the customer info that makes projects operationally usable). Platform-admin only in MVP, with tenant-context-agnostic core. CSV/Excel upload with column mapping UI and preview. Fail-on-row-error model with preview as the partial-success substitute. Audit trail captured at both per-record and batch levels.

### Entity Scope

- **In scope for MVP import:**
  - Projects with their custom field values
  - Customer org records (`contact_type = 'customer'`)
  - Customer contact records (`contact_type = 'customer_contact'`)
- **Deferred contact types** (added incrementally during normal tenant operation):
  - Subcontractor records
  - Vendor records
  - Registration assignees (system creates these; warrantor adds as registrations land in prep window)

### Schema Shape

```
import_batches
  id              uuid PK
  tenant_id       uuid FK → tenants
  initiated_by    uuid FK → auth.users  -- platform admin in MVP
  source_filename text
  project_count   integer
  customer_count  integer
  status          text  -- 'completed' | 'failed' | 'rolled_back'
  created_at      timestamptz

projects (excerpt — full schema drafted in Phase 3)
  ...
  customer_id              uuid nullable FK → contacts
  customer_name_snapshot   text
  customer_email_snapshot  text
  customer_phone_snapshot  text
  site_address_street      text
  site_address_city        text
  site_address_state       text
  site_address_zip         text
  imported_via_batch_id    uuid nullable FK → import_batches

contacts (extends Phase 0 item 16 schema with import tracking)
  ...
  imported_via_batch_id    uuid nullable FK → import_batches
```

### Tooling Decisions

| Sub-question | Decision | Rationale |
|---|---|---|
| Entity scope | Projects + customer org + customer contacts | Projects without customer info are not operationally usable. Claim intake auto-population, notice generation, and Section 7 activation all depend on customer data. Deferring to a follow-up contacts migration creates a kicked-can problem. |
| Location | Platform admin first; tenant-side deferred | White-glove onboarding fits mid-sized EPC customers. `lib/core/` import functions are tenant-context-agnostic and accept `tenant_id` as a parameter, so wiring to tenant-side later is additive. |
| Tooling depth | CSV/Excel upload + column mapping UI + preview | Customer's source data should be accepted as-is rather than forcing a reformat. Mapping UI scope expands to include customer/customer_contact columns. |
| Error model | Fail on any row error | Preview surfaces all issues (project, customer, customer_contact) before commit. Partial-success state management deferred until real usage shows it's unbearable. |
| Audit trail | Both per-record and batch entries | Per-record granularity for individual investigation; batch-level summary for "what happened during onboarding". |

### Known Implementation Costs (Phase 3)

- Customer dedup strategy: name + email match within the tenant. Implementation detail for Phase 3.
- Date parsing across multiple formats: Excel serial dates, multiple date string formats, locale variance. Known implementation cost.
- Custom field definitions are **never** created by import. Definitions remain a tenant admin UI creation step BEFORE any import.

### Future Flag

If/when tenant-side import ships, revisit whether fail-on-row-error is bearable without platform admin support.

### Downstream Impacts

- `lib/core/` import functions are tenant-context-agnostic and accept `tenant_id` as a parameter.
- Platform admin import UI at `/admin/tenants/<id>/import` (or similar). Workflow: file upload → column header detection → mapping UI (project columns + customer columns) → preview → confirm → run import → audit batch + per-record audit entries.
- Tenant-side import UI explicitly NOT in MVP. Path to building it later: wire same `lib/core` functions to a new Server Action in tenant context with tenant-scoped RLS.

---

## Decision 9: Clock Event Infrastructure

DECISION: pg_cron as the trigger mechanism, explicit `clock_events` table as the event record, best-effort firing with manual retry, hourly cron frequency.

### Pre-Decision Context

Supabase upgraded to Pro tier (~$25/month) as a business decision independent of Decision 9. This unlocks pg_cron and resolves several other deferred items (automated backups, leaked password protection). Vercel stays on Hobby until real production traffic.

### Trigger Mechanism: pg_cron

- Lives inside the database (Supabase-native), not the hosting layer.
- Principle-aligned: System-Managed Clock + Structural Integrity + portability across hosting changes.
- Mitigation for code-visibility concern: every scheduled job is defined in a version-controlled migration alongside its supporting function. New contributors find schedules via the migrations directory.

### Event Record Shape: explicit `clock_events` table

```
clock_events
  id              uuid PK
  tenant_id       uuid NOT NULL FK → tenants
  event_type      text NOT NULL
                  -- 'registration_prep' | 'info_request_due'
                  -- | 'warranty_expiry_warning' | (extensible)
                  -- CHECK constraint enforces allowed values
  entity_type     text NOT NULL
                  -- 'project' | 'claim' | 'warranty_coverage'
                  -- | (extensible)
                  -- CHECK constraint enforces allowed values
  entity_id       uuid NOT NULL
  fires_at        timestamptz NOT NULL
  status          text NOT NULL DEFAULT 'pending'
                  -- 'pending' | 'fired' | 'cancelled' | 'failed'
  fired_at        timestamptz nullable
  failure_reason  text nullable
  payload         jsonb  -- event-type-specific context, validated
                         -- at write time per event type
  created_at      timestamptz
  updated_at      timestamptz

  CREATE INDEX clock_events_pending_fires_at_idx
    ON clock_events (fires_at)
    WHERE status = 'pending';
  CREATE INDEX clock_events_tenant_idx ON clock_events (tenant_id);
  CREATE INDEX clock_events_entity_idx
    ON clock_events (entity_type, entity_id);
```

### Mechanics

- Inspectable: `SELECT * FROM clock_events WHERE status = 'pending' ORDER BY fires_at` shows what's coming.
- Auditable: every firing becomes a permanent row with `fired_at` timestamp.
- Decoupled from entity state: cancellation is a status update, not an entity mutation.
- Server Actions that create/update/delete entities with scheduled events must update the corresponding `clock_events` rows:
  - Project creation with `contractual_milestone_date` → insert pending `clock_events` row for `registration_prep`.
  - Project `milestone_date` update → update `fires_at` on existing pending row.
  - Project soft-delete → set `status='cancelled'` on pending rows.
  - Similar patterns apply for other event types.

### Failure Handling: best-effort with manual retry

- Failed events flip to `status='failed'` with `failure_reason` captured.
- Platform admin UI surfaces failed events with diagnosis context and a retry button.
- No auto-retry — solving a problem without evidence it exists adds complexity that can mask real bugs.

### Cron Frequency: hourly (`'0 * * * *'`)

- Captures hour-precision deadlines (information request response windows) with at most one hour of slack.
- Day-precision events (registration prep, warranty expiry warnings) fire reliably.
- Revisit if real usage shows tighter precision is needed.

### Downstream Impacts

- Supabase Pro upgrade enables pg_cron extension. Enabling pg_cron is a Phase 3 / build-time task.
- The cron handler (a SQL function called by pg_cron, defined in a migration) reads pending events where `fires_at <= NOW()` and dispatches based on `event_type`. Each event type has its own dispatcher function. Handler design specifics are Phase 3 / build-time.
- Platform admin UI for failed-event surface is Phase 3 / build-time.
- `payload` JSONB validation per `event_type` happens application-layer at insert time (in the Server Action that creates the event), not at the database level. Each event_type has its own expected payload schema.

### Phase 0 Implication

The System-Managed Clock Principle now has concrete implementation backing. v2 documents pg_cron + `clock_events` as the canonical mechanism for any future scheduled event in WarrantyOS. Future contributors don't invent their own scheduling pattern — they add event types to `clock_events`.

---

## Decision 10: Schema Source of Truth

DECISION: Option C — migrations are canonical schema; `schema.sql` is a generated artifact, never hand-edited. The generator script is built as the first Phase 3 task, before any new schema migrations are written.

### Decision Details

- **Migrations are canonical schema.** Numbered migration files in `supabase/migrations/` are the authoritative source of truth for schema state.
- **`schema.sql` is a generated artifact**, never hand-edited.
- **The generator script is built as the first Phase 3 task**, before any new schema migrations are written.
- **Until the generator exists**, `schema.sql` remains as-is (currently in sync). No new migrations are written until the generator exists — Phase 3 build sequencing handles this naturally.
- **The generator approach** (Supabase CLI command, custom pg_dump script, or other) is a Phase 3 implementation decision, not a Decision 10 question. Any approach that produces deterministic `schema.sql` from the applied migrations is acceptable.
- **New migrations follow the existing pattern**: numbered sequentially, `SET search_path = public` hardening on functions, comments explaining design decisions, RLS policies applied alongside table creation.

### Rationale

- Migrations canonical (Option A, C, or D over B): Option B (`schema.sql` canonical) has structural problems for production deploys. Existing databases have already had migrations applied; treating `schema.sql` as canonical means inventing conventions for what has already been deployed vs what is pending.
- Option C over Option D (hand-maintained `schema.sql`): the Structural Integrity Principle says foundation issues should be addressed when identified, not deferred. Phase 3 introduces 9+ new tables (contacts, tenant_id_sequences, custom_field_definitions, custom_field_values, warranty_types, warranty_registrations, projects, import_batches, clock_events) plus modifications to existing ones. Option D's hand-sync discipline worked at 4 migrations; it cannot safely be assumed to scale to 13+. The Tailwind v3→v4 deferral (Session 1 → Sessions 5b/5c) is the precedent for why "ship the convention now, fix it later" carries real risk.
- Option C over Option A (retire `schema.sql`): generated `schema.sql` preserves easy current-state inspection and code-review ergonomics without sacrificing the canonical-migrations property.
- Pre-commit hook rejected: pre-commit hooks are conventions dressed up in code ("the same person who forgets to update `schema.sql` will also forget to install the hook"). Once the generator exists, the generator IS the check.

### Phase 3 First-Task Constraint

This decision creates a hard ordering for Phase 3:

1. Build the `schema.sql` generator script (~30 min – 2 hours).
2. Verify it produces a `schema.sql` identical to the current hand-maintained one (sanity check that the generator is correct before relying on it).
3. THEN begin writing new migrations for the Phase 3 tables (contacts, projects, etc.).

This sequencing prevents drift between migrations and `schema.sql` during Phase 3's schema-heavy work.

---

## Phase 0 Alignment Items Added During Phase 2

**Item 16 — Unified Contacts Directory.** (Added during Decision 1.) Per-tenant `contacts` table with a `contact_type` discriminator covering: customers, customer contacts, subcontractors, subcontractor contacts, vendors, vendor contacts, registration assignees, other. Single-table approach for the prototype; specialized tables only if type-specific fields proliferate later. Tenant users (`public.users`) stay separate from the contacts directory — auth and RLS implications differ.

---

## New Conventions Established During Phase 2

**Standard RLS Pattern — `tenant_id` denormalization for child tables.** (Established by Decisions 3 and 5.) Tenant-scoped child tables denormalize `tenant_id` directly rather than requiring JOIN-through-parent for RLS evaluation. Tradeoff: a redundant column with a stay-in-sync application-layer invariant. Benefit: simpler RLS policies, faster read paths. Applies to `custom_field_values`, `warranty_registrations`, and future child tables where the parent is also tenant-scoped.

**Defense-in-Depth Pattern for architecturally permanent constraints.** (Established by last-admin protection (Session 5e Test 2) and Decision 6.) Application-layer check intercepts at the Server Action with a clean user-facing error. Database constraint (CHECK, UNIQUE, trigger, or RLS filter) provides structural enforcement that no code path can bypass. Convention applies to any future "architecturally permanent" constraint.

**Stateless Tokenized Interaction Pattern.** (Generalized during Decision 1 from v1's "Stateless Customer Interaction Principle".) The pattern is used by both claim intake (customer-facing) and registration assignment (assignee-facing), with extensibility for future stateless workflows. A tokenized email link gives a non-authenticated party time-bound access to a focused interface; no account, no session persistence beyond the link.

**FK + Snapshot Pattern with two shapes (single-FK and dual-FK).** (Established by Decisions 1 and 8.) Tenant-scoped records that reference parties whose contact info must remain audit-defensible across long horizons use an FK to the canonical record plus snapshot columns captured at assignment/association time.
- **Single-FK shape (Decision 8):** the referenced entity is always a directory contact. Example: `projects.customer_id` references `contacts(id)` with `customer_name_snapshot` / `customer_email_snapshot` / `customer_phone_snapshot` captured at project creation.
- **Dual-FK shape (Decision 1):** the referenced entity can be either a directory contact OR a tenant user. Two nullable FKs with a CHECK constraint enforcing exactly one non-null. Example: `warranty_registrations.assigned_to_contact_id` + `assigned_to_user_id` with snapshot columns captured at assignment.
- In both shapes, the snapshot is written by the system at assignment time, never updated on read, never synced to FK changes.

---

## Phase 3 Revision Flags

The following items must be revised in Phase 3 v2 drafting:

- **Audit Topic 1 (Role Tier Model):** retire all PM-role-on-users discussion. The PM role is not added to the tenant role model.
- **Audit Topic 6 (Warranty Registration):** Warranty Support Subcontractors section references the Unified Contacts Directory rather than capturing raw text.
- **Audit Topic 7 (Project Entity):** specify the soft-delete discriminator since ON DELETE RESTRICT (Decision 5) makes soft-delete the normal cleanup path.
- **Audit Topic 9 (Claim Intake):** O&M Provider contacts and similar reference the Unified Contacts Directory using the same FK + snapshot pattern from Decision 1.
- **Audit Topic 10 (ALA System):** verify markup default against the 6 claim intake workbooks; if a 15% figure has a real source, revisit the default established in Decision 7.
- **Phase 0 item 8 (PM role):** revise to state that assignees are either a directory contact or a tenant user, accessed via the Stateless Tokenized Interaction Pattern or existing app login respectively.

---

## Phase 3 First-Task Constraint (from Decision 10)

Phase 3 begins with the `schema.sql` generator script as the first task. Hard ordering:

1. Build the `schema.sql` generator script (~30 min – 2 hours).
2. Verify it produces a `schema.sql` identical to the current hand-maintained one.
3. THEN begin writing new migrations for the Phase 3 tables.

No new migrations are written until the generator exists. This prevents drift between migrations and `schema.sql` during Phase 3's schema-heavy work (9+ new tables plus modifications).

---

End of Phase 2 decisions log. Phase 2 complete.

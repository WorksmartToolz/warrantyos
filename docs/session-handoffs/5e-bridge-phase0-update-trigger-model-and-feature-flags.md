# WarrantyOS — Phase 0 Update: Warranty Trigger Model and Feature Flag System

Generated: 2026-05-22 (post Phase 2 / pre Phase 3)
Purpose: Capture two locked architectural additions to Phase 0 alignment surfaced after the Phase 2 decisions log was committed but before Phase 3 drafting begins. These items are anchor architecture for Phase 3; the Phase 3 session must read this document alongside the Phase 3 handoff before drafting any project, registration, or clock-event sections.
Status: Locked architecture. Both items resolved before Phase 3. No further decisions required mid-drafting.

---

## Why this document exists

Phase 2 closed with 10 architectural decisions, a new Phase 0 item 16 (Unified Contacts Directory), four new conventions, and three commits documenting the bridge. The Phase 3 handoff document was drafted, reviewed, and committed at `1a9293a`.

After the Phase 3 handoff was committed, Andre surfaced a gap that Phase 2 had not addressed: **the existing project lifecycle assumes the warranty trigger date is known in advance** (Phase 0 item 9: "Projects exist in WarrantyOS once their contractual milestone date is known. Registration prep is triggered `registration_lead_time_days` before the milestone."). That assumption is correct for the EPC business shape — where the warrantor is part of the construction process and the trigger milestone is observable in a shared system — but it silently breaks for the supply-only business shape, where the warranty starts at delivery and the warrantor has no presence at the delivery event.

This is anchor-level architecture. It affects projects, registrations, clock events, and the System-Managed Clock principle. It needs to be resolved before Tier 2 of the Phase 3 drafting order (Project entity), not during drafting.

This document locks two related architectural additions:

- **Phase 0 item 17 — Warranty Trigger Model is multi-source.** Establishes WHAT the trigger sources are.
- **Phase 0 item 18 — Feature Flag System.** Establishes HOW trigger sources (and other workflows) are gated per-tenant.

Both are locked. No new Phase 3 decisions are required to integrate them — Phase 3 documents them, doesn't re-litigate them.

---

## Phase 0 Alignment Item 17 — Warranty Trigger Model is Multi-Source

### The structural problem this resolves

WarrantyOS serves two distinct warrantor business shapes:

**EPC shape.** Warrantor is part of (or contractually positioned in) the construction process. Warranty trigger is a contractually-defined milestone — substantial completion, commercial operation date (COD), commissioning date, or a contract-defined variance — memorialized in the project's Work Breakdown Schedule (WBS). The trigger date is **known in advance** because the project is observable in a construction-management system of record. Procore is one example; other systems are equivalent. The warrantor has visibility into the project lifecycle and can prepare for the trigger event before it occurs.

**Supply-only shape.** Warrantor sells the warranted product (e.g., racking) and ships it. The buyer-installer is the one with site presence; the warrantor has none. Warranty trigger is the **delivery date** — the moment the product changes hands at the destination. The warrantor does not observe this event. The buyer-installer does, and the buyer-installer's incentive to volunteer the delivery date promptly is not naturally aligned with the warrantor's (every day of delay extends the buyer's effective warranty coverage). This is an asymmetric-information structural problem, not a missing feature.

The pre-existing mechanism (Phase 0 item 9) handles the EPC shape correctly but does not handle the supply-only shape. Some tenants operate in pure EPC. Some operate in pure supply-only. Some operate in both (Andre's current employer is a hybrid). The architecture must accommodate all three.

### The locked solution: trigger_source as a first-class concept

The Project entity (Audit Topic 7) carries two new fields:

- **`trigger_source`** — the source of truth for the warranty trigger date. Enumerated, extensible. Identifies *how* the trigger date is determined and *who* is the source of truth for it.
- **`trigger_status`** — the current state of the trigger relative to the project lifecycle. Enumerated. Identifies *whether* the trigger has been confirmed, is pending, or is overdue.

### Phase 1 trigger sources (four values)

The `trigger_source` enum accepts these Phase 1 values:

1. **`contractual_date_manual`** — Trigger date is a contractually-defined date entered manually by a tenant user at project creation. EPC shape. The user supplies the date directly; no integration. The "default EPC trigger" for tenants without WBS-integration tooling.

2. **`wbs_integration`** — Trigger date is sourced from a construction-management system via API integration. EPC shape. The project carries an external reference (e.g., Procore project ID, WBS milestone identifier) and WarrantyOS reads the milestone date from the integrated system. Procore is the canonical example; the integration architecture is extensible to other systems. When the integrated system reports that the WBS milestone has been hit, the trigger date is captured and `trigger_status` advances.

3. **`delivery_report_tokenized`** — Trigger date is reported by the buyer-installer via a tokenized email link, using the Stateless Tokenized Interaction Pattern established in Phase 2 Decision 1. Supply-only shape. The warrantor's first knowledge of the delivery date comes from the buyer's submission of the tokenized form. The form is sent when the project is created (at sale time) and remains open until the buyer reports the delivery date.

4. **`delivery_report_api`** — Trigger date is sourced from a logistics or freight-carrier API confirming delivery to the installation site. Supply-only shape. Reserved as a Phase 1 enum value to make the future integration path explicit; concrete API integrations (carrier-specific) are not Phase 3 scope. Documented so v2 doesn't have to retrofit the enum later.

The enum is **extensible**. Future trigger sources (e.g., `customs_release_api`, `inspection_signoff`, `warrantor_self_report`) can be added as additional architectural decisions in later phases. Phase 1 ships with these four; the structure is designed to accommodate more without restructuring.

### trigger_status state machine

The `trigger_status` enum tracks where the trigger event is in its lifecycle:

- **`pending`** — Project exists; trigger event has not yet occurred. The default state at project creation for all trigger sources where the trigger is in the future or unconfirmed.
- **`confirmed`** — Trigger event has occurred; trigger date is captured; warranty start date is established. The state at which registration prep can fire (for trigger sources where prep is post-confirmation) or has fired (for trigger sources where prep is pre-trigger).
- **`overdue`** — Expected trigger window has passed and no confirmation has been received. Applies primarily to `delivery_report_tokenized` (buyer has not responded within the expected delivery window) and `wbs_integration` (the integrated milestone has not flipped within the expected timeframe). Surfaces to platform admins and tenant team admins for follow-up.

Transitions between states are governed by the trigger source. The state machine is documented in v2 alongside the Project entity section.

### Revision to Phase 0 item 9

Phase 0 item 9, as originally written, reads:

> Projects exist in WarrantyOS once their contractual milestone date is known. Registration prep is triggered `registration_lead_time_days` before the milestone (default 21 days, per-tenant configurable).

This wording is EPC-specific and must be revised in Phase 3 to read:

> Projects exist in WarrantyOS at the point determined by their trigger source. For `contractual_date_manual` and `wbs_integration` trigger sources (EPC shape), the project is created when the trigger date is known in advance, and registration prep is triggered `registration_lead_time_days` before the trigger date (default 21 days, per-tenant configurable). For `delivery_report_tokenized` and `delivery_report_api` trigger sources (supply-only shape), the project is created when the sale occurs, and registration prep is triggered upon delivery confirmation (i.e., the registration prep clock event fires when `trigger_status` advances from `pending` to `confirmed`), not before.

This revision is not a Phase 3 decision — it is a Phase 3 drafting task, applying the locked semantics of item 17.

### New clock event types

Decision 9 established the `clock_events` table with extensible `event_type` values. Item 17 adds two new event types to the Phase 1 enum:

- **`registration_prep_pre_trigger`** — Fires `registration_lead_time_days` before a known trigger date. Used for `contractual_date_manual` and `wbs_integration` trigger sources. This renames and specializes the `registration_prep` event type from Decision 9's Phase 1 enum. Phase 3 drafting treats `registration_prep_pre_trigger` as the EPC-specific event handling pre-trigger arithmetic; supply-only confirmation is handled as a direct Server Action effect (see below).
- **`trigger_confirmation_overdue`** — Fires when a project's expected trigger window has passed without confirmation. Used primarily for `delivery_report_tokenized` to escalate to platform admins / team admins when a buyer has not reported delivery. Configurable per-tenant: overdue threshold defaults to (delivery window + grace period) where both are tenant-configurable, with sensible defaults to be set during Phase 3 drafting based on supply-only operational norms.

Registration prep on confirmation is a direct Server Action effect, not a future-firing clock event. When `trigger_status` advances to `confirmed`, the Server Action handling that transition immediately creates the warranty registration without going through `clock_events`. The `clock_events` table is reserved for future-firing events; synchronous transitions do not belong there. This applies to both supply-only flows (where confirmation is the trigger event itself) and to `wbs_integration` flows (where the poller's detection of a milestone state change is itself a synchronous transition once detected).

### Integration architecture (WBS / API trigger sources)

Phase 1 supports `wbs_integration` as an enum value but does not lock the specific integration mechanism for any particular system (Procore, etc.). The architectural pattern is:

- Project carries `trigger_source = 'wbs_integration'` plus an `integration_config` JSONB blob (or dedicated columns — Phase 3 implementation detail) capturing the external system identity and the project's reference within that system.
- A poller (likely a `clock_events`-driven hourly check, leveraging Decision 9's infrastructure) reads the external system on a tenant-configurable schedule and detects milestone state changes.
- When the configured milestone hits the configured state, the poller captures the timestamp, sets `trigger_status = 'confirmed'`, and directly invokes the Server Action that creates the warranty registration (no `clock_events` row — the transition is synchronous once the poller detects it).

Concrete integrations (Procore, others) are Phase 4+ build work. v2 documents the pattern; specific integrations come later. Reserved as architectural placeholder so Phase 3 drafting accounts for the pattern without committing to a specific vendor implementation.

### Supply-only structural acknowledgment

The supply-only shape has an irreducible information-asymmetry problem that no software architecture fully solves. The buyer-installer is the source of truth for delivery date; their incentive to report promptly is not natively aligned with the warrantor's interest. WarrantyOS mitigates but does not eliminate this:

- **Tokenized form sent at sale time**, not delivery time — the link exists and is monitored from the moment the project enters WarrantyOS.
- **Overdue escalation** via `trigger_confirmation_overdue` event — silence is surfaced, not ignored.
- **Contractual default-trigger language** is the operational/legal layer that backstops the platform — tenants are expected to include clauses in their sales contracts that trigger the warranty by default after N days post-shipment if no delivery confirmation is received. WarrantyOS supports recording these clauses but does not enforce them automatically in Phase 1 (the default-trigger logic is contractual and operational, not pure software, and the platform should not assume contractual language uniformly across tenants).

The `trigger_confirmation_overdue` event is the structural signal that *something* — operational follow-up, legal default-trigger application, contractual enforcement — needs to happen. The platform surfaces the gap; the warrantor's operational policy fills it.

### Downstream impacts for Phase 3 drafting

- Project entity (Audit Topic 7) carries `trigger_source` and `trigger_status` columns plus optional `integration_config` and `trigger_date` (the captured date, set when `trigger_status` becomes `confirmed`).
- Warranty Registration (Audit Topic 6) is generated based on `trigger_status` transitions, not solely on calendar arithmetic against a known milestone date.
- System-Managed Clock principle in v1 must be revised in Phase 3 to acknowledge that the clock's relationship to the warranty trigger differs by trigger source (pre-trigger for EPC, post-confirmation for supply-only).
- Stateless Tokenized Interaction Pattern (established in Phase 2 Decision 1) extends to cover delivery reporting via `delivery_report_tokenized`. This is an application of the pattern, not a new pattern.
- The `import_batches` mechanism (Decision 8) must accommodate the trigger source as part of imported project data — customers bringing project portfolios from EPC or supply-only operations must be able to map their source data to the right trigger source at import time.
- Customer-facing Communications (v1's 14 notice types) gain at least two new templates: the delivery-reporting tokenized form and the overdue-trigger follow-up notice. Phase 3 drafting catalogues them.

---

## Phase 0 Alignment Item 18 — Feature Flag System

### Why this is foundational, not bolt-on

Different tenants operate in different business shapes. Some are pure EPC. Some are pure supply-only. Some are hybrid. If WarrantyOS bakes both workflows into every tenant by default, the pure-shape tenants see UI for features they don't use, which is bad onboarding UX and weak sales positioning — a Reviewer at a pure-EPC firm should not see a "delivery report awaiting" surface they will never act on.

Building per-tenant feature switchability as foundational architecture (not bolt-on) costs little per-feature but gives WarrantyOS structural flexibility forever. This is the same architectural logic that justified multi-tenancy from day one: bake it in early, benefit forever; bolt it on later, painful retrofit.

The feature flag system is now anchor architecture. v2 documents it as a Tier 1 foundational element alongside Standard RLS Pattern, Stateless Tokenized Interaction Pattern, and the others.

### Shape

The feature flag system has four parts:

1. **Storage.** Per-tenant feature configuration lives in `tenants.settings.enabled_features` (JSONB key) or in a dedicated `tenant_features` table. The choice between these is a Phase 3 implementation detail and depends on whether feature flag config has independent operational characteristics (audit trail on flag changes, who toggled them, when) that justify a dedicated table. JSONB is the lighter starting point; a dedicated table is the natural upgrade if richer semantics emerge.

2. **Application-layer helper.** A `lib/core/features/is-feature-enabled.ts` function (or equivalent) takes a `tenantId` and a `feature` identifier and returns boolean. Called by Server Actions before allowing feature-gated operations. Called by Server Components before rendering feature-gated UI. The helper is the single source of truth for "is this feature on for this tenant"; no Server Action or component evaluates flags directly.

3. **Platform admin UI surface.** Platform admins can toggle features per tenant via the existing `/admin/tenants/<id>/` surface (new sub-page or section, drafted in Phase 3 / built in Phase 4). Toggles are audit-logged: who toggled, when, from what to what.

   Feature flag toggling is restricted to platform admins. Tenant Team Admins do not have access to feature flag configuration — feature availability is a platform-business decision (what's sold to which tenant), not a tenant-self-service configuration. Tenant Team Admins see only the features that are enabled for their tenant; they cannot disable enabled features or enable disabled ones. The RLS policy on the feature flag storage (JSONB key or dedicated table) restricts UPDATE access to the platform admin role.

4. **Default features at tenant provisioning.** Tenant provisioning (`lib/core/provision-tenant.ts`) seeds the default feature set. The default model is **opt-out**: at provisioning, both `epc_workflow` and `supply_only_workflow` are enabled. Platform admin disables selectively if a tenant's business shape is pure-one-or-the-other. This default favors discoverability (new tenants see all workflows and can scope down) over minimalism (forcing every tenant to opt in to each workflow at provisioning).

### Phase 1 features (two values)

- **`epc_workflow`** — Gates EPC trigger sources (`contractual_date_manual`, `wbs_integration`) and any EPC-specific UI elements (WBS integration configuration, milestone date entry, EPC-flavored registration prep flows).
- **`supply_only_workflow`** — Gates supply-only trigger sources (`delivery_report_tokenized`, `delivery_report_api`) and any supply-only-specific UI elements (delivery-reporting form configuration, overdue-trigger escalation surfaces, supply-only flavored registration prep flows).

Both default to enabled at provisioning. Hybrid tenants (Andre's current employer is one) leave both enabled; pure-shape tenants disable the workflow they don't use.

### How feature flags interact with Item 17 (multi-source trigger model)

The interaction is the **defense-in-depth pattern** established by Phase 2 Decision 6 (anchor warranty type protection):

- **At the schema level:** `trigger_source` accepts all four Phase 1 enum values regardless of tenant feature configuration. The database is permissive; it does not enforce per-tenant feature gating.
- **At the application layer:** Server Actions check `isFeatureEnabled(tenantId, 'epc_workflow')` before allowing the creation of a project with `trigger_source IN ('contractual_date_manual', 'wbs_integration')`. Similarly for `supply_only_workflow`. The application is the gate.
- **At the UI layer:** Project creation forms render only the trigger sources whose feature flag is enabled. A pure-EPC tenant's UI never displays delivery-report options; a pure-supply-only tenant's UI never displays milestone date entry.

This separation — schema permissive, application/UI enforced — is the same pattern Decision 6 used for anchor type protection (schema allows the `is_system` flag values, application and trigger enforce architectural permanence). v2 documents both as instances of the Defense-in-Depth Pattern (Phase 2 convention).

### Extensibility to future features

The feature flag system is designed to accommodate future modules without restructuring. Future feature flags Phase 3 or later might add:

- `claim_intake_advanced_workflows` — gates extended claim intake forms beyond the Phase 1 minimum.
- `ala_signature_capture` — gates ALA signature workflow if introduced.
- `customer_portal` — gates a future customer-facing portal if added beyond tokenized links.
- Whatever additional business-shape variants emerge.

None of these are Phase 1 features. They are noted here so the next Phase 3 Claude understands the system is designed to accommodate them, and so feature naming conventions can be established early. Phase 3 drafting documents the Phase 1 features (`epc_workflow`, `supply_only_workflow`) and the extensibility pattern; concrete future features are added when their own architectural decisions are made.

### Downstream impacts for Phase 3 drafting

- Feature Flag System becomes a new Tier 1 section in v2, alongside Standard RLS Pattern, Stateless Tokenized Interaction Pattern, Cache Invalidation Pattern, Unified Contacts Directory, Custom Field System, Clock Event Infrastructure, ID Generation, and Schema source-of-truth convention.
- Tenant provisioning section in v2 documents the default feature set and the opt-out model.
- Project entity section in v2 references the Feature Flag System when documenting how `trigger_source` is constrained at the application layer.
- Platform admin section in v2 gains a feature-flag-management subsection.
- The `tenants.settings` JSONB documentation in v2 gains an `enabled_features` key spec (assuming Phase 3 chooses JSONB over a dedicated table; if dedicated table, the table is documented separately).
- Audit logging: feature flag changes are audit-quality events (Defensibility Principle). The audit trail captures `tenant_id`, `feature`, `old_value`, `new_value`, `changed_by` (platform admin user id), `changed_at`.

---

## Combined Phase 3 implications

Both items together require these adjustments to the Phase 3 plan as documented in `docs/session-handoffs/5e-bridge-phase3-handoff.md`:

### Tier 1 (foundational) gains a new section

Feature Flag System slots into Tier 1 of the Phase 3 dependency order. The full Tier 1 list becomes:

- Standard RLS Pattern
- Stateless Tokenized Interaction Pattern
- Cache Invalidation Pattern
- **Feature Flag System (new)**
- Unified Contacts Directory
- Custom Field System (architecturally locked by Decision 3)
- Clock Event Infrastructure
- ID Generation (`tenant_id_sequences`)
- Schema source-of-truth convention (Decision 10)

Feature Flag System should be drafted *before* Project (which references it for `trigger_source` gating). Order within Tier 1 is otherwise unconstrained, but Feature Flag System has a hard dependency from Project (Tier 2).

### Tier 2 entity sections get expanded scope

Project (Tier 2) gains:
- `trigger_source` enum and Phase 1 values documentation
- `trigger_status` state machine documentation
- Per-trigger-source lifecycle behavior
- Feature flag interaction at the application layer
- Integration-config placeholder for `wbs_integration` and `delivery_report_api`
- Revised Phase 0 item 9 language

Warranty Registration (Tier 2) integrates the multi-source model — registration generation timing differs by trigger source.

### Clock Event Infrastructure (Tier 1) gains new event types

The event_type enum documented in v2 must include:
- `registration_prep_pre_trigger` (renamed and specialized from Decision 9's `registration_prep`)
- `trigger_confirmation_overdue`

Registration prep on `trigger_status` advance to `confirmed` is handled as a direct Server Action effect, not as a `clock_events` row. See Item 17's "New clock event types" section for the rationale.

### System-Managed Clock principle gets revised

The principle's wording in v2 acknowledges that the clock's relationship to the warranty trigger event is trigger-source-specific. Pre-trigger arithmetic for EPC; post-confirmation event firing for supply-only.

### No new Phase 2-style decisions in Phase 3

Both items 17 and 18 are locked here. Phase 3 documents them; Phase 3 does not re-litigate them. If any sub-question surfaces during Phase 3 drafting (e.g., "JSONB vs dedicated table for `enabled_features`"), it is treated as a Phase 3 implementation detail and resolved within the drafting flow, not escalated as a new architectural decision.

---

## What the Phase 3 session needs to know

The new Claude starting Phase 3 must read this document **after** the three Phase 1 / Phase 2 reference documents but **before** the SOPs and workbooks, and **before** the Phase 3 handoff doc itself if possible (so the handoff doc's Tier 1 list is read with item 18's Feature Flag System addition already in mind).

Suggested updated reading order for Phase 3 session start:

1. `docs/architecture-reference.md` (v1)
2. `docs/session-handoffs/5e-bridge-phase1-audit.md` (Phase 1 audit)
3. `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` (Phase 2 decisions)
4. **This document** (Phase 0 update covering items 17 and 18)
5. `docs/session-handoffs/5e-bridge-phase3-handoff.md` (Phase 3 handoff)
6. The 7 operational SOPs
7. The 6 claim intake workbooks

The Phase 3 handoff's Section 5 (Reference Documents) and Section 12 (Confirm You Understand) implicitly need to incorporate this document. Since the Phase 3 handoff is already committed, the cleanest path is: the new Phase 3 chat receives this document as opening context alongside the handoff, and the handoff's reading list is mentally extended to include this document. A formal revision of the Phase 3 handoff is not necessary — the addendum operates as a Phase 0 update applied on top of all prior phase work.

---

End of Phase 0 update document. Items 17 and 18 are locked architecture for Phase 3.

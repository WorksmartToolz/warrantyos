**Last updated:** 516277c 2026-07-10

# 5e-Bridge Phase 3 Decisions Log

This file extends the Phase 2 decisions log (Decisions 1-10, captured in
5e-bridge-phase2-decisions-log.md) with
architectural decisions made during Phase 3 drafting sessions. Each
decision is numbered, dated, and captures the question, the resolution,
and the schema or pattern locked.

These decisions are referenced by v2 architecture sections through their
decision numbers (e.g., "per Decision 11" or "per Decision 12"). The
sections themselves don't re-document the decisions; they cross-reference
them by number.

---

## Decision 11: Customer Work Authorization Entity

**Decided in Session 5e (Phase 3 Tier 3 triage-and-resolve session).**

### Context

Customer Work Authorization was referenced operationally in SOP 1
("the warranty professional must request a customer Work Authorization
before the joint/exploratory inspection can commence") but had no v2
schema definition. Flagged as the most urgent Cat 3 item in the 31-flag
triage because it was blocking Customer Work Authorization section
drafting and Work Plan Workflow section drafting.

### Question

What is the architectural shape of the Customer Work Authorization
entity? Specifically:
- Entity scope: single per claim or one-to-many?
- Schema shape: template-vs-document like ALA, or different?
- Customer input shape: what fields does the customer provide?
- Blocking-gate behavior: what does Work Authorization gate?
- Signature mechanism: tokenized acceptance, wet signature, or e-signature?

### Resolution

**Five locked commitments:**

**11.1: One-to-many with claims, event-specific.**

Each Work Authorization is tied to a specific on-site activity (an
inspection, a work plan execution, or any other event requiring physical
presence at the customer's site). A claim has zero, one, or many Work
Authorizations across its lifecycle. There is no UNIQUE constraint on
claim_id. Each authorization authorizes a specific bounded operational
event, not the whole claim.

**11.2: Universal blocking-gate behavior.**

No on-site activity of any kind — inspection, repair, site visit, anything
where warrantor personnel or contracted personnel physically arrive at
the customer's site — proceeds without an approved Work Authorization for
that specific event. The Server Action layer enforces this as a
precondition check before any operation that creates on-site presence.

This is stronger than SOP 1's explicit language (which named inspections
only); the platform commitment is broader and intentionally so.

**11.3: Template-vs-document schema parallel to ALA.**

Two tables in a parent-child relationship:
- `work_authorization_templates` — tenant-defined template definitions
- `work_authorization_documents` — per-event instantiations

The parent-child shape mirrors ALA's template-vs-document model but the
relationship to claims is one-to-many (vs ALA's one-to-one), reflecting
the per-event scope of authorizations.

**11.4: Tokenized form-acceptance with signature artifact.**

The Stateless Tokenized Interaction Pattern applies (the pattern's fifth
canonical use after claim intake, registration assignee submission,
supply-only delivery reporting, and service report customer review).
The customer clicks the tokenized link and reaches the Work
Authorization form. The form's approval response includes a
signature-equivalent field — a typed name + an "I authorize" checkbox —
that's captured as column values on the document row. Form submission
with the signature artifact completed constitutes legal approval; the
platform records who submitted, when, with full audit trail.

This is locked for Work Authorization specifically. The ALA signature
mechanism (Cat 3 flag from triage, separately) is held as a separate
architectural question because ALA's legal-force implications (assumption
of financial liability) may warrant a different mechanism.

**11.5: Revise-and-resend as primary denial recovery path.**

When a customer denies a Work Authorization, the document is editable
(warrantor revises scope, dates, or other fields based on the customer's
denial reason) and resent for re-review. The denial reason and revision
history stay on the same document — same claim_id, same
event_reference_id, full audit trail of how this specific authorization
request evolved.

Revision history is captured in a child table
`work_authorization_revisions`. The customer sees the full revision
history transparently on resend (Option A from the resolution
discussion — full transparency for trust-building, operational clarity,
and audit-defensibility).

A withdrawal-and-new-document path exists as a fallback for the edge
case where a denial isn't recoverable through revision (the warrantor
decides to scrap the request entirely and start over).

### Additional locked architectural elements

**State machine on document status column.** Seven values enforcing the
operational lifecycle:
- `draft` — warrantor created, not yet sent
- `sent` — sent to customer, awaiting response
- `approved` — customer approved with signature artifact
- `denied` — customer denied with denial explanation
- `revised` — warrantor edited after denial; back to draft-like state pending resend
- `resent` — re-sent after revision, awaiting customer response again
- `withdrawn` — warrantor scrapped the request (fallback path)

**Sixth Clock Event type added to Decision 9's enum:**
`work_authorization_response_overdue` — fires when
`expected_response_date` passes with `customer_decision` still null. The
dispatcher's behavior: send a reminder notification to the customer's
tokenized link contact email; configurable cadence is a Phase 3
implementation detail.

This exercises Decision 9's extensibility property. The Phase 1
event_type enum is now:
1. `registration_prep_pre_trigger`
2. `info_request_due`
3. `warranty_expiry_warning`
4. `trigger_confirmation_overdue`
5. `service_report_response_due` (added by Service Report Submission section)
6. `work_authorization_response_overdue` (added by Decision 11)

### Schema sketch

```
work_authorization_templates
  id                          uuid PK
  tenant_id                   uuid NOT NULL FK -> tenants
  name                        text NOT NULL
  warrantor_field_config      jsonb NOT NULL
                              -- the configuration of warrantor-completed
                              -- fields shown to the customer as read-only
                              -- context (requestor info, planned dates,
                              -- crew size, SOW activity)
  customer_field_config       jsonb NOT NULL
                              -- the configuration of customer-entered
                              -- fields (O&M contact info, site access,
                              -- gate codes, special access requirements)
  legal_language              jsonb NOT NULL
                              -- ProseMirror-compatible JSON; the tenant-
                              -- defined legal/operational language that
                              -- accompanies the form
  is_default                  boolean NOT NULL DEFAULT false
                              -- at most one default per tenant
  deleted_at                  timestamptz nullable
                              -- soft-delete required; retired templates
                              -- must remain queryable for documents
                              -- generated from them
  created_at                  timestamptz NOT NULL DEFAULT now()
  updated_at                  timestamptz NOT NULL DEFAULT now()
```

```
work_authorization_documents
  id                                uuid PK
  tenant_id                         uuid NOT NULL FK -> tenants
  claim_id                          uuid NOT NULL FK -> claims
                                    -- NO UNIQUE constraint;
                                    -- one-to-many with claim
  template_id                       uuid NOT NULL FK ->
                                      work_authorization_templates
  template_snapshot                 jsonb NOT NULL
                                    -- template content captured at
                                    -- document generation time, frozen
  event_type                        text NOT NULL
                                    -- 'inspection' | 'repair_work' |
                                    --   'site_visit' | future types
                                    -- CHECK constraint enforces values
                                    -- identifies what on-site activity
                                    -- this authorizes
  event_reference_id                uuid nullable
                                    -- FK to the specific event entity
                                    -- (inspections.id when event_type =
                                    -- 'inspection', etc.); shape resolved
                                    -- at implementation time per
                                    -- event_type (see open question 11b)
  status                            text NOT NULL DEFAULT 'draft'
                                    -- 'draft' | 'sent' | 'approved' |
                                    --   'denied' | 'revised' | 'resent' |
                                    --   'withdrawn'
                                    -- CHECK constraint enforces values
  expected_response_date            date nullable
                                    -- warrantor-set date by which
                                    -- customer response is expected;
                                    -- drives reminder event firing
  
  -- Warrantor-completed fields (set at work_plan stage by warranty team)
  requestor_name                    text NOT NULL
  requestor_company                 text NOT NULL
  requestor_phone                   text nullable
  requestor_email                   text NOT NULL
  planned_start_at                  timestamptz NOT NULL
  planned_end_at                    timestamptz NOT NULL
  crew_size                         integer NOT NULL
  sow_activities                    jsonb NOT NULL
                                    -- ProseMirror-compatible JSON;
                                    -- the planned Scope of Work
  
  -- Customer-entered fields (filled when customer responds)
  om_provider_company               text nullable
  om_contact_name                   text nullable
  om_contact_phone                  text nullable
  om_contact_email                  text nullable
  site_emergency_address            jsonb nullable
                                    -- structured address; shape consistent
                                    -- with project's site_address pattern
  site_accessibility_date           date nullable
  operating_hours                   text nullable
  special_access_required           boolean nullable
  special_access_details            jsonb nullable
                                    -- ProseMirror-compatible JSON;
                                    -- conditional on
                                    -- special_access_required = true
  gate_code_needed                  boolean nullable
  gate_code_details                 jsonb nullable
                                    -- conditional on gate_code_needed = true
  customer_comments                 jsonb nullable
                                    -- optional response, ProseMirror-
                                    -- compatible JSON; safety orientations,
                                    -- check-in/check-out, observations
  
  -- Approval / denial outcome
  customer_decision                 text nullable
                                    -- 'approved' | 'denied'
                                    -- nullable until customer responds
  denial_explanation                jsonb nullable
                                    -- ProseMirror-compatible JSON;
                                    -- required when customer_decision =
                                    -- 'denied' (enforced app-layer)
  
  -- Signature artifact (only populated on approval)
  signer_name_typed                 text nullable
                                    -- the customer's typed-name signature
  authorization_acknowledged        boolean nullable
                                    -- the "I authorize" checkbox; must be
                                    -- true for an approval submission
  
  -- Customer who completed the request
  request_completed_by_name         text nullable
                                    -- the customer's representative name
  
  -- Token storage (mirrors other tokenized interaction patterns)
  customer_token                    text nullable
                                    -- single-use token for the tokenized
                                    -- access link; null after consumption
  customer_token_expires_at         timestamptz nullable
  
  -- Lifecycle timestamps
  requested_at                      timestamptz NOT NULL DEFAULT now()
                                    -- when warrantor created and sent the
                                    -- request
  responded_at                      timestamptz nullable
                                    -- when customer submitted their
                                    -- response
  
  created_at                        timestamptz NOT NULL DEFAULT now()
  updated_at                        timestamptz NOT NULL DEFAULT now()
  -- CHECK / app-layer invariant: tenant_id matches the referenced
  -- claim's tenant_id
```

```
work_authorization_revisions
  id                              uuid PK
  tenant_id                       uuid NOT NULL FK -> tenants
  work_authorization_document_id  uuid NOT NULL FK ->
                                    work_authorization_documents
  revised_by_user_id              uuid NOT NULL FK -> public.users(id)
                                  -- the warrantor user who made the
                                  -- revision
  revision_reason                 jsonb NOT NULL
                                  -- ProseMirror-compatible JSON;
                                  -- typically captures the denial reason
                                  -- that triggered this revision
  field_changes                   jsonb NOT NULL
                                  -- structured record of what fields
                                  -- changed (before/after pairs);
                                  -- shape is a Phase 3 implementation
                                  -- detail
  revised_at                      timestamptz NOT NULL DEFAULT now()
```

### Cross-entity dependencies

- **Claims (FK):** parent entity. ON DELETE behavior parallel to other
  claim-child FK flags (Phase 3 implementation detail).
- **Inspections (event reference):** when `event_type = 'inspection'`,
  the `event_reference_id` points to the inspections row. Work
  Authorization must exist with `customer_decision = 'approved'` before
  the inspection's status can advance from 'requested' to 'scheduled'
  (the on-site activity gate). This resolves the Inspections section's
  flagged "ALA gate interaction with inspections lifecycle" question
  (re-resolved against Work Authorization rather than ALA — the gate is
  Work Authorization, not ALA).
- **Work Plan Workflow (event reference):** when `event_type =
  'repair_work'`, the `event_reference_id` points to the work plan
  entity. Work Authorization must exist with `customer_decision =
  'approved'` before work plan execution can commence.
- **Clock Event Infrastructure:** the new event type
  `work_authorization_response_overdue` fires reminders when
  `expected_response_date` passes with no response.
- **Custom Field System (Decision 3):** Work Authorization is NOT in
  Phase 1 custom-field entity scope. The template's
  `customer_field_config` and `warrantor_field_config` JSONB serve as
  the tenant-configurable mechanism instead.
- **Acknowledgment Gate Pattern (Decision 12):** Work Authorization
  uses Decision 12's Acknowledgment Gate Pattern via `gate_purpose =
  'work_authorization'`. When a tenant has configured a Site Readiness
  & Safety Requirements gate (or equivalent), the customer encounters
  the gate as the first screen of the tokenized link before reaching
  the Work Authorization form.

### Open architectural questions deferred

**11a — Resolved.** Originally flagged: denial-to-resolution flow. Now
resolved by 11.5 (revise-and-resend with revision history).

**11b — Polymorphic `event_reference_id` FK shape.** Different target
tables per `event_type` (inspections, work plans, future types). Whether
this is implemented as a single nullable column with application-layer
dispatch, separate event-type-specific columns (e.g., `inspection_id`,
`work_plan_id`), or a junction table is a Phase 3 implementation detail.

### Decision implications for already-committed sections

- **Inspections Foundation:** the cross-entity dependency on Customer
  Work Authorization (flagged in that section) is now architecturally
  resolved. The Inspections section's gate-behavior reference to "Work
  Authorization before joint inspection commences" maps to Work
  Authorization with `customer_decision = 'approved'`. No section
  revision required; the existing flag-language is consistent.
- **Service Report Submission:** no direct interaction with Work
  Authorization. No section revision required.
- **ALA System:** ALA blocking-gate behavior and Work Authorization
  blocking-gate behavior are now both locked as separate but parallel
  mechanisms. ALA gates investigation (whether the warranty
  determination can proceed); Work Authorization gates on-site presence.
  The two operate independently and can both apply to the same claim.

---

## Decision 12: Customer-Facing Disclaimer / Acknowledgment Gate Pattern

**Decided in Session 5e (Phase 3 Tier 3 triage-and-resolve session).**

### Context

During Decision 11 resolution, Andre surfaced an architectural pattern
visible in operational reality but not yet documented in v2: certain
tokenized customer interactions require a pre-form acknowledgment gate
that must be completed before the customer can access the actual
interaction form.

Two confirmed instances:
- Site Readiness & Safety Requirements gate for Customer Work
  Authorization
- Warranty Claim Submission Requirements gate for Claim Intake

Both have the same shape: tenant-defined content (legal/safety/operational
language), customer must read and check an acknowledgment box, then
proceeds to the actual form. The content is admin-configured per tenant;
the gate pattern itself is platform architecture.

### Question

Should this be:
1. Treated as a one-off feature of specific sections, or
2. Architected as a platform-wide pattern any tokenized customer
   interaction can opt into via tenant configuration?

### Resolution

**Locked as a platform-wide pattern documented at Tier 1** (alongside
Stateless Tokenized Interaction, FK + Snapshot, Standard RLS, etc.)
because it's reused across multiple sections.

**Seven locked commitments:**

**12.1: Two-table parent-child shape.**
- `acknowledgment_gate_templates` — tenant-defined, soft-delete required
- `acknowledgment_gate_records` — per-acknowledgment-event instantiations
  with frozen content_snapshot for defensibility

**12.2: Per-purpose configuration via `gate_purpose` enum.**
- `claim_submission`
- `work_authorization`
- Future tokenized customer interaction types
- Extensible like clock_events event_type

**12.3: Optional per tenant per purpose.**

The platform supports gates natively, but tenants without configured
gates for a given purpose skip the gate. The platform doesn't enforce
safety/legal requirements on warrantors who already have their own
external compliance processes.

**12.4: One gate per protected entity in Phase 1.**

Multi-gate-per-entity is deferred as speculative. Multiple acknowledgments
needed for a single entity can be combined into a single longer gate
document.

**12.5: Rich-text content via ProseMirror-compatible JSON.**

Per Decision 4's storage format. Gives tenants flexibility for formatting
without the platform pre-deciding shape.

**12.6: Polymorphic protected-entity reference.**

`authorized_entity_type` + `authorized_entity_id` columns. Implementation
detail of the polymorphic FK shape deferred to Phase 3.

**12.7: Gate mechanics.**

- Customer clicks tokenized link, encounters gate as first screen if
  tenant has one configured for the interaction's purpose
- Customer must check acknowledgment box (and optionally type name if
  gate config requires)
- On submission, `acknowledgment_gate_records` row is created with
  frozen content snapshot, customer identity capture, timestamp, IP, and
  polymorphic reference to the protected entity
- Server Action checks for the record before rendering the protected
  form; if no record exists for this entity, gate is shown; if record
  exists, form is shown
- One acknowledgment per protected entity (customer doesn't re-acknowledge
  for the same entity)

### Schema sketch

```
acknowledgment_gate_templates
  id                          uuid PK
  tenant_id                   uuid NOT NULL FK -> tenants
  gate_purpose                text NOT NULL
                              -- 'claim_submission' |
                              --   'work_authorization' | other future
                              --   tokenized interaction types
                              -- CHECK constraint enforces allowed values;
                              -- extensible like clock_events event_type
  name                        text NOT NULL
                              -- tenant-friendly identifier
  content                     jsonb NOT NULL
                              -- ProseMirror-compatible JSON;
                              -- the gate's body content
  acknowledgment_label        text NOT NULL
                              -- the text shown next to the checkbox
                              -- (e.g., "By checking this box, I confirm...")
  requires_typed_name         boolean NOT NULL DEFAULT false
                              -- whether the gate config requires the
                              -- customer to type their name in addition
                              -- to checking the box
  is_default                  boolean NOT NULL DEFAULT false
                              -- at most one default per
                              -- (tenant_id, gate_purpose)
  deleted_at                  timestamptz nullable
                              -- soft-delete required; retired gates
                              -- must remain queryable for records that
                              -- captured acknowledgment against them
  created_at                  timestamptz NOT NULL DEFAULT now()
  updated_at                  timestamptz NOT NULL DEFAULT now()
```

```
acknowledgment_gate_records
  id                          uuid PK
  tenant_id                   uuid NOT NULL FK -> tenants
  template_id                 uuid NOT NULL FK ->
                                acknowledgment_gate_templates
  template_content_snapshot   jsonb NOT NULL
                              -- frozen content at acknowledgment time
                              -- (the customer agreed to exactly this
                              -- content, not whatever the current
                              -- template says)
  acknowledger_name           text nullable
                              -- if the gate requires a typed name
  acknowledged_at             timestamptz NOT NULL
  acknowledger_ip             text nullable
                              -- captured for audit trail
  
  -- Polymorphic reference to what this acknowledgment authorizes
  authorized_entity_type      text NOT NULL
                              -- 'claim' | 'work_authorization_document'
                              --   | future types
                              -- CHECK constraint enforces allowed values
  authorized_entity_id        uuid NOT NULL
                              -- FK target depends on authorized_entity_type;
                              -- shape resolved per type at implementation
  
  created_at                  timestamptz NOT NULL DEFAULT now()
```

### Cross-entity dependencies

- **All tokenized customer interactions:** any section using the
  Stateless Tokenized Interaction Pattern with a `gate_purpose` value
  may have a configured gate. Phase 1 instances: Claim Intake
  (`gate_purpose = 'claim_submission'`), Customer Work Authorization
  (`gate_purpose = 'work_authorization'`).

### Open architectural questions

**12a — Resolved.** Originally flagged: optional vs mandatory gates.
Now resolved by 12.3 (optional per tenant per purpose).

**12b — Resolved.** Originally flagged: multiple gates per protected
entity. Now resolved by 12.4 (one gate per entity in Phase 1).

**12c — Resolved.** Originally flagged: gate content shape. Now resolved
by 12.5 (rich-text via ProseMirror).

### Decision implications for already-committed sections

- **Claim Intake Data Model:** the existing section needs revision to
  cross-reference Decision 12. The "Stateless tokenized intake link"
  subsection should add a paragraph noting that when a tenant has
  configured a gate for `gate_purpose = 'claim_submission'`, the
  customer encounters the gate first. This revision is scheduled as
  Decision 12 follow-up work.
- **Service Report Submission:** the section was drafted without
  considering this pattern, but no section revision is required — the
  pattern is documented at Tier 1 and the section can reference it
  without explicit inclusion. Worth flagging in a future review if
  service report customer review uses the pattern.
- **Inspections Foundation:** no direct application (Inspections
  doesn't involve a tokenized customer interaction; customer-facing
  aspects happen through Work Authorization).

### Implementation status

Decision 12 is locked but the Tier 1 Acknowledgment Gate Pattern section
is not yet drafted in v2. The pattern section should be drafted before
or in parallel with Customer Work Authorization section drafting, since
Work Authorization cross-references it.

---

---

## Decision 13: Work Plan Execution Path and Internal Team Capture

**Decided in Session 5f (Phase 3 Tier 3 Work Plan Workflow pre-triage).**

### Context

Pre-triage of source materials for the Work Plan Workflow section
(SOP 6 Key Components of a Work Plan, SOP 1 Accepted Warranty Claim
Lifecycle, Work Plan Data Inputs workbook, v1 anchor architecture's
Four Work Plan Execution Paths) surfaced a reconciliation question
between the workbook's three-value Service Type dropdown and v1's
four execution paths.

### Question

The Work Plan Data Inputs workbook has a Service Type dropdown with
three values: Internal–Warranty FOS, Internal–Construction Support,
Ext. Subcontractor. v1 anchor architecture has Four Work Plan
Execution Paths: Path 1 (Warrantor Self-Performs), Path 2A
(Scope-Owned Subcontractor), Path 2B (Outsourced Subcontractor), and
Path 3 (Customer Self-Services). These taxonomies do not map cleanly.

What is the locked enum shape for capturing execution path and
internal team assignment?

### Resolution

**Five locked commitments:**

**13.1: Two-column shape for execution path and internal team capture.**

- `work_plans.execution_path` — platform-locked enum capturing v1's
  four paths
- `work_plans.internal_team_id` — FK nullable, only populated when
  execution_path = 'warrantor_self_performs'

**13.2: execution_path enum values (locked, platform-level):**

- `warrantor_self_performs` — internal team executes the repair
- `scope_owned_subcontractor` — original installer with active
  warranty obligation executes the repair (v1's Path 2A)
- `outsourced_subcontractor` — third party procured via RFQ executes
  the repair (v1's Path 2B)
- `customer_self_services` — customer executes the repair with
  warrantor reimbursement (v1's Path 3)

Maps to v1's Four Work Plan Execution Paths verbatim. CHECK
constraint enforces values; extensible via migration if a fifth
execution path surfaces operationally.

**13.3: New `internal_teams` table — tenant-defined internal team
registry.**

The workbook's distinction between "Internal–Warranty FOS" and
"Internal–Construction Support" reflects a tenant-specific
organizational reality (primary internal team vs fallback internal
team when external resources aren't viable or scope exceeds primary
team capacity). The team labels themselves are tenant-specific
(Terrasmart uses Warranty FOS and Construction Support; other
warrantors define their own naming).

The platform commits to supporting the operational pattern (each
tenant may define multiple internal teams used for warranty work)
without enshrining specific team labels. The `internal_teams` table
is the tenant-configurable registry.

**13.4: Architectural commitment to the operational structure, not
the labels.**

The two-team or n-team operational pattern (primary internal team,
one or more fallback internal teams) is universal across warrantors
industry-wide. The team labels (e.g., Terrasmart's "Warranty FOS"
and "Construction Support") are NOT platform-locked enum values.
Each warrantor defines their own team labels through the
internal_teams table.

**13.5: No is_primary boolean on internal_teams.**

A primary-vs-fallback distinction is not architecturally tracked at
the team level. UI default-selection behavior (pre-selecting a
warrantor's preferred default team when creating a work_plan) can
live in tenants.settings if needed. Cost-per-team queries answer
through the future Cost Tracking section joining work_plans to
internal_teams via internal_team_id. Verified via chat 4 scan: no
existing v2 content depends on a primary-vs-fallback team
distinction.

### Schema sketch

```
internal_teams
  id              uuid PK
  tenant_id       uuid NOT NULL FK -> tenants
                  -- denormalized per Standard RLS Pattern
  name            text NOT NULL
                  -- tenant's own label (e.g., "Warranty FOS",
                  -- "Construction Support", "Tier 1 Service",
                  -- whatever fits the warrantor's organizational
                  -- structure)
  description     text nullable
                  -- optional explanatory note
  deleted_at      timestamptz nullable
                  -- soft-delete required; historical work_plans
                  -- retain internal_team_id FK even when teams
                  -- are retired
  created_at      timestamptz NOT NULL DEFAULT now()
  updated_at      timestamptz NOT NULL DEFAULT now()
```

The work_plans.execution_path and work_plans.internal_team_id
columns are detailed in Decision 15's Work Plan schema sketch.

### Cross-entity dependencies

- **work_plans (FK from work_plans.internal_team_id):** the internal
  team is referenced by a Work Plan when its execution_path =
  'warrantor_self_performs'. CHECK / app-layer invariant:
  internal_team_id is non-null when execution_path =
  'warrantor_self_performs', null otherwise.
- **Future Cost Tracking section:** cost-per-internal-team and
  cost-per-execution-path queries answer by joining cost-tracking
  records to work_plans and reading these two columns. The Cost
  Tracking section, when drafted, must ensure its schema supports
  these joins.

### Open architectural questions deferred

- **ON DELETE behavior on internal_team_id.** Soft-delete on
  internal_teams means hard-deletion isn't an ordinary path; the FK
  clause is Phase 3 implementation detail.
- **Internal team membership tracking.** Whether internal_teams
  should reference contacts or tenant users for team-membership
  tracking (which warrantor user is on which team) is a separate
  question not in Decision 13's scope.

### Decision implications for already-committed sections

None. Decision 13 introduces new architecture (the internal_teams
table and the execution_path / internal_team_id columns on
work_plans) without modifying any committed v2 section.

---

## Decision 14: Notice of Defect Entity

**Decided in Session 5f (Phase 3 Tier 3 Work Plan Workflow
pre-triage).**

### Context

SOP 1 (Accepted Warranty Claim Lifecycle) describes the "Notice of
Defect" as the formal communication from the warranty professional
to a believed-responsible party (subcontractor or internal team)
saying "this defect is yours; respond with acceptance/rejection."
The architecture needed to determine whether Notice of Defect is a
separate entity, a state on the Work Plan, columns on the claim, or
something else.

Initial framing assumed Notice of Defect was tightly coupled to
Work Plan (i.e., Notice of Defect IS the initial state of a Work
Plan, with acceptance triggering Work Plan finalization and
rejection triggering a new Work Plan). Andre pushed back: Notice of
Defect is not necessarily connected to a Work Plan. The claim flow
includes scenarios where the responsible subcontractor is put on
notice at claim review time, but no Work Plan is ever created
because the subcontractor handles remediation independently OR the
matter is contractually outside warrantor coordination OR claim
resolution evolves without warrantor-coordinated execution.

Andre's correction: Notice of Defect's purpose is "the party
believed to be responsible has been officially notified and that is
a matter of record." It is an audit artifact of official
notification, separate from any downstream execution work.

Further refinement: acceptance of a Notice of Defect is not
bulletproof closure. The subcontractor might accept at the notice
stage, get to site, and shift their position ("not on me, it's the
other guy"). Architecture must capture the binding response at the
moment of response without committing to that response as final
resolution.

### Question

What is the architectural shape of the Notice of Defect, given that
it is:
- A claim-level audit artifact, not a Work Plan state
- Independently created at any point in claim lifecycle (claim review
  time OR later)
- Multiple per claim (recipient changes as responsibility picture
  evolves)
- A binding accept/reject response capture, but not closure-binding
- Sent to subcontractors (Path 2A or 2B), internal teams (Path 1),
  OR other party types (vendors for vendor-supplied component issues,
  original installers, future types)
- Decoupled from Work Plan creation downstream (some lead to Work
  Plans, some don't)

### Resolution

**Ten locked commitments:**

**14.1: Separate entity, claim-child, one-to-many.**

A `notices_of_defect` table. NO UNIQUE constraint on claim_id —
multiple Notices of Defect per claim are operationally real and
expected across the claim lifecycle.

**14.2: Recipient via Decision 1's dual-FK + Snapshot Pattern,
broadened.**

`recipient_contact_id` FK to contacts (any contact_type —
subcontractor, vendor, original installer, future types) OR
`recipient_user_id` FK to public.users (internal team assignee).
CHECK constraint: exactly one non-null.

Recipient identity captured with snapshot columns at notification
time (name, email, company) for audit-defensibility per the FK +
Snapshot Pattern.

**14.3: Binding response with three states, historical record
preserved.**

`response_status` enum: 'pending', 'accepted', 'rejected'. Response
timestamp captured.

Post-acceptance position changes (recipient accepts then later
disputes on site or in scope) are NOT captured as revisions to this
Notice of Defect's response_status. They become NEW events — a new
Notice of Defect to another party, a claim status transition, an
escalation event — captured in their respective sections. Historical
record of the original response is preserved.

**14.4: No FK relationship to Work Plan in either direction.**

The Notice of Defect's architectural responsibility ends at response
capture. Whether a Work Plan, downstream tracking, dispute, or other
activity follows from an accepted Notice is operational and
contract-dependent — not encoded in the schema. notices_of_defect
has no work_plan_id FK; work_plans has no notice_of_defect_id FK.

If a future analysis needs to ask "which Notice of Defect led to
this Work Plan", it's an application-layer question answered by
reading the claim's history, not a schema-enforced relationship.

**14.5: Stateless Tokenized Interaction Pattern's sixth canonical
use.**

The recipient receives a tokenized email link to respond. Same
pattern as five prior uses (claim intake, registration assignee
submission, supply-only delivery reporting, service report customer
review, Customer Work Authorization). Token storage on the
notices_of_defect row via recipient_token + recipient_token_expires_at
columns per the "shape to copy, not shared store" rule.

**14.6: Notice of Defect can be created at any point in claim
lifecycle.**

Notice of Defect can be sent at claim review time (during initial
responsibility determination) OR later (after Joint Inspection
findings, after scope investigation reveals a different responsible
party, etc.). The architecture does not constrain when
notices_of_defect rows can be created — operational decision
governed by Server Action authority rules.

**14.7: expected_response_date is NOT NULL.**

Every Notice of Defect has a warrantor-set response deadline. This
drives reminder firing through the clock event infrastructure.

**14.8: notification_message field captured.**

Warrantor can include a custom message (ProseMirror-compatible JSON
per Decision 4) along with the claim summary snapshot.
Tenant-configurable messaging at the per-Notice level.

**14.9: Seventh clock event type added to Decision 9's enum.**

`notice_of_defect_response_overdue` fires when expected_response_date
passes with response_status still 'pending'. Decision 9's
clock_events event_type enum now has seven values:

1. registration_prep_pre_trigger
2. info_request_due
3. warranty_expiry_warning
4. trigger_confirmation_overdue
5. service_report_response_due
6. work_authorization_response_overdue
7. notice_of_defect_response_overdue (added by Decision 14)

**14.10: Phase 1 contact_type enum extension flagged.**

Adding `vendor_contact` and `original_installer_contact` (or
equivalent) to the Phase 1 contact_type enum is a routine Phase 3
implementation detail when Notice of Defect functionality is built.
Not new architecture — extension via migration.

### Schema sketch

```
notices_of_defect
  id                            uuid PK
  tenant_id                     uuid NOT NULL FK -> tenants
                                -- denormalized per Standard RLS Pattern
  claim_id                      uuid NOT NULL FK -> claims
                                -- NO UNIQUE constraint;
                                -- one-to-many with claim
  
  -- Recipient capture (the party put on notice)
  -- Decision 1's dual-FK + Snapshot Pattern, broadened
  recipient_contact_id          uuid nullable FK -> contacts
                                -- when recipient is a subcontractor,
                                -- vendor, original installer, or
                                -- other contact_type
  recipient_user_id             uuid nullable FK -> public.users(id)
                                -- when recipient is an internal team
                                -- assignee (warrantor user)
  recipient_name_snapshot       text NOT NULL
                                -- frozen at notification time
  recipient_email_snapshot      text NOT NULL
  recipient_company_snapshot    text nullable
                                -- frozen at notification time
  -- CHECK constraint: exactly one of recipient_contact_id or
  -- recipient_user_id is non-null
  
  -- The notification event
  notified_at                   timestamptz NOT NULL DEFAULT now()
                                -- the matter-of-record moment
  notified_by_user_id           uuid NOT NULL FK -> public.users(id)
                                -- the warranty professional who sent
                                -- the notification
  
  -- What was sent
  claim_summary_snapshot        jsonb NOT NULL
                                -- frozen snapshot of claim information
                                -- shared with recipient at notification
                                -- (claim_id, defect description,
                                -- relevant claim_type_data, etc.)
  notification_message          jsonb nullable
                                -- ProseMirror-compatible JSON;
                                -- warrantor's custom message body
                                -- accompanying the claim summary
  
  -- Binding response capture
  response_status               text NOT NULL DEFAULT 'pending'
                                -- 'pending' | 'accepted' | 'rejected'
                                -- CHECK constraint enforces values
  response_at                   timestamptz nullable
  response_explanation          jsonb nullable
                                -- ProseMirror-compatible JSON;
                                -- recipient's reasoning, particularly
                                -- important for rejections
  
  -- Token storage (Stateless Tokenized Interaction Pattern,
  -- sixth canonical use)
  recipient_token               text nullable
                                -- single-use token; null after
                                -- consumption
  recipient_token_expires_at    timestamptz nullable
  
  -- Response deadline (drives clock event firing)
  expected_response_date        date NOT NULL
                                -- warrantor-set deadline
  
  created_at                    timestamptz NOT NULL DEFAULT now()
  updated_at                    timestamptz NOT NULL DEFAULT now()
  -- CHECK / app-layer invariant: tenant_id matches the referenced
  -- claim's tenant_id
```

### Cross-entity dependencies

- **claims (FK parent).** Notice of Defect is a claim-child entity.
  ON DELETE behavior on claim_id is a Phase 3 implementation detail
  parallel to other claim-child FK flags.
- **contacts and public.users (recipient dual-FK).** Recipient
  identity captured via FK + Snapshot Pattern. New contact_type
  values added by migration as needed.
- **Clock Event Infrastructure (Decision 9).** Seventh event type
  added: notice_of_defect_response_overdue.
- **Work Plans.** No FK relationship in either direction. The
  Notice-of-Defect-to-Work-Plan operational sequence is captured at
  the application layer through claim history, not at the schema
  level.

### Open architectural questions deferred

- **ON DELETE behavior on claim_id.** Parallel to other claim-child
  FK flags.
- **ON DELETE behavior on recipient_contact_id and recipient_user_id.**
  Soft-delete on contacts and tenant users means hard-deletion isn't
  ordinary; FK clause is Phase 3 implementation detail.
- **claim_summary_snapshot shape.** The structured shape of the
  frozen claim snapshot (which claim fields are captured, JSONB
  format details) is a Phase 3 implementation detail.
- **Multiple notices_of_defect rows to the same recipient on the
  same claim.** Whether resending a Notice of Defect to a
  previously-noticed party creates a new row or updates the existing
  row is a Phase 3 operational question.

### Decision implications for already-committed sections

None. Decision 14 introduces a new entity (notices_of_defect)
without modifying any committed v2 section.

---

## Decision 15: Work Plan Status State Machine

**Decided in Session 5f (Phase 3 Tier 3 Work Plan Workflow
pre-triage).**

### Context

SOP 1 (Accepted Warranty Claim Lifecycle) describes the operational
Work Plan lifecycle: Work Plan is drafted, sent for Customer Work
Authorization, authorized, repair executes, Service Report submitted,
claim closes. Several of these lifecycle moments belong to OTHER
entities (Customer Work Authorization per Decision 11; Service
Report per the Service Report Submission section) rather than to
the Work Plan itself.

The state machine needs to capture only the lifecycle moments that
are uniquely Work Plan moments — not states that other entities
already track.

### Question

What is the locked status enum for the work_plans table, and which
lifecycle moments belong to other entities rather than to the Work
Plan?

### Resolution

**Five locked commitments:**

**15.1: Five-value status state machine.**

The work_plans.status column has five values:

- `draft` — Work Plan is being authored. Editable freely by the
  authoring party (subcontractor in Path 2A, warranty professional
  in Path 1 or post-rejection scenarios). The customer cannot see a
  draft.
- `sent_for_authorization` — Work Plan has been bundled into a
  Customer Work Authorization request and sent to the customer.
  The Customer Work Authorization's own state machine (Decision 11)
  governs the approval/denial/revision lifecycle; the Work Plan stays
  in sent_for_authorization while that runs, including across
  revision cycles on the Work Authorization.
- `authorized` — A Customer Work Authorization for this Work Plan
  has been approved by the customer. Work Plan is ready for execution
  per the warrantor's coordination.
- `completed` — Repair work is complete and a Service Report has
  been submitted per the Service Report Submission section's
  lifecycle. Claim-level transitions and customer review of the
  Service Report continue from here.
- `cancelled` — Work Plan was created but will not be executed.
  Terminal state for Work Plans that are abandoned (situation
  changed, customer rejected Work Authorization and warrantor opted
  not to revise, a different Work Plan superseded this one, etc.).

CHECK constraint enforces values. Transitions are governed by Server
Actions, not direct UPDATE on the column.

**15.2: No `submitted` state.**

A previously-considered `submitted` state (Work Plan finalized but
not yet sent for Work Authorization) collapses into the draft →
sent_for_authorization transition. Draft is editable up to the point
of sending; the act of sending IS the transition.

**15.3: No `in_execution` state.**

A previously-considered `in_execution` state (repair actively
underway on-site) is NOT modeled on the Work Plan. That lifecycle
moment is tracked at the claim status level, not the Work Plan
status level. Modeling it on both would duplicate state.

**15.4: No scheduling state between authorized and completed.**

A previously-considered intermediate state ("scheduled but not yet
started") is NOT modeled. Same reasoning as in_execution — scheduling
is a claim-level concern, captured in the claim's lifecycle rather
than the Work Plan's status.

**15.5: No revision/resent states on the Work Plan.**

The Customer Work Authorization (Decision 11) has revised/resent
states governing the customer-rejection-and-revision lifecycle.
The Work Plan does NOT replicate these states. When a customer
rejects a Work Authorization and the warrantor revises and re-sends,
the Work Plan stays in sent_for_authorization while the underlying
Work Authorization document goes through its own revision cycle.
The Work Plan only transitions to authorized when a Work Authorization
for it is finally approved.

### Schema sketch

The work_plans schema is detailed in the Work Plan Workflow section
when drafted. The status column shape:

```
work_plans
  ...
  status              text NOT NULL DEFAULT 'draft'
                      -- 'draft' | 'sent_for_authorization' |
                      --   'authorized' | 'completed' | 'cancelled'
                      -- CHECK constraint enforces values
  ...
```

### Cross-entity dependencies

- **Customer Work Authorization (Decision 11).** Work Plan's
  sent_for_authorization state corresponds to the existence of one
  or more Work Authorization documents for this Work Plan. The Work
  Plan transitions to authorized when a Work Authorization
  customer_decision = 'approved' for it. The revision lifecycle on
  Work Authorizations does not propagate to Work Plan status.
- **Service Report Submission section.** Work Plan transitions to
  completed when a service_report row exists for the claim
  documenting completion. Service Report's own customer review
  lifecycle (accept/dispute/acquiesce) continues independently.
- **Claim status.** Several Work Plan lifecycle moments
  (scheduling, on-site execution, repair finalization) are tracked
  at the claim status level rather than on the Work Plan. The Tier 3
  claim lifecycle section will settle which specific claim status
  values transition on which Work Plan state changes.

### Open architectural questions deferred

- **Authority rules for status transitions.** Which roles can move
  Work Plans through which transitions (e.g., can any Reviewer
  cancel a Work Plan, or only Team Admin; can a different reviewer
  send a Work Plan for authorization that another reviewer drafted)
  are operational authorization concerns, not schema-level.
- **The transition from completed back to a non-terminal state.**
  Whether a completed Work Plan can ever transition backward (e.g.,
  Service Report disputed by customer leads to repair re-execution)
  is operational and depends on whether the dispute resolution path
  creates a new Work Plan or reopens an existing one. Phase 3
  operational decision.

### Decision implications for already-committed sections

- **Customer Work Authorization section (Decision 11)** is the
  source of revision lifecycle for the customer approval cycle. The
  Work Plan Workflow section, when drafted, must cross-reference
  Decision 11 for revision mechanics rather than re-documenting them
  on the Work Plan side.
- **Service Report Submission section** is the source of completion
  capture and customer review lifecycle. Work Plan Workflow section
  cross-references the Service Report section rather than duplicating
  its lifecycle.
- **Tier 3 Claim Lifecycle section (future)** will settle the
  specific claim status values that transition on Work Plan state
  changes. Decision 15 does not pre-commit those transitions.

---

## Decision 16: Parts Claims Out of Work Plan Workflow Scope

**Decided in Session 5f (Phase 3 Tier 3 Work Plan Workflow
pre-triage).**

### Context

Parts Claims (claim_type = 'replacement_parts') are a distinct
claim_type already locked in the Claim Intake Data Model section,
with intake fields captured in claim_type_data JSONB per the Parts
Claim Datapoints workbook. Operationally, Parts Claim fulfillment
involves shipping/receiving logistics — sourcing the part, shipping
to site, customer or O&M provider receiving, installing — that
differs fundamentally from field-repair execution covered by the
Work Plan Workflow's schema (planned arrival, crew size, on-site
SOW activities).

The Parts Claim Datapoints workbook captures intake fields only —
no fulfillment lifecycle data is documented in any of the source
materials available for the Work Plan Workflow section. Architecting
parts fulfillment within Work Plan Workflow would require
improvising from first principles rather than drafting from
documented operational reality, contrary to Phase 3 discipline.

### Question

Where does Parts Claim fulfillment activity live architecturally?

### Resolution

**Five locked commitments:**

**16.1: Parts Claims do NOT flow through the Work Plan Workflow
section.**

The Work Plan Workflow architecture (Decisions 13, 14, 15) is
designed for field-repair execution at customer sites. Parts Claims
have a fundamentally different downstream lifecycle (shipping/
receiving logistics rather than on-site crew coordination) that the
Work Plan schema and its supporting entities do not naturally fit.

**16.2: Parts Claims complete through a future Parts Fulfillment
section.**

A separate Tier 3 section (or future session) will architect the
Parts Fulfillment lifecycle — sourcing, shipping, tracking,
receiving, defective-part-return, etc. Sources for that section
will need to be assembled (no operational SOP or workbook in the
current source corpus documents this lifecycle).

**16.3: The Work Plan Workflow section explicitly notes this scope
boundary.**

The Work Plan Workflow section's "What is NOT in" subsection will
include a deliberate-omission item stating: Parts Claims
(claim_type = 'replacement_parts') are not handled through the
Work Plan Workflow; their fulfillment lifecycle is architected
separately in a future Parts Fulfillment section.

**16.4: Parts Claims still flow through Claim Intake unchanged.**

The Claim Intake Data Model's claim_type = 'replacement_parts'
schema (already locked in v2) handles Parts Claim intake — what
the customer submits, captured in claim_type_data JSONB per the
Parts Claim Datapoints workbook. Decision 16 changes nothing about
Claim Intake.

**16.5: Parts Claims do not get Notice of Defect, Work Plan, Work
Authorization, or Service Report rows in Phase 1.**

Phase 1 of Parts Claims architecture covers intake only. Whether
parts fulfillment integrates with these existing entities (e.g.,
does shipping involve a Customer Work Authorization for delivery
access?) or has fully separate downstream entities is a future
architectural decision when the Parts Fulfillment section is
drafted.

### Schema sketch

No new schema in Decision 16. The Parts Fulfillment section, when
drafted in a future session, will define its own schema.

### Cross-entity dependencies

- **Claim Intake Data Model.** Parts Claims continue to be captured
  through the existing claim_type = 'replacement_parts' shape. No
  change.
- **Work Plan Workflow.** Parts Claims explicitly excluded from
  Work Plan Workflow's scope.
- **Future Parts Fulfillment section.** Will be architected
  separately when source materials and operational requirements are
  assembled.

### Open architectural questions deferred (all for future Parts Fulfillment section)

- **Parts Fulfillment entity shape.** Whether shipments are 1:1 with
  claims, multiple shipments per claim, what fields track logistics.
- **Relationship to Service Report Submission.** Whether a Parts
  Claim uses the existing service_reports table to capture "customer
  received and installed the part" or whether Parts Fulfillment has
  its own completion capture entity.
- **Clock event types for parts fulfillment.** Shipping reminders,
  delivery confirmation overdue, etc.
- **Customer Work Authorization interaction.** Whether delivery
  access requires its own Work Authorization (event_type =
  'parts_delivery' or similar future value).

### Decision implications for already-committed sections

- **Claim Intake Data Model section:** no change. Parts Claim intake
  continues per the existing claim_type = 'replacement_parts'
  schema.
- **Work Plan Workflow section (when drafted):** must include the
  explicit Parts Claims scope-boundary item per 16.3.

---

## Decision 17: Tenant-Editable Defaults Pattern (formalized as new Tier 1 platform pattern) and application to Inspections

**Decided in Session 5h (Path C — chat 4 verified scope).**

### Context

Surfaced mid-drafting of Work Plan Workflow (Session 5f) when Andre
identified that the currently-committed Inspections Foundation
section's 4-value platform-locked status enum (requested, scheduled,
in_progress, completed) does not reflect enterprise-level operational
workflow. The proposed remediation extended to three new Inspections
enums (inspection_type, inspection_trigger, inspection_status) with
platform-provided defaults that tenants can edit.

Decision 17's pre-session scope note (committed in 5f2934e) identified
that "tenant-editable defaults" was potentially a new Tier 1 platform
pattern beyond v2's existing platform-locked enums and tenant-defined
JSONB/templates. Reserve Forecasting scope note (committed in f8d5e2f)
later identified calculation parameters as a second canonical use of
the same pattern.

Chat 4 verification at Session 5h opening confirmed Path C: formalize
the pattern as a new Tier 1 platform pattern rather than treating it
as an Inspections-specific configuration mechanism.

Pre-triage Decision 18 (Session 5g) resolved Cat 3 #5 and #6.
Decision 18.2 established that inspection_trigger requires "Third
Party" as the eighth default value.

### Question

What is the architectural shape of the Tenant-Editable Defaults Pattern
as a Tier 1 platform pattern, and how does it apply to the three
Inspections enums?

### Resolution

Two major sub-sections: Part A formalizes the pattern; Part B applies
it to Inspections.

### Part A: Tenant-Editable Defaults Pattern formalization

**Nine architectural commitments establish the pattern.**

**17.A.1: Per-enum lookup tables.** The pattern uses per-enum lookup
tables (one table per tenant-editable enum), not a polymorphic-with-
discriminator table. Each lookup table follows the same structural
convention, parallel to internal_teams (Decision 13). Operational
tables reference their lookup table via typed FK.

**17.A.2: Hybrid FK + denormalized value snapshot on operational
tables.** Operational tables carry BOTH an FK to the lookup table AND
a denormalized value snapshot column. The FK provides database-
enforced referential integrity; the snapshot column preserves the
value at row creation time for cross-tenant reporting and audit-
defensibility. The sync invariant is application-layer enforced,
matching the FK + Snapshot Pattern's established convention.

**17.A.3: Platform seeds at provisioning; tenants own forever after.**
Platform default values are seeded into a tenant's lookup tables at
tenant provisioning time. After provisioning, tenants own their
lookup tables completely. The platform has NO propagation, opt-in,
or force mechanism that affects existing tenants' lookup data.
Platform code and infrastructure updates operate on the platform
layer and do not intersect with tenant lookup table data.

**17.A.4: Two columns: platform-canonical value + tenant-editable
label.** Each lookup table has a value column (platform-canonical
identifier, snake_case, lowercase; tenants cannot edit for non-
tenant-added rows) and a label column (tenant-displayed name; freely
editable subject to lock_tier restrictions). Operational tables
denormalize the value (not the label) per 17.A.2. Tenant-added
custom values get an auto-generated value via slugification of the
label.

**17.A.5: Three-category model via lock_tier discriminator.** The
lookup tables carry a lock_tier text column with CHECK constraint:

- platform_locked: platform commits to this value as canonical;
  tenants CANNOT rename or soft-delete. Tenants CAN disable per
  17.A.7.
- platform_seeded: platform provides as starting point; tenants CAN
  rename and disable; tenants CANNOT soft-delete.
- tenant_added: full tenant control (rename, disable, soft-delete
  all allowed).

**17.A.6: Application-layer validation with migration-readiness to
trigger enforcement.** Defense-in-Depth at v1 launch uses
application-layer validation in Server Actions plus minimal DB CHECK
constraints. No PostgreSQL triggers at v1. Migration readiness to
trigger-based enforcement is preserved through five architectural
commitments:

1. Single canonical validation function (all tenant-editable
   defaults reference validation lives in one helper).
2. Single canonical validation rule (row exists AND tenant_id
   matches AND disabled_at IS NULL AND deleted_at IS NULL AND
   lock_tier permits the operation).
3. Schema design supports trigger mode natively (lookup tables'
   columns are in their final shape from v1).
4. Test infrastructure tests the validation rule consistently.
5. Operational logging surfaces validation failures consistently.

The future migration from application-layer to trigger enforcement
is a pure DB-layer change: add trigger functions whose logic mirrors
the canonical validation function. No application code changes. No
schema changes. No data migration.

**17.A.7: Disable and soft-delete semantics.**

- disabled_at: tenant-disabled. Hides from new-entry dropdowns AND
  from active admin list view. Historical operational records still
  display the value normally. Applies to ALL lock_tiers (including
  platform_locked).
- deleted_at: soft-delete. Applies ONLY to tenant_added rows.

Admin UI provides a "view disabled" surface so tenants can re-enable
disabled values.

**17.A.8: Lookup tables always present; admin UI visibility gated by
feature flag for feature-gated capabilities.** Lookup tables are
always present in the schema across all tenants regardless of feature
flag state. Admin UI visibility is gated by the feature flag. Feature
flag enable/disable is a pure flag operation with no schema
migrations.

**17.A.9: Canonical-text-value design constraint for platform-locked
defaults.** Platform-locked default values seeded into per-tenant
lookup tables MUST use the same canonical value string across all
tenants. Per-tenant rows for the same platform-locked default have
identical value column content. Platform-wide analytics queries
filter by value, not by id. Tenant-added rows have tenant-specific
value strings.

### Pattern lookup table schema (canonical shape)

    <enum_name>s
      id            uuid PK
      tenant_id     uuid NOT NULL FK -> tenants
      value         text NOT NULL
      label         text NOT NULL
      lock_tier     text NOT NULL
                    -- 'platform_locked' | 'platform_seeded' | 'tenant_added'
      sort_order    integer NOT NULL DEFAULT 0
      disabled_at   timestamptz nullable
      deleted_at    timestamptz nullable
                    -- applies ONLY to lock_tier = 'tenant_added'
      created_at    timestamptz NOT NULL DEFAULT now()
      updated_at    timestamptz NOT NULL DEFAULT now()

All tenant-editable defaults lookup tables follow the Standard RLS
Pattern's six steps.

### Mixed-pattern entities: role-based decision tree

When an entity has multiple enum-like columns, each column's pattern
assignment is determined by its operational role:

1. **Workflow-driver** (platform code branches on the value) ->
   platform-locked CHECK enum
2. **Structural axis** (values are universal and drive cost routing
   or authority) -> platform-locked CHECK enum
3. **Categorization** (values legitimately vary by tenant business)
   -> Tenant-Editable Defaults Pattern (lookup table)
4. **Ambiguous** -> default to platform-locked CHECK enum, with
   documented intent to promote to tenant-editable if operational
   pressure surfaces

The asymmetry that drives rule 4: platform-locked-to-tenant-editable
is a forward migration (feasible). Tenant-editable-to-platform-locked
is a breaking change. Lean conservative; promote later as need is
demonstrated.

**Three additional constraints documented in the pattern:**

- **Schema introspection overhead for mixed-pattern entities is
  real.** Operators using generic tools face ergonomic cost. Future
  engineers should add tenant-editable columns deliberately.
- **Platform-wide reporting works only when canonical-text-value
  constraint (17.A.9) is honored.**
- **TypeScript exhaustiveness asymmetry reinforces role separation.**
  Platform-locked enums give exhaustive type checking; tenant-editable
  enums explicitly do NOT (they're data, not code-relevant).

### Part B: Application to Inspections

**Three architectural commitments apply the pattern to Inspections.**

**17.B.1: inspection_types as tenant-editable defaults.** New lookup
table inspection_types created. Four platform-locked default values:

- value: warranty, label: Warranty, lock_tier: platform_locked
- value: condition_assessment, label: Condition Assessment, lock_tier: platform_locked
- value: remediation_verification, label: Remediation Verification, lock_tier: platform_locked
- value: failure_investigation, label: Failure Investigation, lock_tier: platform_locked

Tenants can add Category 3 (tenant_added) inspection types. Tenants
cannot rename or soft-delete the four platform-locked defaults but
CAN disable them per 17.A.7.

The inspections table gains: inspection_type_id (FK to
inspection_types) and inspection_type_value (snapshot of value).

**17.B.2: inspection_triggers as tenant-editable defaults.** New
lookup table inspection_triggers created. Eight platform-locked
default values:

- value: warranty_claim, label: Warranty Claim, lock_tier: platform_locked
- value: customer_request, label: Customer Request, lock_tier: platform_locked
- value: repeat_condition_verification, label: Repeat Condition Verification, lock_tier: platform_locked
- value: post_remediation_verification, label: Post-Remediation Verification, lock_tier: platform_locked
- value: failure_investigation, label: Failure Investigation, lock_tier: platform_locked
- value: preventative_condition_assessment, label: Preventative / Condition Assessment, lock_tier: platform_locked
- value: internal_review, label: Internal Review, lock_tier: platform_locked
- value: third_party, label: Third Party, lock_tier: platform_locked

The Third Party value is required by Decision 18.2. Tenants can add
Category 3 (tenant_added) inspection triggers.

The inspections table gains: inspection_trigger_id and
inspection_trigger_value.

**17.B.3: inspection_status is platform-locked CHECK enum, NOT
tenant-editable defaults.** inspection_status is a workflow-driver
enum. Per the role-based decision tree, workflow-driver enums use
platform-locked CHECK enums, not the tenant-editable defaults
pattern.

The four platform-locked values (REPLACES the currently committed
4-value enum):

- open: inspection created, awaiting activity
- in_progress: observations being captured
- under_review: inspection results being reviewed
- issued: documentation completed and released to customer

No inspection_statuses lookup table is created.

Migration mapping from old enum to new enum:
- requested -> open
- scheduled -> open
- in_progress -> in_progress
- completed -> under_review

The new value 'issued' represents an operational state that did not
exist in the old enum.

### NCR terminology

NCR (non-conformance report) is per-tenant terminology, not platform
vocabulary. The 'issued' status value's platform-level semantic is
"inspection results have been finalized and the resulting
documentation has been released to the customer." Consistent with
Decision 18.1 and Decision 13.4.

### Mixed-pattern entity: Inspections is the first canonical example

The inspections table is the first v2 entity with mixed enum-handling
patterns. Five enum-like columns spanning three patterns:

- performed_by: platform-locked CHECK, Structural axis
- paid_by: platform-locked CHECK, Structural axis
- inspection_type: Tenant-Editable Defaults, Categorization
- inspection_trigger: Tenant-Editable Defaults, Categorization
- inspection_status: platform-locked CHECK, Workflow-driver

This becomes the reference example for the role-based decision tree.

### Schema changes to inspections table

New columns:
- inspection_type_id uuid NOT NULL FK -> inspection_types(id)
- inspection_type_value text NOT NULL (snapshot per 17.A.2)
- inspection_trigger_id uuid NOT NULL FK -> inspection_triggers(id)
- inspection_trigger_value text NOT NULL (snapshot per 17.A.2)

Changed column:
- status: REPLACES the committed 4-value enum (requested, scheduled,
  in_progress, completed) with new 4-value enum (open, in_progress,
  under_review, issued). CHECK constraint enforces new values.

### Cross-entity dependencies

- **Inspections Foundation section** (commit e846e2c, revised in
  Session 5g via commit 065a72b): requires substantial revision to
  reflect Decision 17. Schema changes, mixed-pattern documentation,
  new lookup tables documented as canonical examples, role-based
  decision tree framing. Section revision lands in a separate
  commit following this Decision's commit.

- **Customer Work Authorization section** (commit c8b674d): contains
  a specific status-value reference: "Work Authorization with
  customer_decision = 'approved' is required before the inspection's
  status can advance from 'requested' to 'scheduled'." This becomes
  stale post-Decision 17. The Customer Work Authorization section
  requires targeted revision.

- **Reserve Forecasting capability scope note** (commit f8d5e2f):
  references "Decision 17's tenant-editable defaults pattern" as
  the mechanism for calculation parameters. Reserve Forecasting
  calculation parameters become the second canonical use of the
  pattern.

- **Feature Flag System (Phase 0 Item 18)**: 17.A.8 establishes that
  tenant-editable defaults lookup tables for feature-gated
  capabilities follow the "data always present; UI visibility gated"
  pattern.

### Open architectural questions deferred

- **Performance characteristics of canonical validation helper at
  scale.** Profile and optimize if performance becomes a concern.
  Not anticipated as a v1 concern.

- **Bulk operations on tenant-editable defaults.** A tenant bulk-
  reconfiguring lookup tables may need batch Server Action support.
  Phase 3 implementation detail.

- **Sub-flavors of platform-locked defaults.** Tenants can add
  sub-flavors via tenant_added rows. UI design for "create sub-flavor
  of platform-locked default" is a Phase 3 UI design question.

- **Cross-section pattern documentation.** A dedicated Tier 1 section
  "Tenant-Editable Defaults Pattern" in the architecture reference is
  required. The section's drafting is part of next session's work.

### Decision implications for already-committed sections

Three sections require revision following this Decision's commit:

**1. Inspections Foundation section** (commit e846e2c, revised
065a72b): substantial revision required.

**2. Customer Work Authorization section** (commit c8b674d): targeted
update to the specific status-value reference.

**3. New section required: Tenant-Editable Defaults Pattern (Tier 1).**

All three section revisions land in next session's work, not in
this Decision's commit. The Decision's commit captures the
architectural commitments; the section drafting follows.

---

## Decision 18: Inspections Schema Axes — Claimant Attendance and Requester (resolved as non-features)

**Decided in Session 5g (Decision 17 pre-triage).**

### Context

The committed Inspections Foundation section (commit e846e2c) flagged
two architectural questions as "downstream decisions" beyond the locked
performed_by and paid_by axes:

1. Claimant attendance ("Joint Inspection" posture). Whether
   claimant-invitation or claimant-attendance is captured as structured
   data on inspections.
2. Inspection requester (who asked for the inspection). Whether the
   requester axis is captured as a separate column or boolean.

Both were Cat 3 backlog items (#5 and #6 in the eleven-item Cat 3 list)
flagged for downstream resolution. Pre-triage before Decision 17's
Inspections Expansion work revealed both have clean resolutions that
should land before Decision 17 proceeds so the Inspections schema work
in Decision 17 has these axes already settled.

### Question

Should the inspections schema capture (a) claimant invitation and/or
attendance, and (b) the requester axis (who initiated the inspection)?
Or do these remain operationally tracked without schema columns?

### Resolution

**Two locked commitments:**

**18.1: Claimant attendance is NOT captured at the schema level.**

The "Joint Inspection" framing is Terrasmart-specific terminology —
most warrantors call this simply "Inspection." The invitation to the
claimant is implicit (not formally extended through a tracked gesture)
and claimant attendance is rare and operationally inconsequential to
the warrantor. No downstream workflow reads claimant attendance to
make decisions; cost allocation, authority routing, and reporting all
operate without this signal.

A tenant who operationally cares about tracking claimant attendance
for specific inspections can capture this in inspection_report JSONB
on a per-inspection basis. The platform does not add claimant-related
columns (no claimant_invited, no claimant_attended, no
joint_inspection boolean).

This resolves the Cat 3 #5 question.

**18.2: Requester axis is captured by inspection_trigger, NOT a
separate column.**

The WHO question (who requested the inspection) is answered by reading
the inspection_trigger value. Each trigger value implies a requester:

- Customer Request implies claimant-initiated
- Third Party implies external-party-initiated (vendor, insurer, etc.)
- Internal Review, Warranty Claim, Preventative / Condition Assessment,
  Repeat Condition Verification, Post-Remediation Verification, and
  Failure Investigation all imply warrantor-initiated

This subsumes the Cat 3 #6 requester axis question into Decision 17's
inspection_trigger enum work. The Decision 17 work adds Third Party
to the default set of trigger values explicitly to ensure
external-party-initiated inspections have a coherent default value to
record under.

No separate requested_by column, no separate claimant_initiated
boolean. The architecture commits to performed_by and paid_by as the
two structural axes; inspection_trigger captures the operational
reason AND the implicit requester in one column.

This resolves the Cat 3 #6 question.

### Architectural implications for Decision 17

Decision 17's inspection_trigger enum's default set MUST include
"Third Party" as the eighth value so external-party-initiated
inspections have a coherent default to record under. The enum's
default set is therefore (subject to Decision 17's tenant-editable
defaults pattern work):

1. Warranty Claim
2. Customer Request
3. Repeat Condition Verification
4. Post-Remediation Verification
5. Failure Investigation
6. Preventative / Condition Assessment
7. Internal Review
8. Third Party (added by this Decision)

Decision 17 may or may not add sub-flavors of Third Party (Vendor
Request, Insurer Request, etc.) — current architectural commitment
is a single Third Party value, with tenants free to add sub-flavors
through the tenant-editable defaults mechanism if their operational
reality requires.

### Schema sketch

No new schema columns. The inspections table retains its currently-
committed schema (id, tenant_id, claim_id, performed_by, paid_by,
status, inspection_report, created_at, updated_at) with Decision 17's
work adding inspection_type, inspection_trigger, and revised
inspection_status separately.

### Cross-entity dependencies

None new. Decision 18 confirms architectural commitments that align
with the already-committed Inspections Foundation section's locked
axes (performed_by, paid_by).

### Open architectural questions deferred

- **Sub-flavors of Third Party trigger.** Whether Third Party splits
  into Vendor Request, Insurer Request, or other sub-flavors as
  default values is deferred. Current commitment is single Third
  Party value; tenants can add sub-flavors via tenant-editable
  defaults mechanism per Decision 17.

### Decision implications for already-committed sections

**Inspections Foundation section (commit e846e2c) requires text
revision in two subsections:**

1. **"What is NOT in the inspections foundation" subsection.** The
   two bullets that frame claimant attendance and requester as
   "Flagged above as a downstream question" need revision to frame
   them as decided non-features per this Decision.

2. **"Outstanding architectural questions" subsection.** The two
   bullets covering claimant attendance and inspection requester
   currently say "is a downstream decision." Both need revision to
   reference this Decision as the resolution.

Section revision lands in the same session as Decision 18's commit
to keep architecture and decisions log in sync.

---

## Decision 19: ALA Signature Capture Mechanism (Accept/Decline + Atomic Signature + Decline-Recant Window)

**Decided in Session 5j.**

### Context

Audit Topic 10 flagged the ALA signature mechanism as TBD between
tokenized form acceptance, wet signature, and electronic signature
service. v2's ALA System section (prior session) captured the question
as an open architectural question with three real options. The
architectural commitment v2 made was that the ala_documents schema
supports any signing mechanism via signer_name, signer_email, and
signed_at; the question of WHICH mechanism was deferred.

Customer Work Authorization (Decision 11) locked its signature
mechanism as tokenized form-acceptance with typed-name-plus-checkbox.
v2 explicitly noted that ALA's signature mechanism is held as a
separate question because ALA's assumption of financial liability may
warrant a different mechanism. The locking of Work Authorization did
not pre-decide ALA's.

This Decision resolves the ALA signature mechanism with ten
architectural commitments. The Decision is informed by chat 4's
independent architectural read which surfaced three substantive
concerns (accessibility on canvas widget, signature_image storage
shape, declined-as-terminal restrictiveness) and two clarifications
(state machine semantics, token regeneration mechanics). All five
have been integrated into the locked commitments.

### Question

What signature mechanism does the ALA use, how is that mechanism
configured, and what is the operational lifecycle of the document
from claimant receipt through final state?

### Resolution

Ten architectural commitments.

**19.1: Two-step flow with atomic Accept-and-Signature.**

The ALA signing flow has two steps:

- Step 1: claimant chooses Accept or Decline
- Step 2 (only if Accept): claimant provides electronic signature

The two steps are atomic. A claimant who clicks Accept MUST complete
the signature in the same flow before the decision is recorded. If
the claimant abandons during signature (browser closes, network
fails, distraction), nothing is captured. The Server Action commits
Accept and Signature together as a single atomic write, or commits
neither.

Decline is the only single-step terminal action (no signature follows).

This is more restrictive than chat 4's initial four-state read
suggested. The atomic-accept-and-signature commitment eliminates an
'accepted_unsigned' intermediate state that would otherwise exist.

**19.2: Decline is explicitly captured at the schema level.**

A claimant who actively declined is operationally distinct from a
claimant who has not yet responded. Schema captures both states
distinctly via three new columns:

- claimant_decision text nullable
                    -- 'accepted' | 'declined'
                    -- CHECK constraint enforces values
                    -- application invariant: when 'accepted',
                    --   signed_at must be non-null (atomic)
- decided_at timestamptz nullable
              -- moment of Accept/Decline click
              -- non-null when claimant_decision is non-null
- decline_reason text nullable
                  -- optional free-text context from the claimant
                  -- only populated when claimant_decision = 'declined'

decided_at captures the moment of Accept/Decline click; signed_at
captures the moment of completed signature. In the happy path
(atomic accept-and-signature), the two timestamps are near-identical.
The columns remain semantically distinct so downstream code can
read whichever it needs.

**19.3: Architecture is per-tenant configurable for signature
mechanism.**

The platform commits to a configurable architecture, anticipating
that warrantors operating in different jurisdictions or under
different contractual preferences will need different mechanisms.
Configuration stored at tenants.settings.ala_signature_method.

A new column on ala_documents captures which mechanism was used to
sign each specific document (historical documents retain their
mechanism even if the tenant changes their setting later):

- signature_method text NOT NULL DEFAULT 'in_platform_widget'
                   -- 'in_platform_widget' | 'esignature_service'
                   -- CHECK constraint enforces values

The Server Action handling document creation reads the tenant's
current setting and applies it as the document's signature_method
at row creation. The setting determines the mechanism for new
documents; the column preserves the mechanism for the lifetime of
each document.

**19.4: v1 default is in_platform_widget with accessibility-compliant
dual-path UI.**

The platform's default signature mechanism at v1 is the in-platform
widget. The widget has TWO sub-paths within the same signature_method
enum value:

- Canvas-based sub-path: draw-your-signature interface for users
  who prefer or are able to use it. Signature captured as image data,
  stored in Supabase Storage (tenant-scoped path), with the URL
  reference on the document row.
- Typed-name-plus-checkbox fallback sub-path: parallel to Customer
  Work Authorization's signature mechanism (Decision 11). Provided
  for users requiring assistive technology compatibility or those
  who prefer the typed shape. The acknowledgment checkbox replaces
  the canvas image as the binding artifact.

Both sub-paths produce a valid signed ALA. Both populate signer_name,
signer_email, and signed_at. Only the canvas sub-path populates
signature_image_url; the typed-name sub-path leaves it null.

The Server Action layer is responsible for ensuring the
in_platform_widget UI surface offers both sub-paths. This
architectural commitment is not optional — accessibility compliance
(ADA and equivalent regulations) requires the typed-name fallback
within the default path.

Schema column for the canvas sub-path:

- signature_image_url text nullable
                       -- URL reference to Supabase Storage; image
                       --   stored as binary blob in tenant-scoped
                       --   path
                       -- only populated when signature_method =
                       --   'in_platform_widget' AND canvas sub-path
                       --   was used AND signed_at non-null

Storage shape is URL reference (not bytea) to align with platform
conventions for binary data — claim photos, service report photos,
work authorization documents follow the same convention. Decouples
large-blob storage from document metadata queries; keeps backup
and replication efficient. The Server Action writes the canvas data
to Supabase Storage and stores the resulting URL on the document.

**19.5: e-signature service integration architecturally supported;
specific service(s) deferred to future Decision.**

The signature_method enum includes 'esignature_service' as a valid
value. A future column captures the service-specific reference:

- esignature_envelope_id text nullable
                          -- reference to e-signature service
                          --   envelope/document ID
                          -- only populated when signature_method =
                          --   'esignature_service' AND signed_at
                          --   non-null

At v1, the platform does NOT have an actual e-signature service
integration built. A tenant who configures
tenants.settings.ala_signature_method = 'esignature_service' will
encounter a "not yet supported" error from the Server Action layer
when attempting to send an ALA for signing.

Which specific e-signature service(s) the platform integrates with
(DocuSign, HelloSign, Adobe Sign, etc.) is deferred to a future
Decision when operational pressure surfaces.

signer_name and signer_email semantics by signature_method:

- in_platform_widget (canvas sub-path): signer_name from canvas
  widget's name input field; signer_email from tokenized session
- in_platform_widget (typed-name fallback sub-path): signer_name
  from typed-name input; signer_email from tokenized session
- esignature_service: both fields from service's response callback

**19.6: Decline surfaces a warning to the claimant AFTER commit.**

When the claimant clicks Decline, the decision is captured immediately
(claimant_decision = 'declined', decided_at = now()) and the outcome
screen displays a warning explaining the consequence: the warrantor
cannot proceed with the claim, and the claim is subject to denial.

Warning shown post-commit, not as a pre-commit confirmation.

Warning text per-tenant configurable, stored at
tenants.settings.ala_decline_warning_text. Storage shape parallel to
Decision 7's tenants.settings.ala_markup_percent. Platform default
seeded at provisioning (suggested default: "We cannot move forward
without your acceptance. Your claim is subject to denial."). Tenants
edit through the Server Action layer that validates settings.
Validation enforces NOT NULL and 50-500 character bounds.

The Tenant-Editable Defaults Pattern is deliberately NOT used for
the warning text. That pattern fits enum-like data with multiple
values; a single per-tenant configurable string fits tenants.settings.

**19.7: Three-state operational state machine.**

The ala_documents row transitions through three states based on
claimant_decision and signed_at:

- unsigned — signed_at IS NULL AND claimant_decision IS NULL.
  Document sent to claimant; awaiting any response.
- signed — claimant_decision = 'accepted' AND signed_at IS NOT
  NULL. ALA in force. Blocking-gate cleared; claim can advance
  from Indistinct.
- declined — claimant_decision = 'declined' AND signed_at IS NULL.
  Claimant explicitly declined. Pending the decline-recant window
  (see 19.9); becomes permanently terminal after the window expires.

There is no accepted_unsigned state. Accept-and-Signature are atomic
(per 19.1).

The blocking-gate behavior locked by the ALA System section remains
intact: claim cannot advance from Indistinct status until signed_at
IS NOT NULL (state: signed).

**19.8: ALA is the sixth canonical use of the Stateless Tokenized
Interaction Pattern.**

The claimant is a non-authenticated party — the Stateless Tokenized
Interaction Pattern's customer case. The claimant receives a
tokenized email link to the ALA document, opens it, completes the
Accept/Decline decision and (on Accept) the signature step within
the same tokenized session.

The pattern's "shape to copy, not shared store" rule applies. Two
new columns on ala_documents:

- claimant_token text nullable
- claimant_token_expires_at timestamptz nullable

Per-row token regeneration is the mechanic for token expiry recovery.
The warrantor can update claimant_token and claimant_token_expires_at
on the existing ala_documents row when the token expires; the
document state (unsigned or, post-19.9 reset, unsigned again) is
preserved across regeneration. Parallel to Customer Work
Authorization's token behavior.

This is the sixth canonical use of the Stateless Tokenized Interaction
Pattern, after claim intake, registration assignee submission,
supply-only delivery reporting, service report customer review, and
Customer Work Authorization (Decision 11). The current ala_documents
schema in v2 tentatively named the pattern as a possible signing
channel; this Decision resolves that conditionality. The pattern IS
used.

**19.9: Decline-recant window with per-tenant configurable duration.**

Decline is NOT immediately permanently terminal. A configurable
window opens from decided_at during which the claimant can recant
their decline (typically by emailing the warrantor) and the warrantor
can re-issue the same ALA for another acceptance attempt.

Window duration stored at
tenants.settings.ala_decline_recant_window_days. Storage shape
parallel to Decision 7's ala_markup_percent. Platform default at
provisioning: 3 days. Validation bounds: 1-30 days.

Re-issue mechanic (during window):

- Warrantor invokes a re-issue Server Action on the declined
  ala_documents row
- Server Action verifies claimant_decision = 'declined' AND
  current time is within ala_decline_recant_window_days of decided_at
- Action writes audit trail entry capturing the decline event (who
  declined, when, decline_reason if populated) before resetting
  fields
- Resets claimant_decision = NULL, decided_at = NULL,
  decline_reason = NULL
- Regenerates claimant_token and claimant_token_expires_at
- Re-sends tokenized link to claimant
- Document state returns to unsigned; claimant has full Accept/
  Decline path available again

After window expiry, the re-issue Server Action is blocked. If the
claimant later recants outside the window, they must resubmit the
claim entirely (new claim, new Indistinct outcome, new ALA generated
downstream).

A new clock_event type fires at window expiry:

- ala_decline_window_expired — fires at decided_at +
  ala_decline_recant_window_days days when claimant_decision =
  'declined'. The event marks the decline as permanently terminal
  and unblocks downstream claim denial workflow.

Decline-as-recantable-then-terminal is more lenient than chat 4's
initial read suggested but more restrictive than mirroring Customer
Work Authorization's revise-and-resend. ALA's revise-and-resend
question is deferred — if operational pressure surfaces (claimants
who would have accepted with revised markup or scope), a future
Decision can add a child table for ALA document revisions. For v1,
the recant-window mechanic handles the most common case (claimant
declines hastily, reconsiders within a few days).

**19.10: Counter-signature is deliberately absent.**

Decision 19 does NOT capture a counter-signature from the warrantor.
ALA is authored by the warrantor and the operative event is claimant
acceptance; the warrantor's role is implicit in the Server Action
that created the document. This is deliberate and architecturally
correct for an Owner's Consent and Assumption of Liability Agreement.

### Schema sketch — full updated ala_documents

The ala_documents schema with this Decision's additions:

    ala_documents
      id                          uuid PK
      tenant_id                   uuid NOT NULL FK -> tenants
                                  -- denormalized per Standard RLS Pattern
      claim_id                    uuid NOT NULL UNIQUE FK -> claims
                                  -- UNIQUE enforces 1:1 with claim
      template_id                 uuid NOT NULL FK -> ala_templates
      content_snapshot            jsonb NOT NULL
      markup_percent_snapshot     numeric(4,3) NOT NULL
      -- Existing signer columns (retained):
      signer_name                 text nullable
      signer_email                text nullable
      signed_at                   timestamptz nullable
                                  -- non-null is the architectural
                                  --   marker of 'ALA in force'
      -- New columns added by Decision 19:
      claimant_decision           text nullable
                                  -- 'accepted' | 'declined'
                                  -- CHECK constraint enforces values
                                  -- application invariant: when
                                  --   'accepted', signed_at must be
                                  --   non-null (atomic)
      decided_at                  timestamptz nullable
      decline_reason              text nullable
      signature_method            text NOT NULL
                                    DEFAULT 'in_platform_widget'
                                  -- 'in_platform_widget' |
                                  --   'esignature_service'
                                  -- CHECK constraint enforces values
      signature_image_url         text nullable
                                  -- URL to Supabase Storage; only
                                  --   when canvas sub-path used
      esignature_envelope_id      text nullable
                                  -- only when signature_method =
                                  --   'esignature_service'
      claimant_token              text nullable
      claimant_token_expires_at   timestamptz nullable
      created_at                  timestamptz NOT NULL DEFAULT now()
      updated_at                  timestamptz NOT NULL DEFAULT now()
      -- CHECK / app-layer invariant: tenant_id matches the
      --   referenced claim's tenant_id

Eight new columns added. Existing columns retained.

### Tenant settings additions

Three new keys at tenants.settings JSONB:

- ala_signature_method text
  -- 'in_platform_widget' | 'esignature_service'
  -- DEFAULT 'in_platform_widget' at provisioning
  -- application-layer validation enforces enum
- ala_decline_warning_text text
  -- DEFAULT platform-curated warning
  -- application-layer validation: NOT NULL, 50-500 character bounds
- ala_decline_recant_window_days integer
  -- DEFAULT 3 at provisioning
  -- application-layer validation bounds: 1-30 days

### Clock event types added

One new event type added to the clock_event enum:

- ala_decline_window_expired — fires at decided_at +
  ala_decline_recant_window_days days when claimant_decision =
  'declined'. Event handler marks the decline as permanently
  terminal; downstream claim denial workflow can proceed.

This is the seventh clock_event type after Decision 9's six.

### Cross-section dependencies

- **Stateless Tokenized Interaction Pattern (Tier 1)**: ALA is the
  sixth canonical use. Pattern section's canonical-uses list should
  be updated when the section is next revised.
- **Tenant-Editable Defaults Pattern (Tier 1)**: documented here as
  considered and deliberately not used for the warning text. Pattern
  fits enum-like multi-value lookup data, not single per-tenant
  strings.
- **Decision 7 (ALA markup default)**: same operational shape
  (tenants.settings JSONB) used here for three new settings.
- **Decision 11 (Customer Work Authorization)**: parallel pattern for
  decision capture (claimant_decision here; customer_decision there).
  Both use the explicit-decision-capture philosophy. Work
  Authorization's signature mechanism (typed-name-plus-checkbox) is
  deliberately different from ALA's canvas-with-typed-name-fallback
  reflecting the legal-force distinction.
- **Decision 9 (Clock Event Infrastructure)**: a new event type
  (ala_decline_window_expired) joins the existing enum.
- **Audit trail mechanism**: the re-issue Server Action depends on
  v2's audit trail infrastructure to capture decline events before
  reset. Audit trail implementation is Phase 3 implementation detail.

### Open architectural questions deferred

- **Specific e-signature service integration.** Which service(s) the
  platform integrates with (DocuSign, HelloSign, Adobe Sign, etc.)
  is deferred to a future Decision when operational pressure
  surfaces. The architecture supports any service through the
  esignature_envelope_id column; integration work is not yet
  undertaken.

- **Wet signature mechanism.** Not architecturally supported at v1.
  If wet signature ever surfaces operationally as a need, it would
  require its own Decision to add a third signature_method value and
  an additional column for uploaded signed-document reference.

- **ALA revise-and-resend.** If operational pressure surfaces
  (claimants declining for revisable reasons like markup percentage
  or scope clarification), a future Decision can add a child table
  for ALA document revisions, parallel to Customer Work
  Authorization's revise-and-resend mechanic. v1 commits to the
  recant-window mechanic instead, which handles the most common
  case (hasty decline reconsidered within days).

- **Multi-scenario decline warnings.** Decision 19 commits a single
  warning text per tenant. If operational pressure surfaces for
  different warnings in different decline contexts (first decline
  vs near claim closure), the Tenant-Editable Defaults Pattern
  would fit that multi-value enum-like shape. Current commitment
  is single-string-in-settings.

- **Canvas signature legal defensibility.** The in_platform_widget's
  canvas sub-path produces a signature image and session log.
  Defensible in many jurisdictions but not all, depending on
  agreement stakes. Tenants in jurisdictions requiring higher legal
  standing (e.g., e-signature service with built-in audit trails,
  timestamp servers, established case law) wait for the
  esignature_service integration. This is per-tenant
  per-jurisdiction concern that tenants manage themselves; the
  architecture's job is to support the choice, which it does.

- **Canvas signature image format and bounds.** PNG vs JPEG, size
  bounds (suggested 50KB-500KB), resolution (suggested 600x200
  pixels) are Phase 3 implementation details.

- **Claimant token expiry window default.** The Stateless Tokenized
  Interaction Pattern doesn't lock a uniform expiry; per-use windows
  vary. ALA's claimant_token_expires_at default (24 hours, 72 hours,
  7 days?) is a Phase 3 implementation detail.

### Decision implications for already-committed sections

**ALA System section** (current v2 commit) requires substantial
revision:

1. The "Signature capture: an open architectural question" subsection
   — the open question is now resolved. Subsection content needs to
   be rewritten to reflect the locked architecture (two-step atomic
   flow, in_platform_widget default with accessibility fallback,
   esignature_service reserved, three-state machine, decline-warning
   mechanism, decline-recant window).

2. The "ala_documents schema" subsection — the eight new columns
   (claimant_decision, decided_at, decline_reason, signature_method,
   signature_image_url, esignature_envelope_id, claimant_token,
   claimant_token_expires_at) need to be added to the schema sketch.

3. The "Indistinct outcome is the trigger" subsection — the
   conditional language ("Whether the routing-for-signature uses
   the Stateless Tokenized Interaction Pattern...depends on the
   signature mechanism question") needs to be updated to commit
   that the pattern IS used.

**Stateless Tokenized Interaction Pattern section** (Tier 1):
canonical-uses list should be updated to include ALA as the sixth
canonical use. Targeted update; light touch.

**Clock Event Infrastructure section** (Tier 1): the clock_event
type enum needs the ala_decline_window_expired addition documented.

**Tenant provisioning Server Action** (lib/core/provision-tenant.ts):
the three new tenants.settings keys (ala_signature_method,
ala_decline_warning_text, ala_decline_recant_window_days) need to
be set at provisioning. Phase 3 implementation work; not
architectural.

Section revisions land in subsequent commits following this
Decision's commit.

This Decision resolves Cat 3 backlog item #1 (ALA signature capture
mechanism). Remaining Cat 3 backlog: eight items.

---

## Decision 20: O&M Provider as contact_type, Authorized-Agent Relationship, and Customer-O&M Authorization Document Requirement

**Decided in Session A (Cat 3 backlog resolution).**

### Context

Cat 3 backlog item #3 surfaced an open architectural question flagged
at line 2248 of v2's architecture reference (within Parts Claim
context): "The contact_type for the FK is the open question — Item
16's eight Phase 1 values include subcontractor_contact, which could
fit, but a dedicated om_provider value may be cleaner. Resolving the
contact_type is a downstream decision."

The question scope expanded during architectural drafting. O&M
Providers are not simply another contact category — operational
reality is that each claimant typically engages an O&M Provider who
manages warranty matters on the customer's behalf and is contractually
authorized to act as the customer's agent for warranty claims, parts
orders, repair coordination, and related interactions.

This Decision resolves the contact_type question, the customer-O&M
Provider relationship structure, the authorized-agent role capture
mechanism, the matched-pair traversal mechanism, the v1 operational
regime for binding-commitment agency, and surfaces a new Cat 3
backlog item (#9) for the Customer-O&M Authorization document
architecture parallel to ALA.

The Decision is informed by chat 4's independent architectural read
which surfaced two substantive concerns (claim-submitter traceability
gap, v1-to-Cat-3-#9 operational gap) plus refinements on traversal
mechanism, contact_type immutability, customer-row-scope flexibility,
and Cat 3 #9 scope. All concerns and refinements have been integrated
into the locked commitments.

### Question

What contact_type captures O&M Providers in the unified contacts
directory, how is the customer-O&M Provider relationship structured,
how is authorized-agent role recorded in transactions, how is the
matched-pair traversal handled, and what preconditions govern O&M
Provider agency on the customer's behalf at v1 and post-Cat-3-#9?

### Resolution

Ten architectural commitments.

**20.1: New contact_type values for O&M Provider follow the matched-
pair convention.**

Add two values to the Phase 1 contact_type enum on the contacts
table:

- om_provider — the O&M Provider organization
- om_provider_contact — individual contacts within an O&M Provider
  organization

The Phase 1 contact_type enum grows from eight values to ten. The
matched-pair convention follows the established Phase 0 Item 16
pattern (customer + customer_contact, subcontractor +
subcontractor_contact, vendor + vendor_contact).

Application-layer validation enforces the enum at row insert. The
CHECK constraint on contact_type is updated to include the two new
values.

**20.2: O&M Provider is recognized as a distinct operational party.**

O&M Providers are operationally distinct from subcontractors (the
party that installed the system) and customers (the end-customer
who owns it). O&M Providers operate and maintain the warrantied
system day-to-day, are typically the first responders to defects,
and act as the authorized agent of the customer for warranty matters
per the customer's contractual engagement with them.

**20.3: linked_om_provider_id captures the customer's CURRENT
authorized O&M Provider, with customer-row-scope flexibility.**

A new column on the customer contact row captures the customer's
currently engaged O&M Provider:

- linked_om_provider_id uuid nullable FK -> contacts (where
  contact_type = 'om_provider')

Nullable because not all customers have an O&M Provider; some
self-manage. Updatable when the customer changes O&M Provider;
historical relationships preserved through transaction-time FK +
Snapshot Pattern on claim/parts-order/document records.

CHECK / application-layer invariant: when linked_om_provider_id is
non-null, the referenced contact row MUST have contact_type =
'om_provider'.

Customer-row-scope flexibility: a tenant who needs per-site O&M
Provider modeling (e.g., one O&M Provider for the inverter side
and another for the panel side of a single commercial customer)
can model this via per-site customer rows — each customer-row-as-
site has its own linked_om_provider_id. The single-FK choice does
not constrain multi-O&M-Provider scenarios; tenants choose their
customer-row granularity to match their commercial relationships.

If a tenant genuinely cannot model their multi-provider scenario
as multiple customer rows, the deferral question becomes active
(see Open architectural questions deferred).

**20.4: Authorized-agent role is INFERABLE from actor contact_type
with traversal through parent_contact_id; no explicit flag column.**

Transaction actor capture follows the established v2 convention.
Every claim, parts order, ALA document, Service Report, Customer
Work Authorization, and similar transaction records an actor via
contact_id (the contact who performed the action). The agency
check is:

- actor's contact_type IN ('om_provider', 'om_provider_contact')
- AND (if om_provider_contact, traverse parent_contact_id to find
  parent om_provider)
- AND that om_provider matches customer.linked_om_provider_id

The traversal mechanism requires parent_contact_id on contact rows
(see 20.10).

No explicit "acting as agent" boolean flag is added to operational
tables. The role is queryable through the contacts table lookup;
adding a flag would bloat operational tables with derivable data.
If reporting needs surface that argue for the explicit flag at
scale, revisitable. For v1, derivable is sufficient.

Contact_type immutability: contact_type is effectively immutable
per row. If a contact's operational role changes (rare), a new
contact row is created rather than UPDATE on the existing row.
Server Action layer enforces; schema does not. This discipline is
what makes "derivable, not stored" sound across time — the actor's
contact_type at the moment of query equals the actor's contact_type
at the moment of action.

**20.5: Pre-build addition with no migration burden.**

The contacts table established by Phase 0 Item 16 is not yet built.
The two new contact_type values (20.1), the linked_om_provider_id
column (20.3), and the parent_contact_id column (20.10) all join
the application-layer enum, CHECK constraints, and table schema at
table-creation time as part of the original migration. No
retroactive migration is required.

**20.6: O&M Provider as unified directory entry, carved into
INFORMATIONAL and BINDING-COMMITMENT operational contexts.**

The om_provider contact_type is the canonical directory entry for
O&M Providers across all operational contexts. The operational
contexts are carved into two categories:

**INFORMATIONAL contexts (available at v1):**

- Parts Claim ship-to (the original line 2248 flag) — Decision 20
  resolves the contact_type, no precondition needed
- Claim submitter — claim filing by O&M Provider is informational;
  the claim is filed in the customer's name with the O&M Provider's
  submitter capture
- Inspection site contact — on-site coordinator role; informational
- Communications recipient — status updates, repair coordination
  notifications

**BINDING-COMMITMENT contexts (GATED until Cat 3 #9 resolves):**

- ALA acceptance by O&M Provider
- Customer Work Authorization approval by O&M Provider
- Service Report customer-side review (acceptance or dispute) by
  O&M Provider

For the gated contexts at v1: the binding-commitment Server Actions
verify the actor's contact_type and BLOCK the action with a
"O&M Provider binding-commitment agency is not yet supported"
error if the actor is om_provider or om_provider_contact. The
customer must perform the binding-commitment action directly until
Cat 3 #9 lands. This is the architectural commitment to gated-
until-#9-lands operational regime (see 20.7).

**20.7: v1 operational regime: binding-commitment O&M Provider
agency is BLOCKED until Cat 3 #9 lands.**

The Customer-O&M Authorization document is REQUIRED as a precondition
for O&M Provider agency in binding-commitment contexts. The document
captures the customer's acknowledgment of four explicit commitments:

(a) The customer authorizes the O&M Provider to act on the
    customer's behalf for warranty matters
(b) The customer understands they will NOT be notified for ALA-type
    events and other agent-handled binding decisions
(c) The customer acknowledges that any decision or agreement
    entered into by the O&M Provider is binding on the customer
(d) The customer remains ultimately responsible for the consequences
    of decisions made by the O&M Provider on their behalf

At v1, the document mechanism does NOT exist; it is architecturally
deferred to Cat 3 #9. Without the document mechanism, the
precondition cannot be operationally satisfied within the platform.

v1's operational regime resolves this gap by GATING binding-
commitment O&M Provider agency entirely:

- O&M Providers can participate as informational contacts (the
  four contexts in 20.6)
- O&M Providers CANNOT act as agents in binding-commitment contexts
  (the three contexts in 20.6); the customer must act directly
- Tenants who require binding-commitment O&M Provider agency must
  wait for Cat 3 #9 to land

This is the architecturally clean resolution. Alternatives
considered (tenant attestation as a transitional regime; soft-allow
with retroactive backfill) were rejected: the tenant-attestation
regime creates a transitional accommodation that is operationally
difficult to deprecate when Cat 3 #9 lands; the soft-allow regime
creates retroactive authorization complexity that compounds.

Gated-until-#9-lands matches v2's discipline of architectural
integrity over operational immediacy. Cat 3 #9 should be
prioritized accordingly.

The "ultimately responsible" mechanism in 20.7(d) is downstream
legal terms-and-conditions territory — the document architecture's
job is to preserve the customer's acknowledgment in an audit-
defensible form (signed, dated, content-snapshotted parallel to
ALA). The legal mechanism for enforcing responsibility is governed
by the warranty contract and applicable law, not by the document
architecture. Cat 3 #9 should note that tenants who want specific
recourse language include it in their per-tenant template, parallel
to ALA template configuration.

**20.8: Cat 3 #9 surfaced — Customer-O&M Authorization document
architecture (expanded scope).**

A new Cat 3 backlog item is added: #9 Customer-O&M Authorization
document architecture. Scope parallel to ALA System (Decision 19)
PLUS the additional mechanics surfaced during Decision 20:

Core scope (parallel to ALA):

- Per-tenant template architecture (templates table and documents
  table)
- Per-tenant configurable acknowledgment text capturing the four
  commitments from 20.7
- Signature capture mechanism (likely reusing Decision 19's
  in_platform_widget with typed-name-fallback for accessibility
  compliance — ADA and equivalent)
- Customer-facing tokenized signing flow (Stateless Tokenized
  Interaction Pattern, likely seventh canonical use depending on
  sequencing)
- Operational state machine (unsigned, signed, voided, superseded)
- Audit defensibility — the signed authorization is the legal
  defense if a customer ever disputes that they agreed to let the
  O&M Provider sign anything on their behalf

Voiding and superseding mechanics (new scope from Decision 20):

- When a customer changes O&M Provider, the prior authorization is
  voided; a new authorization must be signed for the new O&M
  Provider before binding-commitment agency activates for the new
  provider
- Mid-claim O&M Provider change handling: when a claim was filed
  by O&M Provider A acting under Customer X's authorization, and
  mid-claim Customer X changes to O&M Provider B, the question of
  whether A's authority on the in-flight claim persists vs whether
  authority transfers to B vs whether the in-flight claim is frozen
  pending Customer X's direct action is part of Cat 3 #9's scope
- Prior decision binding preservation: per 20.7(c), decisions made
  by O&M Provider A are binding on Customer X when made. Audit-
  defensibility requires the document architecture preserves A's
  authorization at the moment of decision via FK + Snapshot to the
  authorization document, parallel to ALA's content_snapshot
  pattern. Cat 3 #9 must commit to this snapshot mechanism.

Audit trail for linked_om_provider_id changes (new scope from
Decision 20):

- When a customer changes O&M Provider, the FK on the customer
  row updates. Cat 3 #9 should include a change-log mechanism
  (audit table or trigger-based) to capture when changes happened
  and what the prior values were. The audit-trail value of
  historical FK + Snapshot at claim/parts-order level partly
  compensates but doesn't reconstruct "Customer X changed O&M
  Provider three times in 2026, here are the dates."

Cross-section dependencies with ALA and Customer Work Authorization
should be re-examined as part of Cat 3 #9 to ensure consistent
patterns.

Cat 3 #9 warrants a dedicated architectural session parallel to
Session 5j (which architected ALA). Estimated scope: 90-150 min
with possible chat 4 verification round for substantive concerns
(accessibility, document storage shape, voiding mechanics, mid-
relationship-change handling, snapshot mechanism, audit trail
shape).

**20.9: Resolves the line 2248 open architectural question.**

The open question flagged at line 2248 of v2's Parts Claim context
("The contact_type for the FK is the open question — Item 16's
eight Phase 1 values include subcontractor_contact, which could
fit, but a dedicated om_provider value may be cleaner") is resolved
by 20.1: the dedicated om_provider value is the cleaner answer that
flag explicitly identified.

The Parts Claim section text at line 2248 requires a targeted
revision following this Decision's commit to replace the open-
question framing with the resolved answer.

**20.10: parent_contact_id column on contact rows enables matched-
pair traversal.**

The matched-pair convention (customer + customer_contact,
subcontractor + subcontractor_contact, vendor + vendor_contact,
and now om_provider + om_provider_contact per 20.1) requires a
parent-child relationship between the organization-level contact
and the individual contacts at that organization. Phase 0 Item 16
established the matched-pair convention but did not lock the
parent-child mechanism.

This Decision adds:

- parent_contact_id uuid nullable FK -> contacts (self-referential)
  -- references the parent organization contact when this row is
  --   an individual-contact variant (customer_contact,
  --   subcontractor_contact, vendor_contact, om_provider_contact)
  -- null for organization-level rows (customer, subcontractor,
  --   vendor, om_provider)
  -- null for non-matched-pair rows (registration_assignee, other)
  -- CHECK / app-layer invariant: when contact_type ends in
  --   '_contact', parent_contact_id MUST be non-null and the
  --   referenced row's contact_type must be the matching
  --   organization-level type (e.g., om_provider_contact's parent
  --   must have contact_type = 'om_provider')

The traversal mechanism in 20.4 depends on this column. Without
parent_contact_id, an om_provider_contact actor cannot be linked
back to their parent om_provider organization to verify the agency
match against customer.linked_om_provider_id.

The mechanism is added at the Phase 0 Item 16 level (not Cat 3 #9)
because it affects ALL matched pairs, not just O&M Provider.
Pre-build addition; no migration burden.

### Schema additions

**contacts table additions (all pre-build):**

- contact_type enum extended (8 -> 10 values): adds 'om_provider'
  and 'om_provider_contact' to the existing enum
- CHECK constraint updated to include the two new values
- parent_contact_id uuid nullable FK -> contacts (self-referential,
  per 20.10)
- CHECK / app-layer invariant on parent_contact_id (see 20.10)

**customer contact row additions:**

- linked_om_provider_id uuid nullable FK -> contacts
  -- references contacts where contact_type = 'om_provider'
  -- CHECK / app-layer invariant: when non-null, referenced row's
  --   contact_type must = 'om_provider'

**Claim Intake submitter capture revision:**

The current Claim Intake submitter capture (submitter_name and
submitter_email as free-text columns) is revised to FK + Snapshot
when the actor is a known contact, with free-text fallback for
one-off third parties. New shape:

- submitter_contact_id uuid nullable FK -> contacts
  -- references the contact who submitted the claim
  -- null when the submitter is a one-off third party not in the
  --   contacts directory
- submitter_name text NOT NULL
  -- captured at submission; snapshot of the submitter's name at
  --   that moment regardless of whether submitter_contact_id is
  --   populated
- submitter_email text NOT NULL
  -- captured at submission; snapshot of the submitter's email at
  --   that moment regardless of whether submitter_contact_id is
  --   populated

When submitter_contact_id is populated, downstream workflows can
traverse to the contact's contact_type to derive whether the
submission was by the customer directly, by a customer_contact,
by the O&M Provider (subject to 20.6's INFORMATIONAL vs BINDING-
COMMITMENT carving), or by another party type. When
submitter_contact_id is null, the snapshot is the only record;
agency role cannot be derived because there's no contact reference.

This revision is small (one new column, two existing columns
retained as snapshot fields) and pre-build (Claim Intake table not
yet built).

### Cross-section dependencies

- **Phase 0 Item 16 (Unified contacts directory):** contact_type
  enum grows from 8 to 10 values; linked_om_provider_id added to
  the customer row shape; parent_contact_id added at contact-row
  level for matched-pair traversal
- **Line 2248 (Parts Claim ship-to flag):** resolved by Decision 20
- **Claim Intake:** submitter capture revised to FK + Snapshot when
  known contact, free-text fallback for one-off third parties
- **Customer Work Authorization (Decision 11):** actor capture
  pattern carries through; O&M Provider as authorized agent BLOCKED
  at v1 until Cat 3 #9 lands (per 20.6, 20.7)
- **ALA System (Decision 19):** ALA acceptance by O&M Provider
  BLOCKED at v1 until Cat 3 #9 lands; flag added in Signature
  capture mechanism subsection
- **Service Report Submission:** customer-side review (acceptance
  or dispute) by O&M Provider BLOCKED at v1 until Cat 3 #9 lands;
  flag added
- **Inspections Foundation:** O&M Provider as inspection site
  contact is INFORMATIONAL (not blocked); contact_type capture is
  sufficient

### Open architectural questions deferred

- **Customer-O&M Authorization document architecture (Cat 3 #9).**
  Scope per 20.8. Includes core ALA-parallel architecture, voiding
  and superseding mechanics, mid-relationship-change handling, prior
  decision snapshot mechanism, and audit trail for
  linked_om_provider_id changes.

- **Multiple concurrent O&M Providers per single customer row.**
  Decision 20 commits to single-FK linked_om_provider_id. If a
  tenant genuinely cannot model their multi-provider scenario as
  multiple customer rows (per 20.3's customer-row-scope flexibility),
  the deferral question becomes active. Trigger for revisit: a
  tenant who needs multi-provider per single customer row and
  cannot reasonably model their commercial relationship at the
  customer-row level. Forward migration to a link table is feasible.

- **Cross-tenant O&M Provider identity reconciliation.** A
  real-world O&M Provider company may serve customers across
  multiple WarrantyOS tenants. Under Phase 0 Item 16, contacts is
  tenant-scoped, so the same real-world O&M Provider has separate
  contact rows in each tenant's directory. This duplication is
  operationally correct at v1 (each tenant manages their own
  directory). If the platform later wants O&M Provider self-service
  (one O&M Provider company logs in once and sees their work
  across all tenants they serve), the architecture needs to evolve.
  Known forward-evolution question; not actionable at v1.

- **Scoped authorization (binary vs scope-qualified at v1).**
  Decision 20 commits to binary authorization at v1 — an O&M
  Provider is authorized for all binding-commitment contexts or
  for none. A customer might want to authorize their O&M Provider
  for some contexts but not others (e.g., parts orders yes, ALA
  decisions no), or for low-dollar repairs but require direct
  customer approval for high-dollar repairs. v1 does not support
  scoped authorization; the document architecture (Cat 3 #9) can
  grow scope/threshold fields if operational pressure surfaces.

- **O&M Provider self-service portal.** If the platform later
  wants O&M Providers to have their own login (rather than acting
  on customer's behalf via tokenized flows), this is substantial
  architectural work. Not in v1 scope.

### Decision implications for already-committed sections

**Phase 0 Item 16 (Unified contacts directory) section:** schema
update to add the two new contact_type values, the
linked_om_provider_id column on customer rows, and the
parent_contact_id column on contact rows. Section narrative updated
to document the matched-pair extension, the linked_om_provider_id
purpose with customer-row-scope flexibility note, the
parent_contact_id traversal mechanism, and the contact_type
immutability discipline.

**Parts Claim section** (line 2248 area): targeted revision to
replace the open-question framing with the resolved Decision 20
answer.

**Claim Intake section:** submitter capture revision per Decision 20
schema additions. Small surgical update — adds submitter_contact_id
column, retains submitter_name and submitter_email as snapshot
fields.

**ALA System section:** flag added to the Signature capture mechanism
subsection that O&M Provider acceptance is BLOCKED at v1 until
Cat 3 #9 (Customer-O&M Authorization document architecture) lands.
Light touch addition.

**Customer Work Authorization section:** parallel flag added that
O&M Provider approval is BLOCKED at v1 until Cat 3 #9 lands. Light
touch addition.

**Service Report Submission section:** parallel flag added that
O&M Provider customer-side review (acceptance or dispute) is BLOCKED
at v1 until Cat 3 #9 lands. Light touch addition.

**Inspections Foundation section:** no flag needed; O&M Provider as
inspection site contact is INFORMATIONAL (per 20.6).

Section revisions land in subsequent commits following this
Decision's commit.

This Decision resolves Cat 3 backlog item #3 (O&M Provider
contact_type). It surfaces Cat 3 backlog item #9 (Customer-O&M
Authorization document architecture). Remaining Cat 3 backlog: nine
items.

---

## Decision 21: Service Report Customer Review Window Configurability and Canonical Three-Day Response Window Convention

**Decided in Session B (Cat 3 backlog resolution).**

### Context

Cat 3 backlog item #4 surfaced the Service Report customer review
window length as a deferred Phase 3 implementation detail. The
Service Report Submission section already flagged this at line
3581 (pre-Decision-21 line numbering): "Whether tenants can
configure the window length per their own contractual norms — and
where that configuration lives (tenants.settings with a
service_report_response_days key, parallel to the existing
ala_markup_percent and rich_text_max_chars settings) — is a Phase
3 implementation detail flagged here. The architectural commitment
is the clock-event-driven mechanism; the window length default and
configurability are downstream."

This Decision resolves the deferred question. The architectural
commitments apply Decision 19's precedent
(ala_decline_recant_window_days) to the Service Report customer
review window AND establish a canonical platform convention for
three-day claimant response windows that future similar Decisions
inherit.

Andre's operational catch during the session surfaced an important
cross-cutting concern: three days is the canonical claimant
response window across the platform (per SOP 1's "a minimum of
three days" baseline and Decision 19's prior commitment to three
days for ala_decline_recant_window_days). Future Decisions adding
similar windows should default to three days unless operational
pressure surfaces otherwise. This Decision establishes that
convention explicitly.

### Question

How is the Service Report customer review window length configured
across tenants, what is the default value, what bounds apply, what
mechanism handles tenants who want to disable the silence-acceptance
behavior entirely, and what convention governs future similar
windows on the platform?

### Resolution

Eight architectural commitments.

**21.1: Service Report customer review window length is per-tenant
configurable.**

Storage at tenants.settings.service_report_response_days (JSONB key).
Storage shape parallels Decision 7's ala_markup_percent and Decision
19's ala_decline_recant_window_days — single per-tenant scalar value
with application-layer validation.

**21.2: Platform default at provisioning: 3 days (calendar days).**

The default matches the canonical platform convention established
by 21.6. Three days reflects SOP 1's "a minimum of three days"
baseline and Decision 19's prior commitment to three days for the
ALA decline-recant window.

**21.3: Validation bounds: 3-30 days.**

Application-layer validation enforces. Bounds match Decision 19's
ala_decline_recant_window_days bounds for consistency. Minimum
of 3 honors SOP 1's stated floor; maximum of 30 is a sensible
operational ceiling.

**21.4: Calendar days, not business days.**

Implementation uses now() + interval '[N] days' on the clock event's
fires_at calculation. Tenants who want effective business-day
behavior can configure a longer value to approximate it (e.g., 5
calendar days for approximately 3 business days excluding weekends).

Business-day arithmetic is deliberately not adopted at v1 because:
- Implementation complexity is real (per-tenant holiday calendars
  would be required for true business-day accuracy)
- v2's clock-event-driven mechanism stays simple
- Tenants who need effective business-day behavior have the
  per-tenant configurability to approximate it
- Future expansion to business-day mode is possible if operational
  pressure surfaces

**21.5: Tenant disable capability via Feature Flag System.**

New feature flag service_report_acquiesce_window (default enabled
at provisioning). When the flag is disabled, the
service_report_response_due clock event is NOT created at Service
Report issuance. The silence-acceptance path (Assumption of
Acquiesce per SOP 1) does not fire. The customer must explicitly
accept or dispute via the tokenized review interface; the claim
remains open until the customer acts.

The Feature Flag System (Phase 0 Item 18) is the right home for
this rather than another tenants.settings key because:
- This is conceptually a feature gate (on/off behavior), not a
  scalar configuration
- The Feature Flag System provides admin UI and documented audit
  logging
- Consistent with how other tenant-toggleable behaviors are handled

The flag joins the Phase 1 features list in the Feature Flag System
section.

**21.6: Canonical platform convention — three days is the canonical
claimant response window across the platform.**

This Decision establishes an explicit architectural convention:
three days is the canonical default for any claimant response
window on the platform. Each per-tenant setting still exists
(tenants can override per-window), but new Decisions adding similar
windows MUST default to three days unless an operational pressure
surfaces otherwise.

Applies to:
- ala_decline_recant_window_days (Decision 19, already 3)
- service_report_response_days (this Decision)
- Future Cat 3 #5 ALA reminder window (when that Decision lands)
- Any future claimant response window

Rationale: SOP 1's "a minimum of three days" baseline plus Decision
19's three-day default already establish the de facto convention.
Naming it as a platform convention prevents future Decisions from
re-inventing or picking different defaults. The convention is
documentation-level architectural commitment, not a schema-level
mechanism.

**21.7: Tenant setting changes are future-effective only (Path A on
in-flight Service Reports).**

When a tenant updates tenants.settings.service_report_response_days,
in-flight Service Reports retain their original window. The
clock_events.fires_at value is locked at Service Report issuance
when the clock event row was created; setting changes do not
retroactively recalculate fires_at for pending clock events.

New Service Reports issued after the setting change use the new
window value.

Path A is chosen over Path B (cascading propagation with tenant
warning before commit) because:
- No new propagation architecture required; v2's existing clock_events
  shape already handles this naturally
- Operationally honest about how Service Level Agreement changes
  typically work (future-effective is the standard interpretation)
- Customers in-flight retain their original window expectation
  rather than receiving silent extensions they're not notified of
- No cascade pattern that would need to apply consistently across
  Decision 19 and other future windows
- KPI concerns (a tenant wanting to compare claim closure performance
  before/after a policy change) are addressable in reporting (filter
  by issuance date) rather than requiring clock event recalculation

The reading of clock_events.fires_at IS the structural record of
which window applied to each Service Report. No separate snapshot
column on service_reports is needed; the window length is derivable
from fires_at minus issued_at.

**21.8: Resolves Cat 3 backlog item #4.**

The Service Report Submission section's existing Phase 3-deferred
flag is replaced with the locked configurability commitment. The
"three-day customer review window" framing throughout the section
is updated to "tenant-configurable customer review window with
three-day default."

### Schema additions

None to operational tables. Two additions to existing infrastructure:

**Tenant settings (JSONB):**

- service_report_response_days integer
  -- DEFAULT 3 at provisioning
  -- application-layer validation: 3-30 day bounds
  -- per-tenant configurable

**Feature Flag System (Phase 0 Item 18):**

- service_report_acquiesce_window boolean
  -- DEFAULT enabled at provisioning
  -- when disabled, service_report_response_due clock event is NOT
  --   created at Service Report issuance
  -- joins Phase 1 features list

No changes to service_reports table. No changes to clock_events
table. The configurability flows entirely through tenants.settings
and Feature Flag System.

### Cross-section dependencies

- **Service Report Submission section:** Multiple updates — window
  length framing, the Phase 3-deferred flag replacement, the
  feature flag gating mechanic for clock event creation, the
  canonical platform convention cross-reference
- **Feature Flag System (Phase 0 Item 18):** New feature flag
  service_report_acquiesce_window added to Phase 1 features list
- **Tenant provisioning Server Action:** Adds the new
  tenants.settings key and the new feature flag at provisioning
- **Decision 19 (ALA decline-recant window):** Cross-references
  Decision 21.6's canonical platform convention — Decision 19's
  three-day default aligns with the convention established here
  (no schema or section changes needed in the ALA System section;
  the convention is documentation-level)
- **Future Cat 3 #5 (ALA reminder notifications via clock_events):**
  Should default any new claimant response window to three days
  per the canonical convention

### Open architectural questions deferred

- **Business-day arithmetic mode.** v1 commits to calendar days.
  If operational pressure surfaces for business-day windows (e.g.,
  tenants in regulated industries with explicit business-day
  contractual language), a future Decision can add a business-day
  mode. Implementation would require per-tenant holiday calendars.
  Not in v1 scope.

- **Cascading propagation on setting changes (Path B).** Path A is
  locked at v1. If operational pressure surfaces for immediate
  cascade of setting changes to in-flight clock events, a future
  Decision can add the propagation pattern. Would apply consistently
  across ala_decline_recant_window_days, service_report_response_days,
  and any future similar settings. Not in v1 scope.

- **Window length for Notice of Closure response (if any).** v2's
  current architecture does not have a Notice of Closure response
  window. If future Decisions add one, the canonical three-day
  convention from 21.6 applies.

### Decision implications for already-committed sections

**Service Report Submission section** (multiple updates):

1. Window length references throughout — replace "three-day customer
   review window" framing with "tenant-configurable customer review
   window with three-day default per the canonical platform convention
   (Decision 21.6)."

2. The Phase 3-deferred flag (current line 3581 area) — replace with
   the locked configurability commitment. Cross-reference
   tenants.settings.service_report_response_days for the per-tenant
   configurability, the 3-30 day bounds, and the Path A
   future-effective-only semantics.

3. The service_report_response_due clock event documentation — add
   the feature flag gating mechanic: when
   service_report_acquiesce_window is disabled, the clock event is
   NOT created; the silence-acceptance path does not fire.

4. The three possible actions in the customer review interface
   (accept, dispute, no action) — clarify that the "no action" path
   (Assumption of Acquiesce) only operates when the
   service_report_acquiesce_window feature flag is enabled.

**Feature Flag System (Phase 0 Item 18) section:**

Add service_report_acquiesce_window to the Phase 1 features list.
Light touch addition.

Section revisions land in subsequent commits following this
Decision's commit.

This Decision resolves Cat 3 backlog item #4 (Customer review window
configurability for Service Report) and establishes the canonical
platform convention for three-day claimant response windows.
Remaining Cat 3 backlog: eight items (down from nine).

---

## Decision 22: Hosted-DB Migration History Baseline Procedure (Phase 4 Transition Prerequisite)

**Decided in Session B (Cat 3 backlog resolution).**

### Context

Cat 3 backlog item #2 surfaces a Phase 4 blocker. The hosted/remote
Supabase database's migration_history table has no record of
000_baseline or migrations 001-004 — those tables were created
manually in the SQL Editor before the migrations directory existed
in the repo. Phase 4 work that involves applying migrations to the
hosted DB cannot begin until the remote migration history is
baselined.

CLAUDE-rev3.md currently documents this as a stop-point (lines 71-83):
do NOT run `supabase db push`, `supabase db remote commit`,
`supabase migration up --linked`, or any command that applies local
migrations to the hosted/remote/production database until the remote
has been baselined via `supabase migration repair`.

This Decision documents the locked baseline procedure, the
verification gates, the failure modes and recovery procedures, and
the Phase 4 transition criteria.

Honest framing: this is a procedural/transitional Decision rather
than a typical architectural one. No new schema, no new operational
pattern. But the procedural rigor matters because the failure modes
are subtle and silent — the highest-risk mode (drift between local
migration files and remote schema) does not manifest at baseline
time; it manifests months later when a downstream migration assumes
state that doesn't actually exist.

The Decision is informed by chat 4's independent architectural read
which surfaced six substantive concerns: drift failure mode (Mode
D) as the most consequential silent failure, Mode C gating that was
too permissive, missing fourth Phase 4 condition (schema.sql
regeneration verification), missing failure modes E (wrong project)
and F (CLI version), strict pre-state commitment, and historical
context in section documentation. All concerns have been integrated
into the locked commitments.

### Question

What is the locked procedure for baselining the hosted DB's
migration history, what verification gates apply before and after,
what failure modes are anticipated and how are they recovered, where
does this documentation live in v2, and what conditions gate Phase
4 from beginning?

### Resolution

Ten architectural commitments.

**22.1: Phase 4 transition gate.**

Phase 4 work involving migrations cannot begin until the baseline
procedure is executed and verified. The CLAUDE-rev3.md stop-point
(currently lines 71-83) remains in force until Phase 4 transition
criteria (22.8) are all satisfied. Until then, Claude Code must
STOP and surface the hazard rather than running migration commands
that would apply local migrations to the hosted DB.

**22.2: The baseline procedure — six-step sequence.**

The procedure is six sequential steps. Each step has explicit
verification before proceeding to the next.

**Step 0 — Backup current migration_history table contents.**

Before any modification, capture the current state of
supabase_migrations.schema_migrations to a file. The table is
trivially small; the safety net matters.

Mechanism: query the table via psql or Supabase CLI, persist to
disk under a timestamped filename. Suggested:

    supabase_migrations_schema_migrations_backup_<YYYYMMDD-HHMMSS>.sql

The backup file is retained in the operator's local environment
(not committed to the repo) and serves as the recovery baseline
if Mode C (see 22.5) becomes necessary.

**Step 1 — Pre-procedure verification gates (per 22.3).**

All verification gates in 22.3 must pass before any repair command
runs. If any gate fails, STOP. Do not proceed.

**Step 2 — Run five sequential repair commands.**

    supabase migration repair --linked --status applied 000
    supabase migration repair --linked --status applied 001
    supabase migration repair --linked --status applied 002
    supabase migration repair --linked --status applied 003
    supabase migration repair --linked --status applied 004

Each command marks one local migration as already-applied without
re-running it. The procedure is sequential (not a single command
with multiple version arguments) for explicit per-step verification
gates between commands.

The procedure is idempotent at the migration level: running
`supabase migration repair --linked --status applied <version>` on
a migration that is ALREADY marked applied is a no-op or
success-on-already-applied. This idempotency is the foundation for
Mode B recovery (see 22.5).

**Step 3 — Per-command post-verification (per 22.4).**

After each repair command succeeds, verify via
`supabase migration list --linked` that the just-repaired migration
shows as applied. If the list shows an unexpected state after any
single repair, STOP and investigate before proceeding to the next
migration.

**Step 4 — Final post-procedure verification.**

After all five repair commands succeed, `supabase migration list
--linked` should show all five migrations as applied:

    000_baseline                | applied
    001_invitations             | applied
    002_security_hardening      | applied
    003_team_admin_role         | applied
    004_team_admin_management   | applied

If the final list differs from this expected state, STOP and
investigate before declaring baseline complete.

**Step 5 — Schema.sql regeneration smoke test (per 22.8 condition 4).**

After baseline is verified, run the schema.sql regeneration mechanism
established by Decision 10. Confirm the output matches expected
(should be effectively no change from current committed schema.sql
since baseline established the same state already on disk).

If schema.sql regeneration produces unexpected output, STOP. The
regeneration mechanism is the Phase 4 development feedback loop;
it must be working correctly before Phase 4 begins.

**22.3: Pre-procedure verification gates.**

Six gates must pass before Step 2 runs:

**Gate 1 — Local repo state.** `git status` clean, working tree on
the expected branch (current Phase 3 branch).

**Gate 2 — Local migrations present.** `ls supabase/migrations/`
returns the expected five files: 000_baseline.sql,
001_invitations.sql, 002_security_hardening.sql,
003_team_admin_role.sql, 004_team_admin_management.sql.

**Gate 3 — Supabase CLI authenticated and version pinned.**
`supabase projects list` returns the expected project. The CLI
version is pinned to the version tested at baseline procedure
documentation time. Version mismatch is failure mode F (see 22.5).

**Gate 4 — Linked project verified against known-good project ID.**
`supabase status --linked` shows the correct project ID, matched
against the project ID stored persistently (in CLAUDE-rev3.md or a
committed config file). A single-character typo in project ID is
unrecoverable surgery on the wrong database. Visual inspection is
NOT sufficient — the verification is "matches the stored ID exactly,"
not "looks right."

**Gate 5 — Migration history pre-state strict commitment.**
`supabase migration list --linked` must return one of two acceptable
pre-states:

- (a) Empty migration_history (the expected greenfield case for this
  hazard)
- (b) One or more of 000-004 already marked applied (the
  idempotent partial-completion recovery case)

Any other pre-state — 005+ entries present, unknown versions,
partial state across non-000-004 versions, mixed unexpected
entries — triggers STOP for human investigation. The baseline
procedure does NOT silently overwrite unexpected state.

**Gate 6 — Drift verification between local files and actual remote
schema (per 22.9).**

This is the most critical pre-verification gate. Before any repair
command runs, generate the actual remote schema via `supabase db
diff` and compare against the local supabase/schema.sql (Decision
10's generated artifact). If they don't match, STOP and reconcile
before proceeding.

See 22.9 for the full drift handling commitment.

If any gate fails, STOP. Do not proceed to Step 2.

**22.4: Per-command post-verification commitments.**

After each repair command in Step 2, verify the next state via
`supabase migration list --linked`. The just-repaired migration must
show as applied. If unexpected state at any point, STOP and
investigate before proceeding to the next migration in the sequence.

The verification commitments are NOT optional — they are not just
operational hygiene, they are architectural gates. The procedure
explicitly trades sequential-command-overhead for explicit per-step
state visibility. Single-command alternatives (e.g., `supabase
migration repair --linked --status applied 000 001 002 003 004`)
are deliberately NOT used because they defer all verification to
the end and lose per-step state visibility.

**22.5: Failure modes and recovery procedures — six named modes.**

**Mode A — Repair command itself fails.** CLI returns an error
before modifying the migration history. Recovery: address the
underlying error (typically authentication, network, or CLI
version), retry the command. No rollback needed because no state
change occurred.

**Mode B — Partial completion across commands.** Some migrations
are marked applied, others are not (e.g., 000-002 succeeded but 003
failed). Recovery: identify which are already marked applied via
`supabase migration list --linked`, resume the procedure with the
next unrepaired migration. The procedure is idempotent at the
migration level (per 22.2 commitment) so re-running repair on
already-applied migrations is safe.

**Mode C — All repairs succeed but migration history doesn't match
expectations.** Recovery requires direct SQL surgery on
supabase_migrations.schema_migrations. Mode C is gated per 22.10
as a last-resort escape valve with concrete procedural requirements.

**Mode D — Drift between local migration files and actual remote
schema.** This is the most consequential silent failure. The drift
verification gate (22.3 Gate 6, full commitment in 22.9) prevents
this mode from manifesting at baseline time. Without Gate 6, this
mode is silent — post-repair, the migration_history claims a state
the database doesn't actually have; subsequent migrations (005+) may
fail when they assume baseline state that isn't present.

Recovery if Mode D is detected post-baseline (drift discovered
after baseline procedure ran): the situation requires Mode C-style
intervention plus reconciliation work on the local schema.sql and/or
000_baseline.sql to align local files with actual remote state.
Detection mechanism: `supabase db diff` shows differences between
local schema.sql and remote that should not exist post-baseline.

**Mode E — Wrong linked project.** The pre-verification gate
(22.3 Gate 4) prevents this mode by matching the linked project ID
against a known-good stored ID. If the gate fails (linked project
ID does not match stored ID), STOP — do not run repair against the
wrong database.

Recovery if Mode E is detected after repair commands have already
run against the wrong project: requires Mode C on the wrong project
to undo the spurious baseline entries, then correct project linkage
via `supabase link --project-ref <correct-id>`, then restart the
baseline procedure from Step 0.

**Mode F — CLI version mismatch.** The pre-verification gate
(22.3 Gate 3) prevents this mode by checking CLI version against
the pinned tested version. Repair behavior is version-dependent;
running an untested CLI version produces unpredictable results.

Recovery if Mode F is detected before repair commands run: install
the pinned CLI version, re-run pre-verification. Recovery if
detected after repair commands have run with the wrong CLI version:
case-by-case investigation based on actual observed behavior; may
require Mode C intervention.

**22.6: Documentation location — new section "Database Migration
Tooling" in v2.**

Decision 22 adds a new section to v2's architecture reference titled
"Database Migration Tooling." This section was previously flagged as
Tier 4 cross-cutting future work; Decision 22 advances it.

The section is the authoritative reference for migration tooling
across the platform lifecycle, not just the one-time baseline
procedure. Section content includes:

- Historical context of the hazard (why it exists — manual SQL
  Editor changes before migrations directory existed, what the
  original setup looked like, lessons learned)
- The locked baseline procedure (per 22.2, 22.3, 22.4)
- The failure modes and recovery procedures (per 22.5)
- The Mode C gating procedure (per 22.10)
- The Phase 4 transition criteria (per 22.8)
- Cross-references to Decision 10's schema.sql regeneration
  mechanism
- Ongoing operational mechanics post-baseline (how `supabase db
  push` works, how schema.sql regenerates, how to verify migration
  history matches expectation across subsequent migration work)

A future operator reading this section three years from now should
understand both what to do and why this section exists. The section
serves audit defensibility and protects against similar situations
recurring.

**22.7: CLAUDE-rev3.md stop-point evolution and password handling.**

Current CLAUDE-rev3.md stop-point text (lines 71-83) remains in force
until Phase 4 transition criteria (22.8) are satisfied. After
Decision 22 commits but before baseline is executed, the stop-point
text is updated to cross-reference Decision 22's documented
procedure:

"See Decision 22 and the Database Migration Tooling section for the
locked baseline procedure. STOP and surface this hazard if asked
to push migrations to the remote until baseline is verified
complete."

The stop-point itself stays. Claude Code must still STOP and
surface the hazard rather than running migration commands directly,
until Phase 4 transition criteria are satisfied.

**Password handling.** The `supabase migration repair` command takes
a `--password` flag. The procedure specifies:

- Use interactive prompt for password (Supabase CLI default behavior
  if password is not passed inline)
- NEVER inline the password in shell commands
- NEVER commit any artifact containing the password
- The password should not appear in shell history, git history, or
  any committed file

Password-in-shell-history is a real exposure surface. The
interactive prompt is the safer default.

**22.8: Phase 4 transition criteria — four conditions.**

Phase 4 work can begin once ALL four conditions are satisfied:

1. **Baseline procedure executed and verified.** Per 22.2 Steps 0-4
   complete with all per-step verifications passing.

2. **Schema.sql regeneration mechanism verified working
   post-baseline.** Per 22.2 Step 5. The schema generator script
   (or equivalent Decision 10 mechanism) runs successfully and
   produces expected output.

3. **Session-handoff entry documenting successful execution.** A
   session-handoff entry records the execution date, the verifying
   user (Andre), the pre-state observed (per 22.3 Gate 5), the
   post-state confirmed (per 22.4 final verification), and any
   anomalies encountered and resolved. This entry serves as the
   permanent record that baseline was successfully completed.

4. **CLAUDE-rev3.md stop-point updated to RESOLVED.** The stop-point
   text is updated to "RESOLVED" status with the execution date.
   This is the LAST step in the Phase 4 transition. It signals
   that Phase 4 is unblocked.

The four conditions are ordered. Condition 4 (CLAUDE-rev3.md update) is
the LAST step that signals readiness, not parallel to verification.
Sequence: complete baseline -> verify (Steps 4 and 5) -> session
handoff entry -> CLAUDE-rev3.md update -> Phase 4 unblocked.

Before all four conditions are met, Phase 4 work is BLOCKED. After
all four, Phase 4 work proceeds normally and the stop-point becomes
historical context preserved in the Database Migration Tooling section.

**22.9: Drift verification — the critical pre-baseline gate.**

The most consequential failure mode in this procedure (Mode D in
22.5) is silent: post-repair, the migration_history claims a state
the database doesn't actually have. Subsequent migrations (005+)
may assume baseline state that isn't present. The drift verification
gate prevents this mode from manifesting at baseline time.

**Mechanism.** Before Step 2 of the baseline procedure runs:

1. Generate the actual remote schema via `supabase db diff`
2. Compare against the local supabase/schema.sql (Decision 10's
   generated artifact)
3. If they match (no significant drift), proceed to Step 2
4. If they don't match, STOP and reconcile

**Reconciliation.** When drift is detected, two real reconciliation
paths:

- (a) Update 000_baseline.sql to match actual remote state. The
  local file becomes the source of truth for what's actually on
  the remote.
- (b) Apply corrective SQL to the remote to bring it into alignment
  with the local file. The local file remains the authoritative
  source.

The reconciliation choice depends on which state is correct
(intended). Path (a) is appropriate when the remote is the source
of truth (manual changes captured operational decisions that should
persist). Path (b) is appropriate when the local file is the source
of truth (manual changes were accidental drift that should be
corrected).

Either reconciliation path requires explicit Andre approval and a
session-handoff entry documenting the reconciliation. The drift
verification gate is non-optional — bypassing it converts the
baseline procedure from "safe and idempotent" to "potential silent
corruption of migration history."

**22.10: Mode C gating — last-resort escape valve with five named
gates.**

Mode C (all repairs succeed but migration history doesn't match
expectations) requires direct SQL surgery on
supabase_migrations.schema_migrations. This is rare, high-risk,
high-context work. Mode C is gated as a last-resort escape valve
with concrete procedural requirements, not a routine fallback.

**Five gates must be satisfied before any Mode C SQL runs:**

**Gate 1 — Backup before modification.** Capture
supabase_migrations.schema_migrations table contents to a file
before running any UPDATE or DELETE. (This is the same backup
captured in Step 0 of 22.2; verify it exists and is current. If
not, capture it now.) The table is trivially small; the backup
cost is negligible; the safety net matters.

**Gate 2 — Explicit Andre approval of the specific SQL.** Not
"warrantor approval" or "operator approval" — Andre by name. The
SQL must be stated in full (not described abstractly) before
approval is granted.

**Gate 3 — Chat 4 verification round on the specific SQL.** Mode
C is rare enough that the verification round overhead is worth it.
Paste the proposed SQL into chat 4 for independent verification
before running. Chat 4's read is independent of in-session
groupthink and may surface concerns about side effects on related
rows or related state.

**Gate 4 — Session-handoff entry documenting the surgery.** Before
the SQL runs, draft a session-handoff entry capturing: the SQL to
be applied, the rationale, the verification steps run (including
Gates 1-3), the state before, and the expected state after. The
entry goes in the decisions log or a dedicated incident-handling
section.

**Gate 5 — Post-modification verification.** After the SQL runs,
immediately re-run `supabase migration list --linked` and confirm
the actual state matches the expected state from Gate 4. If not,
more surgery is required — return to Gate 1 with the new SQL.

**If any gate fails, do not proceed.** Mode C is not the right
recovery path when any gate fails.

If actual state is genuinely unrecoverable through CLI commands
AND Mode C is also unworkable (e.g., the supabase_migrations table
itself is in an unexpected state), the recovery path becomes
"restore from point-in-time backup" — out of scope for this
Decision but flagged for awareness.

### Schema additions

None. Decision 22 is a procedural Decision; no schema changes are
required for the procedure to be locked. The architectural
commitment is to the procedure documentation and to the Phase 4
transition gating.

### Cross-section dependencies

- **CLAUDE-rev3.md (project-level operational rules):** Stop-point text
  updated per 22.7. Stop-point itself remains in force until Phase
  4 transition criteria are satisfied per 22.8.
- **New section "Database Migration Tooling" in architecture-
  reference-v2.md:** Per 22.6. Section is added to v2 by Decision 22.
- **Decision 10 (Migrations as canonical schema, schema.sql as
  generated artifact):** Schema.sql regeneration is verified as
  part of the Phase 4 transition (22.8 condition 2). Cross-
  referenced from the new Database Migration Tooling section.

### Open architectural questions deferred

- **What if supabase_migrations table itself is in an unexpected
  state.** If the migration_history table itself is corrupted or
  in an unrecoverable state (beyond what Mode C SQL surgery can
  fix), the recovery path becomes "restore from point-in-time
  backup." Backup restoration is out of scope for this Decision;
  flagged for operator awareness if Mode C escalates.

- **Multi-tenant migration tooling complexity.** Decision 22
  addresses the single hosted DB / single tenant scenario at this
  phase. Multi-tenant migration considerations (when WarrantyOS
  serves multiple tenants on the same hosted DB at scale) are
  outside the immediate hazard scope and deferred to future
  Decisions if operational pressure surfaces.

- **Test migration smoke test as additional Phase 4 prerequisite.**
  Chat 4 surfaced this as a possible additional condition for
  Phase 4 transition (apply a no-op migration end-to-end to confirm
  the entire migration pipeline works post-baseline). Not added to
  the four locked conditions but flagged as operational hygiene
  worth doing alongside the schema.sql regeneration verification.

- **Backup verification before Phase 4 starts.** Chat 4 surfaced
  recent point-in-time backup verification as standard pre-major-
  work hygiene. Not added to the locked conditions but flagged
  for operational awareness.

### Decision implications for already-committed sections

**New section in v2's architecture reference:** Database Migration
Tooling. Section content per 22.6.

**CLAUDE-rev3.md stop-point evolution per 22.7:** Cross-reference
updated to point to Decision 22 and the new Database Migration Tooling
section. Stop-point itself remains in force.

These land in subsequent commits this session if pacing permits,
or in a follow-up session if pacing requires deferral.

This Decision resolves Cat 3 backlog item #2 (Hosted-DB-no-migration-
history hazard) at the architectural commitment level. The procedure
itself executes when Phase 4 begins, which is downstream of this
Decision. Remaining Cat 3 backlog: six items.

---

## Decision 23: Warranty Registration Lifecycle Trigger Timing, Actual Start Date Semantics, and Registration Status State Machine (Cat 3 #7 + #6 resolved)

**Decided in Session C (Cat 3 backlog resolution).**

### Context

Cat 3 backlog item #7 (contractual_date_manual creation-timing) opened
with a narrow schema question — when does the warranty_registrations
row come into existence for `contractual_date_manual` trigger source.
v2 flagged the question as unresolved in the Warranty Registration
section's Clock-event interactions subsection: "what specifically
happens at firing time, including whether the registration record is
created at project creation or at prep-event firing, is not specified
by any locked source."

Andre's operational framing during Session C substantially expanded
the scope. The resolution touches:

- The semantic role of `trigger_date` on projects (single confirmed
  contractual date entered at project creation for
  `contractual_date_manual`)
- The introduction of `actual_start_date` on warranty_registrations
  (the operational-reality date the warrantor confirms the warranty
  actually started, distinct from the contractual trigger_date)
- The registration lifecycle timing (registration row is created when
  the `registration_prep_pre_trigger` clock event fires, not at
  project creation)
- The registration status state machine (Cat 3 #6, now resolved as a
  byproduct of #7's resolution)
- Claim eligibility interaction with actual_start_date confirmation
  status
- Migration/import handling for projects missing trigger_date
- Warranty coverage start_date derivation using immutable snapshot
  semantics with COALESCE derivation at query time
- Section 7 rejection handling within the state machine

The scope expansion is architecturally justified because Andre's
operational framing surfaced a first-principle-level commitment:
**the warranty starts according to contract, not warrantor activity.**
Platform state must not create barriers to customer rights that the
contract grants. This principle is documented within Decision 23 as
rationale for specific commitments; a future Decision may elevate it
to a first-principle-level architectural anchor if it recurs across
other domains. Flagged for consideration in a later session.

Cat 3 #6 (Registration status enum richer values) was on the backlog
as a separate item chained after #7. Andre's operational answer to a
mid-drafting question locked #6's resolution — the state machine is
`pre_activation`, `assigned`, `active`, `rejected` (four flat states).
Because #6's resolution is tightly coupled to #7's registration
lifecycle timing, both are resolved together in this Decision rather
than requiring two separate Decisions.

The Decision is informed by chat 4's independent architectural read
which surfaced ten substantive concerns integrated into the locked
commitments below: 23.2's scope restriction to trigger sources with
known-at-creation trigger_date, COALESCE canonicalization as an
application invariant, precise "atomic" language for 23.3, 23.8's
cross-reference expectation, operational queue commitment for
pre_activation, explicit downstream guards for permissive migration,
derived-not-manual commitment for dual flagging, Section 7 rejection
modeled as a fourth state, minor migration hygiene, and temporal
validity commitment for actual_start_date.

### Question

For `trigger_source = 'contractual_date_manual'`: when is the
warranty_registrations row created, what date semantics govern the
project and registration entities across the trigger lifecycle, what
state machine governs the registration's progress (including Section
7 rejection), how does claim eligibility interact with the
"warranty starts per contract" principle, and how is migration/import
handling for missing trigger_date architected?

### Resolution

Fourteen architectural commitments.

**23.1: `projects.trigger_date` is populated at project creation for
`contractual_date_manual` trigger source.**

At project creation for `contractual_date_manual`, the warrantor
enters the contractually-agreed date the warranty is scheduled to be
active. This date populates `projects.trigger_date` at that moment.

This revises the earlier v2 schema comment ("set when trigger_status
becomes 'confirmed'; null until then"). That comment is accurate for
`wbs_integration`, `delivery_report_tokenized`, and
`delivery_report_api` (where trigger_date is populated when the
trigger event actually happens). For `contractual_date_manual`,
trigger_date is populated at project creation — the trigger_source
name itself describes this: it's the manually-entered contractual
date.

`trigger_status` remains `pending` at project creation for
`contractual_date_manual` because the warranty hasn't started yet
(the date is in the future). State transitions of `trigger_status`
are governed by other events, not by the calendar reaching
`trigger_date`.

The trigger_date column comment in the projects table schema MUST be
revised as part of Decision 23's schema commitment. Comment revision:

    trigger_date                date nullable
                                -- For 'contractual_date_manual':
                                --   populated at project creation
                                --   with the contractually-agreed
                                --   warranty active date. Non-null
                                --   at creation (application-layer
                                --   enforcement, exception via
                                --   migration path per 23.11).
                                -- For 'wbs_integration',
                                --   'delivery_report_tokenized',
                                --   'delivery_report_api': populated
                                --   when trigger_status becomes
                                --   'confirmed' (trigger event
                                --   actually happens). Null until
                                --   then.

**23.2: A `registration_prep_pre_trigger` clock event is inserted at
project creation ONLY for trigger sources where trigger_date is
known at project creation.**

This commitment applies to `contractual_date_manual` and to
`wbs_integration` in the "known-in-advance" case where the integration
poller has captured the milestone date at project creation.

At project creation for these sources, the platform calculates
`trigger_date - registration_lead_time_days` (per-tenant configurable
setting, default 21) and inserts a clock_events row of type
`registration_prep_pre_trigger` with that value as `fires_at`. The
entity_type = 'project', entity_id = the project's id.

The clock event is a scheduled reminder — Decision 9's Clock Event
Infrastructure holds the row until the hourly pg_cron poll detects
`fires_at` is in the past AND `status = 'pending'`. On that poll, the
dispatcher runs.

For `delivery_report_tokenized`, `delivery_report_api`, and
`wbs_integration` when trigger_date is NOT known at project creation
(supply-only shape and polling-not-yet-completed shape), the
mechanism is different and locked in Phase 0 Item 17 and current v2:
the warranty_registrations row is created SYNCHRONOUSLY when the
trigger event occurs (buyer report, carrier API confirmation, poller
detection) via a Server Action, not via a clock event. This
distinction is preserved by Decision 23; the clock-event-driven
mechanism applies only where trigger_date is known at creation.

The uniform semantic (trigger_date is the operative warranty start
date) holds across all trigger sources. Only the timing of trigger_date
population — and consequently the mechanism for scheduling registration
creation — varies by trigger source.

**23.3: The warranty_registrations row is created when the
`registration_prep_pre_trigger` clock event fires (for trigger
sources where 23.2 applies).**

When the dispatcher runs the `registration_prep_pre_trigger` event,
its Server Action performs an atomic write:

1. Creates the `warranty_registrations` row associated with the
   project (project_id populated, tenant_id denormalized per Standard
   RLS Pattern)
2. Assigns the registration to an assignee. Assignment populates one
   of `assigned_to_contact_id` or `assigned_to_user_id` per the
   dual-FK model. Captures assignee snapshots
   (`assigned_to_name_snapshot`, `assigned_to_email_snapshot`,
   `assigned_to_phone_snapshot`) per the FK + Snapshot Pattern
3. Sets `warranty_registrations.status = 'assigned'`
4. Sends notification to the assignee

"Atomic" here means the Server Action commits row+state in a single
database write, NOT transactional all-or-nothing across all four
effects. The distinction matters: if the row creation succeeds but
assignment fails (contact FK invalid, assignee soft-deleted between
dispatcher scheduling and firing, notification service down), the
row exists with `status = 'pre_activation'` per 23.7's edge-case
disposition. The atomic commit succeeds to whichever state is
achievable given the partial-failure conditions.

The normal path (all four effects succeed) produces a row directly
in `assigned` state. The `pre_activation` state exists as a fallback
for the partial-failure edge case.

Between project creation and the clock event firing, the registration
row does NOT exist. The project exists (with trigger_date recorded),
but no registration exists yet.

The assignment mechanism (how the Server Action determines the
assignee — pre-configured default per tenant, assignment task
surfaced to team admins, operator selection) is downstream operational
scope. Decision 23 locks that assignment happens as part of the
atomic operation; the mechanism itself is Phase 4 / operational
drafting.

**23.4: `warranty_registrations.actual_start_date` is a new nullable
column with no default.**

Schema addition to warranty_registrations:

    actual_start_date         date nullable
                              -- populated by the warrantor when they
                              --   confirm the warranty actually started
                              --   operationally; null until confirmed;
                              --   no default value

The column is nullable with no default (not a sentinel value like
1900-01-01). Application code checks `IS NULL` to determine whether
actual_start_date has been confirmed.

Purpose: `actual_start_date` captures the date the warrantor has
confirmed the warranty operationally started, which may or may not
equal `trigger_date` (the contractually-agreed date). Warrantor
confirmation happens with no fixed timing — could be before, at, or
after trigger_date. The warrantor confirms whenever they get the
information.

**23.4a: No temporal constraint bounds actual_start_date relative to
trigger_date.**

The relationship between actual_start_date and trigger_date is
operationally unconstrained. Both cases are valid:

- actual_start_date BEFORE trigger_date: warranty started
  operationally earlier than the contractual date. The customer
  benefits from the earlier date via COALESCE derivation per 23.5,
  which favors customer rights per 23.8's principle.
- actual_start_date AFTER trigger_date: warranty started
  operationally later than the contractual date. During the interim,
  the customer's warranty is still active per the contract
  (COALESCE falls back to trigger_date). The dual flagging model
  (23.10) surfaces the gap for warrantor follow-up.

No database CHECK constraint bounds actual_start_date relative to
trigger_date. The gap can be arbitrarily large — no implicit upper
bound. Warrantors decide operationally whether specific gaps warrant
investigation or intervention; the platform does not enforce timing
constraints on actual_start_date confirmation.

**23.5: Warranty coverage `start_date` is populated at coverage
creation with `trigger_date`. Coverage rows are immutable snapshots;
the effective start date is derived at query time via COALESCE.**

At coverage creation, `warranty_coverages.start_date` is populated
with the current value of `projects.trigger_date`. This is a snapshot
at coverage creation.

Later, if `actual_start_date` is confirmed and differs from
trigger_date, coverage rows are NOT updated. Coverage `start_date`
remains as the trigger_date snapshot captured at coverage creation.

The effective start date for warranty calculations (claim eligibility,
end_date derivation, expiry warnings) is derived at query time via
COALESCE:

    effective_start_date = COALESCE(
        warranty_registrations.actual_start_date,
        warranty_coverages.start_date
    )

Where `actual_start_date` is on the parent warranty_registrations row.
When actual_start_date is null, the coverage's snapshotted start_date
(equal to trigger_date at snapshot time) is used. When
actual_start_date is confirmed, it overrides.

This preserves audit-defensibility: coverage rows are historical
records of what was known at creation time. Effective start is
derived, not stored. Historical accuracy is preserved even when
actual_start_date is confirmed after coverages were created and after
claims were filed.

**23.5a: The COALESCE derivation is an APPLICATION INVARIANT.**

Application code MUST use COALESCE(warranty_registrations.actual_start_date,
warranty_coverages.start_date) for effective start date derivation in
ALL of the following contexts:

- Claim eligibility calculations
- Coverage window calculations
- Warranty period displays to warrantors and customers
- end_date derivation (Cat 3 #8, downstream)
- Expiry warning firing calculations

Application code MUST NEVER read `warranty_coverages.start_date`
directly for effective start date purposes. Reading the snapshot
directly bypasses the derivation and produces incorrect effective
start dates whenever actual_start_date has been populated. This is a
silent data corruption failure mode.

This invariant is architecturally comparable to Decision 19's atomic
Accept-and-Signature invariant. It applies uniformly across all code
paths that touch effective start date semantics.

An alternative implementation approach that would eliminate the
application invariant: implement effective_start_date as a PostgreSQL
generated column on warranty_coverages (computed from a join to
warranty_registrations) or as a view. This would enforce the
derivation at the schema level; application code would read a single
column. Adds implementation complexity but eliminates the cross-cutting
invariant. Flagged as a Phase 4 implementation option; Decision 23
does not commit to either the invariant-enforced-in-app or the
generated-column path. The commitment is the derivation semantic;
the enforcement mechanism is a Phase 4 implementation choice.

**23.6: Warranty coverages are created during the prep window by the
assignee.**

Coverages are child rows of warranty_registrations. Under Decision
23's timing model, the warranty_registrations row is created when the
prep event fires (~21 days before trigger_date for the
`contractual_date_manual` case). Coverages come into existence during
the prep window that follows.

The assignee, during their prep work, configures coverages by drawing
down warranty types from the tenant's warranty_types list, setting
term_years for each, and populating coverage rows. Coverage creation
is part of the prep work that must complete before Section 7
activation.

At coverage creation, each coverage row's `start_date` is populated
with the current `projects.trigger_date` value (per 23.5). Each
coverage row's `end_date` is derived from `start_date + term_years`
(the mechanism for this derivation is Cat 3 #8, still on the backlog).

**23.7: warranty_registrations.status state machine is
`pre_activation`, `assigned`, `active`, `rejected` (four flat
sequential states).**

This commitment resolves Cat 3 #6 (Registration status enum richer
values) as a byproduct of Decision 23's registration lifecycle work.

State machine:

- `pre_activation` — the registration row exists but no assignee has
  been captured. This state is reserved for edge cases where the
  clock event dispatcher's atomic operation partially failed
  (assignment failure, notification service down, etc.). The row
  exists in the database, but the atomic operation did not fully
  complete. Not entered during normal operation.

- `assigned` — an assignee has been captured on the registration.
  Assignee is working on prep (configuring coverages, gathering
  Section 7 documentation, etc.). This is the state most registrations
  spend their prep window in.

- `active` — Section 7 activation has passed, WarrantyID has been
  issued, `activated_at` is populated. Registration is live.
  Downstream claims, coverages billing time toward expiry, and
  customer-facing communications reference the WarrantyID.

- `rejected` — Section 7 activation attempt was rejected by the
  reviewer. The registration is not active; the assignee must revise
  and resubmit. This is a transient state (see transitions below).

Transitions:

- doesn't-exist -> `assigned` (normal path, per 23.3's atomic
  Server Action)
- doesn't-exist -> `pre_activation` (edge case, when assignment fails
  during dispatcher)
- `pre_activation` -> `assigned` (when assignment completes after
  edge-case entry, via manual intervention or retry mechanism)
- `assigned` -> `active` (when Section 7 activation gate passes)
- `assigned` -> `rejected` (when Section 7 activation attempt is
  rejected)
- `rejected` -> `assigned` (when the assignee revises and resubmits;
  Section 7 rejection loops back to prep state for revision)

No transition from `active` to any earlier state. Retirement or
cancellation of an active registration is a separate concern not
covered here.

No transition from `rejected` to `active` directly; rejection always
routes back through `assigned` for revision before another activation
attempt.

The CHECK constraint on `warranty_registrations.status` enforces the
four allowed values.

**23.7a: The `pre_activation` state requires an operational queue
surface for warrantor operations.**

Because `pre_activation` is an edge-case fallback state where the
atomic Server Action partially failed, rows in this state require
active operational attention. A registration sitting in `pre_activation`
means: the clock event fired, the row was created, but assignment
did not complete. Something needs to happen to advance the row to
`assigned`.

Without an operational surface, `pre_activation` rows would silently
accumulate as an unnoticed operational failure mode.

Decision 23 commits: the platform surfaces an operational queue for
warrantor team admins showing registrations in `pre_activation` state.
The queue drives active follow-up to resolve the failed assignment
(either by manual assignment through an operational UI, or by
diagnosing and retrying the failed dispatcher path).

The queue's specific UI/UX and the mechanism for resolving
`pre_activation` rows (manual assignment vs retry) are Phase 4 /
operational drafting.

**23.8: Warranty starts per contract, not warrantor activity —
platform state does not block customer rights.**

This commitment is a rationale-level principle informing 23.9 and
23.10. Documenting it explicitly:

The contract between warrantor and customer specifies when the
warranty is active. `projects.trigger_date` records the contractual
date. Warrantor internal delays in confirming operational activation
(`actual_start_date`) do not shift the customer's contractual rights.
If the trigger_date arrives before actual_start_date is confirmed, the
customer's warranty is still active per the contract — the platform
must not deny claims on the basis of internal state.

This principle is architectural, not just operational. It shapes:

- Claim intake behavior when the target project has trigger_date in
  the past and actual_start_date null (23.9)
- Effective start date derivation via COALESCE with trigger_date as
  fallback (23.5)
- The dual flagging model (23.10)

The principle is at rationale-level within Decision 23. It may recur
in future Decisions (claim eligibility rules, warranty expiration
handling, other customer-facing timing questions). If it does, a
future Decision may elevate it to a first-principle-level
architectural anchor comparable to the v1 Core Operational Philosophy
principles. That elevation is out of scope for Decision 23; flagged
for consideration.

**Cross-reference expectation: any future Decision that touches
claim eligibility, coverage window calculations, warranty expiration
handling, or customer-facing timing MUST reference 23.8 explicitly.**
Absent this cross-reference discipline, future Decisions could
inadvertently contradict the warranty-starts-per-contract principle
by making customer rights conditional on warrantor-side state without
recognizing 23.8. Decision 23 names this expectation to preserve the
principle across future architectural work.

**23.9: Claim eligibility uses effective start date via COALESCE with
trigger_date as fallback.**

For claim eligibility calculations:

    effective_start_date = COALESCE(
        warranty_registrations.actual_start_date,
        projects.trigger_date
    )

Where projects.trigger_date is the contractually-agreed date
(populated at project creation for `contractual_date_manual`) and
warranty_registrations.actual_start_date is the warrantor-confirmed
operational date.

Note: 23.5 defines the same COALESCE pattern operating on
warranty_coverages.start_date (the snapshot of trigger_date). Both
patterns are semantically equivalent because coverage.start_date IS
trigger_date at snapshot time. The distinction: 23.5 governs coverage
derivations (end_date calculations, coverage windows); 23.9 governs
claim eligibility. Application code paths may use either derivation
depending on which parent entity is being queried; both must produce
the same effective_start_date value for the same registration.

Claim eligibility rules (Cat 3 #1, still on the backlog) will build
on this effective start date. This commitment establishes the
derivation; the specific rules for what makes a claim eligible are
downstream.

The COALESCE with trigger_date as fallback IS the mechanism by which
the warranty-starts-per-contract principle is enforced. When
actual_start_date is null (warrantor hasn't confirmed yet), the
customer's warranty is still active per the contractual trigger_date.

**23.10: Dual flagging model — project-level operational queue AND
claim-level flagging, both derived-not-manual.**

Two independent surfaces flag the "actual_start_date not yet
confirmed" condition when it arises operationally:

- **Project-level operational queue.** Projects where trigger_date has
  passed AND actual_start_date is still NULL surface in an operational
  queue for warrantor follow-up. The queue drives ongoing operational
  cleanup independent of any claims filed. Team admins can review the
  queue and confirm actual_start_date values in batch.

- **Claim-level flagging.** Claims filed against a project where
  actual_start_date is NULL are accepted normally (per 23.8's
  warranty-starts-per-contract principle) but individually flagged in
  the claim intake surface. The reviewer sees "this claim was filed
  against a project with unconfirmed actual_start_date" as context,
  which may inform their evaluation but does not block the claim.

Both flags exist because they serve different operational purposes:
the project-level queue drives proactive follow-up before claims are
filed; the claim-level flag surfaces context to reviewers evaluating
specific filed claims. Both flags clear when actual_start_date is
confirmed.

**Both flags are DERIVED from current state, NOT MANUALLY MAINTAINED.**
The project-level queue is a query filter over projects
(`WHERE trigger_date < NOW() AND registration.actual_start_date IS
NULL`). The claim-level flag is a derived boolean computed at claim
display time from the same conditions. Neither flag is a stored
boolean column that could go stale, be manually toggled, or diverge
from the underlying state. Both flags are always accurate reflections
of current state.

This derived-not-manual commitment prevents the two flags from
becoming divergent sources of truth. If either flag were stored as
state, they could conflict — one flag might be cleared while the
other remained set, producing inconsistent operator experience.
Derived flags cannot diverge because they're computed from the same
underlying columns.

**Claim history preservation:** When a flagged claim is filed, and the
flag later clears (actual_start_date populated), the claim's current
flag state clears too. However, the audit trail preserves that the
claim was flagged at filing time. The specific mechanism (audit table
entry, timestamped flag history, event log) is downstream operational
drafting; the architectural commitment is that filing-time flag
state is preserved in audit-defensible form.

**23.11: Migration/import handling for projects with missing
trigger_date, with explicit downstream guards.**

Per Decision 8's data migration tooling and Decision 22's operational
model, some project rows may be migrated into the system with
`trigger_source = 'contractual_date_manual'` and `trigger_date = NULL`
because the customer's source data was incomplete at migration time.

Migration handling:

- The project row is created in the system despite missing
  trigger_date (permissive-with-surfacing model)
- The `registration_prep_pre_trigger` clock event is NOT created at
  migration time (no known trigger_date to schedule against)
- The row surfaces in a "projects missing trigger_date" operational
  queue for warrantor follow-up
- When the warrantor later enters the trigger_date via post-migration
  editing, the Server Action creates the `registration_prep_pre_trigger`
  clock event at that point (scheduled to fire at
  `trigger_date - registration_lead_time_days`)

Application-layer enforcement: a project row created through the
standard Server Action (not migration) MUST have `trigger_date`
non-null when `trigger_source = 'contractual_date_manual'`. Migration
is the exception path — Server Action bypass allows migration to
insert rows with missing trigger_date.

The database CHECK constraint on projects does NOT enforce trigger_date
non-null for `contractual_date_manual`, precisely because migration
needs to create these rows. Enforcement is application-layer only.

**Explicit downstream guards:**

Three specific guards must be documented as commitments of the Server
Action layer that handle migrated projects with missing trigger_date:

1. **Deferred clock event creation.** The Server Action that
   populates trigger_date on a migrated project must handle the
   "trigger_date was null, now being populated" case by creating the
   `registration_prep_pre_trigger` clock event at that point (not at
   original project creation). This is the retrospective scheduling
   path.

2. **Cat 3 #1 handoff for in-flight state.** Between migration
   completion and trigger_date population (whether by warrantor entry
   or by never happening), the project exists but has no registration
   and no clock event. Claims may be filed during this in-flight
   state. Claim eligibility handling for "project exists, trigger_date
   populated (past), but registration not yet created" is a Cat 3 #1
   concern; Decision 23 introduces the state (by making registration
   creation deferred through clock event) and thus flags the Cat 3 #1
   handoff explicitly.

3. **Past-dated trigger_date handling.** If a warrantor populates
   trigger_date with a past date (e.g., migrating projects whose
   contractual dates already occurred), the calculation
   `trigger_date - lead_time_days` produces a past `fires_at`.
   Decision 9's clock_events dispatcher fires already-past events on
   the next poll, so this works — the clock event is created, and
   the dispatcher fires it on the next hourly poll. Between the
   trigger_date population and the next dispatcher poll, the project
   exists without a registration; this is an in-flight state that
   the Cat 3 #1 handoff (guard 2 above) covers.

These three guards are architectural commitments of Decision 23, not
downstream operational scope. Server Action implementations for
project creation, project editing (trigger_date update), and the
`registration_prep_pre_trigger` dispatcher must honor these guards.

**23.12: Reassignment mechanics are deferred to a downstream Decision.**

The atomic assignment model in 23.3 handles initial assignment when
the clock event dispatcher fires. Decision 23 does NOT address:

- Reassignment when the current assignee needs to be replaced
  (assignee left the company, incorrectly assigned, deprovisioned,
  or otherwise unavailable)
- Audit trail requirements for reassignment history
- Notification behavior on reassignment (both to old and new assignee)
- Whether reassignment can occur in `active` state or only in
  `assigned` / `rejected` / `pre_activation` states

The atomic model is elegant for initial assignment; reassignment is a
real edge case that requires its own mechanism. Deferring here
preserves 23.3's atomic model without introducing complexity beyond
what Cat 3 #7's scope required.

Flagged for a future Decision (potentially Cat 3 #4 territory, though
#4 was resolved by Decision 21 and did not cover this).

### Schema additions

Two schema changes to existing tables:

**projects (semantic revision + column comment update):**

- `trigger_date` semantics revised per 23.1. Populated at project
  creation for `contractual_date_manual`; unchanged for other trigger
  sources. Application-layer enforcement (via Server Action creating
  projects, not database CHECK) requires trigger_date non-null when
  trigger_source is `contractual_date_manual`, except through the
  migration path per 23.11.
- Column comment on trigger_date MUST be updated per 23.1's revised
  wording. This is a schema migration change (`COMMENT ON COLUMN`
  statement in the Phase 4 migration file).

**warranty_registrations (new column):**

- `actual_start_date date nullable` (no default)

**warranty_registrations (CHECK constraint expansion):**

- The CHECK constraint on `status` must be updated to allow four
  values: `pre_activation`, `assigned`, `active`, `rejected`. This is
  a schema migration change.

No changes to warranty_coverages schema. Coverage `start_date` behavior
is a semantic clarification (23.5) rather than a schema change.

**No data backfill required at migration time.** Existing warranty
registrations get NULL for actual_start_date at migration time,
which is the correct initial state (matching "not yet confirmed").
Phase 4 implementers do NOT need to invent a backfill script.

### Cross-section dependencies

- **Project section** (in v2's architecture-reference-v2-rev3.md):
  - trigger_date semantics revision for `contractual_date_manual`
    (23.1) with column comment update
  - Lifecycle subsection needs updates reflecting trigger_date-at-
    creation semantics for `contractual_date_manual` and
    Decision 23.3's registration creation timing
  - Migration/import handling documented in a subsection (23.11)
    including the three downstream guards

- **Warranty Registration section**:
  - actual_start_date column added to schema (23.4)
  - 23.4a temporal validity commitment (no bounds on
    actual_start_date relative to trigger_date)
  - Registration status state machine explicitly documented as four
    flat states (23.7) with all transitions
  - `pre_activation` operational queue commitment (23.7a)
  - Clock-event interactions subsection updated to reflect Decision
    23.2's scope restriction and Decision 23.3's registration-at-prep-
    event-firing timing (replacing the "not specified by any locked
    source" flag)
  - Assignment semantics clarified with precise atomic language (23.3)
  - Reassignment mechanics deferred (23.12) flagged

- **Warranty Type Coverages section**:
  - Coverage start_date derivation via COALESCE documented (23.5)
  - Coverage creation timing during prep window documented (23.6)
  - Immutability of coverage snapshots documented (23.5)
  - COALESCE application invariant documented (23.5a)

- **Claim Intake Data Model section** (when drafted; currently Tier 3
  deferred):
  - Claim-level flagging for unconfirmed actual_start_date (23.10)
  - Effective start date derivation via COALESCE (23.9)
  - warranty-starts-per-contract principle in claim intake acceptance
    (23.8, cross-reference expectation locked)
  - In-flight state handling for migrated projects (23.11 guard 2)
    handoff to Cat 3 #1

- **Feature Flag System (Phase 0 Item 18)**: No changes needed. The
  `epc_workflow` feature flag already gates `contractual_date_manual`
  projects; Decision 23 operates within that gated scope.

- **Decision 8 (Data Migration Tooling MVP Scope)**:
  Migration/import handling for missing trigger_date (23.11) is a
  post-Decision-8 addendum to Decision 8's Phase 1 import scope.
  Decision 8 already supports customer-data-import; Decision 23 adds
  the specific handling for `contractual_date_manual` projects with
  missing trigger_date.

- **Decision 22 (Database Migration Tooling)**:
  Decision 23 introduces both a schema change (actual_start_date
  column) and a comment/semantic change (trigger_date column comment
  revision per 23.1). Both changes land in a Phase 4 migration file.
  The migration must include `COMMENT ON COLUMN projects.trigger_date
  IS ...` statements to update the semantic documentation. Standard
  Phase 4 operational path applies (Decision 22's ongoing operational
  mechanics): author migration file locally, test, run supabase db
  push after baseline complete, verify with schema.sql regeneration.
  No additional Decision 22 commitments required; the standard path
  covers it.

- **Cat 3 #1 (Claim eligibility rules)**: Decision 23.9 establishes
  the effective start date derivation via COALESCE. Cat 3 #1 will
  build claim eligibility rules on top of this derivation. Decision
  23.11 guard 2 flags the in-flight state (project exists,
  trigger_date populated but past, registration not yet created) as
  a Cat 3 #1 concern that Decision 23 introduces but does not
  resolve.

- **Cat 3 #8 (end_date derivation mechanism)**: Coverage end_date
  derivation (from start_date + term_years) remains Cat 3 #8. Decision
  23.5's immutable-snapshot commitment for coverage start_date holds
  regardless of the end_date derivation mechanism. Cat 3 #8 must
  honor the COALESCE application invariant (23.5a) when computing
  end_date-dependent values.

### Open architectural questions deferred

- **Assignment mechanism at clock event firing (23.3 step 2).** The
  specific mechanism by which the Server Action determines the
  assignee — pre-configured default assignee per tenant, assignment
  task surfaced to team admins, operator selection — is downstream
  operational scope. Decision 23 locks that assignment happens as
  part of the atomic operation; the mechanism itself is Phase 4 /
  operational drafting.

- **What happens to trigger_status when trigger_date is reached.**
  Decision 23 commits that `trigger_status` state transitions are not
  automatically driven by the calendar reaching trigger_date. The
  question of what does drive trigger_status confirmation for
  `contractual_date_manual` (whether it's tied to actual_start_date
  confirmation, to a manual reviewer action, or to something else) is
  flagged for future architectural work.

- **Claim eligibility rules (Cat 3 #1).** Decision 23 establishes the
  effective start date derivation (23.9) that claim eligibility will
  use. The specific rules for what makes a claim eligible against a
  warranty are Cat 3 #1, still on the backlog. Decision 23.11 guard
  2 flags the in-flight state handoff.

- **Warranty expiration handling.** When the warranty period ends
  (start + term_years), what happens to coverages, to the ability to
  file claims, to notifications — all flagged for future architectural
  work. Decision 23 doesn't touch expiration; it only touches the
  start side.

- **Actual_start_date corrections after initial confirmation.** If
  the warrantor confirms actual_start_date and later needs to correct
  it (data entry error, updated operational information), the
  correction mechanism is not specified here. Likely path: standard
  Server Action UPDATE with audit trail; the semantics of what happens
  to already-filed claims after correction is a follow-on question.

- **Reassignment mechanics (23.12).** Deferred to a future Decision.

- **COALESCE enforcement mechanism (23.5a).** Application invariant
  vs. PostgreSQL generated column vs. view — Phase 4 implementation
  choice. Decision 23 commits the derivation semantic; enforcement
  mechanism is downstream.

- **Section 7 rejection audit trail.** When Section 7 rejects a
  registration (transition `assigned` -> `rejected`), the rejection
  reason and rejecting reviewer identity should presumably be captured
  for audit-defensibility. Mechanism not specified here; downstream
  operational scope.

### Decision implications for already-committed sections

**Project section (in v2's architecture-reference-v2-rev3.md):**

- Lifecycle subsection updates per 23.1, 23.2, 23.11
- New "Migration and import handling" subsection or paragraph per
  23.11 including the three downstream guards
- Schema comment revision on trigger_date per 23.1

**Warranty Registration section:**

- Schema addition for actual_start_date per 23.4
- 23.4a temporal validity commitment documented
- Clock-event interactions subsection rewritten per 23.2 (scope
  restriction) and 23.3 (atomic assignment semantics)
- New "Registration status state machine" subsection per 23.7 with
  four states and all transitions
- New "Pre-activation operational queue" subsection per 23.7a
- Assignment semantics documented per 23.3 with precise atomic
  language
- Reassignment mechanics deferral flagged per 23.12

**Warranty Type Coverages section:**

- Coverage start_date derivation subsection per 23.5
- COALESCE application invariant subsection per 23.5a
- Coverage creation timing paragraph per 23.6

**No section-level updates required for Claim Intake Data Model**
(that section is Tier 3 deferred; when it's drafted, Decision 23.8,
23.9, 23.10, 23.11 guard 2 inform it).

### Cat 3 backlog impact

- Item #7 (contractual_date_manual creation-timing) resolved by this
  Decision
- Item #6 (Registration status enum richer values) resolved by this
  Decision as a byproduct of 23.7
- Remaining Cat 3 backlog: FOUR items (was six pre-Decision-23)
  - #1 Claim eligibility rules + emergency carve-outs
  - #5 ALA reminder notifications via clock_events
  - #8 end_date derivation mechanism
  - #9 Customer-O&M Authorization document architecture

Section cascade updates land in subsequent commits this session.

---
## Future decisions

Decisions 17+ will be appended above this section as triage-and-resolve
work continues on the remaining Cat 3 items from the original triage
list. The most urgent remaining Cat 3 items (in priority order):

### Decision 17 (next-session focused workstream)

**Inspections Expansion + tenant-editable defaults pattern + Customer
Work Authorization revision.**

Surfaced mid-drafting of Work Plan Workflow (Session 5f). Three new
enums proposed for the inspections entity, plus potentially a new
Tier 1 platform pattern.

Proposed enums (tenant-editable defaults; defaults provided by platform,
admin at company setup can edit):

- inspection_type (4 values): Warranty, Condition Assessment,
  Remediation Verification, Failure Investigation
- inspection_trigger (7 values): Warranty Claim, Customer Request,
  Repeat Condition Verification, Post-Remediation Verification,
  Failure Investigation, Preventative / Condition Assessment,
  Internal Review
- inspection_status (3 values): Open (inspection created, observations
  in progress), Under Review (warranty review in progress), Issued
  (customer NCR completed and released)

The proposed status enum REPLACES the currently-committed 4-value
status in Inspections Foundation (requested, scheduled, in_progress,
completed). Semantics are different — the new shape captures the
warranty-review workflow state rather than just the inspection
lifecycle.

Architectural questions to resolve in Decision 17:

- The "tenant-editable defaults" pattern is potentially a new Tier 1
  platform pattern. v2 currently has platform-locked enums OR
  tenant-defined JSONB/templates; tenant-editable defaults is a third
  shape (platform provides defaults, tenants can edit). If formalized,
  it has implications across many sections (work_plan_type,
  execution_path, claim_type, gate_purpose, event_type values on Work
  Authorization and Notice of Defect) currently locked as
  platform-level enums.
- The status enum REPLACEMENT requires careful framing — the existing
  4-value enum was corroborated by audit; the new 3-value enum needs
  source-grounded justification.
- Interaction with the existing performed_by / paid_by orthogonal
  axes on Inspections Foundation. Adding inspection_type and
  inspection_trigger creates additional axes; whether they're all
  orthogonal or some are derived needs explicit framing.
- The term "NCR" (non-conformance report) appearing in the status
  semantics. Whether NCR is platform-level concept or per-tenant
  naming convention needs confirmation.

Downstream ripple identified by chat 4 verification:

- Inspections Foundation section (obvious — its own schema changes
  substantively).
- Customer Work Authorization section (Decision 11) — contains a
  specific status-value reference: "Work Authorization with
  customer_decision = 'approved' is required before the inspection's
  status can advance from 'requested' to 'scheduled'." This becomes
  stale if the status enum changes; needs section revision parallel
  to the Inspections Foundation revision.
- Possibly a new Tier 1 pattern section (if tenant-editable defaults
  is formalized).

Work Plan Workflow has no material dependency on Decision 17;
verified by chat 4 independent read during Session 5f. Decision 17
work is its own focused architectural session.

- ALA signature capture mechanism (legal-force question, may be
  per-tenant)
- Claim eligibility rules + emergency carve-outs
- Hosted-DB-no-migration-history hazard (Phase 4 blocker, separate
  session likely needed)
- O&M Provider contact_type
- Inspections claimant-attendance capture
- Inspections requester axis
- Customer review window length configurability (Service Report)
- ALA reminder notifications via clock_events
- Registration status enum richer values
- contractual_date_manual creation-timing
- end_date derivation mechanism (Warranty Type Coverages)

---

## Future capabilities (post-Cat 3 backlog)

The following capabilities are scoped product additions that build on
the core platform after the Cat 3 architectural backlog resolves. They
are not architectural debt; they are future product features whose
architectural design becomes its own Decision when actively taken up.
Each is documented here so that the scope, dependencies, and open
architectural questions are captured at the moment they were
identified, not reconstructed later from chat history.

### Warranty Reserve Forecasting Capability

**Identified mid-session 5f after Work Plan Workflow drafting
completed.**

#### Business problem

Every warranty claim costs money. Most warrantor organizations
estimate warranty reserve amounts using prior-year claim totals plus
a small adjustment — a guess that ignores portfolio size and growth.
A reserve sized for a small portfolio offers no real protection once
the business grows. The platform should answer the question of how
much to reserve with math grounded in actual claim experience rather
than intuition.

#### Capability scope

A decision-support tool that uses the platform's claim history and
project portfolio data to compute warranty reserve requirements as
percentages of project sales price, scaling automatically with
portfolio growth. The capability drives four distinct decision
workflows:

- **Reserve Adder % at contract signing.** Output a per-project
  percentage to include in project pricing to pre-fund warranty risk,
  building the cushion into margin before contract signature rather
  than absorbing claim costs after the fact.
- **Estimated Annual Reserve in finance reviews.** Forward-looking
  total warranty liability across the portfolio, not just
  backward-looking spend.
- **Per-product-line reserve adder analysis for product strategy
  reviews.** Lines with high adder percentages signal warranty costs
  are consuming more margin than expected — surfaces the conversation
  for product reviews before pricing decisions.
- **Sensitivity Analysis for risk management.** Stress test showing
  what reserve requirements look like if claim frequency or severity
  increases above baseline — answers "what does exposure look like in
  a bad year."

#### Calculation approach (high-level)

Reads claim history to compute frequency (claims per active project)
and cost (mean + statistical buffer for cost variability above the
average). Uses Total Sales Price as the denominator to express
reserve requirements as percentages. Applies an admin/overhead
loading factor. Aggregates per-product-line and portfolio-wide.

Specific parameters (statistical buffer multiplier, admin/overhead
loading factor percentage, aggregation rules, etc.) are NOT
hard-coded — they are configurable per tenant via the
tenant-editable defaults pattern. See Question 6 below for how this
ties into Decision 17's pattern work.

#### Architectural dependencies and open questions

The capability has two main data inputs that affect platform
architecture:

**Input 1: Claim history.** Reads from existing claim entities
(claims, work_plans, notices_of_defect, service_reports) plus the
future Cost Tracking section. No new schema needed for this input
beyond Cost Tracking, which is already on the roadmap.

**Input 2: Project portfolio financial data.** Requires NEW financial
dimensions on the Projects entity (currently committed Tier 2). The
Projects entity does not currently capture any financial dimensions.
Adding them is greenfield architecture.

#### Open architectural questions

The future Decision session that takes up this capability needs to
resolve:

**1. Data-vs-capability architectural pattern.**

Per chat 4's verification analysis during Session 5f, the strongest
architectural framing is the hybrid pattern: financial data fields
exist as core platform schema (every tenant captures them, with
independent value for sales analysis, margin reporting, and cost
attribution); the reserve forecasting CALCULATION ENGINE, REPORTING,
and ANALYTICS layer are feature-flagged per Phase 0 Item 18's Feature
Flag System, gated by tenant entitlement to the monetizable
extension.

This pattern separates two concerns v2 has so far treated as one:
"data exists" vs "capability is enabled." The pattern reuses for any
future monetizable extension whose data inputs have independent value
outside the extension itself.

Sub-options ruled out by chat 4's analysis:

- Multi-tenant schema variation (extension activation modifies
  schema per tenant) — breaks v2's uniform-schema-across-tenants
  assumption that other entities rely on.
- Separate project_financials child table — adds join overhead for
  every reporting query without earning its keep for just a few
  scalar financial fields.

**2. Phase 0 Item 18 scope extension.**

The Feature Flag System's current documented scope is
workflow-oriented (gating whether tenants can perform certain
workflows). Reserve forecasting is a CAPABILITY gated by
ENTITLEMENT, structurally similar but semantically different. The
Decision session may need to extend Item 18's documented scope to
explicitly cover monetizable capability-gating, not just workflow
toggles. Small but architecturally meaningful extension.

**3. Independent-value test for financial fields.**

The hybrid pattern (data is core, capability is gated) is load-
bearing on the claim that financial fields have value outside the
reserve forecasting extension — sales analysis, margin reporting,
cost attribution percentages. The Decision session should test this
claim against operational reality. If the fields genuinely have
independent value, the hybrid pattern wins. If they're dead weight
for non-extension tenants, capture goes under the feature flag along
with the calculation engine.

**4. Required financial dimensions (over-provisioning question).**

Andre's existing organization (Terrasmart) uses four financial
dimensions to drive reserve forecasting:

- Total Sales Price (reserve denominator)
- Materials Cost (direct material component)
- Labor Cost (installation scope where applicable)
- Admin/Overhead Markup (organizational loading factor)

The labels are Terrasmart-specific but the OPERATIONAL CONCEPT
(capturing project sales/cost/margin structure) is industry-universal.
The Decision session should confirm that four dimensions are
SUFFICIENT for accurate reserve forecasting across the variety of
warrantor business models, or expand the set.

Asymmetric risk principle: if we plan for 7 dimensions and most
tenants only use 5, that's fine — unused dimensions are nullable. If
we plan for 4 and discover 7 are needed, the tool fails for some
tenants OR requires later schema expansion (technically possible but
operationally messier).

Speculative additional candidate financial dimensions (not confirmed
as needed; included as starting points for research during the
Decision session):

- Equipment/Capital Cost — when projects involve equipment
  depreciation or capital amortization separate from materials
- Subcontractor Cost — when subcontractor work is part of project
  delivery and tracked separately from internal labor
- Warranty Period in years — longer warranty drives higher reserves;
  calculation input even though not strictly financial
- Geographic Risk Factor — some warrantors may price reserves based
  on regional climate/environmental risk variation
- Product Mix Categorization — different product lines have
  different failure modes; reserve calculation may need
  product-mix-aware factors

These are speculative pattern-matches from general engineering
accounting practice, not confirmed from solar-EPC-specific domain
research. The Decision session should validate against industry
practice and confirm or expand the set.

**5. Field-naming question.**

The financial dimensions are operationally universal but labels vary
across warrantor organizations. The Decision session should resolve:

- Platform-locked column names with generic labels (e.g.,
  total_sales_price), with UI label customization at the tenant
  level (display "Contract Value" or whatever the tenant's preferred
  terminology) — likely lean given other tenant-naming patterns in v2
- Tenant-defined field labels with platform-locked column semantics
- Some other approach surfaced during the Decision session

**6. Calculation parameters use Decision 17's tenant-editable
defaults pattern.**

The reserve forecasting calculation includes parameters that should
NOT be hard-coded: the statistical buffer multiplier, the
admin/overhead loading factor, aggregation rules, and any other
calculation tunables that future operational reality surfaces.

Per Andre's instruction, these parameters use the tenant-editable
defaults pattern: platform ships with sensible defaults, admin at
company setup can edit them per tenant. This is the SAME
architectural pattern Decision 17 is taking up for Inspections
(inspection_type, inspection_trigger, inspection_status defaults).

The reserve forecasting Decision session does NOT need to
re-architect the tenant-editable defaults mechanism. It just applies
whatever pattern Decision 17 establishes. The Decision 17 work
should be explicit that the pattern is platform-wide, not
Inspections-specific.

If the tenant-editable defaults pattern emerges as a new Tier 1
platform pattern (which chat 4's verification suggested it might),
reserve forecasting calculation parameters are one of its canonical
uses alongside Inspections.

#### Precedent significance

The Decision session that resolves this capability also establishes
the precedent pattern for future monetizable extensions on the
platform. Whatever architectural pattern lands here (hybrid data-
core/capability-gated, or capability-gated-only, or other) becomes
the template for the next monetizable extension. The Decision
session should be explicit that it is setting a reusable pattern,
not just resolving this one case.

#### Cross-section dependencies

- **Projects entity (Tier 2):** requires schema expansion to add the
  financial dimensions. Parallel to Decision 17's Inspections
  Foundation revision pattern.
- **Cost Tracking (future Tier 3):** reads project financials to
  attribute claim costs back as percentages of sales price. Cost
  Tracking's queries assume the financial fields exist on Projects.
- **Feature Flag System (Phase 0 Item 18):** scope extension to
  cover capability-gating beyond workflow-gating.
- **Decision 17 tenant-editable defaults pattern:** calculation
  parameters use this pattern; reserve forecasting is one of the
  canonical uses if the pattern formalizes as Tier 1.

#### Implementation status

Not yet drafted. Captured here as future scope for the Decision
session that takes up reserve forecasting. Priority ordering:
after the 11 Cat 3 backlog items and Decision 17 resolve.

---

## Decision 24: end_date Derivation Mechanism (Warranty Type Coverages)

**Decided in Session D (Cat 3 backlog resolution).**

### Context

Decision 23.5a locked that effective_start_date is derived via
COALESCE(warranty_registrations.actual_start_date,
warranty_coverages.start_date), with enforcement flagged as either
an application-layer invariant OR a schema-level mechanism
(generated column or view) as a Phase 4 implementation option. The
current v2 Warranty Type Coverages section carries the "end_date is
derived, not stored" commitment and names two candidate mechanisms
(Postgres generated column vs. application-layer computation),
deferring the choice.

Cat 3 backlog item #8 asked for the end_date derivation mechanism
to be locked. Chat 3's independent architectural review surfaced
that a generated column cannot express the cross-table COALESCE
(Postgres generated columns may only reference columns on their
own table), reducing the real choice to application-layer
computation vs. a database view.

This Decision resolves the mechanism choice for BOTH
effective_start_date AND effective_end_date via a single database
view, exercising the schema-level enforcement option that Decision
23.5a flagged. It supersedes 23.5a's application-layer default and
extends the invariant family to end_date.

### Question

What mechanism enforces the COALESCE derivation for effective start
and effective end dates on warranty coverages, and how does that
mechanism interact with the Standard RLS Pattern's tenant isolation
guarantees?

### Resolution

Seven architectural commitments.

**24.1: No end_date column is added to warranty_coverages.**

Confirms the already-locked "derived, not stored" commitment. The
base warranty_coverages table remains as-is: start_date is an
immutable snapshot of trigger_date at coverage creation, term_years
is the immutable term length. No end_date column, no
effective_end_date column, no snapshot-only computed value on the
base table.

**24.2: A database view named warranty_coverages_effective is
created.**

The view joins warranty_coverages with its parent
warranty_registrations and exposes computed effective_start_date
and effective_end_date columns alongside the base coverage columns
needed for downstream reads.

View definition:

    CREATE VIEW warranty_coverages_effective
    WITH (security_invoker = true)
    AS
    SELECT
      c.id,
      c.tenant_id,
      c.warranty_registration_id,
      c.warranty_type_id,
      c.start_date,
      c.term_years,
      COALESCE(r.actual_start_date, c.start_date)
        AS effective_start_date,
      (COALESCE(r.actual_start_date, c.start_date)
        + (c.term_years || ' years')::interval)::date
        AS effective_end_date
    FROM warranty_coverages c
    JOIN warranty_registrations r
      ON r.id = c.warranty_registration_id;

The view exposes both effective_start_date and effective_end_date
in a single object so that application code and operational tooling
have one canonical read surface for coverage timing.

**24.3: Application code reads warranty_coverages_effective for
effective start/end dates.**

All read paths that need effective_start_date or effective_end_date
MUST query warranty_coverages_effective, not warranty_coverages
directly. The base table's start_date and term_years remain
readable for schema-inspection or historical-snapshot purposes, but
any read that treats them as effective values is architecturally
prohibited.

Contexts where the view MUST be used:

- Claim eligibility calculations
- Coverage window calculations
- Warranty period displays to warrantors and customers
- Expiry warning firing calculations (warranty_expiry_warning clock
  events)
- Reports and dashboards showing coverage timing
- Any operational tooling that filters, sorts, or displays coverage
  end dates

Reading warranty_coverages.start_date + term_years directly at the
application layer, bypassing the view, reproduces the silent data
corruption failure mode 23.5a exists to prevent. This is
architecturally prohibited.

**24.4: The 23.5a invariant is now schema-enforced via the view,
not application-layer.**

This commitment supersedes Decision 23.5a's application-layer
default. Decision 23.5a explicitly flagged "PostgreSQL generated
column or view" as a Phase 4 implementation option; Decision 24
exercises the view option.

Both effective_start_date and effective_end_date are enforced at
the schema level via warranty_coverages_effective's column
definitions. The application-layer MUST/MUST NEVER language in
23.5a is retained conceptually but its enforcement mechanism shifts
from "every read site applies COALESCE" to "every read site queries
the view."

Scope boundary: Decision 23.9's claim eligibility COALESCE operates
on projects.trigger_date as the fallback (different parent entity
than warranty_coverages.start_date). Decision 24's view does NOT
cover Decision 23.9's derivation — 23.9 remains application-layer
because it involves a different join structure. Decision 24 covers
coverage-level derivations only.

**24.5: The view uses security_invoker = true for RLS pass-through.**

Postgres views default to executing with the view owner's
privileges (SECURITY DEFINER behavior). Without security_invoker =
true, the view would bypass Row-Level Security policies on the
underlying tables, creating a cross-tenant data leak vector.

The security_invoker = true attribute (Postgres 15+) causes the
view to execute with the querying user's privileges, respecting
RLS policies on warranty_coverages and warranty_registrations.
Tenant isolation is preserved.

This attribute is REQUIRED and non-optional. Any migration
creating this view MUST include WITH (security_invoker = true).
Any view alteration MUST preserve the attribute.

The missing-GRANTs incident from Phase 1 (a table with missing
grants that PostgREST could not see at all) is the precedent for
treating view security as a first-class schema concern. The
Standard RLS Pattern is being extended in this Decision's cascade
to formalize the security_invoker convention for all future views.

**24.6: Cross-reference discipline.**

Per Decision 23.8's cross-reference expectation, any Decision
touching claim eligibility, coverage window calculations, or
customer-facing timing MUST reference 23.8 explicitly. Decision 24
touches all three via the view's effective_end_date exposure.

Decision 24 acknowledges Decision 23.8's warranty-starts-per-
contract principle: the view's COALESCE derivation with start_date
(the trigger_date snapshot) as fallback preserves the customer's
contractual warranty rights when actual_start_date is not yet
confirmed. Coverage end calculations proceed based on the
contractual date, not blocked by pending warrantor operational
confirmation.

Future Decisions touching coverage expiration, claim eligibility,
warranty period display, or expiry warning firing MUST reference
both 23.5a (as refined by 24.4) and Decision 24 as the
authoritative sources for effective start/end date derivation.

**24.7: Materialized view question deferred.**

For very large coverage tables with high-read patterns, a
materialized view might offer performance advantages over the
standard view via cached results. Decision 24 does not commit to
materialized view semantics. Rationale:

- Prototype-phase performance requirements are not yet
  characterized
- Materialized views add refresh-management complexity (when to
  refresh, refresh triggers, stale-read tolerance)
- The standard view meets correctness requirements and is
  operationally simpler
- If read performance becomes a bottleneck, a future Decision can
  convert to materialized

Deferred, not foreclosed. Flagged for revisit if operational
pressure surfaces.

### Schema changes

One schema addition:

- New view: warranty_coverages_effective
- Attribute: WITH (security_invoker = true) — REQUIRED
- Join: warranty_coverages c JOIN warranty_registrations r
  ON r.id = c.warranty_registration_id
- Exposed columns: base coverage columns (id, tenant_id,
  warranty_registration_id, warranty_type_id, start_date,
  term_years) plus computed effective_start_date and
  effective_end_date

No changes to warranty_coverages base table. No changes to
warranty_registrations base table.

Migration must include appropriate GRANTs on the view for the
application role that PostgREST uses, following the same pattern
as base table GRANTs. Missing GRANTs on the view will produce the
same failure mode as missing GRANTs on a table.

### Cross-section dependencies

- **Warranty Type Coverages section** (v2):
  - "end_date is derived, not stored" subsection: update to reflect
    view-based mechanism per 24.1, 24.2, 24.3
  - "Coverage start_date derivation" subsection: update to note
    schema-level enforcement per 24.4
  - Possibly a new subsection or paragraph on
    warranty_coverages_effective view semantics

- **Standard RLS Pattern section** (v2):
  - New subsection or paragraph on view security convention:
    views on tenant-scoped tables MUST use security_invoker = true
    (Postgres 15+ required). References Decision 24 as trigger case
    and the missing-GRANTs Phase 1 precedent.

- **Decision 22 (Database Migration Tooling)**: The view addition
  is a Phase 4 migration. Standard Phase 4 operational path applies
  (author migration file locally, test, run supabase db push after
  baseline complete, verify with schema.sql regeneration). No
  additional Decision 22 commitments required.

- **Cat 3 #1 (Claim eligibility rules)**: When Cat 3 #1 is
  resolved, its eligibility logic MUST use
  warranty_coverages_effective per 24.3. Decision 23.9's separate
  COALESCE (on projects.trigger_date) remains application-layer per
  24.4 scope boundary.

### Open architectural questions deferred

- **View column subset.** Decision 24 exposes base coverage columns
  plus effective_start_date and effective_end_date. Whether
  additional derived columns (e.g., days_remaining,
  is_active_flag) should be exposed via the view is deferred to
  operational need.

- **Materialized view path.** Per 24.7.

- **View-based enforcement for Decision 23.9.** Decision 23.9's
  claim eligibility COALESCE could theoretically be enforced via a
  parallel view joining projects with warranty_registrations. Not
  in scope for Decision 24; deferred pending operational pressure.

### Decision implications for already-committed sections

**Standard RLS Pattern section:**
- New "View security convention" subsection (or paragraph within
  an existing subsection) documenting the security_invoker = true
  requirement per 24.5

**Warranty Type Coverages section:**
- "end_date is derived, not stored" subsection rewritten to reflect
  view-based mechanism
- "Coverage start_date derivation" subsection updated to note
  schema-level enforcement supersedes application-layer default
- Possibly new subsection introducing warranty_coverages_effective

**No section-level updates required for Claim Intake Data Model**
(that section is Tier 3 deferred).

### Cat 3 backlog impact

- Item #8 (end_date derivation mechanism) resolved by this Decision
- Remaining Cat 3 backlog: THREE items (was four pre-Decision-24)
  - #1 Claim eligibility rules + emergency carve-outs
  - #5 ALA reminder notifications via clock_events
  - #9 Customer-O&M Authorization document architecture

Section cascade updates land in subsequent commits this session.


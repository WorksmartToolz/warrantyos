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

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
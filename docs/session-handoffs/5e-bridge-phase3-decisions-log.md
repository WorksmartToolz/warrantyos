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

## Future decisions

Decisions 13+ will be appended below as triage-and-resolve work continues
on the remaining Cat 3 items from the 14-flag list. The most urgent
remaining Cat 3 items (in priority order):

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
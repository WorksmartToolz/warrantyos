-- 021_inspections.sql
--
-- The Inspection: a claim-level investigation into a defect's cause, scope, or
-- fix. The warranty professional uses one when the information in a claim is
-- insufficient to determine corrective actions, or when an Indistinct claim
-- needs investigation before warranty determination. v1's Six Gates reference
-- inspection at Gate 3 (Evidence Evaluation) and downstream.
--
-- This table is the first v2 entity with mixed enum-handling patterns and is
-- the architecture's canonical reference example for the role-based decision
-- tree the Tenant-Editable Defaults Pattern specifies. Five enum-like columns
-- span three patterns:
--   performed_by       - platform-locked CHECK enum (structural axis: values are
--                          universal across warrantor business models and drive
--                          authority checks).
--   paid_by            - platform-locked CHECK enum (structural axis: values are
--                          universal and drive cost recovery routing).
--   inspection_type    - Tenant-Editable Defaults (categorization: values vary
--                          by tenant business and operational vocabulary).
--   inspection_trigger - Tenant-Editable Defaults (categorization: values vary
--                          by tenant business).
--   status             - platform-locked CHECK enum (workflow-driver: platform
--                          code branches on the value to drive the state
--                          machine).
-- The assignment is the role-based decision tree applied per column. Future v2
-- entities with multiple enum-like columns follow the same per-column reasoning
-- rather than picking one uniform pattern across the entity. Do NOT harmonize.
--
-- This migration completes steps 4 and 5 of the Tenant-Editable Defaults
-- six-step convention: the operational table's FK + value snapshot columns.
-- The lookup tables are 018 (inspection_types) and 019 (inspection_triggers).
--
-- Locked sources:
--   architecture-reference.md "Inspections Foundation" -> the inspections schema
--     sketch, the five enum-like columns, inspection_report JSONB, the
--     mixed-pattern role-based reasoning, the deliberate-omissions list.
--   architecture-reference.md "Tenant-Editable Defaults Pattern" -> "Operational
--     table integration via FK + Snapshot" (steps 4 and 5, verbatim shape).
--   architecture-reference.md "FK + Snapshot Pattern" -> the core rule: snapshot
--     written at association time, never updated on read, never re-synced.
--   Decision 17 Part A - the pattern; 17.A.6 - no PostgreSQL triggers at v1.
--   Decision 17 Part B - the four default inspection_types and eight default
--     inspection_triggers; the four-value status enum replacing the original.
--   Decision 18.1 - claimant attendance (Joint Inspection) is a non-feature at
--     the schema level.
--   Decision 18.2 - the requester axis is captured by inspection_trigger; there
--     is no separate requested_by column.
--
-- performed_by and paid_by are TWO ORTHOGONAL AXES, deliberately not one
-- conflated enum. Audit Topic 11 proposed a single three-value enum
-- (internal | third_party | customer_paid), which tries to express both who
-- runs the inspection and who pays through one column. It cannot express real
-- cases: a claimant-funded warrantor-performed inspection, or a
-- warrantor-performed inspection reimbursed by a vendor or insurer. All six
-- performer/payer combinations are operationally real and natively supported.
-- There is deliberately NO CHECK coupling the two columns.
--
-- ON DELETE resolved at build time on claim_id: RESTRICT.
--
--   The arch ref leaves this one open — "ON DELETE behavior on the claim_id FK
--   is not yet locked... the specific clause is a Phase 3 implementation
--   detail" — while naming both the parallel and the restraint plainly:
--   "RESTRICT, with soft-delete as the operational cleanup path." RESTRICT is
--   that restraint at the database layer, matching the 010/016/020 precedent
--   for parent rows carrying independent meaning. CASCADE would hard-delete
--   audit-bearing investigations into defect causation — the cascade-
--   destruction of auditable data the architecture names as the outcome to
--   avoid. 017's CASCADE does NOT transfer here: Decision 3's rationale there
--   is that a custom field value is a dependent attribute, not an independent
--   record. An inspection is an independent record with its own state machine,
--   its own findings, and its own lifecycle.
--
-- ON DELETE on the two lookup FKs: RESTRICT. NOT a deferred question.
--
--   The arch ref states it outright: ON DELETE on the two FKs to the lookup
--   tables "is governed by the lookup tables' soft-delete semantics per the
--   Tenant-Editable Defaults Pattern; hard-deletion is not an ordinary path."
--   RESTRICT is also the only architecturally available clause here, not merely
--   the preferred one: both columns are NOT NULL, so SET NULL is illegal, and
--   CASCADE would destroy inspection history when a tenant hard-deletes a
--   lookup row — exactly what the pattern's soft-delete semantics exist to
--   prevent.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   - No unique on claim_id. A claim may have zero, one, or many inspections
--     over its lifecycle (an initial internal inspection, then a third-party
--     expert inspection if the first is inconclusive). The arch ref is explicit.
--     Same one-to-many shape as work_plans (020).
--   - No CHECK coupling performed_by and paid_by. The two axes are independent
--     and every combination is valid; a coupling CHECK would re-introduce
--     exactly the conflation Audit Topic 11's enum was rejected for.
--   - No inspection_statuses lookup table. status is a platform-locked CHECK
--     enum per the role-based decision tree (workflow-driver). Tenant additions
--     would create unknown states the platform's state machine cannot handle.
--     This deliberately differs from inspection_type/inspection_trigger on the
--     same table: different role, different pattern.
--   - No claimant-attendance column. Decision 18.1 resolves Joint Inspection
--     posture as a non-feature at the schema level; tenants who track it
--     operationally do so in inspection_report JSONB. Parallel to Decision
--     13.4's Warranty FOS / Construction Support framing: tenant-specific
--     terminology is per-tenant naming, not platform vocabulary.
--   - No requested_by / requester column. Decision 18.2: the requester axis is
--     read from the trigger value (Customer Request implies claimant-initiated;
--     Third Party implies external-party-initiated; the remaining trigger values
--     imply warrantor-initiated).
--   - No scheduling, findings, or recommendation columns (planned start date,
--     scheduled party, findings detail). Operational detail lives inside
--     inspection_report JSONB per shape, or in downstream entity tables (Work
--     Authorization, work_plans). Audit Topic 11's framing, honored here: "the
--     foundation costs little; the workflow comes later."
--   - No cost-tracking columns. Cost tracking is its own Tier 3 section, which
--     reads paid_by to determine the recovery path. Inspection costs feed that
--     section; they do not live here.
--   - No custom field involvement. Inspections are outside Decision 3's Phase 1
--     custom-field entity scope (projects, warranty_registrations, claims).
--     inspection_report JSONB is the flexibility mechanism in lieu.
--   - No work_authorization_id and no ala_id FK. Both cross-entity dependencies
--     (Work Authorization before an on-site inspection commences per SOP 1; the
--     ALA gate on Indistinct claims) are explicitly deferred by the arch ref to
--     downstream Tier 3 sections.
--   - No clock_events wiring. Whether inspections insert clock_events rows for
--     reminder firing, or whether reminders are derived at read time, is flagged
--     open for downstream operational drafting. Clock Event Infrastructure
--     supports adding inspection-related event types without restructuring.
--   - No PostgreSQL trigger enforcing the FK + snapshot sync invariant.
--     Decision 17.A.6: no triggers at v1. The canonical validation helper is
--     application-layer, and the schema is already in its final trigger-ready
--     shape (the pattern's commitment 3), so the future migration to trigger
--     enforcement is a pure DB-layer change.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints):
--
--   - tenant_id matches the referenced claim's tenant_id. The arch ref marks
--     this "CHECK / app-layer invariant"; 17.A.6 caps v1 DB enforcement, and
--     016/017/020 all place the tenant-match invariant app-layer. Precedent
--     followed.
--   - inspection_type_value matches the referenced inspection_types.value at row
--     creation; likewise inspection_trigger_value. Enforced through the single
--     canonical validation helper (the pattern's commitment 1).
--   - The referenced lookup row exists, its tenant_id matches, disabled_at IS
--     NULL, deleted_at IS NULL, and its lock_tier permits the operation (the
--     canonical validation rule, the pattern's commitment 2).
--   - inspection_report JSONB shape validation per inspection shape. The
--     expected shapes are downstream operational drafting, not architectural.

create table public.inspections (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references public.tenants(id),
                            -- denormalized per Standard RLS Pattern.
  claim_id                  uuid not null
                              references public.claims(id) on delete restrict,
                            -- NO unique: zero, one, or many inspections per
                            --   claim across its lifecycle.
  performed_by              text not null,
                            -- WHO PERFORMS. Orthogonal to paid_by; drives
                            --   authority checks (which credentials apply).
  paid_by                   text not null,
                            -- WHO PAYS. Orthogonal to performed_by; drives cost
                            --   recovery routing.
  inspection_type_id        uuid not null
                              references public.inspection_types(id) on delete restrict,
  inspection_type_value     text not null,
                            -- Tenant-Editable Defaults, steps 4 and 5: FK gives
                            --   database-enforced referential integrity to the
                            --   per-tenant lookup table; the snapshot preserves
                            --   the value at row creation. Never re-synced —
                            --   the FK may drift if the label is later edited,
                            --   the snapshot cannot.
  inspection_trigger_id     uuid not null
                              references public.inspection_triggers(id) on delete restrict,
  inspection_trigger_value  text not null,
                            -- same FK + Snapshot shape; also carries the
                            --   requester signal per Decision 18.2.
  status                    text not null default 'open',
                            -- four-value state machine (Decision 17 Part B).
  inspection_report         jsonb,
                            -- per-inspection findings, structured per inspection
                            --   shape; null until findings are captured. Same
                            --   convention as claims.claim_type_data: variable-
                            --   schema-by-discriminator data goes in JSONB,
                            --   validated application-layer.
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint inspections_performed_by_check check (
    performed_by in ('warrantor', 'third_party')
  ),
  constraint inspections_paid_by_check check (
    paid_by in ('warrantor', 'claimant', 'third_party')
  ),
  constraint inspections_status_check check (
    status in (
      'open',
      'in_progress',
      'under_review',
      'issued'
    )
  )
);
create index inspections_tenant_id_idx
  on public.inspections (tenant_id);
create index inspections_claim_id_idx
  on public.inspections (claim_id);
comment on table public.inspections is
  'A claim-level investigation into a defect''s cause, scope, or fix '
  '(Decision 17 Part B, Decision 18). Used when a claim''s information is '
  'insufficient to determine corrective actions, or when an Indistinct claim '
  'needs investigation before warranty determination. Zero, one, or many per '
  'claim. The canonical reference example for the Tenant-Editable Defaults '
  'role-based decision tree: five enum-like columns across three patterns.';
comment on column public.inspections.performed_by is
  'WHO PERFORMS the inspection: warrantor (own personnel) or third_party (an '
  'external expert, subcontractor, structural engineer, manufacturer''s rep, or '
  'independent investigator). Platform-locked CHECK enum — a structural axis '
  'universal across warrantor business models. Orthogonal to paid_by: every '
  'performer/payer combination is operationally real and valid.';
comment on column public.inspections.paid_by is
  'WHO PAYS for the inspection: warrantor, claimant, or third_party (vendor '
  'reimbursement, insurer-funded, or similar cases where cost is borne by a '
  'party external to the warrantor-claimant relationship). Platform-locked '
  'CHECK enum — a structural axis. Read by the Tier 3 cost-tracking section to '
  'determine the cost recovery path. Orthogonal to performed_by.';
comment on column public.inspections.inspection_type_value is
  'Snapshot of inspection_types.value at row creation (FK + Snapshot Pattern). '
  'Never updated on read, never re-synced when the lookup row changes. Lets '
  'cross-tenant analytics filter on value without joining the per-tenant lookup '
  'table; per-tenant queries reading the current label join through the FK.';
comment on column public.inspections.inspection_trigger_value is
  'Snapshot of inspection_triggers.value at row creation (FK + Snapshot '
  'Pattern). Never re-synced. Also answers the WHO-asked question per Decision '
  '18.2 — Customer Request implies claimant-initiated, Third Party implies '
  'external-party-initiated, the remaining trigger values imply '
  'warrantor-initiated. There is deliberately no requested_by column.';
comment on column public.inspections.status is
  'Platform-locked workflow-driver enum. open (created, awaiting activity; '
  'subsumes the original enum''s requested and scheduled, since no field work '
  'has happened in either) -> in_progress (field work actively underway, '
  'regardless of session count) -> under_review (observations captured, '
  'internal review and documentation drafting) -> issued (documentation '
  'finalized and released to customer; terminal on the happy path — some '
  'tenant vocabularies call this document a Non-Conformance Report). Backward '
  'transitions are not part of the architectural commitment at this layer.';
comment on column public.inspections.inspection_report is
  'Per-inspection findings as JSONB, because inspection shapes capture '
  'different things: pile depths and soil conditions on a foundation issue, '
  'load calculations and failure mode analysis on a racking failure, a '
  'contracted investigator''s narrative elsewhere. Also the flexibility '
  'mechanism in lieu of custom fields (Audit Topic 11), and the operational '
  'home for claimant attendance if a tenant tracks it (Decision 18.1).';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.inspections enable row level security;

create policy "inspections: members can view their tenant's rows"
  on public.inspections
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: status transitions, report capture, and the
-- canonical FK + snapshot validation all run through Server Actions.

grant all on public.inspections to anon, authenticated, service_role;

-- 020_work_plans.sql
--
-- The Work Plan: the warrantor's INTENT — the document detailing the corrective
-- actions the warrantor or executing subcontractor intends to perform to address
-- a claim. Customer Work Authorization (Decision 11) is the customer-facing
-- COMMITMENT generated from that intent; the two entities are deliberately
-- separate.
--
-- Locked sources:
--   architecture-reference.md "Work Plan Workflow" -> work_plans schema sketch,
--     the eight SOP 6 components, the one-to-many-with-claims shape.
--   Decision 13.1 - two-column shape for execution path + internal team capture.
--   Decision 13.2 - the four execution_path values (v1's Four Work Plan
--     Execution Paths verbatim).
--   Decision 15.1 - the five-value status state machine.
--   Decision 15.2/15.3/15.4/15.5 - the four states deliberately NOT modeled.
--   Decision 16.3 - Parts Claims explicitly out of Work Plan Workflow scope.
--   Decision 14.4 - no FK relationship to Notice of Defect in either direction.
--
-- ON DELETE resolved at build time on all four FKs: RESTRICT.
--
--   Every parent of this table soft-deletes or soft-removes: internal_teams
--   (Decision 13.3's deleted_at), contacts (deleted_at), claims (via the
--   registration/project soft-delete chain), public.users (removed_at). The
--   arch ref defers each clause as "a Phase 3 implementation detail" while
--   stating the restraint plainly: "hard-deletion isn't an ordinary path."
--   RESTRICT is that restraint expressed at the database layer, and matches
--   the 010 (projects->registrations) and 016 (registrations->claims)
--   precedent for parent rows carrying independent meaning.
--
--   On internal_team_id specifically, RESTRICT is the only architecturally
--   available clause, not merely the preferred one. Decision 13.3 requires
--   soft-delete precisely so "historical work_plans retain internal_team_id
--   FK even when teams are retired." CASCADE would delete those work plans —
--   the exact outcome 13.3 exists to prevent. SET NULL would null the column,
--   violating the execution_path CHECK below that requires it NOT NULL when
--   execution_path = 'warrantor_self_performs', leaving the row
--   unrepresentable. Only RESTRICT preserves the locked requirement.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   * No UNIQUE on claim_id. One-to-many is the locked shape: each Work Plan
--     bounds one specific execution event, and a claim may have many across its
--     lifecycle. This deliberately differs from ala_documents and
--     service_reports, which DO carry UNIQUE(claim_id) — those bound the claim
--     as a whole, not an event within it. Same shape as work_authorization_
--     documents and notices_of_defect.
--
--   * No work_authorization_id FK. Per Decision 11 the FK runs the other
--     direction: work_authorization_documents.event_reference_id points here
--     when event_type = 'repair_work'. A reverse FK would duplicate it.
--
--   * No notice_of_defect_id FK. Per Decision 14.4 there is NO FK relationship
--     in either direction. The operational sequence ("a subcontractor accepted
--     a Notice of Defect and then drafted a Work Plan") is read from the claim's
--     history at the application layer, not enforced at the schema level.
--
--   * No service_report_id FK. Service Report references claim_id; the Work
--     Plan transitions to 'completed' based on a service_reports row existing
--     for the claim, not on a direct FK.
--
--   * No customer FK. The customer is the parent project's, reachable via
--     claim_id -> warranty_registration_id -> projects.customer_id. Duplicating
--     it here would create a sync surface.
--
--   * No 'submitted', 'in_execution', 'scheduled', 'revised', or 'resent'
--     status values. Each is explicitly excluded: 15.2 (submitted collapses
--     into the draft -> sent_for_authorization transition — the act of sending
--     IS the transition), 15.3 (in_execution is tracked at the claim status
--     level; modeling it on both would duplicate state), 15.4 (scheduling is
--     likewise claim-level), 15.5 (revised/resent belong to Customer Work
--     Authorization's own state machine — the Work Plan stays in
--     sent_for_authorization across the Work Authorization's revision cycles).
--
--   * No warrantor-contact columns. The workbook's "Warrantor Contact"
--     (Name/Phone/Email) maps to warranty_professional_user_id plus its joined
--     user record — not to redundant columns here.
--
--   * No claim_type gating for Parts Claims. Per Decision 16.3, Parts Claims
--     (claim_type = 'replacement_parts') do not flow through this workflow at
--     all; their fulfillment lifecycle is a separate future Parts Fulfillment
--     architecture. The exclusion is enforced app-layer — no DB constraint
--     couples this table to the parent claim's claim_type.
--
-- APP-LAYER COMPANIONS (not in this migration):
--   * Status transitions run through Server Actions, never direct UPDATE
--     (Decision 15.1). Authority rules per transition are downstream.
--   * The tenant_id match against the parent claim's tenant_id.
--   * The subcontractor name/email/phone snapshot capture at row creation
--     (FK + Snapshot Pattern, single-FK shape).

create table public.work_plans (
  id                            uuid primary key default gen_random_uuid(),
  tenant_id                     uuid not null references public.tenants(id),
                                -- denormalized per Standard RLS Pattern.
  claim_id                      uuid not null
                                  references public.claims(id) on delete restrict,
                                -- NO unique: one-to-many with claim.
  execution_path                text not null,
                                -- v1's Four Work Plan Execution Paths
                                --   (Decision 13.2).
  internal_team_id              uuid
                                  references public.internal_teams(id) on delete restrict,
                                -- populated only on warrantor_self_performs.
  subcontractor_contact_id      uuid
                                  references public.contacts(id) on delete restrict,
                                -- populated only on the two subcontractor paths.
  subcontractor_name_snapshot   text,
  subcontractor_email_snapshot  text,
  subcontractor_phone_snapshot  text,
                                -- FK + Snapshot Pattern, single-FK shape;
                                --   captured at Work Plan creation, never
                                --   re-synced.
  warranty_professional_user_id uuid not null
                                  references public.users(id) on delete restrict,
                                -- the tenant user managing this Work Plan (the
                                --   workbook's "Warrantor Contact"); always
                                --   populated regardless of execution_path.
  work_plan_type                text not null,
                                -- from the Work Plan Data Inputs workbook's
                                --   "Work Plan Type" dropdown.
  status                        text not null default 'draft',
                                -- five-value state machine (Decision 15.1).
  planned_start_at              timestamptz not null,
                                -- SOP 6 component 1: Planned Arrival Date/Time.
  planned_end_at                timestamptz not null,
                                -- SOP 6 component 6: Estimated Duration is the
                                --   start/end pair, mirroring Customer Work
                                --   Authorization (Decision 11) for clean field
                                --   replication at Work Authorization generation.
                                --   The workbook's "Number of Days to Complete"
                                --   is derivable from the difference.
  crew_size                     integer not null,
                                -- SOP 6 component 2.
  corrective_actions            jsonb not null,
                                -- SOP 6 component 3; ProseMirror-compatible
                                --   JSON per Decision 4.
  required_materials_equipment  jsonb,
                                -- SOP 6 component 4; the workbook's "Special
                                --   Equipment Needed" maps here. Nullable: not
                                --   every Work Plan requires special materials.
  repair_scope_approach         jsonb not null,
                                -- SOP 6 component 5; the workbook's "Service
                                --   Scope of Work" maps here.
  safety_considerations         jsonb,
                                -- SOP 6 component 7. Nullable: tenants may rely
                                --   on the Acknowledgment Gate Pattern's Site
                                --   Readiness & Safety Requirements gate for
                                --   much of this content.
  site_access_coordination      jsonb,
                                -- SOP 6 component 8. Nullable: Customer Work
                                --   Authorization captures the structured site
                                --   access fields directly; this is the
                                --   warrantor's planning notes preceding it.
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),

  constraint work_plans_execution_path_check check (
    execution_path in (
      'warrantor_self_performs',
      'scope_owned_subcontractor',
      'outsourced_subcontractor',
      'customer_self_services'
    )
  ),

  constraint work_plans_work_plan_type_check check (
    work_plan_type in ('repair', 'inspection', 'both')
  ),

  constraint work_plans_status_check check (
    status in (
      'draft',
      'sent_for_authorization',
      'authorized',
      'completed',
      'cancelled'
    )
  ),

  -- Decision 13.1: internal_team_id is non-null exactly when execution_path
  -- = 'warrantor_self_performs', null otherwise.
  constraint work_plans_internal_team_path_check check (
    (execution_path = 'warrantor_self_performs' and internal_team_id is not null)
    or
    (execution_path <> 'warrantor_self_performs' and internal_team_id is null)
  ),

  -- Decision 13.1: subcontractor_contact_id is non-null exactly when
  -- execution_path is one of the two subcontractor paths, null otherwise.
  -- On customer_self_services both FKs are null: the customer-as-executor is
  -- captured through the claim's parent project's customer_id, and no
  -- Work-Plan-level FK is needed.
  constraint work_plans_subcontractor_path_check check (
    (execution_path in ('scope_owned_subcontractor', 'outsourced_subcontractor')
      and subcontractor_contact_id is not null)
    or
    (execution_path not in ('scope_owned_subcontractor', 'outsourced_subcontractor')
      and subcontractor_contact_id is null)
  )
);

create index work_plans_tenant_id_idx
  on public.work_plans (tenant_id);

create index work_plans_claim_id_idx
  on public.work_plans (claim_id);

comment on table public.work_plans is
  'The warrantor''s INTENT: the planned corrective actions for a claim '
  '(Decisions 13/15/16; SOP 6). Customer Work Authorization (Decision 11) is '
  'the customer-facing COMMITMENT generated from this intent — the two entities '
  'are deliberately separate. One-to-many with claims: each Work Plan bounds one '
  'execution event, and a claim may have many across its lifecycle. Parts Claims '
  '(claim_type = replacement_parts) do NOT flow through this workflow per '
  'Decision 16.3; their fulfillment is a separate future architecture.';

comment on column public.work_plans.execution_path is
  'v1''s Four Work Plan Execution Paths, platform-locked (Decision 13.2). '
  'warrantor_self_performs: an internal team executes. '
  'scope_owned_subcontractor: the original installer with an active warranty '
  'obligation executes (v1 Path 2A). outsourced_subcontractor: a third party '
  'procured via RFQ executes (v1 Path 2B). customer_self_services: the customer '
  'executes with warrantor reimbursement (v1 Path 3). Extensible via migration '
  'if a fifth path surfaces operationally.';

comment on column public.work_plans.internal_team_id is
  'The specific internal team executing, when execution_path = '
  'warrantor_self_performs (Decision 13.1). Team labels are tenant data, NOT '
  'platform enum values (13.4). ON DELETE RESTRICT is the only architecturally '
  'available clause: Decision 13.3 requires soft-delete precisely so historical '
  'work_plans retain this FK when teams retire — CASCADE would destroy those '
  'rows, and SET NULL would violate work_plans_internal_team_path_check.';

comment on column public.work_plans.subcontractor_contact_id is
  'The executing subcontractor, when execution_path is scope_owned_subcontractor '
  'or outsourced_subcontractor (Decision 13.1). FK + Snapshot Pattern, single-FK '
  'shape. Single-FK rather than the dual-FK shape Service Report uses for its '
  'submitter: execution_path already disambiguates who executes, so the assignee '
  'capture splits cleanly by path and needs no column accepting either a contact '
  'or a user.';

comment on column public.work_plans.warranty_professional_user_id is
  'The tenant user managing this Work Plan from the warrantor''s side — the '
  'workbook''s "Warrantor Contact". Always populated regardless of '
  'execution_path. The workbook''s Name/Phone/Email fields resolve through this '
  'FK''s joined user record rather than as redundant columns.';

comment on column public.work_plans.work_plan_type is
  'Whether this Work Plan covers repair work, inspection work, or both. From the '
  'Work Plan Data Inputs workbook''s "Work Plan Type" dropdown. The relationship '
  'between work_plan_type = both and Customer Work Authorization''s event_type '
  '(one bundled document vs two separate documents) is a downstream operational '
  'question, not locked here.';

comment on column public.work_plans.status is
  'Five-value state machine (Decision 15.1): draft (authored, customer cannot '
  'see it) -> sent_for_authorization (bundled into a Customer Work Authorization '
  'and sent; stays here across the Work Authorization''s own revision cycles per '
  '15.5) -> authorized (a Work Authorization for this plan was customer-approved) '
  '-> completed (a Service Report exists for the claim). cancelled is terminal '
  'for abandoned plans. Transitions run through Server Actions, never direct '
  'UPDATE. Deliberately absent: submitted (15.2), in_execution (15.3), a '
  'scheduling state (15.4), revised/resent (15.5).';

comment on column public.work_plans.planned_end_at is
  'SOP 6 component 6 (Estimated Duration) is captured as the planned_start_at / '
  'planned_end_at pair rather than a duration scalar, mirroring Customer Work '
  'Authorization (Decision 11) so fields replicate cleanly when a Work '
  'Authorization is generated from this plan. The workbook''s "Number of Days to '
  'Complete" is derivable from the difference.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.work_plans enable row level security;

create policy "work_plans: members can view their tenant's rows"
  on public.work_plans
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: status transitions and field edits run through
-- Server Actions, per Decision 15.1.

grant all on public.work_plans to anon, authenticated, service_role;

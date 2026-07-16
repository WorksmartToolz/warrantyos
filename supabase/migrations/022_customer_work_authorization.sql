-- 022_customer_work_authorization.sql
--
-- The Customer Work Authorization: the customer-facing COMMITMENT. The document
-- a warrantor sends to a customer to obtain explicit approval before warranty
-- personnel -- or contracted third parties under the warrantor's coordination --
-- perform any on-site activity at the customer's site.
--
-- Work Plan (020) is the warrantor's INTENT; this is what the customer agreed to
-- permit. The two entities are deliberately separate.
--
-- UNIVERSAL BLOCKING GATE: no on-site activity of any kind proceeds without an
-- approved Work Authorization for that specific event. SOP 1 names the
-- inspection case ("the warranty professional must request a customer Work
-- Authorization before the joint/exploratory inspection can commence"); the
-- architecture extends the gate to ALL on-site activity intentionally. SOP 1
-- captured the canonical case; the platform commits to the pattern. Enforcement
-- is a Server Action precondition check, not a DB constraint.
--
-- Three tables, parent-child-revisions:
--   work_authorization_templates  -- tenant-defined reusable configuration
--   work_authorization_documents  -- one specific authorization event, frozen
--                                    template snapshot + the customer's response
--   work_authorization_revisions  -- full history of warrantor edits to one doc
--
-- Locked sources:
--   architecture-reference.md "Customer Work Authorization" -> all three schema
--     sketches, the seven-value status state machine, the revise-and-resend
--     mechanic, the one-to-many-with-claims shape, the deliberate-omissions list.
--   Decision 11 - the locked architectural specification, including the
--     two-column event shape (event_type + event_reference_id) and the five
--     locked commitments.
--   Decision 11.2 - universal blocking-gate behavior.
--   Decision 12 - Acknowledgment Gate Pattern; gate_purpose =
--     'work_authorization' guards this document's tokenized form. The gate is an
--     interstitial on THIS document's customer_token -- there is no second token.
--   Decision 20.6 / 20.7 / Decision 28 - O&M Provider approval is BLOCKED at v1
--     without a signed om_authorization_documents row (event_type =
--     'work_authorization'). App-layer check, not a DB constraint.
--
-- ONE-TO-MANY WITH CLAIMS -- no UNIQUE on claim_id. Each Work Authorization
-- authorizes ONE specific on-site event: an inspection at one date/time, a
-- repair-work execution at another, a follow-up visit later. A claim with three
-- events has three documents. This is the same shape as work_plans (020) and
-- notices_of_defect, and the deliberate contrast against ala_documents and
-- service_reports, which DO carry UNIQUE(claim_id) because those bound the claim
-- as a whole. The scope distinction is the reason: ALA authorizes financial
-- liability for the claim's investigation (once per Indistinct outcome); Work
-- Authorization authorizes physical site presence for a bounded event (which
-- recurs).
--
-- event_reference_id: SINGLE NULLABLE COLUMN, NO FK -- resolved at build time.
--
--   Decision 11.b left the polymorphic shape open, naming three candidates: a
--   single nullable column with app-layer dispatch by event_type; separate
--   event-type-specific FK columns with a CHECK; or a junction table.
--
--   Resolved as the single nullable column, because it is the only candidate
--   that honors the locked two-column shape Decision 11 commits to by name
--   (event_type + event_reference_id):
--     - The junction table is doubly excluded: it eliminates the locked
--       event_reference_id column, and it supports many-to-many, which this
--       section's own "No multi-event-per-document" omission forbids.
--     - Separate typed FK columns (inspection_id, work_plan_id, + CHECK) would
--       give real referential integrity -- and 017 (custom_field_values) is a
--       real precedent for preferring typed FKs over a polymorphic key per
--       Decision 3. But that shape DELETES event_reference_id, the column
--       Decision 11 locks. 017's precedent does not transfer: Decision 3 chose
--       typed FKs where no locked column name was at stake. Here one is.
--     - The single nullable column preserves the locked text verbatim.
--
--   In-repo precedent for exactly this shape: clock_events (013) carries NO FK
--   on entity_id -- it is a polymorphic reference resolved by entity_type. Same
--   problem, same answer, already built.
--
--   The arch ref anticipates the consequence and accepts it: "Without a
--   database-enforced FK (per the polymorphic shape question), this becomes an
--   application-layer integrity concern. The application must check for active
--   Work Authorizations before allowing the referenced event entity to be
--   deleted." That check, and dispatch by event_type, are app-layer.
--
-- ON DELETE resolved at build time:
--   documents.claim_id                    -> RESTRICT. The arch ref names the
--     restraint ("RESTRICT with soft-delete as the cleanup path") and defers
--     only the clause. Matches 010/016/020/021.
--   documents.template_id                 -> RESTRICT. Templates soft-delete and
--     their documents must stay readable; CASCADE would be exactly the
--     cascade-destruction of auditable data the architecture names as the
--     outcome to avoid. Directly parallel to 017's RESTRICT on definition_id --
--     same reasoning, same shape.
--   documents.event_reference_id          -> no clause. There is no FK to carry
--     one (see above). App-layer integrity per the arch ref.
--   revisions.work_authorization_document_id -> CASCADE. A revision is a
--     dependent attribute of its parent document, not an independent record --
--     017's entity-FK CASCADE reasoning applies exactly. Deliberately differs
--     from the RESTRICTs above: different relationship, different answer.
--   revisions.revised_by_user_id          -> RESTRICT. Tenant users soft-remove
--     (removed_at); matches 020's warranty_professional_user_id.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   - No UNIQUE on documents.claim_id. One-to-many is locked. See above.
--   - No FK on event_reference_id. Locked-shape-preserving; see above.
--   - No partial UNIQUE index on (tenant_id) WHERE is_default. The arch ref
--     offers partial-UNIQUE or app-layer and picks neither; 17.A.6 caps v1 DB
--     enforcement, and every prior table places this class of invariant
--     app-layer. Parallel to ALA's and Acknowledgment Gate's is_default flags,
--     which face the identical open question.
--   - No customer FK to the Unified Contacts Directory. Deliberate per the arch
--     ref: the customer-facing identity capture is signer_name_typed plus
--     request_completed_by_name as direct text. The customer-of-record is
--     reachable through claim_id -> warranty_registration_id ->
--     projects.customer_id; the on-site representative who responds is often a
--     different person and varies per event.
--   - No O&M provider FK. Direct field capture (om_provider_company through
--     om_contact_email) is Decision 11's locked schema, paralleling Claim
--     Intake. Any future move to FK + Snapshot warrants its own decision.
--   - No work_plan_id FK. When event_type = 'repair_work', event_reference_id
--     IS the work plan reference. A separate column would duplicate it.
--   - No second token for the Acknowledgment Gate. The gate is an interstitial
--     on customer_token, not its own tokenized interaction (Decision 12).
--   - No multi-event-per-document. One document covers exactly one
--     (event_type, event_reference_id) pair.
--   - No custom field involvement. Work Authorization is outside Decision 3's
--     Phase 1 scope; tenant-configurable variation lives in the template's
--     warrantor_field_config / customer_field_config JSONB.
--   - No DB CHECK coupling customer_decision = 'denied' to denial_explanation,
--     or approval to (signer_name_typed + authorization_acknowledged). The arch
--     ref marks these app-layer ("enforced app-layer"); 17.A.6 caps v1 DB
--     enforcement. Same restraint as 016's emergency_stabilized_at.
--   - No DB CHECK coupling special_access_details to special_access_required,
--     or gate_code_details to gate_code_needed. Conditional per the arch ref's
--     prose; app-layer, same reasoning.
--   - No status CHECK coupling to customer_decision. The seven-value status
--     machine and the two-value decision are separate columns; transitions are
--     governed by Server Actions, not by direct UPDATE.
--   - No clock_events row created here. The
--     work_authorization_response_overdue event is inserted by the Server Action
--     that sends or resends the document, per Decision 9's convention that
--     clock_events is for future-firing events scheduled by the action that
--     causes them. clock_events (013) already carries the event_type value.
--   - No created_at/updated_at on revisions. The locked sketch carries only
--     revised_at. Built verbatim -- an applying table does not vary the locked
--     column set.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints):
--   - tenant_id matches the referenced claim's tenant_id (documents) and the
--     parent document's tenant_id (revisions).
--   - event_reference_id resolves to the right table per event_type, and the
--     referenced row exists.
--   - At most one is_default = true template per tenant.
--   - denial_explanation required when customer_decision = 'denied'.
--   - signer_name_typed + authorization_acknowledged = true required when
--     customer_decision = 'approved'.
--   - The customer's response satisfies the template's required-field set.
--   - O&M Provider actors are blocked without a signed
--     om_authorization_documents row (Decision 28).
--   - The universal blocking gate: no on-site activity without an approved
--     document for that specific event.

-- ---------------------------------------------------------------------------
-- work_authorization_templates
-- ---------------------------------------------------------------------------
create table public.work_authorization_templates (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references public.tenants(id),
                          -- denormalized per Standard RLS Pattern.
  name                    text not null,
  warrantor_field_config  jsonb not null,
                          -- configuration of warrantor-completed fields shown
                          --   to the customer as read-only context (requestor
                          --   info, planned dates, crew size, SOW activity).
  customer_field_config   jsonb not null,
                          -- configuration of customer-entered fields (O&M
                          --   contact info, site access, gate codes, special
                          --   access requirements). Determines which are
                          --   required vs optional and any tenant labeling.
  legal_language          jsonb not null,
                          -- ProseMirror-compatible JSON per Decision 4; the
                          --   tenant-defined legal/operational language.
  is_default              boolean not null default false,
                          -- at most one default per tenant; app-layer.
  deleted_at              timestamptz,
                          -- soft-delete REQUIRED: a template retired today may
                          --   have generated documents last year, whose
                          --   template_snapshot must stay readable while
                          --   template_id still resolves for reporting.
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index work_authorization_templates_tenant_id_idx
  on public.work_authorization_templates (tenant_id);
comment on table public.work_authorization_templates is
  'Tenant-defined reusable configuration for Customer Work Authorization '
  '(Decision 11). Same templates-and-documents shape as the ALA System and the '
  'Acknowledgment Gate Pattern. Soft-delete is required, not optional: retired '
  'templates must remain queryable because documents generated from them '
  'reference template_id for reporting.';
comment on column public.work_authorization_templates.is_default is
  'At most one is_default = true per tenant is the architectural intent. '
  'Enforcement is app-layer: the arch ref offers partial-UNIQUE or app-layer '
  'and picks neither, and Decision 17.A.6 caps v1 DB enforcement. Parallel to '
  'ALA''s and Acknowledgment Gate''s is_default flags.';

-- ---------------------------------------------------------------------------
-- work_authorization_documents
-- ---------------------------------------------------------------------------
create table public.work_authorization_documents (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references public.tenants(id),
                              -- denormalized per Standard RLS Pattern.
  claim_id                    uuid not null
                                references public.claims(id) on delete restrict,
                              -- NO unique: one-to-many with claim. Each document
                              --   authorizes one bounded on-site event.
  template_id                 uuid not null
                                references public.work_authorization_templates(id)
                                on delete restrict,
  template_snapshot           jsonb not null,
                              -- template content frozen at document generation.
                              --   The customer agreed to exactly this, not to
                              --   whatever the template says today.
  event_type                  text not null,
                              -- what on-site activity this authorizes.
  event_reference_id          uuid,
                              -- polymorphic reference to the event entity,
                              --   resolved app-layer by event_type. NO FK --
                              --   see the header for why this preserves
                              --   Decision 11's locked two-column shape.
                              --   Precedent: clock_events.entity_id (013).
  status                      text not null default 'draft',
                              -- seven-value state machine; transitions run
                              --   through Server Actions, never direct UPDATE.
  expected_response_date      date,
                              -- warrantor-set; drives the
                              --   work_authorization_response_overdue clock
                              --   event's fires_at.

  -- Warrantor-completed fields. Entered by the warranty team at document
  -- creation; read-only context to the customer.
  requestor_name              text not null,
  requestor_company           text not null,
  requestor_phone             text,
  requestor_email             text not null,
  planned_start_at            timestamptz not null,
  planned_end_at              timestamptz not null,
                              -- the window the warrantor intends to be on-site;
                              --   mirrors work_plans' start/end pair for clean
                              --   field replication at generation.
  crew_size                   integer not null,
  sow_activities              jsonb not null,
                              -- ProseMirror-compatible JSON; the planned Scope
                              --   of Work. Composed from the Work Plan's
                              --   corrective_actions + repair_scope_approach at
                              --   generation time (composition mechanics are a
                              --   flagged Phase 3 implementation detail).

  -- Customer-entered fields. Filled by the customer when responding.
  om_provider_company         text,
  om_contact_name             text,
  om_contact_phone            text,
  om_contact_email            text,
                              -- direct field capture, NOT FK + Snapshot --
                              --   Decision 11's locked schema, paralleling
                              --   Claim Intake.
  site_emergency_address      jsonb,
                              -- structured address; shape consistent with the
                              --   project's site_address pattern.
  site_accessibility_date     date,
  operating_hours             text,
  special_access_required     boolean,
  special_access_details      jsonb,
                              -- conditional on special_access_required = true;
                              --   app-layer.
  gate_code_needed            boolean,
  gate_code_details           jsonb,
                              -- conditional on gate_code_needed = true;
                              --   app-layer.
  customer_comments           jsonb,
                              -- optional; safety orientations, check-in/
                              --   check-out procedures, site observations.

  -- Customer response.
  customer_decision           text,
                              -- null until the customer responds.
  denial_explanation          jsonb,
                              -- required when customer_decision = 'denied';
                              --   app-layer.
  signer_name_typed           text,
  authorization_acknowledged  boolean,
                              -- the signature artifact: typed name + "I
                              --   authorize" checkbox = true constitutes legal
                              --   approval for the on-site event.
  request_completed_by_name   text,

  -- Stateless Tokenized Interaction Pattern: token on this row, not in
  -- invitations ("shape to copy, not shared store"). Fifth canonical use.
  customer_token              text,
  customer_token_expires_at   timestamptz,

  requested_at                timestamptz not null default now(),
  responded_at                timestamptz,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint work_authorization_documents_event_type_check check (
    event_type in ('inspection', 'repair_work', 'site_visit')
  ),
  constraint work_authorization_documents_status_check check (
    status in (
      'draft',
      'sent',
      'approved',
      'denied',
      'revised',
      'resent',
      'withdrawn'
    )
  ),
  constraint work_authorization_documents_customer_decision_check check (
    customer_decision in ('approved', 'denied')
  )
);
create index work_authorization_documents_tenant_id_idx
  on public.work_authorization_documents (tenant_id);
create index work_authorization_documents_claim_id_idx
  on public.work_authorization_documents (claim_id);
create index work_authorization_documents_template_id_idx
  on public.work_authorization_documents (template_id);
create index work_authorization_documents_event_reference_idx
  on public.work_authorization_documents (event_type, event_reference_id);
  -- the polymorphic lookup path: "which authorizations reference this event?"
  -- Mirrors clock_events_entity_idx (entity_type, entity_id) from 013.
comment on table public.work_authorization_documents is
  'One customer authorization for one bounded on-site event (Decision 11). The '
  'customer-facing COMMITMENT generated from a Work Plan''s INTENT. Universal '
  'blocking gate: no on-site activity proceeds without an approved document for '
  'that specific event -- broader than SOP 1''s inspection-only language, which '
  'the architecture treats as the canonical instance, not the limit. '
  'One-to-many with claims: each document bounds one event, and a claim may '
  'have many across its lifecycle. Contrast ala_documents and service_reports, '
  'which are UNIQUE per claim because they bound the claim as a whole.';
comment on column public.work_authorization_documents.event_reference_id is
  'Polymorphic reference to the authorized event: inspections.id when '
  'event_type = ''inspection'', work_plans.id when ''repair_work''. NO database '
  'FK -- Decision 11 locks the two-column (event_type + event_reference_id) '
  'shape, and typed per-event FK columns would delete this locked column. '
  'Precedent: clock_events.entity_id. Dispatch and referential integrity are '
  'app-layer; the application must check for active authorizations before '
  'allowing a referenced event entity to be deleted.';
comment on column public.work_authorization_documents.status is
  'Seven-value state machine. draft (warrantor authoring; customer cannot see '
  'it) -> sent (tokenized link emailed) -> approved (terminal happy path; '
  'on-site activity authorized) | denied (triggers revise-and-resend) -> '
  'revised (warrantor edited the denied document) -> resent (customer decides '
  'again, seeing the full revision history) | withdrawn (request scrapped '
  'entirely; fallback for denials not recoverable through revision). '
  'Transitions run through Server Actions. Authority rules per transition are '
  'operational and deferred.';
comment on column public.work_authorization_documents.authorization_acknowledged is
  'The "I authorize" checkbox. Together with signer_name_typed this is the '
  'signature artifact constituting legal approval. Deliberately distinct from '
  'ALA''s mechanism (Decision 19''s Accept/Decline + atomic signature + recant '
  'window): ALA''s assumption of financial liability warrants that ceremony, '
  'while authorizing on-site activity fits typed-name-plus-checkbox atomicity. '
  'Neither pre-decides the other.';
comment on column public.work_authorization_documents.customer_token is
  'Fifth canonical use of the Stateless Tokenized Interaction Pattern, after '
  'claim intake, registration assignee submission, supply-only delivery '
  'reporting, and service report customer review. Stored on this row per the '
  'pattern''s "shape to copy, not shared store" rule. When a tenant configures '
  'an Acknowledgment Gate for gate_purpose = ''work_authorization'' (Decision '
  '12), that gate is an interstitial on THIS token -- there is no second token.';

-- ---------------------------------------------------------------------------
-- work_authorization_revisions
-- ---------------------------------------------------------------------------
create table public.work_authorization_revisions (
  id                              uuid primary key default gen_random_uuid(),
  tenant_id                       uuid not null references public.tenants(id),
                                  -- denormalized per Standard RLS Pattern.
  work_authorization_document_id  uuid not null
                                    references public.work_authorization_documents(id)
                                    on delete cascade,
                                  -- a revision is a dependent attribute of its
                                  --   document, not an independent record.
  revised_by_user_id              uuid not null
                                    references public.users(id) on delete restrict,
                                  -- the warrantor user who made the revision.
  revision_reason                 jsonb not null,
                                  -- ProseMirror-compatible JSON; typically the
                                  --   customer's denial_explanation or a
                                  --   paraphrase of it.
  field_changes                   jsonb not null,
                                  -- structured record of what changed
                                  --   (before/after pairs). The exact JSONB
                                  --   shape -- structured diff, flat key-value
                                  --   map, full-document snapshot -- is a
                                  --   flagged Phase 3 implementation detail;
                                  --   the column and its NOT NULL are locked.
  revised_at                      timestamptz not null default now()
);
create index work_authorization_revisions_tenant_id_idx
  on public.work_authorization_revisions (tenant_id);
create index work_authorization_revisions_document_id_idx
  on public.work_authorization_revisions (work_authorization_document_id);
comment on table public.work_authorization_revisions is
  'Full history of warrantor edits to one Work Authorization document '
  '(Decision 11). Revise-and-resend is the PRIMARY recovery path for a denied '
  'authorization -- not withdraw-and-recreate. The document''s id, claim_id, '
  'and event_reference_id stay the same; the same request evolves through '
  'revisions until approved or withdrawn. The customer sees the full revision '
  'history transparently on resend (Option A in Decision 11: transparency for '
  'trust-building and audit-defensibility; burying the history was rejected). '
  'Built verbatim to the locked sketch: revised_at only, no created_at/'
  'updated_at, no soft-delete.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step) -- all three tables
-- ---------------------------------------------------------------------------
alter table public.work_authorization_templates enable row level security;

create policy "work_authorization_templates: tenant read"
  on public.work_authorization_templates
  for select
  using (tenant_id = public.get_user_tenant_id());

alter table public.work_authorization_documents enable row level security;

create policy "work_authorization_documents: tenant read"
  on public.work_authorization_documents
  for select
  using (tenant_id = public.get_user_tenant_id());

alter table public.work_authorization_revisions enable row level security;

create policy "work_authorization_revisions: tenant read"
  on public.work_authorization_revisions
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: status transitions, the customer's tokenized
-- response, revision capture, and the universal blocking-gate precondition all
-- run through Server Actions.

grant all on public.work_authorization_templates to anon, authenticated, service_role;
grant all on public.work_authorization_documents to anon, authenticated, service_role;
grant all on public.work_authorization_revisions to anon, authenticated, service_role;
